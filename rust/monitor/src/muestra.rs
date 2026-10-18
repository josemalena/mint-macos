//! Una muestra: lo leído de /proc ahora, comparado con la anterior para sacar los
//! porcentajes y las tasas, y el historial de 10 minutos para las gráficas.

use std::collections::{HashMap, VecDeque};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::proc::{self, Cpu, Proceso};

pub const HISTORIAL: Duration = Duration::from_secs(600);

/// Lo que se calcula de un proceso entre dos muestras.
#[derive(Debug, Clone, Default)]
pub struct Fila {
    pub p: Proceso,
    /// % de un núcleo (100 = uno entero, como la Mac).
    pub cpu: Option<f64>,
    pub despertares: Option<f64>,
}

#[derive(Debug, Clone, Default)]
pub struct Sistema {
    pub cpu: Cpu,
    pub mem: HashMap<String, u64>,
    pub red: (u64, u64, u64, u64),
    pub disco: (u64, u64, u64, u64),
    pub presion: Option<f64>,
}

pub struct Muestreo {
    raiz: PathBuf,
    mi_uid: u32,
    anterior: Option<(f64, Sistema, HashMap<i32, Proceso>)>,
    pub filas: Vec<Fila>,
    pub sistema: Sistema,
    pub cuando_ms: i64,
    /// serie → (unix ms, valor).
    pub historial: HashMap<String, VecDeque<(i64, f64)>>,
    /// % de usuario, de sistema y ocioso de la última muestra.
    pub partes_cpu: Option<(f64, f64, f64)>,
}

fn ahora_s() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0)
}

/// avg10 de some en /proc/pressure/memory: el % del tiempo con procesos esperando memoria.
fn leer_presion(raiz: &Path) -> Option<f64> {
    let t = fs::read_to_string(raiz.join("proc/pressure/memory")).ok()?;
    t.lines().find(|l| l.starts_with("some"))?.split_whitespace().find_map(|c| c.strip_prefix("avg10=")).and_then(|v| v.parse().ok())
}

impl Muestreo {
    pub fn nuevo(raiz: &Path) -> Muestreo {
        Muestreo { raiz: raiz.to_path_buf(), mi_uid: proc::mi_uid(), anterior: None, filas: Vec::new(), sistema: Sistema::default(), cuando_ms: 0, historial: HashMap::new(), partes_cpu: None }
    }

    fn leer_sistema(&self) -> Sistema {
        let r = &self.raiz;
        Sistema {
            cpu: proc::leer_cpu(&fs::read_to_string(r.join("proc/stat")).unwrap_or_default()),
            mem: proc::leer_meminfo(&fs::read_to_string(r.join("proc/meminfo")).unwrap_or_default()),
            red: proc::leer_red(&fs::read_to_string(r.join("proc/net/dev")).unwrap_or_default()),
            disco: proc::leer_disco(&fs::read_to_string(r.join("proc/diskstats")).unwrap_or_default(), &r.join("sys/block")),
            presion: leer_presion(r),
        }
    }

    fn poner(&mut self, serie: &str, ms: i64, v: f64) {
        let h = self.historial.entry(serie.to_string()).or_default();
        h.push_back((ms, v));
        let limite = ms - HISTORIAL.as_millis() as i64;
        while h.front().map(|(t, _)| *t < limite).unwrap_or(false) {
            h.pop_front();
        }
    }

