/*
 * DBusMenu para globalmenu@macos: el menú de las apps que no son GTK nativo.
 *
 * Firefox, Thunderbird, Chrome, Edge, Electron (VS Code), LibreOffice y Qt no
 * publican su barra como GMenuModel (org.gtk.Menus), que es lo que lee el
 * applet para Fynder. Publican com.canonical.dbusmenu y se anotan en el
 * registrador com.canonical.AppMenu.Registrar (appmenu-registrar, instalado):
 * ventana (XID) → servicio y ruta. Esto es lo mismo que hace KDE Plasma.
 *
 *   Registrador  pregunta GetMenuForWindow(xid) y avisa WindowRegistered y
 *                WindowUnregistered (varias apps se anotan segundos después de
 *                abrir la ventana).
 *   LectorDbusmenu  lee el árbol (GetLayout), avisa a la app antes de abrir
 *                un menú (AboutToShow), manda el clic (Event «clicked») y
 *                escucha cuando el menú cambia (LayoutUpdated,
 *                ItemsPropertiesUpdated).
 *
 * Las apps GTK con appmenu-gtk-module NO pasan por aquí: no se anotan en el
 * registrador y publican org.gtk.Menus en _GTK_MENUBAR_OBJECT_PATH, con sus
 * acciones en esa misma ruta y el prefijo «unity.». Eso lo lee applet.js.
 *
 * Un ítem llega como {id, props, hijos}. De props se usan: type
 * («separator»), label (con «_» de atajo de teclado), enabled, visible,
 * toggle-type («checkmark» o «radio»), toggle-state (1 marcado),
 * shortcut ([["Control", "Shift", "n"]]) y children-display («submenu»).
 * Lo que no viene vale lo que dice la especificación: activo y visible.
 */

const { Gio, GLib } = imports.gi;

const REGISTRADOR = "com.canonical.AppMenu.Registrar";
const RUTA_REGISTRADOR = "/com/canonical/AppMenu/Registrar";
const IFAZ_MENU = "com.canonical.dbusmenu";
const PROPS = ["type", "label", "enabled", "visible", "toggle-type", "toggle-state", "shortcut", "children-display"];
const ESPERA_MS = 3000;

function llamar(bus, ruta, ifaz, metodo, params, tipo) {
  return new Promise((resolver, rechazar) => {
    Gio.DBus.session.call(bus, ruta, ifaz, metodo, params,
      tipo ? new GLib.VariantType(tipo) : null, Gio.DBusCallFlags.NONE, ESPERA_MS, null,
      (con, res) => {
        try { resolver(con.call_finish(res)); } catch (e) { rechazar(e); }
      });
  });
}

/** (ia{sv}av) → {id, props, hijos}. */
function desempacar(v) {
  let id = v.get_child_value(0).get_int32();
  let props = {};
  let dic = v.get_child_value(1);
  for (let i = 0; i < dic.n_children(); i++) {
    let par = dic.get_child_value(i);
    let k = par.get_child_value(0).get_string()[0];
    props[k] = par.get_child_value(1).get_variant().deepUnpack();
  }
  let hijos = [];
  let av = v.get_child_value(2);
  for (let i = 0; i < av.n_children(); i++) hijos.push(desempacar(av.get_child_value(i).get_variant()));
  return { id, props, hijos };
}

/** «_Archivo» → «Archivo»; «__» queda como un «_». */
function etiqueta(item) {
  return (item.props.label || "").replace(/__/g, "\u0000").replace(/_/g, "").replace(/\u0000/g, "_");
}

function esSeparador(item) { return item.props.type === "separator"; }
function esVisible(item) { return item.props.visible !== false; }
function estaActivo(item) { return item.props.enabled !== false; }
function tieneSubmenu(item) { return item.props["children-display"] === "submenu" || item.hijos.length > 0; }

/** [["Control", "Shift", "n"]] → «⇧⌘N», en el orden de la Mac (⌥ ⇧ ⌘). Con
 *  keyd, ⌘ es Control. */
