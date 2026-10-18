//! mint-macos-monitor: los datos de Activity Monitor (org.mintmacos.Monitor1, ver
//! DBUS.md), sin ventana y sin root. Lo arranca la activación por D-Bus; mide solo
//! mientras haya un cliente suscrito, y se va solo a los 2 minutos sin clientes.
//!
//! MONITOR_RAIZ cambia la raíz de /proc, /sys y /etc (solo las pruebas).

mod apps;
mod muestra;
mod proc;

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

use zbus::blocking::{Connection, MessageIterator};
use zbus::message::{Header, Type as TipoMensaje};
use zbus::zvariant::{OwnedValue, Value};
use zbus::{interface, MatchRule};

const NOMBRE: &str = "org.mintmacos.Monitor1";
const RUTA: &str = "/org/mintmacos/Monitor1";
const SIN_CLIENTES: Duration = Duration::from_secs(120);

type Dict = HashMap<String, OwnedValue>;

fn ov<'a>(v: impl Into<Value<'a>>) -> OwnedValue {
    v.into().try_to_owned().expect("valor D-Bus sin descriptores")
}

/// (clave, fuente, motivo) de cada columna: de dónde sale, o por qué no hay.
const COLUMNAS: &[(&str, &str, &str)] = &[
    ("pid", "/proc/<pid>/stat", ""),
    ("ppid", "/proc/<pid>/stat", ""),
    ("nombre", ".desktop de la app, o comm", ""),
    ("icono", ".desktop de la app", ""),
    ("usuario", "/proc/<pid>/status + /etc/passwd", ""),
    ("cpu", "/proc/<pid>/stat entre dos muestras", ""),
    ("tiempo_cpu", "/proc/<pid>/stat", ""),
    ("hilos", "/proc/<pid>/status", ""),
    ("despertares", "/proc/<pid>/status voluntary_ctxt_switches", "solo procesos propios"),
    ("memoria", "/proc/<pid>/status RssAnon", ""),
    ("memoria_residente", "/proc/<pid>/status VmRSS", ""),
    ("comprimida", "/proc/<pid>/status VmSwap", ""),
    ("leido", "/proc/<pid>/io read_bytes", "solo procesos propios"),
    ("escrito", "/proc/<pid>/io write_bytes", "solo procesos propios"),
    ("tipo", "clase ELF de /proc/<pid>/exe", "solo procesos propios"),
    ("origen", "/proc/<pid>/cgroup (app-flatpak-…)", ""),
    ("puertos", "", "sin fuente: Linux no tiene puertos de Mach"),
    ("energia", "", "sin fuente"),
    ("energia_promedio", "", "sin fuente"),
    ("app_nap", "", "sin fuente: Linux no tiene App Nap"),
    ("gpu_alto_rendimiento", "", "sin fuente"),
    ("red_enviada", "", "sin fuente sin root"),
    ("red_recibida", "", "sin fuente sin root"),
    ("paquetes_enviados", "", "sin fuente sin root"),
    ("paquetes_recibidos", "", "sin fuente sin root"),
];

struct Motor {
    muestreo: Mutex<muestra::Muestreo>,
    clientes: Mutex<HashMap<String, u32>>,
    hay_clientes: Condvar,
    sin_clientes_desde: Mutex<Option<Instant>>,
    apps: apps::Apps,
    usuarios: HashMap<u32, String>,
    mi_uid: u32,
    raiz: PathBuf,
    bus: Mutex<Option<Connection>>,
}

impl Motor {
    fn intervalo(&self) -> Option<Duration> {
        self.clientes.lock().unwrap().values().min().map(|ms| Duration::from_millis(*ms as u64))
    }

    fn emitir<B: serde::Serialize + zbus::zvariant::DynamicType>(&self, senal: &str, cuerpo: &B) {
        if let Some(c) = self.bus.lock().unwrap().as_ref() {
            let _ = c.emit_signal(None::<&str>, RUTA, NOMBRE, senal, cuerpo);
        }
    }

    fn soltar(&self, quien: &str) {
        let mut c = self.clientes.lock().unwrap();
        if c.remove(quien).is_some() && c.is_empty() {
            *self.sin_clientes_desde.lock().unwrap() = Some(Instant::now());
        }
    }

    /// El hilo que mide: espera dormido mientras no hay clientes.
    fn medir(self: Arc<Self>) {
        loop {
            let espera = {
                let mut c = self.clientes.lock().unwrap();
                while c.is_empty() {
                    c = self.hay_clientes.wait(c).unwrap();
                }
                Duration::from_millis(*c.values().min().unwrap_or(&2000) as u64)
            };
            let ms = {
                let mut m = self.muestreo.lock().unwrap();
                m.muestrear();
                m.cuando_ms
            };
            self.emitir("Muestreado", &(ms,));
            std::thread::sleep(espera);
        }
    }

