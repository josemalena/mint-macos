//! org.mintmacos.AppleID1: el Apple ID de System Preferences, sin ventana. Una sola cuenta para
//! iCloud Drive (rclone, con la contraseña del Apple ID y el código de 2FA) y para Mail y Calendar
//! en Thunderbird (con una contraseña de app). Sale de settings/apple_id.py; la hoja de Sign In la
//! pone Dev-Dock en Vala. Contrato y «qué se guarda y dónde»: DBUS.md.
//!
//! La contraseña y el código nunca van a la línea de comando (se ve en /proc/<pid>/cmdline) ni al
//! registro: a rclone por stdin y por variables de entorno.
use std::collections::HashMap;
use std::fs;
use std::io::Write as _;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use zbus::interface;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{OwnedValue, Value};

const NOMBRE: &str = "org.mintmacos.AppleID1";
const RUTA: &str = "/org/mintmacos/AppleID1";
const SIN_LLAMADAS: Duration = Duration::from_secs(120);
const CON_CODIGO_PENDIENTE: Duration = Duration::from_secs(600);
const ID_TB: &str = "mmacos"; // prefijo de lo que se crea en Thunderbird (el mismo de apple_id.py)
const MARCA_INI: &str = "// >>> mint-macos Apple ID (no editar: lo regenera System Preferences)";
const MARCA_FIN: &str = "// <<< mint-macos Apple ID";
// El esquema de libsecret de apple_id.py: lo que guardó el panel en Python se sigue encontrando.
const ESQUEMA: &str = "org.mintmacos.AppleID";

type Dict = HashMap<String, OwnedValue>;

// ── Dónde está cada cosa ─────────────────────────────────────────────────────
/// Lo que el servicio toca. En producción sale de las variables de siempre (las de icloud.sh); las
/// pruebas lo arman a mano con un rclone, un systemctl, un CalDAV y un llavero falsos.
#[derive(Clone)]
struct Entorno {
    rclone: PathBuf,
    remoto: String,
    servicio: String,
    unidades: PathBuf,
    carpeta: PathBuf,
    systemctl: PathBuf,
    caldav: String,
    thunderbird: PathBuf,
    llavero: Llavero,
    mirar_procesos: bool,
    log: PathBuf,
}

#[derive(Clone)]
enum Llavero {
    /// El llavero de la sesión (Secret Service por D-Bus).
    Sistema,
    /// Solo en pruebas: un archivo con «apple_id\tclave» por línea.
    #[cfg_attr(not(test), allow(dead_code))]
    Archivo(PathBuf),
}

impl Entorno {
    fn real() -> Self {
        let hogar = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
        let var = |k: &str, d: &str| std::env::var(k).unwrap_or_else(|_| d.to_string());
        let servicio = var("ICLOUD_SERVICIO", "rclone-icloud");
        Entorno {
            rclone: hogar.join(".local/bin/rclone"),
            remoto: var("ICLOUD_REMOTO", "icloud"),
            servicio,
            unidades: hogar.join(".config/systemd/user"),
            carpeta: std::env::var_os("ICLOUD_CARPETA").map(PathBuf::from).unwrap_or_else(|| hogar.join("iCloud Drive")),
            systemctl: PathBuf::from("systemctl"),
            caldav: "https://caldav.icloud.com".into(),
            thunderbird: hogar.join(".thunderbird"),
            llavero: Llavero::Sistema,
            mirar_procesos: true,
            log: hogar.join(".local/share/mint-macos/settings/apple-id.log"),
        }
    }
}

#[derive(Debug)]
struct Error(String);

impl<T: std::fmt::Display> From<T> for Error {
    fn from(e: T) -> Self {
        Error(e.to_string())
    }
}

fn error<T>(m: &str) -> Result<T, Error> {
    Err(Error(m.to_string()))
}

// ── rclone ───────────────────────────────────────────────────────────────────
struct Salida {
    ok: bool,
    stdout: String,
    stderr: String,
}

/// Corre rclone con `args` (nunca un secreto), `entrada` por stdin y `env` (donde sí van el estado y
/// el código del 2FA: /proc/<pid>/environ solo lo lee el mismo usuario).
fn rclone(e: &Entorno, args: &[&str], entrada: Option<&str>, env: &[(&str, &str)]) -> Result<Salida, Error> {
    let mut c = Command::new(&e.rclone);
    c.args(args).envs(env.iter().copied()).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut h = c.spawn().map_err(|x| Error(format!("rclone did not start: {x}")))?;
    let mut stdin = h.stdin.take().expect("stdin");
    if let Some(t) = entrada {
        stdin.write_all(t.as_bytes())?;
    }
    drop(stdin);
    let o = h.wait_with_output()?;
    Ok(Salida { ok: o.status.success(), stdout: String::from_utf8_lossy(&o.stdout).into(), stderr: String::from_utf8_lossy(&o.stderr).into() })
}

