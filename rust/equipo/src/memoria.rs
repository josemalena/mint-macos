//! La memoria instalada, de la tabla SMBIOS (/sys/firmware/dmi/tables/DMI, solo root):
//! las estructuras tipo 17 (Memory Device) de la especificación DMTF DSP0134.
//!
//! Se lee al arrancar porque la memoria no cambia con el sistema corriendo. De cada
//! módulo instalado: tamaño, tipo y velocidad. La velocidad que se da es la
//! configurada (a la que corre de verdad) si el BIOS la trae, y si no la máxima del
//! módulo; con módulos distintos, la menor, que es a la que va el bus. La Mac la
//! escribe en MHz aunque sea MT/s («1333 MHz DDR3»), y aquí igual.

/// Un módulo instalado.
#[derive(Debug, PartialEq)]
pub struct Modulo {
    pub bytes: u64,
    pub tipo: Option<&'static str>,
    /// MT/s; None si el BIOS no la sabe.
    pub velocidad: Option<u32>,
}

/// Una ranura (instalada o vacía), en el orden de la tabla: la pestaña Memory de
/// About This Mac enseña una por ranura.
#[derive(Debug, PartialEq)]
pub struct Ranura {
    /// Device Locator («DIMM0», «ChannelA-DIMM0»); None si el BIOS no lo trae.
    pub etiqueta: Option<String>,
    /// None = vacía.
    pub bytes: Option<u64>,
    pub tipo: Option<&'static str>,
    pub velocidad: Option<u32>,
    pub fabricante: Option<String>,
}

#[derive(Debug, PartialEq)]
pub struct Memoria {
    pub total: u64,
    pub tipo: Option<&'static str>,
    pub velocidad: Option<u32>,
    pub modulos: usize,
    pub ranuras: Vec<Ranura>,
}

/// La cadena número `n` (desde 1) de las que van detrás del área con formato.
fn cadena(cadenas: &[u8], n: u8) -> Option<String> {
    if n == 0 {
        return None;
    }
    let s = cadenas.split(|b| *b == 0).nth(n as usize - 1)?;
    let s = String::from_utf8_lossy(s).trim().to_string();
    // Lo que ponen los BIOS cuando no saben.
    let relleno = ["", "unknown", "not specified", "to be filled by o.e.m.", "undefined", "none", "n/a"];
    if relleno.contains(&s.to_ascii_lowercase().as_str()) || s.chars().all(|c| c == '0' || c == 'x' || c == 'X') {
        None
    } else {
        Some(s)
    }
}

/// Todas las ranuras de la tabla, vacías incluidas.
pub fn ranuras(tabla: &[u8]) -> Vec<Ranura> {
    let mut out = Vec::new();
    recorrer(tabla, |d, cadenas| {
        let m = modulo(d);
        out.push(Ranura {
            etiqueta: d.get(0x10).and_then(|n| cadena(cadenas, *n)),
            bytes: m.as_ref().map(|m| m.bytes),
            tipo: m.as_ref().and_then(|m| m.tipo),
            velocidad: m.as_ref().and_then(|m| m.velocidad),
            // Fabricante (2.3+, 0x17); de un zócalo vacío no se dice.
            fabricante: if m.is_some() && d.len() > 0x17 { cadena(cadenas, d[0x17]) } else { None },
        });
    });
    out
}

/// Memory Type (7.18.2). Solo los que se ven en equipos de verdad.
fn tipo(b: u8) -> Option<&'static str> {
    Some(match b {
        0x0F => "SDRAM",
        0x12 => "DDR",
        0x13 => "DDR2",
        0x14 => "DDR2 FB-DIMM",
        0x18 => "DDR3",
        0x1A => "DDR4",
        0x1B => "LPDDR",
        0x1C => "LPDDR2",
        0x1D => "LPDDR3",
        0x1E => "LPDDR4",
        0x22 => "DDR5",
        0x23 => "LPDDR5",
        _ => return None,
    })
}

fn u16_en(d: &[u8], i: usize) -> Option<u16> {
    d.get(i..i + 2).map(|b| u16::from_le_bytes([b[0], b[1]]))
}

