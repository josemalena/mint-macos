/*
 * El perfil de la versión de macOS escogida (perfiles/ESQUEMA.md): los textos, el orden y los atajos de los menús vienen de ahí, por
 * id estable, y no de literales de una versión. La versión activa es $XDG_RUNTIME_DIR/mint-macos/macos.json (la copia al entrar
 * `mint-macos-version --aplicar`); sin ella, la escogida en ~/.config/mint-macos/macos.json; sin ninguna, Catalina.
 * Los perfiles se generan en cada máquina (tienen textos de Apple) y no van al repo: si no están, las funciones devuelven null y
 * la pieza usa lo que lleva puesto.
 *
 * Este archivo es el mismo en applemenu@macos y en appmenu@macos (copia exacta; lo vigila el caso 64).
 */
const { GLib, Gio } = imports.gi;

const POR_DEFECTO = "catalina-10.15";
const _cache = { firma: null, version: null, archivos: {} };

// Fecha de modificación de un archivo, o "" si no existe: con ella se sabe si cambió la versión activa o el perfil.
function _mtime(ruta) {
  try {
    let info = Gio.File.new_for_path(ruta).query_info("time::modified,time::modified-usec", Gio.FileQueryInfoFlags.NONE, null);
    return info.get_attribute_uint64("time::modified") + "." + info.get_attribute_uint32("time::modified-usec");
  } catch (e) { return ""; }
}

function _rutasVersion() {
  return [
    GLib.build_filenamev([GLib.get_user_runtime_dir(), "mint-macos", "macos.json"]),
    GLib.build_filenamev([GLib.get_user_config_dir(), "mint-macos", "macos.json"]),
  ];
}

function _leerJson(ruta) {
  try {
    let [ok, bytes] = GLib.file_get_contents(ruta);
    return ok ? JSON.parse(imports.byteArray.toString(bytes)) : null;
  } catch (e) { return null; }
}

/** El id de la versión activa («catalina-10.15»). */
function activa() {
  // Si cambió el archivo de la versión (mint-macos-version --aplicar, o la prueba), se olvida lo leído.
  let candidatos = _rutasVersion();
  let firma = candidatos.map(_mtime).join("|");
  if (firma !== _cache.firma) { _cache.firma = firma; _cache.version = null; _cache.archivos = {}; }
  if (_cache.version) return _cache.version;
  for (let c of candidatos) {
    let d = _leerJson(c);
    if (d && d.version) { _cache.version = d.version; return d.version; }
  }
  _cache.version = POR_DEFECTO;
  return POR_DEFECTO;
}

/** Un archivo de apps/ del perfil activo, o null (con caché mientras no cambie la versión activa). */
function _app(nombre) {
  let k = activa() + "/" + nombre;
  if (!(k in _cache.archivos)) {
    _cache.archivos[k] = _leerJson(GLib.build_filenamev([GLib.get_home_dir(), ".local", "share", "mint-macos", "macos", activa(), "apps", nombre + ".json"]));
  }
  return _cache.archivos[k];
}

/** El menú Apple como lista de ítems {id, texto, atajo, separador, oculto, alterno_de, submenu…}, o null. */
function menuApple() {
  let d = _app("menu-apple");
  return d && d.items ? d.items : null;
}

/** Los ítems estándar del menú «app» (About, Preferences…, Hide, Quit…) por su acción, o null. */
function menuEstandar(idMenu) {
  let d = _app("menus-estandar");
  if (!d || !d.menus) return null;
  let m = d.menus.find(x => x.id === idMenu);
  return m ? m.items : null;
}

/** El ítem con ese id (el comando de Carbon o la acción de AppKit) dentro de una lista, o null. */
function item(lista, id) {
  if (!lista) return null;
  for (let it of lista) {
    if (it.id === id) return it;
    if (it.submenu) { let r = item(it.submenu, id); if (r) return r; }
  }
  return null;
}

/** El texto del ítem con las variables resueltas: «Hide %@» + {"%@": "Firefox"} → «Hide Firefox». */
function texto(it, variables) {
  if (!it || !it.texto) return null;
  let t = it.texto;
  for (let k in (variables || {})) t = t.split(k).join(variables[k]);
  return t;
}