fn archivo_rclone(e: &Entorno) -> Result<PathBuf, Error> {
    let s = rclone(e, &["config", "file"], None, &[])?;
    match s.stdout.lines().map(str::trim).filter(|l| !l.is_empty()).last() {
        Some(l) if s.ok && l.starts_with('/') => Ok(PathBuf::from(l)),
        _ => error("rclone did not say where its configuration is."),
    }
}

/// Las secciones de rclone.conf: [nombre] → clave → valor.
fn secciones(texto: &str) -> HashMap<String, HashMap<String, String>> {
    let mut r: HashMap<String, HashMap<String, String>> = HashMap::new();
    let mut actual = None;
    for l in texto.lines().map(str::trim) {
        if let Some(n) = l.strip_prefix('[').and_then(|x| x.strip_suffix(']')) {
            actual = Some(n.to_string());
            r.entry(n.to_string()).or_default();
        } else if let (Some(n), Some((k, v))) = (&actual, l.split_once('=')) {
            r.get_mut(n).unwrap().insert(k.trim().into(), v.trim().into());
        }
    }
    r
}

/// El texto sin la sección `[remoto]`.
fn sin_seccion(texto: &str, remoto: &str) -> String {
    let cabecera = format!("[{remoto}]");
    let mut dentro = false;
    let mut r = String::new();
    for l in texto.lines() {
        let t = l.trim();
        if t.starts_with('[') {
            dentro = t == cabecera;
        }
        if !dentro {
            r.push_str(l);
            r.push('\n');
        }
    }
    r
}

/// Escribe con 0600 desde el primer byte y cambia de un golpe (rename).
fn escribir_privado(ruta: &Path, texto: &str) -> Result<(), Error> {
    if let Some(d) = ruta.parent() {
        fs::create_dir_all(d)?;
    }
    let tmp = ruta.with_extension("mint-macos-tmp");
    let mut f = fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&tmp)?;
    f.write_all(texto.as_bytes())?;
    f.sync_all()?;
    fs::rename(&tmp, ruta)?;
    Ok(())
}

/// La salida completa de rclone para diagnosticar un Sign In que falla: stdout y stderr, nunca los
/// argumentos ni el entorno (ahí van el estado y el código).
fn guardar_log(e: &Entorno, s: &Salida) {
    let _ = fs::create_dir_all(e.log.parent().unwrap_or(Path::new(".")));
    if let Ok(mut f) = fs::OpenOptions::new().append(true).create(true).mode(0o600).open(&e.log) {
        let cola = |t: &str| t.chars().rev().take(6000).collect::<Vec<_>>().into_iter().rev().collect::<String>();
        let _ = write!(f, "--- {} ok={}\n[stderr]\n{}\n[stdout]\n{}\n", segundos(), s.ok, cola(&s.stderr), cola(&s.stdout));
    }
}

fn segundos() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// Lo que se le enseña al usuario cuando rclone falla (la misma regla de apple_id.py): el Error de
/// un JSON; si no, la última línea que hable de un error, sin la fecha ni el nivel; si no, un fijo.
fn mensaje_de_error(s: &Salida) -> String {
    for t in [s.stdout.trim(), s.stderr.trim()] {
        if let (Some(i), Some(f)) = (t.find('{'), t.rfind('}')) {
            if let Ok(serde_json::Value::Object(d)) = serde_json::from_str::<serde_json::Value>(&t[i..=f]) {
                if let Some(m) = d.get("Error").or_else(|| d.get("error")).and_then(|v| v.as_str()) {
                    if let Some(l) = m.trim().lines().next() {
                        return l.to_string();
                    }
                }
            }
        }
    }
    for t in [s.stderr.trim(), s.stdout.trim()] {
        for l in t.lines().map(str::trim).rev() {
            let b = l.to_lowercase();
            if l != "{" && l != "}" && ["error", "failed", "incorrect", "invalid"].iter().any(|p| b.contains(p)) {
                return limpiar_linea(l);
            }
        }
    }
    "Apple did not accept the account.".into()
}

fn limpiar_linea(l: &str) -> String {
    let mut t = l;
    // «2026/10/18 22:18:42 » delante.
    if t.len() > 20 && t.as_bytes()[4] == b'/' && t.as_bytes()[19] == b' ' {
        t = &t[20..];
    }
    for n in ["NOTICE:", "ERROR :", "ERROR:", "CRITICAL:", "WARNING:"] {
        if let Some(r) = t.trim_start().strip_prefix(n) {
            t = r;
        }
    }
    let t = t.trim();
    t.strip_prefix("Fatal error:").unwrap_or(t).trim().to_string()
}

/// Lo que rclone contesta a un paso del alta: None si terminó, o (estado, pregunta) si quiere el código.
fn leer_paso(e: &Entorno, s: Salida) -> Result<Option<(String, String)>, Error> {
    if !s.ok {
        guardar_log(e, &s);
        return Err(Error(mensaje_de_error(&s)));
    }
    let d: serde_json::Value = serde_json::from_str(s.stdout.trim()).unwrap_or(serde_json::Value::Null);
    match d.get("State").and_then(|v| v.as_str()).filter(|v| !v.is_empty()) {
        Some(st) => {
            let p = d.pointer("/Option/Help").and_then(|v| v.as_str()).unwrap_or("Verification code");
            Ok(Some((st.to_string(), p.to_string())))
        }
        None => Ok(None),
    }
}

