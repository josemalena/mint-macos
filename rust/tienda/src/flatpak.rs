//! libflatpak por una FFI mínima, contra la libflatpak.so.0 que trae Mint (no hay
//! libflatpak-dev). Solo lo que hace falta: la instalación, la transacción
//! (instalar, quitar, actualizar, correr), su progreso, lo que tiene actualización,
//! el tamaño de un ref y refrescar el appstream de un remote. Cada símbolo está
//! comprobado con `nm -D` contra la .so real, y las pruebas lo ejercitan con un repo
//! de juguete (prueba-flatpak.sh).
//!
//! Los valores de los enums y las firmas de las señales salen de la typelib de
//! Flatpak 1.14 (gi.repository.Flatpak): TransactionOperationType INSTALL=0,
//! UPDATE=1, INSTALL_BUNDLE=2, UNINSTALL=3; FlatpakError NOT_AUTHORIZED=24,
//! OUT_OF_SPACE=18, ABORTED=4.

#![allow(non_camel_case_types)]

use std::ffi::{c_char, c_int, c_uint, c_void, CStr, CString};
use std::path::Path;
use std::ptr;

type gboolean = c_int;

#[repr(C)]
struct GError {
    domain: u32,
    code: c_int,
    message: *mut c_char,
}

#[repr(C)]
struct GPtrArray {
    pdata: *mut *mut c_void,
    len: c_uint,
}

#[repr(C)]
struct GList {
    data: *mut c_void,
    next: *mut GList,
    prev: *mut GList,
}

#[link(name = "libflatpak.so.0", kind = "dylib", modifiers = "+verbatim")]
extern "C" {
    fn flatpak_installation_new_user(c: *mut c_void, e: *mut *mut GError) -> *mut c_void;
    fn flatpak_installation_new_system(c: *mut c_void, e: *mut *mut GError) -> *mut c_void;
    #[cfg_attr(not(test), allow(dead_code))]
    fn flatpak_installation_new_for_path(f: *mut c_void, user: gboolean, c: *mut c_void, e: *mut *mut GError) -> *mut c_void;
    fn flatpak_transaction_new_for_installation(i: *mut c_void, c: *mut c_void, e: *mut *mut GError) -> *mut c_void;
    fn flatpak_transaction_add_install(t: *mut c_void, remote: *const c_char, r: *const c_char, sub: *const *const c_char, e: *mut *mut GError) -> gboolean;
    fn flatpak_transaction_add_uninstall(t: *mut c_void, r: *const c_char, e: *mut *mut GError) -> gboolean;
    fn flatpak_transaction_add_update(t: *mut c_void, r: *const c_char, sub: *const *const c_char, commit: *const c_char, e: *mut *mut GError) -> gboolean;
    fn flatpak_transaction_set_no_interaction(t: *mut c_void, no: gboolean);
    fn flatpak_transaction_run(t: *mut c_void, c: *mut c_void, e: *mut *mut GError) -> gboolean;
    fn flatpak_transaction_get_operations(t: *mut c_void) -> *mut GList;
    fn flatpak_transaction_operation_get_download_size(op: *mut c_void) -> u64;
    fn flatpak_transaction_operation_get_operation_type(op: *mut c_void) -> c_int;
    fn flatpak_transaction_operation_get_ref(op: *mut c_void) -> *const c_char;
    fn flatpak_transaction_progress_get_progress(p: *mut c_void) -> c_int;
    fn flatpak_transaction_progress_get_status(p: *mut c_void) -> *mut c_char;
    fn flatpak_transaction_progress_get_bytes_transferred(p: *mut c_void) -> u64;
    fn flatpak_transaction_progress_set_update_frequency(p: *mut c_void, ms: c_uint);
    fn flatpak_installation_list_installed_refs_for_update(i: *mut c_void, c: *mut c_void, e: *mut *mut GError) -> *mut GPtrArray;
    fn flatpak_ref_format_ref(r: *mut c_void) -> *mut c_char;
    fn flatpak_installed_ref_get_origin(r: *mut c_void) -> *const c_char;
    fn flatpak_installation_fetch_remote_ref_sync(i: *mut c_void, remote: *const c_char, kind: c_int, name: *const c_char, arch: *const c_char, branch: *const c_char, c: *mut c_void, e: *mut *mut GError) -> *mut c_void;
    fn flatpak_remote_ref_get_download_size(r: *mut c_void) -> u64;
    fn flatpak_remote_ref_get_installed_size(r: *mut c_void) -> u64;
    fn flatpak_installation_update_appstream_sync(i: *mut c_void, remote: *const c_char, arch: *const c_char, changed: *mut gboolean, c: *mut c_void, e: *mut *mut GError) -> gboolean;
}

