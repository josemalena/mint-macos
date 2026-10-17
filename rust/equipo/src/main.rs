//! mint-macos-equipo: qué equipo es y qué sistema corre, para About This Mac/PC.
//!
//! Lo corre al arrancar mint-macos-equipo.service (oneshot del sistema) y escribe
//! /run/mint-macos/equipo.json, legible para todos (0644). Lo leen libmacos y el
//! applet; si el archivo falta, ellos leen DMI y os-release con la misma regla.
//!
//!     version           1
//!     tipo              "mac" si sys_vendor es «Apple Inc.», si no "pc"
//!     fabricante        sys_vendor
//!     identificador     product_name (Macmini6,1)
//!     nombre            el nombre comercial de la tabla de Apple (src/modelos.rs); si el
//!                       identificador no está o Apple lo usa para varios modelos, el
//!                       identificador tal cual
//!     nombres           los nombres de la tabla, en el orden de la página de Apple
//!     fuente_nombre     la página de Apple de esa fila
//!     version_producto  product_version (en muchos PC, el nombre comercial)
//!     sistema           id, nombre, version y texto: ID, NAME, VERSION y PRETTY_NAME de
//!                       os-release
//!     logo, logo_icono  LOGO= de os-release (o «ID-logo» si no trae) y su archivo en
//!                       hicolor: el scalable, o si no el PNG más grande
//!
//! Lo que no se puede leer va null, nunca "". Nada se adivina: un PC sin tabla lleva
//! lo que dice su DMI.
//!
//!     mint-macos-equipo                    escribe /run/mint-macos/equipo.json
//!     mint-macos-equipo --imprimir         lo escribe en la salida, sin tocar nada
//!     mint-macos-equipo --salida ARCHIVO   en otro archivo
//!     mint-macos-equipo --raiz DIR         lee DIR/sys/class/dmi/id, DIR/etc/os-release y
//!                                          DIR/usr/share/icons (para las pruebas)

mod modelos;

use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::exit;

const SALIDA: &str = "/run/mint-macos/equipo.json";

fn salir(msg: &str, codigo: i32) -> ! {
    eprintln!("mint-macos-equipo: {msg}");
    exit(codigo)
}

/// Un archivo de /sys/class/dmi/id sin el salto final; null si no se lee o queda vacío.
fn dmi(raiz: &Path, campo: &str) -> Option<String> {
    let b = fs::read(raiz.join("sys/class/dmi/id").join(campo)).ok()?;
    let s = String::from_utf8_lossy(&b).trim().to_string();
    if s.is_empty() { None } else { Some(s) }
}

/// Un valor de os-release, con las comillas de la especificación: entre "…" valen los
/// escapes \" \\ \$ \` ; entre '…' nada; sin comillas, tal cual.
fn valor_os_release(v: &str) -> String {
    let v = v.trim();
    let mut c = v.chars();
    match c.next() {
        Some(q @ ('"' | '\'')) if v.len() >= 2 && v.ends_with(q) => {
            let dentro = &v[1..v.len() - 1];
            if q == '\'' {
                return dentro.to_string();
            }
            let mut out = String::new();
            let mut it = dentro.chars().peekable();
            while let Some(ch) = it.next() {
                if ch == '\\' {
                    if let Some(&n) = it.peek() {
                        if matches!(n, '"' | '\\' | '$' | '`') {
                            out.push(n);
                            it.next();
                            continue;
                        }
                    }
                }
                out.push(ch);
            }
            out
        }
        _ => v.to_string(),
    }
}

/// /etc/os-release, o /usr/lib/os-release si no está (la especificación).
fn os_release(raiz: &Path) -> Vec<(String, String)> {
    let texto = fs::read(raiz.join("etc/os-release"))
        .or_else(|_| fs::read(raiz.join("usr/lib/os-release")))
        .map(|b| String::from_utf8_lossy(&b).into_owned())
        .unwrap_or_default();
    let mut out = Vec::new();
    for l in texto.lines() {
        let l = l.trim();
        if l.is_empty() || l.starts_with('#') {
            continue;
        }
        if let Some((k, v)) = l.split_once('=') {
            out.push((k.trim().to_string(), valor_os_release(v)));
        }
    }
    out
}