/// Primer paso: la sección del remoto (con la contraseña ofuscada, como la guarda rclone) y el alta.
fn iniciar(e: &Entorno, apple_id: &str, clave: &str) -> Result<Option<(String, String)>, Error> {
    if apple_id.trim().is_empty() || clave.is_empty() {
        return error("Enter your Apple ID and password.");
    }
    if apple_id.contains(['\n', '\r', '[', ']']) {
        return error("That is not an Apple ID.");
    }
    let o = rclone(e, &["obscure", "-"], Some(clave), &[])?;
    let ofus = o.stdout.trim();
    if !o.ok || ofus.is_empty() {
        return error("rclone could not prepare the password.");
    }
    let ruta = archivo_rclone(e)?;
    let previo = fs::read_to_string(&ruta).unwrap_or_default();
    let mut nuevo = sin_seccion(&previo, &e.remoto);
    if !nuevo.is_empty() && !nuevo.ends_with("\n\n") {
        nuevo.push('\n');
    }
    nuevo.push_str(&format!("[{}]\ntype = iclouddrive\napple_id = {}\npassword = {}\n", e.remoto, apple_id.trim(), ofus));
    escribir_privado(&ruta, &nuevo)?;
    // Sin parámetros, «config update» corre el alta del backend con lo que ya está en la sección.
    let s = rclone(e, &["config", "update", &e.remoto], None, &[("RCLONE_NON_INTERACTIVE", "true")])?;
    let r = leer_paso(e, s);
    if r.is_err() {
        // Una contraseña que Apple no aceptó no se queda en rclone.conf.
        let _ = escribir_privado(&ruta, &sin_seccion(&fs::read_to_string(&ruta).unwrap_or_default(), &e.remoto));
    }
    r
}

fn seguir(e: &Entorno, estado: &str, codigo: &str) -> Result<Option<(String, String)>, Error> {
    let s = rclone(e, &["config", "update", &e.remoto], None, &[
        ("RCLONE_NON_INTERACTIVE", "true"),
        ("RCLONE_CONTINUE", "true"),
        ("RCLONE_STATE", estado),
        ("RCLONE_RESULT", codigo),
    ])?;
    leer_paso(e, s)
}

fn sesion_icloud(e: &Entorno) -> Option<String> {
    let ruta = archivo_rclone(e).ok()?;
    let s = secciones(&fs::read_to_string(ruta).ok()?);
    let d = s.get(&e.remoto)?;
    let tiene = |k: &str| d.get(k).is_some_and(|v| !v.is_empty());
    (d.get("type").map(String::as_str) == Some("iclouddrive") && tiene("apple_id") && (tiene("trust_token") || tiene("cookies")))
        .then(|| d["apple_id"].clone())
}

fn montado(e: &Entorno) -> bool {
    // En mountinfo los espacios van como \040.
    let buscado = e.carpeta.to_string_lossy().replace(' ', "\\040");
    fs::read_to_string("/proc/self/mountinfo").unwrap_or_default().lines().any(|l| l.split(' ').nth(4) == Some(buscado.as_str()))
}

fn systemctl(e: &Entorno, accion: &str) -> bool {
    Command::new(&e.systemctl).args(["--user", accion, &e.servicio]).stdout(Stdio::null()).stderr(Stdio::null())
        .status().is_ok_and(|s| s.success())
}

/// Levanta el servicio que monta ~/iCloud Drive (lo instala icloud.sh montar). El mensaje lo dice
/// si no está instalado.
fn montar(e: &Entorno) -> String {
    if !e.unidades.join(format!("{}.service", e.servicio)).exists() {
        return "iCloud Drive is signed in. To see it in Fynder, install the mount: icloud.sh montar.".into();
    }
    if systemctl(e, "restart") {
        "iCloud Drive is connected.".into()
    } else {
        "iCloud Drive is signed in, but the mount did not start.".into()
    }
}

// ── El llavero ───────────────────────────────────────────────────────────────
fn atributos(apple_id: Option<&str>) -> HashMap<&str, &str> {
    let mut a = HashMap::from([("xdg:schema", ESQUEMA), ("servicio", "mail")]);
    if let Some(i) = apple_id {
        a.insert("apple_id", i);
    }
    a
}

mod secret {
    //! Lo justo del Secret Service (org.freedesktop.Secret) para guardar, buscar y borrar la
    //! contraseña de app, como hace libsecret, sin depender de ella.
    use super::*;
    use zbus::blocking::{Connection, Proxy};
    use zbus::zvariant::{ObjectPath, OwnedObjectPath};

    const DESTINO: &str = "org.freedesktop.secrets";

    /// Con tope: si el llavero no contesta (o tarda en arrancar), Estado no se queda colgado.
    fn conectar() -> zbus::Result<Connection> {
        zbus::blocking::connection::Builder::session()?.method_timeout(Duration::from_secs(5)).build()
    }

