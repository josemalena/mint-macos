//! Arma /Applications como la de macOS: una copia del .desktop por app y la
//! subcarpeta Utilities.
//!
//! Reemplaza a aplicaciones/aplicaciones.py con el mismo comportamiento: las mismas
//! opciones (con las abreviaturas y los mensajes de argparse), los mismos archivos
//! byte a byte, con la misma fecha, y la misma lista .mint-macos-aplicaciones.
//! Las apps las sigue dando la GIO del sistema (g_app_info_get_all), como en el
//! Python: el orden, los nombres traducidos, OnlyShowIn y TryExec salen de ahí, no
//! de una copia.
//!
//! Lo corre aplicaciones.service (el .path lo dispara al cambiar los lanzadores).
//!
//! Donde el Python revienta con una excepción (un archivo que no es UTF-8 estricto,
//! una lista que no es JSON, una carpeta sin permiso) este sale con 1 y un mensaje
//! corto. Diferencias conocidas, ninguna con archivos que este mismo programa
//! escribe: al quitar carpetas anidadas vacías el Python sigue el orden de un set
//! (cambia en cada corrida) y este va de la más honda a la de arriba; un lanzador
//! con nombre de archivo que no es UTF-8 o una lista con un \uD800 suelto sale con
//! 1; en los mensajes de error de las opciones, un carácter sin asignar de Unicode
//! sale tal cual y no escapado, y los dígitos que no son ASCII no cuentan como
//! número negativo.

use std::collections::{HashMap, HashSet};
use std::ffi::{CStr, CString, OsStr};
use std::fs;
use std::io::Write;
use std::os::raw::{c_char, c_int, c_ulong, c_void};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::PermissionsExt;
use std::process::exit;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// El __doc__ del Python (sacado tal cual del archivo): es la descripción de --help.
const AYUDA: &str = include_str!("ayuda.txt");

const DESTINO: &str = "/Applications";
const UTILITIES: &str = "Utilities";
const LISTA: &str = ".mint-macos-aplicaciones";

const OCULTAR: &[&str] = &[
    "fynder.desktop", "nemo.desktop", "nemo-mac.desktop", "org.gnome.Nautilus.desktop",
    "plank.desktop", "net.launchpad.plank.desktop",
    "rofi.desktop", "rofi-theme-selector.desktop",
];
const ARRIBA: &[&str] = &["cinnamon-settings.desktop", "mintinstall.desktop", "mint-macos-settings.desktop"];
const PREFERENCIAS: &str = "mint-macos-settings.desktop";
const AJUSTES_CINNAMON: &str = "cinnamon-settings.desktop";
const NOMBRES: &[(&str, &str)] = &[("launchpad.desktop", "Launchpad")];
const CATEGORIAS_UTILITIES: &[&str] = &[
    "System", "Monitor", "TerminalEmulator", "Security", "Filesystem",
    "X-GNOME-Utilities", "Settings", "DesktopSettings", "HardwareSettings",
    "Archiving",
];
/// Las terminaciones de GENERICOS, en el orden de la alternancia de la regex.
const GENERICOS: &[&str] = &["web browser", "browser", "mail", "email", "e-mail", "client"];

// --- GIO y libc -------------------------------------------------------------

#[repr(C)]
#[allow(dead_code)]
struct GList {
    data: *mut c_void,
    next: *mut GList,
    prev: *mut GList,
}

#[link(name = "gio-2.0")]
#[link(name = "gobject-2.0")]
#[link(name = "glib-2.0")]
extern "C" {
    fn g_app_info_get_all() -> *mut GList;
    fn g_app_info_should_show(app: *mut c_void) -> c_int;
    fn g_app_info_get_display_name(app: *mut c_void) -> *const c_char;
    fn g_desktop_app_info_get_filename(app: *mut c_void) -> *const c_char;
    fn g_desktop_app_info_get_generic_name(app: *mut c_void) -> *const c_char;
    fn g_desktop_app_info_get_categories(app: *mut c_void) -> *const c_char;
    fn g_desktop_app_info_get_boolean(app: *mut c_void, key: *const c_char) -> c_int;
}

#[repr(C)]
#[allow(dead_code)]
struct Passwd {
    pw_name: *mut c_char,
    pw_passwd: *mut c_char,
    pw_uid: u32,
    pw_gid: u32,
    pw_gecos: *mut c_char,
    pw_dir: *mut c_char,
    pw_shell: *mut c_char,
}

#[repr(C)]
#[allow(dead_code)]
#[derive(Default)]
struct Winsize {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
}

extern "C" {
    fn access(ruta: *const c_char, modo: c_int) -> c_int;
    fn getuid() -> u32;
    fn getpwuid(uid: u32) -> *mut Passwd;
    fn ioctl(fd: c_int, pedido: c_ulong, ...) -> c_int;
    fn setlocale(categoria: c_int, locale: *const c_char) -> *const c_char;
}

const LC_CTYPE: c_int = 0;

const W_OK: c_int = 2;
const X_OK: c_int = 1;
const TIOCGWINSZ: c_ulong = 0x5413;

/// Una app como la da GIO, leída de una vez.
struct App {
    ruta: Vec<u8>,
    mostrar: bool,
    nombre: String,
    generico: String,
    categorias: Option<String>,
    terminal: bool,
}

fn cadena(p: *const c_char) -> Option<String> {
    if p.is_null() {
        None
    } else {
        Some(unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned())
    }
}

/// Gio.AppInfo.get_all(). La lista no se libera: el proceso termina enseguida.
fn todas_las_apps() -> Vec<App> {
    let terminal = CString::new("Terminal").unwrap();
    let mut out = Vec::new();
    let mut l = unsafe { g_app_info_get_all() };
    while !l.is_null() {
        let a = unsafe { (*l).data };
        let ruta = unsafe { g_desktop_app_info_get_filename(a) };
        out.push(App {
            ruta: if ruta.is_null() { Vec::new() } else { unsafe { CStr::from_ptr(ruta) }.to_bytes().to_vec() },
            mostrar: unsafe { g_app_info_should_show(a) } != 0,
            nombre: cadena(unsafe { g_app_info_get_display_name(a) }).unwrap_or_default(),
            generico: cadena(unsafe { g_desktop_app_info_get_generic_name(a) }).unwrap_or_default(),
            categorias: cadena(unsafe { g_desktop_app_info_get_categories(a) }),
            terminal: unsafe { g_desktop_app_info_get_boolean(a, terminal.as_ptr()) } != 0,
        });
        l = unsafe { (*l).next };
    }
    out
}

// --- Cadenas como las de Python ---------------------------------------------
//
// Un str de Python que viene de una ruta o de argv puede llevar los bytes que no son
// UTF-8 como sustitutos U+DC80..U+DCFF (surrogateescape), y uno de JSON cualquier
// sustituto suelto. Por eso las rutas van como puntos de código (u32), no como String.

type T = Vec<u32>;

fn t(s: &str) -> T {
    s.chars().map(|c| c as u32).collect()
}

/// Bytes de una ruta o de argv → str de Python (surrogateescape).
fn de_fs(mut b: &[u8]) -> T {
    let mut out = T::new();
    loop {
        match std::str::from_utf8(b) {
            Ok(v) => {
                out.extend(v.chars().map(|c| c as u32));
                return out;
            }
            Err(e) => {
                let (bien, resto) = b.split_at(e.valid_up_to());
                out.extend(std::str::from_utf8(bien).unwrap().chars().map(|c| c as u32));
                let malos = e.error_len().unwrap_or(resto.len());
                out.extend(resto[..malos].iter().map(|&x| 0xdc00 + x as u32));
                b = &resto[malos..];
            }
        }
    }
}

/// str → bytes para el sistema; None donde Python da ValueError (un sustituto que
/// no es de surrogateescape, o un NUL).
fn a_fs(s: &[u32]) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    for &c in s {
        match c {
            0 => return None,
            0xdc80..=0xdcff => out.push((c - 0xdc00) as u8),
            0xd800..=0xdfff => return None,
            _ => {
                let mut buf = [0u8; 4];
                out.extend_from_slice(char::from_u32(c).unwrap().encode_utf8(&mut buf).as_bytes());
            }
        }
    }
    Some(out)
}

