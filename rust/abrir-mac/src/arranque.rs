//! La notificación de arranque de freedesktop (startup-notification 0.1): un
//! «new:» al lanzar y un «remove:» cuando sale la ventana o la app falla. Con
//! ella el Muelle pone el ícono de la app rebotando en cuanto se pide abrirla
//! (StartupMonitor y LaunchingDockItem del fork de Plank, que la reconocen por
//! WMCLASS «darling-…») y Muffin pone el cursor de espera, como en la Mac.
//!
//! Los mensajes van a la ventana raíz como ClientMessage de 20 bytes:
//! el primero _NET_STARTUP_INFO_BEGIN, los demás _NET_STARTUP_INFO, y el
//! texto termina en NUL. El que manda tiene que ser una ventana, así que se
//! crea una sin mapear y se bota al terminar, como hace libstartup-notification.
//! Xlib se declara a mano: son seis funciones y no vale un crate por ellas.

use std::ffi::{c_char, c_int, c_long, c_uint, c_ulong, c_void, CString};
use std::ptr;

type Display = c_void;
type Window = c_ulong;
type Atom = c_ulong;

#[repr(C)]
#[derive(Clone, Copy)]
struct XClientMessageEvent {
    tipo: c_int,
    serial: c_ulong,
    send_event: c_int,
    display: *mut Display,
    window: Window,
    message_type: Atom,
    format: c_int,
    // La unión b[20] / s[10] / l[5] de Xlib: mide y se alinea como cinco long.
    data: [c_long; 5],
}

#[repr(C)]
union XEvent {
    xclient: XClientMessageEvent,
    _relleno: [c_long; 24],
}

const CLIENT_MESSAGE: c_int = 33;
const PROPERTY_CHANGE_MASK: c_long = 1 << 22;

#[link(name = "X11")]
extern "C" {
    fn XOpenDisplay(nombre: *const c_char) -> *mut Display;
    fn XCloseDisplay(d: *mut Display) -> c_int;
    fn XDefaultRootWindow(d: *mut Display) -> Window;
    fn XInternAtom(d: *mut Display, nombre: *const c_char, solo_si_existe: c_int) -> Atom;
    fn XCreateSimpleWindow(d: *mut Display, padre: Window, x: c_int, y: c_int, ancho: c_uint, alto: c_uint,
                           borde: c_uint, color_borde: c_ulong, fondo: c_ulong) -> Window;
    fn XDestroyWindow(d: *mut Display, w: Window) -> c_int;
    fn XSendEvent(d: *mut Display, w: Window, propagar: c_int, mascara: c_long, e: *mut XEvent) -> c_int;
    fn XFlush(d: *mut Display) -> c_int;
}

/// Un valor entre comillas, con \ delante de las comillas y de la propia \.
fn citar(v: &str) -> String {
    let mut s = String::from("\"");
    for c in v.chars() {
        if c == '"' || c == '\\' {
            s.push('\\');
        }
        s.push(c);
    }
    s.push('"');
    s
}

/// «new: ID="…" NAME="…"» a partir de las parejas clave/valor.
fn mensaje(orden: &str, campos: &[(&str, &str)]) -> String {
    let mut m = format!("{orden}:");
    for (k, v) in campos {
        m.push(' ');
        m.push_str(k);
        m.push('=');
        m.push_str(&citar(v));
    }
    m
}

/// Los trozos de 20 bytes, con el NUL final; el último se rellena con ceros.
fn trozos(m: &str) -> Vec<[u8; 20]> {
    let mut bytes = m.as_bytes().to_vec();
    bytes.push(0);
    bytes.chunks(20).map(|c| {
        let mut t = [0u8; 20];
        t[..c.len()].copy_from_slice(c);
        t
    }).collect()
}

