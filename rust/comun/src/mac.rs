//! Lo que se lee de una .app de Mac sin ejecutarla: el Info.plist, si el
//! ejecutable es Mach-O x86_64 (lo que corre Darling) y el ícono del .icns.
//! Lo usan mint-macos-abrir-mac y el generador de lanzadores de /Applications
//! (rust/appimages), para que los dos lean las apps igual.

use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};

const CPU_X86_64: u32 = 0x0100_0007;

pub struct App {
    pub ruta: PathBuf,
    pub ejecutable: PathBuf,
    pub nombre_ejecutable: String,
    pub nombre: String,
    pub id: String,
    pub minimo: Option<String>,
    pub icono: Option<String>,
}

pub fn leer_app(ruta: &Path) -> Result<App, String> {
    let info = ruta.join("Contents/Info.plist");
    let datos = leer_con_tope(&info, 1 << 20).map_err(|_| "The application is missing its Info.plist.".to_string())?;
    let claves = plist::claves(&datos).ok_or("Its Info.plist can't be read.")?;
    let valor = |k: &str| claves.iter().find(|(c, _)| c == k).map(|(_, v)| v.clone()).filter(|v| !v.is_empty());
    let nombre_ejecutable = valor("CFBundleExecutable").ok_or("Its Info.plist has no CFBundleExecutable.")?;
    if nombre_ejecutable.contains('/') {
        return Err("Its CFBundleExecutable is not a plain name.".into());
    }
    let ejecutable = ruta.join("Contents/MacOS").join(&nombre_ejecutable);
    let nombre = valor("CFBundleDisplayName")
        .or_else(|| valor("CFBundleName"))
        .unwrap_or_else(|| nombre_visible(ruta));
    let id = valor("CFBundleIdentifier")
        .filter(|i| i.chars().all(|c| c.is_ascii_alphanumeric() || ".-_".contains(c)))
        .unwrap_or_else(|| nombre_ejecutable.clone());
    Ok(App {
        ruta: ruta.to_path_buf(),
        ejecutable,
        nombre_ejecutable,
        nombre,
        id,
        minimo: valor("LSMinimumSystemVersion"),
        icono: valor("CFBundleIconFile"),
    })
}

pub fn leer_con_tope(p: &Path, tope: u64) -> std::io::Result<Vec<u8>> {
    let mut v = Vec::new();
    fs::File::open(p)?.take(tope).read_to_end(&mut v)?;
    Ok(v)
}

pub fn nombre_visible(ruta: &Path) -> String {
    let n = ruta.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    n.strip_suffix(".app").unwrap_or(&n).to_string()
}

/// Si el ejecutable trae código que Darling puede correr. Solo lee la cabecera.
pub fn revisar_macho(p: &Path) -> Result<(), String> {
    let cab = leer_con_tope(p, 4096).map_err(|_| "The application's executable can't be found.".to_string())?;
    let u32_le = |o: usize| cab.get(o..o + 4).map(|b| u32::from_le_bytes(b.try_into().unwrap()));
    let u32_be = |o: usize| cab.get(o..o + 4).map(|b| u32::from_be_bytes(b.try_into().unwrap()));
    let sin_intel = "This application doesn't have a version for 64-bit Intel processors.".to_string();
    match cab.get(..4) {
        Some([0xcf, 0xfa, 0xed, 0xfe]) => (u32_le(4) == Some(CPU_X86_64)).then_some(()).ok_or(sin_intel),
        Some([0xce, 0xfa, 0xed, 0xfe]) => Err("This application is 32-bit and can't run.".into()),
        // Fat: big-endian. cafebabf es la variante de 64 bits, con entradas de 32 bytes.
        Some([0xca, 0xfe, 0xba, 0xbe]) | Some([0xca, 0xfe, 0xba, 0xbf]) => {
            let paso = if cab[3] == 0xbf { 32 } else { 20 };
            let n = u32_be(4).unwrap_or(0) as usize;
            // Un .class de Java empieza igual; ahí el «número de tajadas» es la versión (≥ 45).
            if n == 0 || n > 16 {
                return Err("The application's executable is not a Mac program.".into());
            }
            (0..n).any(|i| u32_be(8 + i * paso) == Some(CPU_X86_64)).then_some(()).ok_or(sin_intel)
        }
        _ => Err("The application's executable is not a Mac program.".into()),
    }
}

/// «10.15.8» → (10, 15).
pub fn version(v: &str) -> (u32, u32) {
    let mut p = v.split('.').map(|x| x.parse::<u32>().unwrap_or(0));
    (p.next().unwrap_or(0), p.next().unwrap_or(0))
}