/// Como lo escribe sys.stdout (UTF-8 estricto): None si lleva un sustituto.
fn a_utf8(s: &[u32]) -> Option<String> {
    s.iter().map(|&c| char::from_u32(c)).collect()
}

/// Con surrogateescape: los U+DC80..U+DCFF vuelven a ser su byte; otro sustituto, None.
fn a_bytes_escape(s: &[u32]) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    for &c in s {
        match c {
            0xdc80..=0xdcff => out.push((c - 0xdc00) as u8),
            0xd800..=0xdfff => return None,
            _ => {
                let mut buf = [0u8; 4];
                out.extend_from_slice(char::from_u32(c).unwrap().encode_utf8(&mut buf).as_bytes());
            }
        }
    }
    Some(out)
}

/// El manejador de errores de sys.stdout de Python (config_get_stdio_errors):
/// surrogateescape si el LC_CTYPE es C, POSIX o uno de los de la coerción
/// (C.UTF-8, C.utf8, UTF-8); estricto con cualquier otro.
fn stdout_escapa() -> bool {
    static ESCAPA: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ESCAPA.get_or_init(|| {
        let vacio = CString::new("").unwrap();
        unsafe { setlocale(LC_CTYPE, vacio.as_ptr()) };
        let loc = unsafe { setlocale(LC_CTYPE, std::ptr::null()) };
        if loc.is_null() {
            return false;
        }
        let loc = unsafe { CStr::from_ptr(loc) }.to_bytes();
        matches!(loc, b"C" | b"POSIX" | b"C.UTF-8" | b"C.utf8" | b"UTF-8")
    })
}

/// sys.stdout.write(): None donde el Python revienta con UnicodeEncodeError.
fn para_stdout(s: &[u32]) -> Option<Vec<u8>> {
    if stdout_escapa() {
        a_bytes_escape(s)
    } else {
        a_utf8(s).map(String::into_bytes)
    }
}

/// Como lo escribe sys.stderr (backslashreplace).
fn a_err(s: &[u32]) -> String {
    s.iter()
        .map(|&c| match char::from_u32(c) {
            Some(ch) => ch.to_string(),
            None => format!("\\u{c:04x}"),
        })
        .collect()
}

fn de_t(s: &[u32]) -> String {
    a_utf8(s).unwrap_or_else(|| a_err(s))
}

fn concat(partes: &[&[u32]]) -> T {
    partes.iter().flat_map(|p| p.iter().copied()).collect()
}

/// str.isspace() de Python (y \s de re): incluye \x1c-\x1f, que char::is_whitespace no.
fn es_espacio(c: char) -> bool {
    c.is_whitespace() || ('\u{1c}'..='\u{1f}').contains(&c)
}

/// str.strip() de Python.
fn strip(s: &str) -> &str {
    s.trim_matches(es_espacio)
}

/// Los saltos de línea universales del modo texto de Python: \r\n y \r pasan a \n.
fn universal(s: &str) -> String {
    s.replace("\r\n", "\n").replace('\r', "\n")
}

/// str.isprintable() de Python, sin los puntos de código sin asignar (eso pide la
/// tabla de Unicode entera).
fn imprimible(c: u32) -> bool {
    let Some(ch) = char::from_u32(c) else { return false };
    if c == 0x20 {
        return true;
    }
    if ch.is_control() {
        return false;
    }
    let no = [
        // Zs, Zl, Zp
        (0xa0, 0xa0), (0x1680, 0x1680), (0x2000, 0x200a), (0x2028, 0x2029), (0x202f, 0x202f),
        (0x205f, 0x205f), (0x3000, 0x3000),
        // Cf
        (0xad, 0xad), (0x600, 0x605), (0x61c, 0x61c), (0x6dd, 0x6dd), (0x70f, 0x70f),
        (0x890, 0x891), (0x8e2, 0x8e2), (0x180e, 0x180e), (0x200b, 0x200f), (0x202a, 0x202e),
        (0x2060, 0x2064), (0x2066, 0x206f), (0xfeff, 0xfeff), (0xfff9, 0xfffb),
        (0x110bd, 0x110bd), (0x110cd, 0x110cd), (0x13430, 0x1343f), (0x1bca0, 0x1bca3),
        (0x1d173, 0x1d17a), (0xe0001, 0xe0001), (0xe0020, 0xe007f),
        // Co
        (0xe000, 0xf8ff), (0xf0000, 0xffffd), (0x100000, 0x10fffd),
    ];
    !no.iter().any(|&(a, b)| (a..=b).contains(&c))
}

/// repr() de un str de Python.
fn repr(s: &[u32]) -> T {
    let comilla = if s.contains(&('\'' as u32)) && !s.contains(&('"' as u32)) { '"' } else { '\'' } as u32;
    let mut r = vec![comilla];
    for &c in s {
        let esc = match c {
            0x5c => "\\\\".to_string(),
            0x0a => "\\n".to_string(),
            0x0d => "\\r".to_string(),
            0x09 => "\\t".to_string(),
            _ if c == comilla => format!("\\{}", char::from_u32(c).unwrap()),
            _ if imprimible(c) => {
                r.push(c);
                continue;
            }
            _ if c < 0x100 => format!("\\x{c:02x}"),
            _ if c < 0x10000 => format!("\\u{c:04x}"),
            _ => format!("\\U{c:08x}"),
        };
        r.extend(t(&esc));
    }
    r.push(comilla);
    r
}

// --- posixpath --------------------------------------------------------------

const BARRA: u32 = '/' as u32;

fn join(a: &[u32], b: &[u32]) -> T {
    if b.first() == Some(&BARRA) {
        b.to_vec()
    } else if a.is_empty() || a.last() == Some(&BARRA) {
        concat(&[a, b])
    } else {
        concat(&[a, &[BARRA], b])
    }
}

fn dirname(p: &[u32]) -> T {
    let i = p.iter().rposition(|&c| c == BARRA).map(|i| i + 1).unwrap_or(0);
    let mut head = p[..i].to_vec();
    if !head.is_empty() && head.iter().any(|&c| c != BARRA) {
        while head.last() == Some(&BARRA) {
            head.pop();
        }
    }
    head
}

fn basename(p: &[u8]) -> &[u8] {
    let i = p.iter().rposition(|&c| c == b'/').map(|i| i + 1).unwrap_or(0);
    &p[i..]
}

fn ruta(p: &[u32]) -> Option<std::path::PathBuf> {
    a_fs(p).map(|b| std::path::PathBuf::from(std::ffi::OsString::from_vec(b)))
}

/// os.path.exists / isfile / isdir: sigue los enlaces y da False ante cualquier error.
fn existe(p: &[u32]) -> bool {
    ruta(p).map(|r| fs::metadata(r).is_ok()).unwrap_or(false)
}

fn es_archivo(p: &[u32]) -> bool {
    ruta(p).and_then(|r| fs::metadata(r).ok()).map(|m| m.is_file()).unwrap_or(false)
}

fn es_carpeta(p: &[u32]) -> bool {
    ruta(p).and_then(|r| fs::metadata(r).ok()).map(|m| m.is_dir()).unwrap_or(false)
}

/// os.access: con una ruta que no se puede codificar, el Python revienta.
fn acceso(p: &[u32], modo: c_int) -> bool {
    let b = a_fs(p).unwrap_or_else(|| reventar(&format!("{}: ruta no válida", a_err(p))));
    let c = CString::new(b).unwrap();
    unsafe { access(c.as_ptr(), modo) == 0 }
}

/// Una ruta que el Python sí puede usar (si no, revienta).
fn ruta_o_reventar(p: &[u32]) -> std::path::PathBuf {
    ruta(p).unwrap_or_else(|| reventar(&format!("{}: ruta no válida", a_err(p))))
}

