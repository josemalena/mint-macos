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
 *
 * Si la ventana no publica el menú de GTK, se le pregunta al registrador
 * com.canonical.AppMenu.Registrar y se lee por com.canonical.dbusmenu (Edge,
 * Chrome, Electron, Qt, Thunderbird…, y las GTK con appmenu-gtk-module).
 * Ese lector es dbusmenu.js, de la sesión de la barra.
 */

const Applet = imports.ui.applet;
const Tooltips = imports.ui.tooltips;
const PopupMenu = imports.ui.popupMenu;
const Main = imports.ui.main;
const { Gio, GLib, St, Clutter, Cinnamon } = imports.gi;
const Cairo = imports.cairo;

const ATTR_LABEL = "label";
const ATTR_ACTION = "action";
const ATTR_TARGET = "target";
const ATTR_ACCEL = "accel";
// Texto literal del atajo («^⌘N»), para lo que atajoBonito no puede mostrar (⌃ no se distingue de ⌘ con keyd): gana sobre «accel».
const ATTR_ACCEL_LITERAL = "x-constanza-accel";
// Ítem alterno (b): va justo después de su ítem base y solo se ve con ⌥ apretado, en su lugar (como el Finder de la Mac).
const ATTR_ALTERNO = "x-constanza-alternate";
// Etiqueta del Finder (s): el hex de su color («» = sin color). Las seguidas se dibujan en una fila de círculos.
const ATTR_TAG_COLOR = "x-constanza-tag-color";
// El ícono del ítem, un GIcon serializado (el menú Go de Catalina lleva uno por ítem).
const ATTR_ICON = "icon";
const LINK_SUBMENU = "submenu";
const LINK_SECTION = "section";

// La barra de menús va siempre en SF, como en macOS, aunque el shell de
// Cinnamon use otra fuente. Va en línea: el tema de Mojave le gana a un
// stylesheet de applet (padding 0 y negrita en los botones del panel), y
// después de recargar el tema el stylesheet no siempre vuelve a ganar.
const ESTILO_FUENTE = 'font-family: ".SF NS", sans-serif; font-size: 10pt;';
// Los desplegables, con la SF del grado de los menús de Catalina (regla de
// fontconfig de tema/fuentes); si no está, cae a la SF normal. 14 px, como los
// menús de Catalina (José, 13-10-2026): la altura cuadra con la captura de la Mac
// («Hide Others» 11 px de alto, igual que allá). El texto sale un 4 % más ancho
// (la Mac aplica su espaciado de letras de 14 px; «About Finder» mide 83 px allá
// y 88 aquí). Un letter-spacing no lo arregla: el St de Cinnamon lo ignora por
// debajo de -1 px (probado: 0, -0.33, -0.5 y -1 px dan el mismo ancho, y -2 px
// ya lo achica un 12 %). La barra de arriba se queda en 13,3 px (10pt), que es
// la de la barra de menús de Catalina.
const ESTILO_MENU = 'font-family: ".SF NS Menú", ".SF NS", sans-serif; font-size: 10.5pt;';
// Los títulos (File, Edit…): blancos y en peso regular. El cuerpo de más lo
// pone el grado de la SF (GRAD 620); con 600 encima salían 22 % más gruesos
// y 4 px más anchos que en la Mac (Dev-Dock, «Window»: 50 px allá). En la Mac
// solo el nombre de la app va en negrita. 9 px por lado: unos 20 px de tinta
// a tinta entre títulos.
const ESTILO_BOTON = ESTILO_FUENTE + " color: #ffffff; font-weight: normal; padding: 0 9px;";

function atributo(modelo, i, nombre) {
  let v = modelo.get_item_attribute_value(i, nombre, null);
  return v ? v : null;
}

function texto(modelo, i, nombre) {
  let v = atributo(modelo, i, nombre);
  try { return v ? v.unpack() : null; } catch (e) { return null; }
}

// Separador como el de macOS (medido por la sesión de la barra en c28): el
// renglón sin el relleno de los demás y la línea de 2 px de borde a borde.
function separador() {
  let s = new PopupMenu.PopupSeparatorMenuItem();
  s.actor.set_style("padding: 7px 0 3px 0; margin: 0; min-height: 0; spacing: 0;");
  s._drawingArea.set_style("height: 2px; padding: 0; margin: 0; border-bottom-width: 0; -margin-horizontal: 0px; -gradient-height: 2px; -gradient-start: #45484b; -gradient-end: #45484b;");
  return s;
}

