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
const RE_ABOUT = /^(about|acerca de)\b/i;
const DBUS_TIMEOUT = 400;

function llamar(bus, ruta, iface, metodo, args, tipo) {
  return Gio.DBus.session.call_sync(bus, ruta, iface, metodo, args,
    tipo ? new GLib.VariantType(tipo) : null, Gio.DBusCallFlags.NONE, DBUS_TIMEOUT, null);
}

function buscarEnMenu(bus, ruta, patron) {
  let pendientes = [0], vistos = new Set(), hallado = null;
  try {
    for (let vuelta = 0; vuelta < 6 && pendientes.length && !hallado; vuelta++) {
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
          if (!hallado && it.action && patron.test(etiqueta))
            hallado = { accion: it.action, objetivo: it.target };
        }
      }
    }
  } catch (e) {}
  try {
    llamar(bus, ruta, "org.gtk.Menus", "End", new GLib.Variant("(au)", [[...vistos]]), null);
  } catch (e) {}
  return hallado;
}

function activarAccion(bus, ruta, nombre, objetivo) {
  let params = [];
  if (objetivo !== undefined && objetivo !== null) {
    try { params = [GLib.Variant.new_string(String(objetivo))]; } catch (e) {}
  }
  llamar(bus, ruta, "org.gtk.Actions", "Activate",
    new GLib.Variant("(sava{sv})", [nombre, params, {}]), null);
}

const RE_PREFS = /^(preferences|preferencias|settings|ajustes)\b/i;

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

function getFocusedWindow() {
  try { return global.display.get_focus_window ? global.display.get_focus_window() : null; }
  catch (e) { return null; }
}

function isDesktopWindow(w) {
  try { return (w && w.get_window_type && w.get_window_type() === 6); }
  catch (e) { return false; }
}

function getFocusedPid() {
  let w = getFocusedWindow();
  if (!w || isDesktopWindow(w)) return 0;
  try { return w.get_pid ? w.get_pid() : 0; } catch (e) { return 0; }
}

function killProcessTree(pid) {
  const root = Number(pid);
  if (!root || root <= 0) return;

  const qpid = shellQuote(String(root));

  const bash = `
set -e
ROOT=${qpid}

collect_children_pgrep() { local p="$1"; pgrep -P "$p" 2>/dev/null || true; }
collect_children_proc()  { local p="$1"; local f="/proc/$p/task/$p/children"; [ -r "$f" ] && cat "$f" 2>/dev/null || true; }

collect_all() {
  local queue="$1"
  local out=""
  while [ -n "$queue" ]; do
    local p="\${queue%% *}"
    queue="\${queue#* }"
    [ -z "$p" ] && continue
    out="$out $p"

    local kids=""
    kids="$(collect_children_pgrep "$p")"
    [ -z "$kids" ] && kids="$(collect_children_proc "$p")"

    for k in $kids; do queue="$queue $k"; done
  done
  echo "$out"
}

PIDS="$(collect_all "$ROOT")"

# TERM children-first
for p in $(echo "$PIDS" | awk '{for(i=NF;i>=1;i--) printf $i" ";}'); do
  kill -TERM "$p" 2>/dev/null || true
done

sleep 1.2

# KILL children-first
for p in $(echo "$PIDS" | awk '{for(i=NF;i>=1;i--) printf $i" ";}'); do
  kill -KILL "$p" 2>/dev/null || true
done
`;
  spawn(`bash -lc ${shellQuote(bash)}`);
}

class AboutAppDialog extends ModalDialog.ModalDialog {
  constructor(title, bodyText) {
    super({ styleClass: null });

    this.contentLayout.add(new St.Label({
      text: title,
      style_class: "dialog-title",
      x_align: St.Align.START
    }));

    let scroll = new St.ScrollView({ style_class: "vfade", overlay_scrollbars: true });
    let label = new St.Label({
      text: bodyText,
      style_class: "dialog-description",
      x_align: St.Align.START
    });
    label.clutter_text.line_wrap = true;
    label.clutter_text.selectable = true;

    scroll.add_actor(label);
    this.contentLayout.add(scroll);

    this.setButtons([
      {
        label: "OK",
        action: () => this.close(),
        key: 0
      }
    ]);
  }
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