    fn proxy<'a>(c: &Connection, ruta: &'a str, interfaz: &'a str) -> zbus::Result<Proxy<'a>> {
        Proxy::new(c, DESTINO, ruta, interfaz)
    }

    fn buscar(c: &Connection, attrs: &HashMap<&str, &str>) -> zbus::Result<(Vec<OwnedObjectPath>, Vec<OwnedObjectPath>)> {
        proxy(c, "/org/freedesktop/secrets", "org.freedesktop.Secret.Service")?.call("SearchItems", &(attrs,))
    }

    pub fn hay(attrs: &HashMap<&str, &str>) -> bool {
        conectar().and_then(|c| buscar(&c, attrs)).is_ok_and(|(a, b)| !a.is_empty() || !b.is_empty())
    }

    pub fn guardar(etiqueta: &str, attrs: &HashMap<&str, &str>, clave: &str) -> Result<(), Error> {
        let c = conectar()?;
        let serv = proxy(&c, "/org/freedesktop/secrets", "org.freedesktop.Secret.Service")?;
        // «plain»: la clave viaja por el bus de la sesión, que solo es del usuario (lo mismo que
        // libsecret cuando no negocia).
        let (_, sesion): (OwnedValue, OwnedObjectPath) = serv.call("OpenSession", &("plain", Value::from("")))?;
        let col = "/org/freedesktop/secrets/aliases/default";
        let (_, prompt): (Vec<OwnedObjectPath>, OwnedObjectPath) = serv.call("Unlock", &(vec![ObjectPath::try_from(col)?],))?;
        if prompt.as_str() != "/" {
            return error("The keyring is locked: unlock it and try again.");
        }
        let a: HashMap<String, String> = attrs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
        let props: HashMap<&str, Value> = HashMap::from([
            ("org.freedesktop.Secret.Item.Label", Value::from(etiqueta)),
            ("org.freedesktop.Secret.Item.Attributes", Value::from(a)),
        ]);
        let secreto = (sesion.as_ref(), Vec::<u8>::new(), clave.as_bytes().to_vec(), "text/plain");
        let (_, prompt): (OwnedObjectPath, OwnedObjectPath) =
            proxy(&c, col, "org.freedesktop.Secret.Collection")?.call("CreateItem", &(props, secreto, true))?;
        if prompt.as_str() != "/" {
            return error("The keyring asked for confirmation: try again.");
        }
        Ok(())
    }

    pub fn borrar(attrs: &HashMap<&str, &str>) {
        let Ok(c) = conectar() else { return };
        let Ok((a, b)) = buscar(&c, attrs) else { return };
        for i in a.iter().chain(b.iter()) {
            if let Ok(p) = proxy(&c, i.as_str(), "org.freedesktop.Secret.Item") {
                let _: zbus::Result<OwnedObjectPath> = p.call("Delete", &());
            }
        }
    }
}

fn llavero_hay(e: &Entorno) -> bool {
    match &e.llavero {
        Llavero::Sistema => secret::hay(&atributos(None)),
        Llavero::Archivo(p) => fs::read_to_string(p).is_ok_and(|t| !t.trim().is_empty()),
    }
}

fn llavero_guardar(e: &Entorno, apple_id: &str, clave: &str) -> Result<(), Error> {
    match &e.llavero {
        Llavero::Sistema => secret::guardar(&format!("Apple ID (app) {apple_id}"), &atributos(Some(apple_id)), clave),
        Llavero::Archivo(p) => escribir_privado(p, &format!("{apple_id}\t{clave}\n")),
    }
}

fn llavero_borrar(e: &Entorno) {
    match &e.llavero {
        Llavero::Sistema => secret::borrar(&atributos(None)),
        Llavero::Archivo(p) => {
            let _ = fs::remove_file(p);
        }
    }
}

// ── Mail y Calendar (Thunderbird) ────────────────────────────────────────────
fn thunderbird_abierto(e: &Entorno) -> bool {
    e.mirar_procesos
        && fs::read_dir("/proc").into_iter().flatten().flatten().any(|d| {
            fs::read_to_string(d.path().join("comm")).is_ok_and(|c| matches!(c.trim(), "thunderbird" | "thunderbird-bin"))
        })
}

/// [sección] → clave → valor de un .ini de Thunderbird, en orden.
fn ini(texto: &str) -> Vec<(String, HashMap<String, String>)> {
    let mut r: Vec<(String, HashMap<String, String>)> = Vec::new();
    for l in texto.lines().map(str::trim) {
        if let Some(n) = l.strip_prefix('[').and_then(|x| x.strip_suffix(']')) {
            r.push((n.to_string(), HashMap::new()));
        } else if let (Some(u), Some((k, v))) = (r.last_mut(), l.split_once('=')) {
            u.1.insert(k.trim().into(), v.trim().into());
        }
    }
    r
}