/// Manda un mensaje. Sin DISPLAY (o sin X) no hace nada: es un adorno, no
/// puede impedir que la app abra.
fn mandar(m: &str) {
    unsafe {
        let d = XOpenDisplay(ptr::null());
        if d.is_null() {
            return;
        }
        let raiz = XDefaultRootWindow(d);
        let emisor = XCreateSimpleWindow(d, raiz, -100, -100, 1, 1, 0, 0, 0);
        let inicio = CString::new("_NET_STARTUP_INFO_BEGIN").unwrap();
        let resto = CString::new("_NET_STARTUP_INFO").unwrap();
        let a_inicio = XInternAtom(d, inicio.as_ptr(), 0);
        let a_resto = XInternAtom(d, resto.as_ptr(), 0);
        for (i, t) in trozos(m).iter().enumerate() {
            let mut data = [0 as c_long; 5];
            ptr::copy_nonoverlapping(t.as_ptr(), data.as_mut_ptr() as *mut u8, 20);
            let mut e = XEvent {
                xclient: XClientMessageEvent {
                    tipo: CLIENT_MESSAGE,
                    serial: 0,
                    send_event: 1,
                    display: d,
                    window: emisor,
                    message_type: if i == 0 { a_inicio } else { a_resto },
                    format: 8,
                    data,
                },
            };
            XSendEvent(d, raiz, 0, PROPERTY_CHANGE_MASK, &mut e);
        }
        XDestroyWindow(d, emisor);
        XFlush(d);
        XCloseDisplay(d);
    }
}

/// Una secuencia de arranque abierta. Al soltarla manda el «remove:», también
/// la que heredó de quien lo lanzó (DESKTOP_STARTUP_ID), para que el cursor de
/// espera no se quede hasta que Muffin se canse.
pub struct Arranque {
    ids: Vec<String>,
}

impl Arranque {
    /// `clase` es la WM_CLASS que tendrán sus ventanas («darling-<id>»): con
    /// ella el Muelle sabe qué app es y quita el ícono saltando cuando sale.
    pub fn empezar(nombre: &str, clase: &str, icono: Option<&str>, binario: &str) -> Arranque {
        let id = format!("mint-macos-abrir-mac-{}-{}", std::process::id(),
                         std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0));
        let mut campos = vec![("ID", id.as_str()), ("NAME", nombre), ("SCREEN", "0"), ("BIN", binario), ("WMCLASS", clase)];
        if let Some(i) = icono {
            campos.push(("ICON", i));
        }
        mandar(&mensaje("new", &campos));
        let mut ids = vec![id];
        if let Ok(heredado) = std::env::var("DESKTOP_STARTUP_ID") {
            if !heredado.is_empty() {
                ids.push(heredado);
            }
        }
        Arranque { ids }
    }
}

impl Drop for Arranque {
    fn drop(&mut self) {
        for id in &self.ids {
            mandar(&mensaje("remove", &[("ID", id)]));
        }
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn el_mensaje_cita_y_escapa() {
        assert_eq!(mensaje("new", &[("ID", "a"), ("NAME", "Dice \"hola\" \\")]),
                   "new: ID=\"a\" NAME=\"Dice \\\"hola\\\" \\\\\"");
    }

    #[test]
    fn trozos_de_veinte_con_nul() {
        let t = trozos("remove: ID=\"0123456789\"");
        assert_eq!(t.len(), 2);
        assert_eq!(&t[0], b"remove: ID=\"01234567");
        assert_eq!(&t[1][..5], b"89\"\0\0");
        // Si el texto mide justo 20, el NUL va en un trozo aparte.
        assert_eq!(trozos(&"x".repeat(20)).len(), 2);
    }
}

#[cfg(test)]
mod en_x {
    /// A mano, con un X de prueba: `DISPLAY=:78 cargo test -- --ignored`
    /// mientras `xev -root -event property` escucha en ese display.
    #[test]
    #[ignore]
    fn manda_new_y_remove() {
        let a = super::Arranque::empezar("TextEdit", "darling-com.apple.textedit", Some("/tmp/x.png"), "TextEdit");
        drop(a);
    }
}
