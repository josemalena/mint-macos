/*
 * Application Menu (macOS-style) — Cinnamon Applet
 * UUID: appmenu@macos
 *
 * What it does:
 * - Shows focused app name (WM_CLASS), fallback "Finder"
 * - Treats nemo-desktop as Finder
 * - Menu items, como el menú de la app en macOS:
 *    - About <App>     el About de la propia app si lo publica por D-Bus; si
 *                      no, un diálogo con PID, ejecutable y paquete
 *    - Preferences…    solo si la app lo publica en su menú
 *    - Hide <App> ⌘H, Hide Others ⌥⌘H, Show All: minimiza/restaura ventanas
 *    - Quit <App> ⌘Q   TERM y luego KILL al árbol de procesos de la ventana
 *
 * Notes:
 * - No dependency on imports.ui.windowTracker (some Cinnamon builds lack it).
 */

const Applet = imports.ui.applet;
const PopupMenu = imports.ui.popupMenu;
const Util = imports.misc.util;
const Settings = imports.ui.settings;
const GLib = imports.gi.GLib;
const St = imports.gi.St;
const ModalDialog = imports.ui.modalDialog;
const Gio = imports.gi.Gio;
const Cinnamon = imports.gi.Cinnamon;
const Meta = imports.gi.Meta;
const Clutter = imports.gi.Clutter;
const Main = imports.ui.main;

// «About» de la propia app. Si la ventana publica su menú por D-Bus con el
// protocolo de GTK (nemo-mac, Fynder, cualquier GtkApplication con menubar),
// se busca el ítem About/Acerca de en ese menú y se activa su acción, igual
// que en macOS; si no hay menú pero la app exporta la acción app.about, se usa
// esa. Devuelve true si la app se encargó del diálogo.
const RE_ABOUT = /\b(about|acerca de)\b/i;   // «contiene», no «empieza con»
const DBUS_TIMEOUT = 400;

// Un patrón puede traer su «preferido»: entre varios ítems que lo cumplen se
// toma el que cumple el preferido («About Firefox») antes que uno que solo
// contiene la palabra («Open About Config»).
const PREFERIDOS = new Map([[RE_ABOUT, /^(about|acerca de)\b/i]]);

function elegirItem(candidatos, patron) {
  let pref = PREFERIDOS.get(patron);
  return (pref && candidatos.find(c => pref.test(c.etiqueta))) || candidatos[0] || null;
}

// ── El servicio del menú (org.mintmacos.Menu1, nativo/menu/DBUS.md) ─────────────────────────────────────────────────
// Buscar el ítem de About, Preferences… o Quit en el menú de la app (y leer su menú propio) lo hace el servicio, sin bloquear
// a Cinnamon. Si nadie tiene el nombre, se cae a las lecturas síncronas de siempre, más abajo.
const MENU1 = "org.mintmacos.Menu1";
const RUTA_MENU1 = "/org/mintmacos/Menu1";

function m1(metodo, params, tipo) {
  return new Promise((resolver, rechazar) => {
    Gio.DBus.session.call(MENU1, RUTA_MENU1, MENU1, metodo, params, tipo ? new GLib.VariantType(tipo) : null,
      Gio.DBusCallFlags.NONE, 4000, null, (con, res) => {
        try { resolver(con.call_finish(res)); } catch (e) { rechazar(e); }
      });
  });
}

function sinServicio(e) {
  let m = String(e && e.message);
  return m.indexOf("ServiceUnknown") >= 0 || m.indexOf("NameHasNoOwner") >= 0 || m.indexOf("not provided by any") >= 0;
}

function xidDe(w) {
  try { return w.get_xwindow(); } catch (e) { return 0; }
}

// Todos los ítems del menú de la ventana (el de la barra y el propio de la app); un segundo pedido en 1,5 s reutiliza el primero.
let _cacheItems = { xid: 0, cuando: 0, promesa: null };
function itemsServicio(w) {
  let xid = xidDe(w), ahora = GLib.get_monotonic_time();
  if (_cacheItems.promesa && _cacheItems.xid === xid && ahora - _cacheItems.cuando < 1500000) return _cacheItems.promesa;
  let p = m1("Buscar", new GLib.Variant("(us)", [xid, ""]), "(aa{sv})").then(r => r.recursiveUnpack()[0]);
  _cacheItems = { xid, cuando: ahora, promesa: p };
  p.catch(() => { if (_cacheItems.promesa === p) _cacheItems.promesa = null; });
  return p;
}

// El ítem que cumple el patrón (con el preferido de elegirItem), o null.
async function itemPorPatron(w, patron) {
  let items = await itemsServicio(w);
  let candidatos = items.filter(i => i.activo !== false && patron.test(i.etiqueta || ""))
    .map(i => ({ etiqueta: i.etiqueta, it: i }));
  let e = elegirItem(candidatos, patron);
  return e ? e.it : null;
}

function activarItemServicio(w, it) {
  return m1("Activar", new GLib.Variant("(uus)", [xidDe(w), it.version, it.id]), "(b)").then(r => r.deepUnpack()[0]);
}

function llamar(bus, ruta, iface, metodo, args, tipo) {
  return Gio.DBus.session.call_sync(bus, ruta, iface, metodo, args,
    tipo ? new GLib.VariantType(tipo) : null, Gio.DBusCallFlags.NONE, DBUS_TIMEOUT, null);
}

function buscarEnMenu(bus, ruta, patron) {
  let pendientes = [0], vistos = new Set(), candidatos = [], hallado = null;
  let pref = PREFERIDOS.get(patron);
  let bastaCon = () => candidatos.length && (!pref || candidatos.some(c => pref.test(c.etiqueta)));
  try {
    for (let vuelta = 0; vuelta < 6 && pendientes.length && !bastaCon(); vuelta++) {
      let grupos = pendientes.filter(g => !vistos.has(g));
      pendientes = [];
      if (!grupos.length) break;
      grupos.forEach(g => vistos.add(g));
      let r = llamar(bus, ruta, "org.gtk.Menus", "Start",
        new GLib.Variant("(au)", [grupos]), "(a(uuaa{sv}))").recursiveUnpack()[0];
      for (let [, , items] of r) {
        for (let it of items) {
          for (let enlace of [":submenu", ":section"])
            if (it[enlace]) pendientes.push(it[enlace][0]);
          let etiqueta = (it.label || "").replace(/_/g, "");
          if (it.action && patron.test(etiqueta))
            candidatos.push({ etiqueta, accion: it.action, objetivo: it.target });
        }
      }
    }
  } catch (e) {}
  try {
    llamar(bus, ruta, "org.gtk.Menus", "End", new GLib.Variant("(au)", [[...vistos]]), null);
  } catch (e) {}
  hallado = elegirItem(candidatos, patron);
  return hallado ? { accion: hallado.accion, objetivo: hallado.objetivo } : null;
}

