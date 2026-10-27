//! Lo que comparten mint-macos-appimages y mint-macos-abrir-mac: la ventana de
//! Gatekeeper de la primera vez, los avisos de Cinnamon, el origen de un archivo
//! bajado y su sha256. Salió de appimages/src/main.rs tal cual; ver
//! aplicaciones/APPIMAGE.md («Cómo quedó») para la pregunta y lo que se guarda.

use std::ffi::{CStr, CString, OsString};
use std::fs;
use std::io::Read;
use std::os::raw::{c_char, c_int, c_void};
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

// --- GLib y libc ----------------------------------------------------------------

const G_CHECKSUM_SHA256: c_int = 2;

#[link(name = "glib-2.0")]
extern "C" {
    fn g_checksum_new(tipo: c_int) -> *mut c_void;
    fn g_checksum_update(c: *mut c_void, data: *const u8, len: isize);
    fn g_checksum_get_string(c: *mut c_void) -> *const c_char;
    fn g_checksum_free(c: *mut c_void);
}

extern "C" {
    fn getxattr(path: *const c_char, name: *const c_char, value: *mut c_void, size: usize) -> isize;
}

pub fn sha256_de(ruta: &Path) -> std::io::Result<String> {
    let mut f = fs::File::open(ruta)?;
    let mut buf = vec![0u8; 1 << 20];
    unsafe {
        let c = g_checksum_new(G_CHECKSUM_SHA256);
        loop {
            let n = match f.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => n,
                Err(e) => {
                    g_checksum_free(c);
                    return Err(e);
                }
            };
            g_checksum_update(c, buf.as_ptr(), n as isize);
        }
        let s = CStr::from_ptr(g_checksum_get_string(c)).to_string_lossy().into_owned();
        g_checksum_free(c);
        Ok(s)
    }
}

/// Un atributo extendido como bytes, o None si no está.
pub fn xattr(ruta: &Path, nombre: &str) -> Option<Vec<u8>> {
    let c = CString::new(ruta.as_os_str().as_bytes()).ok()?;
    let nombre = CString::new(nombre).ok()?;
    let mut buf = vec![0u8; 4096];
    let n = unsafe { getxattr(c.as_ptr(), nombre.as_ptr(), buf.as_mut_ptr() as *mut c_void, buf.len()) };
    if n <= 0 {
        return None;
    }
    buf.truncate(n as usize);
    Some(buf)
}

/// De dónde se bajó: Chrome y Firefox lo anotan en user.xdg.origin.url.
pub fn origen_de(ruta: &Path) -> Option<String> {
    String::from_utf8(xattr(ruta, "user.xdg.origin.url")?).ok().filter(|s| !s.is_empty())
}

// --- Dónde vive cada cosa ------------------------------------------------------

pub fn xdg(var: &str, defecto: &str) -> PathBuf {
    match std::env::var_os(var) {
        Some(v) if Path::new(&v).is_absolute() => PathBuf::from(v),
        _ => home().join(defecto),
    }
}

pub fn home() -> PathBuf {
    PathBuf::from(std::env::var_os("HOME").unwrap_or_else(|| OsString::from("/")))
}

/// $XDG_STATE_HOME/mint-macos: las aprobadas y los avisos.
pub fn estado() -> PathBuf {
    xdg("XDG_STATE_HOME", ".local/state").join("mint-macos")
}

// --- Aprobadas -----------------------------------------------------------------

/// Si el sha256 ya está en el archivo de aprobadas (líneas «<sha256> <ruta>»).
pub fn aprobada(archivo: &Path, sha: &str) -> bool {
    fs::read_to_string(archivo)
        .map(|t| t.lines().any(|x| x.split(' ').next() == Some(sha)))
        .unwrap_or(false)
}

pub fn aprobar(archivo: &Path, sha: &str, ruta: &Path) {
    use std::io::Write;
    if let Some(d) = archivo.parent() {
        let _ = fs::create_dir_all(d);
    }
    if let Ok(mut f) = fs::OpenOptions::new().create(true).append(true).open(archivo) {
        let _ = writeln!(f, "{sha} {}", ruta.display());
    }
}

// --- Avisos --------------------------------------------------------------------

/// `quien` es el prefijo de la línea en stderr («appimages», «abrir-mac»).
pub fn avisar(quien: &str, titulo: &str, cuerpo: &str) {
    eprintln!("{quien}: {titulo}: {cuerpo}");
    // Sin esperar: en una sesión sin servidor de avisos, notify-send no debe trabar.
    let _ = Command::new("notify-send")
        .args(["-a", "Applications", "-i", "dialog-warning", titulo, cuerpo])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

// --- La pregunta de la primera vez --------------------------------------------

/// La ventana de Gatekeeper: mac-gatekeeper si está (Vala, con la cara de
/// Catalina); si no, zenity. true = Open.
pub fn preguntar(nombre: &str, origen: Option<&str>, icono: Option<&str>, ruta: &Path) -> bool {
    let host = origen.and_then(|o| o.split("://").nth(1)).and_then(|r| r.split('/').next()).filter(|h| !h.is_empty());
    let segunda = match host {
        Some(h) => format!("It was downloaded from {h}."),
        None => "Its origin is unknown.".to_string(),
    };
    let st = if en_path("mac-gatekeeper") {
        let mut c = Command::new("mac-gatekeeper");
        c.arg("--app").arg(nombre).arg("--ruta").arg(ruta);
        if let Some(o) = origen {
            c.arg("--origen").arg(o);
        }
        if let Some(i) = icono {
            c.arg("--icono").arg(i);
        }
        c.status()
    } else {
        Command::new("zenity")
            .args(["--question", "--title=", "--icon-name=dialog-warning", "--ok-label=Open", "--cancel-label=Cancel", "--width=420"])
            .arg(format!(
                "--text=<b>“{}” is an app downloaded from the Internet. Are you sure you want to open it?</b>\n\n{}",
                marcado(nombre),
                marcado(&segunda)
            ))
            .stderr(Stdio::null())
            .status()
    };
    matches!(st, Ok(s) if s.success())
}

pub fn en_path(p: &str) -> bool {
    std::env::var_os("PATH").map(|v| std::env::split_paths(&v).any(|d| d.join(p).is_file())).unwrap_or(false)
}

pub fn marcado(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn aprobadas_formato_compartido() {
        let dir = std::env::temp_dir().join(format!("mint-macos-comun-{}", std::process::id()));
        let archivo = dir.join("sub/aprobadas");
        assert!(!aprobada(&archivo, "abc"), "sin archivo no hay nada aprobado");
        aprobar(&archivo, "abc", Path::new("/Applications/Uno Dos.app"));
        assert!(aprobada(&archivo, "abc"));
        assert!(!aprobada(&archivo, "abcd"), "compara el sha entero, no un prefijo");
        assert_eq!(fs::read_to_string(&archivo).unwrap(), "abc /Applications/Uno Dos.app\n");
        let _ = fs::remove_dir_all(&dir);
    }
}