#[link(name = "gobject-2.0")]
extern "C" {
    fn g_signal_connect_data(inst: *mut c_void, sig: *const c_char, cb: *const c_void, data: *mut c_void, destroy: *const c_void, flags: c_int) -> std::ffi::c_ulong;
    fn g_object_unref(o: *mut c_void);
}

#[link(name = "glib-2.0")]
extern "C" {
    fn g_error_free(e: *mut GError);
    fn g_ptr_array_unref(a: *mut GPtrArray);
    fn g_list_free_full(l: *mut GList, free: unsafe extern "C" fn(*mut c_void));
    fn g_free(p: *mut c_void);
    fn g_quark_to_string(q: u32) -> *const c_char;
    fn g_main_context_new() -> *mut c_void;
    fn g_main_context_push_thread_default(c: *mut c_void);
    fn g_main_context_pop_thread_default(c: *mut c_void);
    fn g_main_context_unref(c: *mut c_void);
}

#[link(name = "gio-2.0")]
extern "C" {
    fn g_cancellable_new() -> *mut c_void;
    fn g_cancellable_cancel(c: *mut c_void);
    #[cfg_attr(not(test), allow(dead_code))]
    fn g_file_new_for_path(p: *const c_char) -> *mut c_void;
}

/// Un error de GLib ya leído: dominio, código y mensaje.
#[derive(Debug, Clone, PartialEq)]
pub struct Fallo {
    pub dominio: String,
    pub codigo: i32,
    pub mensaje: String,
}

impl Fallo {
    fn propio(m: &str) -> Fallo {
        Fallo { dominio: "mint-macos-tienda".into(), codigo: 0, mensaje: m.into() }
    }

    /// El `codigo` de la señal Terminado (DBUS.md).
    pub fn clase(&self) -> &'static str {
        match (self.dominio.as_str(), self.codigo) {
            ("g-io-error-quark", 19) | ("flatpak-error-quark", 4) => "cancelado",
            ("flatpak-error-quark", 24) => "sin-autorizacion",
            ("flatpak-error-quark", 18) => "sin-espacio",
            ("g-io-error-quark", 12) => "sin-espacio",
            _ => {
                let m = self.mensaje.to_lowercase();
                if m.contains("not authorized") || m.contains("authorization") {
                    "sin-autorizacion"
                } else if m.contains("could not resolve") || m.contains("couldn't resolve") || m.contains("network") || m.contains("timeout was reached") {
                    "sin-red"
                } else if m.contains("no space") {
                    "sin-espacio"
                } else {
                    "fallo"
                }
            }
        }
    }
}

unsafe fn tomar_error(e: *mut GError) -> Fallo {
    if e.is_null() {
        return Fallo::propio("error sin detalle");
    }
    let q = g_quark_to_string((*e).domain);
    let f = Fallo {
        dominio: if q.is_null() { String::new() } else { CStr::from_ptr(q).to_string_lossy().into_owned() },
        codigo: (*e).code,
        mensaje: if (*e).message.is_null() { String::new() } else { CStr::from_ptr((*e).message).to_string_lossy().into_owned() },
    };
    g_error_free(e);
    f
}

fn cadena(s: &str) -> Result<CString, Fallo> {
    CString::new(s).map_err(|_| Fallo::propio("cadena con un cero"))
}

unsafe fn tomar_cadena(p: *mut c_char) -> String {
    if p.is_null() {
        return String::new();
    }
    let s = CStr::from_ptr(p).to_string_lossy().into_owned();
    g_free(p as *mut c_void);
    s
}