    // ⌘H y ⌥⌘H: keyd deja pasar ⌘ como Super y Cinnamon no usa esas teclas.
    this._atajos = [
      ["appmenu-macos-ocultar", "<Super>h", () => this._ocultarApp()],
      ["appmenu-macos-ocultar-otras", "<Super><Alt>h", () => this._ocultarOtras()],
    ];
    for (let [n, k, f] of this._atajos) Main.keybindingManager.addHotKey(n, k, f);
    this._applyLabelStyle();
    this._updateLabel();

    // Update label + menu texts on focus change
    this._focusSig = 0;
    try {
      this._focusSig = global.display.connect("notify::focus-window", () => {
        this._updateLabel();
        this._updateMenuLabels();
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
      this.actor.set_style(`padding-left: ${px}px; padding-right: ${px}px;`);
      this._applet_label.set_style('padding-left: 0; padding-right: 0; font-family: ".SF NS", sans-serif; font-size: 10pt;');
    } catch (e) {}
  }

  _getFocusedAppName() {
    let fallback = (this.fallbackLabel && this.fallbackLabel.length) ? this.fallbackLabel : "Finder";

    let w = getFocusedWindow();
    if (!w || isDesktopWindow(w)) return fallback;

    let cls = getWmClass(w);
    if (!cls) return fallback;

    let norm = cls.toLowerCase();
    if (norm === "nemo-desktop") return fallback;

    return prettifyName(cls);
  }

  _updateLabel() {
    this.set_applet_label(this._getFocusedAppName());
  }

  // El menú de la app como en macOS: About, Preferences… (si la app lo
  // publica), Hide, Hide Others, Show All y Quit. Hide y compañía los hace
  // Cinnamon minimizando ventanas; no hace falta la app.
  _buildMenu() {
    this.menu.removeAll();
    let item = (texto, atajo, accion) => {
      let it = new PopupMenu.PopupMenuItem(texto);
      if (atajo) {
        it.addActor(new St.Label({ text: atajo, y_align: Clutter.ActorAlign.CENTER,
                                   style: "color: rgba(255,255,255,0.45); padding-left: 24px;" }),
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
      s.actor.set_style("padding: 7px 0 3px 0; margin: 0; min-height: 0; spacing: 0;");
      s._drawingArea.set_style("height: 2px; padding: 0; margin: 0; border-bottom-width: 0; -margin-horizontal: 0px; -gradient-height: 2px; -gradient-start: #45484b; -gradient-end: #45484b;");
      this.menu.addMenuItem(s); return s;
    };

    let name = this._getFocusedAppName();
    let w = getFocusedWindow();
    let propio = (w && !isDesktopWindow(w)) ? leerMenuDeApp(w) : null;
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
      this.aboutItem = item(`About ${name}`, "", () => this._showAboutDialog());
      this.prefsSep = sep();
      this.prefsItem = item("Preferences…", "⌘,", () => {
        let v = getFocusedWindow();
        if (v) activarDeMenu(v, RE_PREFS);
      });
    }
    sep();
    this.hideItem = item(`Hide ${name}`, "⌘H", () => this._ocultarApp());
    this.hideOthersItem = item("Hide Others", "⌥⌘H", () => this._ocultarOtras());
    this.showAllItem = item("Show All", "", () => this._mostrarTodas());
    sep();
    this.quitItem = item(`Quit ${name}`, "⌘Q", () => {
      let pid = getFocusedPid();
      if (pid > 0) killProcessTree(pid);
    });
  }

  // alAbrir: solo al abrir el menú se pregunta a la app si tiene Preferences
  // (es una llamada D-Bus; no se hace en cada cambio de foco).
  _updateMenuLabels(alAbrir) {
    let name = this._getFocusedAppName();
    let w = getFocusedWindow();
    let hayApp = !!(w && !isDesktopWindow(w));
    if (this.aboutItem) this.aboutItem.label.text = `About ${name}`;
    this.hideItem.label.text = `Hide ${name}`;
    this.quitItem.label.text = `Quit ${name}`;
    if (alAbrir && this.prefsItem) {
      let prefs = hayApp && menuTiene(w, RE_PREFS);
      this.prefsItem.actor.visible = prefs;
      this.prefsSep.actor.visible = prefs;
    }
    this.hideItem.setSensitive(hayApp);
    this.hideOthersItem.setSensitive(hayApp);
    this.quitItem.setSensitive(hayApp);
    this.showAllItem.setSensitive(ventanasNormales().some(v => v.minimized));
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

    if (abrirAboutDeLaApp(w)) return;

    let pid = getFocusedPid();
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
    for (let [n] of this._atajos || []) {
      try { Main.keybindingManager.removeHotKey(n); } catch (e) {}
    }
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