    pub fn muestrear(&mut self) {
        let t = ahora_s();
        let ms = (t * 1000.0) as i64;
        let sis = self.leer_sistema();
        let procs = proc::procesos(&self.raiz, self.mi_uid);
        let mut filas = Vec::with_capacity(procs.len());
        let anterior = self.anterior.take();
        if let Some((t0, s0, p0)) = &anterior {
            let dt = (t - t0).max(0.001);
            for p in &procs {
                let antes = p0.get(&p.pid);
                // Mismo pid y comm: el mismo proceso (un pid reciclado empieza de cero).
                let antes = antes.filter(|a| a.comm == p.comm);
                let cpu = antes.map(|a| (p.ticks.saturating_sub(a.ticks)) as f64 / proc::USER_HZ as f64 / dt * 100.0);
                let desp = match (antes.and_then(|a| a.voluntarios), p.voluntarios) {
                    (Some(a), Some(b)) => Some(b.saturating_sub(a) as f64 / dt),
                    _ => None,
                };
                filas.push(Fila { p: p.clone(), cpu, despertares: desp });
            }
            // Las series de las gráficas.
            let pct = |a: (u64, u64), b: (u64, u64)| {
                let total = b.0.saturating_sub(a.0) as f64;
                if total > 0.0 { 100.0 * (1.0 - b.1.saturating_sub(a.1) as f64 / total) } else { 0.0 }
            };
            let total = pct(s0.cpu.total, sis.cpu.total);
            self.poner("cpu", ms, total);
            for (i, (a, b)) in s0.cpu.nucleos.iter().zip(&sis.cpu.nucleos).enumerate() {
                self.poner(&format!("cpu.{i}"), ms, pct(*a, *b));
            }
            let d = sis.cpu.total.0.saturating_sub(s0.cpu.total.0) as f64;
            if d > 0.0 {
                let (u0, k0, o0) = s0.cpu.partes;
                let (u1, k1, o1) = sis.cpu.partes;
                self.partes_cpu = Some((100.0 * u1.saturating_sub(u0) as f64 / d, 100.0 * k1.saturating_sub(k0) as f64 / d, 100.0 * o1.saturating_sub(o0) as f64 / d));
            }
            if let Some((u, k, _)) = self.partes_cpu {
                self.poner("cpu.usuario", ms, u);
                self.poner("cpu.sistema", ms, k);
            }
            let tasa = |a: u64, b: u64| b.saturating_sub(a) as f64 / dt;
            self.poner("red.rx", ms, tasa(s0.red.0, sis.red.0));
            self.poner("red.tx", ms, tasa(s0.red.1, sis.red.1));
            self.poner("red.paquetes_rx", ms, tasa(s0.red.2, sis.red.2));
            self.poner("red.paquetes_tx", ms, tasa(s0.red.3, sis.red.3));
            self.poner("disco.leido", ms, tasa(s0.disco.0, sis.disco.0));
            self.poner("disco.escrito", ms, tasa(s0.disco.1, sis.disco.1));
            self.poner("disco.lecturas", ms, tasa(s0.disco.2, sis.disco.2));
            self.poner("disco.escrituras", ms, tasa(s0.disco.3, sis.disco.3));
        } else {
            filas.extend(procs.iter().map(|p| Fila { p: p.clone(), cpu: None, despertares: None }));
        }
        let m = &sis.mem;
        let g = |k: &str| m.get(k).copied().unwrap_or(0);
        let usada = g("MemTotal").saturating_sub(g("MemAvailable"));
        self.poner("mem.usada", ms, usada as f64);
        self.poner("mem.cache", ms, (g("Cached") + g("Buffers")) as f64);
        self.poner("swap.usada", ms, g("SwapTotal").saturating_sub(g("SwapFree")) as f64);
        if let Some(p) = sis.presion {
            self.poner("mem.presion", ms, p);
        }
        self.anterior = Some((t, sis.clone(), procs.into_iter().map(|p| (p.pid, p)).collect()));
        self.filas = filas;
        self.sistema = sis;
        self.cuando_ms = ms;
    }

    /// (unix ms, valor) de una serie en los últimos `segundos`.
    pub fn serie(&self, nombre: &str, segundos: u32) -> Vec<(i64, f64)> {
        let desde = self.cuando_ms - segundos as i64 * 1000;
        self.historial.get(nombre).map(|h| h.iter().filter(|(t, _)| *t >= desde).copied().collect()).unwrap_or_default()
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn dos_muestras_dan_porcentajes_y_series() {
        let mut m = Muestreo::nuevo(Path::new("/"));
        m.muestrear();
        assert!(m.filas.iter().all(|f| f.cpu.is_none()), "la primera muestra no tiene con qué comparar");
        // Algo de trabajo para que haya ticks.
        let mut x = 0u64;
        for i in 0..20_000_000u64 { x = x.wrapping_add(i * i); }
        std::hint::black_box(x);
        std::thread::sleep(Duration::from_millis(300));
        m.muestrear();
        let yo = std::process::id() as i32;
        let f = m.filas.iter().find(|f| f.p.pid == yo).unwrap();
        assert!(f.cpu.is_some() && f.despertares.is_some());
        assert_eq!(m.serie("cpu", 60).len(), 1);
        assert!(m.serie("cpu.0", 60).len() == 1 && m.serie("mem.usada", 60).len() == 2);
    }
}
