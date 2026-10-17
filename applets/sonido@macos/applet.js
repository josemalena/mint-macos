/*
 * Volumen de la barra (sonido@macos).
 *
 * El menú que sale al pulsar el altavoz, como en Catalina (captura 16-barra-estado-7-volume-100-oscuro):
 *
 *   Volume:                             (en gris)
 *   ━━━━━━━━━━━━━━●                     el control
 *   ─────────────
 *   Output Device:                      (en gris)
 *   ✓ PBH-S370                          los dispositivos de salida; la marca, el activo
 *     Background Music
 *   ─────────────
 *   Sound Preferences…
 *
 * Usa Cvc (el mezclador de Cinnamon), como sound@cinnamon.org, al que reemplaza en la barra. Girar la rueda sobre el
 * altavoz sube y baja el volumen; el clic central silencia. Vuelta atrás: poner sound@cinnamon.org y quitar este.
 */

const Applet = imports.ui.applet;
const PopupMenu = imports.ui.popupMenu;
const Util = imports.misc.util;
const Cvc = imports.gi.Cvc;
const { Clutter, GLib, St } = imports.gi;

const GRIS = "color: rgba(255,255,255,0.45);";
const ANCHO_MARCA = 16;
const PASO = 0.05;           // lo que sube o baja un giro de la rueda

class SonidoApplet extends Applet.IconApplet {
  constructor(metadata, orientation, panelHeight, instanceId) {
    super(orientation, panelHeight, instanceId);
    this.setAllowedLayout(Applet.AllowedLayout.BOTH);

    this._salida = null;           // el stream de salida por defecto (Cvc.MixerSink)
    this._dispositivos = [];       // { id, item }
    this._activo = -1;             // id del dispositivo de salida activo
    this._silencioId = 0;
    this._volumenId = 0;
    this._arrastrando = false;

    this.menuManager = new PopupMenu.PopupMenuManager(this);
    this.menu = new Applet.AppletPopupMenu(this, orientation);
    this.menuManager.addMenu(this.menu);

    this._control = new Cvc.MixerControl({ name: "Volume (macOS)" });
    this._control.connect("state-changed", () => this._alCambiarEstado());
    this._control.connect("output-added", (c, id) => this._agregarSalida(id));
    this._control.connect("output-removed", (c, id) => this._quitarSalida(id));
    this._control.connect("active-output-update", (c, id) => { this._activo = id; this._leerSalida(); this._marcarActivo(); });
    this._control.connect("default-sink-changed", () => { this._leerSalida(); this._marcarActivo(); });
    this._norma = this._control.get_vol_max_norm();

    this._armar();
    this.set_applet_icon_symbolic_name("xsi-audio-volume-muted");
    this.actor.connect("scroll-event", (a, e) => this._alGirar(e));
    this._control.open();
  }

  on_applet_clicked() {
    this.menu.toggle();
  }

  on_applet_middle_clicked() {
    if (this._salida) this._salida.change_is_muted(!this._salida.is_muted);
  }

  // ── el menú ──────────────────────────────────────────────────────────────
  _titulo(texto) {
    let item = new PopupMenu.PopupMenuItem(texto, { reactive: false });
    item.label.set_style(GRIS);
    return item;
  }

  _armar() {
    this.menu.removeAll();
    this.menu.addMenuItem(this._titulo("Volume:"));
    this._deslizador = new PopupMenu.PopupSliderMenuItem(0);
    this._deslizador.connect("value-changed", (item, valor) => this._alMoverDeslizador(valor));
    this._deslizador.connect("drag-begin", () => { this._arrastrando = true; });
    this._deslizador.connect("drag-end", () => { this._arrastrando = false; });
    this.menu.addMenuItem(this._deslizador);
    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
    this.menu.addMenuItem(this._titulo("Output Device:"));
    this._lista = new PopupMenu.PopupMenuSection();
    this.menu.addMenuItem(this._lista);
    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
    let prefs = new PopupMenu.PopupMenuItem("Sound Preferences…");
    prefs.connect("activate", () => Util.spawnCommandLine("mac-settings sound"));
    this.menu.addMenuItem(prefs);
    for (let d of this._dispositivos) this._lista.addMenuItem(d.item);
  }

