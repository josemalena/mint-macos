/*
 * Global Menu (macOS) — applet de Cinnamon
 * UUID: globalmenu@macos
 *
 * Muestra en el panel la barra de menú de la ventana enfocada, como en macOS.
 * Usa el protocolo estándar de GTK: la aplicación exporta su menú como
 * GMenuModel (org.gtk.Menus) y sus acciones (org.gtk.Actions) en D-Bus, y deja
 * en su ventana las propiedades X _GTK_UNIQUE_BUS_NAME, _GTK_MENUBAR_OBJECT_PATH,
 * _GTK_APPLICATION_OBJECT_PATH y _GTK_WINDOW_OBJECT_PATH, que Muffin expone en
 * Meta.Window. Si la ventana no publica menú, el applet queda vacío.
 *
 * Va a la derecha de appmenu@macos (el nombre de la app con Quit/About).
 */

const Applet = imports.ui.applet;
const PopupMenu = imports.ui.popupMenu;
const Main = imports.ui.main;
const { Gio, GLib, St, Clutter, Cinnamon } = imports.gi;

const ATTR_LABEL = "label";
const ATTR_ACTION = "action";
const ATTR_TARGET = "target";
const ATTR_ACCEL = "accel";
const LINK_SUBMENU = "submenu";
const LINK_SECTION = "section";

// La barra de menús va siempre en SF, como en macOS, aunque el shell de
// Cinnamon use otra fuente. Va en línea: el tema de Mojave le gana a un
// stylesheet de applet (padding 0 y negrita en los botones del panel), y
// después de recargar el tema el stylesheet no siempre vuelve a ganar.
const ESTILO_FUENTE = 'font-family: ".SF NS", sans-serif; font-size: 10pt;';
const ESTILO_BOTON = ESTILO_FUENTE + " font-weight: normal; padding: 0 8px;";

function atributo(modelo, i, nombre) {
  let v = modelo.get_item_attribute_value(i, nombre, null);
  return v ? v : null;
}

function texto(modelo, i, nombre) {
  let v = atributo(modelo, i, nombre);
  try { return v ? v.unpack() : null; } catch (e) { return null; }
}

// «_File» → «File» (el guion bajo marca el atajo de teclado en GTK).
function limpiarEtiqueta(s) {
  return (s || "").replace(/__/g, "\u0000").replace(/_/g, "").replace(/\u0000/g, "_");
}

// «<Control><Shift>n» → «⇧⌘N», como en macOS: con keyd, ⌘ es Ctrl.
function atajoBonito(accel) {
  if (!accel) return "";
  let s = accel, out = "";
  const mods = [["<Primary>", "⌘"], ["<Control>", "⌘"], ["<Ctrl>", "⌘"], ["<Shift>", "⇧"],
                ["<Alt>", "⌥"], ["<Super>", "◆"], ["<Meta>", "◆"]];
  let cambio = true;
  while (cambio) {
    cambio = false;
    for (let [k, v] of mods) {
      if (s.startsWith(k)) { out += v; s = s.slice(k.length); cambio = true; }
    }
  }
  // Orden de macOS: ⌥ ⇧ ⌘, y sin repetir (Primary y Control son el mismo ⌘).
  let orden = "◆⌥⇧⌘";
  out = [...new Set(out)].sort((a, b) => orden.indexOf(a) - orden.indexOf(b)).join("");
  return out + (s.length === 1 ? s.toUpperCase() : s);
}

// Pide los ítems de un modelo y de sus enlaces para que GDBusMenuModel se
// suscriba: los submenús llegan perezosos, y sin esto el primer clic sale vacío.
// La suscripción vive lo que viva el objeto, por eso se guardan en `vivos`:
// si el recolector de basura suelta un submodelo, GTK deja de mandarlo.
function precargar(modelo, profundidad, vivos) {
  if (!modelo || profundidad > 4) return;
  vivos.push(modelo);
  let n = modelo.get_n_items();
  for (let i = 0; i < n; i++) {
    for (let l of [LINK_SUBMENU, LINK_SECTION]) {
      let sub = modelo.get_item_link(i, l);
      if (sub) precargar(sub, profundidad + 1, vivos);
    }
  }
}

// Cinnamon centra el menú bajo el botón; en macOS arranca en su borde
// izquierdo. Se conserva la «y» de Cinnamon y se ajusta solo la «x», sin
// salirse del monitor.
function alinearALaIzquierda() {
  let [x, y] = PopupMenu.PopupMenu.prototype._calculatePosition.call(this);
  let caja = Cinnamon.util_get_transformed_allocation(this.sourceActor);
  let ancho = this.actor.get_preferred_size()[2];
  let monitor = Main.layoutManager.findMonitorForActor(this.sourceActor);
  x = Math.max(monitor.x, Math.min(caja.x1, monitor.x + monitor.width - ancho));
  return [Math.round(x), y];
}