/// El perfil que Thunderbird usa de verdad: el de installs.ini manda sobre el Default=1 de profiles.ini.
fn perfil_thunderbird(e: &Entorno) -> Result<PathBuf, Error> {
    let tb = &e.thunderbird;
    let perfiles = fs::read_to_string(tb.join("profiles.ini")).map_err(|_| Error("Thunderbird has no profile: open it once and quit.".into()))?;
    for (_, s) in ini(&fs::read_to_string(tb.join("installs.ini")).unwrap_or_default()) {
        if let Some(d) = s.get("Default").filter(|d| !d.is_empty()) {
            return Ok(tb.join(d));
        }
    }
    for (n, s) in ini(&perfiles) {
        if n.starts_with("Profile") && s.get("Default").map(String::as_str) == Some("1") {
            if let Some(p) = s.get("Path") {
                return Ok(if s.get("IsRelative").map(String::as_str) == Some("0") { PathBuf::from(p) } else { tb.join(p) });
            }
        }
    }
    error("Could not find Thunderbird's default profile.")
}

fn pref_actual(prefs: &str, nombre: &str) -> String {
    let buscado = format!("user_pref(\"{nombre}\",");
    prefs.lines().map(str::trim).find_map(|l| {
        let r = l.strip_prefix(&buscado)?.trim().strip_suffix(");")?.trim();
        serde_json::from_str::<String>(r).ok()
    }).unwrap_or_default()
}

fn lista_con(actual: &str, nuevo: &str) -> String {
    let mut p: Vec<&str> = actual.split(',').filter(|x| !x.is_empty()).collect();
    if !p.contains(&nuevo) {
        p.push(nuevo);
    }
    p.join(",")
}

/// El bloque de user.js con la cuenta de iCloud (IMAP/SMTP) y sus calendarios. Mezcla las listas
/// que Thunderbird ya tiene en prefs.js, porque user.js las pisa enteras.
fn bloque_userjs(perfil: &Path, apple_id: &str, nombre: &str, calendarios: &[(String, String)]) -> String {
    let prefs = fs::read_to_string(perfil.join("prefs.js")).unwrap_or_default();
    let mut l = vec![MARCA_INI.to_string()];
    let mut p = |k: String, v: serde_json::Value| l.push(format!("user_pref(\"{k}\", {v});"));
    let s = |t: &str| serde_json::Value::from(t);
    p("mail.accountmanager.accounts".into(), s(&lista_con(&pref_actual(&prefs, "mail.accountmanager.accounts"), &format!("{ID_TB}_acc"))));
    p(format!("mail.account.{ID_TB}_acc.server"), s(&format!("{ID_TB}_srv")));
    p(format!("mail.account.{ID_TB}_acc.identities"), s(&format!("{ID_TB}_id")));
    p(format!("mail.server.{ID_TB}_srv.type"), s("imap"));
    p(format!("mail.server.{ID_TB}_srv.hostname"), s("imap.mail.me.com"));
    p(format!("mail.server.{ID_TB}_srv.port"), 993.into());
    p(format!("mail.server.{ID_TB}_srv.socketType"), 3.into()); // SSL/TLS
    p(format!("mail.server.{ID_TB}_srv.userName"), s(apple_id));
    p(format!("mail.server.{ID_TB}_srv.name"), s("iCloud"));
    p(format!("mail.server.{ID_TB}_srv.authMethod"), 3.into()); // contraseña normal
    p(format!("mail.identity.{ID_TB}_id.useremail"), s(apple_id));
    p(format!("mail.identity.{ID_TB}_id.fullName"), s(nombre));
    p(format!("mail.identity.{ID_TB}_id.smtpServer"), s(&format!("{ID_TB}_smtp")));
    p("mail.smtpservers".into(), s(&lista_con(&pref_actual(&prefs, "mail.smtpservers"), &format!("{ID_TB}_smtp"))));
    p(format!("mail.smtpserver.{ID_TB}_smtp.hostname"), s("smtp.mail.me.com"));
    p(format!("mail.smtpserver.{ID_TB}_smtp.port"), 587.into());
    p(format!("mail.smtpserver.{ID_TB}_smtp.try_ssl"), 2.into()); // STARTTLS
    p(format!("mail.smtpserver.{ID_TB}_smtp.username"), s(apple_id));
    p(format!("mail.smtpserver.{ID_TB}_smtp.authMethod"), 3.into());
    p(format!("mail.smtpserver.{ID_TB}_smtp.description"), s("iCloud"));
    for (i, (url, nom)) in calendarios.iter().enumerate() {
        let c = format!("calendar.registry.{ID_TB}_cal{i}");
        p(format!("{c}.type"), s("caldav"));
        p(format!("{c}.uri"), s(url));
        p(format!("{c}.name"), s(nom));
        p(format!("{c}.username"), s(apple_id));
        p(format!("{c}.cache.enabled"), true.into());
    }
    l.push(MARCA_FIN.into());
    l.join("\n") + "\n"
}