/// os.path.expanduser de «~/resto».
fn en_el_home(resto: &str) -> T {
    let home = match std::env::var_os("HOME") {
        Some(h) => h.into_vec(),
        None => {
            let pw = unsafe { getpwuid(getuid()) };
            if pw.is_null() || unsafe { (*pw).pw_dir }.is_null() {
                return t(&format!("~{resto}"));
            }
            unsafe { CStr::from_ptr((*pw).pw_dir) }.to_bytes().to_vec()
        }
    };
    let mut h = de_fs(&home);
    while h.last() == Some(&BARRA) {
        h.pop();
    }
    let r = concat(&[&h, &t(resto)]);
    if r.is_empty() { t("/") } else { r }
}

// --- Salida -----------------------------------------------------------------

/// Donde el Python termina con una excepción: sale con 1.
fn reventar(msg: &str) -> ! {
    let _ = std::io::stdout().flush();
    eprintln!("aplicaciones: {msg}");
    exit(1)
}

/// print() a stdout: si el texto no se puede escribir, el Python revienta ahí.
fn imprimir(s: &[u32]) {
    imprimir_crudo(&concat(&[s, &t("\n")]));
}

// --- La configuración -------------------------------------------------------

struct Config {
    ocultar: HashSet<T>,
    mostrar: HashSet<T>,
    arriba: HashSet<T>,
    utilities: HashSet<T>,
    nombre: HashMap<T, String>,
}

/// str.split(None, max) de Python.
fn split_ws(s: &str, max: usize) -> Vec<&str> {
    let mut out = Vec::new();
    let mut resto = s.trim_start_matches(es_espacio);
    while !resto.is_empty() {
        if out.len() == max {
            out.push(resto);
            break;
        }
        let fin = resto.find(es_espacio).unwrap_or(resto.len());
        out.push(&resto[..fin]);
        resto = resto[fin..].trim_start_matches(es_espacio);
    }
    out
}

fn leer_config(config: &[u32]) -> Config {
    let mut cfg = Config {
        ocultar: OCULTAR.iter().map(|s| t(s)).collect(),
        mostrar: HashSet::new(),
        arriba: ARRIBA.iter().map(|s| t(s)).collect(),
        utilities: HashSet::new(),
        nombre: NOMBRES.iter().map(|(a, b)| (t(a), b.to_string())).collect(),
    };
    if !existe(config) {
        return cfg;
    }
    let bytes = fs::read(ruta_o_reventar(config)).unwrap_or_else(|e| reventar(&format!("{}: {e}", de_t(config))));
    let texto = String::from_utf8(bytes).unwrap_or_else(|_| reventar(&format!("{}: no es UTF-8", de_t(config))));
    for linea in universal(&texto).split('\n') {
        let linea = strip(linea.split('#').next().unwrap());
        if linea.is_empty() {
            continue;
        }
        let partes = split_ws(linea, 2);
        if partes.len() < 2 {
            continue;
        }
        let (orden, id) = (partes[0], t(partes[1]));
        if orden == "nombre" && partes.len() == 3 {
            cfg.nombre.insert(id, strip(partes[2]).to_string());
        } else {
            match orden {
                "ocultar" => {
                    cfg.mostrar.remove(&id);
                    cfg.ocultar.insert(id);
                }
                "mostrar" => {
                    cfg.ocultar.remove(&id);
                    cfg.mostrar.insert(id);
                }
                "arriba" => {
                    cfg.arriba.insert(id);
                }
                "utilities" => {
                    cfg.utilities.insert(id);
                }
                _ => {}
            }
        }
    }
    cfg
}

// --- Las apps que entran ----------------------------------------------------

/// Un carácter contra una letra de GENERICOS con re.IGNORECASE: la minúscula simple
/// del carácter, más los arreglos de sre (ı con i, ſ con s); İ baja a i.
fn igual_sin_caso(c: char, letra: char) -> bool {
    if !letra.is_ascii_alphabetic() {
        return c == letra;
    }
    c.to_ascii_lowercase() == letra
        || (letra == 'i' && (c == '\u{130}' || c == '\u{131}'))
        || (letra == 's' && c == '\u{17f}')
}

/// GENERICOS.sub("", s): r"\s+(web browser|browser|mail|email|e-mail|client)$" con
/// re.I, buscando como sre (el primer inicio que casa, \s+ codicioso y la
/// alternancia en orden; $ casa al final o antes de un \n final).
fn quitar_generico(s: &str) -> String {
    let cs: Vec<char> = s.chars().collect();
    let n = cs.len();
    for i in 0..n {
        if !es_espacio(cs[i]) {
            continue;
        }
        let mut j = i;
        while j < n && es_espacio(cs[j]) {
            j += 1;
        }
        for k in (i + 1..=j).rev() {
            for w in GENERICOS {
                let w: Vec<char> = w.chars().collect();
                if k + w.len() > n || !w.iter().enumerate().all(|(m, &l)| igual_sin_caso(cs[k + m], l)) {
                    continue;
                }
                let fin = k + w.len();
                if fin == n || (fin + 1 == n && cs[fin] == '\n') {
                    return cs[..i].iter().chain(cs[fin..].iter()).collect();
                }
            }
        }
    }
    s.to_string()
}

/// «Firefox Web Browser» → «Firefox» (como en la barra del menú).
fn nombre_corto(app: &App) -> String {
    let n = strip(&app.nombre).to_string();
    let g = strip(&app.generico);
    let mut corto = n.clone();
    if !g.is_empty() && corto.to_lowercase().ends_with(&format!(" {}", g.to_lowercase())) {
        let quitar = g.chars().count() + 1;
        let largo = corto.chars().count();
        corto = corto.chars().take(largo.saturating_sub(quitar)).collect();
    }
    let corto = strip(&quitar_generico(&corto)).to_string();
    if corto.is_empty() { n } else { corto }
}

/// RE_PANEL: ^(cinnamon-settings-.+|cinnamon-.+-panel)\.desktop$ (el . no casa un
/// \n y el $ admite uno al final).
fn es_panel(id: &[u32]) -> bool {
    let Some(s) = a_utf8(id) else { return false };
    let s = s.strip_suffix('\n').unwrap_or(&s);
    let Some(base) = s.strip_suffix(".desktop") else { return false };
    if base.contains('\n') {
        return false;
    }
    let ajustes = base.len() > "cinnamon-settings-".len() && base.starts_with("cinnamon-settings-");
    let panel = base.len() > "cinnamon--panel".len() && base.starts_with("cinnamon-") && base.ends_with("-panel");
    ajustes || panel
}

#[derive(Clone)]
struct Vista {
    id: T,
    app: usize,
    nombre: String,
    sub: &'static str,
    exacto: bool,
    completo: String,
}

