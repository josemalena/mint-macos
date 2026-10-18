//! Los controladores de video, de /sys/bus/pci/devices: los de clase 0x0300 (VGA),
//! 0x0302 (3D) y 0x0380 (Display). El que arrancó la pantalla (boot_vga = 1) va
//! primero.
//!
//! El nombre, el de mercado cuando hay fuente (como lo dice la Mac: «Intel HD
//! Graphics 4000»): Intel de la tabla de Mesa (src/gpus.rs, generada), AMD de
//! /usr/share/libdrm/amdgpu.ids (por device y revisión); si no, pci.ids, la base
//! que usa lspci, sin ejecutarlo. La VRAM solo si el driver la dice
//! (mem_info_vram_total, amdgpu): una integrada de Intel no tiene propia.

use std::fs;
use std::path::Path;

#[derive(Debug, PartialEq)]
pub struct Grafico {
    /// «8086:0166».
    pub pci: String,
    pub fabricante: Option<String>,
    pub modelo: Option<String>,
    /// «Intel HD Graphics 4000»; si no hay nombre de mercado, el de pci.ids, y si
    /// tampoco, el id PCI.
    pub texto: String,
    /// De dónde sale texto: «mesa», «amdgpu.ids», «pci.ids» o «pci».
    pub fuente: &'static str,
    pub vram: Option<u64>,
}

/// AMD: «1002:73bf» con revisión «c1» en amdgpu.ids («73BF,\tC1,\tAMD Radeon RX 6800 XT»).
pub fn amdgpu(ids: &str, device: &str, revision: &str) -> Option<String> {
    let (d, r) = (device.to_ascii_uppercase(), revision.to_ascii_uppercase());
    ids.lines().filter(|l| !l.starts_with('#')).find_map(|l| {
        let mut c = l.splitn(3, ',').map(str::trim);
        let (Some(a), Some(b), Some(n)) = (c.next(), c.next(), c.next()) else { return None };
        (a == d && b == r).then(|| n.to_string())
    })
}

/// Fabricante y dispositivo en pci.ids: «8086  Intel Corporation» y debajo, con un
/// tabulador, «\t0166  3rd Gen Core processor Graphics Controller».
pub fn nombres(ids: &str, vendor: &str, device: &str) -> (Option<String>, Option<String>) {
    let mut fab = None;
    for l in ids.lines() {
        if l.starts_with('#') || l.is_empty() {
            continue;
        }
        if !l.starts_with('\t') {
            if fab.is_some() {
                break; // se acabó el bloque del fabricante sin el dispositivo
            }
            if let Some(r) = l.strip_prefix(vendor) {
                if r.starts_with("  ") {
                    fab = Some(r.trim().to_string());
                }
            }
        } else if fab.is_some() && !l.starts_with("\t\t") {
            if let Some(r) = l[1..].strip_prefix(device) {
                if r.starts_with("  ") {
                    return (fab, Some(r.trim().to_string()));
                }
            }
        }
    }
    (fab, None)
}

/// Como lo decía About en Vala: sin «Corporation», y AMD por su nombre corto.
fn fabricante_corto(f: &str) -> String {
    f.replace("Advanced Micro Devices, Inc. [AMD/ATI]", "AMD")
        .replace(" Corporation", "")
        .replace(" Corp.", "")
}

fn hex(p: &Path) -> Option<String> {
    let t = fs::read_to_string(p).ok()?;
    let t = t.trim().trim_start_matches("0x").to_ascii_lowercase();
    (!t.is_empty()).then_some(t)
}

