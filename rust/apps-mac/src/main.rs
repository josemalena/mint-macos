//! org.mintmacos.AppsMac1: las .app de Mac sin .desktop (decisión de José,
//! 27-10-2026). El Launchpad, el Muelle y Fynder le preguntan por una app que
//! no está abierta (su nombre, la clase de sus ventanas, sus íconos); las
//! ventanas que ya corren traen _DARLING_APP_NAME y _NET_WM_ICON.
//!
//! El contrato está en org.mintmacos.AppsMac1.xml, junto a este crate.
//!
//! - Lee las .app con comun::mac, igual que abrir-mac: nunca las ejecuta.
//! - Los íconos son todos los PNG del .icns, en ~/.cache/mint-macos/apps-mac.
//!   Las llamadas nunca esperan por ellos: devuelven los que ya están y un
//!   hilo hace los que faltan y avisa con IconosListos.
//! - AppsCambiaron cuando algo entra o sale de /Applications o ~/Applications
//!   (inotify, declarado a mano como Xlib en abrir-mac).
//! - Vive mientras quede en el bus alguien que lo llamó; si no, se va al
//!   minuto sin llamadas y la activación por D-Bus lo vuelve a levantar.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant, UNIX_EPOCH};

use comun::mac::{archivo_abiertas, archivo_icns, escribir_abiertas, leer_abiertas, leer_app, leer_con_tope,
                 nombre_visible, pngs_de_icns, revisar_macho, App};
use comun::{home, xdg};
use zbus::interface;
use zbus::message::Header;
use zbus::names::BusName;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{OwnedValue, Value};

const NOMBRE: &str = "org.mintmacos.AppsMac1";
const RUTA: &str = "/org/mintmacos/AppsMac1";
const SIN_LLAMADAS: Duration = Duration::from_secs(60);
// /Applications/Utilities/X.app está a un nivel; más hondo no se busca.
const PROFUNDIDAD: u32 = 2;

type Dic = HashMap<String, OwnedValue>;

static CONEXION: OnceLock<zbus::blocking::Connection> = OnceLock::new();

// --- Dónde están las apps --------------------------------------------------------

fn carpetas() -> Vec<PathBuf> {
    vec![PathBuf::from("/Applications"), home().join("Applications")]
}

fn buscar(dir: &Path, profundidad: u32, v: &mut Vec<PathBuf>) {
    let Ok(entradas) = fs::read_dir(dir) else { return };
    let mut hijos: Vec<PathBuf> = entradas.flatten().map(|e| e.path()).collect();
    hijos.sort();
    for p in hijos {
        let nombre = p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        if nombre.starts_with('.') || !p.is_dir() {
            continue;
        }
        if nombre.ends_with(".app") {
            v.push(p);
        } else if profundidad > 0 {
            buscar(&p, profundidad - 1, v);
        }
    }
}

/// Las .app de /Applications y ~/Applications (lo que devuelve Listar).
fn de_carpetas() -> Vec<PathBuf> {
    let mut v = Vec::new();
    for c in carpetas() {
        buscar(&c, PROFUNDIDAD, &mut v);
    }
    v
}

/// Las de las carpetas más las de mac-abiertas. Las abiertas que ya no
/// existen se botan del archivo.
fn candidatas() -> Vec<PathBuf> {
    let mut v = de_carpetas();
    let archivo = archivo_abiertas();
    let abiertas = leer_abiertas(&archivo);
    let vivas: Vec<(String, PathBuf)> = abiertas.iter().filter(|(_, r)| r.is_dir()).cloned().collect();
    if vivas.len() != abiertas.len() {
        let _ = escribir_abiertas(&archivo, &vivas);
    }
    for (_, r) in vivas {
        if !v.contains(&r) {
            v.push(r);
        }
    }
    v
}

fn leer(rutas: &[PathBuf]) -> Vec<App> {
    rutas.iter().filter_map(|r| leer_app(r).ok()).collect()
}

// --- Resolver ----------------------------------------------------------------------

