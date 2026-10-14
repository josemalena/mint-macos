/*
 * Fast User Switching (usuario@macos).
 *
 * El menú que sale al pulsar la silueta de la derecha de la barra de Catalina
 * (captura de José, Screen Shot 1.32.26 PM):
 *
 *   ✓ Guest User            solo si LightDM permite invitados; con la
 *   ● <Nombre completo>     marca la cuenta de esta sesión
 *   ─────────────
 *     Login Window…
 *   ─────────────
 *     Users & Groups Preferences…
 *
 * Sale del applet user@cinnamon.org (GPL), al que reemplaza en la barra. Cambiar
 * de cuenta bloquea esta sesión y le pide a LightDM la otra (dm-tool), como
 * hace el applet de Cinnamon con «Switch User».
 */

const Applet = imports.ui.applet;
const Lang = imports.lang;
const PopupMenu = imports.ui.popupMenu;
const Util = imports.misc.util;
const AccountsService = imports.gi.AccountsService;
const { Clutter, Gio, GLib, St } = imports.gi;

const TAMANO_AVATAR = 24;
const ANCHO_MARCA = 16;

// ¿Deja LightDM entrar como invitado? Lee la configuración en el orden en que
// LightDM la lee: gana el último «allow-guest» y hace falta el ayudante.
function invitadoPermitido() {
  if (!GLib.file_test("/usr/lib/lightdm/lightdm-guest-session", GLib.FileTest.EXISTS)) return false;
  let archivos = [];
  for (let dir of ["/usr/share/lightdm/lightdm.conf.d", "/etc/lightdm/lightdm.conf.d"]) {
    try {
      let e = Gio.File.new_for_path(dir).enumerate_children("standard::name", 0, null);
      let nombres = [], info;
      while ((info = e.next_file(null)) !== null) {
        if (info.get_name().endsWith(".conf")) nombres.push(info.get_name());
      }
      nombres.sort();
      for (let n of nombres) archivos.push(`${dir}/${n}`);
    } catch (e) { /* no existe */ }
  }
  archivos.push("/etc/lightdm/lightdm.conf");
  let permitido = false;
  for (let f of archivos) {
    try {
      let [ok, bytes] = GLib.file_get_contents(f);
      if (!ok) continue;
      for (let linea of String.fromCharCode.apply(null, bytes).split("\n")) {
        let m = linea.match(/^\s*allow-guest\s*=\s*(\w+)/);
        if (m) permitido = m[1].toLowerCase() === "true";
      }
    } catch (e) { /* no se puede leer */ }
  }
  return permitido;
}

function esInvitado(nombre) {
  return nombre.indexOf("guest-") === 0;
}

// La marca naranja de la cuenta de esta sesión: un círculo con una palomita.
function marca() {
  let area = new St.DrawingArea({ width: ANCHO_MARCA, height: ANCHO_MARCA });
  area.connect("repaint", a => {
    let cr = a.get_context();
    cr.setSourceRGBA(0.96, 0.62, 0.20, 1);
    cr.arc(8, 8, 7, 0, 2 * Math.PI);
    cr.fill();
    cr.setSourceRGBA(1, 1, 1, 1);
    cr.setLineWidth(1.8);
    cr.moveTo(4.6, 8.2);
    cr.lineTo(7, 10.6);
    cr.lineTo(11.6, 5.6);
    cr.stroke();
    cr.$dispose();
  });
  return area;
}

// El avatar gris del invitado: círculo con una silueta, dibujada.
function avatarInvitado() {
  let area = new St.DrawingArea({ width: TAMANO_AVATAR, height: TAMANO_AVATAR });
  area.connect("repaint", a => {
    let cr = a.get_context();
    cr.setSourceRGBA(0.62, 0.63, 0.65, 1);
    cr.arc(12, 12, 12, 0, 2 * Math.PI);
    cr.fill();
    cr.setSourceRGBA(0.82, 0.83, 0.85, 1);
    cr.arc(12, 9.5, 4.2, 0, 2 * Math.PI);
    cr.fill();
    cr.arc(12, 23, 8.4, Math.PI, 2 * Math.PI);
    cr.fill();
    cr.$dispose();
  });
  return area;
}