/// Una FlatpakInstallation. Se usa siempre desde el hilo que la creó o con el
/// cerrojo del motor: libflatpak no dice que sea segura entre hilos.
pub struct Instalacion(*mut c_void);
unsafe impl Send for Instalacion {}

impl Drop for Instalacion {
    fn drop(&mut self) {
        unsafe { g_object_unref(self.0) }
    }
}

impl Instalacion {
    pub fn abrir(cual: &str) -> Result<Instalacion, Fallo> {
        let mut e = ptr::null_mut();
        let i = unsafe {
            match cual {
                "user" => flatpak_installation_new_user(ptr::null_mut(), &mut e),
                "system" => flatpak_installation_new_system(ptr::null_mut(), &mut e),
                _ => return Err(Fallo::propio("instalación desconocida")),
            }
        };
        if i.is_null() {
            return Err(unsafe { tomar_error(e) });
        }
        Ok(Instalacion(i))
    }

    /// Una instalación en otra carpeta, como si fuera de usuario (las pruebas).
    #[cfg_attr(not(test), allow(dead_code))]
    pub fn en(dir: &Path) -> Result<Instalacion, Fallo> {
        let p = cadena(&dir.to_string_lossy())?;
        let mut e = ptr::null_mut();
        let i = unsafe {
            let f = g_file_new_for_path(p.as_ptr());
            let i = flatpak_installation_new_for_path(f, 1, ptr::null_mut(), &mut e);
            g_object_unref(f);
            i
        };
        if i.is_null() {
            return Err(unsafe { tomar_error(e) });
        }
        Ok(Instalacion(i))
    }

    /// Los refs instalados que tienen actualización: (ref, remote).
    pub fn actualizables(&self) -> Result<Vec<(String, String)>, Fallo> {
        let mut e = ptr::null_mut();
        let a = unsafe { flatpak_installation_list_installed_refs_for_update(self.0, ptr::null_mut(), &mut e) };
        if a.is_null() {
            return Err(unsafe { tomar_error(e) });
        }
        let mut out = Vec::new();
        unsafe {
            for k in 0..(*a).len as usize {
                let r = *(*a).pdata.add(k);
                let o = flatpak_installed_ref_get_origin(r);
                out.push((tomar_cadena(flatpak_ref_format_ref(r)), if o.is_null() { String::new() } else { CStr::from_ptr(o).to_string_lossy().into_owned() }));
            }
            g_ptr_array_unref(a);
        }
        Ok(out)
    }

    /// (descarga, instalada) en bytes de un ref del remote, del resumen que ya está en caché.
    pub fn tamanos(&self, remote: &str, referencia: &str) -> Result<(u64, u64), Fallo> {
        let partes: Vec<&str> = referencia.split('/').collect();
        let [tipo, nombre, arco, rama] = partes.as_slice() else { return Err(Fallo::propio("ref sin cuatro partes")) };
        let kind = if *tipo == "runtime" { 1 } else { 0 };
        let (r, n, a, b) = (cadena(remote)?, cadena(nombre)?, cadena(arco)?, cadena(rama)?);
        let mut e = ptr::null_mut();
        let rr = unsafe { flatpak_installation_fetch_remote_ref_sync(self.0, r.as_ptr(), kind, n.as_ptr(), a.as_ptr(), b.as_ptr(), ptr::null_mut(), &mut e) };
        if rr.is_null() {
            return Err(unsafe { tomar_error(e) });
        }
        let t = unsafe { (flatpak_remote_ref_get_download_size(rr), flatpak_remote_ref_get_installed_size(rr)) };
        unsafe { g_object_unref(rr) };
        Ok(t)
    }

    /// Baja el appstream nuevo de un remote. true si cambió.
    pub fn refrescar_appstream(&self, remote: &str) -> Result<bool, Fallo> {
        let r = cadena(remote)?;
        let mut cambio: gboolean = 0;
        let mut e = ptr::null_mut();
        let ok = unsafe { flatpak_installation_update_appstream_sync(self.0, r.as_ptr(), ptr::null(), &mut cambio, ptr::null_mut(), &mut e) };
        if ok == 0 {
            return Err(unsafe { tomar_error(e) });
        }
        Ok(cambio != 0)
    }
}