/// user.js sin el bloque anterior y con `bloque` al final (vacío: solo lo quita).
fn escribir_userjs(perfil: &Path, bloque: &str) -> Result<(), Error> {
    let ruta = perfil.join("user.js");
    let mut previo = fs::read_to_string(&ruta).unwrap_or_default();
    while let (Some(i), Some(f)) = (previo.find(MARCA_INI), previo.find(MARCA_FIN)) {
        if f < i {
            break;
        }
        let mut fin = f + MARCA_FIN.len();
        if previo[fin..].starts_with('\n') {
            fin += 1;
        }
        previo.replace_range(i..fin, "");
    }
    if !previo.is_empty() && !previo.ends_with('\n') && !bloque.is_empty() {
        previo.push('\n');
    }
    fs::write(&ruta, previo + bloque)?;
    Ok(())
}

// ── CalDAV de iCloud ─────────────────────────────────────────────────────────
/// Un nodo de XML por su nombre local (sin espacio de nombres: en estas respuestas no se pisan).
#[derive(Default)]
struct Nodo {
    nombre: String,
    texto: String,
    hijos: Vec<Nodo>,
}

impl Nodo {
    fn todos<'a>(&'a self, n: &str, r: &mut Vec<&'a Nodo>) {
        for h in &self.hijos {
            if h.nombre == n {
                r.push(h);
            }
            h.todos(n, r);
        }
    }
    fn uno(&self, n: &str) -> Option<&Nodo> {
        let mut r = Vec::new();
        self.todos(n, &mut r);
        r.into_iter().next()
    }
}

fn arbol(xml: &str) -> Result<Nodo, Error> {
    use quick_xml::events::Event;
    let mut lector = quick_xml::Reader::from_str(xml);
    let mut pila = vec![Nodo::default()];
    loop {
        match lector.read_event().map_err(|e| Error(format!("iCloud answered with broken XML: {e}")))? {
            Event::Start(t) => pila.push(Nodo { nombre: t.local_name().as_ref().to_string(), ..Default::default() }),
            Event::Empty(t) => {
                let n = Nodo { nombre: t.local_name().as_ref().to_string(), ..Default::default() };
                pila.last_mut().unwrap().hijos.push(n);
            }
            Event::Text(t) => pila.last_mut().unwrap().texto.push_str(t.as_ref()),
            Event::CData(t) => pila.last_mut().unwrap().texto.push_str(t.as_ref()),
            // quick-xml entrega «&amp;» y compañía aparte del texto.
            Event::GeneralRef(g) => {
                let n = g.as_ref().to_string();
                let c = match n.as_str() {
                    "amp" => Some('&'),
                    "lt" => Some('<'),
                    "gt" => Some('>'),
                    "quot" => Some('"'),
                    "apos" => Some('\''),
                    _ => n.strip_prefix("#x").map(|h| u32::from_str_radix(h, 16).ok()).unwrap_or_else(|| n.strip_prefix('#').and_then(|d| d.parse().ok()))
                        .and_then(char::from_u32),
                };
                if let Some(c) = c {
                    pila.last_mut().unwrap().texto.push(c);
                }
            }
            Event::End(_) if pila.len() > 1 => {
                let n = pila.pop().unwrap();
                pila.last_mut().unwrap().hijos.push(n);
            }
            Event::Eof => break,
            _ => {}
        }
    }
    Ok(pila.swap_remove(0))
}

fn origen(url: &str) -> &str {
    let desde = url.find("://").map(|i| i + 3).unwrap_or(0);
    url[desde..].find('/').map(|i| &url[..desde + i]).unwrap_or(url)
}

fn absoluta(base: &str, href: &str) -> String {
    if href.starts_with("http") { href.to_string() } else { format!("{}{}", origen(base), href) }
}

fn base64(b: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut r = String::new();
    for c in b.chunks(3) {
        let n = (c[0] as u32) << 16 | (*c.get(1).unwrap_or(&0) as u32) << 8 | *c.get(2).unwrap_or(&0) as u32;
        for i in 0..4 {
            r.push(if i <= c.len() { T[(n >> (18 - 6 * i) & 63) as usize] as char } else { '=' });
        }
    }
    r
}

fn propfind(url: &str, apple_id: &str, clave: &str, prop: &str, profundidad: &str) -> Result<Nodo, Error> {
    let agente: ureq::Agent = ureq::Agent::config_builder()
        .http_status_as_error(false)
        .allow_non_standard_methods(true)
        .timeout_global(Some(Duration::from_secs(30)))
        .build()
        .into();
    let cuerpo = format!("<d:propfind xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\"><d:prop>{prop}</d:prop></d:propfind>");
    // Basic desde el primer envío: iCloud a veces contesta 401 sin ofrecer el reto.
    let req = ureq::http::Request::builder()
        .method(ureq::http::Method::from_bytes(b"PROPFIND").unwrap())
        .uri(url)
        .header("Depth", profundidad)
        .header("Content-Type", "application/xml; charset=utf-8")
        .header("Authorization", format!("Basic {}", base64(format!("{apple_id}:{clave}").as_bytes())))
        .body(cuerpo)?;
    let mut r = agente.run(req).map_err(|e| Error(format!("Cannot reach iCloud: {e}")))?;
    match r.status().as_u16() {
        200..=299 => arbol(&r.body_mut().read_to_string().map_err(|e| Error(format!("Cannot reach iCloud: {e}")))?),
        401 | 403 => error("Apple did not accept the app-specific password."),
        c => Err(Error(format!("CalDAV answered {c}."))),
    }
}

