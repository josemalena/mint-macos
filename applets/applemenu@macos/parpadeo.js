// El parpadeo de la Mac al escoger un ítem de menú (desde System 6): el resaltado parpadea antes de que el menú se cierre y la acción
// corra. En Cinnamon todos los menús St pasan por PopupBaseMenuItem.activate, que emite «activate» (y con él el menú se cierra y el
// applet hace lo suyo): este módulo lo envuelve para parpadear primero, con el menú todavía abierto. Se instala al cargar el applet y
// se quita al descargarlo (como colgadas.js); no toca el JS del sistema.
//
// Los ajustes (org.mintmacos.menus: menu-flash, flash-count, flash-duration-ms) están apagados por defecto hasta que Infra mida los de la
// Mac; sin el esquema instalado tampoco parpadea nada.
const Gio = imports.gi.Gio;
const GLib = imports.gi.GLib;
const PopupMenu = imports.ui.popupMenu;

var original = null;
var ajustes = null;

function _ajustes() {
  if (ajustes) return ajustes;
  try {
    let fuente = Gio.SettingsSchemaSource.get_default();
    // Si el esquema se instaló con la sesión ya abierta, la fuente por omisión no lo ve: se mira la carpeta del usuario
    if (!fuente || !fuente.lookup("org.mintmacos.menus", true)) {
      let carpeta = GLib.build_filenamev([GLib.get_user_data_dir(), "glib-2.0", "schemas"]);
      if (GLib.file_test(GLib.build_filenamev([carpeta, "gschemas.compiled"]), GLib.FileTest.EXISTS))
        fuente = Gio.SettingsSchemaSource.new_from_directory(carpeta, fuente, false);
    }
    let esquema = fuente ? fuente.lookup("org.mintmacos.menus", true) : null;
    if (esquema)
      ajustes = new Gio.Settings({ settings_schema: esquema });
  } catch (e) {}
  return ajustes;
}

function activar() {
  if (original !== null) return;
  original = PopupMenu.PopupBaseMenuItem.prototype.activate;
  PopupMenu.PopupBaseMenuItem.prototype.activate = function(event, keepMenu) {
    let cfg = _ajustes();
    // Sin parpadeo (apagado, sin esquema, ya parpadeando, ítem que deja el menú abierto o que no se puede escoger): lo de siempre
    if (!cfg || !cfg.get_boolean("menu-flash") || keepMenu || this._parpadeando || this.sensitive === false || !this.actor) {
      return original.call(this, event, keepMenu);
    }
    let veces = cfg.get_int("flash-count");
    let fase = cfg.get_int("flash-duration-ms");
    this._parpadeando = true;
    // El ítem ya está resaltado: se apaga, se enciende, … y al final queda encendido un instante antes de cerrar
    let paso = 0;
    let total = veces * 2;
    if (total === 0) {   // sin apagar: queda resaltado fijo `fase` ms y luego se ejecuta (lo medido en High Sierra)
      GLib.timeout_add(GLib.PRIORITY_DEFAULT, fase, () => {
        this._parpadeando = false;
        try { original.call(this, event, keepMenu); } catch (e) { global.logError("parpadeo: " + e); }
        return GLib.SOURCE_REMOVE;
      });
      return undefined;
    }
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, fase, () => {
      try {
        paso++;
        this.actor.change_style_pseudo_class("active", paso % 2 === 0);
      } catch (e) { paso = total; }
      if (paso < total) return GLib.SOURCE_CONTINUE;
      this._parpadeando = false;
      try { original.call(this, event, keepMenu); } catch (e) { global.logError("parpadeo: " + e); }
      return GLib.SOURCE_REMOVE;
    });
    return undefined;
  };
}

function desactivar() {
  if (original === null) return;
  PopupMenu.PopupBaseMenuItem.prototype.activate = original;
  original = null;
}