class UsuarioApplet extends Applet.Applet {
  constructor(metadata, orientation, panelHeight, instanceId) {
    super(orientation, panelHeight, instanceId);
    this.setAllowedLayout(Applet.AllowedLayout.BOTH);

    this._icono = new St.Icon({
      icon_name: "xsi-avatar-default-symbolic",
      icon_type: St.IconType.SYMBOLIC,
      icon_size: this.getPanelIconSize(St.IconType.SYMBOLIC),
    });
    this.actor.add_actor(this._icono);

    this._usuarios = AccountsService.UserManager.get_default();
    this._actual = GLib.get_user_name();
    // La lista de cuentas llega de AccountsService un momento después de arrancar.
    this._usuarios.connect("notify::is-loaded", () => this._armar());

    this.menuManager = new PopupMenu.PopupMenuManager(this);
    this.menu = new Applet.AppletPopupMenu(this, orientation);
    this.menuManager.addMenu(this.menu);
    this.menu.connect("open-state-changed", (m, abierto) => { if (abierto) this._armar(); });
    this._armar();
  }

  on_applet_clicked() {
    this.menu.toggle();
  }

  on_panel_height_changed() {
    this._icono.set_icon_size(this.getPanelIconSize(St.IconType.SYMBOLIC));
  }

  on_panel_icon_size_changed() {
    this._icono.set_icon_size(this.getPanelIconSize(St.IconType.SYMBOLIC));
  }

  // Un renglón: la marca (o su hueco), el avatar y el nombre, en una caja a la izquierda.
  _fila(conMarca, avatar, texto, habilitado, alActivar) {
    let item = new PopupMenu.PopupBaseMenuItem({ reactive: habilitado, activate: habilitado });
    let caja = new St.BoxLayout({ vertical: false, x_expand: true });
    let hueco = new St.Bin({ width: ANCHO_MARCA, height: ANCHO_MARCA, y_align: St.Align.MIDDLE, style: "margin-right: 6px;" });
    if (conMarca) hueco.set_child(marca());
    caja.add_actor(hueco);
    let marco = new St.Bin({ style: "margin-right: 8px;", y_align: St.Align.MIDDLE });
    marco.set_child(avatar);
    caja.add_actor(marco);
    let etiqueta = new St.Label({ text: texto, y_align: Clutter.ActorAlign.CENTER });
    if (!habilitado) etiqueta.set_style("color: rgba(255,255,255,0.6);");
    caja.add_actor(etiqueta);
    item.addActor(caja, { span: -1, expand: true });
    if (alActivar) item.connect("activate", alActivar);
    return item;
  }

  _bloquearYCambiar(orden) {
    Util.spawnCommandLine("cinnamon-screensaver-command --lock");
    Util.spawnCommandLine(orden);
  }

  _armar() {
    this.menu.removeAll();
    let hayLightDM = !!GLib.getenv("XDG_SEAT_PATH");
    let soyInvitado = esInvitado(this._actual);

    if (invitadoPermitido()) {
      this.menu.addMenuItem(this._fila(soyInvitado, avatarInvitado(), "Guest User", !soyInvitado,
        () => this._bloquearYCambiar("dm-tool switch-to-guest")));
    }

    for (let u of this._usuarios.list_users()) {
      let nombre = u.get_user_name();
      if (u.is_system_account() || esInvitado(nombre) || u.get_locked()) continue;
      // La foto de la cuenta si la tiene; si no, la silueta dibujada.
      let foto = u.get_icon_file();
      let avatar;
      if (foto && GLib.file_test(foto, GLib.FileTest.EXISTS)) {
        avatar = new St.Bin({ width: TAMANO_AVATAR, height: TAMANO_AVATAR,
          style: `background-image: url("${foto}"); background-size: cover; border-radius: ${TAMANO_AVATAR / 2}px;` });
      } else {
        avatar = avatarInvitado();
      }
      let esActual = nombre === this._actual;
      this.menu.addMenuItem(this._fila(esActual, avatar, u.get_real_name() || nombre, !esActual && hayLightDM,
        () => this._bloquearYCambiar(`dm-tool switch-to-user ${nombre}`)));
    }

    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
    let login = new PopupMenu.PopupMenuItem("Login Window…", { reactive: hayLightDM });
    if (hayLightDM) login.connect("activate", () => this._bloquearYCambiar("dm-tool switch-to-greeter"));
    this.menu.addMenuItem(login);
    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
    let prefs = new PopupMenu.PopupMenuItem("Users & Groups Preferences…");
    prefs.connect("activate", () => Util.spawnCommandLine("mac-settings users"));
    this.menu.addMenuItem(prefs);
  }

  on_applet_removed_from_panel() {}
}

function main(metadata, orientation, panelHeight, instanceId) {
  return new UsuarioApplet(metadata, orientation, panelHeight, instanceId);
}
