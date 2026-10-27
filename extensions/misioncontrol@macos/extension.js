// Mission Control y Spaces de macOS Catalina para Cinnamon.
//
//   ⌃↑      todas las ventanas del escritorio actual (la vista Scale de
//           Cinnamon); otra vez ⌃↑ o Esc la cierra.
//   ⌃↓      solo las ventanas de la app del frente (App Exposé): la misma
//           vista, filtrada a esa app.
//   ⌃← ⌃→   el escritorio de la izquierda o de la derecha.
//
// ⌃← ⌃→ llegan como ⌃⌘← ⌃⌘→: keyd convierte ⌥← ⌥→ en Ctrl+← Ctrl+→ (moverse
// por palabras), así que el ⌃← físico tiene que salir distinto para no
// confundirse con ⌥←. Eso lo hace la capa [control] de keyd/default.conf.
//
// Apagar la extensión quita los atajos y deja la vista de Cinnamon sin filtro.

const Main = imports.ui.main;
const Cinnamon = imports.gi.Cinnamon;
const Workspace = imports.ui.workspace;
const Overview = imports.ui.overview;
const GLib = imports.gi.GLib;

const ATAJOS = {
  'misioncontrol-todas':   ['<Control>Up', mostrarTodas],
  'misioncontrol-app':     ['<Control>Down', mostrarApp],
  'misioncontrol-izq':     ['<Control><Super>Left', () => Main.wm.actionMoveWorkspaceLeft()],
  'misioncontrol-der':     ['<Control><Super>Right', () => Main.wm.actionMoveWorkspaceRight()],
};

// La app cuyas ventanas enseña la vista; null enseña todas.
let soloApp = null;
let filtroOriginal = null;
let idOculta = 0;
let showOriginal = null;

function appDe(metaWindow) {
  try { return Cinnamon.WindowTracker.get_default().get_window_app(metaWindow); } catch (e) { return null; }
}

function mostrarTodas() {
  soloApp = null;
  Main.overview.toggle();
}

function mostrarApp() {
  if (Main.overview.visible) { Main.overview.hide(); return; }
  let foco = global.display.focus_window;
  let app = foco ? appDe(foco) : null;
  if (!app) return;
  soloApp = app;
  Main.overview.show();
}

// La duración con que Cinnamon anima la entrada (las ventanas van a su lugar, EASE_IN_OUT_QUAD, que es la curva medida): la de la Mac
// sale del perfil de la versión de macOS (apps/animaciones.json, «mission-control-entrar»). Overview.ANIMATION_TIME es de la vista, no el
// ajuste global de animaciones de José; sin perfil queda la de Cinnamon (200 ms). Solo vale para ENTRAR (lo medido): la salida no está
// medida y se queda con la de Cinnamon, así que la duración se pone al mostrar y se devuelve cuando la vista terminó de mostrarse.
let duracionOriginal = null;
let msEntrada = null;
let idMostrada = 0;

function msDelPerfil(clave) {
  try {
    let id = null;
    for (let dir of [GLib.get_user_runtime_dir(), GLib.get_user_config_dir()]) {
      try {   // file_get_contents lanza si el archivo no está
        let [ok, bytes] = GLib.file_get_contents(GLib.build_filenamev([dir, 'mint-macos', 'macos.json']));
        if (ok) { id = JSON.parse(imports.byteArray.toString(bytes)).version; break; }
      } catch (e) {}
    }
    if (!id) return null;
    let [ok2, datos] = GLib.file_get_contents(GLib.build_filenamev([GLib.get_user_data_dir(), 'mint-macos', 'macos', id, 'apps', 'animaciones.json']));
    let ms = ok2 ? JSON.parse(imports.byteArray.toString(datos)).comportamiento[clave].ms : 0;
    return ms > 0 ? ms : null;
  } catch (e) {
    return null;
  }
}

function init(metadata) {}

function enable() {
  // El filtro: la vista pregunta por cada ventana si va; con soloApp, solo
  // van las de esa app.
  let proto = Workspace.WorkspaceMonitor.prototype;
  filtroOriginal = proto._isOverviewWindow;
  proto._isOverviewWindow = function (win) {
    if (!filtroOriginal.call(this, win)) return false;
    if (!soloApp) return true;
    return appDe(win.get_meta_window()) === soloApp;
  };
  idOculta = Main.overview.connect('hidden', () => { soloApp = null; });
  msEntrada = msDelPerfil('mission-control-entrar');
  if (msEntrada !== null) {
    duracionOriginal = Overview.ANIMATION_TIME;
    showOriginal = Main.overview.show;
    Main.overview.show = function (...args) {
      Overview.ANIMATION_TIME = msEntrada;
      return showOriginal.apply(this, args);
    };
    idMostrada = Main.overview.connect('shown', () => { Overview.ANIMATION_TIME = duracionOriginal; });
  }

  for (let [nombre, [atajo, fn]] of Object.entries(ATAJOS))
    Main.keybindingManager.addHotKey(nombre, atajo, fn);
  // Para las esquinas activas (System Preferences ▸ Mission Control ▸ Hot
  // Corners…): una esquina solo corre comandos, y este es el que llega aquí.
  global.mintMacosMissionControl = mostrarTodas;
  global.mintMacosAppWindows = mostrarApp;
}

function disable() {
  delete global.mintMacosMissionControl;
  delete global.mintMacosAppWindows;
  for (let nombre of Object.keys(ATAJOS))
    Main.keybindingManager.removeHotKey(nombre);
  if (idOculta) { Main.overview.disconnect(idOculta); idOculta = 0; }
  if (duracionOriginal !== null) {
    Overview.ANIMATION_TIME = duracionOriginal;
    delete Main.overview.show;   // vuelve a la del prototipo
    Main.overview.disconnect(idMostrada);
    duracionOriginal = null;
  }
  if (filtroOriginal) {
    Workspace.WorkspaceMonitor.prototype._isOverviewWindow = filtroOriginal;
    filtroOriginal = null;
  }
  soloApp = null;
}
