// ⌘Tab de macOS Catalina para Cinnamon.
//
// Reemplaza el selector de Cinnamon (switch-windows y switch-group) mientras
// la extensión esté encendida; al apagarla, los atajos vuelven al de Cinnamon
// (Main.wm._startAppSwitcher). No toca archivos del sistema ni gsettings.
//
//   ⌘Tab / ⇧⌘Tab   una entrada por app, en orden de uso; al soltar ⌘ la app
//                  pasa al frente con todas sus ventanas.
//   ⌘Tab rápido    cambia a la app anterior sin enseñar el panel.
//   con ⌘ abajo    Q cierra la app elegida, H la oculta, ← → mueven, Esc sale;
//                  el mouse elige al pasar y el clic activa.
//   ⌘` / ⇧⌘`       rota entre las ventanas de la app activa, sin panel.
//
// keyd: con ⌘ sostenido, ⌘Q sale como Ctrl+Q y ⌘← ⌘→ como Inicio/Fin, y para
// mandarlas keyd suelta Super un instante. Por eso soltar ⌘ no activa enseguida:
// se espera SUELTA_MS y, si Super volvió, el panel sigue abierto.

const Clutter = imports.gi.Clutter;
const St = imports.gi.St;
const Meta = imports.gi.Meta;
const Cinnamon = imports.gi.Cinnamon;
const GLib = imports.gi.GLib;
const Pango = imports.gi.Pango;
const Main = imports.ui.main;

const ICONO = 128;          // tamaño del ícono en el panel (se encoge si no caben)
const AIRE_ICONO = 8;       // aire del resaltado alrededor del ícono
const SUELTA_MS = 40;       // espera antes de tomar ⌘ como suelta (keyd)
const HOVER_MS = 300;       // el mouse no elige hasta pasado esto (panel debajo del puntero)

const ATAJOS = ['switch-windows', 'switch-windows-backward', 'switch-group', 'switch-group-backward'];

let selector = null;
// Ventanas que ocultamos con H: al volver a la app se restauran todas, como
// en la Mac; una minimizada a mano no se toca.
let ocultas = new WeakSet();

function appDe(w) {
  let app = Cinnamon.WindowTracker.get_default().get_window_app(w);
  return app;
}

function claveDe(w) {
  let app = appDe(w);
  return app ? app.get_id() : 'wm:' + (w.get_wm_class() || w.get_id());
}

// Ventanas normales de todos los escritorios, la usada más recientemente
// primero (la lista de Mutter ya viene en ese orden).
function ventanasMRU() {
  return global.display.get_tab_list(Meta.TabList.NORMAL_ALL, null)
    .filter(w => !w.is_skip_taskbar());
}

// Una entrada por app, en el orden de su ventana más reciente.
function appsMRU() {
  let porClave = new Map();
  for (let w of ventanasMRU()) {
    let k = claveDe(w);
    if (!porClave.has(k)) porClave.set(k, { clave: k, app: appDe(w), ventanas: [] });
    porClave.get(k).ventanas.push(w);
  }
  return [...porClave.values()];
}

function nombreDe(e) {
  if (e.app) return e.app.get_name();
  return e.ventanas[0].get_wm_class() || e.ventanas[0].get_title() || '';
}

// Trae la app al frente con todas sus ventanas, en su orden: la más vieja
// primero y la más reciente encima.
function activarApp(e) {
  let ahora = global.get_current_time();
  let visibles = e.ventanas.filter(w => !w.minimized);
  let restaurar = e.ventanas.filter(w => w.minimized && ocultas.has(w));
  if (!visibles.length && !restaurar.length && e.ventanas.length)
    restaurar = [e.ventanas[0]];   // todas minimizadas a mano: la más reciente
  for (let w of restaurar) { ocultas.delete(w); w.unminimize(); }
  let traer = e.ventanas.filter(w => !w.minimized);
  for (let i = traer.length - 1; i > 0; i--) traer[i].raise();
  if (traer.length) Main.activateWindow(traer[0], ahora);
}

function ocultarApp(e) {
  for (let w of e.ventanas) if (!w.minimized) { ocultas.add(w); w.minimize(); }
}

// Como «Quit» en la Mac: se le pide a cada ventana que cierre, así la app
// puede preguntar si guarda. Nunca se mata el proceso.
function cerrarApp(e) {
  let ahora = global.get_current_time();
  for (let w of e.ventanas) w.delete(ahora);
}

class Selector {
  constructor(binding) {
    this._apps = appsMRU();
    this._mask = primaryModifier(binding.get_mask());
    this._indice = this._apps.length > 1 ? 1 : 0;
    this._mostrado = false;
    this._mouseListo = false;
    this._timers = new Set();
    this._celdas = [];
    // Una app que se cierra (Q, o por su cuenta) sale del panel al irse su
    // última ventana; la selección pasa a la siguiente, como en la Mac.
    this._idDestroy = global.window_manager.connect('destroy', () => {
      if (!this._recargaPendiente) {
        this._recargaPendiente = true;
        this._despues(60, () => { this._recargaPendiente = false; this._recargar(); });
      }
    });

    this.actor = new St.Widget({ reactive: true, x: 0, y: 0,
                                 width: global.screen_width, height: global.screen_height });
    Main.uiGroup.add_child(this.actor);
  }

