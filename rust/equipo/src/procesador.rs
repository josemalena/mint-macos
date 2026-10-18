//! El procesador, de /proc/cpuinfo, con el nombre como lo escribe la Mac:
//! «2.5 GHz Dual-Core Intel Core i5». Es la misma regla que tenía About en Vala
//! (nativo/acerca/acerca_datos.vala), pasada aquí para que se lea una vez al arrancar.

#[derive(Debug, PartialEq)]
pub struct Procesador {
    /// «Intel(R) Core(TM) i5-3210M CPU @ 2.50GHz», tal cual.
    pub modelo: String,
    pub ghz: Option<f64>,
    /// Núcleos físicos: «cpu cores» de cada «physical id» distinto, sumados.
    pub nucleos: Option<u32>,
    pub texto: String,
}

fn valor(l: &str) -> &str {
    l.split_once(':').map(|(_, v)| v.trim()).unwrap_or("")
}

/// Los GHz de «… @ 2.50GHz»; si el nombre no los trae (AMD), los de `base_khz`.
fn ghz_del_nombre(m: &str) -> Option<f64> {
    let (_, d) = m.split_once('@')?;
    let d = d.trim();
    let num: String = d.chars().take_while(|c| c.is_ascii_digit() || *c == '.').collect();
    if !d[num.len()..].trim_start().starts_with("GHz") {
        return None;
    }
    num.parse().ok()
}

/// Una palabra que empieza en `i` (sin letra ni dígito antes) y es i3, i5, i7 o i9
/// seguida de «-»: «i5-3210M» → «i5».
fn quitar_sufijo_core(s: &str) -> String {
    s.split(' ')
        .map(|p| {
            let b = p.as_bytes();
            if b.len() > 3 && b[0] == b'i' && matches!(b[1], b'3' | b'5' | b'7' | b'9') && b[2] == b'-' {
                p[..2].to_string()
            } else {
                p.to_string()
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn limpiar(modelo: &str) -> String {
    let mut s = modelo.replace("(R)", "").replace("(TM)", "");
    if let Some(i) = s.find('@') {
        s.truncate(i);
    }
    let s = s
        .split_whitespace()
        .filter(|p| *p != "CPU" && *p != "Processor")
        .collect::<Vec<_>>()
        .join(" ");
    quitar_sufijo_core(&s)
}

pub fn leer(cpuinfo: &str, base_khz: Option<u64>) -> Option<Procesador> {
    let mut modelo = String::new();
    let mut fisico = String::new();
    let mut vistos = std::collections::HashSet::new();
    let mut nucleos = 0u32;
    for l in cpuinfo.lines() {
        if l.starts_with("model name") && modelo.is_empty() {
            modelo = valor(l).to_string();
        } else if l.starts_with("physical id") {
            fisico = valor(l).to_string();
        } else if l.starts_with("cpu cores") && vistos.insert(fisico.clone()) {
            nucleos += valor(l).parse::<u32>().unwrap_or(0);
        }
    }
    if modelo.is_empty() {
        return None;
    }
    let ghz = ghz_del_nombre(&modelo).or(base_khz.filter(|k| *k > 0).map(|k| k as f64 / 1_000_000.0));
    let nucleos = (nucleos > 0).then_some(nucleos);
    let mut partes = Vec::new();
    if let Some(g) = ghz {
        partes.push(format!("{g:.1} GHz"));
    }
    match nucleos {
        Some(2) => partes.push("Dual-Core".to_string()),
        Some(4) => partes.push("Quad-Core".to_string()),
        Some(n) => partes.push(format!("{n}-Core")),
        None => {}
    }
    partes.push(limpiar(&modelo));
    Some(Procesador { texto: partes.join(" "), modelo, ghz, nucleos })
}

#[cfg(test)]
mod pruebas {
    use super::*;

    const MINI: &str = "processor\t: 0\nmodel name\t: Intel(R) Core(TM) i5-3210M CPU @ 2.50GHz\nphysical id\t: 0\ncpu cores\t: 2\n\nprocessor\t: 1\nmodel name\t: Intel(R) Core(TM) i5-3210M CPU @ 2.50GHz\nphysical id\t: 0\ncpu cores\t: 2\n";

    #[test]
    fn la_mac_mini() {
        let p = leer(MINI, None).unwrap();
        assert_eq!(p.texto, "2.5 GHz Dual-Core Intel Core i5");
        assert_eq!(p.nucleos, Some(2));
    }

    #[test]
    fn amd_sin_ghz_en_el_nombre() {
        let c = "model name\t: AMD Ryzen 7 5800X 8-Core Processor\nphysical id\t: 0\ncpu cores\t: 8\n";
        assert_eq!(leer(c, Some(3_800_000)).unwrap().texto, "3.8 GHz 8-Core AMD Ryzen 7 5800X 8-Core");
        assert_eq!(leer(c, None).unwrap().texto, "8-Core AMD Ryzen 7 5800X 8-Core");
    }

    #[test]
    fn dos_zocalos_suman_y_sin_modelo_no_hay() {
        let c = "model name\t: Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz\nphysical id\t: 0\ncpu cores\t: 10\nphysical id\t: 1\ncpu cores\t: 10\nphysical id\t: 1\ncpu cores\t: 10\n";
        assert_eq!(leer(c, None).unwrap().texto, "2.8 GHz 20-Core Intel Xeon E5-2680 v2");
        assert!(leer("processor : 0\n", None).is_none());
    }
}