class GlobalMenuApplet extends Applet.Applet {
  constructor(metadata, orientation, panel_height, instance_id) {
    super(orientation, panel_height, instance_id);
    this._orientation = orientation;
    this.set_applet_tooltip("");

    this._caja = new St.BoxLayout({ style_class: "globalmenu-caja" });
    this.actor.add_actor(this._caja);

    this.menuManager = new PopupMenu.PopupMenuManager(this);
    this._menus = [];
    this._ventana = null;
    this._modelo = null;
    this._grupos = {};
    this._senalModelo = 0;
    this._pendiente = 0;
    this._vivos = [];
    this._senalesSub = [];

    this._senalFoco = global.display.connect("notify::focus-window", () => this._alCambiarFoco());
    this._alCambiarFoco();
  }

  _limpiar() {
    for (let m of this._menus) {
      try { this.menuManager.removeMenu(m); } catch (e) {}
      try { m.destroy(); } catch (e) {}
    }
    this._menus = [];
    this._caja.destroy_all_children();
  }

  _soltarModelo() {
    if (this._modelo && this._senalModelo) {
      try { this._modelo.disconnect(this._senalModelo); } catch (e) {}
    }
    this._soltarSubmodelos();
    this._modelo = null;
    this._senalModelo = 0;
    this._grupos = {};
    this._vivos = [];
  }

  _soltarSubmodelos() {
    for (let [m, id] of this._senalesSub) { try { m.disconnect(id); } catch (e) {} }
    this._senalesSub = [];
  }

  _alCambiarFoco() {
    let w = global.display.focus_window;
    // Al abrir uno de nuestros menús el foco no cambia a otra app; si la nueva
    // ventana es nula (el escritorio, el propio panel) se conserva el menú.
    if (!w) return;
    if (w === this._ventana) return;

    let bus = null, rutaMenu = null, rutaApp = null, rutaVentana = null;
    try {
      bus = w.get_gtk_unique_bus_name();
      rutaMenu = w.get_gtk_menubar_object_path();
      rutaApp = w.get_gtk_application_object_path();
      rutaVentana = w.get_gtk_window_object_path();
    } catch (e) {}

    this._ventana = w;
    this._soltarModelo();
    this._limpiar();
    if (!bus || !rutaMenu) return;

    let con = Gio.DBus.session;
    this._modelo = Gio.DBusMenuModel.get(con, bus, rutaMenu);
    if (rutaApp) this._grupos.app = Gio.DBusActionGroup.get(con, bus, rutaApp);
    if (rutaVentana) this._grupos.win = Gio.DBusActionGroup.get(con, bus, rutaVentana);
    for (let g of Object.values(this._grupos)) { try { g.list_actions(); } catch (e) {} }

    this._senalModelo = this._modelo.connect("items-changed", () => this._programarArmado());
    precargar(this._modelo, 0, this._vivos);
    this._programarArmado();
  }