// Los renglones reparten sus hijos con las columnas del menú, pero Clutter
// guarda el ancho que pidieron antes de recibirlas, y Cinnamon solo lo
// invalida si el tema tiene background-image (_menuQueueRelayout). Sin esto,
// al llenar un menú abierto la caja queda en 257 y el renglón se pinta a 276:
// el separador y el resaltado se salen por la derecha. Pasaba en los dos
// caminos (en GTK, el Go de Fynder, foto de José del 10-10-2026). Se baja
// también a los submenús en línea.
function relanzar(menu) {
  for (let a of menu.box.get_children()) {
    a.queue_relayout();
    let d = a._delegate;
    if (d && d.menu && d.menu.box && d.menu !== menu) relanzar(d.menu);
  }
  menu.box.queue_relayout();
}

// Lo que se ve de un menú dbusmenu, para saber si cambió al abrirlo.
function firmaDbus(items) {
  return JSON.stringify(items, (k, v) => (typeof v === "function" ? undefined : v));
}

// «_File» → «File» (el guion bajo marca el atajo de teclado en GTK).
function limpiarEtiqueta(s) {
  return (s || "").replace(/__/g, "\u0000").replace(/_/g, "").replace(/\u0000/g, "_");
}

// «<Control><Shift>n» → «⇧⌘N», como en macOS: con keyd, ⌘ es Ctrl.
function atajoBonito(accel, teclaBonita) {
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
  return out + (teclaBonita ? teclaBonita(s) : (s.length === 1 ? s.toUpperCase() : s));
}

// Spotlyte (el lanzador) no cambia la barra: mientras tiene el foco es la de Fynder (la de su
// escritorio), como Spotlight en macOS.
function esLanzador(w) {
  try {
    let c = ((w.get_wm_class_instance && w.get_wm_class_instance()) || (w.get_wm_class && w.get_wm_class()) || "").toLowerCase();
    return c === "ulauncher" || c === "spotlyte";
  } catch (e) { return false; }
}

const RE_INTERNAS = /^mac-(ventanas|acerca|gatekeeper|sesion|forcequit|captura-herramienta)/;
function esInterna(w) {
  try {
    let c = ((w.get_wm_class_instance && w.get_wm_class_instance()) || (w.get_wm_class && w.get_wm_class()) || "").toLowerCase();
    return RE_INTERNAS.test(c);
  } catch (e) { return false; }
}

function ventanaDelEscritorioDeFynder() {
  try {
    for (let a of global.get_window_actors()) {
      let m = a.meta_window;
      let c = m && ((m.get_wm_class_instance && m.get_wm_class_instance()) || "");
      if (c && c.toLowerCase() === "nemo-desktop") return m;
    }
  } catch (e) {}
  return null;
}

// La ✓ de macOS va en el margen izquierdo, sin correr el texto: donde
// Cinnamon pone el punto de radio (PopupBaseMenuItem._allocate lo coloca en
// el relleno). setOrnament(CHECK) pinta una casilla, que la Mac no tiene.
function marcar(item) {
  item._onRepaintDot = dibujarCheck;
  item.setShowDot(true);
}