/// En el orden del contrato: ruta, clase o bundle id, y el nombre solo si es
/// de una sola app.
fn resolver<'a>(clave: &str, apps: &'a [App], suelta: &'a mut Option<App>) -> Option<&'a App> {
    if clave.is_empty() {
        return None;
    }
    if clave.starts_with('/') {
        let p = fs::canonicalize(clave).ok()?;
        if let Some(a) = apps.iter().find(|a| a.ruta == p) {
            return Some(a);
        }
        // Cualquier .app del host, aunque no esté en las carpetas.
        *suelta = leer_app(&p).ok();
        return suelta.as_ref();
    }
    let id = clave.strip_prefix("darling-").unwrap_or(clave);
    if let Some(a) = apps.iter().find(|a| a.id.eq_ignore_ascii_case(id)) {
        return Some(a);
    }
    let mut por_nombre = apps.iter().filter(|a| a.nombre == clave || a.nombre_ejecutable == clave || nombre_visible(&a.ruta) == clave);
    let primera = por_nombre.next()?;
    if por_nombre.any(|a| a.id != primera.id) {
        return None;
    }
    Some(primera)
}

// --- Los íconos ------------------------------------------------------------------

fn cache() -> PathBuf {
    xdg("XDG_CACHE_HOME", ".cache").join("mint-macos/apps-mac")
}

fn mtime(p: &Path) -> String {
    fs::metadata(p).and_then(|m| m.modified()).ok().and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| format!("{}.{:09}", d.as_secs(), d.subsec_nanos())).unwrap_or_default()
}

/// Lo que invalida los PNG: el Info.plist (puede cambiar de .icns) y el .icns.
fn sello(app: &App, icns: &Path) -> String {
    format!("{} {} {}", mtime(&app.ruta.join("Contents/Info.plist")), mtime(icns), icns.display())
}

fn png(app: &App, px: u32) -> PathBuf {
    cache().join(format!("{}-{px}.png", app.id))
}

/// Los íconos ya hechos, o None si faltan o están viejos. Sin .icns: vacío.
fn en_cache(app: &App) -> Option<HashMap<u32, String>> {
    let Some(icns) = archivo_icns(app) else { return Some(HashMap::new()) };
    let texto = fs::read_to_string(cache().join(format!("{}.sello", app.id))).ok()?;
    let (primera, anchos) = texto.split_once('\n')?;
    if primera != sello(app, &icns) {
        return None;
    }
    let mut m = HashMap::new();
    for a in anchos.split_whitespace().filter_map(|a| a.parse::<u32>().ok()) {
        let p = png(app, a);
        if !p.is_file() {
            return None;
        }
        m.insert(a, p.to_string_lossy().into_owned());
    }
    Some(m)
}

fn generar(app: &App) -> HashMap<u32, String> {
    let mut m = HashMap::new();
    let Some(icns) = archivo_icns(app) else { return m };
    let Ok(datos) = leer_con_tope(&icns, 16 << 20) else { return m };
    if fs::create_dir_all(cache()).is_err() {
        return m;
    }
    for (a, cuerpo) in pngs_de_icns(&datos) {
        let p = png(app, a);
        if fs::write(&p, cuerpo).is_ok() {
            m.insert(a, p.to_string_lossy().into_owned());
        }
    }
    let mut anchos: Vec<u32> = m.keys().copied().collect();
    anchos.sort();
    let anchos: Vec<String> = anchos.iter().map(u32::to_string).collect();
    let _ = fs::write(cache().join(format!("{}.sello", app.id)), format!("{}\n{}\n", sello(app, &icns), anchos.join(" ")));
    m
}

/// Hace los PNG que faltan, de uno en uno, y avisa con IconosListos.
fn obrero(rx: Receiver<App>, estado: Arc<Mutex<Estado>>) {
    for app in rx {
        let iconos = generar(&app);
        estado.lock().unwrap().pendientes.remove(&app.id);
        if let Some(c) = CONEXION.get() {
            let _ = c.emit_signal(None::<BusName>, RUTA, NOMBRE, "IconosListos", &(app.id.as_str(), iconos));
        }
    }
}

// --- El diccionario de cada app --------------------------------------------------

fn valor<'a>(v: impl Into<Value<'a>>) -> OwnedValue {
    OwnedValue::try_from(v.into()).expect("sin descriptores de archivo")
}

fn dic(app: &App, iconos: HashMap<u32, String>) -> Dic {
    let motivo = revisar_macho(&app.ejecutable).err();
    let mut d = Dic::new();
    d.insert("ruta".into(), valor(app.ruta.to_string_lossy().into_owned()));
    d.insert("id".into(), valor(app.id.clone()));
    d.insert("nombre".into(), valor(app.nombre.clone()));
    d.insert("clase".into(), valor(format!("darling-{}", app.id.to_lowercase())));
    d.insert("ejecutable".into(), valor(app.ejecutable.to_string_lossy().into_owned()));
    d.insert("iconos".into(), valor(iconos));
    d.insert("puede_correr".into(), valor(motivo.is_none()));
    d.insert("motivo".into(), valor(motivo.unwrap_or_default()));
    d.insert("version_minima".into(), valor(app.minimo.clone().unwrap_or_default()));
    d
}

