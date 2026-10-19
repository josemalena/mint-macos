//! org.mintmacos.AppleID1: el Apple ID de System Preferences, sin ventana. Una sola cuenta para
//! iCloud Drive (rclone, con la contraseña del Apple ID y el código de 2FA) y para Mail y Calendar
//! en Thunderbird (con una contraseña de app). Sale de settings/apple_id.py; la hoja de Sign In la
//! pone Dev-Dock en Vala. Contrato y «qué se guarda y dónde»: DBUS.md.
//!
//! La contraseña y el código nunca van a la línea de comando (se ve en /proc/<pid>/cmdline) ni al
//! registro: van a la API de rclone (rcd en un socket Unix propio). rclone.conf va entero cifrado y
//! su clave vive en el llavero; este mismo binario se la da a rclone (`--clave-config`).
use std::collections::HashMap;
use std::fs;
use std::io::Write as _;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
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
    /// Lo que rclone corre para pedir la clave de rclone.conf (RCLONE_PASSWORD_COMMAND).
    ayudante: String,
    mirar_procesos: bool,
    log: PathBuf,
}

#[derive(Clone)]
enum Llavero {
    /// El llavero de la sesión (Secret Service por D-Bus).
    Sistema,
    /// Solo en pruebas: una carpeta con un archivo por servicio («apple_id\tclave»).
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
            // Este mismo binario: `mint-macos-appleid --clave-config`.
            ayudante: format!("{} --clave-config", std::env::current_exe().unwrap_or_else(|_| hogar.join(".local/lib/mint-macos/mint-macos-appleid")).display()),
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

/// El entorno de cada rclone: la clave de rclone.conf la da el ayudante (nunca un tty).
fn entorno_rclone(e: &Entorno) -> [(&'static str, &str); 2] {
    [("RCLONE_PASSWORD_COMMAND", e.ayudante.as_str()), ("RCLONE_ASK_PASSWORD", "false")]
}

/// Corre rclone con `args` (nunca un secreto) y `entrada` por stdin.
fn rclone(e: &Entorno, args: &[&str], entrada: Option<&str>) -> Result<Salida, Error> {
    let mut c = Command::new(&e.rclone);
    c.args(args).envs(entorno_rclone(e)).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped());
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
    let s = rclone(e, &["config", "file"], None)?;
    match s.stdout.lines().map(str::trim).filter(|l| !l.is_empty()).last() {
        Some(l) if s.ok && l.starts_with('/') => Ok(PathBuf::from(l)),
        _ => error("rclone did not say where its configuration is."),
    }
}

fn cifrada(ruta: &Path) -> bool {
    fs::read_to_string(ruta).is_ok_and(|t| t.lines().take(5).any(|l| l.starts_with("RCLONE_ENCRYPT_V0:")))
}

/// Todos los remotos, con sus valores (descifrados si hace falta): `rclone config dump`.
fn volcado(e: &Entorno) -> Result<serde_json::Map<String, serde_json::Value>, Error> {
    let s = rclone(e, &["config", "dump"], None)?;
    if !s.ok {
        return Err(Error(mensaje_de_error(&s)));
    }
    match serde_json::from_str(s.stdout.trim()) {
        Ok(serde_json::Value::Object(m)) => Ok(m),
        _ => error("rclone did not return its configuration."),
    }
}

/// rclone.conf entero cifrado con el cifrado de rclone, y su clave (al azar) en el llavero (José,
/// 18-10-2026). Si ya lo está, no se toca. Comprueba que después se lean los mismos remotos.
fn asegurar_cifrado(e: &Entorno) -> Result<(), Error> {
    let ruta = archivo_rclone(e)?;
    if cifrada(&ruta) {
        return Ok(());
    }
    let antes = if ruta.exists() { volcado(e)? } else { Default::default() };
    crear_clave_config(e)?;
    let s = rclone(e, &["config", "encryption", "set"], None)?;
    if !s.ok || !cifrada(&ruta) {
        guardar_log(e, &s);
        return error("Could not encrypt rclone's configuration.");
    }
    if volcado(e)? != antes {
        return error("rclone's configuration changed while encrypting it: check rclone.conf.");
    }
    Ok(())
}

/// La salida completa de rclone para diagnosticar un Sign In que falla: stdout y stderr, nunca los
/// argumentos ni lo que va por el socket (ahí van la clave y el código).
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
                        return limpiar_linea(l);
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

/// Una llamada a la API de rclone (`rclone rcd` en un socket Unix propio, 0700, que vive lo que
/// dura la llamada). Así la clave y el código van en el cuerpo de la petición: ni en argv ni en el
/// entorno, y rclone escribe rclone.conf él mismo, cifrado.
fn rc(e: &Entorno, metodo: &str, cuerpo: &serde_json::Value) -> Result<serde_json::Value, Error> {
    use std::io::Read as _;
    use std::os::unix::net::UnixStream;
    let base = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    let dir = base.join(format!("mint-macos-appleid-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::DirBuilder::new().mode(0o700).create(&dir)?;
    let sock = dir.join("rc.sock");
    let mut hijo = Command::new(&e.rclone)
        .args(["rcd", "--rc-no-auth", "--rc-addr", &format!("unix://{}", sock.display())])
        .envs(entorno_rclone(e))
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|x| Error(format!("rclone did not start: {x}")))?;
    let r = (|| {
        let hasta = Instant::now() + Duration::from_secs(20);
        let mut s = loop {
            if let Ok(s) = UnixStream::connect(&sock) {
                break s;
            }
            if Instant::now() > hasta || hijo.try_wait().ok().flatten().is_some() {
                return error("rclone could not open its configuration.");
            }
            std::thread::sleep(Duration::from_millis(100));
        };
        let datos = cuerpo.to_string();
        s.set_read_timeout(Some(Duration::from_secs(180)))?;
        write!(s, "POST /{metodo} HTTP/1.0\r\nHost: rclone\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{datos}", datos.len())?;
        let mut resp = String::new();
        s.read_to_string(&mut resp)?;
        let json = resp.split_once("\r\n\r\n").map(|x| x.1).unwrap_or("");
        let v: serde_json::Value = serde_json::from_str(json.trim()).map_err(|_| Error("rclone answered something unexpected.".into()))?;
        match v.get("error").or_else(|| v.get("Error")).and_then(|m| m.as_str()).filter(|m| !m.is_empty()) {
            Some(m) => Err(Error(limpiar_linea(m.lines().next().unwrap_or(m)))),
            None => Ok(v),
        }
    })();
    let _ = hijo.kill();
    let _ = hijo.wait();
    let _ = fs::remove_dir_all(&dir);
    r
}

/// Lo que rclone contesta a un paso del alta: None si terminó, o (estado, pregunta) si quiere el código.
fn leer_paso(v: &serde_json::Value) -> Option<(String, String)> {
    let st = v.get("State").and_then(|s| s.as_str()).filter(|s| !s.is_empty())?;
    let p = v.pointer("/Option/Help").and_then(|h| h.as_str()).unwrap_or("Verification code");
    Some((st.to_string(), p.to_string()))
}

/// Primer paso: el remoto de iCloud con la contraseña (rclone la ofusca y la guarda en rclone.conf,
/// que va cifrado) y el alta.
fn iniciar(e: &Entorno, apple_id: &str, clave: &str) -> Result<Option<(String, String)>, Error> {
    if apple_id.trim().is_empty() || clave.is_empty() {
        return error("Enter your Apple ID and password.");
    }
    if apple_id.contains(['\n', '\r', '[', ']']) {
        return error("That is not an Apple ID.");
    }
    asegurar_cifrado(e)?;
    // Uno nuevo cada vez: la sesión de otro Apple ID no se mezcla con esta.
    let _ = rc(e, "config/delete", &serde_json::json!({ "name": e.remoto }));
    let r = rc(e, "config/create", &serde_json::json!({
        "name": e.remoto,
        "type": "iclouddrive",
        "parameters": { "apple_id": apple_id.trim(), "password": clave },
        "opt": { "obscure": true, "nonInteractive": true },
    }));
    match r {
        Ok(v) => Ok(leer_paso(&v)),
        Err(x) => {
            // Una contraseña que Apple no aceptó no se queda en rclone.conf.
            let _ = rc(e, "config/delete", &serde_json::json!({ "name": e.remoto }));
            Err(x)
        }
    }
}

fn seguir(e: &Entorno, estado: &str, codigo: &str) -> Result<Option<(String, String)>, Error> {
    let v = rc(e, "config/update", &serde_json::json!({
        "name": e.remoto,
        "parameters": {},
        "opt": { "continue": true, "state": estado, "result": codigo, "nonInteractive": true },
    }))?;
    Ok(leer_paso(&v))
}

fn sesion_icloud(e: &Entorno) -> Option<String> {
    let todo = volcado(e).ok()?;
    let d = todo.get(&e.remoto)?;
    let valor = |k: &str| d.get(k).and_then(|v| v.as_str()).filter(|v| !v.is_empty());
    (valor("type") == Some("iclouddrive") && (valor("trust_token").is_some() || valor("cookies").is_some()))
        .then(|| valor("apple_id").map(String::from))
        .flatten()
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
/// `servicio`: «mail» (la contraseña de app) o «rclone-config» (la clave de rclone.conf).
fn atributos<'a>(servicio: &'a str, apple_id: Option<&'a str>) -> HashMap<&'a str, &'a str> {
    let mut a = HashMap::from([("xdg:schema", ESQUEMA), ("servicio", servicio)]);
    if let Some(i) = apple_id {
        a.insert("apple_id", i);
    }
    a
}

mod secret {
    //! Lo justo del Secret Service (org.freedesktop.Secret) para guardar, leer, buscar y borrar,
    //! como hace libsecret, sin depender de ella.
    use super::*;
    use zbus::blocking::{Connection, Proxy};
    use zbus::zvariant::{ObjectPath, OwnedObjectPath};

    const DESTINO: &str = "org.freedesktop.secrets";
    const COLECCION: &str = "/org/freedesktop/secrets/aliases/default";

    /// Con tope: si el llavero no contesta (o tarda en arrancar), Estado no se queda colgado.
    fn conectar() -> zbus::Result<Connection> {
        zbus::blocking::connection::Builder::session()?.method_timeout(Duration::from_secs(5)).build()
    }

    fn proxy<'a>(c: &Connection, ruta: &'a str, interfaz: &'a str) -> zbus::Result<Proxy<'a>> {
        Proxy::new(c, DESTINO, ruta, interfaz)
    }

    fn servicio(c: &Connection) -> zbus::Result<Proxy<'static>> {
        proxy(c, "/org/freedesktop/secrets", "org.freedesktop.Secret.Service")
    }

    fn buscar(c: &Connection, attrs: &HashMap<&str, &str>) -> zbus::Result<(Vec<OwnedObjectPath>, Vec<OwnedObjectPath>)> {
        servicio(c)?.call("SearchItems", &(attrs,))
    }

    /// «plain»: el secreto viaja por el bus de la sesión, que solo es del usuario (lo mismo que
    /// libsecret cuando no negocia).
    fn sesion(c: &Connection) -> zbus::Result<OwnedObjectPath> {
        let (_, s): (OwnedValue, OwnedObjectPath) = servicio(c)?.call("OpenSession", &("plain", Value::from("")))?;
        Ok(s)
    }

    pub fn hay(attrs: &HashMap<&str, &str>) -> bool {
        conectar().and_then(|c| buscar(&c, attrs)).is_ok_and(|(a, b)| !a.is_empty() || !b.is_empty())
    }

    /// El secreto, si está y el llavero está abierto. Con `pedir`, si el llavero está cerrado se
    /// enseña su diálogo para abrirlo (el de gnome-keyring) y se espera un rato.
    pub fn leer(attrs: &HashMap<&str, &str>, pedir: bool) -> Result<Option<String>, Error> {
        let c = conectar()?;
        let (mut abiertos, cerrados) = buscar(&c, attrs)?;
        if abiertos.is_empty() && !cerrados.is_empty() {
            if !pedir {
                return error("The keyring is locked.");
            }
            let (_, prompt): (Vec<OwnedObjectPath>, OwnedObjectPath) = servicio(&c)?.call("Unlock", &(cerrados,))?;
            if prompt.as_str() != "/" {
                let _: zbus::Result<()> = proxy(&c, prompt.as_str(), "org.freedesktop.Secret.Prompt")?.call("Prompt", &("",));
            }
            let hasta = Instant::now() + Duration::from_secs(120);
            while abiertos.is_empty() && Instant::now() < hasta {
                std::thread::sleep(Duration::from_millis(500));
                abiertos = buscar(&c, attrs)?.0;
            }
            if abiertos.is_empty() {
                return error("The keyring is locked.");
            }
        }
        let Some(item) = abiertos.into_iter().next() else { return Ok(None) };
        let s = sesion(&c)?;
        let secretos: HashMap<OwnedObjectPath, (OwnedObjectPath, Vec<u8>, Vec<u8>, String)> =
            servicio(&c)?.call("GetSecrets", &(vec![item.clone()], s))?;
        Ok(secretos.get(&item).map(|x| String::from_utf8_lossy(&x.2).into_owned()))
    }

    pub fn guardar(etiqueta: &str, attrs: &HashMap<&str, &str>, clave: &str) -> Result<(), Error> {
        let c = conectar()?;
        let s = sesion(&c)?;
        let (_, prompt): (Vec<OwnedObjectPath>, OwnedObjectPath) = servicio(&c)?.call("Unlock", &(vec![ObjectPath::try_from(COLECCION)?],))?;
        if prompt.as_str() != "/" {
            return error("The keyring is locked: unlock it and try again.");
        }
        let a: HashMap<String, String> = attrs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
        let props: HashMap<&str, Value> = HashMap::from([
            ("org.freedesktop.Secret.Item.Label", Value::from(etiqueta)),
            ("org.freedesktop.Secret.Item.Attributes", Value::from(a)),
        ]);
        let secreto = (s.as_ref(), Vec::<u8>::new(), clave.as_bytes().to_vec(), "text/plain");
        let (_, prompt): (OwnedObjectPath, OwnedObjectPath) =
            proxy(&c, COLECCION, "org.freedesktop.Secret.Collection")?.call("CreateItem", &(props, secreto, true))?;
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

fn llavero_hay(e: &Entorno, servicio: &str) -> bool {
    match &e.llavero {
        Llavero::Sistema => secret::hay(&atributos(servicio, None)),
        Llavero::Archivo(d) => fs::read_to_string(d.join(servicio)).is_ok_and(|t| !t.trim().is_empty()),
    }
}

fn llavero_leer(e: &Entorno, servicio: &str, pedir: bool) -> Result<Option<String>, Error> {
    match &e.llavero {
        Llavero::Sistema => secret::leer(&atributos(servicio, None), pedir),
        Llavero::Archivo(d) => Ok(fs::read_to_string(d.join(servicio)).ok().and_then(|t| t.lines().last().map(|l| l.rsplit('\t').next().unwrap_or("").to_string()))),
    }
}

fn llavero_guardar(e: &Entorno, servicio: &str, etiqueta: &str, apple_id: Option<&str>, clave: &str) -> Result<(), Error> {
    match &e.llavero {
        Llavero::Sistema => secret::guardar(etiqueta, &atributos(servicio, apple_id), clave),
        Llavero::Archivo(d) => escribir_privado(&d.join(servicio), &format!("{}\t{clave}\n", apple_id.unwrap_or(""))),
    }
}

fn llavero_borrar(e: &Entorno, servicio: &str) {
    match &e.llavero {
        Llavero::Sistema => secret::borrar(&atributos(servicio, None)),
        Llavero::Archivo(d) => {
            let _ = fs::remove_file(d.join(servicio));
        }
    }
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

const CLAVE_CONFIG: &str = "rclone-config";

/// La clave de rclone.conf: 32 bytes al azar, en el llavero. Si ya hay una, se queda esa.
fn crear_clave_config(e: &Entorno) -> Result<(), Error> {
    if llavero_leer(e, CLAVE_CONFIG, true)?.is_some_and(|c| !c.is_empty()) {
        return Ok(());
    }
    let mut b = [0u8; 32];
    use std::io::Read as _;
    fs::File::open("/dev/urandom")?.read_exact(&mut b)?;
    llavero_guardar(e, CLAVE_CONFIG, "rclone configuration (mint-macos)", None, &base64(&b))?;
    match llavero_leer(e, CLAVE_CONFIG, false)? {
        Some(c) if c == base64(&b) => Ok(()),
        _ => error("The keyring did not keep rclone's key."),
    }
}

/// El ayudante (`--clave-config`): lo que rclone pide con --password-command. Espera al llavero un
/// rato (al entrar, el montaje puede llegar antes que gnome-keyring) y, si no, avisa y falla.
fn dar_clave_config(e: &Entorno) -> i32 {
    let hasta = Instant::now() + Duration::from_secs(90);
    let mut ultimo;
    loop {
        match llavero_leer(e, CLAVE_CONFIG, true) {
            Ok(Some(c)) if !c.is_empty() => {
                println!("{c}");
                return 0;
            }
            Ok(_) => {
                ultimo = "rclone's key is not in the keyring.".into();
                break;
            }
            Err(Error(m)) => ultimo = m,
        }
        if Instant::now() > hasta {
            break;
        }
        std::thread::sleep(Duration::from_secs(3));
    }
    eprintln!("mint-macos-appleid: {ultimo}");
    let _ = Command::new("notify-send")
        .args(["-i", "folder-remote", "iCloud Drive can't open its settings", &format!("{ultimo} Unlock the keyring (Passwords and Keys) and iCloud Drive will try again.")])
        .stdout(Stdio::null()).stderr(Stdio::null()).status();
    1
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
    llavero_guardar(e, "mail", &format!("Apple ID (app) {}", apple_id.trim()), Some(apple_id.trim()), clave_app.trim())?;
    let nombre = if nombre.trim().is_empty() { apple_id.trim() } else { nombre.trim() };
    escribir_userjs(&perfil, &bloque_userjs(&perfil, apple_id.trim(), nombre, &cals))?;
    Ok(cals.len())
}

/// Sign Out: el montaje, el remoto de rclone, el llavero y el bloque de Thunderbird.
fn cerrar_sesion(e: &Entorno) {
    if e.unidades.join(format!("{}.service", e.servicio)).exists() {
        systemctl(e, "stop");
    }
    // La clave de rclone.conf se queda: el archivo sigue cifrado con los otros remotos.
    let _ = rclone(e, &["config", "delete", &e.remoto], None);
    llavero_borrar(e, "mail");
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
    d.insert("mail_configurado".into(), Value::from(llavero_hay(e, "mail")).try_to_owned().unwrap());
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
    match std::env::args().nth(1).as_deref() {
        // El --password-command de rclone (lo pone el envoltorio ~/.local/bin/rclone).
        Some("--clave-config") => std::process::exit(dar_clave_config(&Entorno::real())),
        // icloud.sh cifrar: rclone.conf cifrado, con su clave en el llavero.
        Some("--cifrar-config") => std::process::exit(match asegurar_cifrado(&Entorno::real()) {
            Ok(()) => 0,
            Err(Error(m)) => {
                eprintln!("mint-macos-appleid: {m}");
                1
            }
        }),
        _ => {}
    }
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