/// Las apps que entran: (id, índice de la app, nombre visible, subcarpeta), sin repetir.
fn aplicaciones(cfg: &Config, todas: &[App]) -> Vec<(T, usize, String, &'static str)> {
    let mut vistas: HashMap<String, Vista> = HashMap::new();
    let hay_preferencias = todas.iter().any(|a| a.mostrar && basename(&a.ruta) == PREFERENCIAS.as_bytes());
    for (i, app) in todas.iter().enumerate() {
        if !app.mostrar {
            continue;
        }
        let id_b = basename(&app.ruta);
        if app.ruta.is_empty() || !id_b.ends_with(b".desktop") {
            continue;
        }
        let id = de_fs(id_b);
        if cfg.ocultar.contains(&id) && !cfg.mostrar.contains(&id) {
            continue;
        }
        if id == t(AJUSTES_CINNAMON) && hay_preferencias && !cfg.mostrar.contains(&id) {
            continue;
        }
        if es_panel(&id) && !cfg.mostrar.contains(&id) {
            continue;
        }
        if app.terminal {
            continue;
        }
        if app.categorias.as_deref().unwrap_or("").contains("ConsoleOnly") {
            continue;
        }
        let completo = strip(&app.nombre).to_string();
        let nombre = match cfg.nombre.get(&id) {
            Some(n) if !n.is_empty() => n.clone(),
            _ => nombre_corto(app),
        };
        // El nombre es el propio del lanzador (o uno puesto a mano) y no uno acortado: «KiCad» a secas.
        let exacto = cfg.nombre.contains_key(&id) || nombre == completo;
        let cats = app.categorias.as_deref().unwrap_or("");
        let en_utilities = cats.split(';').any(|c| CATEGORIAS_UTILITIES.contains(&c));
        let sub = if cfg.arriba.contains(&id) {
            ""
        } else if cfg.utilities.contains(&id) || en_utilities {
            UTILITIES
        } else {
            ""
        };
        let clave = nombre.to_lowercase();
        if let Some(previo) = vistas.get(&clave).cloned() {
            // Dos lanzadores con el mismo nombre. Si es el mismo programa instalado dos veces (VS Code), gana el
            // primero que devuelve GIO, que es el de más prioridad. Pero «KiCad PCB Calculator» se acorta a «KiCad»
            // y chocaba con el KiCad de verdad: el que se acortó se queda con su nombre completo y el exacto con el
            // corto.
            if exacto && !previo.exacto && !previo.completo.is_empty() && !vistas.contains_key(&previo.completo.to_lowercase()) {
                vistas.insert(previo.completo.to_lowercase(), Vista { nombre: previo.completo.clone(), exacto: true, ..previo });
                vistas.insert(clave, Vista { id, app: i, nombre, sub, exacto, completo });
            } else if !exacto && previo.exacto && !completo.is_empty() && !vistas.contains_key(&completo.to_lowercase()) {
                vistas.insert(completo.to_lowercase(), Vista { id, app: i, nombre: completo.clone(), sub, exacto: true, completo });
            }
            continue;
        }
        vistas.insert(clave, Vista { id, app: i, nombre, sub, exacto, completo });
    }
    let mut out: Vec<_> = vistas.into_values().map(|v| (v.id, v.app, v.nombre, v.sub)).collect();
    out.sort_by_key(|v| (!v.3.is_empty(), v.2.to_lowercase()));
    out
}

/// ¿La línea empieza con ^(Name(\[[^\]]*\])?|X-MintMacos-Origen)= ?
fn es_linea_de_nombre(l: &str) -> bool {
    if l.starts_with("X-MintMacos-Origen=") {
        return true;
    }
    let Some(r) = l.strip_prefix("Name") else { return false };
    if r.starts_with('=') {
        return true;
    }
    match r.strip_prefix('[') {
        Some(r) => match r.find(']') {
            Some(f) => r[f + 1..].starts_with('='),
            None => false,
        },
        None => false,
    }
}

/// El .desktop con Name= cambiado (y sin los Name[xx]=, que lo taparían). El bool
/// dice que la ruta de origen no es UTF-8: el Python revienta al escribirlo.
fn contenido(origen: &[u8], visible: &str) -> (String, bool) {
    let p = std::path::Path::new(OsStr::from_bytes(origen));
    let bytes = fs::read(p).unwrap_or_else(|e| reventar(&format!("{}: {e}", p.display())));
    let texto = universal(&String::from_utf8_lossy(&bytes));
    let (origen_s, malo) = match std::str::from_utf8(origen) {
        Ok(s) => (s.to_string(), false),
        Err(_) => (String::from_utf8_lossy(origen).into_owned(), true),
    };
    let mut salida: Vec<String> = Vec::new();
    let (mut en_entrada, mut puesto) = (false, false);
    for l in texto.split('\n') {
        if l.starts_with('[') {
            if en_entrada && !puesto {
                salida.push(format!("Name={visible}"));
                puesto = true;
            }
            en_entrada = strip(l) == "[Desktop Entry]";
            salida.push(l.to_string());
            if en_entrada {
                salida.push(format!("Name={visible}"));
                salida.push(format!("X-MintMacos-Origen={origen_s}"));
                puesto = true;
            }
            continue;
        }
        if en_entrada && es_linea_de_nombre(l) {
            continue;
        }
        salida.push(l.to_string());
    }
    (salida.join("\n"), malo)
}

struct Deseado {
    texto: String,
    malo: bool,
    /// st_mtime del origen: segundos y nanosegundos.
    mtime: (i64, i64),
}

/// {ruta relativa: lo que debe tener} de todo lo que debe existir, en orden.
fn deseado(cfg: &Config, todas: &[App], sufijo: &str) -> Vec<(T, Deseado)> {
    let mut out = Vec::new();
    for (id, i, nombre, sub) in aplicaciones(cfg, todas) {
        let visible = format!("{nombre}{sufijo}");
        let rel = if sub.is_empty() { id } else { join(&t(sub), &id) };
        let origen = &todas[i].ruta;
        let (texto, malo) = contenido(origen, &visible);
        let m = fs::metadata(OsStr::from_bytes(origen)).unwrap_or_else(|e| reventar(&format!("{}: {e}", String::from_utf8_lossy(origen))));
        use std::os::unix::fs::MetadataExt;
        out.push((rel, Deseado { texto, malo, mtime: (m.mtime(), m.mtime_nsec()) }));
    }
    out.sort_by(|a, b| a.0.cmp(&b.0));
    out
}

/// os.utime(ruta, (mtime, mtime)) con el st_mtime en float, como el Python: el float
/// pierde los últimos nanosegundos y se redondea hacia abajo
/// (_PyTime_DoubleToDenominator con ROUND_FLOOR).
fn hora_como_python(sec: i64, nsec: i64) -> SystemTime {
    let d = sec as f64 + nsec as f64 * 1e-9;
    let mut entera = d.trunc();
    let mut frac = ((d - entera) * 1e9).floor();
    if frac >= 1e9 {
        frac -= 1e9;
        entera += 1.0;
    } else if frac < 0.0 {
        frac += 1e9;
        entera -= 1.0;
    }
    let (s, n) = (entera as i64, frac as u32);
    if s >= 0 {
        UNIX_EPOCH + Duration::new(s as u64, n)
    } else {
        UNIX_EPOCH - Duration::new(s.unsigned_abs(), 0) + Duration::new(0, n)
    }
}

// --- JSON (el de Python: json.load y json.dump con indent=0) ----------------

enum J {
    Cadena(T),
    /// Número, true, false o null: se puede meter en un set, pero no es un str.
    Otro,
    Lista(Vec<J>),
    Objeto(Vec<T>),
}

struct Lector {
    c: Vec<char>,
    i: usize,
}

impl Lector {
    fn ver(&self) -> Option<char> {
        self.c.get(self.i).copied()
    }

    fn espacios(&mut self) {
        while matches!(self.ver(), Some(' ' | '\t' | '\n' | '\r')) {
            self.i += 1;
        }
    }

    fn sigue(&self, s: &str) -> bool {
        s.chars().enumerate().all(|(k, ch)| self.c.get(self.i + k) == Some(&ch))
    }

    fn hex4(&self, desde: usize) -> Option<u32> {
        if desde + 4 > self.c.len() {
            return None;
        }
        let mut v = 0;
        for k in 0..4 {
            v = v * 16 + self.c[desde + k].to_digit(16)?;
        }
        Some(v)
    }

    fn cadena(&mut self) -> Result<T, ()> {
        self.i += 1;
        let mut out = T::new();
        loop {
            let ch = self.ver().ok_or(())?;
            self.i += 1;
            match ch {
                '"' => return Ok(out),
                '\\' => {
                    let e = self.ver().ok_or(())?;
                    self.i += 1;
                    let v = match e {
                        '"' => '"' as u32,
                        '\\' => '\\' as u32,
                        '/' => '/' as u32,
                        'b' => 8,
                        'f' => 12,
                        'n' => 10,
                        'r' => 13,
                        't' => 9,
                        'u' => {
                            let mut v = self.hex4(self.i).ok_or(())?;
                            self.i += 4;
                            if (0xd800..=0xdbff).contains(&v) && self.sigue("\\u") {
                                if let Some(b) = self.hex4(self.i + 2) {
                                    if (0xdc00..=0xdfff).contains(&b) {
                                        v = 0x10000 + ((v - 0xd800) << 10) + (b - 0xdc00);
                                        self.i += 6;
                                    }
                                }
                            }
                            v
                        }
                        _ => return Err(()),
                    };
                    out.push(v);
                }
                c if (c as u32) < 0x20 => return Err(()),
                c => out.push(c as u32),
            }
        }
    }