pub fn leer(raiz: &Path) -> Vec<Grafico> {
    let ids = ["usr/share/misc/pci.ids", "usr/share/hwdata/pci.ids"]
        .iter()
        .find_map(|r| fs::read_to_string(raiz.join(r)).ok())
        .unwrap_or_default();
    let mut v: Vec<(bool, String, Grafico)> = Vec::new();
    let Ok(dir) = fs::read_dir(raiz.join("sys/bus/pci/devices")) else { return Vec::new() };
    for e in dir.flatten() {
        let d = e.path();
        let Some(clase) = hex(&d.join("class")) else { continue };
        if !(clase.starts_with("0300") || clase.starts_with("0302") || clase.starts_with("0380")) {
            continue;
        }
        let (Some(ven), Some(dev)) = (hex(&d.join("vendor")), hex(&d.join("device"))) else { continue };
        let (fab, modelo) = nombres(&ids, &ven, &dev);
        let fab = fab.map(|f| fabricante_corto(&f));
        let pci = format!("{ven}:{dev}");
        let mercado = match ven.as_str() {
            "8086" => u16::from_str_radix(&dev, 16).ok().and_then(|n| crate::gpus::INTEL.iter().find(|(i, _)| *i == n)).map(|(_, nombre)| (nombre.to_string(), "mesa")),
            "1002" => {
                let rev = hex(&d.join("revision")).unwrap_or_default();
                fs::read_to_string(raiz.join("usr/share/libdrm/amdgpu.ids")).ok().and_then(|t| amdgpu(&t, &dev, &rev)).map(|n| (n, "amdgpu.ids"))
            }
            _ => None,
        };
        let (texto, fuente) = match (mercado, &fab, &modelo) {
            (Some((n, f)), _, _) => (n, f),
            (None, Some(f), Some(m)) => (format!("{f} {m}"), "pci.ids"),
            (None, Some(f), None) => (format!("{f} {pci}"), "pci.ids"),
            _ => (pci.clone(), "pci"),
        };
        let vram = fs::read_to_string(d.join("mem_info_vram_total")).ok().and_then(|t| t.trim().parse::<u64>().ok()).filter(|v| *v > 0);
        let arranque = fs::read_to_string(d.join("boot_vga")).map(|s| s.trim() == "1").unwrap_or(false);
        v.push((arranque, e.file_name().to_string_lossy().into_owned(), Grafico { pci, fabricante: fab, modelo, texto, fuente, vram }));
    }
    v.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(&b.1)));
    v.into_iter().map(|(_, _, g)| g).collect()
}

#[cfg(test)]
mod pruebas {
    use super::*;

    const IDS: &str = "# pci.ids\n1002  Advanced Micro Devices, Inc. [AMD/ATI]\n\t6798  Tahiti XT [Radeon HD 7970]\n8086  Intel Corporation\n\t0154  3rd Gen Core processor DRAM Controller\n\t0166  3rd Gen Core processor Graphics Controller\n\t\t106b 00fa  Mac mini\n10de  NVIDIA Corporation\n";

    #[test]
    fn nombres_de_pci_ids() {
        assert_eq!(nombres(IDS, "8086", "0166"), (Some("Intel Corporation".into()), Some("3rd Gen Core processor Graphics Controller".into())));
        assert_eq!(nombres(IDS, "10de", "1234"), (Some("NVIDIA Corporation".into()), None));
        assert_eq!(nombres(IDS, "abcd", "0166"), (None, None));
        // un subsistema con el mismo número no cuenta como dispositivo
        assert_eq!(nombres(IDS, "8086", "106b").1, None);
    }

    #[test]
    fn de_sys_con_el_de_arranque_primero() {
        let t = std::env::temp_dir().join(format!("equipo-graficos-{}", std::process::id()));
        let _ = fs::remove_dir_all(&t);
        let poner = |dir: &str, clase: &str, ven: &str, dev: &str, boot: &str| {
            let d = t.join("sys/bus/pci/devices").join(dir);
            fs::create_dir_all(&d).unwrap();
            fs::write(d.join("class"), clase).unwrap();
            fs::write(d.join("vendor"), ven).unwrap();
            fs::write(d.join("device"), dev).unwrap();
            if !boot.is_empty() {
                fs::write(d.join("boot_vga"), boot).unwrap();
            }
        };
        poner("0000:00:00.0", "0x060000\n", "0x8086\n", "0x0154\n", "");
        poner("0000:00:02.0", "0x030000\n", "0x8086\n", "0x0166\n", "0\n");
        poner("0000:01:00.0", "0x030000\n", "0x1002\n", "0x6798\n", "1\n");
        fs::create_dir_all(t.join("usr/share/misc")).unwrap();
        fs::write(t.join("usr/share/misc/pci.ids"), IDS).unwrap();
        let g = leer(&t);
        // Intel con nombre de Mesa; la AMD sin amdgpu.ids de prueba se queda con pci.ids.
        assert_eq!(g.iter().map(|x| (x.texto.as_str(), x.fuente)).collect::<Vec<_>>(), [("AMD Tahiti XT [Radeon HD 7970]", "pci.ids"), ("Intel HD Graphics 4000", "mesa")]);
        fs::create_dir_all(t.join("usr/share/libdrm")).unwrap();
        fs::write(t.join("usr/share/libdrm/amdgpu.ids"), "# x\n1.0.0\n6798,\t00,\tAMD Radeon HD 7970\n").unwrap();
        fs::write(t.join("sys/bus/pci/devices/0000:01:00.0/revision"), "0x00\n").unwrap();
        fs::write(t.join("sys/bus/pci/devices/0000:01:00.0/mem_info_vram_total"), "3221225472\n").unwrap();
        let g = leer(&t);
        assert_eq!((g[0].texto.as_str(), g[0].fuente, g[0].vram), ("AMD Radeon HD 7970", "amdgpu.ids", Some(3 << 30)));
        assert_eq!(g[1].vram, None, "la integrada de Intel no dice VRAM");
        fs::remove_dir_all(&t).unwrap();
    }
}
