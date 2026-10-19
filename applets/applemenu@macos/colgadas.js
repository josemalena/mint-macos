// Cuando una ventana no contesta, Muffin le pide a Cinnamon un «close dialog» (closeDialog.js: «… is not responding», Wait / Force Quit).
// En Catalina no sale ningún diálogo: se abre Force Quit Applications con esa app escogida y marcada «(not responding)».
// Este módulo cambia la clase CloseDialog de Cinnamon por una que lanza mac-forcequit-lanzar --seleccionar PID. No toca el JS del
// sistema: sustituye la clase al cargar el applet y la devuelve al quitarlo. Si el lanzador no está instalado, se usa el diálogo
// de Cinnamon de siempre, para no quedarse sin salida.
const GLib = imports.gi.GLib;
const GObject = imports.gi.GObject;
const Meta = imports.gi.Meta;
const CloseDialogDeCinnamon = imports.ui.closeDialog;

// El lanzador: el del PATH de la sesión (así lo encuentran también las pruebas) o el de ~/.local/bin
function lanzador() {
  return GLib.find_program_in_path('mac-forcequit-lanzar') ||
    GLib.build_filenamev([GLib.get_home_dir(), ".local/bin/mac-forcequit-lanzar"]);
}
const PING_MS = 5000;   // lo mismo que hace closeDialog.js: Muffin pregunta de nuevo y, si la app contesta, esconde el diálogo

var original = null;

const ForceQuitDialog = GObject.registerClass({
  Implements: [Meta.CloseDialog],
  Properties: { 'window': GObject.ParamSpec.override('window', Meta.CloseDialog) },
}, class ForceQuitDialog extends GObject.Object {
  _init(window) {
    super._init();
    this._window = window;
    this._delegado = null;
    this._timeoutId = 0;
  }

  get window() { return this._window; }
  set window(window) { this._window = window; }

  vfunc_show() {
    if (this._timeoutId !== 0 || this._delegado)
      return;
    if (!GLib.file_test(lanzador(), GLib.FileTest.IS_EXECUTABLE)) {
      this._delegado = new original(this._window);
      this._delegado.connect('response', (d, r) => this.response(r));
      this._delegado.vfunc_show();
      return;
    }
    global.log('colgadas: la ventana de pid ' + this._window.get_pid() + ' no contesta; abro Force Quit');
    this._lanzar();
    // La ventana de Force Quit ya está; el ping sigue para que Muffin esconda el diálogo cuando la app vuelva a contestar.
    this._timeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, PING_MS, () => {
      this._window.check_alive(global.display.get_current_time_roundtrip());
      return GLib.SOURCE_CONTINUE;
    });
  }

  vfunc_hide() {
    if (this._delegado) {
      this._delegado.vfunc_hide();
      this._delegado = null;
      return;
    }
    if (this._timeoutId !== 0) {
      GLib.source_remove(this._timeoutId);
      this._timeoutId = 0;
    }
  }

  vfunc_focus() {
    if (this._delegado)
      this._delegado.vfunc_focus();
  }

  _lanzar() {
    let pid = this._window.get_pid();
    if (!(pid > 1))
      return;
    try {
      GLib.spawn_async(null, [lanzador(), '--seleccionar', String(pid)], null, GLib.SpawnFlags.DO_NOT_REAP_CHILD, null);
    } catch (e) {
      global.logError('mac-forcequit: no se pudo abrir Force Quit: ' + e);
    }
  }
});

function activar() {
  if (original !== null)
    return;
  global.log('colgadas: Force Quit reemplaza el diálogo «no responde» de Cinnamon');
  original = CloseDialogDeCinnamon.CloseDialog;
  CloseDialogDeCinnamon.CloseDialog = ForceQuitDialog;
}

function desactivar() {
  if (original === null)
    return;
  CloseDialogDeCinnamon.CloseDialog = original;
  original = null;
}