    fn numero(&mut self) -> Result<(), ()> {
        let digito = |l: &Lector, k: usize| l.c.get(k).map(|c| c.is_ascii_digit()).unwrap_or(false);
        if self.ver() == Some('-') {
            self.i += 1;
        }
        match self.ver() {
            Some('0') => self.i += 1,
            Some('1'..='9') => {
                while digito(self, self.i) {
                    self.i += 1;
                }
            }
            _ => return Err(()),
        }
        if self.ver() == Some('.') && digito(self, self.i + 1) {
            self.i += 1;
            while digito(self, self.i) {
                self.i += 1;
            }
        }
        if matches!(self.ver(), Some('e' | 'E')) {
            let mut k = self.i + 1;
            if matches!(self.c.get(k), Some('+' | '-')) {
                k += 1;
            }
            if digito(self, k) {
                self.i = k;
                while digito(self, self.i) {
                    self.i += 1;
                }
            }
        }
        Ok(())
    }

    fn valor(&mut self) -> Result<J, ()> {
        match self.ver().ok_or(())? {
            '"' => Ok(J::Cadena(self.cadena()?)),
            '{' => {
                self.i += 1;
                self.espacios();
                let mut claves: Vec<T> = Vec::new();
                if self.ver() == Some('}') {
                    self.i += 1;
                    return Ok(J::Objeto(claves));
                }
                loop {
                    if self.ver() != Some('"') {
                        return Err(());
                    }
                    let k = self.cadena()?;
                    self.espacios();
                    if self.ver() != Some(':') {
                        return Err(());
                    }
                    self.i += 1;
                    self.espacios();
                    self.valor()?;
                    if !claves.contains(&k) {
                        claves.push(k);
                    }
                    self.espacios();
                    match self.ver() {
                        Some('}') => {
                            self.i += 1;
                            return Ok(J::Objeto(claves));
                        }
                        Some(',') => {
                            self.i += 1;
                            self.espacios();
                        }
                        _ => return Err(()),
                    }
                }
            }
            '[' => {
                self.i += 1;
                self.espacios();
                let mut v = Vec::new();
                if self.ver() == Some(']') {
                    self.i += 1;
                    return Ok(J::Lista(v));
                }
                loop {
                    v.push(self.valor()?);
                    self.espacios();
                    match self.ver() {
                        Some(']') => {
                            self.i += 1;
                            return Ok(J::Lista(v));
                        }
                        Some(',') => {
                            self.i += 1;
                            self.espacios();
                        }
                        _ => return Err(()),
                    }
                }
            }
            _ => {
                for lit in ["null", "true", "false", "NaN", "Infinity", "-Infinity"] {
                    if self.sigue(lit) {
                        self.i += lit.chars().count();
                        return Ok(J::Otro);
                    }
                }
                self.numero()?;
                Ok(J::Otro)
            }
        }
    }
}

/// json.load de la lista (el archivo en UTF-8 estricto, con saltos universales).
fn leer_lista(p: &[u32]) -> J {
    let nombre = de_t(p);
    let bytes = fs::read(ruta_o_reventar(p)).unwrap_or_else(|e| reventar(&format!("{nombre}: {e}")));
    let texto = String::from_utf8(bytes).unwrap_or_else(|_| reventar(&format!("{nombre}: no es UTF-8")));
    let texto = universal(&texto);
    if texto.starts_with('\u{feff}') {
        reventar(&format!("{nombre}: JSON con BOM"));
    }
    let mut l = Lector { c: texto.chars().collect(), i: 0 };
    l.espacios();
    let v = l.valor().unwrap_or_else(|_| reventar(&format!("{nombre}: no es JSON")));
    l.espacios();
    if l.i != l.c.len() {
        reventar(&format!("{nombre}: no es JSON (sobra texto)"));
    }
    v
}

/// json.dump(lista, f, indent=0) con ensure_ascii.
fn json_lista(v: &[T]) -> String {
    if v.is_empty() {
        return "[]".to_string();
    }
    let items: Vec<String> = v
        .iter()
        .map(|s| {
            let mut o = String::from("\"");
            for &c in s {
                match c {
                    0x22 => o.push_str("\\\""),
                    0x5c => o.push_str("\\\\"),
                    0x0a => o.push_str("\\n"),
                    0x0d => o.push_str("\\r"),
                    0x09 => o.push_str("\\t"),
                    0x08 => o.push_str("\\b"),
                    0x0c => o.push_str("\\f"),
                    0x20..=0x7e => o.push(char::from_u32(c).unwrap()),
                    0x10000.. => {
                        let v = c - 0x10000;
                        o.push_str(&format!("\\u{:04x}\\u{:04x}", 0xd800 + (v >> 10), 0xdc00 + (v & 0x3ff)));
                    }
                    _ => o.push_str(&format!("\\u{c:04x}")),
                }
            }
            o.push('"');
            o
        })
        .collect();
    format!("[\n{}\n]", items.join(",\n"))
}

// --- Sincronizar y quitar ---------------------------------------------------

/// os.rmdir(sub) si es una carpeta vacía que no es el destino.
fn quitar_si_vacia(sub: &[u32], destino: &[u32]) {
    if sub == destino || !es_carpeta(sub) {
        return;
    }
    let r = ruta_o_reventar(sub);
    let vacia = fs::read_dir(&r).unwrap_or_else(|e| reventar(&format!("{}: {e}", de_t(sub)))).next().is_none();
    if vacia {
        fs::remove_dir(&r).unwrap_or_else(|e| reventar(&format!("{}: {e}", de_t(sub))));
    }
}

fn escribir(destino: &[u32], rel: &[u32], d: &Deseado) {
    let r = ruta_o_reventar(&join(destino, rel));
    let carpeta = dirname(&join(destino, rel));
    if carpeta.is_empty() {
        reventar("carpeta vacía");
    }
    fs::create_dir_all(ruta_o_reventar(&carpeta)).unwrap_or_else(|e| reventar(&format!("{}: {e}", de_t(&carpeta))));
    let mut f = fs::File::create(&r).unwrap_or_else(|e| reventar(&format!("{}: {e}", r.display())));
    if d.malo {
        reventar(&format!("{}: la ruta de origen no es UTF-8", r.display()));
    }
    f.write_all(d.texto.as_bytes()).unwrap_or_else(|e| reventar(&format!("{}: {e}", r.display())));
    drop(f);
    fs::set_permissions(&r, fs::Permissions::from_mode(0o755)).unwrap_or_else(|e| reventar(&format!("{}: {e}", r.display())));
    let hora = hora_como_python(d.mtime.0, d.mtime.1);
    let f = fs::File::options().write(true).open(&r).unwrap_or_else(|e| reventar(&format!("{}: {e}", r.display())));
    f.set_times(fs::FileTimes::new().set_accessed(hora).set_modified(hora))
        .unwrap_or_else(|e| reventar(&format!("{}: {e}", r.display())));
}