    fn fila(&self, f: &muestra::Fila, cols: &[String]) -> Dict {
        let p = &f.p;
        let quiere = |k: &str| cols.is_empty() || cols.iter().any(|c| c == k);
        let app = self.apps.de(p.flatpak.as_deref(), &p.cmdline, &p.comm);
        let mut d = Dict::new();
        let mut poner = |k: &str, v: OwnedValue| {
            if quiere(k) {
                d.insert(k.to_string(), v);
            }
        };
        poner("pid", ov(p.pid));
        poner("ppid", ov(p.ppid));
        poner("nombre", ov(app.map(|a| a.nombre.clone()).unwrap_or_else(|| p.comm.clone())));
        if let Some(i) = app.and_then(|a| a.icono.clone()) {
            poner("icono", ov(i));
        }
        if let Some(u) = self.usuarios.get(&p.uid) {
            poner("usuario", ov(u.clone()));
        }
        if let Some(c) = f.cpu {
            poner("cpu", ov(c));
        }
        poner("tiempo_cpu", ov(p.ticks * 1000 / proc::USER_HZ));
        poner("hilos", ov(p.hilos));
        if let Some(w) = f.despertares {
            poner("despertares", ov(w.round() as u32));
        }
        if let Some(a) = p.anon {
            poner("memoria", ov(a));
        }
        if let Some(r) = p.rss {
            poner("memoria_residente", ov(r));
        }
        if let Some(s) = p.swap {
            poner("comprimida", ov(s));
        }
        if let Some(r) = p.leido {
            poner("leido", ov(r));
        }
        if let Some(w) = p.escrito {
            poner("escrito", ov(w));
        }
        if let Some(b) = p.bits {
            poner("tipo", ov(format!("{b} bit")));
        }
        poner("origen", ov(if p.flatpak.is_some() { "flatpak" } else { "nativo" }));
        d
    }

    /// Solo los procesos de José: de otro usuario no se mandan señales (en la Mac eso
    /// pide la clave de administrador).
    fn senal(self: &Arc<Self>, pid: i32, cual: &str) -> bool {
        let Some(p) = proc::leer_proceso(&self.raiz, pid, self.mi_uid) else { return false };
        if p.uid != self.mi_uid || pid <= 1 || pid == std::process::id() as i32 {
            return false;
        }
        let ok = std::process::Command::new("kill").args([cual, &pid.to_string()]).status().map(|s| s.success()).unwrap_or(false);
        if ok {
            let m = self.clone();
            std::thread::spawn(move || {
                for _ in 0..50 {
                    // Terminado: ya no está, o quedó zombi esperando a que su padre lo recoja.
                    let stat = std::fs::read_to_string(m.raiz.join("proc").join(pid.to_string()).join("stat")).unwrap_or_default();
                    let zombi = stat.rfind(')').map(|i| stat[i + 1..].trim_start().starts_with('Z')).unwrap_or(true);
                    if zombi {
                        m.emitir("ProcesoTermino", &(pid,));
                        return;
                    }
                    std::thread::sleep(Duration::from_millis(100));
                }
            });
        }
        ok
    }
}

/// La primera batería de /sys/class/power_supply: (capacidad %, estado).
fn bateria(raiz: &std::path::Path) -> Option<(u32, String)> {
    for e in std::fs::read_dir(raiz.join("sys/class/power_supply")).ok()?.flatten() {
        let d = e.path();
        if std::fs::read_to_string(d.join("type")).map(|t| t.trim() == "Battery").unwrap_or(false) {
            let c = std::fs::read_to_string(d.join("capacity")).ok()?.trim().parse().ok()?;
            let s = std::fs::read_to_string(d.join("status")).map(|t| t.trim().to_string()).unwrap_or_default();
            return Some((c, s));
        }
    }
    None
}

struct Servicio {
    m: Arc<Motor>,
}

#[interface(name = "org.mintmacos.Monitor1")]
impl Servicio {
    fn suscribir(&self, #[zbus(header)] h: Header<'_>, intervalo_ms: u32) {
        let Some(quien) = h.sender().map(|s| s.to_string()) else { return };
        self.m.clientes.lock().unwrap().insert(quien, intervalo_ms.clamp(1000, 5000));
        *self.m.sin_clientes_desde.lock().unwrap() = None;
        self.m.hay_clientes.notify_all();
    }

    fn soltar(&self, #[zbus(header)] h: Header<'_>) {
        if let Some(q) = h.sender() {
            self.m.soltar(q.as_str());
        }
    }

    fn procesos(&self, columnas: Vec<String>) -> Vec<Dict> {
        let m = self.m.muestreo.lock().unwrap();
        m.filas.iter().map(|f| self.m.fila(f, &columnas)).collect()
    }

    fn columnas(&self) -> Vec<(String, String, String)> {
        COLUMNAS.iter().map(|(a, b, c)| (a.to_string(), b.to_string(), c.to_string())).collect()
    }

    fn historial(&self, serie: String, segundos: u32) -> Vec<(i64, f64)> {
        self.m.muestreo.lock().unwrap().serie(&serie, segundos.min(600))
    }