/// Para cancelar una transacción desde otro hilo.
pub struct Cancelador(*mut c_void);
unsafe impl Send for Cancelador {}
unsafe impl Sync for Cancelador {}

impl Cancelador {
    pub fn nuevo() -> Cancelador {
        Cancelador(unsafe { g_cancellable_new() })
    }
    pub fn cancelar(&self) {
        unsafe { g_cancellable_cancel(self.0) }
    }
}

impl Drop for Cancelador {
    fn drop(&mut self) {
        unsafe { g_object_unref(self.0) }
    }
}

#[derive(Debug, Clone)]
pub enum Operacion {
    Instalar { remote: String, referencia: String },
    Quitar { referencia: String },
    Actualizar { referencia: String },
}

#[derive(Debug, Clone, PartialEq)]
pub struct Progreso {
    /// De toda la transacción, 0-100.
    pub porcentaje: u32,
    /// «instalando», «quitando», «descargando»…
    pub etapa: &'static str,
    pub bytes: u64,
    pub total: u64,
    /// El estado que da libflatpak («Installing org.gimp.GIMP»), para el detalle.
    pub estado: String,
}

struct Estado<'a> {
    avisar: &'a mut dyn FnMut(Progreso),
    total: u64,
    hechos: u64,
    /// Lo bajado por la operación en curso y lo que pesa.
    actual_bytes: u64,
    actual_total: u64,
    actual_tipo: c_int,
    ops: u32,
    ops_hechas: u32,
}

impl Estado<'_> {
    fn emitir(&mut self, pct_op: c_int, estado: String) {
        let pct_op = pct_op.clamp(0, 100) as u64;
        let porcentaje = if self.total > 0 {
            ((self.hechos + self.actual_bytes).min(self.total) * 100 / self.total) as u32
        } else if self.ops > 0 {
            ((self.ops_hechas as u64 * 100 + pct_op) / self.ops as u64) as u32
        } else {
            pct_op as u32
        };
        let etapa = match self.actual_tipo {
            3 => "quitando",
            _ if self.actual_bytes < self.actual_total => "descargando",
            1 => "actualizando",
            _ => "instalando",
        };
        (self.avisar)(Progreso { porcentaje: porcentaje.min(100), etapa, bytes: self.hechos + self.actual_bytes, total: self.total, estado });
    }
}

unsafe extern "C" fn al_listo(t: *mut c_void, data: *mut c_void) -> gboolean {
    let st = &mut *(data as *mut Estado);
    let ops = flatpak_transaction_get_operations(t);
    let mut l = ops;
    while !l.is_null() {
        st.total += flatpak_transaction_operation_get_download_size((*l).data);
        st.ops += 1;
        l = (*l).next;
    }
    g_list_free_full(ops, g_object_unref_c);
    1
}

unsafe extern "C" fn g_object_unref_c(p: *mut c_void) {
    g_object_unref(p)
}

unsafe extern "C" fn al_cambiar(p: *mut c_void, data: *mut c_void) {
    let st = &mut *(data as *mut Estado);
    st.actual_bytes = flatpak_transaction_progress_get_bytes_transferred(p);
    let pct = flatpak_transaction_progress_get_progress(p);
    let estado = tomar_cadena(flatpak_transaction_progress_get_status(p));
    st.emitir(pct, estado);
}

unsafe extern "C" fn al_operar(_t: *mut c_void, op: *mut c_void, p: *mut c_void, data: *mut c_void) {
    let st = &mut *(data as *mut Estado);
    st.actual_bytes = 0;
    st.actual_total = flatpak_transaction_operation_get_download_size(op);
    st.actual_tipo = flatpak_transaction_operation_get_operation_type(op);
    flatpak_transaction_progress_set_update_frequency(p, 150);
    g_signal_connect_data(p, c"changed".as_ptr(), al_cambiar as *const c_void, data, ptr::null(), 0);
    let r = flatpak_transaction_operation_get_ref(op);
    let r = if r.is_null() { String::new() } else { CStr::from_ptr(r).to_string_lossy().into_owned() };
    st.emitir(0, r);
}