/// Usuario → principal → calendar-home → los calendarios, como [(url, nombre)].
fn descubrir_calendarios(base: &str, apple_id: &str, clave: &str) -> Result<Vec<(String, String)>, Error> {
    let raiz = format!("{}/", base.trim_end_matches('/'));
    let x = propfind(&raiz, apple_id, clave, "<d:current-user-principal/>", "0")?;
    let Some(principal) = x.uno("current-user-principal").and_then(|n| n.uno("href")) else {
        return error("iCloud did not return the calendar principal.");
    };
    let principal = absoluta(&raiz, principal.texto.trim());
    let x = propfind(&principal, apple_id, clave, "<c:calendar-home-set/>", "0")?;
    let Some(casa) = x.uno("calendar-home-set").and_then(|n| n.uno("href")) else {
        return error("iCloud did not return the calendar home.");
    };
    let casa = absoluta(&principal, casa.texto.trim());
    let x = propfind(&casa, apple_id, clave, "<d:displayname/><d:resourcetype/>", "1")?;
    let mut respuestas = Vec::new();
    x.todos("response", &mut respuestas);
    Ok(respuestas.into_iter().filter(|r| r.uno("resourcetype").and_then(|t| t.uno("calendar")).is_some()).filter_map(|r| {
        let href = r.hijos.iter().find(|h| h.nombre == "href")?.texto.trim().to_string();
        let nom = r.uno("displayname").map(|n| n.texto.trim()).filter(|n| !n.is_empty()).unwrap_or("iCloud");
        Some((absoluta(&casa, &href), nom.to_string()))
    }).collect())
}

/// Guarda la contraseña de app en el llavero y deja Mail y Calendar en Thunderbird. Devuelve
/// cuántos calendarios quedaron.
fn configurar_mail(e: &Entorno, apple_id: &str, nombre: &str, clave_app: &str) -> Result<usize, Error> {
    if apple_id.trim().is_empty() || clave_app.trim().is_empty() {
        return error("Paste the app-specific password.");
    }
    if thunderbird_abierto(e) {
        return error("Quit Thunderbird and try again (it reads its settings when it opens).");
    }
    let perfil = perfil_thunderbird(e)?;
    // También comprueba la contraseña: con una mala, nada se guarda.
    let cals = descubrir_calendarios(&e.caldav, apple_id.trim(), clave_app.trim())?;
    llavero_guardar(e, apple_id.trim(), clave_app.trim())?;
    let nombre = if nombre.trim().is_empty() { apple_id.trim() } else { nombre.trim() };
    escribir_userjs(&perfil, &bloque_userjs(&perfil, apple_id.trim(), nombre, &cals))?;
    Ok(cals.len())
}

/// Sign Out: el montaje, el remoto de rclone, el llavero y el bloque de Thunderbird.
fn cerrar_sesion(e: &Entorno) {
    if e.unidades.join(format!("{}.service", e.servicio)).exists() {
        systemctl(e, "stop");
    }
    let _ = rclone(e, &["config", "delete", &e.remoto], None, &[]);
    llavero_borrar(e);
    if let Ok(p) = perfil_thunderbird(e) {
        if p.join("user.js").exists() {
            let _ = escribir_userjs(&p, "");
        }
    }
}

fn estado(e: &Entorno) -> Dict {
    let id = sesion_icloud(e);
    let mut d = Dict::new();
    d.insert("apple_id".into(), Value::from(id.clone().unwrap_or_default()).try_to_owned().unwrap());
    d.insert("icloud_con_sesion".into(), Value::from(id.is_some()).try_to_owned().unwrap());
    d.insert("icloud_montado".into(), Value::from(montado(e)).try_to_owned().unwrap());
    d.insert("mail_configurado".into(), Value::from(llavero_hay(e)).try_to_owned().unwrap());
    d
}

// ── El servicio ──────────────────────────────────────────────────────────────
/// Lo que vive entre llamadas: el estado del 2FA que rclone dejó pendiente (nunca el código).
#[derive(Default)]
struct Pendiente {
    estado: Option<String>,
}

struct Servicio {
    e: Entorno,
    pendiente: Arc<Mutex<Pendiente>>,
    ultima: Arc<Mutex<Instant>>,
}

fn respuesta(resultado: &str, mensaje: &str) -> Dict {
    let mut d = Dict::new();
    d.insert("resultado".into(), Value::from(resultado).try_to_owned().unwrap());
    d.insert("mensaje".into(), Value::from(mensaje).try_to_owned().unwrap());
    d
}

/// Un paso del alta (clave o código) → la respuesta del contrato.
fn paso(e: &Entorno, p: &Mutex<Pendiente>, r: Result<Option<(String, String)>, Error>) -> (Dict, bool) {
    match r {
        Err(Error(m)) => (respuesta("error", &m), false),
        Ok(Some((st, pregunta))) => {
            p.lock().unwrap().estado = Some(st);
            (respuesta("necesita_codigo", &pregunta), false)
        }
        Ok(None) => {
            p.lock().unwrap().estado = None;
            (respuesta("ok", &montar(e)), true)
        }
    }
}

