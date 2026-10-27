// La sombra de las ventanas con lo medido en la Mac (apps/efectos.json del perfil de la versión activa: ventana.sombra). Muffin dibuja la sombra
// de las ventanas con Meta.ShadowFactory; el tema no puede cambiarla (una box-shadow en el CSS de la decoración corre el cliente). Sin perfil,
// o sin sombra medida en él, queda la de Cinnamon. Al apagar la extensión se devuelven los parámetros de antes.
//
// El perfil da la sombra como la mide la Mac: gaussiana de sigma_px, opacidad 0-1 y desplazamiento hacia abajo. Los parámetros de Muffin son
// radius (el blur: medido en Xvfb con el Muffin de la máquina, la sigma que se ve es ≈ radius; caso 117), opacity 0-255 y y_offset.

const Meta = imports.gi.Meta;
const GLib = imports.gi.GLib;

const CLASES = ['normal', 'dialog', 'modal_dialog', 'utility'];
let originales = [];

function leerPerfil() {
  try {
    let id = null;
    for (let dir of [GLib.get_user_runtime_dir(), GLib.get_user_config_dir()]) {
      try {   // file_get_contents lanza si el archivo no está
        let [ok, bytes] = GLib.file_get_contents(GLib.build_filenamev([dir, 'mint-macos', 'macos.json']));
        if (ok) { id = JSON.parse(imports.byteArray.toString(bytes)).version; break; }
      } catch (e) {}
    }
    if (!id) return null;
    let [ok2, datos] = GLib.file_get_contents(GLib.build_filenamev([GLib.get_user_data_dir(), 'mint-macos', 'macos', id, 'apps', 'efectos.json']));
    return ok2 ? JSON.parse(imports.byteArray.toString(datos)).ventana.sombra : null;
  } catch (e) {
    return null;
  }
}

// Los valores de Muffin para una sombra medida, o null si el perfil no la trae.
function parametros(s) {
  if (!s || !(s.sigma_px > 0) || !(s.opacidad > 0)) return null;
  return { radius: Math.round(s.sigma_px), top_fade: -1, x_offset: 0, y_offset: Math.round(s.desplazamiento_y_px || 0),
           opacity: Math.round(Math.min(1, s.opacidad) * 255) };
}

function init(metadata) {}

function enable() {
  let s = leerPerfil();
  let fabrica = Meta.ShadowFactory.get_default();
  for (let [enfocada, clave] of [[true, 'activa'], [false, 'inactiva']]) {
    let p = s ? parametros(s[clave]) : null;
    if (!p) continue;
    for (let clase of CLASES) {
      // set_params pide el Boxed Meta.ShadowParams, no un objeto: se pide el actual (una copia), se le cambian los campos y se devuelve
      let antes = fabrica.get_params(clase, enfocada);
      originales.push([clase, enfocada, { radius: antes.radius, top_fade: antes.top_fade, x_offset: antes.x_offset, y_offset: antes.y_offset, opacity: antes.opacity }]);
      let nuevo = fabrica.get_params(clase, enfocada);
      for (let k of Object.keys(p)) nuevo[k] = p[k];
      fabrica.set_params(clase, enfocada, nuevo);
    }
  }
}

function disable() {
  let fabrica = Meta.ShadowFactory.get_default();
  for (let [clase, enfocada, p] of originales) {
    let nuevo = fabrica.get_params(clase, enfocada);
    for (let k of Object.keys(p)) nuevo[k] = p[k];
    fabrica.set_params(clase, enfocada, nuevo);
  }
  originales = [];
}
