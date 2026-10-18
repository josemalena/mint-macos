//! Lo que se lee de /proc en cada muestra, sin root. Todo se lee una vez por muestra
//! para todos los clientes.
//!
//! Unidades: USER_HZ es 100 en Linux (lo fija el ABI para /proc, no depende del
//! núcleo), y las memorias de /proc/<pid>/status y smaps_rollup vienen en kB.

use std::collections::HashMap;
use std::fs;
use std::path::Path;

pub const USER_HZ: u64 = 100;

/// Un proceso en una muestra.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Proceso {
    pub pid: i32,
    pub ppid: i32,
    pub comm: String,
    pub cmdline: Vec<String>,
    pub uid: u32,
    /// utime + stime, en ticks de USER_HZ.
    pub ticks: u64,
    pub hilos: u32,
    pub rss: Option<u64>,
    /// RssAnon: la memoria propia del proceso (sin lo que comparte con archivos), lo más
    /// parecido a «Memory» de la Mac (su phys_footprint). Se lee de status para todos,
    /// también los de root.
    pub anon: Option<u64>,
    pub swap: Option<u64>,
    pub leido: Option<u64>,
    pub escrito: Option<u64>,
    pub voluntarios: Option<u64>,
    /// app-flatpak-<id>-… del cgroup: el id de Flatpak, si corre dentro de uno.
    pub flatpak: Option<String>,
    /// «64 bit» o «32 bit», de la clase ELF del ejecutable (solo procesos propios: el
    /// exe de otros pide ptrace).
    pub bits: Option<u8>,
}

fn kb(v: &str) -> Option<u64> {
    v.trim().trim_end_matches("kB").trim().parse::<u64>().ok().map(|n| n * 1024)
}

/// /proc/<pid>/stat: el comm va entre paréntesis y puede tener espacios y «)».
pub fn leer_stat(t: &str) -> Option<(String, i32, u64)> {
    let a = t.find('(')?;
    let b = t.rfind(')')?;
    let comm = t[a + 1..b].to_string();
    let resto: Vec<&str> = t[b + 1..].split_whitespace().collect();
    // Después del «)»: estado(0) ppid(1) … utime(11) stime(12).
    let ppid = resto.get(1)?.parse().ok()?;
    let ut: u64 = resto.get(11)?.parse().ok()?;
    let st: u64 = resto.get(12)?.parse().ok()?;
    Some((comm, ppid, ut + st))
}

pub fn leer_proceso(raiz: &Path, pid: i32, mi_uid: u32) -> Option<Proceso> {
    let d = raiz.join("proc").join(pid.to_string());
    let (comm, ppid, ticks) = leer_stat(&fs::read_to_string(d.join("stat")).ok()?)?;
    let mut p = Proceso { pid, ppid, comm, ticks, ..Default::default() };
    for l in fs::read_to_string(d.join("status")).ok()?.lines() {
        let Some((k, v)) = l.split_once(':') else { continue };
        match k {
            "Uid" => p.uid = v.split_whitespace().next().and_then(|x| x.parse().ok()).unwrap_or(u32::MAX),
            "Threads" => p.hilos = v.trim().parse().unwrap_or(0),
            "VmRSS" => p.rss = kb(v),
            "RssAnon" => p.anon = kb(v),
            "VmSwap" => p.swap = kb(v),
            "voluntary_ctxt_switches" => p.voluntarios = v.trim().parse().ok(),
            _ => {}
        }
    }
    p.cmdline = fs::read(d.join("cmdline")).map(|b| b.split(|c| *c == 0).filter(|s| !s.is_empty()).map(|s| String::from_utf8_lossy(s).into_owned()).collect()).unwrap_or_default();
    if p.uid == mi_uid {
        // Lo que solo se puede leer de los procesos propios. (smaps_rollup no: leerlo de
        // todos tomaba 0.62 s por muestra, el 85 % del costo; 18-10-2026.)
        if let Ok(t) = fs::read_to_string(d.join("io")) {
            for l in t.lines() {
                if let Some(v) = l.strip_prefix("read_bytes:") {
                    p.leido = v.trim().parse().ok();
                } else if let Some(v) = l.strip_prefix("write_bytes:") {
                    p.escrito = v.trim().parse().ok();
                }
            }
        }
        // EI_CLASS del ELF: 1 = 32 bit, 2 = 64 bit.
        if let Ok(mut f) = fs::File::open(d.join("exe")) {
            let mut cab = [0u8; 5];
            if std::io::Read::read_exact(&mut f, &mut cab).is_ok() && &cab[..4] == b"\x7fELF" {
                p.bits = match cab[4] { 1 => Some(32), 2 => Some(64), _ => None };
            }
        }
    } else {
        p.voluntarios = None;
    }
    if let Ok(t) = fs::read_to_string(d.join("cgroup")) {
        p.flatpak = t.split('/').find_map(|c| c.strip_prefix("app-flatpak-")).and_then(|r| r.split('-').next()).map(String::from);
    }
    Some(p)
}

pub fn procesos(raiz: &Path, mi_uid: u32) -> Vec<Proceso> {
    let mut v: Vec<Proceso> = fs::read_dir(raiz.join("proc"))
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| e.file_name().to_str()?.parse::<i32>().ok())
        .filter_map(|pid| leer_proceso(raiz, pid, mi_uid))
        .collect();
    v.sort_by_key(|p| p.pid);
    v
}

/// /proc/stat: (total, ocioso) en ticks, del total y de cada núcleo.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Cpu {
    pub total: (u64, u64),
    pub nucleos: Vec<(u64, u64)>,
    /// usuario, sistema, ocioso del total (para el resumen de la pestaña CPU).
    pub partes: (u64, u64, u64),
    pub procesos: u64,
}

