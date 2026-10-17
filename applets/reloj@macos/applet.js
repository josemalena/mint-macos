/*
 * Reloj de la barra (reloj@macos).
 *
 * El texto de la barra y el menú que sale al pulsarlo, como en Catalina (captura 16-barra-estado-3-clock-oscuro):
 *
 *   Thursday, October 15, 2026          (en gris)
 *   View as Analog                      (en gris: aquí no hay reloj analógico)
 *   ✓ View as Digital
 *   ─────────────
 *   Open Date & Time Preferences…
 *
 * El formato del texto es el de Date & Time (settings/fecha.py), que lo escribe en los JSON de calendar@cinnamon.org; este
 * applet los lee, así que el panel sigue funcionando igual. Vuelta atrás: poner calendar@cinnamon.org en el panel y quitar este.
 */

const Applet = imports.ui.applet;
const PopupMenu = imports.ui.popupMenu;
const Util = imports.misc.util;
const { Clutter, Gio, GLib, St } = imports.gi;

const FORMATO_POR_DEFECTO = "%a %b %-d %-I:%M %p";
const FORMATO_FECHA = "%A, %B %-d, %Y";
const GRIS = "color: rgba(255,255,255,0.45);";
const ANCHO_MARCA = 16;

// El formato personalizado de Date & Time, si está puesto; si no, el de Catalina.
function leerFormato() {
  let dir = GLib.build_filenamev([GLib.get_user_config_dir(), "cinnamon", "spices", "calendar@cinnamon.org"]);
  try {
    let e = Gio.File.new_for_path(dir).enumerate_children("standard::name", 0, null);
    let info;
    while ((info = e.next_file(null)) !== null) {
      if (!info.get_name().endsWith(".json")) continue;
      let [ok, bytes] = GLib.file_get_contents(GLib.build_filenamev([dir, info.get_name()]));
      if (!ok) continue;
      let d = JSON.parse(String.fromCharCode.apply(null, bytes));
      if (d["use-custom-format"] && d["use-custom-format"].value && d["custom-format"] && d["custom-format"].value) {
        return d["custom-format"].value;
      }
    }
  } catch (e) { /* sin archivo: el de Catalina */ }
  return FORMATO_POR_DEFECTO;
}

class RelojApplet extends Applet.TextApplet {
  constructor(metadata, orientation, panelHeight, instanceId) {
    super(orientation, panelHeight, instanceId);
    this.setAllowedLayout(Applet.AllowedLayout.BOTH);
    this._formato = leerFormato();
    this._temporizador = 0;

    this.menuManager = new PopupMenu.PopupMenuManager(this);
    this.menu = new Applet.AppletPopupMenu(this, orientation);
    this.menuManager.addMenu(this.menu);
    this.menu.connect("open-state-changed", (m, abierto) => { if (abierto) this._armar(); });
    this._armar();

    // Si Date & Time cambia el formato, se vuelve a leer.
    this._vigilantes = [];
    try {
      let dir = Gio.File.new_for_path(GLib.build_filenamev([GLib.get_user_config_dir(), "cinnamon", "spices", "calendar@cinnamon.org"]));
      let v = dir.monitor_directory(Gio.FileMonitorFlags.NONE, null);
      v.connect("changed", () => { this._formato = leerFormato(); this._pintar(); });
      this._vigilantes.push(v);
    } catch (e) { /* sin carpeta: no hay nada que vigilar */ }
    this._pintar();
  }

  _ahora() {
    return GLib.DateTime.new_now_local();
  }

  // Pinta la hora y se vuelve a llamar justo al siguiente cambio (cada segundo si el formato lleva segundos).
  _pintar() {
    if (this._temporizador) { GLib.source_remove(this._temporizador); this._temporizador = 0; }
    let ahora = this._ahora();
    let texto = ahora.format(this._formato) || "";
    this.set_applet_label(texto);
    let conSegundos = /%[-_0^#]?[SsTrXc]/.test(this._formato);
    let espera = conSegundos ? 1000 - Math.floor(ahora.get_microsecond() / 1000)
                             : (60 - ahora.get_second()) * 1000 - Math.floor(ahora.get_microsecond() / 1000);
    this._temporizador = GLib.timeout_add(GLib.PRIORITY_DEFAULT, Math.max(espera, 50), () => {
      this._temporizador = 0;
      this._pintar();
      return GLib.SOURCE_REMOVE;
    });
  }

  on_applet_clicked() {
    this.menu.toggle();
  }

  _gris(texto) {
    let item = new PopupMenu.PopupMenuItem(texto, { reactive: false });
    item.label.set_style(GRIS);
    return item;
  }

  _armar() {
    this.menu.removeAll();
    this.menu.addMenuItem(this._gris(this._ahora().format(FORMATO_FECHA)));

    this.menu.addMenuItem(this._gris("View as Analog"));          // sin reloj analógico: en gris, como en Date & Time

    let digital = new PopupMenu.PopupBaseMenuItem();
    let caja = new St.BoxLayout({ vertical: false, x_expand: true });
    caja.add_actor(new St.Label({ text: "✓", width: ANCHO_MARCA, y_align: Clutter.ActorAlign.CENTER }));
    caja.add_actor(new St.Label({ text: "View as Digital", y_align: Clutter.ActorAlign.CENTER }));
    digital.addActor(caja, { span: -1, expand: true });
    this.menu.addMenuItem(digital);

    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
    let prefs = new PopupMenu.PopupMenuItem("Open Date & Time Preferences…");
    prefs.connect("activate", () => Util.spawnCommandLine("mac-settings datetime"));
    this.menu.addMenuItem(prefs);
  }

  on_applet_removed_from_panel() {
    if (this._temporizador) { GLib.source_remove(this._temporizador); this._temporizador = 0; }
    for (let v of this._vigilantes) v.cancel();
  }
}

function main(metadata, orientation, panelHeight, instanceId) {
  return new RelojApplet(metadata, orientation, panelHeight, instanceId);
}