impl Servicio {
    fn tocar(&self) {
        *self.ultima.lock().unwrap() = Instant::now();
    }
}

#[interface(name = "org.mintmacos.AppleID1")]
impl Servicio {
    /// apple_id (s, "" sin sesión), icloud_con_sesion, icloud_montado y mail_configurado (b).
    async fn estado(&self) -> Dict {
        self.tocar();
        let e = self.e.clone();
        blocking::unblock(move || estado(&e)).await
    }

    /// Primer paso de iCloud Drive → {resultado: ok | necesita_codigo | error, mensaje}.
    async fn iniciar_sesion(&self, apple_id: String, clave: String, #[zbus(signal_emitter)] emisor: SignalEmitter<'_>) -> Dict {
        self.tocar();
        let (e, p) = (self.e.clone(), self.pendiente.clone());
        let (d, cambio) = blocking::unblock(move || {
            p.lock().unwrap().estado = None;
            let r = iniciar(&e, &apple_id, &clave);
            paso(&e, &p, r)
        }).await;
        self.tocar();
        if cambio {
            let _ = Self::cambio(&emisor).await;
        }
        d
    }

    /// El código de 2FA → lo mismo que IniciarSesion (otra vez necesita_codigo si Apple pide otro).
    async fn enviar_codigo(&self, codigo: String, #[zbus(signal_emitter)] emisor: SignalEmitter<'_>) -> Dict {
        self.tocar();
        let (e, p) = (self.e.clone(), self.pendiente.clone());
        let (d, cambio) = blocking::unblock(move || {
            let Some(st) = p.lock().unwrap().estado.clone() else {
                return (respuesta("error", "Start again with your Apple ID and password."), false);
            };
            let codigo: String = codigo.chars().filter(|c| !c.is_whitespace()).collect();
            if codigo.is_empty() {
                return (respuesta("error", "Enter the verification code."), false);
            }
            let r = seguir(&e, &st, &codigo);
            paso(&e, &p, r)
        }).await;
        self.tocar();
        if cambio {
            let _ = Self::cambio(&emisor).await;
        }
        d
    }

    /// Mail y Calendar en Thunderbird → {resultado: ok | error, cuantos_calendarios (i), mensaje}.
    async fn configurar_mail(&self, apple_id: String, nombre: String, clave_app: String,
                             #[zbus(signal_emitter)] emisor: SignalEmitter<'_>) -> Dict {
        self.tocar();
        let e = self.e.clone();
        let r = blocking::unblock(move || configurar_mail(&e, &apple_id, &nombre, &clave_app)).await;
        self.tocar();
        let (mut d, n) = match r {
            Ok(n) => (respuesta("ok", "Open Thunderbird and, if it asks, choose the saved password."), n as i32),
            Err(Error(m)) => (respuesta("error", &m), 0),
        };
        d.insert("cuantos_calendarios".into(), Value::from(n).try_to_owned().unwrap());
        if d["resultado"] == Value::from("ok").try_to_owned().unwrap() {
            let _ = Self::cambio(&emisor).await;
        }
        d
    }

    /// Sign Out: quita el montaje, la sesión de rclone, la contraseña de app y la cuenta de Thunderbird.
    async fn cerrar_sesion(&self, #[zbus(signal_emitter)] emisor: SignalEmitter<'_>) {
        self.tocar();
        let (e, p) = (self.e.clone(), self.pendiente.clone());
        blocking::unblock(move || {
            p.lock().unwrap().estado = None;
            cerrar_sesion(&e)
        }).await;
        let _ = Self::cambio(&emisor).await;
    }

    /// Algo cambió: la ventana vuelve a pedir Estado.
    #[zbus(signal)]
    async fn cambio(emisor: &SignalEmitter<'_>) -> zbus::Result<()>;
}

fn main() {
    let ultima = Arc::new(Mutex::new(Instant::now()));
    let pendiente: Arc<Mutex<Pendiente>> = Default::default();
    let s = Servicio { e: Entorno::real(), pendiente: pendiente.clone(), ultima: ultima.clone() };
    let c = zbus::blocking::connection::Builder::session()
        .and_then(|b| b.name(NOMBRE))
        .and_then(|b| b.serve_at(RUTA, s))
        .and_then(|b| b.build());
    let _c = match c {
        Ok(c) => c,
        Err(e) => {
            eprintln!("mint-macos-appleid: {e}");
            std::process::exit(1);
        }
    };
    loop {
        std::thread::sleep(Duration::from_secs(10));
        // Con un código de 2FA por llegar se espera más: el estado de rclone vive solo aquí.
        let tope = if pendiente.lock().unwrap().estado.is_some() { CON_CODIGO_PENDIENTE } else { SIN_LLAMADAS };
        if ultima.lock().unwrap().elapsed() > tope {
            break;
        }
    }
}

#[cfg(test)]
mod pruebas;
