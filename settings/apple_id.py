#!/usr/bin/env python3
"""Apple ID de System Preferences: una sola cuenta para iCloud Drive (rclone) y
para Mail y Calendar (Thunderbird).

Apple no usa la misma clave para todo, y esto se dice en la hoja:
  - iCloud Drive: la contraseña del Apple ID y el código de 2FA (rclone).
  - Mail y Calendar: una contraseña de app, que se genera en appleid.apple.com.

La contraseña del Apple ID no se guarda aquí: se le pasa a rclone (que guarda su
propia sesión de 30 días) y se olvida. La de app va al llavero del sistema
(libsecret), nunca a un archivo de texto.

En pruebas, MINT_APPLEID_PRUEBA=1 no toca rclone, Thunderbird ni la red: acepta
la contraseña «password» y el código «123456».
"""
import json
import os
import re
import subprocess
import time
import urllib.request
import xml.etree.ElementTree as ET

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GLib  # noqa: E402

try:
    gi.require_version("Secret", "1")
    from gi.repository import Secret  # noqa: E402
except (ValueError, ImportError):  # sin libsecret
    Secret = None

PRUEBA = bool(os.environ.get("MINT_APPLEID_PRUEBA"))
REMOTO = os.environ.get("ICLOUD_REMOTO", "icloud")
RCLONE = os.path.expanduser("~/.local/bin/rclone")
SERVICIO = os.environ.get("ICLOUD_SERVICIO", "rclone-icloud")
HOGAR = os.path.expanduser("~")
TB = os.path.join(HOGAR, ".thunderbird")
ID_TB = "mmacos"  # prefijo de lo que esta hoja crea en Thunderbird
MARCA_INI = "// >>> mint-macos Apple ID (no editar: lo regenera System Preferences)"
MARCA_FIN = "// <<< mint-macos Apple ID"

ESQUEMA = None
if Secret is not None:
    ESQUEMA = Secret.Schema.new(
        "org.mintmacos.AppleID", Secret.SchemaFlags.NONE,
        {"servicio": Secret.SchemaAttributeType.STRING, "apple_id": Secret.SchemaAttributeType.STRING})


class ErrorAppleID(Exception):
    pass