unsafe extern "C" fn al_terminar_op(_t: *mut c_void, _op: *mut c_void, _commit: *const c_char, _res: c_int, data: *mut c_void) {
    let st = &mut *(data as *mut Estado);
    st.hechos += st.actual_total;
    st.actual_bytes = 0;
    st.actual_total = 0;
    st.ops_hechas += 1;
    st.emitir(0, String::new());
}

/// Corre una transacción entera en este hilo, con su propio contexto de GLib (las
/// señales de progreso salen de ahí, no de un bucle ajeno).
pub fn correr(inst: &Instalacion, ops: &[Operacion], cancelar: &Cancelador, avisar: &mut dyn FnMut(Progreso)) -> Result<(), Fallo> {
    unsafe {
        let ctx = g_main_context_new();
        g_main_context_push_thread_default(ctx);
        let r = correr_en(inst, ops, cancelar, avisar);
        g_main_context_pop_thread_default(ctx);
        g_main_context_unref(ctx);
        r
    }
}

unsafe fn correr_en(inst: &Instalacion, ops: &[Operacion], cancelar: &Cancelador, avisar: &mut dyn FnMut(Progreso)) -> Result<(), Fallo> {
    let mut e = ptr::null_mut();
    let t = flatpak_transaction_new_for_installation(inst.0, ptr::null_mut(), &mut e);
    if t.is_null() {
        return Err(tomar_error(e));
    }
    struct Soltar(*mut c_void);
    impl Drop for Soltar {
        fn drop(&mut self) {
            unsafe { g_object_unref(self.0) }
        }
    }
    let _t = Soltar(t);
    flatpak_transaction_set_no_interaction(t, 1);
    for op in ops {
        let ok = match op {
            Operacion::Instalar { remote, referencia } => {
                let (r, f) = (cadena(remote)?, cadena(referencia)?);
                flatpak_transaction_add_install(t, r.as_ptr(), f.as_ptr(), ptr::null(), &mut e)
            }
            Operacion::Quitar { referencia } => {
                let f = cadena(referencia)?;
                flatpak_transaction_add_uninstall(t, f.as_ptr(), &mut e)
            }
            Operacion::Actualizar { referencia } => {
                let f = cadena(referencia)?;
                flatpak_transaction_add_update(t, f.as_ptr(), ptr::null(), ptr::null(), &mut e)
            }
        };
        if ok == 0 {
            return Err(tomar_error(e));
        }
    }
    let mut st = Estado { avisar, total: 0, hechos: 0, actual_bytes: 0, actual_total: 0, actual_tipo: 0, ops: 0, ops_hechas: 0 };
    let data = &mut st as *mut Estado as *mut c_void;
    g_signal_connect_data(t, c"ready".as_ptr(), al_listo as *const c_void, data, ptr::null(), 0);
    g_signal_connect_data(t, c"new-operation".as_ptr(), al_operar as *const c_void, data, ptr::null(), 0);
    g_signal_connect_data(t, c"operation-done".as_ptr(), al_terminar_op as *const c_void, data, ptr::null(), 0);
    let ok = flatpak_transaction_run(t, cancelar.0, &mut e);
    if ok == 0 {
        return Err(tomar_error(e));
    }
    st.ops_hechas = st.ops;
    st.hechos = st.total;
    st.emitir(100, String::new());
    Ok(())
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn clases_de_fallo() {
        let f = |d: &str, c: i32, m: &str| Fallo { dominio: d.into(), codigo: c, mensaje: m.into() }.clase();
        assert_eq!(f("g-io-error-quark", 19, "Operation was cancelled"), "cancelado");
        assert_eq!(f("flatpak-error-quark", 24, ""), "sin-autorizacion");
        assert_eq!(f("flatpak-error-quark", 18, ""), "sin-espacio");
        assert_eq!(f("g-io-error-quark", 0, "While fetching: Could not resolve hostname"), "sin-red");
        assert_eq!(f("flatpak-error-quark", 21, "Nothing matches"), "fallo");
    }

    /// Una transacción de verdad contra un repo de juguete (lo arma prueba-flatpak.sh,
    /// que pone TIENDA_FLATPAK_PRUEBA): instalar con su runtime, el progreso, el
    /// tamaño, una actualización, cancelar y quitar. Sin esa variable no corre.
    #[test]
    #[ignore]
    fn transaccion_de_juguete() {
        let Ok(t) = std::env::var("TIENDA_FLATPAK_PRUEBA") else { return };
        let t = std::path::PathBuf::from(t);
        let inst = Instalacion::en(&t.join("inst")).unwrap();
        let referencia = "app/org.mintmacos.Juguete/x86_64/stable".to_string();
        let instalado = t.join("inst/app/org.mintmacos.Juguete/x86_64/stable/active");

        let (d, i) = inst.tamanos("juguete", &referencia).unwrap();
        assert!(d > 0 && i >= 3 << 20, "tamaños: descarga {d}, instalada {i}");

        let c = Cancelador::nuevo();
        let mut v: Vec<Progreso> = Vec::new();
        correr(&inst, &[Operacion::Instalar { remote: "juguete".into(), referencia: referencia.clone() }], &c, &mut |p| v.push(p)).unwrap();
        assert!(instalado.exists(), "no quedó instalada");
        assert!(t.join("inst/runtime/org.mintmacos.Juguete.Platform/x86_64/1/active").exists(), "no trajo el runtime");
        assert_eq!(v.last().map(|p| p.porcentaje), Some(100));
        assert!(v.windows(2).all(|w| w[0].porcentaje <= w[1].porcentaje), "el porcentaje retrocedió: {:?}", v.iter().map(|p| p.porcentaje).collect::<Vec<_>>());
        assert!(v.iter().any(|p| p.total > 0), "sin total de bytes");

        // Una versión nueva en el repo: tiene que salir como actualizable.
        std::fs::write(t.join("app/files/version"), "2").unwrap();
        let ok = std::process::Command::new("flatpak").arg("build-export").stdout(std::process::Stdio::null()).arg(t.join("repo")).arg(t.join("app")).arg("stable").status().unwrap();
        assert!(ok.success());
        let act = inst.actualizables().unwrap();
        assert_eq!(act, [(referencia.clone(), "juguete".to_string())]);
        correr(&inst, &[Operacion::Actualizar { referencia: referencia.clone() }], &c, &mut |_| {}).unwrap();
        assert!(inst.actualizables().unwrap().is_empty());
        assert_eq!(std::fs::read_to_string(instalado.join("files/version")).unwrap(), "2");

        // Cancelada antes de empezar: no quita nada y dice «cancelado».
        let cc = Cancelador::nuevo();
        cc.cancelar();
        let e = correr(&inst, &[Operacion::Quitar { referencia: referencia.clone() }], &cc, &mut |_| {}).unwrap_err();
        assert_eq!(e.clase(), "cancelado", "{e:?}");
        assert!(instalado.exists());

        correr(&inst, &[Operacion::Quitar { referencia }], &c, &mut |_| {}).unwrap();
        assert!(!instalado.exists(), "no se quitó");
    }

    /// La FFI contra la .so de verdad: abrir una instalación vacía en una carpeta
    /// aparte y pedirle lo que tiene para actualizar (nada).
    #[test]
    fn la_so_responde() {
        let d = std::env::temp_dir().join(format!("tienda-flatpak-{}", std::process::id()));
        std::fs::create_dir_all(&d).unwrap();
        let i = Instalacion::en(&d).expect("instalación en una carpeta");
        assert_eq!(i.actualizables().unwrap(), Vec::<(String, String)>::new());
        let e = i.tamanos("no-existe", "app/x.Y/x86_64/stable").unwrap_err();
        assert!(!e.mensaje.is_empty());
        std::fs::remove_dir_all(&d).unwrap();
    }
}