function atajo(item) {
  let s = item.props.shortcut;
  if (!s || !s.length || !s[0].length) return "";
  const MOD = { Control: "⌘", Ctrl: "⌘", Primary: "⌘", Shift: "⇧", Alt: "⌥", Super: "◆", Meta: "◆" };
  const ORDEN = "◆⌥⇧⌘";
  const TECLA = { Delete: "⌦", BackSpace: "⌫", Return: "↩", Escape: "⎋", Tab: "⇥", space: "Space",
                  Left: "←", Right: "→", Up: "↑", Down: "↓", Page_Up: "⇞", Page_Down: "⇟",
                  Home: "↖", End: "↘", plus: "+", minus: "-", equal: "=", comma: ",", period: ".",
                  bracketleft: "[", bracketright: "]", slash: "/", backslash: "\\", semicolon: ";",
                  apostrophe: "'", grave: "`", Insert: "Ins",
                  Esc: "⎋", Del: "⌦", Backspace: "⌫", Enter: "↩", KP_Enter: "⌤",
                  // Edge manda algunas teclas como carácter de control, no por nombre.
                  "\u001b": "⎋", "\u007f": "⌦", "\u0008": "⌫", "\t": "⇥", "\r": "↩", "\n": "↩" };
  let mods = [], tecla = "";
  for (let k of s[0]) {
    if (MOD[k]) mods.push(MOD[k]);
    else tecla = TECLA[k] || (k.length === 1 ? k.toUpperCase() : k);
  }
  // Un atajo sin tecla (Edge manda alguno así) no se pinta a medias: «⇧».
  if (!tecla) return "";
  mods = [...new Set(mods)].sort((a, b) => ORDEN.indexOf(a) - ORDEN.indexOf(b));
  return mods.join("") + tecla;
}

/** «checkmark» o «radio» y si está marcado; null si no es de marcar. */
function marca(item) {
  let tipo = item.props["toggle-type"];
  if (tipo !== "checkmark" && tipo !== "radio") return null;
  return { tipo, marcado: item.props["toggle-state"] === 1 };
}

var Registrador = class Registrador {
  constructor(alCambiar) {
    this._alCambiar = alCambiar;
    let con = Gio.DBus.session;
    this._senales = [
      con.signal_subscribe(null, REGISTRADOR, "WindowRegistered", RUTA_REGISTRADOR, null,
        Gio.DBusSignalFlags.NONE, (_c, _s, _r, _i, _n, p) => this._alCambiar(p.get_child_value(0).get_uint32())),
      con.signal_subscribe(null, REGISTRADOR, "WindowUnregistered", RUTA_REGISTRADOR, null,
        Gio.DBusSignalFlags.NONE, (_c, _s, _r, _i, _n, p) => this._alCambiar(p.get_child_value(0).get_uint32())),
    ];
  }

  /** [servicio, ruta] del menú de la ventana, o null si no se anotó. El
   *  registrador se activa solo por D-Bus si no estaba corriendo. */
  async menuDe(xid) {
    if (!xid) return null;
    try {
      let r = await llamar(REGISTRADOR, RUTA_REGISTRADOR, REGISTRADOR, "GetMenuForWindow",
        new GLib.Variant("(u)", [xid]), "(so)");
      let [servicio, ruta] = r.deepUnpack();
      if (!servicio || !ruta || ruta === "/") return null;
      return [servicio, ruta];
    } catch (e) {
      return null; // la ventana no publica menú
    }
  }

  destruir() {
    for (let id of this._senales) { try { Gio.DBus.session.signal_unsubscribe(id); } catch (e) {} }
    this._senales = [];
  }
};

/** Un ítem del árbol en la forma que pinta el applet. `menu` es el lector. */
function aItem(menu, item) {
  if (esSeparador(item)) return { separador: true };
  // Thunderbird deja ítems sin etiqueta (los que esconde por contexto).
  if (!etiqueta(item) && !tieneSubmenu(item)) return null;
  let m = marca(item);
  let hijos = item.hijos.filter(esVisible);
  return {
    etiqueta: etiqueta(item),
    atajo: atajo(item),
    activo: estaActivo(item),
    marca: m ? (m.tipo === "checkmark" ? "check" : "radio") : null,
    marcado: m ? m.marcado : false,
    submenu: tieneSubmenu(item) ? hijos.map(h => aItem(menu, h)) : null,
    activar: () => menu._clic(item.id),
  };
}

/** Quita separadores al principio, al final y repetidos (las apps los dejan
 *  donde escondieron ítems). */