  // Los ítems llegan en ráfagas por D-Bus: se arma una sola vez cuando paran.
  _programarArmado() {
    if (this._pendiente) GLib.source_remove(this._pendiente);
    this._pendiente = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 60, () => {
      this._pendiente = 0;
      this._armarBarra();
      return GLib.SOURCE_REMOVE;
    });
  }

  _armarBarra() {
    this._limpiar();
    let m = this._modelo;
    if (!m) return;
    this._vivos = [];
    precargar(m, 0, this._vivos);
    let n = m.get_n_items();
    for (let i = 0; i < n; i++) {
      let sub = m.get_item_link(i, LINK_SUBMENU);
      let etiqueta = limpiarEtiqueta(texto(m, i, ATTR_LABEL));
      if (!sub || !etiqueta) continue;
      this._agregarBoton(etiqueta, sub);
    }
  }

  _agregarBoton(etiqueta, submenu) {
    let boton = new St.Button({ label: etiqueta, style_class: "globalmenu-boton", reactive: true,
                                can_focus: true, track_hover: true, toggle_mode: false,
                                style: ESTILO_BOTON });
    this._caja.add_actor(boton);

    let lado = this._orientation === St.Side.BOTTOM ? St.Side.BOTTOM : St.Side.TOP;
    let menu = new PopupMenu.PopupMenu(boton, lado);
    menu._calculatePosition = alinearALaIzquierda;
    menu.actor.set_style(ESTILO_FUENTE);
    Main.uiGroup.add_actor(menu.actor);
    menu.actor.hide();
    this.menuManager.addMenu(menu);
    this._menus.push(menu);

    menu.connect("open-state-changed", (_m, abierto) => {
      boton.checked = abierto;
      if (abierto) this._llenar(menu, submenu);
    });
    boton.connect("clicked", () => menu.toggle());
  }

  _grupoDe(nombre) {
    let p = nombre.indexOf(".");
    if (p < 0) return [null, nombre];
    return [this._grupos[nombre.slice(0, p)] || null, nombre.slice(p + 1)];
  }

  // Llena un menú (o submenú) con el GMenuModel, cada vez que se abre: así
  // las acciones salen con su estado y su «enabled» del momento.
  _llenar(menu, modelo) {
    this._soltarSubmodelos();
    menu.removeAll();
    this._agregarItems(menu, modelo, 0);
    // Si un submenú llega por D-Bus con el menú ya abierto, se rehace.
    this._vigilar(modelo, menu, modelo);
  }

  _vigilar(m, menu, raiz) {
    let id = m.connect("items-changed", () => {
      if (!menu.isOpen) return;
      if (this._relleno) GLib.source_remove(this._relleno);
      this._relleno = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 40, () => {
        this._relleno = 0;
        if (menu.isOpen) this._llenar(menu, raiz);
        return GLib.SOURCE_REMOVE;
      });
    });
    this._senalesSub.push([m, id]);
    let n = m.get_n_items();
    for (let i = 0; i < n; i++)
      for (let l of [LINK_SUBMENU, LINK_SECTION]) {
        let sub = m.get_item_link(i, l);
        if (sub) { this._vivos.push(sub); this._vigilar(sub, menu, raiz); }
      }
  }

  _agregarItems(menu, modelo, profundidad) {
    let n = modelo.get_n_items();
    let huboAlgo = false;
    for (let i = 0; i < n; i++) {
      let seccion = modelo.get_item_link(i, LINK_SECTION);
      if (seccion) {
        if (huboAlgo && seccion.get_n_items() > 0)
          menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        if (this._agregarItems(menu, seccion, profundidad)) huboAlgo = true;
        continue;
      }
      let etiqueta = limpiarEtiqueta(texto(modelo, i, ATTR_LABEL));
      let sub = modelo.get_item_link(i, LINK_SUBMENU);
      if (sub) {
        let item = new PopupMenu.PopupSubMenuMenuItem(etiqueta);
        menu.addMenuItem(item);
        if (profundidad < 4) this._agregarItems(item.menu, sub, profundidad + 1);
        huboAlgo = true;
        continue;
      }
      this._agregarAccion(menu, modelo, i, etiqueta);
      huboAlgo = true;
    }
    return huboAlgo;
  }

  _agregarAccion(menu, modelo, i, etiqueta) {
    let accion = texto(modelo, i, ATTR_ACTION);
    let objetivo = atributo(modelo, i, ATTR_TARGET);
    let [grupo, nombre] = accion ? this._grupoDe(accion) : [null, null];
    let activa = !!(grupo && nombre && grupo.has_action(nombre) && grupo.get_action_enabled(nombre));

    let estado = null;
    try { if (grupo && nombre && grupo.has_action(nombre)) estado = grupo.get_action_state(nombre); } catch (e) {}

    let item;
    if (estado && estado.get_type_string() === "b" && !objetivo) {
      // Interruptor (p. ej. «Show Hidden Files»).
      item = new PopupMenu.PopupSwitchMenuItem(etiqueta, estado.get_boolean());
      item.connect("toggled", (_it, valor) => grupo.change_action_state(nombre, GLib.Variant.new_boolean(valor)));
    } else if (estado && objetivo) {
      // Grupo de radio: marcado si el estado es igual al objetivo del ítem.
      item = new PopupMenu.PopupMenuItem(etiqueta);
      try { if (estado.equal(objetivo)) item.setOrnament(PopupMenu.OrnamentType.DOT); } catch (e) {}
      item.connect("activate", () => grupo.change_action_state(nombre, objetivo));
    } else {
      item = new PopupMenu.PopupMenuItem(etiqueta);
      item.connect("activate", () => { if (grupo && nombre) grupo.activate_action(nombre, objetivo); });
    }

    let atajo = atajoBonito(texto(modelo, i, ATTR_ACCEL));
    if (atajo) {
      try {
        item.addActor(new St.Label({ text: atajo, style_class: "globalmenu-atajo", y_align: Clutter.ActorAlign.CENTER }),
                      { align: St.Align.END });
      } catch (e) {}
    }
    item.setSensitive(activa);
    menu.addMenuItem(item);
  }

  on_applet_removed_from_panel() {
    if (this._senalFoco) { try { global.display.disconnect(this._senalFoco); } catch (e) {} }
    if (this._pendiente) GLib.source_remove(this._pendiente);
    if (this._relleno) GLib.source_remove(this._relleno);
    this._soltarModelo();
    this._limpiar();
  }
}

function main(metadata, orientation, panel_height, instance_id) {
  return new GlobalMenuApplet(metadata, orientation, panel_height, instance_id);
}
