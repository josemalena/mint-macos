//! Qué decodifica la GPU por VA-API, leído al arrancar (la GPU no cambia con el
//! sistema corriendo). Se pregunta a libva directo, por el nodo de render DRM, sin X
//! y sin llamar a vainfo: vaGetDisplayDRM, vaInitialize, vaQueryConfigProfiles y,
//! de cada perfil, si tiene el punto de entrada VLD (decodificar).
//!
//! Sirve para decidir si hace falta enhanced-h264ify: una GPU que decodifica H.264
//! pero no VP9 ni AV1 (la HD 4000 de la Mac mini) se ahoga con lo que YouTube manda
//! por defecto (settings/navegadores).
//!
//! Los valores de VAProfile y VAEntrypoint son los de va/va.h (libva 2.x).

use std::ffi::{c_char, c_int, c_void};
use std::os::fd::AsRawFd;
use std::path::Path;

#[link(name = "libva.so.2", kind = "dylib", modifiers = "+verbatim")]
extern "C" {
    fn vaInitialize(dpy: *mut c_void, major: *mut c_int, minor: *mut c_int) -> c_int;
    fn vaTerminate(dpy: *mut c_void) -> c_int;
    fn vaMaxNumProfiles(dpy: *mut c_void) -> c_int;
    fn vaMaxNumEntrypoints(dpy: *mut c_void) -> c_int;
    fn vaQueryConfigProfiles(dpy: *mut c_void, list: *mut c_int, n: *mut c_int) -> c_int;
    fn vaQueryConfigEntrypoints(dpy: *mut c_void, profile: c_int, list: *mut c_int, n: *mut c_int) -> c_int;
    fn vaSetErrorCallback(dpy: *mut c_void, cb: *const c_void, ctx: *mut c_void) -> *const c_void;
    fn vaSetInfoCallback(dpy: *mut c_void, cb: *const c_void, ctx: *mut c_void) -> *const c_void;
}

#[link(name = "libva-drm.so.2", kind = "dylib", modifiers = "+verbatim")]
extern "C" {
    fn vaGetDisplayDRM(fd: c_int) -> *mut c_void;
}

const VLD: c_int = 1;

/// VAProfile → el nombre del códec (los que se ven en GPUs de verdad).
pub fn codec(perfil: c_int) -> Option<&'static str> {
    Some(match perfil {
        0 | 1 => "mpeg2",
        2..=4 => "mpeg4",
        5..=7 | 13 | 15 | 16 | 36 => "h264",
        8..=10 => "vc1",
        11 => "h263",
        12 => "jpeg",
        14 => "vp8",
        17 | 18 | 23..=31 | 34 => "hevc",
        19..=22 => "vp9",
        32 | 33 => "av1",
        _ => return None,
    })
}

unsafe extern "C" fn callado(_ctx: *mut c_void, _msg: *const c_char) {}

/// Los códecs que decodifica la GPU del nodo `render` (p. ej. /dev/dri/renderD128),
/// ordenados y sin repetir. None si no hay nodo o libva no inicia.
pub fn decodifica(render: &Path) -> Option<Vec<&'static str>> {
    let f = std::fs::OpenOptions::new().read(true).write(true).open(render).ok()?;
    unsafe {
        let dpy = vaGetDisplayDRM(f.as_raw_fd());
        if dpy.is_null() {
            return None;
        }
        // libva escribe «libva info: …» en la salida; aquí no hace falta.
        vaSetErrorCallback(dpy, callado as *const c_void, std::ptr::null_mut());
        vaSetInfoCallback(dpy, callado as *const c_void, std::ptr::null_mut());
        let (mut ma, mut mi) = (0, 0);
        if vaInitialize(dpy, &mut ma, &mut mi) != 0 {
            vaTerminate(dpy);
            return None;
        }
        let mut perfiles = vec![0; vaMaxNumProfiles(dpy).max(0) as usize];
        let mut n = 0;
        let mut out = Vec::new();
        if vaQueryConfigProfiles(dpy, perfiles.as_mut_ptr(), &mut n) == 0 {
            let mut ents = vec![0; vaMaxNumEntrypoints(dpy).max(1) as usize];
            for &p in &perfiles[..n.max(0) as usize] {
                let mut ne = 0;
                if vaQueryConfigEntrypoints(dpy, p, ents.as_mut_ptr(), &mut ne) == 0 && ents[..ne.max(0) as usize].contains(&VLD) {
                    out.extend(codec(p));
                }
            }
        }
        vaTerminate(dpy);
        drop(f);
        out.sort();
        out.dedup();
        Some(out)
    }
}

/// El primer nodo de render de /dev/dri (renderD128…), bajo `raiz`.
pub fn nodo(raiz: &Path) -> Option<std::path::PathBuf> {
    let mut v: Vec<_> = std::fs::read_dir(raiz.join("dev/dri")).ok()?.flatten().map(|e| e.path()).filter(|p| p.file_name().map(|n| n.to_string_lossy().starts_with("renderD")).unwrap_or(false)).collect();
    v.sort();
    v.into_iter().next()
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn perfiles_de_va_h() {
        assert_eq!(codec(7), Some("h264"));
        assert_eq!(codec(13), Some("h264"));
        assert_eq!(codec(19), Some("vp9"));
        assert_eq!(codec(32), Some("av1"));
        assert_eq!(codec(18), Some("hevc"));
        assert_eq!(codec(-1), None);
    }

    /// Contra la GPU de verdad, si la hay: lo mismo que dice vainfo.
    #[test]
    fn la_gpu_de_esta_maquina() {
        let Some(n) = nodo(Path::new("/")) else { return };
        let Some(v) = decodifica(&n) else { return };
        let o = std::process::Command::new("vainfo").args(["--display", "drm", "--device"]).arg(&n).output();
        let Ok(o) = o else { return };
        let t = String::from_utf8_lossy(&o.stdout);
        for (perfil, c) in [("VAProfileH264High", "h264"), ("VAProfileVP9Profile0", "vp9"), ("VAProfileAV1Profile0", "av1"), ("VAProfileHEVCMain ", "hevc")] {
            let tiene = t.lines().any(|l| l.contains(perfil) && l.contains("VAEntrypointVLD"));
            assert_eq!(v.contains(&c), tiene, "{c}: vainfo dice {tiene}, libva directo {:?}", v);
        }
    }
}