  arrancar(binding) {
    if (!this._apps.length) { this.destruir(); return; }
    let modal = Main.pushModal(this.actor);
    if (!modal)
      modal = Main.pushModal(this.actor, global.get_current_time(), Meta.ModalOptions.POINTER_ALREADY_GRABBED);
    if (!modal) { this._activarYCerrar(); return; }
    this._modal = true;

    this.actor.connect('key-press-event', (a, ev) => this._tecla(ev));
    this.actor.connect('key-release-event', () => this._soltada());
    this.actor.connect('button-press-event', () => { this.destruir(); return Clutter.EVENT_STOP; });

    // Si ⌘ ya se soltó antes de tomar el teclado, es un ⌘Tab rápido.
    if (!this._modificadorAbajo()) { this._activarYCerrar(); return; }
    if (binding.get_name().endsWith('-backward')) this._indice = this._apps.length - 1;

    let delay = global.settings.get_int('alttab-switcher-delay');
    this._despues(delay, () => this._mostrar());
  }

  _despues(ms, fn) {
    let id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => { this._timers.delete(id); fn(); return GLib.SOURCE_REMOVE; });
    this._timers.add(id);
    return id;
  }

  _modificadorAbajo() {
    let [x, y, mods] = global.get_pointer();
    return (mods & this._mask) !== 0;
  }

  _mostrar() {
    if (this._mostrado || this._destruido) return;
    this._mostrado = true;
    let mon = Main.layoutManager.primaryMonitor;
    let n = this._apps.length;
    let caja = new St.BoxLayout({ style_class: 'cmdtab-panel', vertical: false });
    // Si no caben a 128, se encogen como en la Mac.
    let celdaMax = Math.floor((mon.width * 0.92 - 24) / n);
    let icono = Math.max(32, Math.min(ICONO, celdaMax - 2 * AIRE_ICONO));

    this._apps.forEach((e, i) => {
      let celda = new St.BoxLayout({ vertical: true, reactive: true, track_hover: true,
                                     style_class: 'cmdtab-celda' });
      let marco = new St.Bin({ style_class: 'cmdtab-marco' });
      let tex = e.app ? e.app.create_icon_texture(icono)
                      : new St.Icon({ icon_name: 'application-x-executable', icon_size: icono });
      marco.set_child(tex);
      let nombre = new St.Label({ text: nombreDe(e), style_class: 'cmdtab-nombre' });
      nombre.clutter_text.ellipsize = Pango.EllipsizeMode.END;
      nombre.set_width(icono + 2 * AIRE_ICONO + 40);
      nombre.x_align = Clutter.ActorAlign.CENTER;
      celda.add_child(marco);
      celda.add_child(nombre);
      celda.connect('enter-event', () => { if (this._mouseListo) this._elegir(i); });
      // El clic se atiende al bajar el botón: si no, sube al fondo, que cierra
      // el panel, y la celda nunca ve el botón soltarse.
      celda.connect('button-press-event', () => { this._elegir(i); this._activarYCerrar(); return Clutter.EVENT_STOP; });
      caja.add_child(celda);
      this._celdas.push({ marco, nombre });
    });

    this._panel = caja;
    this.actor.add_child(caja);
    let [, ancho] = caja.get_preferred_width(-1);
    let [, alto] = caja.get_preferred_height(ancho);
    caja.set_position(Math.round(mon.x + (mon.width - ancho) / 2), Math.round(mon.y + (mon.height - alto) / 2));
    this._pintar();
    this._despues(HOVER_MS, () => { this._mouseListo = true; });
  }

  _pintar() {
    this._celdas.forEach((c, i) => {
      let sel = i === this._indice;
      if (sel) c.marco.add_style_pseudo_class('elegido'); else c.marco.remove_style_pseudo_class('elegido');
      c.nombre.opacity = sel ? 255 : 0;
    });
  }

  _elegir(i) {
    if (!this._apps.length) return;
    this._indice = (i + this._apps.length) % this._apps.length;
    if (this._mostrado) this._pintar();
  }

  _tecla(ev) {
    let sym = ev.get_key_symbol();
    let mods = Cinnamon.get_event_state(ev);
    let accion = global.display.get_keybinding_action(ev.get_key_code(), mods);
    this._mouseListo = false;
    this._despues(HOVER_MS, () => { this._mouseListo = true; });

    switch (sym) {
      case Clutter.KEY_Escape: this.destruir(); return Clutter.EVENT_STOP;
      case Clutter.KEY_Return: case Clutter.KEY_KP_Enter: this._activarYCerrar(); return Clutter.EVENT_STOP;
      // keyd manda ⌘← ⌘→ como Inicio y Fin.
      case Clutter.KEY_Right: case Clutter.KEY_End: this._elegir(this._indice + 1); return Clutter.EVENT_STOP;
      case Clutter.KEY_Left: case Clutter.KEY_Home: this._elegir(this._indice - 1); return Clutter.EVENT_STOP;
      // keyd manda ⌘Q como Ctrl+Q: se toma la q con cualquier modificador.
      case Clutter.KEY_q: case Clutter.KEY_Q: this._sobreElegida(cerrarApp); return Clutter.EVENT_STOP;
      case Clutter.KEY_h: case Clutter.KEY_H: this._sobreElegida(ocultarApp); return Clutter.EVENT_STOP;
      // ⇧⌘Tab llega como ISO_Left_Tab y no siempre se resuelve como atajo.
      case Clutter.KEY_ISO_Left_Tab: this._elegir(this._indice - 1); return Clutter.EVENT_STOP;
      case Clutter.KEY_Tab:
        this._elegir(this._indice + ((mods & Clutter.ModifierType.SHIFT_MASK) ? -1 : 1));
        return Clutter.EVENT_STOP;
    }
    switch (accion) {
      case Meta.KeyBindingAction.SWITCH_WINDOWS:
      case Meta.KeyBindingAction.SWITCH_GROUP:
        this._elegir(this._indice + ((mods & Clutter.ModifierType.SHIFT_MASK) ? -1 : 1));
        return Clutter.EVENT_STOP;
      case Meta.KeyBindingAction.SWITCH_WINDOWS_BACKWARD:
      case Meta.KeyBindingAction.SWITCH_GROUP_BACKWARD:
        this._elegir(this._indice - 1);
        return Clutter.EVENT_STOP;
    }
    return Clutter.EVENT_STOP;
  }

  _sobreElegida(fn) {
    let e = this._apps[this._indice];
    if (e) fn(e);
  }

  _recargar() {
    if (this._destruido) return;
    let elegida = this._apps[this._indice] && this._apps[this._indice].clave;
    this._apps = appsMRU();
    if (!this._apps.length) { this.destruir(); return; }
    let i = this._apps.findIndex(e => e.clave === elegida);
    this._indice = i >= 0 ? i : Math.min(this._indice, this._apps.length - 1);
    if (this._mostrado) {
      this._panel.destroy(); this._celdas = []; this._mostrado = false; this._mostrar();
    }
  }

  _soltada() {
    if (this._modificadorAbajo() || this._esperandoSuelta) return Clutter.EVENT_STOP;
    this._esperandoSuelta = true;
    this._despues(SUELTA_MS, () => {
      this._esperandoSuelta = false;
      if (!this._modificadorAbajo()) this._activarYCerrar();
    });
    return Clutter.EVENT_STOP;
  }

  _activarYCerrar() {
    let e = this._apps[this._indice];
    this.destruir();
    if (e) activarApp(e);
  }

  destruir() {
    if (this._destruido) return;
    this._destruido = true;
    for (let id of this._timers) GLib.source_remove(id);
    this._timers.clear();
    if (this._idDestroy) { global.window_manager.disconnect(this._idDestroy); this._idDestroy = 0; }
    if (this._modal) { Main.popModal(this.actor); this._modal = false; }
    this.actor.destroy();
    if (selector === this) selector = null;
  }
}