/// El ícono de la app como PNG en la carpeta dir. Sale del .icns de
/// CFBundleIconFile (o AppIcon.icns): las entradas grandes (ic07 en adelante)
/// son PNG tal cual; se toma la más grande de hasta 512 px. Las viejas
/// (is32, il32…) y las JPEG 2000 no se leen: sin PNG, None. Queda en
/// <dir>/<bundle id>-<tamaño del .icns>.png.
pub fn icono_png(app: &App, dir: &Path) -> Option<PathBuf> {
    let recursos = app.ruta.join("Contents/Resources");
    let nombre = app.icono.clone().unwrap_or_else(|| "AppIcon".into());
    let icns = [recursos.join(&nombre), recursos.join(format!("{nombre}.icns"))].into_iter().find(|p| p.is_file())?;
    let datos = leer_con_tope(&icns, 16 << 20).ok()?;
    let png = png_de_icns(&datos)?;
    let destino = dir.join(format!("{}-{}.png", app.id, datos.len()));
    if !destino.is_file() {
        fs::create_dir_all(destino.parent()?).ok()?;
        fs::write(&destino, png).ok()?;
    }
    Some(destino)
}

/// La entrada PNG más grande de hasta 512 px de un .icns.
pub fn png_de_icns(datos: &[u8]) -> Option<&[u8]> {
    if datos.get(..4)? != b"icns" {
        return None;
    }
    let be = |o: usize| datos.get(o..o + 4).map(|b| u32::from_be_bytes(b.try_into().unwrap()) as usize);
    let mut mejor: Option<(usize, &[u8])> = None;
    let mut o = 8;
    while o + 8 <= datos.len() {
        let largo = be(o + 4)?;
        if largo < 8 || o + largo > datos.len() {
            break;
        }
        let cuerpo = &datos[o + 8..o + largo];
        // PNG: firma y ancho en el IHDR (bytes 16..20).
        if cuerpo.starts_with(b"\x89PNG\r\n\x1a\n") && cuerpo.len() > 24 {
            let ancho = u32::from_be_bytes(cuerpo[16..20].try_into().unwrap()) as usize;
            if ancho <= 512 && mejor.map_or(true, |(a, _)| ancho > a) {
                mejor = Some((ancho, cuerpo));
            }
        }
        o += largo;
    }
    mejor.map(|(_, p)| p)
}

/// Las claves de texto del diccionario de arriba de un Info.plist, XML o binario
/// (bplist00). No hace falta más: lo que se lee son cadenas del primer nivel.
pub mod plist {
    pub fn claves(datos: &[u8]) -> Option<Vec<(String, String)>> {
        if datos.starts_with(b"bplist00") {
            binario(datos)
        } else {
            xml(std::str::from_utf8(datos).ok()?)
        }
    }

    /// <key>K</key> seguido de <string>V</string>, solo en el primer nivel del dict.
    fn xml(t: &str) -> Option<Vec<(String, String)>> {
        let mut r = Vec::new();
        let mut nivel = 0i32;
        let mut resto = &t[t.find("<dict>")? + 6..];
        let mut clave: Option<String> = None;
        while let Some(i) = resto.find('<') {
            resto = &resto[i..];
            let fin = resto.find('>')?;
            let etiqueta = &resto[1..fin];
            resto = &resto[fin + 1..];
            match etiqueta {
                "dict" | "array" => nivel += 1,
                "/dict" | "/array" => {
                    if nivel == 0 {
                        break;
                    }
                    nivel -= 1;
                }
                "key" | "string" if nivel == 0 => {
                    let cierre = resto.find('<')?;
                    let texto = entidades(&resto[..cierre]);
                    if etiqueta == "key" {
                        clave = Some(texto);
                    } else if let Some(k) = clave.take() {
                        r.push((k, texto));
                    }
                }
                e if nivel == 0 && !e.starts_with('/') => clave = None,
                _ => {}
            }
        }
        Some(r)
    }

    fn entidades(s: &str) -> String {
        s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'").replace("&amp;", "&")
    }

    /// bplist00: el trailer de 32 bytes dice dónde está la tabla de offsets y
    /// cuál es el objeto de arriba.
    fn binario(d: &[u8]) -> Option<Vec<(String, String)>> {
        let t = d.get(d.len().checked_sub(32)?..)?;
        let tam_offset = t[6] as usize;
        let tam_ref = t[7] as usize;
        let n = entero(&t[8..16]) as usize;
        let arriba = entero(&t[16..24]) as usize;
        let tabla = entero(&t[24..32]) as usize;
        let offset = |i: usize| -> Option<usize> {
            let o = tabla.checked_add(i.checked_mul(tam_offset)?)?;
            Some(entero(d.get(o..o + tam_offset)?) as usize)
        };
        if arriba >= n {
            return None;
        }
        let o = offset(arriba)?;
        let (tipo, cuenta, inicio) = cabecera(d, o)?;
        if tipo != 0xd {
            return None;
        }
        let mut r = Vec::new();
        for i in 0..cuenta {
            let ref_ = |j: usize| -> Option<usize> {
                let p = inicio.checked_add(j.checked_mul(tam_ref)?)?;
                Some(entero(d.get(p..p + tam_ref)?) as usize)
            };
            let (k, v) = (ref_(i)?, ref_(cuenta + i)?);
            if let (Some(k), Some(v)) = (cadena(d, offset(k)?), cadena(d, offset(v)?)) {
                r.push((k, v));
            }
        }
        Some(r)
    }