fn clave(os: &[(String, String)], k: &str) -> Option<String> {
    // Si una clave se repite, vale la última (como al leerlo con el shell).
    os.iter().rev().find(|(a, _)| a == k).map(|(_, v)| v.clone()).filter(|v| !v.is_empty())
}

/// El archivo del ícono en hicolor: el scalable, o si no el PNG más grande
/// (64x64@2 cuenta como 128; a igual tamaño gana el de escala 1, y después el
/// nombre de carpeta menor, para que no dependa del orden del directorio).
fn buscar_logo(raiz: &Path, icono: &str) -> Option<PathBuf> {
    let hicolor = raiz.join("usr/share/icons/hicolor");
    let svg = hicolor.join("scalable/apps").join(format!("{icono}.svg"));
    if svg.is_file() {
        return Some(svg);
    }
    let mut mejor: Option<((u64, std::cmp::Reverse<u64>, std::cmp::Reverse<String>), PathBuf)> = None;
    for e in fs::read_dir(&hicolor).ok()?.flatten() {
        let nombre = e.file_name().to_string_lossy().into_owned();
        let (medida, escala) = match nombre.split_once('@') {
            Some((m, s)) => (m.to_string(), s.parse::<u64>().unwrap_or(0)),
            None => (nombre.clone(), 1),
        };
        let Some((w, h)) = medida.split_once('x') else { continue };
        let (Ok(w), Ok(_)) = (w.parse::<u64>(), h.parse::<u64>()) else { continue };
        let png = e.path().join("apps").join(format!("{icono}.png"));
        let orden = (w * escala, std::cmp::Reverse(escala), std::cmp::Reverse(nombre.clone()));
        if orden.0 > 0 && png.is_file() && mejor.as_ref().map(|(t, _)| orden > *t).unwrap_or(true) {
            mejor = Some((orden, png));
        }
    }
    mejor.map(|(_, p)| p)
}

// --- JSON ---------------------------------------------------------------------

