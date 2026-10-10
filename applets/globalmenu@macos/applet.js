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
const PopupMenu = imports.ui.popupMenu;
const Main = imports.ui.main;
const { Gio, GLib, St, Clutter, Cinnamon } = imports.gi;
const Cairo = imports.cairo;

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
// Blanco y peso 600: la Mac los pinta algo más gruesos que el regular
// (medido contra la captura de José); 9 px por lado dejan 20-21 px de tinta
// a tinta entre títulos, como allá.
// Los desplegables, con la SF del grado de los menús de Catalina (regla de
// fontconfig de tema/fuentes); si no está, cae a la SF normal.
const ESTILO_MENU = 'font-family: ".SF NS Menú", ".SF NS", sans-serif; font-size: 10pt;';
const ESTILO_BOTON = ESTILO_FUENTE + " color: #ffffff; font-weight: 600; padding: 0 9px;";

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
      // El menú propio de la app (x-constanza-app-menu) lo pinta appmenu en
      // el nombre de la app; aquí no se repite.
      let propio = atributo(m, i, "x-constanza-app-menu");
      try { if (propio && propio.get_boolean()) continue; } catch (e) {}
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
    menu.actor.set_style(ESTILO_MENU);
    menu.actor.add_style_class_name("constanza-menu");
    menu.box.add_style_class_name("constanza-menu-box");
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

    let atajo = atajoBonito(texto(modelo, i, ATTR_ACCEL), this._D && this._D.teclaBonita);
    if (atajo) {
      try {
        item.addActor(new St.Label({ text: atajo, style_class: "globalmenu-atajo", y_align: Clutter.ActorAlign.CENTER }),
                      { align: St.Align.END });
      } catch (e) {}
    }
    item.setSensitive(activa);
    menu.addMenuItem(item);
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
    menu.removeAll();
    this._itemsDbus(menu, items, 0);
    relanzar(menu);
  }

  _itemsDbus(menu, items, profundidad) {
    for (let it of items) {
      if (it.separador) { menu.addMenuItem(separador()); continue; }
      if (it.submenu) {
        let sub = new PopupMenu.PopupSubMenuMenuItem(it.etiqueta);
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
    if (this._pendiente) GLib.source_remove(this._pendiente);
    if (this._relleno) GLib.source_remove(this._relleno);
    this._soltarModelo();
    this._limpiar();
  }
}

function main(metadata, orientation, panel_height, instance_id) {
  return new GlobalMenuApplet(metadata, orientation, panel_height, instance_id);
}