    fn entero(b: &[u8]) -> u64 {
        b.iter().fold(0, |a, &x| (a << 8) | x as u64)
    }

    /// (tipo, cuenta, donde empiezan los datos). Con cuenta 0xf, el largo va
    /// aparte como un entero (marcador 0x1n, 2^n bytes).
    fn cabecera(d: &[u8], o: usize) -> Option<(u8, usize, usize)> {
        let m = *d.get(o)?;
        let (tipo, bajo) = (m >> 4, (m & 0xf) as usize);
        if bajo != 0xf {
            return Some((tipo, bajo, o + 1));
        }
        let mi = *d.get(o + 1)?;
        if mi >> 4 != 1 {
            return None;
        }
        let tam = 1usize << (mi & 0xf);
        Some((tipo, entero(d.get(o + 2..o + 2 + tam)?) as usize, o + 2 + tam))
    }

    fn cadena(d: &[u8], o: usize) -> Option<String> {
        let (tipo, n, i) = cabecera(d, o)?;
        match tipo {
            0x5 => Some(String::from_utf8_lossy(d.get(i..i.checked_add(n)?)?).into_owned()),
            0x6 => {
                let b = d.get(i..i.checked_add(n.checked_mul(2)?)?)?;
                let u: Vec<u16> = b.chunks(2).map(|c| u16::from_be_bytes([c[0], c[1]])).collect();
                Some(String::from_utf16_lossy(&u))
            }
            _ => None,
        }
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn plist_xml_primer_nivel() {
        let t = br#"<?xml version="1.0"?><plist><dict>
            <key>CFBundleExecutable</key><string>Calc &amp; Co</string>
            <key>Anidado</key><dict><key>CFBundleName</key><string>no</string></dict>
            <key>LSUIElement</key><true/>
            <key>CFBundleName</key><string>Calculadora</string>
            </dict></plist>"#;
        let c = plist::claves(t).unwrap();
        assert_eq!(c, vec![("CFBundleExecutable".into(), "Calc & Co".into()), ("CFBundleName".into(), "Calculadora".into())]);
    }

    /// Hecho con plistlib (FMT_BINARY): un dict anidado, un booleano y una
    /// cadena UTF-16 («ñ»), que en bplist va con el marcador 0x6.
    #[test]
    fn plist_binario_primer_nivel() {
        let hex = "62706c6973743030d4010203040507080957416e696461646f5f1012434642756e646c6545786563757461626c655c434642756e646c654e616d655b4c535549456c656d656e74d10306526e6f5443616c636d00430061006c00630075006c00610064006f00720061002000f1090811192e3b474a4d526d0000000000000101000000000000000a0000000000000000000000000000006e";
        let b: Vec<u8> = (0..hex.len()).step_by(2).map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap()).collect();
        let c = plist::claves(&b).unwrap();
        assert_eq!(c, vec![("CFBundleExecutable".into(), "Calc".into()), ("CFBundleName".into(), "Calculadora ñ".into())]);
    }

    /// Un PNG mínimo con ese ancho en el IHDR (lo único que se lee).
    fn png(ancho: u32) -> Vec<u8> {
        let mut v = b"\x89PNG\r\n\x1a\n\0\0\0\x0dIHDR".to_vec();
        v.extend_from_slice(&ancho.to_be_bytes());
        v.extend_from_slice(&ancho.to_be_bytes());
        v.extend_from_slice(&[0; 8]);
        v
    }

    fn entrada(tipo: &[u8; 4], cuerpo: &[u8]) -> Vec<u8> {
        let mut v = tipo.to_vec();
        v.extend_from_slice(&((cuerpo.len() + 8) as u32).to_be_bytes());
        v.extend_from_slice(cuerpo);
        v
    }

    #[test]
    fn icns_el_png_mas_grande_hasta_512() {
        let mut cuerpo = entrada(b"is32", &[1, 2, 3]);
        cuerpo.extend(entrada(b"ic07", &png(128)));
        cuerpo.extend(entrada(b"ic10", &png(1024)));
        cuerpo.extend(entrada(b"ic08", &png(256)));
        let mut icns = b"icns".to_vec();
        icns.extend_from_slice(&((cuerpo.len() + 8) as u32).to_be_bytes());
        icns.extend(cuerpo);
        assert_eq!(png_de_icns(&icns), Some(&png(256)[..]));
        assert_eq!(png_de_icns(b"nada"), None);
    }

    /// Con el ícono de verdad de Calculator, si está en esta máquina.
    #[test]
    fn icns_de_calculator() {
        let p = Path::new("/media/jmalena/Data/darling-prefijo/prueba-apple/Calculator.app/Contents/Resources/AppIcon.icns");
        if let Ok(d) = fs::read(p) {
            let png = png_de_icns(&d).expect("Calculator trae PNG en su .icns");
            assert!(png.starts_with(b"\x89PNG"));
        }
    }
}