pub fn leer_cpu(t: &str) -> Cpu {
    let mut c = Cpu::default();
    for l in t.lines() {
        let mut it = l.split_whitespace();
        let Some(k) = it.next() else { continue };
        if !k.starts_with("cpu") {
            if k == "processes" {
                c.procesos = it.next().and_then(|v| v.parse().ok()).unwrap_or(0);
            }
            continue;
        }
        let n: Vec<u64> = it.filter_map(|v| v.parse().ok()).collect();
        if n.len() < 4 {
            continue;
        }
        // user nice system idle iowait irq softirq steal …
        let ocioso = n[3] + n.get(4).copied().unwrap_or(0);
        let total: u64 = n.iter().take(8).sum();
        if k == "cpu" {
            c.total = (total, ocioso);
            c.partes = (n[0] + n[1], n[2] + n.get(5).copied().unwrap_or(0) + n.get(6).copied().unwrap_or(0), ocioso);
        } else {
            c.nucleos.push((total, ocioso));
        }
    }
    c
}

/// /proc/meminfo, en bytes.
pub fn leer_meminfo(t: &str) -> HashMap<String, u64> {
    t.lines().filter_map(|l| l.split_once(':')).filter_map(|(k, v)| Some((k.to_string(), kb(v)?))).collect()
}

/// /proc/net/dev del sistema, sin lo: (bytes recibidos, bytes enviados, paquetes
/// recibidos, paquetes enviados).
pub fn leer_red(t: &str) -> (u64, u64, u64, u64) {
    let mut r = (0, 0, 0, 0);
    for l in t.lines().skip(2) {
        let Some((nombre, datos)) = l.split_once(':') else { continue };
        if nombre.trim() == "lo" {
            continue;
        }
        let n: Vec<u64> = datos.split_whitespace().filter_map(|v| v.parse().ok()).collect();
        if n.len() >= 10 {
            r.0 += n[0];
            r.1 += n[8];
            r.2 += n[1];
            r.3 += n[9];
        }
    }
    r
}

/// /proc/diskstats, solo de discos enteros (los que tienen /sys/block/<nombre>), sin
/// loop, ram ni zram: (bytes leídos, bytes escritos, lecturas, escrituras).
pub fn leer_disco(t: &str, sys_block: &Path) -> (u64, u64, u64, u64) {
    let mut r = (0, 0, 0, 0);
    for l in t.lines() {
        let c: Vec<&str> = l.split_whitespace().collect();
        if c.len() < 10 {
            continue;
        }
        let nombre = c[2];
        if nombre.starts_with("loop") || nombre.starts_with("ram") || nombre.starts_with("zram") || !sys_block.join(nombre).exists() {
            continue;
        }
        // Sectores de 512 bytes, siempre (Documentation/admin-guide/iostats).
        r.0 += c[5].parse::<u64>().unwrap_or(0) * 512;
        r.1 += c[9].parse::<u64>().unwrap_or(0) * 512;
        r.2 += c[3].parse::<u64>().unwrap_or(0);
        r.3 += c[7].parse::<u64>().unwrap_or(0);
    }
    r
}

/// /etc/passwd: uid → nombre.
pub fn usuarios(raiz: &Path) -> HashMap<u32, String> {
    fs::read_to_string(raiz.join("etc/passwd"))
        .unwrap_or_default()
        .lines()
        .filter_map(|l| {
            let c: Vec<&str> = l.split(':').collect();
            Some((c.get(2)?.parse().ok()?, c.first()?.to_string()))
        })
        .collect()
}

/// Mi uid, de /proc/self/status (sin libc).
pub fn mi_uid() -> u32 {
    fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|t| t.lines().find_map(|l| l.strip_prefix("Uid:")).and_then(|v| v.split_whitespace().next()).and_then(|v| v.parse().ok()))
        .unwrap_or(u32::MAX)
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn stat_con_parentesis_en_el_nombre() {
        let t = "1234 (Web Content (x)) S 1000 1234 1234 0 -1 4194560 100 0 0 0 250 50 0 0 20 0 30 0 100 0 0\n";
        assert_eq!(leer_stat(t), Some(("Web Content (x)".into(), 1000, 300)));
    }

    #[test]
    fn cpu_total_y_nucleos() {
        let t = "cpu  100 0 50 800 50 0 0 0 0 0\ncpu0 50 0 25 400 25 0 0 0 0 0\ncpu1 50 0 25 400 25 0 0 0 0 0\nprocesses 4321\n";
        let c = leer_cpu(t);
        assert_eq!(c.total, (1000, 850));
        assert_eq!(c.nucleos.len(), 2);
        assert_eq!(c.procesos, 4321);
    }

    #[test]
    fn red_sin_lo_y_meminfo_en_bytes() {
        let t = "Inter-|   Receive\n face |bytes\n    lo: 999 1 0 0 0 0 0 0 999 1 0 0 0 0 0 0\n  eno1: 1000 10 0 0 0 0 0 0 2000 20 0 0 0 0 0 0\n";
        assert_eq!(leer_red(t), (1000, 2000, 10, 20));
        assert_eq!(leer_meminfo("MemTotal:       16000 kB\n")["MemTotal"], 16000 * 1024);
    }

    #[test]
    fn este_proceso() {
        let yo = std::process::id() as i32;
        let p = leer_proceso(Path::new("/"), yo, mi_uid()).unwrap();
        assert!(p.rss.unwrap_or(0) > 0 && p.anon.unwrap_or(0) > 0 && p.hilos >= 1 && p.leido.is_some());
        assert_eq!(p.bits, Some(64));
    }
}
