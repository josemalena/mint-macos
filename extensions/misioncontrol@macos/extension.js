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

  for (let [nombre, [atajo, fn]] of Object.entries(ATAJOS))
    Main.keybindingManager.addHotKey(nombre, atajo, fn);
}

function disable() {
  for (let nombre of Object.keys(ATAJOS))
    Main.keybindingManager.removeHotKey(nombre);
  if (idOculta) { Main.overview.disconnect(idOculta); idOculta = 0; }
  if (filtroOriginal) {
    Workspace.WorkspaceMonitor.prototype._isOverviewWindow = filtroOriginal;
    filtroOriginal = null;
  }
  soloApp = null;
}