function activarAccion(bus, ruta, nombre, objetivo) {
  let params = [];
  if (objetivo !== undefined && objetivo !== null) {
    try { params = [GLib.Variant.new_string(String(objetivo))]; } catch (e) {}
  }
  // Activate no responde hasta que la acción termina, y el About de muchas apps
  // (Drawing, xed…) es un diálogo modal: la llamada tarda lo que el diálogo siga
  // abierto. Con una llamada síncrona vencía el timeout, se daba el About por
  // fallido y salía además el diálogo de respaldo. Se manda sin esperar.
  Gio.DBus.session.call(bus, ruta, "org.gtk.Actions", "Activate",
    new GLib.Variant("(sava{sv})", [nombre, params, {}]), null,
    Gio.DBusCallFlags.NONE, -1, null,
    (con, res) => { try { con.call_finish(res); } catch (e) {} });
}

// ── Atajos por app (System Preferences ▸ Keyboard ▸ Shortcuts ▸ App Shortcuts) ──────────────────────────────────────────────
// ~/.config/mint-macos/atajos-apps.json: {"atajos": [{"app": "*" | id del .desktop, "titulo": "Print…", "atajo": "⇧⌘P"}]}. Cada uno
// dice «con este atajo, activa el comando de menú con este nombre en esa app»: se busca por org.mintmacos.Menu1 en el menú de la
// ventana al frente y se activa. Los atajos solo se agarran mientras la app que toca tiene el foco (si no, un Ctrl+P de Cinnamon
// se tragaría el de todas las demás).
//
// El atajo se guarda como se escribe en la Mac («⇧⌘P») y se traduce a lo que Cinnamon ve DESPUÉS de keyd (/etc/keyd/default.conf):
// ⌘ + una tecla de la capa [meta] sale como Ctrl+tecla; ⌘ + una sin regla (h, m, Tab, Espacio, 1…9) sigue como Super; ⌥ es Alt;
// ⌃⌘ + tecla llega como Ctrl+Super.
const RUTA_ATAJOS_APPS = GLib.build_filenamev([GLib.get_user_config_dir(), "mint-macos", "atajos-apps.json"]);
const META_A_CTRL = new Set("abcdefgijklnopqrstuvwxyz0".split("").concat(["slash", "comma", "equal", "minus"]));
const NOMBRES_TECLA = { "/": "slash", ",": "comma", "=": "equal", "-": "minus", ".": "period", "[": "bracketleft", "]": "bracketright",
  ";": "semicolon", "'": "apostrophe", "`": "grave", "\\": "backslash", "␣": "space", "Space": "space", "↩": "Return", "⇥": "Tab",
  "⎋": "Escape", "⌫": "BackSpace", "⌦": "Delete", "←": "Left", "→": "Right", "↑": "Up", "↓": "Down", "⇞": "Page_Up", "⇟": "Page_Down" };

/** «⇧⌘P» → «<Control><Shift>p» (lo que Cinnamon recibe de keyd); null si no se entiende. */
function atajoMacAAccel(texto) {
  let mods = { ctrl: false, cmd: false, alt: false, shift: false };
  let resto = texto.trim();
  for (let c of Array.from(resto)) {
    if (c === "⌃") mods.ctrl = true; else if (c === "⌘") mods.cmd = true;
    else if (c === "⌥") mods.alt = true; else if (c === "⇧") mods.shift = true; else break;
    resto = resto.slice(c.length);
  }
  if (!resto) return null;
  let tecla = NOMBRES_TECLA[resto] || (/^F\d{1,2}$/.test(resto) ? resto : resto.toLowerCase());
  let out = "";
  let control = mods.ctrl, sup = false;
  if (mods.cmd) {
    if (mods.ctrl) sup = true;                          // ⌃⌘: capa compuesta, llega como Ctrl+Super
    else if (META_A_CTRL.has(tecla)) control = true;     // ⌘ + tecla de la capa [meta]: Ctrl
    else sup = true;                                     // sin regla: sigue como Super
  }
  if (control) out += "<Control>";
  if (sup) out += "<Super>";
  if (mods.alt) out += "<Alt>";
  if (mods.shift) out += "<Shift>";
  return out + tecla;
}

function normalizarTitulo(t) {
  return String(t).replace(/[…]|\.\.\./g, "").replace(/\s+/g, " ").trim().toLowerCase();
}

function leerAtajosApps() {
  try {
    let [ok, bytes] = GLib.file_get_contents(RUTA_ATAJOS_APPS);
    if (!ok) return [];
    let d = JSON.parse(imports.byteArray.toString(bytes));
    return (d.atajos || []).filter(e => e && e.titulo && e.atajo && atajoMacAAccel(e.atajo));
  } catch (e) { return []; }
}

// Los ítems estándar del menú de la app (About, Preferences…, Services, Hide, Hide Others, Show All, Quit) salen del perfil de la versión
// de macOS escogida (perfil.js) por su acción de AppKit; sin perfil, el texto de siempre (Catalina).
function textoEstandar(accion, nombre, defecto) {
  try {
    let P = imports.ui.appletManager.applets["appmenu@macos"].perfil;
    let t = P.texto(P.item(P.menuEstandar("app"), accion), { "%@": nombre });
    return t || defecto;
  } catch (e) { return defecto; }
}

function atajoEstandar(accion, defecto) {
  try {
    let P = imports.ui.appletManager.applets["appmenu@macos"].perfil;
    let it = P.item(P.menuEstandar("app"), accion);
    return it && it.atajo !== undefined ? it.atajo : defecto;
  } catch (e) { return defecto; }
}

const RE_PREFS = /^(preferences|preferencias|settings|ajustes)\b/i;
const RE_QUIT = /^(quit|exit|salir|close all windows|cerrar todas las ventanas)\b/i;

// Las apps que publican por dbusmenu (Edge, Firefox, Thunderbird, Qt,
// LibreOffice con appmenu-gtk-module): se busca el ítem en su árbol con el
// lector del menú global (globalmenu@macos/dbusmenu.js). Devuelve una
// función que lo activa, o null.
async function buscarEnDbusmenu(w, patron) {
  let D = null;
  try { D = imports.ui.appletManager.applets["globalmenu@macos"].dbusmenu; } catch (e) {}
  if (!D) return null;
  let xid = 0;
  try { xid = w.get_xwindow(); } catch (e) {}
  let reg = new D.Registrador(() => {});
  let par = null;
  try { par = await reg.menuDe(xid); } finally { reg.destruir(); }
  if (!par) return null;
  let lector = new D.LectorDbusmenu(par[0], par[1], null);
  let hallado = null, candidatos = [];
  let pref = PREFERIDOS.get(patron);
  let bastaCon = () => candidatos.length && (!pref || candidatos.some(c => pref.test(c.etiqueta)));
  let buscar = (items) => {
    for (let it of items || []) {
      if (it.submenu) buscar(it.submenu);
      else if (!it.separador && it.activo !== false && patron.test(it.etiqueta || ""))
        candidatos.push({ etiqueta: it.etiqueta || "", it });
    }
  };
  try {
    for (let t of await lector.titulos()) {
      buscar(t.items());
      if (bastaCon()) break;
      // Chromium y Electron llenan cada menú al abrirlo.
      await t.abrir(); t.cerrar();
      buscar(t.items());
      if (bastaCon()) break;
    }
    let elegido = elegirItem(candidatos, patron);
    hallado = elegido ? elegido.it : null;
  } catch (e) {
    global.logError("appmenu@macos: dbusmenu: " + e);
  }
  if (!hallado) { lector.destruir(); return null; }
  return () => { hallado.activar(); GLib.timeout_add(GLib.PRIORITY_DEFAULT, 2000, () => { lector.destruir(); return GLib.SOURCE_REMOVE; }); };
}