    fn resumen(&self) -> Dict {
        let m = self.m.muestreo.lock().unwrap();
        let mut d = Dict::new();
        let g = |k: &str| m.sistema.mem.get(k).copied();
        if let Some((u, s, o)) = m.partes_cpu {
            d.insert("cpu_usuario".into(), ov(u));
            d.insert("cpu_sistema".into(), ov(s));
            d.insert("cpu_ocioso".into(), ov(o));
        }
        d.insert("procesos".into(), ov(m.filas.len() as u32));
        d.insert("hilos".into(), ov(m.filas.iter().map(|f| f.p.hilos).sum::<u32>()));
        d.insert("nucleos".into(), ov(m.sistema.cpu.nucleos.len() as u32));
        if let (Some(t), Some(a)) = (g("MemTotal"), g("MemAvailable")) {
            d.insert("mem_fisica".into(), ov(t));
            d.insert("mem_usada".into(), ov(t.saturating_sub(a)));
        }
        if let Some(c) = g("Cached") {
            d.insert("mem_cache".into(), ov(c + g("Buffers").unwrap_or(0)));
        }
        // Lo de la derecha del panel Memory, en su equivalente de Linux (DBUS.md).
        if let Some(a) = g("AnonPages") {
            d.insert("mem_app".into(), ov(a));
        }
        let wired: Vec<u64> = ["SUnreclaim", "KernelStack", "PageTables", "Unevictable"].iter().filter_map(|k| g(k)).collect();
        if wired.len() == 4 {
            d.insert("mem_wired".into(), ov(wired.iter().sum::<u64>()));
        }
        if let Some(z) = g("Zswap") {
            d.insert("mem_comprimida".into(), ov(z));
        }
        if let (Some(t), Some(f)) = (g("SwapTotal"), g("SwapFree")) {
            d.insert("swap_total".into(), ov(t));
            d.insert("swap_usada".into(), ov(t.saturating_sub(f)));
        }
        if let Some(p) = m.sistema.presion {
            d.insert("mem_presion".into(), ov(p));
        }
        d.insert("red_recibido".into(), ov(m.sistema.red.0));
        d.insert("red_enviado".into(), ov(m.sistema.red.1));
        d.insert("red_paquetes_recibidos".into(), ov(m.sistema.red.2));
        d.insert("red_paquetes_enviados".into(), ov(m.sistema.red.3));
        d.insert("disco_leido".into(), ov(m.sistema.disco.0));
        d.insert("disco_escrito".into(), ov(m.sistema.disco.1));
        d.insert("disco_lecturas".into(), ov(m.sistema.disco.2));
        d.insert("disco_escrituras".into(), ov(m.sistema.disco.3));
        // La batería de la pestaña Energy, si hay (una Mac mini no tiene).
        if let Some((carga, estado)) = bateria(&self.m.raiz) {
            d.insert("bateria_carga".into(), ov(carga));
            d.insert("bateria_estado".into(), ov(estado));
        }
        d.insert("cuando".into(), ov(m.cuando_ms));
        d
    }

    fn salir(&self, pid: i32) -> bool {
        self.m.senal(pid, "-TERM")
    }

    fn forzar_salida(&self, pid: i32) -> bool {
        self.m.senal(pid, "-KILL")
    }
}

fn main() {
    let raiz = std::env::var_os("MONITOR_RAIZ").map(PathBuf::from).unwrap_or_else(|| "/".into());
    let m = Arc::new(Motor {
        muestreo: Mutex::new(muestra::Muestreo::nuevo(&raiz)),
        clientes: Mutex::new(HashMap::new()),
        hay_clientes: Condvar::new(),
        sin_clientes_desde: Mutex::new(Some(Instant::now())),
        apps: apps::Apps::del_sistema(),
        usuarios: proc::usuarios(&raiz),
        mi_uid: proc::mi_uid(),
        raiz,
        bus: Mutex::new(None),
    });
    let c = zbus::blocking::connection::Builder::session()
        .and_then(|b| b.name(NOMBRE))
        .and_then(|b| b.serve_at(RUTA, Servicio { m: m.clone() }))
        .and_then(|b| b.build());
    let c = match c {
        Ok(c) => c,
        Err(e) => {
            eprintln!("mint-macos-monitor: {e}");
            std::process::exit(1);
        }
    };
    *m.bus.lock().unwrap() = Some(c.clone());
    // Un cliente que se va del bus sin Soltar cuenta como Soltar.
    let (m2, c2) = (m.clone(), c.clone());
    std::thread::spawn(move || {
        let regla = MatchRule::builder().msg_type(TipoMensaje::Signal).sender("org.freedesktop.DBus").and_then(|r| r.member("NameOwnerChanged")).map(|r| r.build());
        let Ok(it) = regla.and_then(|r| MessageIterator::for_match_rule(r, &c2, None)) else { return };
        for msg in it.flatten() {
            if let Ok((nombre, _, nuevo)) = msg.body().deserialize::<(String, String, String)>() {
                if nuevo.is_empty() {
                    m2.soltar(&nombre);
                }
            }
        }
    });
    let m3 = m.clone();
    std::thread::spawn(move || m3.medir());
    loop {
        std::thread::sleep(Duration::from_secs(10));
        let desde = *m.sin_clientes_desde.lock().unwrap();
        if desde.map(|d| d.elapsed() > SIN_CLIENTES).unwrap_or(false) && m.intervalo().is_none() {
            break;
        }
    }
}
