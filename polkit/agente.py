#!/usr/bin/python3
"""Agente de polkit estilo Catalina: el diálogo «… wants to make changes. Enter your password to allow this».

Capturas de Catalina: 1.11.51 PM y 1.16.09 PM (Startup Disk), 1.33.32 PM (Restart) y 12.21.58 AM
(Finder). Es el mismo diálogo para cualquier pkexec: Startup Disk, Modifier Keys, Sharing, Date & Time…

  - User Name siempre se puede editar y viene escrito con el nombre completo («Jose Alberto de la Cruz
    Malena»). Se acepta el usuario (jmalena) o el nombre completo con sus espacios (el GECOS de passwd),
    siempre que polkit lo autorice; se resuelve antes de autenticar.
  - Con la clave mala la ventana solo se sacude, sin mensaje, y se puede volver a intentar.
  - El botón por defecto y el ícono salen de dos anotaciones de la acción en su .policy
    (org.mintmacos.boton y org.mintmacos.icono); las acciones ajenas dicen «OK».
  - La clave solo la toca PolkitAgent.Session (.response()): vive en el campo mientras se teclea, se borra
    al terminar y este código nunca la guarda, la escribe ni la imprime.

Se registra como agente de la sesión de login del proceso (un solo agente por sesión: si Cinnamon tiene el
suyo, no logra registrarse y sale con código 3 sin hacer nada). Mira polkit/LEEME.md.
"""
import grp
import math
import os
import pwd
import sys

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Polkit", "1.0")
gi.require_version("PolkitAgent", "1.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Polkit, PolkitAgent  # noqa: E402

RUTA_OBJETO = "/org/mintmacos/PolkitAgent"
APPS = os.path.expanduser("~/.local/share/mint-macos/settings")
ICONOS = os.path.join(APPS, "iconos")
CANDADO = os.path.join(APPS, "glifos", "LockLocked@2x.png")      # el candado naranja de la Mac (66 px)
BOTON_AJENO = "OK"
ANOTACION_BOTON = "org.mintmacos.boton"
ANOTACION_ICONO = "org.mintmacos.icono"
VERBOSO = bool(os.environ.get("MINT_POLKIT_VERBOSO"))

CSS = b"""
window.mp-polkit { background-color: #2f2f2f; border: 1px solid #1a1a1a; color: #ffffff; }
.mp-polkit-franja { background-color: #3a3a3a; min-height: 22px; border-bottom: 1px solid #1f1f1f; }
.mp-polkit label { color: #ffffff; }
.mp-polkit .mp-titulo { font-weight: 700; font-size: 10pt; }
.mp-polkit .mp-texto { font-size: 9pt; color: rgba(255, 255, 255, 0.78); }
.mp-polkit entry { background-color: #232323; color: #ffffff; border: 1px solid #1a1a1a;
                   border-radius: 3px; padding: 3px 6px; min-height: 16px; }
.mp-polkit entry:focus { border-color: #0a64d6; box-shadow: 0 0 0 2px rgba(10, 100, 214, 0.55); }
.mp-polkit button { background-image: none; background-color: #5a5a5a; color: #ffffff; border: 1px solid #3a3a3a;
                    border-radius: 4px; padding: 3px 14px; min-height: 16px; text-shadow: none; box-shadow: none; }
.mp-polkit button.mp-defecto { background-color: #0a64d6; border-color: #0a4fa8; }
"""


def log(*a):
    if VERBOSO:
        print("[mint-macos-polkit]", *a, file=sys.stderr, flush=True)


# Las acciones que Catalina enseña con su propio texto, en vez del genérico (captura 1.33.32 PM: reiniciar con
# otros usuarios conectados). «nombre» dice qué se escribe de entrada en Name: el usuario (login) o el nombre
# completo; «icono» es el círculo gris de la Mac con su signo.
VARIANTES = {
    "org.freedesktop.login1.reboot-multiple-sessions": {
        "titulo": "Restarting may cause other users logged into this computer to lose unsaved changes.",
        "texto": ("To avoid losing unsaved changes, log out all users before restarting. To continue without "
                  "saving changes, enter an administrator name and password and then click Restart."),
        "boton": "Restart",
        "rotulo_nombre": "Name:",
        "nombre": "login",
        "icono": "reiniciar",
        "extra": "Switch User\u2026",
    },
}


# ── los usuarios que polkit autoriza ─────────────────────────────────────────
def usuarios_autorizados(identidades):
    """{login: (uid, nombre completo)} de las identidades que polkit propone (usuarios y miembros de grupos)."""
    uids = set()
    for ident in identidades:
        if isinstance(ident, Polkit.UnixUser):
            uids.add(ident.get_uid())
        elif isinstance(ident, Polkit.UnixGroup):
            try:
                g = grp.getgrgid(ident.get_gid())
            except KeyError:
                continue
            for login in g.gr_mem:
                try:
                    uids.add(pwd.getpwnam(login).pw_uid)
                except KeyError:
                    pass
            for p in pwd.getpwall():               # los que lo tienen de grupo primario
                if p.pw_gid == g.gr_gid:
                    uids.add(p.pw_uid)
    salida = {}
    for uid in uids:
        try:
            p = pwd.getpwuid(uid)
        except KeyError:
            continue
        salida[p.pw_name] = (uid, p.pw_gecos.split(",")[0].strip() or p.pw_name)
    return salida


def resolver_usuario(texto, autorizados):
    """El login que corresponde a lo escrito: el usuario tal cual o el nombre completo (sin importar
    mayúsculas ni espacios de más); None si no es nadie de los autorizados."""
    t = " ".join(texto.split())
    if not t:
        return None
    if t in autorizados:
        return t
    for login, (_uid, nombre) in autorizados.items():
        if nombre.casefold() == t.casefold():
            return login
    return None


def nombre_por_defecto(autorizados, como_login=False):
    """Lo que se escribe de entrada: el nombre completo de quien está en la sesión (o su usuario, si lo pide la
    variante), si polkit lo autoriza."""
    try:
        yo = pwd.getpwuid(os.getuid()).pw_name
    except KeyError:
        yo = None
    if yo in autorizados:
        return yo if como_login else autorizados[yo][1]
    return sorted(autorizados.values(), key=lambda v: v[1])[0][1] if autorizados else ""


# ── lo que dice la acción: el botón y el ícono salen de sus anotaciones ─────────────────
def anotaciones(action_id):
    """(texto del botón, id del panel para el ícono): de la .policy de la acción, o («OK», None)."""
    boton, icono = BOTON_AJENO, None
    try:
        autoridad = Polkit.Authority.get_sync(None)
        for d in autoridad.enumerate_actions_sync(None):
            if d.get_action_id() == action_id:
                boton = d.get_annotation(ANOTACION_BOTON) or BOTON_AJENO
                icono = d.get_annotation(ANOTACION_ICONO)
                break
    except GLib.Error as e:
        log("sin anotaciones:", e.message)
    return boton, icono


# ── el diálogo ───────────────────────────────────────────────────────────────
class Dialogo(Gtk.Window):
    def __init__(self, mensaje, boton, icono_panel, autorizados, al_aceptar, al_cancelar, variante=None):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        v = variante or {}
        mensaje = v.get("titulo", mensaje)
        boton = v.get("boton", boton)
        self.autorizados = autorizados
        self.al_aceptar, self.al_cancelar = al_aceptar, al_cancelar
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_keep_above(True)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_skip_taskbar_hint(True)
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        self.set_title("Authentication")
        self.get_style_context().add_class("mp-polkit")
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), self._css(), 800)

        raiz = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        franja = Gtk.Box()
        franja.get_style_context().add_class("mp-polkit-franja")
        raiz.pack_start(franja, False, False, 0)
        cuerpo = Gtk.Box(spacing=18, margin=22)
        cuerpo.pack_start(self._icono_reiniciar() if v.get("icono") == "reiniciar" else self._icono(icono_panel),
                          False, False, 0)
        der = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        t = Gtk.Label(label=mensaje, xalign=0)
        t.get_style_context().add_class("mp-titulo")
        t.set_line_wrap(True)
        t.set_max_width_chars(48)
        der.pack_start(t, False, False, 0)
        s = Gtk.Label(label=v.get("texto", "Enter your password to allow this."), xalign=0)
        s.get_style_context().add_class("mp-texto")
        s.set_line_wrap(True)
        s.set_max_width_chars(48)
        der.pack_start(s, False, False, 0)
        g = Gtk.Grid(column_spacing=8, row_spacing=10, margin_top=14)
        for i, rotulo in enumerate((v.get("rotulo_nombre", "User Name:"), "Password:")):
            g.attach(Gtk.Label(label=rotulo, xalign=1.0), 0, i, 1, 1)
        self.usuario = Gtk.Entry(text=nombre_por_defecto(autorizados, v.get("nombre") == "login"), width_chars=34)
        self.usuario.set_hexpand(True)
        self.clave = Gtk.Entry(width_chars=34)
        self.clave.set_visibility(False)
        self.clave.set_input_purpose(Gtk.InputPurpose.PASSWORD)
        for e in (self.usuario, self.clave):
            e.connect("activate", lambda _e: self._aceptar())
        g.attach(self.usuario, 1, 0, 1, 1)
        g.attach(self.clave, 1, 1, 1, 1)
        der.pack_start(g, False, False, 0)
        botones = Gtk.Box(spacing=8, margin_top=10)
        self.cancelar = Gtk.Button(label="Cancel")
        self.cancelar.connect("clicked", lambda _b: self._cancelar())
        self.aceptar = Gtk.Button(label=boton)
        self.aceptar.get_style_context().add_class("mp-defecto")
        self.aceptar.connect("clicked", lambda _b: self._aceptar())
        botones.pack_end(self.aceptar, False, False, 0)
        botones.pack_end(self.cancelar, False, False, 0)
        if v.get("extra"):
            # Switch User…: lleva a la ventana de entrada (LightDM) y cierra este diálogo.
            extra = Gtk.Button(label=v["extra"])
            extra.connect("clicked", lambda _b: self._cambiar_usuario())
            botones.pack_start(extra, False, False, 0)
        der.pack_start(botones, False, False, 0)
        cuerpo.pack_start(der, True, True, 0)
        raiz.pack_start(cuerpo, True, True, 0)
        self.add(raiz)
        self.connect("key-press-event", self._tecla)
        self.connect("delete-event", lambda *_: self._cancelar() or True)
        self.show_all()
        self.usuario.select_region(0, 0)
        self.clave.grab_focus()

    @staticmethod
    def _css():
        p = Gtk.CssProvider()
        p.load_from_data(CSS)
        return p

    def _icono(self, panel):
        """El candado naranja de la Mac y, si la acción lo pide, el ícono de la app abajo a la derecha."""
        area = Gtk.DrawingArea()
        area.set_size_request(72, 80)
        try:
            candado = GdkPixbuf.Pixbuf.new_from_file_at_scale(CANDADO, 60, 60, True)
        except GLib.Error:
            candado = None
        insignia = None
        if panel:
            try:
                insignia = GdkPixbuf.Pixbuf.new_from_file_at_scale(os.path.join(ICONOS, panel + ".png"), 34, 34, True)
            except GLib.Error:
                insignia = None

        def pintar(_w, cr):
            if candado is not None:
                Gdk.cairo_set_source_pixbuf(cr, candado, 2, 6)
                cr.paint()
            if insignia is not None:
                Gdk.cairo_set_source_pixbuf(cr, insignia, 36, 40)
                cr.paint()
            return False
        area.connect("draw", pintar)
        return area

    def _icono_reiniciar(self):
        """El círculo gris de la Mac con el triángulo de Restart (64 px)."""
        area = Gtk.DrawingArea()
        area.set_size_request(72, 72)

        def pintar(_w, cr):
            cr.set_source_rgb(139 / 255, 141 / 255, 142 / 255)
            cr.arc(34, 34, 32, 0, 2 * math.pi)
            cr.fill()
            cr.set_source_rgb(1, 1, 1)
            cr.set_line_width(2.6)
            cr.set_line_join(1)
            cr.move_to(22, 34)
            cr.line_to(43, 21.5)
            cr.line_to(43, 46.5)
            cr.close_path()
            cr.stroke()
            return False
        area.connect("draw", pintar)
        return area

    def _cambiar_usuario(self):
        try:
            import subprocess
            subprocess.Popen(["dm-tool", "switch-to-greeter"], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            pass
        self._cancelar()

    # ── acciones ─────────────────────────────────────────────────────────
    def _tecla(self, _w, ev):
        if ev.keyval == Gdk.KEY_Escape:
            self._cancelar()
            return True
        return False

    def ocupado(self, si):
        for w in (self.usuario, self.clave, self.aceptar):
            w.set_sensitive(not si)
        self.cancelar.set_sensitive(True)

    def _aceptar(self):
        login = resolver_usuario(self.usuario.get_text(), self.autorizados)
        if login is None or not self.clave.get_text():
            self.sacudir()
            return
        self.ocupado(True)
        self.al_aceptar(login, self.clave.get_text())

    def _cancelar(self):
        self.al_cancelar()

    def borrar_clave(self):
        self.clave.set_text("")

    def sacudir(self):
        """Clave o usuario malos: la ventana se sacude de lado a lado, sin ningún mensaje."""
        self.ocupado(False)
        self.borrar_clave()
        self.clave.grab_focus()
        x0, y0 = self.get_position()
        pasos = [-12, 12, -10, 10, -6, 6, -3, 3, 0]
        estado = {"i": 0}

        def mover():
            i = estado["i"]
            if i >= len(pasos):
                return False
            self.move(x0 + pasos[i], y0)
            estado["i"] += 1
            return True
        GLib.timeout_add(28, mover)


# ── el agente ────────────────────────────────────────────────────────────────
# La interfaz que polkitd llama en el agente. Se implementa directo por D-Bus (en vez de subclasear
# PolkitAgent.Listener) porque PyGObject no puede completar el GAsyncReadyCallback de su método
# virtual: se cae con un fallo de segmentación al terminar. La autenticación sigue siendo de
# PolkitAgent.Session y de su ayudante setuid, que es quien avisa a polkitd del resultado.
XML_AGENTE = """
<node>
  <interface name="org.freedesktop.PolicyKit1.AuthenticationAgent">
    <method name="BeginAuthentication">
      <arg type="s" name="action_id" direction="in"/>
      <arg type="s" name="message" direction="in"/>
      <arg type="s" name="icon_name" direction="in"/>
      <arg type="a{ss}" name="details" direction="in"/>
      <arg type="s" name="cookie" direction="in"/>
      <arg type="a(sa{sv})" name="identities" direction="in"/>
    </method>
    <method name="CancelAuthentication">
      <arg type="s" name="cookie" direction="in"/>
    </method>
  </interface>
</node>
"""


class Agente:
    def __init__(self):
        self.peticiones = {}           # cookie → la petición en curso (su diálogo, su sesión y la invocación)
        self.conexion = None
        self.id_objeto = None
        self.autoridad = None
        self.sujeto = None

    # ── el registro ──────────────────────────────────────────────────────
    def registrar(self):
        """Exporta el objeto en el bus del sistema y se registra en polkitd para la sesión de este proceso.
        Devuelve False si ya hay otro agente en esa sesión (por ejemplo el de Cinnamon)."""
        self.conexion = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        info = Gio.DBusNodeInfo.new_for_xml(XML_AGENTE).interfaces[0]
        self.id_objeto = self.conexion.register_object(RUTA_OBJETO, info, self._llamada, None, None)
        self.autoridad = Polkit.Authority.get_sync(None)
        self.sujeto = Polkit.UnixSession.new_for_process_sync(os.getpid(), None)
        locale = (os.environ.get("LANG") or "en_US.UTF-8")
        try:
            self.autoridad.register_authentication_agent_sync(self.sujeto, locale, RUTA_OBJETO, None)
        except GLib.Error as e:
            print("No pude registrarme como agente de polkit:", e.message, file=sys.stderr)
            self.conexion.unregister_object(self.id_objeto)
            self.id_objeto = None
            return False
        return True

    def desregistrar(self):
        if self.id_objeto is None:
            return
        for cookie in list(self.peticiones):
            self._terminar(cookie, cancelada=True)
        try:
            self.autoridad.unregister_authentication_agent_sync(self.sujeto, RUTA_OBJETO, None)
        except GLib.Error:
            pass
        self.conexion.unregister_object(self.id_objeto)
        self.id_objeto = None

    # ── lo que polkitd pide ──────────────────────────────────────────────
    def _llamada(self, _conexion, _remitente, _ruta, _interfaz, metodo, parametros, invocacion):
        if metodo == "BeginAuthentication":
            self._comenzar(parametros, invocacion)
        elif metodo == "CancelAuthentication":
            self._terminar(parametros.unpack()[0], cancelada=True)
            invocacion.return_value(None)
        else:
            invocacion.return_error_literal(Gio.dbus_error_quark(), Gio.DBusError.UNKNOWN_METHOD, metodo)

    def _comenzar(self, parametros, invocacion):
        action_id, mensaje, _icono_tema, _detalles, cookie, _ = parametros.unpack()
        log("petición", action_id)
        identidades = []
        lista = parametros.get_child_value(5)
        for i in range(lista.n_children()):
            tipo, props = lista.get_child_value(i).unpack()
            if tipo == "unix-user" and "uid" in props:
                identidades.append(Polkit.UnixUser.new(props["uid"]))
            elif tipo == "unix-group" and "gid" in props:
                identidades.append(Polkit.UnixGroup.new(props["gid"]))
        autorizados = usuarios_autorizados(identidades)
        if not autorizados:
            invocacion.return_error_literal(Gio.dbus_error_quark(), Gio.DBusError.FAILED,
                                            "No hay usuarios autorizados para esta acción.")
            return
        boton, icono = anotaciones(action_id)
        peticion = {"invocacion": invocacion, "cookie": cookie, "sesion": None, "dialogo": None}
        self.peticiones[cookie] = peticion
        peticion["dialogo"] = Dialogo(mensaje, boton, icono, autorizados,
                                      lambda login, clave: self._autenticar(cookie, login, clave),
                                      lambda: self._terminar(cookie, cancelada=True),
                                      VARIANTES.get(action_id))

    def _autenticar(self, cookie, login, clave):
        peticion = self.peticiones.get(cookie)
        if peticion is None:
            return
        sesion = PolkitAgent.Session.new(Polkit.UnixUser.new_for_name(login), cookie)
        peticion["sesion"] = sesion
        sesion.connect("request", lambda s, _pregunta, _eco: s.response(clave))
        sesion.connect("show-error", lambda *_: None)
        sesion.connect("show-info", lambda *_: None)

        def completada(_s, gano):
            peticion["sesion"] = None
            if gano:
                self._terminar(cookie, cancelada=False)
            elif cookie in self.peticiones:
                peticion["dialogo"].sacudir()
        sesion.connect("completed", completada)
        sesion.initiate()

    def _terminar(self, cookie, cancelada):
        """Cierra el diálogo y contesta a polkitd. Si no se ganó la autorización, polkitd lo toma como cancelado."""
        peticion = self.peticiones.pop(cookie, None)
        if peticion is None:
            return
        if peticion["sesion"] is not None:
            try:
                peticion["sesion"].cancel()
            except Exception:  # noqa: BLE001
                pass
        if peticion["dialogo"] is not None:
            peticion["dialogo"].destroy()
        peticion["invocacion"].return_value(None)


def main():
    agente = Agente()
    if not agente.registrar():
        return 3
    log("registrado como agente de la sesión", agente.sujeto.get_session_id())
    bucle = GLib.MainLoop()
    for senal in (2, 15):                                   # SIGINT y SIGTERM: se da de baja antes de salir
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, senal, lambda: (agente.desregistrar(), bucle.quit(), False)[2])
    bucle.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