// Activa el primer ítem del menú publicado por la app cuya etiqueta cumpla
// el patrón. Devuelve true si lo encontró y lo activó.
function activarDeMenu(w, patron) {
  let bus, rutaMenu, rutaApp, rutaVentana;
  try {
    bus = w.get_gtk_unique_bus_name();
    rutaMenu = w.get_gtk_menubar_object_path();
    rutaApp = w.get_gtk_application_object_path();
    rutaVentana = w.get_gtk_window_object_path();
  } catch (e) { return false; }
  if (!bus || !rutaMenu) return false;
  try {
    let a = buscarEnMenu(bus, rutaMenu, patron);
    if (!a) return false;
    let p = a.accion.indexOf(".");
    let prefijo = a.accion.slice(0, p), nombre = a.accion.slice(p + 1);
    let ruta = prefijo === "win" ? rutaVentana : prefijo === "app" ? rutaApp : null;
    if (!ruta) return false;
    activarAccion(bus, ruta, nombre, a.objetivo);
    return true;
  } catch (e) {
    global.logError("appmenu@macos: menú de la app: " + e);
    return false;
  }
}

// El menú propio de la app (About, Preferences…, Empty Trash…) si la app lo
// publica como primer submenú de su barra con el atributo
// x-constanza-app-menu = true (Fynder, acordado con su sesión). Devuelve una
// lista plana: {etiqueta, accion, objetivo, activo} o {separador: true}.
function leerMenuDeApp(w) {
  let bus, ruta, rutaApp, rutaVentana;
  try {
    bus = w.get_gtk_unique_bus_name(); ruta = w.get_gtk_menubar_object_path();
    rutaApp = w.get_gtk_application_object_path(); rutaVentana = w.get_gtk_window_object_path();
  } catch (e) { return null; }
  if (!bus || !ruta) return null;
  let grupos = {}, pedidos = new Set();
  let pedir = (gs) => {
    gs = gs.filter(g => !pedidos.has(g));
    if (!gs.length) return;
    gs.forEach(g => pedidos.add(g));
    let r = llamar(bus, ruta, "org.gtk.Menus", "Start", new GLib.Variant("(au)", [gs]), "(a(uuaa{sv}))").recursiveUnpack()[0];
    for (let [g, m, items] of r) grupos[g + ":" + m] = items;
  };
  let lista = null;
  try {
    pedir([0]);
    let raiz = (grupos["0:0"] || [])[0];
    if (!raiz || raiz["x-constanza-app-menu"] !== true || !raiz[":submenu"]) return null;
    let [g0, m0] = raiz[":submenu"];
    // Las secciones pueden estar en otros grupos: se piden hasta tenerlas.
    for (let vuelta = 0; vuelta < 4; vuelta++) {
      pedir([g0]);
      let faltan = [];
      for (let k in grupos) for (let it of grupos[k]) if (it[":section"] && !grupos[it[":section"].join(":")]) faltan.push(it[":section"][0]);
      if (!faltan.length) break;
      pedir(faltan);
    }
    lista = [];
    let estado = (accion) => {
      let p = accion.indexOf("."), pref = accion.slice(0, p), n = accion.slice(p + 1);
      let r = pref === "win" ? rutaVentana : pref === "app" ? rutaApp : null;
      if (!r) return false;
      try {
        return llamar(bus, r, "org.gtk.Actions", "Describe", new GLib.Variant("(s)", [n]), "((bgav))").deepUnpack()[0][0];
      } catch (e) { return true; }
    };
    let plano = (clave) => {
      for (let it of grupos[clave] || []) {
        if (it[":section"]) {
          if (lista.length && !lista[lista.length - 1].separador) lista.push({ separador: true });
          plano(it[":section"].join(":"));
        } else if (it.label && it.action) {
          lista.push({ etiqueta: it.label.replace(/_/g, ""), accion: it.action, objetivo: it.target, activo: estado(it.action) });
        }
      }
    };
    plano(g0 + ":" + m0);
    while (lista.length && lista[lista.length - 1].separador) lista.pop();
  } catch (e) {
    global.logError("appmenu@macos: menú de la app: " + e);
    lista = null;
  }
  try { llamar(bus, ruta, "org.gtk.Menus", "End", new GLib.Variant("(au)", [[...pedidos]]), null); } catch (e) {}
  return lista && lista.length ? lista : null;
}

function activarEntrada(w, e) {
  if (e.id !== undefined) {
    activarItemServicio(w, e).catch(err => global.logError("appmenu@macos: " + err));
    return;
  }
  try {
    let bus = w.get_gtk_unique_bus_name();
    let p = e.accion.indexOf("."), pref = e.accion.slice(0, p), n = e.accion.slice(p + 1);
    let r = pref === "win" ? w.get_gtk_window_object_path() : pref === "app" ? w.get_gtk_application_object_path() : null;
    if (bus && r) activarAccion(bus, r, n, e.objetivo);
  } catch (err) { global.logError("appmenu@macos: " + err); }
}

// ¿La app publica ese ítem? (para enseñar Preferences… solo si existe)
function menuTiene(w, patron) {
  try {
    let bus = w.get_gtk_unique_bus_name(), ruta = w.get_gtk_menubar_object_path();
    return !!(bus && ruta && buscarEnMenu(bus, ruta, patron));
  } catch (e) { return false; }
}

// Ventanas normales de la sesión (sin escritorio, paneles ni diálogos sueltos).
function ventanasNormales() {
  return global.get_window_actors().map(a => a.meta_window).filter(w =>
    w && w.get_window_type() === Meta.WindowType.NORMAL && !w.is_skip_taskbar());
}
function appDe(w) {
  try { return Cinnamon.WindowTracker.get_default().get_window_app(w); } catch (e) { return null; }
}
// macOS enseña el nombre propio de la app («Firefox»), no el descriptivo que
// traen muchos .desktop («Firefox Web Browser», «Thunderbird Mail»): se le
// quita el genérico del final, si lo hay. Si no queda nada («Text Editor»,
// que es solo genérico), se deja entero.
function nombreCorto(app) {
  let n = (app.get_name() || "").trim();
  let corto = n;
  try {
    let g = (app.get_app_info().get_generic_name() || "").trim();
    if (g && corto.toLowerCase().endsWith(" " + g.toLowerCase())) corto = corto.slice(0, -(g.length + 1));
  } catch (e) {}
  corto = corto.replace(/\s+(web browser|browser|mail|email|e-mail|client)$/i, "").trim();
  return corto || n;
}