  _agregarSalida(id) {
    let dispositivo = this._control.lookup_output_id(id);
    if (!dispositivo) return;
    let item = new PopupMenu.PopupBaseMenuItem();
    let caja = new St.BoxLayout({ vertical: false, x_expand: true });
    let marca = new St.Label({ text: "", width: ANCHO_MARCA, y_align: Clutter.ActorAlign.CENTER });
    caja.add_actor(marca);
    caja.add_actor(new St.Label({ text: dispositivo.description, y_align: Clutter.ActorAlign.CENTER }));
    item.addActor(caja, { span: -1, expand: true });
    item.connect("activate", () => this._control.change_output(dispositivo));
    this._lista.addMenuItem(item);
    this._dispositivos.push({ id: id, item: item, marca: marca });
    this._marcarActivo();
  }

  _quitarSalida(id) {
    let i = this._dispositivos.findIndex(d => d.id === id);
    if (i < 0) return;
    this._dispositivos[i].item.destroy();
    this._dispositivos.splice(i, 1);
  }

  _marcarActivo() {
    for (let d of this._dispositivos) d.marca.set_text(d.id === this._activo ? "✓" : "");
  }

  // ── el volumen ───────────────────────────────────────────────────────────
  _alCambiarEstado() {
    if (this._control.get_state() == Cvc.MixerControlState.READY) {
      this._leerSalida();
      this._marcarActivo();
      this.actor.show();
    } else {
      this.actor.hide();
    }
  }

  _leerSalida() {
    if (this._salida) {
      if (this._silencioId) this._salida.disconnect(this._silencioId);
      if (this._volumenId) this._salida.disconnect(this._volumenId);
      this._silencioId = this._volumenId = 0;
    }
    this._salida = this._control.get_default_sink();
    if (this._salida) {
      this._silencioId = this._salida.connect("notify::is-muted", () => this._pintar());
      this._volumenId = this._salida.connect("notify::volume", () => this._pintar());
      let d = this._control.lookup_device_from_stream(this._salida);
      if (d) this._activo = d.get_id();
    }
    this._pintar();
  }

  _fraccion() {
    if (!this._salida || this._salida.is_muted) return 0;
    return Math.min(1, this._salida.volume / this._norma);
  }

  _pintar() {
    let f = this._fraccion();
    let nombre = f <= 0 ? "muted" : f < 0.34 ? "low" : f < 0.67 ? "medium" : "high";
    this.set_applet_icon_symbolic_name(`xsi-audio-volume-${nombre}`);
    if (!this._arrastrando) this._deslizador.setValue(f);
  }

  _alMoverDeslizador(valor) {
    if (!this._salida) return;
    this._salida.volume = valor * this._norma;
    this._salida.push_volume();
    if (valor > 0 && this._salida.is_muted) this._salida.change_is_muted(false);
  }

  _alGirar(evento) {
    if (!this._salida) return Clutter.EVENT_PROPAGATE;
    let dir = evento.get_scroll_direction();
    let delta = dir == Clutter.ScrollDirection.UP ? PASO : dir == Clutter.ScrollDirection.DOWN ? -PASO : 0;
    if (!delta) return Clutter.EVENT_PROPAGATE;
    let nuevo = Math.max(0, Math.min(1, this._salida.volume / this._norma + delta));
    this._salida.volume = nuevo * this._norma;
    this._salida.push_volume();
    this._salida.change_is_muted(nuevo <= 0);
    return Clutter.EVENT_STOP;
  }

  on_applet_removed_from_panel() {
    if (this._salida) {
      if (this._silencioId) this._salida.disconnect(this._silencioId);
      if (this._volumenId) this._salida.disconnect(this._volumenId);
    }
    this._control.close();
  }
}

function main(metadata, orientation, panelHeight, instanceId) {
  return new SonidoApplet(metadata, orientation, panelHeight, instanceId);
}