fn sincronizar(destino: &[u32], cfg: &Config, sufijo: &str, simular: bool) {
    let lista_ruta = join(destino, &t(LISTA));
    let mut previo: HashSet<T> = HashSet::new();
    // Un número o un null dentro de la lista: el Python revienta al ordenar lo que
    // sobra, después de escribir y antes de quitar.
    let mut previo_no_str = false;
    if existe(&lista_ruta) {
        match leer_lista(&lista_ruta) {
            J::Lista(v) => {
                for e in v {
                    match e {
                        J::Cadena(s) => {
                            previo.insert(s);
                        }
                        J::Otro => previo_no_str = true,
                        _ => reventar("la lista trae una lista o un objeto adentro (no se puede meter en un set)"),
                    }
                }
            }
            J::Objeto(k) => previo.extend(k),
            J::Cadena(s) => previo.extend(s.into_iter().map(|c| vec![c])),
            J::Otro => reventar("la lista no es una lista"),
        }
    }
    // GIO, después de leer la lista: la primera llamada crea ~/.cache y el Python, si
    // la lista revienta, no llega a hacerla.
    let todas = todas_las_apps();
    let quiero = deseado(cfg, &todas, sufijo);
    let (mut escritos, mut borrados) = (0, 0);

    for (rel, d) in &quiero {
        let r = join(destino, rel);
        // Si existe y no es nuestro, no se pisa.
        if existe(&r) && !previo.contains(rel) {
            eprintln!("respeto {}: ya existe y no es mío", a_err(rel));
            continue;
        }
        let mut igual = false;
        if existe(&r) {
            let p = ruta_o_reventar(&r);
            let b = fs::read(&p).unwrap_or_else(|e| reventar(&format!("{}: {e}", p.display())));
            igual = !d.malo && universal(&String::from_utf8_lossy(&b)) == d.texto;
        }
        if igual && acceso(&r, X_OK) {
            continue;
        }
        escritos += 1;
        if simular {
            imprimir(&concat(&[&t("+ "), rel]));
            continue;
        }
        escribir(destino, rel, d);
    }

    if previo_no_str {
        reventar("la lista trae algo que no es texto");
    }
    let quiero_set: HashSet<&T> = quiero.iter().map(|(r, _)| r).collect();
    let mut sobran: Vec<&T> = previo.iter().filter(|r| !quiero_set.contains(r)).collect();
    sobran.sort();
    for rel in sobran {
        let r = join(destino, rel);
        if es_archivo(&r) {
            borrados += 1;
            if simular {
                imprimir(&concat(&[&t("- "), rel]));
            } else {
                fs::remove_file(ruta_o_reventar(&r)).unwrap_or_else(|e| reventar(&format!("{}: {e}", de_t(&r))));
            }
        }
        if !simular {
            quitar_si_vacia(&dirname(&r), destino);
        }
    }

    if !simular {
        let lista: Vec<T> = quiero.iter().map(|(r, _)| r.clone()).collect();
        let p = ruta_o_reventar(&lista_ruta);
        fs::write(&p, json_lista(&lista)).unwrap_or_else(|e| reventar(&format!("{}: {e}", p.display())));
    }
    imprimir(&concat(&[
        &t(&format!("{} apps en ", quiero.len())),
        destino,
        &t(&format!(": {escritos} escritas, {borrados} quitadas.")),
    ]));
}

fn quitar(destino: &[u32], simular: bool) {
    let lista_ruta = join(destino, &t(LISTA));
    if !existe(&lista_ruta) {
        imprimir(&t("No hay nada generado aquí."));
        return;
    }
    let previo: Vec<T> = match leer_lista(&lista_ruta) {
        J::Lista(v) => {
            let mut out = Vec::new();
            for e in v {
                match e {
                    J::Cadena(s) => out.push(s),
                    // El Python borra los de antes y revienta en os.path.join.
                    _ => {
                        quitar_los(destino, &out, simular);
                        reventar("la lista trae algo que no es texto");
                    }
                }
            }
            out
        }
        J::Objeto(k) => k,
        J::Cadena(s) => s.into_iter().map(|c| vec![c]).collect(),
        J::Otro => reventar("la lista no es una lista"),
    };
    quitar_los(destino, &previo, simular);
    if !simular {
        // El Python recorre un set (su orden cambia en cada corrida); aquí, de la
        // carpeta más honda a la de arriba, para que una anidada vacía no deje a su
        // madre llena.
        let mut subs: Vec<T> = previo.iter().map(|r| dirname(&join(destino, r))).collect();
        subs.sort_by(|a, b| b.len().cmp(&a.len()).then(a.cmp(b)));
        subs.dedup();
        for sub in subs {
            quitar_si_vacia(&sub, destino);
        }
        let p = ruta_o_reventar(&lista_ruta);
        fs::remove_file(&p).unwrap_or_else(|e| reventar(&format!("{}: {e}", p.display())));
    }
    imprimir(&t("Listo: la carpeta quedó como estaba (la carpeta en sí no se borra)."));
}

fn quitar_los(destino: &[u32], previo: &[T], simular: bool) {
    for rel in previo {
        let r = join(destino, rel);
        if es_archivo(&r) {
            imprimir(&concat(&[&t(if simular { "- " } else { "borro " }), rel]));
            if !simular {
                fs::remove_file(ruta_o_reventar(&r)).unwrap_or_else(|e| reventar(&format!("{}: {e}", de_t(&r))));
            }
        }
    }
}

// --- Las opciones, como argparse (Python 3.12) ------------------------------

#[derive(Clone, Copy, PartialEq)]
enum Accion {
    Ayuda,
    Destino,
    Simular,
    Quitar,
    SinSufijo,
}

const OPCIONES: &[(&str, Accion)] = &[
    ("-h", Accion::Ayuda),
    ("--help", Accion::Ayuda),
    ("--destino", Accion::Destino),
    ("--simular", Accion::Simular),
    ("--quitar", Accion::Quitar),
    ("--sin-sufijo", Accion::SinSufijo),
];

fn nombre_accion(a: Accion) -> &'static str {
    match a {
        Accion::Ayuda => "-h/--help",
        Accion::Destino => "--destino",
        Accion::Simular => "--simular",
        Accion::Quitar => "--quitar",
        Accion::SinSufijo => "--sin-sufijo",
    }
}

fn buscar_opcion(s: &[u32]) -> Option<(&'static str, Accion)> {
    OPCIONES.iter().copied().find(|(o, _)| t(o) == s)
}

/// (acción, opción, separador, argumento explícito); acción None: opción desconocida.
#[derive(Clone)]
struct Tupla {
    accion: Option<Accion>,
    opcion: T,
    sep: Option<T>,
    explicito: Option<T>,
}

struct Opciones {
    destino: T,
    simular: bool,
    quitar: bool,
    sin_sufijo: bool,
}

struct Parser {
    prog: T,
}

impl Parser {
    /// shutil.get_terminal_size().columns - 2.
    fn ancho() -> i128 {
        let mut col: i128 = 0;
        if let Some(v) = std::env::var_os("COLUMNS") {
            if let Some(n) = v.to_str().and_then(entero_python) {
                col = n;
            }
        }
        if col <= 0 {
            let mut w = Winsize::default();
            let r = unsafe { ioctl(1, TIOCGWINSZ, &mut w as *mut Winsize) };
            col = if r != 0 || w.ws_col == 0 { 80 } else { w.ws_col as i128 };
        }
        col - 2
    }