function mismaApp(a, b) {
  let x = appDe(a), y = appDe(b);
  if (x && y) return x === y;
  return getWmClass(a) === getWmClass(b);
}

function abrirAboutDeLaApp(w) {
  let bus, rutaMenu, rutaApp, rutaVentana;
  try {
    bus = w.get_gtk_unique_bus_name();
    rutaMenu = w.get_gtk_menubar_object_path();
    rutaApp = w.get_gtk_application_object_path();
    rutaVentana = w.get_gtk_window_object_path();
  } catch (e) { return false; }
  if (!bus) return false;
  try {
    if (rutaMenu) {
      let a = buscarEnMenu(bus, rutaMenu, RE_ABOUT);
      if (a) {
        let p = a.accion.indexOf(".");
        let prefijo = a.accion.slice(0, p), nombre = a.accion.slice(p + 1);
        let ruta = prefijo === "win" ? rutaVentana : prefijo === "app" ? rutaApp : null;
        if (ruta) { activarAccion(bus, ruta, nombre, a.objetivo); return true; }
      }
    }
    if (rutaApp) {
      let lista = llamar(bus, rutaApp, "org.gtk.Actions", "List", null, "(as)").deepUnpack()[0];
      if (lista.indexOf("about") >= 0) { activarAccion(bus, rutaApp, "about", null); return true; }
    }
  } catch (e) {
    global.logError("appmenu@macos: About de la app: " + e);
  }
  return false;
}

// Apps sin ítem About en el menú pero con la acción app.about (GApplication): se pregunta sin bloquear. Promesa: true si la activó.
function abrirAboutPorAccion(w) {
  return new Promise(resolver => {
    let bus = null, rutaApp = null;
    try { bus = w.get_gtk_unique_bus_name(); rutaApp = w.get_gtk_application_object_path(); } catch (e) {}
    if (!bus || !rutaApp) { resolver(false); return; }
    Gio.DBus.session.call(bus, rutaApp, "org.gtk.Actions", "List", null, new GLib.VariantType("(as)"),
      Gio.DBusCallFlags.NONE, DBUS_TIMEOUT, null, (con, res) => {
        try {
          let lista = con.call_finish(res).deepUnpack()[0];
          if (lista.indexOf("about") >= 0) { activarAccion(bus, rutaApp, "about", null); resolver(true); return; }
        } catch (e) {}
        resolver(false);
      });
  });
}

// Los navegadores de Chromium no publican «About» en su menú (Edge solo trae
// «Help center»): su About es una página propia. Se abre en una pestaña con el
// mismo ejecutable (si el navegador ya corre, la abre en la instancia viva).
const ABOUT_CHROMIUM = new Map([
  ["msedge", "edge://settings/help"],
  ["chrome", "chrome://settings/help"],
  ["chromium", "chrome://settings/help"],
  ["brave", "brave://settings/help"],
  ["vivaldi-bin", "vivaldi://about"],
  ["opera", "opera://about"],
]);

function abrirAboutChromium(w) {
  let pid = 0;
  try { pid = w.get_pid(); } catch (e) {}
  if (pid <= 0) return false;
  let exe = "";
  try { exe = GLib.file_read_link(`/proc/${pid}/exe`); } catch (e) { return false; }
  let url = ABOUT_CHROMIUM.get(GLib.path_get_basename(exe));
  if (!url) return false;
  try {
    GLib.spawn_async(null, [exe, url], null, GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.STDOUT_TO_DEV_NULL | GLib.SpawnFlags.STDERR_TO_DEV_NULL, null);
    return true;
  } catch (e) {
    global.logError("appmenu@macos: About de Chromium: " + e);
    return false;
  }
}

function spawn(cmd) {
  Util.spawnCommandLine(cmd);
}

function shellQuote(s) {
  return "'" + String(s).replace(/'/g, "'\"'\"'") + "'";
}

function readFileTrim(path) {
  try {
    let [ok, bytes] = GLib.file_get_contents(path);
    if (!ok) return "";
    return (imports.byteArray.toString(bytes) || "").trim();
  } catch (e) {
    return "";
  }
}

function getWmClass(w) {
  try {
    if (w.get_wm_class_instance) {
      let inst = w.get_wm_class_instance();
      if (inst && inst.length) return inst;
    }
  } catch (e) {}
  try {
    if (w.get_wm_class) {
      let c = w.get_wm_class();
      if (c && c.length) return c;
    }
  } catch (e) {}
  return "";
}

function prettifyName(s) {
  if (!s) return "";
  if (s === s.toLowerCase()) return s.charAt(0).toUpperCase() + s.slice(1);
  return s;
}

function procNameFromPid(pid) {
  let name = readFileTrim(`/proc/${pid}/comm`);
  if (name) return name;
  try {
    let exe = GLib.file_read_link(`/proc/${pid}/exe`);
    if (exe) {
      let parts = exe.split("/");
      return parts[parts.length - 1] || "";
    }
  } catch (e) {}
  return "";
}

// Los programas internos de mint-macos (About, Force Quit, los diálogos de sesión, Gatekeeper, ⇧⌘5) corren en
// binarios sin nombre de app: no tienen menú propio y la barra sigue con la app que estaba al frente (lo dijo José
// con About This Mac, 18-10-2026; con los demás todavía no hay captura, y mientras tanto hacen lo mismo).
const RE_INTERNAS = /^mac-(ventanas|acerca|gatekeeper|sesion|forcequit|captura-herramienta)/;
let ultimaReal = null;

function esInterna(w) {
  try { return RE_INTERNAS.test((getWmClass(w) || "").toLowerCase()); }
  catch (e) { return false; }
}

function ventanaViva(w) {
  try {
    for (let a of global.get_window_actors()) if (a.meta_window === w) return true;
  } catch (e) {}
  return false;
}

function getFocusedWindow() {
  try {
    let w = global.display.get_focus_window ? global.display.get_focus_window() : null;
    if (w && esLanzador(w)) return ventanaDelEscritorioDeFynder();
    if (w && esInterna(w)) return (ultimaReal && ventanaViva(ultimaReal)) ? ultimaReal : ventanaDelEscritorioDeFynder();
    if (w) ultimaReal = w;
    // Sin ventana con foco (al entrar, o cerrada la última) es Fynder, no «Finder»: igual que con el escritorio enfocado.
    // Con un menú de la barra abierto el foco también es nulo y se deja como estaba.
    if (!w && global.stage_input_mode === Cinnamon.StageInputMode.NORMAL) return ventanaDelEscritorioDeFynder();
    return w;
  }
  catch (e) { return null; }
}