fn u32_en(d: &[u8], i: usize) -> Option<u32> {
    d.get(i..i + 4).map(|b| u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
}

/// Una velocidad de 16 bits: 0 = desconocida, 0xFFFF = la de 32 bits en `ext`.
fn velocidad(d: &[u8], i: usize, ext: usize) -> Option<u32> {
    match u16_en(d, i)? {
        0 => None,
        0xFFFF => u32_en(d, ext).filter(|v| *v != 0),
        v => Some(v as u32),
    }
}

/// Un Memory Device (el área con formato, sin sus cadenas). None si el zócalo está vacío
/// o el tamaño no se sabe.
fn modulo(d: &[u8]) -> Option<Modulo> {
    let tam = u16_en(d, 0x0C)?;
    let bytes = match tam {
        0 | 0xFFFF => return None,
        // Extended Size (2.7+): MB en los bits 0-30.
        0x7FFF => (u32_en(d, 0x1C)? & 0x7FFF_FFFF) as u64 * 1024 * 1024,
        t if t & 0x8000 != 0 => (t & 0x7FFF) as u64 * 1024,
        t => t as u64 * 1024 * 1024,
    };
    if bytes == 0 {
        return None;
    }
    let configurada = if d.len() >= 0x22 { velocidad(d, 0x20, 0x58) } else { None };
    let maxima = if d.len() >= 0x17 { velocidad(d, 0x15, 0x54) } else { None };
    Some(Modulo { bytes, tipo: d.get(0x12).and_then(|b| tipo(*b)), velocidad: configurada.or(maxima) })
}

/// Recorre la tabla: cada estructura es [tipo, largo, handle×2, …] y detrás sus cadenas,
/// que terminan en dos ceros. El tipo 127 es el fin. Llama a `f` con cada tipo 17 (el
/// área con formato y sus cadenas).
fn recorrer(tabla: &[u8], mut f: impl FnMut(&[u8], &[u8])) {
    let mut i = 0;
    while i + 4 <= tabla.len() {
        let (t, largo) = (tabla[i], tabla[i + 1] as usize);
        if largo < 4 || i + largo > tabla.len() {
            break;
        }
        // Las cadenas: hasta el primer par de ceros después del área con formato.
        let mut j = i + largo;
        while j + 1 < tabla.len() && !(tabla[j] == 0 && tabla[j + 1] == 0) {
            j += 1;
        }
        if t == 17 {
            f(&tabla[i..i + largo], &tabla[(i + largo).min(j)..j.min(tabla.len())]);
        }
        if t == 127 {
            break;
        }
        i = j + 2;
    }
}

pub fn modulos(tabla: &[u8]) -> Vec<Modulo> {
    let mut out = Vec::new();
    recorrer(tabla, |d, _| out.extend(modulo(d)));
    out
}

pub fn resumir(m: &[Modulo], ranuras: Vec<Ranura>) -> Option<Memoria> {
    if m.is_empty() {
        return None;
    }
    let mut tipos: Vec<_> = m.iter().filter_map(|x| x.tipo).collect();
    tipos.dedup();
    Some(Memoria {
        total: m.iter().map(|x| x.bytes).sum(),
        // Con tipos mezclados no se dice ninguno.
        tipo: if tipos.len() == 1 && m.iter().all(|x| x.tipo.is_some()) { Some(tipos[0]) } else { None },
        velocidad: m.iter().filter_map(|x| x.velocidad).min(),
        modulos: m.len(),
        ranuras,
    })
}

/// «16 GB 1333 MHz DDR3»; lo que no se sabe no sale.
pub fn texto(m: &Memoria) -> String {
    let gb = m.total as f64 / (1u64 << 30) as f64;
    let mut s = if gb.fract() == 0.0 { format!("{} GB", gb as u64) } else { format!("{gb:.1} GB") };
    if let Some(v) = m.velocidad {
        s.push_str(&format!(" {v} MHz"));
    }
    if let Some(t) = m.tipo {
        s.push(' ');
        s.push_str(t);
    }
    s
}

#[cfg(test)]
mod pruebas {
    use super::*;

    /// Un tipo 17 de 0x28 bytes (2.8) con sus cadenas, como lo escribe un BIOS.
    fn tipo17(tam: u16, tipo_b: u8, maxima: u16, configurada: u16) -> Vec<u8> {
        let mut d = vec![0u8; 0x28];
        d[0] = 17;
        d[1] = 0x28;
        d[0x0C..0x0E].copy_from_slice(&tam.to_le_bytes());
        d[0x12] = tipo_b;
        d[0x15..0x17].copy_from_slice(&maxima.to_le_bytes());
        d[0x20..0x22].copy_from_slice(&configurada.to_le_bytes());
        d[0x10] = 1; // Device Locator
        d[0x11] = 2; // Bank Locator
        d[0x17] = 3; // Manufacturer
        d.extend_from_slice(b"DIMM0\0BANK 0\0Samsung\0\0");
        d
    }

    fn fin() -> Vec<u8> {
        vec![127, 4, 0, 0, 0, 0]
    }

    #[test]
    fn dos_modulos_de_la_mac_mini() {
        let mut t = vec![0, 0x18, 0, 0];
        t.resize(0x18, 0);
        t.extend_from_slice(b"Apple Inc.\0\0"); // un tipo 0 delante, con cadenas
        t.extend(tipo17(8192, 0x18, 1600, 1333));
        t.extend(tipo17(8192, 0x18, 1600, 1333));
        t.extend(fin());
        let m = resumir(&modulos(&t), ranuras(&t)).unwrap();
        assert_eq!((m.total, m.tipo, m.velocidad, m.modulos), (16 << 30, Some("DDR3"), Some(1333), 2));
        assert_eq!(m.ranuras.len(), 2);
        assert_eq!(m.ranuras[0].etiqueta.as_deref(), Some("DIMM0"));
        assert_eq!(m.ranuras[0].bytes, Some(8 << 30));
        assert_eq!(m.ranuras[1].fabricante.as_deref(), Some("Samsung"));
        assert_eq!(texto(&m), "16 GB 1333 MHz DDR3");
    }

    #[test]
    fn zocalo_vacio_y_sin_velocidad_configurada() {
        let mut t = tipo17(0, 0x02, 0, 0); // vacío: no cuenta
        t.extend(tipo17(4096, 0x1A, 2400, 0));
        t.extend(fin());
        let r = ranuras(&t);
        let m = resumir(&modulos(&t), r).unwrap();
        assert_eq!(texto(&m), "4 GB 2400 MHz DDR4");
        assert_eq!(m.ranuras.iter().map(|r| r.bytes).collect::<Vec<_>>(), [None, Some(4 << 30)], "la vacía va como vacía");
        assert_eq!(m.ranuras[0].fabricante, None);
    }

    #[test]
    fn tamano_extendido_y_en_kb() {
        let mut d = tipo17(0x7FFF, 0x22, 4800, 4800);
        d[0x1C..0x20].copy_from_slice(&(32768u32).to_le_bytes());
        assert_eq!(modulos(&d)[0].bytes, 32 << 30);
        let d = tipo17(0x8000 | 512, 0x0F, 0, 0);
        assert_eq!(modulos(&d)[0].bytes, 512 * 1024);
    }

    #[test]
    fn velocidades_distintas_da_la_menor_y_tipos_mezclados_no_dicen_tipo() {
        let mut t = tipo17(8192, 0x18, 1600, 1600);
        t.extend(tipo17(8192, 0x1A, 2133, 1333));
        let m = resumir(&modulos(&t), ranuras(&t)).unwrap();
        assert_eq!(texto(&m), "16 GB 1333 MHz");
    }

    #[test]
    fn tabla_rota_no_revienta() {
        assert!(modulos(&[17, 0x28, 0]).is_empty());
        assert!(modulos(&[17, 2, 0, 0, 0, 0]).is_empty());
        assert!(resumir(&[], vec![]).is_none());
    }
}