// --- El servicio -----------------------------------------------------------------

struct Estado {
    ultima: Instant,
    // Los nombres únicos que lo llamaron y siguen en el bus.
    clientes: HashSet<String>,
    // Los id cuyos PNG está haciendo el obrero.
    pendientes: HashSet<String>,
}

struct Servicio {
    estado: Arc<Mutex<Estado>>,
    obrero: Mutex<Sender<App>>,
}

impl Servicio {
    fn llamada(&self, h: &Header<'_>) {
        let mut e = self.estado.lock().unwrap();
        e.ultima = Instant::now();
        if let Some(s) = h.sender() {
            e.clientes.insert(s.to_string());
        }
    }

    /// Los íconos en caché; si faltan, se le piden al obrero y van vacíos.
    fn iconos(&self, app: &App) -> HashMap<u32, String> {
        if let Some(m) = en_cache(app) {
            return m;
        }
        if self.estado.lock().unwrap().pendientes.insert(app.id.clone()) {
            let _ = self.obrero.lock().unwrap().send(app.clone());
        }
        HashMap::new()
    }

    fn resolver_en(&self, clave: &str, apps: &[App]) -> Dic {
        let mut suelta = None;
        match resolver(clave, apps, &mut suelta) {
            Some(a) => dic(a, self.iconos(a)),
            None => Dic::new(),
        }
    }
}

#[interface(name = "org.mintmacos.AppsMac1")]
impl Servicio {
    fn resolver(&self, clave: &str, #[zbus(header)] h: Header<'_>) -> Dic {
        self.llamada(&h);
        self.resolver_en(clave, &leer(&candidatas()))
    }

    fn resolver_varias(&self, claves: Vec<String>, #[zbus(header)] h: Header<'_>) -> Vec<Dic> {
        self.llamada(&h);
        let apps = leer(&candidatas());
        claves.iter().map(|c| self.resolver_en(c, &apps)).collect()
    }

    fn listar(&self, #[zbus(header)] h: Header<'_>) -> Vec<Dic> {
        self.llamada(&h);
        let mut apps = leer(&de_carpetas());
        apps.sort_by_key(|a| a.nombre.to_lowercase());
        apps.iter().map(|a| dic(a, self.iconos(a))).collect()
    }

    #[zbus(signal)]
    async fn iconos_listos(emisor: &SignalEmitter<'_>, id: &str, iconos: HashMap<u32, String>) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn apps_cambiaron(emisor: &SignalEmitter<'_>) -> zbus::Result<()>;
}

// --- Quién sigue en el bus -------------------------------------------------------

/// Cuando un cliente sale del bus deja de contar; si era el último, el minuto
/// sin llamadas empieza ahí.
fn vigilar_clientes(c: zbus::blocking::Connection, estado: Arc<Mutex<Estado>>) {
    let Ok(bus) = zbus::blocking::fdo::DBusProxy::new(&c) else { return };
    let Ok(cambios) = bus.receive_name_owner_changed() else { return };
    for s in cambios {
        let Ok(a) = s.args() else { continue };
        if a.new_owner.is_none() && a.name.starts_with(':') {
            let mut e = estado.lock().unwrap();
            if e.clientes.remove(a.name.as_str()) && e.clientes.is_empty() {
                e.ultima = Instant::now();
            }
        }
    }
}

// --- inotify -----------------------------------------------------------------------

extern "C" {
    fn inotify_init1(flags: i32) -> i32;
    fn inotify_add_watch(fd: i32, ruta: *const std::ffi::c_char, mascara: u32) -> i32;
    fn read(fd: i32, buf: *mut std::ffi::c_void, n: usize) -> isize;
}

const IN_MOVED_FROM: u32 = 0x40;
const IN_MOVED_TO: u32 = 0x80;
const IN_CREATE: u32 = 0x100;
const IN_DELETE: u32 = 0x200;
const IN_CLOEXEC: i32 = 0o2000000;