function isDesktopWindow(w) {
  try { return (w && w.get_window_type && w.get_window_type() === 6); }
  catch (e) { return false; }
}

// El escritorio de Fynder es una ventana más de Fynder para el menú (publica su
// barra y su menú de aplicación), pero como el Finder no se «sale» de él:
// Quit Finder va apagado, y con él no se puede tumbar el escritorio.
function esEscritorioDeFynder(w) {
  try { return !!w && (getWmClass(w) || "").toLowerCase() === "nemo-desktop"; }
  catch (e) { return false; }
}

// Spotlyte (el lanzador) no es «otro programa» para la barra: como Spotlight en macOS, no cambia el
// menú. Mientras tiene el foco, y siempre que no haya programa, la barra es la de Fynder: se usa
// la ventana del escritorio de Fynder en su lugar.
function esLanzador(w) {
  try {
    let c = (getWmClass(w) || "").toLowerCase();
    return c === "ulauncher" || c === "spotlyte";
  } catch (e) { return false; }
}

function ventanaDelEscritorioDeFynder() {
  try {
    for (let a of global.get_window_actors()) {
      let m = a.meta_window;
      if (m && esEscritorioDeFynder(m)) return m;
    }
  } catch (e) {}
  return null;
}

function getFocusedPid() {
  let w = getFocusedWindow();
  if (!w || isDesktopWindow(w)) return 0;
  try { return w.get_pid ? w.get_pid() : 0; } catch (e) { return 0; }
}

// Último recurso del Quit: TERM al proceso y sus descendientes y, a los
// 1.2 s, KILL a los que sigan vivos. Los descendientes se leen de /proc (el
// guion de bash de antes se quedaba en un bucle y no mataba nada).
function descendientes(raiz) {
  let hijos = {};
  try {
    let dir = Gio.File.new_for_path("/proc");
    let en = dir.enumerate_children("standard::name", Gio.FileQueryInfoFlags.NONE, null);
    let info;
    while ((info = en.next_file(null))) {
      let n = info.get_name();
      if (!/^[0-9]+$/.test(n)) continue;
      let stat = readFileTrim(`/proc/${n}/stat`);
      let m = stat.match(/\)\s+\S\s+(\d+)/);   // el ppid va después de «(comm) estado»
      if (!m) continue;
      (hijos[m[1]] = hijos[m[1]] || []).push(Number(n));
    }
  } catch (e) {}
  let todos = [], cola = [Number(raiz)];
  while (cola.length) {
    let p = cola.shift();
    if (todos.indexOf(p) >= 0) continue;
    todos.push(p);
    for (let h of hijos[String(p)] || []) cola.push(h);
  }
  return todos;
}

function killProcessTree(pid) {
  const raiz = Number(pid);
  if (!raiz || raiz <= 1) return;
  let pids = descendientes(raiz).map(String);
  try { Util.spawn(["kill", "-TERM", ...pids]); } catch (e) {}
  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1200, () => {
    let vivos = pids.filter(p => GLib.file_test(`/proc/${p}`, GLib.FileTest.EXISTS));
    if (vivos.length) { try { Util.spawn(["kill", "-KILL", ...vivos]); } catch (e) {} }
    return GLib.SOURCE_REMOVE;
  });
}


// El diálogo de respaldo del About: un ModalDialog normal que se llena aquí.
// No se hereda de él: en este Cinnamon es una clase GObject, y una subclase
// registrada choca al recargar el applet («already registered»).
function AboutAppDialog(title, bodyText) {
  let dlg = new ModalDialog.ModalDialog({ styleClass: null });
  dlg.contentLayout.add(new St.Label({ text: title, style_class: "dialog-title", x_align: St.Align.START }));
  let scroll = new St.ScrollView({ style_class: "vfade", overlay_scrollbars: true });
  let label = new St.Label({ text: bodyText, style_class: "dialog-description", x_align: St.Align.START });
  label.clutter_text.line_wrap = true;
  label.clutter_text.selectable = true;
  scroll.add_actor(label);
  dlg.contentLayout.add(scroll);
  dlg.setButtons([{ label: "OK", action: () => dlg.close(), key: 0 }]);
  return dlg;
}

// El separador de los menús: el de Catalina (2 px, #45484b, bloque de 12) o, con un tema Samaná (Monterey), el medido: 1 px en un bloque de 11 con
// 14 px de margen a cada lado (10 de margen más los 4 de relleno de la caja) y negro 0.10 / blanco 0.14 según el tema (menus/INFORME.md, cambio 4).
function estiloSeparador() {
  let tema = "";
  try { tema = new imports.gi.Gio.Settings({ schema_id: "org.cinnamon.theme" }).get_string("name"); } catch (e) {}
  if (tema.indexOf("Samana") !== 0) {
    return { fila: "padding: 7px 0 3px 0; margin: 0; min-height: 0; spacing: 0;",
             linea: "height: 2px; padding: 0; margin: 0; border-bottom-width: 0; -margin-horizontal: 0px; -gradient-height: 2px; -gradient-start: #45484b; -gradient-end: #45484b;" };
  }
  let c = tema.indexOf("Claro") >= 0 ? "rgba(0, 0, 0, 0.10)" : "rgba(255, 255, 255, 0.14)";
  return { fila: "padding: 5px 0 5px 0; margin: 0 10px; min-height: 0; spacing: 0;",
           linea: `height: 1px; padding: 0; margin: 0; border-bottom-width: 0; -margin-horizontal: 0px; -gradient-height: 1px; -gradient-start: ${c}; -gradient-end: ${c};` };
}