# ── Estado ───────────────────────────────────────────────────────────────────
def _rclone(*args, entrada=None, timeout=90):
    try:
        r = subprocess.run([RCLONE, *args], input=entrada, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise ErrorAppleID(f"rclone did not respond: {e}")
    return r


def apple_id_actual():
    """El Apple ID con sesión en rclone, o None."""
    if PRUEBA:
        return os.environ.get("MINT_APPLEID_PRUEBA_ID") or None
    r = _rclone("config", "show", REMOTO, timeout=15)
    if r.returncode != 0:
        return None
    datos = dict(l.split(" = ", 1) for l in r.stdout.splitlines() if " = " in l)
    if datos.get("type") != "iclouddrive" or not datos.get("apple_id"):
        return None
    return datos["apple_id"] if (datos.get("trust_token") or datos.get("cookies")) else None


def mail_configurado():
    return ESQUEMA is not None and bool(_buscar_clave_app(None))


def _buscar_clave_app(apple_id):
    if ESQUEMA is None:
        return None
    attrs = {"servicio": "mail"}
    if apple_id:
        attrs["apple_id"] = apple_id
    try:
        return Secret.password_lookup_sync(ESQUEMA, attrs, None)
    except GLib.Error:
        return None


# ── iCloud Drive (rclone) ────────────────────────────────────────────────────
def iniciar_icloud(apple_id, clave):
    """Primer paso. Devuelve None si ya quedó, o el estado (dict) si Apple pide
    el código de 2FA. Lanza ErrorAppleID si Apple rechaza."""
    if PRUEBA:
        if clave != "password":
            raise ErrorAppleID("Incorrect Apple ID or password.")
        return {"state": "prueba", "pregunta": "Verification code"}
    # La clave va ofuscada (rclone obscure) para que no se vea en claro en la lista
    # de procesos; es reversible, la protección es solo contra un ps.
    ofus = _rclone("obscure", "-", entrada=clave).stdout.strip()
    r = _rclone("config", "create", REMOTO, "iclouddrive", f"apple_id={apple_id}", f"password={ofus}",
                "--no-obscure", "--non-interactive", timeout=120)
    return _leer_estado(r)


def seguir_icloud(estado, codigo):
    if PRUEBA:
        if codigo != "123456":
            raise ErrorAppleID("Incorrect verification code.")
        return None
    r = _rclone("config", "update", REMOTO, "--continue", "--state", estado["state"], "--result", codigo,
                "--non-interactive", timeout=120)
    return _leer_estado(r)


LOG = os.path.expanduser("~/.local/share/mint-macos/settings/apple-id.log")


def _guardar_log(r):
    """La salida completa de rclone (stdout y stderr, nunca los argumentos: ahí va la clave) para
    diagnosticar un Sign In que falla."""
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(os.open(LOG, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600), "a", encoding="utf-8") as f:
            f.write("--- %s rc=%s\n[stderr]\n%s\n[stdout]\n%s\n" % (
                time.strftime("%Y-%m-%d %H:%M:%S"), r.returncode, (r.stderr or "")[-6000:], (r.stdout or "")[-6000:]))
    except OSError:
        pass


def mensaje_de_error(r):
    """Lo que se le enseña al usuario cuando rclone falla. Nunca «la última línea a ciegas»: rclone puede
    devolver un bloque JSON de varias líneas cuya última línea es «}». Orden: el campo Error/error de un JSON;
    si no, la última línea que diga «error» o «failed» (sin el prefijo de nivel «NOTICE:»); si no, un texto fijo."""
    generico = "Apple did not accept the account."
    for texto in ((r.stdout or "").strip(), (r.stderr or "").strip()):
        if not texto:
            continue
        # ¿Hay un JSON, solo o rodeado de texto?
        ini, fin = texto.find("{"), texto.rfind("}")
        if ini != -1 and fin > ini:
            try:
                d = json.loads(texto[ini:fin + 1])
                err = d.get("Error") or d.get("error") if isinstance(d, dict) else None
                if err:
                    return str(err).strip().splitlines()[0]
            except ValueError:
                pass
    for texto in ((r.stderr or "").strip(), (r.stdout or "").strip()):
        lineas = [l.strip() for l in texto.splitlines() if l.strip()]
        for l in reversed(lineas):
            if re.search(r"error|failed|incorrect|invalid", l, re.I) and l not in ("{", "}"):
                return re.sub(r"^(NOTICE|ERROR|CRITICAL|WARNING)\s*:\s*", "", l).strip()
    return generico


def _leer_estado(r):
    if r.returncode != 0:
        _guardar_log(r)
        raise ErrorAppleID(mensaje_de_error(r))
    try:
        d = json.loads(r.stdout) if r.stdout.strip() else {}
    except ValueError:
        d = {}
    if d.get("State"):
        pregunta = (d.get("Option") or {}).get("Help") or "Verification code"
        return {"state": d["State"], "pregunta": pregunta}
    return None


def montar_icloud():
    """Levanta el servicio que monta ~/iCloud Drive (lo instala icloud.sh montar)."""
    if PRUEBA:
        return
    subprocess.run(["systemctl", "--user", "restart", SERVICIO], capture_output=True, timeout=30)


# ── Mail y Calendar (Thunderbird) ────────────────────────────────────────────
def thunderbird_abierto():
    if PRUEBA:
        return False
    return subprocess.run(["pgrep", "-x", "thunderbird"], capture_output=True).returncode == 0 or \
        subprocess.run(["pgrep", "-x", "thunderbird-bin"], capture_output=True).returncode == 0


def perfil_thunderbird():
    """La carpeta del perfil por defecto de Thunderbird."""
    ini = os.path.join(TB, "profiles.ini")
    if not os.path.exists(ini):
        raise ErrorAppleID("Thunderbird has no profile: open it once and quit.")
    import configparser
    cfg = configparser.ConfigParser()
    cfg.read(ini)
    # El de [Install…] (el que Thunderbird usa de verdad) manda sobre el de [Profile…].
    inst = os.path.join(TB, "installs.ini")
    if os.path.exists(inst):
        c2 = configparser.ConfigParser()
        c2.read(inst)
        for s in c2.sections():
            if c2[s].get("Default"):
                return os.path.join(TB, c2[s]["Default"])
    for s in cfg.sections():
        if s.startswith("Profile") and cfg[s].get("Default") == "1":
            ruta = cfg[s]["Path"]
            return ruta if cfg[s].get("IsRelative", "1") == "0" else os.path.join(TB, ruta)
    raise ErrorAppleID("Could not find Thunderbird's default profile.")


def _pref_actual(prefs_js, nombre):
    m = re.search(r'user_pref\("%s",\s*"([^"]*)"\);' % re.escape(nombre), prefs_js)
    return m.group(1) if m else ""


def _lista_con(actual, nuevo):
    partes = [p for p in actual.split(",") if p]
    if nuevo not in partes:
        partes.append(nuevo)
    return ",".join(partes)


def bloque_userjs(perfil, apple_id, nombre, calendarios):
    """El bloque de user.js con la cuenta de iCloud (IMAP/SMTP) y sus calendarios.
    Mezcla las listas que Thunderbird ya tiene en prefs.js (user.js las pisa enteras)."""
    try:
        prefs = open(os.path.join(perfil, "prefs.js"), encoding="utf-8").read()
    except OSError:
        prefs = ""
    cuentas = _lista_con(_pref_actual(prefs, "mail.accountmanager.accounts"), f"{ID_TB}_acc")
    smtps = _lista_con(_pref_actual(prefs, "mail.smtpservers"), f"{ID_TB}_smtp")
    l = [MARCA_INI]

    def p(k, v):
        l.append('user_pref("%s", %s);' % (k, json.dumps(v)))

    p("mail.accountmanager.accounts", cuentas)
    p(f"mail.account.{ID_TB}_acc.server", f"{ID_TB}_srv")
    p(f"mail.account.{ID_TB}_acc.identities", f"{ID_TB}_id")
    p(f"mail.server.{ID_TB}_srv.type", "imap")
    p(f"mail.server.{ID_TB}_srv.hostname", "imap.mail.me.com")
    p(f"mail.server.{ID_TB}_srv.port", 993)
    p(f"mail.server.{ID_TB}_srv.socketType", 3)       # SSL/TLS
    p(f"mail.server.{ID_TB}_srv.userName", apple_id)
    p(f"mail.server.{ID_TB}_srv.name", "iCloud")
    p(f"mail.server.{ID_TB}_srv.authMethod", 3)       # contraseña normal
    p(f"mail.identity.{ID_TB}_id.useremail", apple_id)
    p(f"mail.identity.{ID_TB}_id.fullName", nombre)
    p(f"mail.identity.{ID_TB}_id.smtpServer", f"{ID_TB}_smtp")
    p("mail.smtpservers", smtps)
    p(f"mail.smtpserver.{ID_TB}_smtp.hostname", "smtp.mail.me.com")
    p(f"mail.smtpserver.{ID_TB}_smtp.port", 587)
    p(f"mail.smtpserver.{ID_TB}_smtp.try_ssl", 2)      # STARTTLS
    p(f"mail.smtpserver.{ID_TB}_smtp.username", apple_id)
    p(f"mail.smtpserver.{ID_TB}_smtp.authMethod", 3)
    p(f"mail.smtpserver.{ID_TB}_smtp.description", "iCloud")
    for i, (url, nom) in enumerate(calendarios):
        c = f"calendar.registry.{ID_TB}_cal{i}"
        p(c + ".type", "caldav")
        p(c + ".uri", url)
        p(c + ".name", nom)
        p(c + ".username", apple_id)
        p(c + ".cache.enabled", True)
    l.append(MARCA_FIN)
    return "\n".join(l) + "\n"


def escribir_userjs(perfil, bloque):
    ruta = os.path.join(perfil, "user.js")
    previo = open(ruta, encoding="utf-8").read() if os.path.exists(ruta) else ""
    previo = re.sub(re.escape(MARCA_INI) + r".*?" + re.escape(MARCA_FIN) + r"\n?", "", previo, flags=re.S)
    with open(ruta, "w", encoding="utf-8") as f:
        f.write(previo + ("\n" if previo and not previo.endswith("\n") else "") + bloque)


def _propfind(url, apple_id, clave, cuerpo, profundidad="0"):
    req = urllib.request.Request(url, data=cuerpo.encode(), method="PROPFIND", headers={
        "Depth": profundidad, "Content-Type": "application/xml; charset=utf-8"})
    mgr = urllib.request.HTTPPasswordMgrWithDefaultRealm()
    mgr.add_password(None, url, apple_id, clave)
    op = urllib.request.build_opener(urllib.request.HTTPBasicAuthHandler(mgr))
    # Basic desde el primer envío (iCloud contesta 401 sin ofrecer el reto a veces).
    import base64
    req.add_header("Authorization", "Basic " + base64.b64encode(f"{apple_id}:{clave}".encode()).decode())
    try:
        return op.open(req, timeout=30).read().decode()
    except urllib.error.HTTPError as e:
        if e.code == 401:
            raise ErrorAppleID("Apple did not accept the app-specific password.")
        raise ErrorAppleID(f"CalDAV answered {e.code}.")
    except OSError as e:
        raise ErrorAppleID(f"Cannot reach iCloud: {e}")


def descubrir_calendarios(apple_id, clave):
    """CalDAV de iCloud: usuario → principal → calendar-home → lista de calendarios.
    Devuelve [(url, nombre)]."""
    ns = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:caldav"}
    base = "https://caldav.icloud.com"
    x = _propfind(base + "/", apple_id, clave,
                  '<d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal/></d:prop></d:propfind>')
    principal = ET.fromstring(x).find(".//d:current-user-principal/d:href", ns)
    if principal is None:
        raise ErrorAppleID("iCloud did not return the calendar principal.")
    x = _propfind(base + principal.text, apple_id, clave,
                  '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop>'
                  '<c:calendar-home-set/></d:prop></d:propfind>')
    casa = ET.fromstring(x).find(".//c:calendar-home-set/d:href", ns)
    if casa is None:
        raise ErrorAppleID("iCloud did not return the calendar home.")
    destino = casa.text if casa.text.startswith("http") else base + casa.text
    x = _propfind(destino, apple_id, clave,
                  '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop>'
                  '<d:displayname/><d:resourcetype/></d:prop></d:propfind>', "1")
    cals = []
    for r in ET.fromstring(x).findall("d:response", ns):
        if r.find(".//c:calendar", ns) is None:
            continue
        href = r.find("d:href", ns).text
        nom = r.find(".//d:displayname", ns)
        cals.append(((href if href.startswith("http") else "https://caldav.icloud.com" + href),
                     (nom.text if nom is not None and nom.text else "iCloud")))
    return cals


def configurar_mail_y_calendar(apple_id, nombre, clave_app):
    """Guarda la contraseña de app en el llavero y deja Mail y Calendar en
    Thunderbird. Devuelve cuántos calendarios quedaron."""
    if PRUEBA:
        return 2
    if thunderbird_abierto():
        raise ErrorAppleID("Quit Thunderbird and try again (it reads its settings when it opens).")
    cals = descubrir_calendarios(apple_id, clave_app)   # también comprueba la contraseña
    if ESQUEMA is not None:
        try:
            Secret.password_store_sync(ESQUEMA, {"servicio": "mail", "apple_id": apple_id},
                                       Secret.COLLECTION_DEFAULT, f"Apple ID (app) {apple_id}", clave_app, None)
        except GLib.Error as e:
            raise ErrorAppleID(f"Could not save the password in the keyring: {e.message}")
    perfil = perfil_thunderbird()
    escribir_userjs(perfil, bloque_userjs(perfil, apple_id, nombre, cals))
    return len(cals)


def cerrar_sesion():
    """Sign Out: quita el remoto de rclone, el llavero y el bloque de Thunderbird."""
    if PRUEBA:
        return
    subprocess.run(["systemctl", "--user", "stop", SERVICIO], capture_output=True, timeout=30)
    _rclone("config", "delete", REMOTO, timeout=15)
    if ESQUEMA is not None:
        try:
            Secret.password_clear_sync(ESQUEMA, {"servicio": "mail"}, None)
        except GLib.Error:
            pass
    try:
        perfil = perfil_thunderbird()
        ruta = os.path.join(perfil, "user.js")
        if os.path.exists(ruta):
            escribir_userjs(perfil, "")
    except ErrorAppleID:
        pass


# ── La hoja ──────────────────────────────────────────────────────────────────
class HojaAppleID(Gtk.Dialog):
    """Sign In como la hoja de Catalina, en dos pasos: iCloud Drive (clave y
    código) y Mail y Calendar (contraseña de app)."""

    def __init__(self, padre, al_terminar=None):
        super().__init__(title="Apple ID", transient_for=padre, modal=True, destroy_with_parent=True)
        self.al_terminar = al_terminar
        self.get_style_context().add_class("mp-hoja")
        self.set_default_size(420, -1)
        self.set_resizable(False)
        self.estado = None
        self.apple_id = ""

        caja = self.get_content_area()
        caja.set_spacing(10)
        caja.set_border_width(24)
        self.titulo = Gtk.Label(xalign=0.5)
        self.titulo.get_style_context().add_class("mp-hoja-titulo")
        self.texto = Gtk.Label(xalign=0.5, wrap=True, max_width_chars=44, justify=Gtk.Justification.CENTER)
        self.texto.get_style_context().add_class("mp-hoja-texto")
        caja.pack_start(self.titulo, False, False, 0)
        caja.pack_start(self.texto, False, False, 0)

        self.campos = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        caja.pack_start(self.campos, False, False, 6)
        self.aviso = Gtk.Label(xalign=0.5, wrap=True, max_width_chars=44)
        self.aviso.get_style_context().add_class("mp-hoja-error")
        caja.pack_start(self.aviso, False, False, 0)

        self.cancelar = self.add_button("Cancel", Gtk.ResponseType.CANCEL)
        self.siguiente = self.add_button("Next", Gtk.ResponseType.OK)
        self.siguiente.get_style_context().add_class("suggested-action")
        self.set_default_response(Gtk.ResponseType.OK)
        self.connect("response", self._respuesta)
        self._paso_cuenta()
        self.show_all()

    # utilidades
    def _limpiar(self):
        for c in self.campos.get_children():
            self.campos.remove(c)
        self.aviso.set_text("")

    def _campo(self, etiqueta, secreto=False, texto=""):
        e = Gtk.Entry()
        e.set_placeholder_text(etiqueta)
        e.set_visibility(not secreto)
        e.set_text(texto)
        e.set_activates_default(True)
        self.campos.pack_start(e, False, False, 0)
        e.show()
        return e

    def _ocupado(self, si):
        self.siguiente.set_sensitive(not si)
        self.campos.set_sensitive(not si)
        self.aviso.set_text("Connecting…" if si else "")

    def _hilo(self, trabajo, listo):
        """Corre `trabajo` fuera del hilo de la interfaz (rclone y la red tardan)."""
        import threading
        self._ocupado(True)

        def corre():
            try:
                res, err = trabajo(), None
            except ErrorAppleID as e:
                res, err = None, str(e)
            except Exception as e:  # noqa: BLE001
                res, err = None, f"Unexpected error: {e}"
            GLib.idle_add(self._vuelve, listo, res, err)
        threading.Thread(target=corre, daemon=True).start()

    def _vuelve(self, listo, res, err):
        self._ocupado(False)
        if err:
            self.aviso.set_text(err)
        else:
            listo(res)
        return False

    # pasos
    def _paso_cuenta(self):
        self.paso = "cuenta"
        self._limpiar()
        self.titulo.set_text("Sign in with your Apple ID")
        self.texto.set_text("Connects iCloud Drive. Mail and Calendar come next with an app-specific password.")
        self.e_id = self._campo("Apple ID", texto=self.apple_id)
        self.e_clave = self._campo("Password", secreto=True)
        self.siguiente.set_label("Next")
        self.e_id.grab_focus()

    def _paso_codigo(self, pregunta):
        self.paso = "codigo"
        self._limpiar()
        self.titulo.set_text("Verification Code")
        self.texto.set_text("Enter the six-digit code that was sent to your other Apple devices.")
        self.e_codigo = self._campo("000000")
        self.e_codigo.set_max_length(8)
        self.siguiente.set_label("Verify")
        self.e_codigo.grab_focus()

    def _paso_mail(self):
        self.paso = "mail"
        self._limpiar()
        self.titulo.set_text("Mail and Calendar")
        self.texto.set_text("iCloud Drive is connected. For Mail and Calendar in Thunderbird, Apple requires an "
                            "app-specific password: create one at appleid.apple.com → Sign-In and Security → "
                            "App-Specific Passwords.")
        abrir = Gtk.LinkButton.new_with_label("https://appleid.apple.com/account/manage",
                                              "Open appleid.apple.com")
        self.campos.pack_start(abrir, False, False, 0)
        abrir.show()
        self.e_app = self._campo("App-specific password (xxxx-xxxx-xxxx-xxxx)", secreto=True)
        self.siguiente.set_label("Set Up")
        self.cancelar.set_label("Not Now")
        self.e_app.grab_focus()

    def _paso_fin(self, cuantos):
        self.paso = "fin"
        self._limpiar()
        self.titulo.set_text("You’re all set")
        self.texto.set_text("iCloud Drive is mounted." + (
            f" Mail and {cuantos} calendar(s) are set up: open Thunderbird and, if it asks, "
            "choose the saved password." if cuantos is not None else ""))
        self.siguiente.set_label("Done")
        self.cancelar.hide()

    def _respuesta(self, _d, r):
        if r != Gtk.ResponseType.OK:
            if self.paso in ("mail",):
                self._paso_fin(None)
                self.al_terminar and self.al_terminar()
                return
            self._cerrar()
            return
        if self.paso == "cuenta":
            self.apple_id = self.e_id.get_text().strip()
            clave = self.e_clave.get_text()
            if not self.apple_id or not clave:
                self.aviso.set_text("Enter your Apple ID and password.")
                return
            self._hilo(lambda: iniciar_icloud(self.apple_id, clave), self._tras_clave)
        elif self.paso == "codigo":
            cod = self.e_codigo.get_text().strip()
            if not cod:
                return
            self._hilo(lambda: seguir_icloud(self.estado, cod), self._tras_codigo)
        elif self.paso == "mail":
            app = self.e_app.get_text().strip()
            if not app:
                self.aviso.set_text("Paste the app-specific password.")
                return
            nombre = GLib.get_real_name() or self.apple_id
            self._hilo(lambda: configurar_mail_y_calendar(self.apple_id, nombre, app), self._tras_mail)
        else:
            self._cerrar()

    def _tras_clave(self, estado):
        if estado:
            self.estado = estado
            self._paso_codigo(estado["pregunta"])
        else:
            self._tras_codigo(None)

    def _tras_codigo(self, estado):
        if estado:                       # pidió otro código: se vuelve a preguntar
            self.estado = estado
            self.aviso.set_text("Apple asked for another code.")
            return
        montar_icloud()
        self.al_terminar and self.al_terminar()
        self._paso_mail()

    def _tras_mail(self, cuantos):
        self.al_terminar and self.al_terminar()
        self._paso_fin(cuantos)

    def _cerrar(self):
        self.destroy()
