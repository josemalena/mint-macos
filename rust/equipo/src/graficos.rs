//! Los controladores de video, de /sys/bus/pci/devices: los de clase 0x0300 (VGA),
//! 0x0302 (3D) y 0x0380 (Display). El nombre sale de pci.ids, la misma base que usa
//! lspci, sin ejecutarlo. El que arrancó la pantalla (boot_vga = 1) va primero.

use std::fs;
use std::path::Path;

#[derive(Debug, PartialEq)]
pub struct Grafico {
    /// «8086:0166».
    pub pci: String,
    pub fabricante: Option<String>,
    pub modelo: Option<String>,
    /// «Intel 3rd Gen Core processor Graphics Controller»; el id PCI si pci.ids no lo trae.
    pub texto: String,
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
        let texto = match (&fab, &modelo) {
            (Some(f), Some(m)) => format!("{f} {m}"),
            (Some(f), None) => format!("{f} {pci}"),
            _ => pci.clone(),
        };
        let arranque = fs::read_to_string(d.join("boot_vga")).map(|s| s.trim() == "1").unwrap_or(false);
        v.push((arranque, e.file_name().to_string_lossy().into_owned(), Grafico { pci, fabricante: fab, modelo, texto }));
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
        assert_eq!(g.iter().map(|x| x.texto.as_str()).collect::<Vec<_>>(), ["AMD Tahiti XT [Radeon HD 7970]", "Intel 3rd Gen Core processor Graphics Controller"]);
        fs::remove_dir_all(&t).unwrap();
    }
}