class AppMenuApplet extends Applet.TextApplet {
  constructor(metadata, orientation, panel_height, instance_id) {
    super(orientation, panel_height, instance_id);

    this.settings = new Settings.AppletSettings(this, metadata.uuid, instance_id);
    this.settings.bind("fallback-label", "fallbackLabel", this._updateLabel.bind(this));
    this.settings.bind("button-padding", "buttonPadding", this._applyLabelStyle.bind(this));

    this.set_applet_tooltip("Application Menu");

    this.menuManager = new PopupMenu.PopupMenuManager(this);
    this.menu = new Applet.AppletPopupMenu(this, orientation);
    // El mismo aspecto que el menú Apple: la clase común del tema Constanza.
    this.menu.actor.add_style_class_name("constanza-menu");
    this.menu.box.add_style_class_name("constanza-menu-box");
    this.menuManager.addMenu(this.menu);

    this._buildMenu();

    // ⌘H, ⌥⌘H y ⌘Q: keyd deja pasar ⌘ como Super y Cinnamon no usa esas
    // teclas. ⌘Q es el Quit del menú para TODAS las apps: muchas (Nemo,
    // Fynder, Edge) no tienen un atajo de salir que keyd pueda traducir.
    this._atajos = [
      ["appmenu-macos-ocultar", "<Super>h", () => this._ocultarApp()],
      ["appmenu-macos-ocultar-otras", "<Super><Alt>h", () => this._ocultarOtras()],
      ["appmenu-macos-salir", "<Super>q", () => this._salirDeApp()],
    ];
    for (let [n, k, f] of this._atajos) Main.keybindingManager.addHotKey(n, k, f);
    this._applyLabelStyle();
    this._updateLabel();

    // Update label + menu texts on focus change
    this._focusSig = 0;
    this._iniciarAtajosApps();
    try {
      this._focusSig = global.display.connect("notify::focus-window", () => {
        this._updateLabel();
        this._updateMenuLabels();
        this._actualizarAtajosApps();
      });
      // El escritorio de Fynder puede salir después que la barra, al entrar.
      this._creadaSig = global.display.connect("window-created", () => {
        GLib.timeout_add(GLib.PRIORITY_DEFAULT, 400, () => { this._updateLabel(); this._updateMenuLabels(); return GLib.SOURCE_REMOVE; });
      });
    } catch (e) {
      this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
        this._updateLabel();
        this._updateMenuLabels();
        return true;
      });
    }

    this.menu.connect("open-state-changed", (_m, open) => {
      if (open) this._updateMenuLabels(true);
    });
  }

  // El relleno va en el botón, no en la etiqueta: así el resaltado empieza y
  // termina 10 px antes y después del nombre, como en la barra de macOS. Va
  // en línea porque el .applet-box del tema le gana a un stylesheet. La
  // fuente también: la barra va en SF aunque el shell use otra.
  _applyLabelStyle() {
    try {
      let px = Number(this.buttonPadding ?? 10);
      // A la derecha 4 px menos: el primer título del menú global trae los
      // suyos, y en la Mac hay 20 px de la app a File. El nombre va en negrita: 600 más el grado de la SF da lo de la Mac («Finder»
      // 44 px y 44 883 de tinta, contra 43 y 50 103 allá).
      this.actor.set_style(`padding-left: ${px}px; padding-right: ${Math.max(0, px - 4)}px;`);
      this._applet_label.set_style('padding-left: 0; padding-right: 0; font-family: ".SF NS", sans-serif; font-size: 10pt; font-weight: 600;');   // el color lo da el tema (blanco en oscuro, #1d1d1f en claro)
    } catch (e) {}
  }

  _getFocusedAppName() {
    let fallback = (this.fallbackLabel && this.fallbackLabel.length) ? this.fallbackLabel : "Finder";

    let w = getFocusedWindow();
    if (!w || isDesktopWindow(w)) return fallback;

    let cls = getWmClass(w);
    if (!cls) return fallback;

    let norm = cls.toLowerCase();
    // El escritorio de Fynder se llama Fynder, no «Finder» (decisión de José,
    // 13-10-2026): es el nombre de la app, y así lo dicen About/Hide/Quit.
    if (norm === "nemo-desktop") return "Fynder";

    // El nombre de la app como lo conoce Cinnamon (su .desktop): «Microsoft
    // Edge», no la clase de la ventana, que en Chromium con otro perfil trae
    // la ruta del perfil («microsoft-edge (/tmp/…)»).
    try {
      let app = appDe(w);
      if (app && !app.is_window_backed()) {
        let n = nombreCorto(app);
        if (n) return n;
      }
    } catch (e) {}
    return prettifyName(cls.replace(/\s*\(.*\)\s*$/, ""));
  }

  _updateLabel() {
    this.set_applet_label(this._getFocusedAppName());
  }

  // El menú de la app como en macOS: About, Preferences… (si la app lo
  // publica), Hide, Hide Others, Show All y Quit. Hide y compañía los hace
  // Cinnamon minimizando ventanas; no hace falta la app.
  _buildMenu(propio) {
    // Sin argumento: se arma el menú de siempre y, aparte, se le pide su menú propio al servicio (sin bloquear).
    let cargar = propio === undefined;
    if (propio === undefined) propio = null;
    this.menu.removeAll();
    let item = (texto, atajo, accion) => {
      let it = new PopupMenu.PopupMenuItem(texto);
      if (atajo) {
        it.addActor(new St.Label({ text: atajo, y_align: Clutter.ActorAlign.CENTER,
                                   style: "color: rgba(128,128,132,0.95); padding-left: 24px;" }),
                    { align: St.Align.END });
      }
      it.connect("activate", () => { this.menu.close(); accion(); });
      this.menu.addMenuItem(it);
      return it;
    };
    // Separador como el de macOS (medido por la sesión de la barra en c28): el
    // renglón sin el relleno de los demás y la línea de 2 px de borde a borde.
    let sep = () => {
      let s = new PopupMenu.PopupSeparatorMenuItem();
      let est = estiloSeparador();
      s.actor.set_style(est.fila);
      s._drawingArea.set_style(est.linea);
      this.menu.addMenuItem(s); return s;
    };

    let name = this._getFocusedAppName();
    let w = getFocusedWindow();
    this._menuPropio = !!propio;
    if (propio) {
      // La app trae su menú (About, Preferences…, Empty Trash…): va tal cual,
      // y aquí se le suman Hide y Quit, que hace Cinnamon.
      this.aboutItem = null; this.prefsItem = null; this.prefsSep = null;
      for (let e of propio) {
        if (e.separador) { sep(); continue; }
        let atajo = RE_PREFS.test(e.etiqueta) ? "⌘," : "";
        let it = item(e.etiqueta, atajo, () => activarEntrada(w, e));
        it.setSensitive(e.activo !== false);
      }
    } else {
      this.aboutItem = item(textoEstandar("orderFrontStandardAboutPanel:", name, `About ${name}`), "", () => this._showAboutDialog());
      this.prefsSep = sep();
      this.prefsItem = item(textoEstandar("showWindow:", name, "Preferences…"), atajoEstandar("showWindow:", "⌘,"), () => {
        let v = getFocusedWindow();
        if (v) this._abrirPreferencias(v);
      });
    }
    sep();
    // Services ▸ como en Catalina (12.31.32 PM): Linux no tiene servicios, así que sale apagado. El texto de su submenú
    // está por verificar (pantallas-con-captura-pendientes), por eso no lleva submenú.
    this.servicesItem = item(textoEstandar("titulo:Services", name, "Services"), "▸", () => {});
    this.servicesItem.setSensitive(false);
    sep();
    this.hideItem = item(textoEstandar("hide:", name, `Hide ${name}`), atajoEstandar("hide:", "⌘H"), () => this._ocultarApp());
    this.hideOthersItem = item(textoEstandar("hideOtherApplications:", name, "Hide Others"), atajoEstandar("hideOtherApplications:", "⌥⌘H"), () => this._ocultarOtras());
    this.showAllItem = item(textoEstandar("unhideAllApplications:", name, "Show All"), "", () => this._mostrarTodas());
    // El Finder no tiene Quit (Catalina 12.31.32 PM): con el escritorio de Fynder al frente ni el renglón ni su separador.
    this.quitSep = sep();
    this.quitItem = item(textoEstandar("terminate:", name, `Quit ${name}`), atajoEstandar("terminate:", "⌘Q"), () => this._salirDeApp());
    if (cargar && w && !isDesktopWindow(w)) this._cargarMenuPropio(w);
  }

  // El menú propio de la app (el marcado x-constanza-app-menu) por el servicio; sin servicio, la lectura síncrona de siempre.
  _cargarMenuPropio(w) {
    m1("MenuApp", new GLib.Variant("(u)", [xidDe(w)]), "(aa{sv})").then(r => {
      let items = r.recursiveUnpack()[0];
      if (!items.length || w !== getFocusedWindow()) return;
      let lista = items.map(i => i.tipo === "separador" ? { separador: true }
        : { etiqueta: i.etiqueta, activo: i.activo, id: i.id, version: i.version });
      this._buildMenu(lista);
      this._updateMenuLabels(false);
    }).catch(e => {
      if (!sinServicio(e)) return;     // la ventana no publica menú propio: queda el de siempre
      let lista = leerMenuDeApp(w);
      if (lista && w === getFocusedWindow()) { this._buildMenu(lista); this._updateMenuLabels(false); }
    });
  }

  _abrirPreferencias(v) {
    itemPorPatron(v, RE_PREFS).then(it => { if (it) activarItemServicio(v, it); }).catch(e => {
      if (sinServicio(e)) activarDeMenu(v, RE_PREFS);
      else global.logError("appmenu@macos: Preferences: " + e);
    });
  }

  // alAbrir: solo al abrir el menú se pregunta a la app si tiene Preferences
  // (es una llamada D-Bus; no se hace en cada cambio de foco).
  _updateMenuLabels(alAbrir) {
    let name = this._getFocusedAppName();
    let w = getFocusedWindow();
    let hayApp = !!(w && !isDesktopWindow(w));
    if (this.aboutItem) this.aboutItem.label.text = textoEstandar("orderFrontStandardAboutPanel:", name, `About ${name}`);
    this.hideItem.label.text = textoEstandar("hide:", name, `Hide ${name}`);
    this.quitItem.label.text = textoEstandar("terminate:", name, `Quit ${name}`);
    if (alAbrir && this.prefsItem) {
      // Preferences… solo si la app lo publica; se pregunta al servicio (sin bloquear) y mientras tanto no se ve.
      this.prefsItem.actor.visible = false;
      this.prefsSep.actor.visible = false;
      if (hayApp) {
        let ponerPrefs = (prefs) => {
          if (!this.prefsItem || w !== getFocusedWindow()) return;
          this.prefsItem.actor.visible = prefs;
          this.prefsSep.actor.visible = prefs;
        };
        itemPorPatron(w, RE_PREFS).then(it => ponerPrefs(!!it)).catch(e => ponerPrefs(sinServicio(e) && menuTiene(w, RE_PREFS)));
      }
    }
    this.hideItem.setSensitive(hayApp);
    this.hideOthersItem.setSensitive(hayApp);
    let esFynder = esEscritorioDeFynder(w);
    this.quitItem.actor.visible = !esFynder;
    this.quitSep.actor.visible = !esFynder;
    this.quitItem.setSensitive(hayApp && !esFynder);
    this.showAllItem.setSensitive(ventanasNormales().some(v => v.minimized));
  }

  // Quit como en macOS: se le pide a la app que salga, para que pregunte si
  // guarda. (a) su propio Quit/Exit, por GTK o por dbusmenu; (b) si no tiene,
  // se cierran sus ventanas una por una; (c) un segundo Quit a la misma app
  // antes de 5 s la mata (TERM y luego KILL), como último recurso.
  async _salirDeApp() {
    let w = getFocusedWindow();
    if (!w || isDesktopWindow(w) || esEscritorioDeFynder(w)) return;
    let app = appDe(w), pid = w.get_pid();
    let ahora = GLib.get_monotonic_time();
    let p = this._quitPendiente;
    // La repetición de la tecla (⌘Q sostenida) llega en menos de 0,7 s: eso no
    // cuenta como segundo Quit; un segundo Quit de verdad, antes de 5 s, mata.
    if (p && p.pid === pid && ahora - p.cuando < 700000) return;
    if (p && p.pid === pid && ahora - p.cuando < 5000000) {
      this._quitPendiente = null;
      killProcessTree(pid);
      return;
    }
    this._quitPendiente = { pid: pid, cuando: ahora };
    try {
      let it = await itemPorPatron(w, RE_QUIT);
      if (it && await activarItemServicio(w, it)) return;
    } catch (e) {
      if (sinServicio(e)) {
        // Sin servicio: las lecturas síncronas de siempre.
        if (activarDeMenu(w, RE_QUIT)) return;
        let activar = await buscarEnDbusmenu(w, RE_QUIT);
        if (activar) { activar(); return; }
      } else {
        global.logError("appmenu@macos: Quit: " + e);
      }
    }
    let hora = global.get_current_time();
    for (let v of ventanasNormales()) if (mismaApp(v, w)) { try { v.delete(hora); } catch (e) {} }
  }

  // ── Atajos por app ────────────────────────────────────────────────────────────────────────────────────────────────────
  _iniciarAtajosApps() {
    this._atajosApp = leerAtajosApps();
    this._hotkeysApp = new Map();        // accel de Cinnamon → nombre del hotkey
    try {
      let f = Gio.File.new_for_path(RUTA_ATAJOS_APPS);
      GLib.mkdir_with_parents(GLib.path_get_dirname(RUTA_ATAJOS_APPS), 0o755);
      this._monitorAtajos = f.monitor_file(Gio.FileMonitorFlags.NONE, null);
      this._monitorAtajos.connect("changed", () => {
        if (this._recargaAtajos) GLib.source_remove(this._recargaAtajos);
        this._recargaAtajos = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 200, () => {
          this._recargaAtajos = 0;
          this._atajosApp = leerAtajosApps();
          this._actualizarAtajosApps();
          return GLib.SOURCE_REMOVE;
        });
      });
    } catch (e) {}
    this._actualizarAtajosApps();
  }

  _entradasDe(w) {
    let id = "";
    try { let a = w && appDe(w); id = (a && a.get_id()) || ""; } catch (e) {}
    return this._atajosApp.filter(e => e.app === "*" || (id && e.app === id));
  }

  // Se agarran los atajos de la app con el foco (y los de «All Applications»); al cambiar de app se sueltan los que ya no tocan.
  _actualizarAtajosApps() {
    let w = getFocusedWindow();
    let quiero = new Map();
    for (let e of (w && !isDesktopWindow(w)) ? this._entradasDe(w) : []) quiero.set(atajoMacAAccel(e.atajo), e);
    for (let [accel, nombre] of [...this._hotkeysApp]) {
      if (!quiero.has(accel)) { try { Main.keybindingManager.removeHotKey(nombre); } catch (e) {} this._hotkeysApp.delete(accel); }
    }
    let n = 0;
    for (let accel of quiero.keys()) {
      if (this._hotkeysApp.has(accel)) continue;
      let nombre = "appmenu-macos-atajo-app-" + (n++) + "-" + accel;
      try {
        Main.keybindingManager.addHotKey(nombre, accel, () => this._dispararAtajoApp(accel));
        this._hotkeysApp.set(accel, nombre);
      } catch (e) { global.logError("appmenu@macos: atajo " + accel + ": " + e); }
    }
  }

  // El atajo se pulsó: se busca el comando de menú de la app con ese nombre y se activa.
  async _dispararAtajoApp(accel) {
    let w = getFocusedWindow();
    if (!w) return;
    let e = this._entradasDe(w).find(x => atajoMacAAccel(x.atajo) === accel);
    if (!e) return;
    try {
      let items = await itemsServicio(w);
      let quiero = normalizarTitulo(e.titulo);
      let it = items.find(i => i.activo !== false && normalizarTitulo(i.etiqueta || "") === quiero);
      if (it) await activarItemServicio(w, it);
    } catch (err) {
      global.logError("appmenu@macos: atajo de app «" + e.titulo + "»: " + err);
    }
  }

  _ocultarApp() {
    let w = getFocusedWindow();
    if (!w || isDesktopWindow(w)) return;
    for (let v of ventanasNormales()) if (mismaApp(v, w)) v.minimize();
  }

  _ocultarOtras() {
    let w = getFocusedWindow();
    if (!w || isDesktopWindow(w)) return;
    for (let v of ventanasNormales()) if (!mismaApp(v, w)) v.minimize();
  }

  _mostrarTodas() {
    for (let v of ventanasNormales()) if (v.minimized) v.unminimize();
  }

  _showAboutDialog() {
    let w = getFocusedWindow();
    let name = this._getFocusedAppName();

    if (!w || isDesktopWindow(w)) {
      let dlg = new AboutAppDialog(`About ${name}`, "No focused application window.");
      dlg.open();
      return;
    }

    // Por el servicio: el About del menú de la app (GTK o dbusmenu). Sin servicio, las lecturas síncronas de siempre.
    itemPorPatron(w, RE_ABOUT).then(it => {
      if (it) return activarItemServicio(w, it);
      return false;
    }).then(hecho => hecho || abrirAboutPorAccion(w)).then(hecho => {
      if (hecho) return;
      if (abrirAboutChromium(w)) return;
      this._aboutDeRespaldo(w, name);
    }).catch(e => {
      if (!sinServicio(e)) global.logError("appmenu@macos: About: " + e);
      if (abrirAboutDeLaApp(w)) return;
      if (abrirAboutChromium(w)) return;
      buscarEnDbusmenu(w, RE_ABOUT).then(activar => {
        if (activar) activar(); else this._aboutDeRespaldo(w, name);
      });
    });
  }

  _aboutDeRespaldo(w, name) {
    let pid = w.get_pid();
    let comm = pid > 0 ? procNameFromPid(pid) : "";
    let exe = pid > 0 ? (() => { try { return GLib.file_read_link(`/proc/${pid}/exe`); } catch (e) { return ""; } })() : "";
    let cmdline = pid > 0 ? readFileTrim(`/proc/${pid}/cmdline`).split("\u0000").filter(Boolean).join(" ") : "";

    // Best-effort: dpkg package/version for the exe path (Mint/Ubuntu/Debian)
    let pkgInfo = "Package: N/A\nVersion: N/A\n";
    try {
      if (exe && exe.length) {
        let tmp = GLib.build_filenamev([GLib.get_tmp_dir(), `appmenu_about_${pid}.txt`]);
        let qtmp = shellQuote(tmp);
        let qexe = shellQuote(exe);

        // dpkg -S maps file -> package; dpkg-query prints version/details.
        let bash = `
set -e
EXE=${qexe}
OUT=${qtmp}
PKG="$(dpkg -S "$EXE" 2>/dev/null | head -n1 | cut -d: -f1 || true)"
if [ -n "$PKG" ]; then
  VER="$(dpkg-query -W -f='${Version}' "$PKG" 2>/dev/null || true)"
  echo "Package: $PKG" > "$OUT"
  echo "Version: $VER" >> "$OUT"
  echo "" >> "$OUT"
  dpkg-query -W -f='Description:\n${Description}\n' "$PKG" 2>/dev/null >> "$OUT" || true
else
  echo "Package: N/A" > "$OUT"
  echo "Version: N/A" >> "$OUT"
fi
`;
        spawn(`bash -lc ${shellQuote(bash)}`);

        // Read after a short delay
        GLib.timeout_add(GLib.PRIORITY_DEFAULT, 150, () => {
          let txt = readFileTrim(tmp);
          if (txt) pkgInfo = txt;
          try { GLib.unlink(tmp); } catch (e) {}

          let body =
`App: ${name}
PID: ${pid}
Process: ${comm || "N/A"}
Executable: ${exe || "N/A"}

${pkgInfo}

Command line:
${cmdline || "N/A"}`;

          let dlg = new AboutAppDialog(`About ${name}`, body);
          dlg.open();
          return GLib.SOURCE_REMOVE;
        });
        return;
      }
    } catch (e) {}

    let body =
`App: ${name}
PID: ${pid}
Process: ${comm || "N/A"}
Executable: ${exe || "N/A"}

${pkgInfo}

Command line:
${cmdline || "N/A"}`;

    let dlg = new AboutAppDialog(`About ${name}`, body);
    dlg.open();
  }

  on_applet_clicked() {
    // Se rehace antes de abrir y con los nombres ya puestos: Cinnamon mide
    // las columnas al armar el menú, y un nombre cambiado después sale cortado.
    if (!this.menu.isOpen) { this._buildMenu(); this._updateMenuLabels(true); }
    this.menu.toggle();
  }

  on_applet_removed_from_panel() {
    if (this._monitorAtajos) { try { this._monitorAtajos.cancel(); } catch (e) {} }
    if (this._recargaAtajos) GLib.source_remove(this._recargaAtajos);
    for (let nombre of (this._hotkeysApp || new Map()).values()) { try { Main.keybindingManager.removeHotKey(nombre); } catch (e) {} }
    for (let [n] of this._atajos || []) {
      try { Main.keybindingManager.removeHotKey(n); } catch (e) {}
    }
    if (this._creadaSig) { try { global.display.disconnect(this._creadaSig); } catch (e) {} this._creadaSig = 0; }
    if (this._focusSig) {
      try { global.display.disconnect(this._focusSig); } catch (e) {}
    }
    if (this._timer) {
      try { GLib.source_remove(this._timer); } catch (e) {}
    }
    if (this.settings) this.settings.finalize();
  }
}

function main(metadata, orientation, panel_height, instance_id) {
  return new AppMenuApplet(metadata, orientation, panel_height, instance_id);
}