/// Vigila las carpetas y sus subcarpetas que no son .app (Utilities).
fn vigilar_carpetas(fd: i32) {
    fn agregar(fd: i32, dir: &Path, profundidad: u32) {
        let Ok(c) = std::ffi::CString::new(dir.as_os_str().as_encoded_bytes()) else { return };
        if unsafe { inotify_add_watch(fd, c.as_ptr(), IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO) } < 0 {
            return;
        }
        if profundidad == 0 {
            return;
        }
        for e in fs::read_dir(dir).into_iter().flatten().flatten() {
            let p = e.path();
            let n = e.file_name().to_string_lossy().into_owned();
            if p.is_dir() && !n.ends_with(".app") && !n.starts_with('.') {
                agregar(fd, &p, profundidad - 1);
            }
        }
    }
    for c in carpetas() {
        agregar(fd, &c, PROFUNDIDAD - 1);
    }
}

fn vigilar_apps() {
    let fd = unsafe { inotify_init1(IN_CLOEXEC) };
    if fd < 0 {
        return;
    }
    vigilar_carpetas(fd);
    let mut buf = [0u8; 4096];
    loop {
        if unsafe { read(fd, buf.as_mut_ptr().cast(), buf.len()) } <= 0 {
            return;
        }
        // Copiar una .app son muchos eventos: se juntan un segundo.
        thread::sleep(Duration::from_secs(1));
        vigilar_carpetas(fd);
        if let Some(c) = CONEXION.get() {
            let _ = c.emit_signal(None::<BusName>, RUTA, NOMBRE, "AppsCambiaron", &());
        }
    }
}

fn main() {
    let estado = Arc::new(Mutex::new(Estado { ultima: Instant::now(), clientes: HashSet::new(), pendientes: HashSet::new() }));
    let (tx, rx) = channel();
    let c = zbus::blocking::connection::Builder::session()
        .and_then(|b| b.name(NOMBRE))
        .and_then(|b| b.serve_at(RUTA, Servicio { estado: estado.clone(), obrero: Mutex::new(tx) }))
        .and_then(|b| b.build());
    let c = match c {
        Ok(c) => c,
        Err(e) => {
            eprintln!("mint-macos-apps-mac: {e}");
            std::process::exit(1);
        }
    };
    let _ = CONEXION.set(c.clone());
    {
        let e = estado.clone();
        thread::spawn(move || obrero(rx, e));
    }
    {
        let e = estado.clone();
        let c = c.clone();
        thread::spawn(move || vigilar_clientes(c, e));
    }
    thread::spawn(vigilar_apps);
    // Sin clientes en el bus y sin llamadas, se va.
    loop {
        thread::sleep(Duration::from_secs(5));
        let e = estado.lock().unwrap();
        if e.clientes.is_empty() && e.pendientes.is_empty() && e.ultima.elapsed() > SIN_LLAMADAS {
            break;
        }
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    fn app(ruta: &str, id: &str, nombre: &str, ejecutable: &str) -> App {
        App {
            ruta: PathBuf::from(ruta),
            ejecutable: PathBuf::from(ruta).join("Contents/MacOS").join(ejecutable),
            nombre_ejecutable: ejecutable.into(),
            nombre: nombre.into(),
            id: id.into(),
            minimo: None,
            icono: None,
        }
    }

    #[test]
    fn orden_de_resolver() {
        let apps = vec![
            app("/Applications/TextEdit.app", "com.apple.TextEdit", "TextEdit", "TextEdit"),
            app("/Applications/Uno/Notas.app", "com.uno.notas", "Notas", "Notas"),
            app("/Applications/Dos/Notas.app", "com.dos.notas", "Notas", "Notas"),
        ];
        let mut s = None;
        assert_eq!(resolver("darling-com.apple.textedit", &apps, &mut s).map(|a| a.id.as_str()), Some("com.apple.TextEdit"));
        assert_eq!(resolver("com.apple.TextEdit", &apps, &mut s).map(|a| a.id.as_str()), Some("com.apple.TextEdit"));
        assert_eq!(resolver("TextEdit", &apps, &mut s).map(|a| a.id.as_str()), Some("com.apple.TextEdit"));
        // Dos apps con el mismo nombre: ninguna.
        assert!(resolver("Notas", &apps, &mut s).is_none());
        assert!(resolver("com.uno.notas", &apps, &mut s).is_some());
        assert!(resolver("", &apps, &mut s).is_none());
        assert!(resolver("/no/existe.app", &apps, &mut s).is_none());
    }
}