fn cadena(s: &str) -> String {
    let mut o = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            '\r' => o.push_str("\\r"),
            '\t' => o.push_str("\\t"),
            c if (c as u32) < 0x20 => o.push_str(&format!("\\u{:04x}", c as u32)),
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

fn opcional(s: &Option<String>) -> String {
    s.as_deref().map(cadena).unwrap_or_else(|| "null".to_string())
}

struct Equipo {
    tipo: &'static str,
    fabricante: Option<String>,
    identificador: Option<String>,
    nombre: Option<String>,
    nombres: Option<Vec<String>>,
    fuente_nombre: Option<String>,
    version_producto: Option<String>,
    sistema: [Option<String>; 4],
    logo: Option<String>,
    logo_icono: Option<String>,
}

fn leer(raiz: &Path) -> Equipo {
    let fabricante = dmi(raiz, "sys_vendor");
    let identificador = dmi(raiz, "product_name");
    let fila = identificador.as_deref().and_then(|i| modelos::MODELOS.iter().find(|(id, _, _)| *id == i));
    let nombre = match fila {
        Some((_, [uno], _)) => Some(uno.to_string()),
        _ => identificador.clone(),
    };
    let os = os_release(raiz);
    let id = clave(&os, "ID");
    let logo_icono = clave(&os, "LOGO").or_else(|| id.as_ref().map(|i| format!("{i}-logo")));
    let logo = logo_icono.as_deref().and_then(|i| buscar_logo(raiz, i)).map(|p| p.to_string_lossy().into_owned());
    Equipo {
        tipo: if fabricante.as_deref() == Some("Apple Inc.") { "mac" } else { "pc" },
        fabricante,
        identificador,
        nombre,
        nombres: fila.map(|(_, n, _)| n.iter().map(|s| s.to_string()).collect()),
        fuente_nombre: fila.map(|(_, _, u)| u.to_string()),
        version_producto: dmi(raiz, "product_version"),
        sistema: [id, clave(&os, "NAME"), clave(&os, "VERSION"), clave(&os, "PRETTY_NAME")],
        logo,
        logo_icono,
    }
}

fn json(e: &Equipo) -> String {
    let nombres = match &e.nombres {
        Some(v) => format!("[{}]", v.iter().map(|s| cadena(s)).collect::<Vec<_>>().join(", ")),
        None => "null".to_string(),
    };
    let [id, nombre, version, texto] = &e.sistema;
    format!(
        "{{\n  \"version\": 1,\n  \"tipo\": {},\n  \"fabricante\": {},\n  \"identificador\": {},\n  \"nombre\": {},\n  \"nombres\": {},\n  \"fuente_nombre\": {},\n  \"version_producto\": {},\n  \"sistema\": {{\n    \"id\": {},\n    \"nombre\": {},\n    \"version\": {},\n    \"texto\": {}\n  }},\n  \"logo\": {},\n  \"logo_icono\": {}\n}}\n",
        cadena(e.tipo),
        opcional(&e.fabricante),
        opcional(&e.identificador),
        opcional(&e.nombre),
        nombres,
        opcional(&e.fuente_nombre),
        opcional(&e.version_producto),
        opcional(id),
        opcional(nombre),
        opcional(version),
        opcional(texto),
        opcional(&e.logo),
        opcional(&e.logo_icono),
    )
}

/// Escribe en un temporal de la misma carpeta y lo cambia de nombre: quien lo lea
/// nunca ve un archivo a medias.
fn escribir(destino: &Path, texto: &str) -> std::io::Result<()> {
    let carpeta = destino.parent().filter(|p| !p.as_os_str().is_empty()).unwrap_or(Path::new("."));
    if !carpeta.is_dir() {
        fs::create_dir_all(carpeta)?;
        fs::set_permissions(carpeta, fs::Permissions::from_mode(0o755))?;
    }
    let tmp = carpeta.join(format!(".{}.tmp", destino.file_name().map(|n| n.to_string_lossy()).unwrap_or_default()));
    let mut f = fs::File::create(&tmp)?;
    f.write_all(texto.as_bytes())?;
    f.sync_all()?;
    drop(f);
    fs::set_permissions(&tmp, fs::Permissions::from_mode(0o644))?;
    fs::rename(&tmp, destino)
}

fn main() {
    let mut raiz = PathBuf::from("/");
    let mut salida = PathBuf::from(SALIDA);
    let mut imprimir = false;
    let mut args = std::env::args_os().skip(1);
    while let Some(a) = args.next() {
        match a.to_str() {
            Some("--imprimir") => imprimir = true,
            Some("--raiz") => raiz = args.next().map(PathBuf::from).unwrap_or_else(|| salir("--raiz sin carpeta", 2)),
            Some("--salida") => salida = args.next().map(PathBuf::from).unwrap_or_else(|| salir("--salida sin archivo", 2)),
            _ => salir(&format!("opción desconocida: {}\nuso: mint-macos-equipo [--imprimir] [--salida ARCHIVO] [--raiz DIR]", a.to_string_lossy()), 2),
        }
    }
    let texto = json(&leer(&raiz));
    if imprimir {
        print!("{texto}");
        return;
    }
    if let Err(e) = escribir(&salida, &texto) {
        salir(&format!("{}: {e}", salida.display()), 1);
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn comillas_de_os_release() {
        assert_eq!(valor_os_release("\"Linux Mint\""), "Linux Mint");
        assert_eq!(valor_os_release("'a \"b\"'"), "a \"b\"");
        assert_eq!(valor_os_release("\"a \\\"b\\\" \\$x \\n\""), "a \"b\" $x \\n");
        assert_eq!(valor_os_release("linuxmint"), "linuxmint");
        assert_eq!(valor_os_release("\""), "\"");
    }

    #[test]
    fn la_tabla_no_repite_y_trae_esta_mac() {
        let mut vistos = std::collections::HashSet::new();
        for (id, nombres, url) in modelos::MODELOS {
            assert!(vistos.insert(*id), "{id} repetido");
            assert!(!nombres.is_empty() && url.starts_with("https://support.apple.com/"));
        }
        let mini = modelos::MODELOS.iter().find(|m| m.0 == "Macmini6,1").unwrap();
        assert_eq!(mini.1, &["Mac mini (Late 2012)"]);
    }

    #[test]
    fn json_escapa() {
        assert_eq!(cadena("a\"b\\c\n\u{1}é"), "\"a\\\"b\\\\c\\n\\u0001é\"");
    }
}
