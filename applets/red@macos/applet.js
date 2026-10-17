/*
 * Wi-Fi de la barra (red@macos).
 *
 * El menú de la captura 16-barra-estado-4-wi-fi-oscuro (Wi-Fi apagado):
 *
 *   Wi-Fi: Off                          (en gris)
 *   Turn Wi-Fi On
 *   ─────────────
 *   Open Network Preferences…
 *
 * Sale solo si NetworkManager ve una tarjeta Wi-Fi (una Mac sin Wi-Fi no enseña el ícono). La lista de redes con el Wi-Fi
 * encendido NO tiene captura (la de Catalina está con el Wi-Fi apagado): hoy encendido enseña «Wi-Fi: On» y el apagado, nada
 * más; cambiar de red se hace en Network. Vuelta atrás: poner network@cinnamon.org y quitar este.
 */

const Applet = imports.ui.applet;
const PopupMenu = imports.ui.popupMenu;
const Util = imports.misc.util;
const NM = imports.gi.NM;

const GRIS = "color: rgba(255,255,255,0.45);";

class RedApplet extends Applet.IconApplet {
  constructor(metadata, orientation, panelHeight, instanceId) {
    super(orientation, panelHeight, instanceId);
    this.setAllowedLayout(Applet.AllowedLayout.BOTH);

    this.menuManager = new PopupMenu.PopupMenuManager(this);
    this.menu = new Applet.AppletPopupMenu(this, orientation);
    this.menuManager.addMenu(this.menu);
    this.menu.connect("open-state-changed", (m, abierto) => { if (abierto) this._armar(); });

    this.set_applet_icon_symbolic_name("xsi-network-wireless-disabled");
    this.actor.hide();
    NM.Client.new_async(null, (obj, res) => {
      try {
        this._cliente = NM.Client.new_finish(res);
      } catch (e) {
        global.logError(`red@macos: ${e.message}`);
        return;
      }
      for (let senal of ["notify::wireless-enabled", "notify::wireless-hardware-enabled", "device-added", "device-removed"]) {
        this._cliente.connect(senal, () => this._pintar());
      }
      this._pintar();
    });
  }

  _hayWifi() {
    return !!this._cliente && this._cliente.get_devices().some(d => d.get_device_type() == NM.DeviceType.WIFI);
  }

  _pintar() {
    if (!this._hayWifi()) {
      this.actor.hide();
      return;
    }
    this.actor.show();
    this.set_applet_icon_symbolic_name(this._cliente.wireless_enabled ? "xsi-network-wireless-signal-good" : "xsi-network-wireless-disabled");
  }

  on_applet_clicked() {
    this.menu.toggle();
  }

  _armar() {
    this.menu.removeAll();
    if (!this._cliente) return;
    let encendido = this._cliente.wireless_enabled;
    let estado = new PopupMenu.PopupMenuItem(`Wi-Fi: ${encendido ? "On" : "Off"}`, { reactive: false });
    estado.label.set_style(GRIS);
    this.menu.addMenuItem(estado);
    let alternar = new PopupMenu.PopupMenuItem(encendido ? "Turn Wi-Fi Off" : "Turn Wi-Fi On");
    alternar.connect("activate", () => this._cliente.wireless_set_enabled(!encendido));
    this.menu.addMenuItem(alternar);
    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
    let prefs = new PopupMenu.PopupMenuItem("Open Network Preferences…");
    prefs.connect("activate", () => Util.spawnCommandLine("mac-settings network"));
    this.menu.addMenuItem(prefs);
  }

  on_applet_removed_from_panel() {}
}

function main(metadata, orientation, panelHeight, instanceId) {
  return new RedApplet(metadata, orientation, panelHeight, instanceId);
}