    fn uso(&self) -> T {
        let ancho = Self::ancho();
        let partes = ["[-h]", "[--destino DESTINO]", "[--simular]", "[--quitar]", "[--sin-sufijo]"];
        let prefijo = "usage: ";
        let lp = prefijo.chars().count() as i128;
        let prog = &self.prog;
        let completo = concat(&[prog, &t(" "), &t(&partes.join(" "))]);
        let cuerpo = if lp + completo.len() as i128 > ancho {
            let lineas = |partes: &[T], sangria: &T, con_prefijo: bool| -> Vec<T> {
                let mut lineas: Vec<T> = Vec::new();
                let mut linea: Vec<T> = Vec::new();
                let ls = sangria.len() as i128;
                let mut largo = if con_prefijo { lp - 1 } else { ls - 1 };
                for p in partes {
                    if largo + 1 + p.len() as i128 > ancho && !linea.is_empty() {
                        lineas.push(concat(&[sangria, &unir(&linea)]));
                        linea.clear();
                        largo = ls - 1;
                    }
                    linea.push(p.clone());
                    largo += p.len() as i128 + 1;
                }
                if !linea.is_empty() {
                    lineas.push(concat(&[sangria, &unir(&linea)]));
                }
                if con_prefijo {
                    lineas[0] = lineas[0][sangria.len()..].to_vec();
                }
                lineas
            };
            let opt: Vec<T> = partes.iter().map(|p| t(p)).collect();
            let lineas = if 4 * (lp + prog.len() as i128) <= 3 * ancho {
                let sangria = vec![' ' as u32; prefijo.chars().count() + prog.len() + 1];
                let mut todo = vec![prog.clone()];
                todo.extend(opt);
                lineas(&todo, &sangria, true)
            } else {
                let sangria = vec![' ' as u32; prefijo.chars().count()];
                let mut l = vec![prog.clone()];
                l.extend(lineas(&opt, &sangria, false));
                l
            };
            let mut u = T::new();
            for (k, l) in lineas.iter().enumerate() {
                if k > 0 {
                    u.push('\n' as u32);
                }
                u.extend(l);
            }
            u
        } else {
            completo
        };
        concat(&[&t(prefijo), &cuerpo, &t("\n")])
    }

    fn ayuda(&self) -> T {
        let ancho = Self::ancho();
        let max_pos = 24i128.min((ancho - 20).max(4));
        let pos = (19 + 2).min(max_pos);
        let ancho_accion = pos - 2 - 2;
        let mut s = self.uso();
        s.extend(t("\n"));
        s.extend(t(AYUDA));
        s.extend(t("\noptions:\n"));
        let cab = "-h, --help";
        if cab.len() as i128 <= ancho_accion {
            s.extend(t(&format!("  {cab:<w$}  show this help message and exit\n", w = ancho_accion as usize)));
        } else {
            s.extend(t(&format!("  {cab}\n{}show this help message and exit\n", " ".repeat(pos as usize))));
        }
        for o in ["--destino DESTINO", "--simular", "--quitar", "--sin-sufijo"] {
            s.extend(t(&format!("  {o}\n")));
        }
        s
    }

    fn error(&self, msg: &[u32]) -> ! {
        eprint!("{}", a_err(&self.uso()));
        eprintln!("{}: error: {}", a_err(&self.prog), a_err(msg));
        exit(2)
    }

    fn error_accion(&self, a: Accion, msg: &[u32]) -> ! {
        self.error(&concat(&[&t(&format!("argument {}: ", nombre_accion(a))), msg]))
    }

    fn opcional(&self, arg: &[u32]) -> Option<Tupla> {
        let guion = '-' as u32;
        if arg.is_empty() || arg[0] != guion {
            return None;
        }
        if let Some((o, a)) = buscar_opcion(arg) {
            return Some(Tupla { accion: Some(a), opcion: t(o), sep: None, explicito: None });
        }
        if arg.len() == 1 {
            return None;
        }
        let igual = arg.iter().position(|&c| c == '=' as u32);
        if let Some(k) = igual {
            if let Some((o, a)) = buscar_opcion(&arg[..k]) {
                return Some(Tupla { accion: Some(a), opcion: t(o), sep: Some(t("=")), explicito: Some(arg[k + 1..].to_vec()) });
            }
        }
        let mut tuplas = Vec::new();
        if arg[1] == guion {
            let (prefijo, sep, explicito) = match igual {
                Some(k) => (&arg[..k], Some(t("=")), Some(arg[k + 1..].to_vec())),
                None => (arg, None, None),
            };
            for (o, a) in OPCIONES {
                if empieza_t(&t(o), prefijo) {
                    tuplas.push(Tupla { accion: Some(*a), opcion: t(o), sep: sep.clone(), explicito: explicito.clone() });
                }
            }
        } else {
            let corto = &arg[..2];
            for (o, a) in OPCIONES {
                if t(o) == corto {
                    tuplas.push(Tupla { accion: Some(*a), opcion: t(o), sep: Some(T::new()), explicito: Some(arg[2..].to_vec()) });
                } else if empieza_t(&t(o), arg) {
                    tuplas.push(Tupla { accion: Some(*a), opcion: t(o), sep: None, explicito: None });
                }
            }
        }
        if tuplas.len() > 1 {
            let lista: Vec<T> = tuplas.iter().map(|x| x.opcion.clone()).collect();
            let mut m = concat(&[&t("ambiguous option: "), arg, &t(" could match ")]);
            for (k, o) in lista.iter().enumerate() {
                if k > 0 {
                    m.extend(t(", "));
                }
                m.extend(o);
            }
            self.error(&m);
        }
        if let Some(x) = tuplas.pop() {
            return Some(x);
        }
        if negativo(arg) || arg.contains(&(' ' as u32)) {
            return None;
        }
        Some(Tupla { accion: None, opcion: arg.to_vec(), sep: None, explicito: None })
    }

    fn analizar(&self, args: &[T]) -> Opciones {
        let mut op = Opciones { destino: t(DESTINO), simular: false, quitar: false, sin_sufijo: false };
        // El patrón de argparse: 'O' opción, 'A' argumento, '-' el «--».
        let mut patron: Vec<char> = Vec::new();
        let mut indices: HashMap<usize, Tupla> = HashMap::new();
        let mut k = 0;
        while k < args.len() {
            if args[k] == t("--") {
                patron.push('-');
                patron.extend(std::iter::repeat('A').take(args.len() - k - 1));
                break;
            }
            match self.opcional(&args[k]) {
                Some(x) => {
                    indices.insert(k, x);
                    patron.push('O');
                }
                None => patron.push('A'),
            }
            k += 1;
        }
        let mut extras: Vec<T> = Vec::new();
        let mut inicio = 0usize;
        let max = indices.keys().max().copied();
        while max.map(|m| inicio <= m).unwrap_or(false) {
            let siguiente = *indices.keys().filter(|&&i| i >= inicio).min().unwrap();
            if !indices.contains_key(&inicio) {
                extras.extend(args[inicio..siguiente].iter().cloned());
                inicio = siguiente;
            }
            inicio = self.consumir(inicio, args, &patron, &indices, &mut extras, &mut op);
        }
        extras.extend(args[inicio.min(args.len())..].iter().cloned());
        if !extras.is_empty() {
            let mut m = t("unrecognized arguments: ");
            for (k, e) in extras.iter().enumerate() {
                if k > 0 {
                    m.push(' ' as u32);
                }
                m.extend(e);
            }
            self.error(&m);
        }
        op
    }

    fn consumir(
        &self,
        inicio: usize,
        args: &[T],
        patron: &[char],
        indices: &HashMap<usize, Tupla>,
        extras: &mut Vec<T>,
        op: &mut Opciones,
    ) -> usize {
        let Tupla { accion, mut opcion, mut sep, mut explicito } = indices[&inicio].clone();
        let Some(mut accion) = accion else {
            extras.push(args[inicio].clone());
            return inicio + 1;
        };
        let mut acciones: Vec<(Accion, Option<T>)> = Vec::new();
        let fin;
        loop {
            let toma = if accion == Accion::Destino { 1 } else { 0 };
            if let Some(e) = explicito.clone() {
                if toma == 0 && opcion[1] != '-' as u32 && !e.is_empty() {
                    let sep_si = sep.as_ref().map(|s| !s.is_empty()).unwrap_or(false);
                    if sep_si || e[0] == '-' as u32 {
                        self.error_accion(accion, &concat(&[&t("ignored explicit argument "), &repr(&e)]));
                    }
                    acciones.push((accion, None));
                    opcion = vec!['-' as u32, e[0]];
                    if let Some((_, a)) = buscar_opcion(&opcion) {
                        accion = a;
                        let resto = e[1..].to_vec();
                        if resto.is_empty() {
                            sep = None;
                            explicito = None;
                        } else if resto[0] == '=' as u32 {
                            sep = Some(t("="));
                            explicito = Some(resto[1..].to_vec());
                        } else {
                            sep = Some(T::new());
                            explicito = Some(resto);
                        }
                    } else {
                        extras.push(concat(&[&t("-"), &e]));
                        fin = inicio + 1;
                        break;
                    }
                } else if toma == 1 {
                    acciones.push((accion, Some(e)));
                    fin = inicio + 1;
                    break;
                } else {
                    self.error_accion(accion, &concat(&[&t("ignored explicit argument "), &repr(&e)]));
                }
            } else {
                if toma == 1 {
                    if patron.get(inicio + 1) != Some(&'A') {
                        self.error_accion(accion, &t("expected one argument"));
                    }
                    acciones.push((accion, Some(args[inicio + 1].clone())));
                } else {
                    acciones.push((accion, None));
                }
                fin = inicio + 1 + toma;
                break;
            }
        }
        for (a, v) in acciones {
            match a {
                Accion::Ayuda => {
                    imprimir_crudo(&self.ayuda());
                    exit(0)
                }
                Accion::Destino => op.destino = v.unwrap(),
                Accion::Simular => op.simular = true,
                Accion::Quitar => op.quitar = true,
                Accion::SinSufijo => op.sin_sufijo = true,
            }
        }
        fin
    }
}

