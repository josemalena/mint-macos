// La entrada de Catalina: después de la clave, el fondo solo; la barra de menú
// aparece (con un fundido) cuando todo lo que se espera ya está.
//
// Lo que se espera, en este orden de preferencia:
//   1. el marcador $XDG_RUNTIME_DIR/mint-macos-listo con el id de ESTA sesión
//      (lo escribe fynder-desktop cuando iCloud montó y el Finder leyó el disco);
//   2. mientras fynder-desktop no lo escriba: iCloud montado (si ~/Desktop
//      vive ahí) y ~/Desktop legible, más 1.5 s de aire.
// Tope de 150 s: si nada llega, la barra sale igual (nunca se queda sin ella).
//
// Solo actúa al entrar a la sesión. Si Cinnamon se reinicia o la extensión se
// enciende con la sesión ya andando, no toca la barra (el marcador
// mint-macos-entrada guarda el id de la sesión que ya pasó por aquí).
//
// La barra se oculta con la opacidad, no con hide(): así no cambia el espacio
// de las ventanas y nada salta al aparecer.

const Main = imports.ui.main;
const GLib = imports.gi.GLib;
const Mainloop = imports.mainloop;

const TOPE_S = 150;
const AIRE_MS = 1500;
const FUNDIDO_MS = 500;

let temporizador = 0;
let ocultos = [];
let t0 = 0;

function init() {}

function sesion() {
  return GLib.getenv('XDG_SESSION_ID') || 'sin-sesion';
}

function ruta(nombre) {
  return GLib.build_filenamev([GLib.get_user_runtime_dir(), nombre]);
}

function leer(nombre) {
  try {
    let [ok, bytes] = GLib.file_get_contents(ruta(nombre));
    return ok ? imports.byteArray.toString(bytes).trim() : null;
  } catch (e) {
    return null;
  }
}

function icloudListo() {
  let desktop = GLib.build_filenamev([GLib.get_home_dir(), 'Desktop']);
  let destino = desktop;
  try { destino = GLib.file_read_link(desktop); } catch (e) {}  // no es un enlace: se queda
  if (destino.indexOf('/') !== 0)
    destino = GLib.build_filenamev([GLib.get_home_dir(), destino]);
  let nube = GLib.build_filenamev([GLib.get_home_dir(), 'iCloud Drive']) + '/';
  if (destino.indexOf(nube) !== 0)
    return true;  // el escritorio no vive en iCloud: no hay nada que esperar
  return GLib.file_test(desktop + '/.', GLib.FileTest.EXISTS);
}

function listo() {
  if (leer('mint-macos-listo') === sesion())
    return true;
  // Sin el marcador de fynder-desktop: lo que se pueda saber de afuera.
  return icloudListo() && (GLib.get_monotonic_time() - t0) / 1000 > AIRE_MS;
}

function paneles() {
  try { return Main.panelManager.getPanels().filter(p => p); } catch (e) { return []; }
}

function mostrar() {
  for (let p of ocultos) {
    try {
      p.actor.reactive = true;
      p.actor.ease({ opacity: 255, duration: FUNDIDO_MS, mode: imports.gi.Clutter.AnimationMode.EASE_OUT_QUAD });
    } catch (e) {
      try { p.actor.opacity = 255; p.actor.reactive = true; } catch (e2) {}
    }
  }
  ocultos = [];
  GLib.file_set_contents(ruta('mint-macos-entrada'), sesion());
}

function vigilar() {
  let pasado = (GLib.get_monotonic_time() - t0) / 1e6;
  if (listo() || pasado >= TOPE_S) {
    temporizador = 0;
    mostrar();
    return GLib.SOURCE_REMOVE;
  }
  return GLib.SOURCE_CONTINUE;
}

function enable() {
  if (leer('mint-macos-entrada') === sesion())
    return;  // esta sesión ya hizo su entrada: no se toca la barra
  t0 = GLib.get_monotonic_time();
  for (let p of paneles()) {
    p.actor.opacity = 0;
    p.actor.reactive = false;
    ocultos.push(p);
  }
  if (!ocultos.length)
    return;
  temporizador = Mainloop.timeout_add(250, vigilar);
}

function disable() {
  if (temporizador) {
    Mainloop.source_remove(temporizador);
    temporizador = 0;
  }
  // Apagarla nunca deja la barra escondida.
  for (let p of ocultos) {
    try { p.actor.opacity = 255; p.actor.reactive = true; } catch (e) {}
  }
  ocultos = [];
}