function primaryModifier(mask) {
  if (mask == 0) return 0;
  let primary = 1;
  while (mask > 1) { mask >>= 1; primary <<= 1; }
  return primary;
}

// ⌘`: la ventana del frente pasa al fondo y sube la siguiente de la misma
// app; con ⇧ al revés. Sin panel, como en la Mac.
function rotarVentanas(binding) {
  let foco = global.display.focus_window;
  if (!foco) return;
  let k = claveDe(foco);
  let ventanas = ventanasMRU().filter(w => claveDe(w) === k && !w.minimized &&
                                      w.get_workspace() === foco.get_workspace());
  if (ventanas.length < 2) return;
  let ahora = global.get_current_time();
  if (binding.get_name().endsWith('-backward')) {
    Main.activateWindow(ventanas[1], ahora);
    foco.lower();
  } else {
    Main.activateWindow(ventanas[ventanas.length - 1], ahora);
  }
}

function manejar(display, window, binding) {
  if (binding.get_name().startsWith('switch-group')) { rotarVentanas(binding); return; }
  if (selector) return;
  selector = new Selector(binding);
  selector.arrancar(binding);
}

function init(metadata) {}

function enable() {
  // Solo si Cinnamon trae el selector que esperamos reemplazar.
  if (!Main.wm || typeof Main.wm._startAppSwitcher !== 'function') {
    global.logError('cmdtab@macos: Main.wm._startAppSwitcher no existe; no se reemplaza nada');
    return;
  }
  for (let a of ATAJOS) Meta.keybindings_set_custom_handler(a, manejar);
}

function disable() {
  if (selector) selector.destruir();
  selector = null;
  if (!Main.wm || typeof Main.wm._startAppSwitcher !== 'function') return;
  for (let a of ATAJOS)
    Meta.keybindings_set_custom_handler(a, (d, w, b) => Main.wm._startAppSwitcher(d, w, b));
}
