/*
 * Bluetooth de la barra (bluetooth@macos).
 *
 * El menú de la captura 16-barra-estado-5-bluetooth-oscuro:
 *
 *   Bluetooth: On                       (en gris)
 *   Turn Bluetooth Off
 *   ─────────────
 *   Devices                             (en gris)
 *   BT-SPEAKER                      ▸   cada dispositivo emparejado, con su submenú
 *   ─────────────
 *   Open Bluetooth Preferences…
 *
 * Habla con BlueZ por D-Bus (org.bluez), sin blueman. El submenú de cada dispositivo (Connect / Disconnect) NO tiene captura:
 * es lo mínimo que sirve, no lo que enseña Catalina. Con Bluetooth apagado no se enseñan los dispositivos (tampoco hay
 * captura de ese estado). Vuelta atrás: quitar este applet y volver a poner el ícono de blueman (xapp-status).
 */

const Applet = imports.ui.applet;
const PopupMenu = imports.ui.popupMenu;
const Util = imports.misc.util;
const { Gio, GLib } = imports.gi;

const GRIS = "color: rgba(255,255,255,0.45);";
const BLUEZ = "org.bluez";

function llamar(ruta, interfaz, metodo, parametros, alTerminar) {
  Gio.DBus.system.call(BLUEZ, ruta, interfaz, metodo, parametros, null, Gio.DBusCallFlags.NONE, 10000, null,
    (conn, res) => {
      try {
        let r = conn.call_finish(res);
        if (alTerminar) alTerminar(r);
      } catch (e) {
        global.logError(`bluetooth@macos: ${interfaz}.${metodo}: ${e.message}`);
        if (alTerminar) alTerminar(null);
      }
    });
}

class BluetoothApplet extends Applet.IconApplet {
  constructor(metadata, orientation, panelHeight, instanceId) {
    super(orientation, panelHeight, instanceId);
    this.setAllowedLayout(Applet.AllowedLayout.BOTH);

    this._adaptador = null;       // { ruta, encendido }
    this._dispositivos = [];      // { ruta, nombre, conectado }
    this._suscripcion = 0;
    this._pendiente = 0;

    this.menuManager = new PopupMenu.PopupMenuManager(this);
    this.menu = new Applet.AppletPopupMenu(this, orientation);
    this.menuManager.addMenu(this.menu);
    this.menu.connect("open-state-changed", (m, abierto) => { if (abierto) this._leer(() => this._armar()); });

    this.set_applet_icon_symbolic_name("xsi-bluetooth-disabled");
    // Cualquier cambio en BlueZ (encender, conectar, aparecer un dispositivo) vuelve a leer, sin saturar.
    this._suscripcion = Gio.DBus.system.signal_subscribe(BLUEZ, "org.freedesktop.DBus.Properties", "PropertiesChanged",
      null, null, Gio.DBusSignalFlags.NONE, () => this._pedirLectura());
    this._leer(() => this._armar());
  }

  on_applet_clicked() {
    this.menu.toggle();
  }

  _pedirLectura() {
    if (this._pendiente) return;
    this._pendiente = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 300, () => {
      this._pendiente = 0;
      this._leer(() => { if (this.menu.isOpen) this._armar(); });
      return GLib.SOURCE_REMOVE;
    });
  }

  // Lee el adaptador y los dispositivos emparejados con GetManagedObjects.
  _leer(alTerminar) {
    llamar("/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", null, r => {
      this._adaptador = null;
      this._dispositivos = [];
      if (r) {
        let objetos = r.deep_unpack()[0];
        for (let ruta in objetos) {
          let ifaces = objetos[ruta];
          if (ifaces["org.bluez.Adapter1"] && !this._adaptador) {
            this._adaptador = { ruta: ruta, encendido: ifaces["org.bluez.Adapter1"]["Powered"].deep_unpack() };
          }
          let d = ifaces["org.bluez.Device1"];
          if (d && d["Paired"] && d["Paired"].deep_unpack()) {
            this._dispositivos.push({
              ruta: ruta,
              nombre: (d["Alias"] || d["Name"] || { deep_unpack: () => ruta }).deep_unpack(),
              conectado: d["Connected"] ? d["Connected"].deep_unpack() : false,
            });
          }
        }
      }
      this._dispositivos.sort((a, b) => a.nombre.localeCompare(b.nombre));
      this._pintarIcono();
      if (alTerminar) alTerminar();
    });
  }

  _pintarIcono() {
    // Sin adaptador (o BlueZ parado) el ícono no tiene qué decir: se esconde, como en una Mac sin Bluetooth.
    if (!this._adaptador) {
      this.actor.hide();
      return;
    }
    this.actor.show();
    this.set_applet_icon_symbolic_name(this._adaptador.encendido ? "xsi-bluetooth-active" : "xsi-bluetooth-disabled");
  }

  _titulo(texto) {
    let item = new PopupMenu.PopupMenuItem(texto, { reactive: false });
    item.label.set_style(GRIS);
    return item;
  }

  _armar() {
    this.menu.removeAll();
    let a = this._adaptador;
    if (!a) return;

    this.menu.addMenuItem(this._titulo(`Bluetooth: ${a.encendido ? "On" : "Off"}`));
    let alternar = new PopupMenu.PopupMenuItem(a.encendido ? "Turn Bluetooth Off" : "Turn Bluetooth On");
    alternar.connect("activate", () => {
      llamar(a.ruta, "org.freedesktop.DBus.Properties", "Set",
        new GLib.Variant("(ssv)", ["org.bluez.Adapter1", "Powered", new GLib.Variant("b", !a.encendido)]), () => this._pedirLectura());
    });
    this.menu.addMenuItem(alternar);

    if (a.encendido && this._dispositivos.length > 0) {
      this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
      this.menu.addMenuItem(this._titulo("Devices"));
      for (let d of this._dispositivos) {
        let sub = new PopupMenu.PopupSubMenuMenuItem(d.nombre);
        let accion = new PopupMenu.PopupMenuItem(d.conectado ? "Disconnect" : "Connect");
        accion.connect("activate", () => llamar(d.ruta, "org.bluez.Device1", d.conectado ? "Disconnect" : "Connect", null,
          () => this._pedirLectura()));
        sub.menu.addMenuItem(accion);
        this.menu.addMenuItem(sub);
      }
    }

    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
    let prefs = new PopupMenu.PopupMenuItem("Open Bluetooth Preferences…");
    prefs.connect("activate", () => Util.spawnCommandLine("mac-settings Bluetooth"));
    this.menu.addMenuItem(prefs);
  }

  on_applet_removed_from_panel() {
    if (this._suscripcion) Gio.DBus.system.signal_unsubscribe(this._suscripcion);
    if (this._pendiente) GLib.source_remove(this._pendiente);
  }
}

function main(metadata, orientation, panelHeight, instanceId) {
  return new BluetoothApplet(metadata, orientation, panelHeight, instanceId);
}