function dibujarCheck(area) {
  let cr = area.get_context();
  let [w, h] = area.get_surface_size();
  let c = area.get_theme_node().get_foreground_color();
  cr.setSourceRGBA(c.red / 255, c.green / 255, c.blue / 255, c.alpha / 255);
  cr.setLineWidth(1.6);
  cr.setLineCap(Cairo.LineCap.ROUND);
  cr.setLineJoin(Cairo.LineJoin.ROUND);
  cr.moveTo(w * 0.08, h * 0.55);
  cr.lineTo(w * 0.38, h * 0.88);
  cr.lineTo(w * 0.95, h * 0.08);
  cr.stroke();
  cr.$dispose();
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

// ── El servicio del menú (org.mintmacos.Menu1, nativo/menu/DBUS.md) ─────────────────────────────────────────────────
// Lo pesado (leer GMenuModel y dbusmenu, aplanar secciones, dar la forma de la Mac a los atajos) lo hace mac-ventanas; el
// applet pide la barra y los menús por xid y dibuja. Si el servicio no está (nadie tiene el nombre) se cae al camino de
// siempre, que sigue más abajo.
const MENU1 = "org.mintmacos.Menu1";
const RUTA_MENU1 = "/org/mintmacos/Menu1";

function menu1(metodo, params, tipo) {
  return new Promise((resolver, rechazar) => {
    Gio.DBus.session.call(MENU1, RUTA_MENU1, MENU1, metodo, params, tipo ? new GLib.VariantType(tipo) : null,
      Gio.DBusCallFlags.NONE, 5000, null, (con, res) => {
        try { resolver(con.call_finish(res)); } catch (e) { rechazar(e); }
      });
  });
}

function sinServicio(e) {
  let m = String(e && e.message);
  return m.indexOf("ServiceUnknown") >= 0 || m.indexOf("NameHasNoOwner") >= 0 || m.indexOf("not provided by any") >= 0;
}

function desempacar(v) {
  return typeof v.recursiveUnpack === "function" ? v.recursiveUnpack() : v.deepUnpack();
}

// Un renglón con submenú: Cinnamon los despliega hacia abajo, en acordeón (José, 18-10-2026: los que salían a la derecha eran
// lentos y el triángulo no se parecía al de Apple). Lo que cambia es la sangría: los ítems de dentro van corridos a la derecha,
// para que se vea que son de un submenú.
const SANGRIA_SUBMENU = "padding-left: 18px;";

// Ítems alternos (⌥). `alterno` toma el lugar de `base` mientras ⌥ está apretado; los pares quedan en menu._pares.
let ALT_APRETADO = false;

function agregarItem(menu, item, esAlterno) {
  let base = null;
  if (esAlterno) {
    let hijos = menu.box.get_children();
    let ultimo = hijos.length ? hijos[hijos.length - 1]._delegate : null;
    if (ultimo && ultimo instanceof PopupMenu.PopupBaseMenuItem && !(ultimo instanceof PopupMenu.PopupSeparatorMenuItem)) base = ultimo;
  }
  menu.addMenuItem(item);
  if (!base) return;
  if (!menu._pares) menu._pares = [];
  menu._pares.push({ base: base, alterno: item });
  sincronizarAlternos(menu, ALT_APRETADO);
}

function sincronizarAlternos(menu, conAlt) {
  ALT_APRETADO = conAlt;
  for (let a of menu.box.get_children()) {
    let d = a._delegate;
    if (d && d.menu && d.menu !== menu && d.menu.box) sincronizarAlternos(d.menu, conAlt);
  }
  for (let p of menu._pares || []) {
    p.base.actor.visible = !conAlt;
    p.alterno.actor.visible = conAlt;
  }
  relanzar(menu);
}

// Con el menú abierto: ⌥ apretado (ahora o después) cambia los ítems; se llama una vez por menú.
function vigilarAlt(menu) {
  let alt = (mods) => (mods & Clutter.ModifierType.MOD1_MASK) !== 0;
  let tecla = (event, apretada) => {
    let k = event.get_key_symbol();
    if (k === Clutter.KEY_Alt_L || k === Clutter.KEY_Alt_R) sincronizarAlternos(menu, apretada);
    return Clutter.EVENT_PROPAGATE;
  };
  menu.actor.connect("key-press-event", (a, e) => tecla(e, true));
  menu.actor.connect("key-release-event", (a, e) => tecla(e, false));
  menu.connect("open-state-changed", (_m, abierto) => {
    if (!abierto) return;
    let [, , mods] = global.get_pointer();
    ALT_APRETADO = alt(mods);
  });
}

// La fila de etiquetas del Finder: una fila de círculos de color, cada uno su propia opción (captura 12.34.39 PM). `lista` trae por
// círculo {color, nombre, activo, activar}; el nombre sale como ayuda al pasar el puntero y uno apagado va sin respuesta al clic.
function filaEtiquetas(menu, lista) {
  let item = new PopupMenu.PopupBaseMenuItem({ reactive: false, activate: false });
  let caja = new St.BoxLayout({ style: "spacing: 9px; padding: 3px 0px 3px 2px;" });
  for (let e of lista) {
    let estilo = e.color
      ? `background-color: ${e.color}; border: 1px solid rgba(255,255,255,0.28);`
      : "background-color: transparent; border: 1.5px solid #8e8e93;";
    let c = new St.Button({ reactive: e.activo, track_hover: e.activo, can_focus: false,
                            style: estilo + " border-radius: 9px; width: 14px; height: 14px;" });
    if (!e.activo) c.set_opacity(90);
    try { new Tooltips.Tooltip(c, e.nombre); } catch (err) {}
    c.connect("clicked", () => { menu.close(); e.activar(); });
    caja.add_actor(c);
  }
  item.addActor(caja, { span: -1 });
  return item;
}

function submenu(etiqueta) {
  let item = new PopupMenu.PopupSubMenuMenuItem(etiqueta);
  item.menu.box.set_style(SANGRIA_SUBMENU);
  return item;
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

    this._D = imports.ui.appletManager.applets[metadata.uuid].dbusmenu;
    this._lector = null;
    // Varias apps anotan su menú tarde: si es la ventana enfocada, se rehace.
    this._reg = new this._D.Registrador(xid => {
      let w = this._ventana;
      if (w && w.get_xwindow && w.get_xwindow() === xid) { this._ventana = null; this._alCambiarFoco(); }
    });

    // BarraCambio / ArbolCambio del servicio: solo las de la ventana de la barra.
    this._senalesMenu1 = ["BarraCambio", "ArbolCambio"].map(nombre =>
      Gio.DBus.session.signal_subscribe(MENU1, MENU1, nombre, RUTA_MENU1, null, Gio.DBusSignalFlags.NONE,
        (_c, _s, _r, _i, n, p) => this._alCambiarMenu1(n, p)));
    this._xidServicio = 0;
    this._version = 0;

    this._senalFoco = global.display.connect("notify::focus-window", () => this._alCambiarFoco());
    // Al entrar el escritorio de Fynder puede salir después que la barra: sin foco, hasta que aparece la barra sale vacía.
    this._senalCreada = 0;
    try {
      this._senalCreada = global.display.connect("window-created", () => {
        if (!this._ventana) GLib.timeout_add(GLib.PRIORITY_DEFAULT, 400, () => { this._alCambiarFoco(); return GLib.SOURCE_REMOVE; });
      });
    } catch (e) {}
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
    if (this._lector) { try { this._lector.destruir(); } catch (e) {} this._lector = null; }
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
    if (w && esLanzador(w)) w = ventanaDelEscritorioDeFynder() || this._ventana;
    // About, Force Quit y demás programas internos de mint-macos no tienen menú: la barra sigue con la app anterior.
    if (w && esInterna(w)) return;
    // Sin ventana con foco (recién entrada la sesión, o cerrada la última) la barra es la de Fynder, como el Finder
    // de la Mac. Con un menú nuestro abierto el foco también es nulo, y ahí sí se conserva lo que hay.
    if (!w && global.stage_input_mode === Cinnamon.StageInputMode.NORMAL) w = ventanaDelEscritorioDeFynder();
    // Al abrir uno de nuestros menús el foco no cambia a otra app; si la nueva
    // ventana es nula (el escritorio, el propio panel) se conserva el menú.
    if (!w) return;
    if (w === this._ventana) return;

    this._ventana = w;
    this._probando = null;
    this._soltarModelo();
    this._limpiar();
    this._viaServicio(w);
  }

  // El servicio da la barra de la ventana; si nadie tiene org.mintmacos.Menu1, se lee aquí como antes.
  _viaServicio(w) {
    let xid = 0;
    try { xid = w.get_xwindow(); } catch (e) {}
    this._xidServicio = xid;
    menu1("Barra", new GLib.Variant("(u)", [xid]), "(uaa{sv})").then(r => {
      if (w !== this._ventana) return;
      let [version, items] = desempacar(r);
      this._version = version;
      this._limpiar();
      for (let it of items) this._agregarBotonServicio(it);
    }).catch(e => {
      if (w !== this._ventana) return;
      if (sinServicio(e)) this._leerEnApplet(w);
    });
  }

  _leerEnApplet(w) {
    let bus = null, rutaMenu = null, rutaApp = null, rutaVentana = null;
    try {
      bus = w.get_gtk_unique_bus_name();
      rutaMenu = w.get_gtk_menubar_object_path();
      rutaApp = w.get_gtk_application_object_path();
      rutaVentana = w.get_gtk_window_object_path();
    } catch (e) {}
    if (!bus || !rutaMenu) { this._probarDbusmenu(w); return; }

    let con = Gio.DBus.session;
    this._modelo = Gio.DBusMenuModel.get(con, bus, rutaMenu);
    if (rutaApp) this._grupos.app = Gio.DBusActionGroup.get(con, bus, rutaApp);
    if (rutaVentana) this._grupos.win = Gio.DBusActionGroup.get(con, bus, rutaVentana);
    // appmenu-gtk-module publica las acciones en la misma ruta del menú, con
    // el prefijo «unity.».
    this._grupos.unity = Gio.DBusActionGroup.get(con, bus, rutaMenu);
    for (let g of Object.values(this._grupos)) { try { g.list_actions(); } catch (e) {} }

    this._senalModelo = this._modelo.connect("items-changed", () => this._programarArmado());
    precargar(this._modelo, 0, this._vivos);
    this._programarArmado();
  }

  _alCambiarMenu1(nombre, p) {
    let w = this._ventana;
    let xid = p.get_child_value(0).get_uint32();
    if (!w || xid !== this._xidServicio) return;
    if (nombre === "BarraCambio") {
      if (this._avisoMenu1) GLib.source_remove(this._avisoMenu1);
      this._avisoMenu1 = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 60, () => { this._avisoMenu1 = 0; this._viaServicio(w); return GLib.SOURCE_REMOVE; });
    } else {
      let id = p.get_child_value(1).get_string()[0];
      for (let m of this._menus) if (m._idServicio === id && m.isOpen) this._abrirServicio(m);
    }
  }

  // Para las pruebas: lo mismo que hace ⌥ al apretarse o soltarse con el menú abierto.
  _sincAlt(menu, conAlt) { sincronizarAlternos(menu, conAlt); }

  _agregarBotonServicio(it) {
    let boton = new St.Button({ label: it.etiqueta, style_class: "globalmenu-boton", reactive: true,
                                can_focus: true, track_hover: true, toggle_mode: false, style: ESTILO_BOTON });
    this._caja.add_actor(boton);
    let lado = this._orientation === St.Side.BOTTOM ? St.Side.BOTTOM : St.Side.TOP;
    let menu = new PopupMenu.PopupMenu(boton, lado);
    menu._calculatePosition = alinearALaIzquierda;
    menu.actor.set_style(ESTILO_MENU);
    menu.actor.add_style_class_name("constanza-menu");
    menu.box.add_style_class_name("constanza-menu-box");
    Main.uiGroup.add_actor(menu.actor);
    menu.actor.hide();
    this.menuManager.addMenu(menu);
    this._menus.push(menu);
    vigilarAlt(menu);
    menu._idServicio = it.id;
    menu.connect("open-state-changed", (_m, abierto) => {
      boton.checked = abierto;
      if (abierto) this._abrirServicio(menu);
      else menu1("Cerrar", new GLib.Variant("(us)", [this._xidServicio, it.id]), null).catch(() => {});
    });
    boton.connect("clicked", () => menu.toggle());
  }

  _abrirServicio(menu) {
    let w = this._ventana;
    menu1("Abrir", new GLib.Variant("(us)", [this._xidServicio, menu._idServicio]), "(uaa{sv})").then(r => {
      if (w !== this._ventana || !menu.isOpen) return;
      let [version, items] = desempacar(r);
      this._version = version;
      this._raiz = menu;
      menu.removeAll();
      menu._pares = [];
      this._itemsServicio(menu, items, 0);
      relanzar(menu);
    }).catch(e => { log("globalmenu: Abrir: " + e.message); });
  }

  // La acción de un ítem del servicio (Activar); si la app rehízo el menú, se vuelve a pedir la barra.
  _activarServicio(id) {
    let w = this._ventana, xid = this._xidServicio;
    return () => {
      menu1("Activar", new GLib.Variant("(uus)", [xid, this._version, id]), "(b)").catch(e => {
        // La app rehízo el menú entre el clic y la llamada: no se ejecutó nada; se vuelve a pedir la barra.
        if (String(e.message).indexOf("Vencido") >= 0 && w === this._ventana) this._viaServicio(w);
        else log("globalmenu: Activar: " + e.message);
      });
    };
  }

  _itemsServicio(menu, items, profundidad) {
    for (let i = 0; i < items.length; i++) {
      let it = items[i];
      if (it.tipo === "separador") { menu.addMenuItem(separador()); continue; }
      if (typeof it.etiqueta_color === "string") {
        let fila = [it];
        while (i + 1 < items.length && typeof items[i + 1].etiqueta_color === "string") fila.push(items[++i]);
        menu.addMenuItem(filaEtiquetas(menu, fila.map(f => ({ color: f.etiqueta_color, nombre: f.etiqueta, activo: f.activo !== false,
                                                             activar: this._activarServicio(f.id) }))));
        continue;
      }
      if (it.tipo === "submenu") {
        let sub = submenu(it.etiqueta);
        menu.addMenuItem(sub);
        if (profundidad < 4 && it.hijos) this._itemsServicio(sub.menu, it.hijos, profundidad + 1);
        sub.setSensitive(it.activo !== false);
        continue;
      }
      let item = new PopupMenu.PopupMenuItem(it.etiqueta);
      if (it.marca && it.marcado) marcar(item);
      let id = it.id, w = this._ventana, xid = this._xidServicio;
      item._esAlterno = !!it.alterno;
      item.connect("activate", () => {
        menu1("Activar", new GLib.Variant("(uus)", [xid, this._version, id]), "(b)").catch(e => {
          // La app rehízo el menú entre el clic y la llamada: no se ejecutó nada; se vuelve a pedir la barra.
          if (String(e.message).indexOf("Vencido") >= 0 && w === this._ventana) this._viaServicio(w);
          else log("globalmenu: Activar: " + e.message);
        });
      });
      if (it.icono) {
        try {
          let ic = new St.Icon({ gicon: Gio.Icon.new_for_string(it.icono), icon_size: 16, style_class: "globalmenu-icono",
                                 y_align: Clutter.ActorAlign.CENTER });
          item.actor.insert_child_at_index(ic, 0);
        } catch (e) {}
      }
      if (it.atajo) {
        try {
          item.addActor(new St.Label({ text: it.atajo, style_class: "globalmenu-atajo", y_align: Clutter.ActorAlign.CENTER }),
                        { align: St.Align.END });
        } catch (e) {}
      }
      item.setSensitive(it.activo !== false);
      agregarItem(menu, item, item._esAlterno);
    }
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

  // Los ítems de la barra, entrando en las secciones sin etiqueta: appmenu-gtk-module (xed y las apps que exportan así)
  // envuelve la barra en dos secciones, y los menús File, Edit… quedan dentro. Devuelve [modelo, índice].
  _itemsDeBarra(m, prof = 0) {
    let res = [];
    let n = m.get_n_items();
    for (let i = 0; i < n; i++) {
      let sub = m.get_item_link(i, LINK_SUBMENU);
      let sec = m.get_item_link(i, LINK_SECTION);
      if (sec && !sub && prof < 4) {
        this._vivos.push(sec);
        precargar(sec, 0, this._vivos);
        res = res.concat(this._itemsDeBarra(sec, prof + 1));
      } else {
        res.push([m, i]);
      }
    }
    return res;
  }

  // ¿El modelo de GTK trae al menos un menú que se pueda pintar?
  _modeloConMenus(m) {
    for (let [mm, i] of this._itemsDeBarra(m)) {
      if (mm.get_item_link(i, LINK_SUBMENU) && limpiarEtiqueta(texto(mm, i, ATTR_LABEL))) return true;
    }
    return false;
  }

  _armarBarra() {
    let m = this._modelo;
    if (!m) return;
    // Ya se está pintando el menú de dbusmenu y el de GTK sigue vacío: no se borra.
    if (this._lector && !this._modeloConMenus(m)) return;
    this._limpiar();
    this._vivos = [];
    precargar(m, 0, this._vivos);
    for (let [mm, i] of this._itemsDeBarra(m)) {
      let sub = mm.get_item_link(i, LINK_SUBMENU);
      let etiqueta = limpiarEtiqueta(texto(mm, i, ATTR_LABEL));
      if (!sub || !etiqueta) continue;
      // El menú propio de la app (x-constanza-app-menu) lo pinta appmenu en
      // el nombre de la app; aquí no se repite.
      let propio = atributo(mm, i, "x-constanza-app-menu");
      try { if (propio && propio.get_boolean()) continue; } catch (e) {}
      this._agregarBoton(etiqueta, sub);
    }
    // Causa de «Firefox pierde el menú global»: con GTK_MODULES=appmenu-gtk-module el módulo anota
    // _GTK_MENUBAR_OBJECT_PATH en CADA ventana GTK, también en las que exportan su menú por dbusmenu
    // (Firefox lo registra en com.canonical.AppMenu.Registrar). El modelo de GTK queda vacío y, como
    // había bus y ruta, nunca se probaba dbusmenu. Si GTK no da ningún menú, se prueba dbusmenu.
    if (this._menus.length > 0) {
      if (this._lector) { try { this._lector.destruir(); } catch (e) {} this._lector = null; }
    } else if (!this._lector && this._ventana && this._probando !== this._ventana) {
      this._probando = this._ventana;
      this._probarDbusmenu(this._ventana);
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
    menu.actor.set_style(ESTILO_MENU);
    menu.actor.add_style_class_name("constanza-menu");
    menu.box.add_style_class_name("constanza-menu-box");
    Main.uiGroup.add_actor(menu.actor);
    menu.actor.hide();
    this.menuManager.addMenu(menu);
    this._menus.push(menu);
    vigilarAlt(menu);

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
    this._raiz = menu;
    this._soltarSubmodelos();
    menu.removeAll();
    menu._pares = [];
    this._agregarItems(menu, modelo, 0);
    relanzar(menu);
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
          menu.addMenuItem(separador());
        if (this._agregarItems(menu, seccion, profundidad)) huboAlgo = true;
        continue;
      }
      if (texto(modelo, i, ATTR_TAG_COLOR) !== null) {
        let fila = [];
        let j = i;
        for (; j < n && !modelo.get_item_link(j, LINK_SECTION) && texto(modelo, j, ATTR_TAG_COLOR) !== null; j++) {
          let accion = texto(modelo, j, ATTR_ACTION), objetivo = atributo(modelo, j, ATTR_TARGET);
          let [grupo, nombre] = accion ? this._grupoDe(accion) : [null, null];
          let activo = !!(grupo && nombre && grupo.has_action(nombre) && grupo.get_action_enabled(nombre));
          fila.push({ color: texto(modelo, j, ATTR_TAG_COLOR) || "", nombre: limpiarEtiqueta(texto(modelo, j, ATTR_LABEL)), activo: activo,
                      activar: () => { if (grupo && nombre) grupo.activate_action(nombre, objetivo); } });
        }
        menu.addMenuItem(filaEtiquetas(menu, fila));
        i = j - 1;
        huboAlgo = true;
        continue;
      }
      let etiqueta = limpiarEtiqueta(texto(modelo, i, ATTR_LABEL));
      let sub = modelo.get_item_link(i, LINK_SUBMENU);
      if (sub) {
        let item = submenu(etiqueta);
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
    // Las marcas como en macOS: una ✓ a la izquierda del texto, sin
    // interruptor; vale para los booleanos y para los grupos de radio.
    if (estado && estado.get_type_string() === "b" && !objetivo) {
      // Booleano (p. ej. «Show Hidden Files»).
      let valor = estado.get_boolean();
      item = new PopupMenu.PopupMenuItem(etiqueta);
      if (valor) marcar(item);
      item.connect("activate", () => grupo.change_action_state(nombre, GLib.Variant.new_boolean(!valor)));
    } else if (estado && objetivo) {
      // Grupo de radio: marcado si el estado es igual al objetivo del ítem.
      item = new PopupMenu.PopupMenuItem(etiqueta);
      try { if (estado.equal(objetivo)) marcar(item); } catch (e) {}
      item.connect("activate", () => grupo.change_action_state(nombre, objetivo));
    } else {
      item = new PopupMenu.PopupMenuItem(etiqueta);
      item.connect("activate", () => { if (grupo && nombre) grupo.activate_action(nombre, objetivo); });
    }

    let atajo = texto(modelo, i, ATTR_ACCEL_LITERAL) || atajoBonito(texto(modelo, i, ATTR_ACCEL), this._D && this._D.teclaBonita);
    let icono = null;
    try {
      let v = atributo(modelo, i, ATTR_ICON);
      if (v) icono = Gio.Icon.deserialize(v);
    } catch (e) {}
    if (icono) {
      try {
        let ic = new St.Icon({ gicon: icono, icon_size: 16, style_class: "globalmenu-icono", y_align: Clutter.ActorAlign.CENTER });
        item.actor.insert_child_at_index(ic, 0);
      } catch (e) {}
    }
    if (atajo) {
      try {
        item.addActor(new St.Label({ text: atajo, style_class: "globalmenu-atajo", y_align: Clutter.ActorAlign.CENTER }),
                      { align: St.Align.END });
      } catch (e) {}
    }
    item.setSensitive(activa);
    try { let a = atributo(modelo, i, ATTR_ALTERNO); item._esAlterno = !!(a && a.get_boolean()); } catch (e) {}
    agregarItem(menu, item, item._esAlterno);
  }

  // ── Camino dbusmenu (apps que no publican el menú de GTK) ──────────────
  async _probarDbusmenu(w) {
    let xid = 0;
    try { xid = w.get_xwindow(); } catch (e) {}
    let par = await this._reg.menuDe(xid);
    if (w !== this._ventana || !par) return;   // el foco ya cambió, o no hay menú
    this._lector = new this._D.LectorDbusmenu(par[0], par[1], () => this._armarDbusmenu(w));
    this._armarDbusmenu(w);
  }

  async _armarDbusmenu(w) {
    let lector = this._lector;
    if (!lector) return;
    let titulos = await lector.titulos();
    if (w !== this._ventana || lector !== this._lector) return;
    this._limpiar();
    for (let t of titulos) this._agregarBotonDbus(t);
  }

  _agregarBotonDbus(t) {
    let boton = new St.Button({ label: t.etiqueta, style_class: "globalmenu-boton", reactive: true,
                                can_focus: true, track_hover: true, toggle_mode: false, style: ESTILO_BOTON });
    this._caja.add_actor(boton);
    let lado = this._orientation === St.Side.BOTTOM ? St.Side.BOTTOM : St.Side.TOP;
    let menu = new PopupMenu.PopupMenu(boton, lado);
    menu._calculatePosition = alinearALaIzquierda;
    menu.actor.set_style(ESTILO_MENU);
    menu.actor.add_style_class_name("constanza-menu");
    menu.box.add_style_class_name("constanza-menu-box");
    Main.uiGroup.add_actor(menu.actor);
    menu.actor.hide();
    this.menuManager.addMenu(menu);
    this._menus.push(menu);
    vigilarAlt(menu);
    menu.connect("open-state-changed", async (_m, abierto) => {
      boton.checked = abierto;
      if (!abierto) { try { t.cerrar(); } catch (e) {} return; }
      // Lo que ya se sabe, en seguida; y otra vez cuando la app lo llene
      // (Chrome, Firefox y Electron arman el menú al abrirlo).
      // Si abrir() no cambió nada (Edge casi nunca cambia), no se rehace: así
      // no parpadea.
      let antes = firmaDbus(t.items());
      this._llenarDbus(menu, t.items());
      await t.abrir();
      if (menu.isOpen && firmaDbus(t.items()) !== antes) this._llenarDbus(menu, t.items());
    });
    boton.connect("clicked", () => menu.toggle());
  }

  _llenarDbus(menu, items) {
    this._raiz = menu;
    menu.removeAll();
    this._itemsDbus(menu, items, 0);
    relanzar(menu);
  }

  _itemsDbus(menu, items, profundidad) {
    for (let it of items) {
      if (it.separador) { menu.addMenuItem(separador()); continue; }
      if (it.submenu) {
        let sub = submenu(it.etiqueta);
        menu.addMenuItem(sub);
        if (profundidad < 4) this._itemsDbus(sub.menu, it.submenu, profundidad + 1);
        sub.setSensitive(it.activo);
        continue;
      }
      // Marcas como en macOS: ✓ a la izquierda, sin interruptor.
      let item = new PopupMenu.PopupMenuItem(it.etiqueta);
      if (it.marca && it.marcado) marcar(item);
      item.connect("activate", () => it.activar());
      if (it.atajo) {
        try {
          item.addActor(new St.Label({ text: it.atajo, style_class: "globalmenu-atajo", y_align: Clutter.ActorAlign.CENTER }),
                        { align: St.Align.END });
        } catch (e) {}
      }
      item.setSensitive(it.activo);
      menu.addMenuItem(item);
    }
  }

  on_applet_removed_from_panel() {
    if (this._reg) { try { this._reg.destruir(); } catch (e) {} this._reg = null; }
    if (this._senalFoco) { try { global.display.disconnect(this._senalFoco); } catch (e) {} }
    if (this._senalCreada) { try { global.display.disconnect(this._senalCreada); } catch (e) {} }
    if (this._pendiente) GLib.source_remove(this._pendiente);
    if (this._relleno) GLib.source_remove(this._relleno);
    if (this._avisoMenu1) GLib.source_remove(this._avisoMenu1);
    for (let id of this._senalesMenu1 || []) { try { Gio.DBus.session.signal_unsubscribe(id); } catch (e) {} }
    this._senalesMenu1 = [];
    this._soltarModelo();
    this._limpiar();
  }
}

function main(metadata, orientation, panel_height, instance_id) {
  return new GlobalMenuApplet(metadata, orientation, panel_height, instance_id);
}