function limpiarSeparadores(items) {
  let fuera = [];
  for (let it of items) {
    if (!it) continue;
    if (it.separador && (!fuera.length || fuera[fuera.length - 1].separador)) continue;
    fuera.push(it);
  }
  while (fuera.length && fuera[fuera.length - 1].separador) fuera.pop();
  for (let it of fuera) if (it.submenu) it.submenu = limpiarSeparadores(it.submenu);
  return fuera;
}

/*
 * Lo que usa applet.js:
 *   let l = new LectorDbusmenu(servicio, ruta, () => rearmar());
 *   for (let t of await l.titulos()) {      // los de la barra
 *     await t.abrir();                       // al abrir el menú
 *     t.items();                             // [{separador} | {etiqueta, atajo, activo,
 *   }                                        //   marca, marcado, submenu, activar()}]
 *   l.destruir();
 * alCambiar llega una sola vez por ráfaga (las apps mandan decenas de señales
 * seguidas al cambiar de documento).
 */
var LectorDbusmenu = class LectorDbusmenu {
  constructor(servicio, ruta, alCambiar) {
    this.servicio = servicio;
    this.ruta = ruta;
    this._alCambiar = alCambiar;
    this._espera = 0;
    let con = Gio.DBus.session;
    this._senales = ["LayoutUpdated", "ItemsPropertiesUpdated"].map(nombre =>
      con.signal_subscribe(servicio, IFAZ_MENU, nombre, ruta, null, Gio.DBusSignalFlags.NONE,
        () => this._avisar()));
  }

  _avisar() {
    if (!this._alCambiar || this._abriendo) return; // AboutToShow dispara LayoutUpdated
    if (this._espera) GLib.source_remove(this._espera);
    this._espera = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 150, () => {
      this._espera = 0;
      this._alCambiar();
      return GLib.SOURCE_REMOVE;
    });
  }

  async _arbol(padre) {
    let r = await llamar(this.servicio, this.ruta, IFAZ_MENU, "GetLayout",
      new GLib.Variant("(iias)", [padre, -1, PROPS]), "(u(ia{sv}av))");
    return desempacar(r.get_child_value(1));
  }

  async _antesDeAbrir(id) {
    try {
      let r = await llamar(this.servicio, this.ruta, IFAZ_MENU, "AboutToShow", new GLib.Variant("(i)", [id]), "(b)");
      return r.get_child_value(0).get_boolean();
    } catch (e) {
      return false; // no todas lo implementan
    }
  }

  _evento(id, evento) {
    let hora = Math.floor(GLib.get_monotonic_time() / 1000) >>> 0;
    Gio.DBus.session.call(this.servicio, this.ruta, IFAZ_MENU, "Event",
      new GLib.Variant("(isvu)", [id, evento, new GLib.Variant("i", 0), hora]),
      null, Gio.DBusCallFlags.NONE, ESPERA_MS, null, null);
  }

  _clic(id) { this._evento(id, "clicked"); }

  /** Los títulos de la barra («File», «Edit»…). */
  async titulos() {
    let raiz;
    try { raiz = await this._arbol(0); } catch (e) { return []; }
    return raiz.hijos.filter(h => esVisible(h) && !esSeparador(h) && etiqueta(h)).map(h => {
      let items = limpiarSeparadores(h.hijos.filter(esVisible).map(x => aItem(this, x)));
      return {
        etiqueta: etiqueta(h),
        // Chrome, Firefox y Electron llenan el menú en AboutToShow; los
        // submenús de segundo nivel que lleguen vacíos se piden también.
        abrir: async () => {
          this._abriendo = true;
          try {
            await this._antesDeAbrir(h.id);
            this._evento(h.id, "opened");
            let sub = await this._arbol(h.id);
            for (let n of sub.hijos)
              if (tieneSubmenu(n) && !n.hijos.length && await this._antesDeAbrir(n.id))
                n.hijos = (await this._arbol(n.id)).hijos;
            items = limpiarSeparadores(sub.hijos.filter(esVisible).map(x => aItem(this, x)));
          } catch (e) {
            // se queda con lo que trajo titulos()
          } finally {
            this._abriendo = false;
          }
        },
        cerrar: () => this._evento(h.id, "closed"),
        items: () => items,
      };
    });
  }

  destruir() {
    if (this._espera) GLib.source_remove(this._espera);
    this._espera = 0;
    for (let id of this._senales) { try { Gio.DBus.session.signal_unsubscribe(id); } catch (e) {} }
    this._senales = [];
    this._alCambiar = null;
  }
};