fn unir(partes: &[T]) -> T {
    let mut u = T::new();
    for (k, p) in partes.iter().enumerate() {
        if k > 0 {
            u.push(' ' as u32);
        }
        u.extend(p);
    }
    u
}

fn empieza_t(s: &[u32], p: &[u32]) -> bool {
    s.len() >= p.len() && s[..p.len()] == p[..]
}

/// stdout.write() del texto tal cual (sin el \n de print).
fn imprimir_crudo(s: &[u32]) {
    match para_stdout(s) {
        Some(v) => {
            let mut o = std::io::stdout().lock();
            let _ = o.write_all(&v);
            let _ = o.flush();
        }
        None => reventar("no se puede escribir en stdout un texto con un sustituto suelto"),
    }
}

/// _negative_number_matcher de argparse: ^-\d+$|^-\d*\.\d+$ ($ admite un \n final).
fn negativo(a: &[u32]) -> bool {
    let casa = |s: &[u32]| -> bool {
        let Some((&g, r)) = s.split_first() else { return false };
        if g != '-' as u32 {
            return false;
        }
        let dig = |c: &u32| (b'0' as u32..=b'9' as u32).contains(c);
        if !r.is_empty() && r.iter().all(dig) {
            return true;
        }
        match r.iter().position(|&c| c == '.' as u32) {
            Some(p) => r[..p].iter().all(dig) && r.len() > p + 1 && r[p + 1..].iter().all(dig),
            None => false,
        }
    };
    casa(a) || (a.last() == Some(&('\n' as u32)) && casa(&a[..a.len() - 1]))
}

/// int(s) de Python para un número en base 10 (sin los dígitos que no son ASCII).
fn entero_python(s: &str) -> Option<i128> {
    let s = strip(s);
    let (neg, cuerpo) = match s.as_bytes().first() {
        Some(b'-') => (true, &s[1..]),
        Some(b'+') => (false, &s[1..]),
        _ => (false, s),
    };
    if cuerpo.is_empty() || cuerpo.starts_with('_') || cuerpo.ends_with('_') || cuerpo.contains("__") {
        return None;
    }
    let mut v: i128 = 0;
    for c in cuerpo.chars() {
        if c == '_' {
            continue;
        }
        let d = c.to_digit(10)? as i128;
        v = v.saturating_mul(10).saturating_add(d);
    }
    Some(if neg { -v } else { v })
}

fn main() {
    // Cinnamon es el escritorio; sin esto, un servicio de systemd (sin sesión
    // gráfica en el entorno) vería otras OnlyShowIn y descartaría apps de más.
    if std::env::var_os("XDG_CURRENT_DESKTOP").is_none() {
        std::env::set_var("XDG_CURRENT_DESKTOP", "X-Cinnamon");
    }
    // XDG_DATA_DIRS completo: un servicio de systemd no siempre trae las de Flatpak y
    // Snap, y sin ellas sus apps desaparecerían de /Applications. Antes de la primera
    // llamada a GIO, que lo lee una vez.
    let actuales = std::env::var_os("XDG_DATA_DIRS").map(|v| v.into_vec()).unwrap_or_default();
    let mut dirs: Vec<Vec<u8>> = actuales.split(|&b| b == b':').filter(|d| !d.is_empty()).map(|d| d.to_vec()).collect();
    let flatpak_usuario = a_fs(&en_el_home("/.local/share/flatpak/exports/share")).unwrap_or_default();
    for d in [
        b"/usr/local/share".to_vec(),
        b"/usr/share".to_vec(),
        b"/var/lib/flatpak/exports/share".to_vec(),
        flatpak_usuario,
        b"/var/lib/snapd/desktop".to_vec(),
    ] {
        if !dirs.contains(&d) && std::path::Path::new(OsStr::from_bytes(&d)).is_dir() {
            dirs.push(d);
        }
    }
    std::env::set_var("XDG_DATA_DIRS", OsStr::from_bytes(&dirs.join(&b':')));
    let config = en_el_home("/.config/mint-macos/aplicaciones.conf");

    let mut argv = std::env::args_os();
    let prog = argv.next().map(|a| de_fs(basename(a.as_bytes()))).unwrap_or_default();
    let args: Vec<T> = argv.map(|a| de_fs(a.as_bytes())).collect();
    let a = Parser { prog }.analizar(&args);

    if !es_carpeta(&a.destino) {
        let d = a_err(&a.destino);
        eprintln!("No existe {d}. Para /Applications hace falta crearla una vez, con tu usuario como dueño:\n  sudo install -d -o $USER -g $(id -gn) {d}");
        exit(1);
    }
    if !acceso(&a.destino, W_OK) {
        let d = a_err(&a.destino);
        eprintln!("{d} no es tuya. Una vez:\n  sudo chown $USER:$(id -gn) {d}");
        exit(1);
    }
    if a.quitar {
        quitar(&a.destino, a.simular);
    } else {
        let cfg = leer_config(&config);
        sincronizar(&a.destino, &cfg, if a.sin_sufijo { "" } else { ".app" }, a.simular);
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn generico_como_la_regex() {
        assert_eq!(quitar_generico("Firefox Web Browser"), "Firefox");
        assert_eq!(quitar_generico("Thunderbird Mail"), "Thunderbird");
        assert_eq!(quitar_generico("X web  browser"), "X web");
        assert_eq!(quitar_generico("Evolution E-MAIL"), "Evolution");
        assert_eq!(quitar_generico("Foo Clıent"), "Foo");
        assert_eq!(quitar_generico("Foo client\n"), "Foo\n");
        assert_eq!(quitar_generico("Mail"), "Mail");
    }

    #[test]
    fn rutas_como_posixpath() {
        assert_eq!(join(&t("/a/"), &t("b")), t("/a/b"));
        assert_eq!(join(&t("/a"), &t("/b")), t("/b"));
        assert_eq!(dirname(&t("/a/b/")), t("/a/b"));
        assert_eq!(dirname(&t("//x")), t("//"));
        assert_eq!(dirname(&t("x")), t(""));
    }

    #[test]
    fn json_como_python() {
        assert_eq!(json_lista(&[]), "[]");
        assert_eq!(json_lista(&[t("a"), t("Utilities/é😀\"")]), "[\n\"a\",\n\"Utilities/\\u00e9\\ud83d\\ude00\\\"\"\n]");
    }

    #[test]
    fn la_hora_pierde_lo_que_pierde_el_float() {
        let h = hora_como_python(1_760_000_000, 123_456_789);
        let d = h.duration_since(UNIX_EPOCH).unwrap();
        assert_eq!(d.as_secs(), 1_760_000_000);
        assert_ne!(d.subsec_nanos(), 123_456_789);
    }
}
