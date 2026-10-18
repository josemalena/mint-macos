//! mint-macos-equipo: qué equipo es y qué sistema corre, para About This Mac/PC.
//!
//! Lo corre al arrancar mint-macos-equipo.service (oneshot del sistema) y escribe
//! /run/mint-macos/equipo.json. Es el único programa que lee los datos del equipo
//! que no cambian con el sistema corriendo (regla de José, 18-10-2026): los demás
//! leen este archivo y no vuelven a leer /sys, /proc ni lspci.
//!
//! El archivo es 0640 root:users porque lleva el número de serie: lo leen las
//! personas de la máquina (el grupo users) y no los demonios (lightdm, etc.).
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
//!     serie             product_serial (solo root); null si es un relleno del fabricante
//!                       («To be filled by O.E.M.», «Default string»…)
//!     procesador        modelo, ghz, nucleos y texto («2.5 GHz Dual-Core Intel Core i5»),
//!                       de /proc/cpuinfo (src/procesador.rs)
//!     memoria           total (bytes), tipo, velocidad (MT/s, que la Mac llama MHz),
//!                       modulos, texto («16 GB 1333 MHz DDR3») y fuente: «smbios» (la
//!                       tabla DMI, solo root) o, si no se lee, «meminfo» con solo el total;
//!                       ranuras: [{etiqueta («BANK 0/DIMM0»), banco, tamano (null =
//!                       vacía), tipo, velocidad, fabricante (un nombre), fabricante_codigo
//!                       (el código JEDEC crudo, «0x859B»)}] en el orden de la tabla
//!     graficos          [{pci, fabricante, modelo, texto, fuente, vram}]: el nombre de
//!                       mercado de Mesa (Intel, src/gpus.rs) o de amdgpu.ids (AMD), si
//!                       no el de pci.ids; vram solo si el driver la da (src/graficos.rs)
//!     video             {decodifica: ["h264", "mpeg2", …]}: lo que la GPU decodifica por
//!                       VA-API (libva por DRM, src/video.rs); null sin GPU o sin driver
//!
//! Lo que no se puede leer va null, nunca "". Nada se adivina: un PC sin tabla lleva
//! lo que dice su DMI.
//!
//!     mint-macos-equipo                    escribe /run/mint-macos/equipo.json
//!     mint-macos-equipo --imprimir         lo escribe en la salida, sin tocar nada
//!     mint-macos-equipo --salida ARCHIVO   en otro archivo
//!     mint-macos-equipo --raiz DIR         lee DIR/sys, DIR/proc, DIR/etc/os-release y
//!                                          DIR/usr/share (para las pruebas)

mod gpus;
mod graficos;
mod memoria;
mod modelos;
mod procesador;
mod video;

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
    serie: Option<String>,
    procesador: Option<procesador::Procesador>,
    memoria: Option<(memoria::Memoria, &'static str)>,
    graficos: Vec<graficos::Grafico>,
    video: Option<Vec<&'static str>>,
}

/// Lo que ponen los fabricantes cuando no graban la serie: no es una serie.
fn serie_de_verdad(s: String) -> Option<String> {
    let l = s.to_ascii_lowercase();
    let relleno = ["to be filled by o.e.m.", "default string", "system serial number", "not specified", "not applicable", "none", "n/a", "0", "123456789", "chassis serial number"];
    if relleno.contains(&l.as_str()) || s.chars().all(|c| c == '0' || c == ' ' || c == 'x' || c == 'X') {
        None
    } else {
        Some(s)
    }
}

/// La memoria de SMBIOS; si la tabla no se lee, el total de /proc/meminfo (lo que ve
/// el núcleo, redondeado a GB al escribirlo), sin tipo ni velocidad.
fn leer_memoria(raiz: &Path) -> Option<(memoria::Memoria, &'static str)> {
    if let Some(m) = fs::read(raiz.join("sys/firmware/dmi/tables/DMI")).ok().and_then(|t| memoria::resumir(&memoria::modulos(&t), memoria::ranuras(&t))) {
        return Some((m, "smbios"));
    }
    let info = fs::read_to_string(raiz.join("proc/meminfo")).ok()?;
    let kb: u64 = info.lines().find_map(|l| l.strip_prefix("MemTotal:"))?.trim().trim_end_matches("kB").trim().parse().ok()?;
    let gb = ((kb as f64 / 1048576.0).round() as u64).max(1);
    Some((memoria::Memoria { total: gb << 30, tipo: None, velocidad: None, modulos: 0, ranuras: vec![] }, "meminfo"))
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
        serie: dmi(raiz, "product_serial").and_then(serie_de_verdad),
        procesador: fs::read_to_string(raiz.join("proc/cpuinfo")).ok().and_then(|c| {
            let base = fs::read_to_string(raiz.join("sys/devices/system/cpu/cpu0/cpufreq/base_frequency")).ok().and_then(|s| s.trim().parse().ok());
            procesador::leer(&c, base)
        }),
        memoria: leer_memoria(raiz),
        graficos: graficos::leer(raiz),
        // Con --raiz (las pruebas) no se le pregunta a la GPU de esta máquina.
        video: if raiz == Path::new("/") { nodo_render().and_then(|n| video::decodifica(&n)) } else { None },
    }
}

/// Al arrancar, el nodo de render puede llegar un poco después que el servicio (el
/// driver de la GPU lo crea udev): se espera hasta 10 s.
fn nodo_render() -> Option<PathBuf> {
    for _ in 0..20 {
        if let Some(n) = video::nodo(Path::new("/")) {
            return Some(n);
        }
        std::thread::sleep(std::time::Duration::from_millis(500));
    }
    None
}

fn json_video(v: &Option<Vec<&'static str>>) -> String {
    match v {
        None => "null".to_string(),
        Some(c) => format!("{{\"decodifica\": [{}]}}", c.iter().map(|x| cadena(x)).collect::<Vec<_>>().join(", ")),
    }
}

fn numero(n: Option<impl std::fmt::Display>) -> String {
    n.map(|v| v.to_string()).unwrap_or_else(|| "null".to_string())
}

fn json_procesador(p: &Option<procesador::Procesador>) -> String {
    match p {
        None => "null".to_string(),
        Some(p) => format!(
            "{{\n    \"modelo\": {},\n    \"ghz\": {},\n    \"nucleos\": {},\n    \"texto\": {}\n  }}",
            cadena(&p.modelo),
            numero(p.ghz.map(|g| format!("{g:.2}"))),
            numero(p.nucleos),
            cadena(&p.texto)
        ),
    }
}

fn json_memoria(m: &Option<(memoria::Memoria, &'static str)>) -> String {
    match m {
        None => "null".to_string(),
        Some((m, fuente)) => format!(
            "{{\n    \"total\": {},\n    \"tipo\": {},\n    \"velocidad\": {},\n    \"modulos\": {},\n    \"texto\": {},\n    \"fuente\": {},\n    \"ranuras\": {}\n  }}",
            m.total,
            opcional(&m.tipo.map(|t| t.to_string())),
            numero(m.velocidad),
            if m.modulos > 0 { m.modulos.to_string() } else { "null".to_string() },
            cadena(&memoria::texto(m)),
            cadena(fuente),
            json_ranuras(&m.ranuras)
        ),
    }
}

/// Las ranuras de memoria; [] si la fuente no las da (meminfo).
fn json_ranuras(r: &[memoria::Ranura]) -> String {
    if r.is_empty() {
        return "[]".to_string();
    }
    let filas: Vec<String> = r
        .iter()
        .map(|x| format!("\n      {{\"etiqueta\": {}, \"banco\": {}, \"tamano\": {}, \"tipo\": {}, \"velocidad\": {}, \"fabricante\": {}, \"fabricante_codigo\": {}}}", opcional(&x.etiqueta), opcional(&x.banco), numero(x.bytes), opcional(&x.tipo.map(String::from)), numero(x.velocidad), opcional(&x.fabricante), opcional(&x.fabricante_codigo)))
        .collect();
    format!("[{}\n    ]", filas.join(","))
}

fn json_graficos(g: &[graficos::Grafico]) -> String {
    if g.is_empty() {
        return "[]".to_string();
    }
    let filas: Vec<String> = g
        .iter()
        .map(|x| format!("\n    {{\"pci\": {}, \"fabricante\": {}, \"modelo\": {}, \"texto\": {}, \"fuente\": {}, \"vram\": {}}}", cadena(&x.pci), opcional(&x.fabricante), opcional(&x.modelo), cadena(&x.texto), cadena(x.fuente), numero(x.vram)))
        .collect();
    format!("[{}\n  ]", filas.join(","))
}

fn json(e: &Equipo) -> String {
    let nombres = match &e.nombres {
        Some(v) => format!("[{}]", v.iter().map(|s| cadena(s)).collect::<Vec<_>>().join(", ")),
        None => "null".to_string(),
    };
    let [id, nombre, version, texto] = &e.sistema;
    format!(
        "{{\n  \"version\": 1,\n  \"tipo\": {},\n  \"fabricante\": {},\n  \"identificador\": {},\n  \"nombre\": {},\n  \"nombres\": {},\n  \"fuente_nombre\": {},\n  \"version_producto\": {},\n  \"sistema\": {{\n    \"id\": {},\n    \"nombre\": {},\n    \"version\": {},\n    \"texto\": {}\n  }},\n  \"logo\": {},\n  \"logo_icono\": {},\n  \"serie\": {},\n  \"procesador\": {},\n  \"memoria\": {},\n  \"graficos\": {},\n  \"video\": {}\n}}\n",
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
        opcional(&e.serie),
        json_procesador(&e.procesador),
        json_memoria(&e.memoria),
        json_graficos(&e.graficos),
        json_video(&e.video),
    )
}

/// El gid del grupo users (100 en Debian), de /etc/group.
fn gid_users() -> Option<u32> {
    let g = fs::read_to_string("/etc/group").ok()?;
    g.lines().find_map(|l| {
        let mut c = l.split(':');
        (c.next()? == "users").then(|| c.nth(1)?.parse().ok()).flatten()
    })
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
    // Antes del rename: nunca hay un equipo.json con la serie y otro permiso.
    let gid = gid_users().ok_or_else(|| std::io::Error::other("no está el grupo users en /etc/group"))?;
    std::os::unix::fs::chown(&tmp, None, Some(gid))?;
    fs::set_permissions(&tmp, fs::Permissions::from_mode(0o640))?;
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
    fn rellenos_no_son_serie() {
        assert_eq!(serie_de_verdad("C07JD0ABDWYL".into()), Some("C07JD0ABDWYL".into()));
        for r in ["To be filled by O.E.M.", "Default string", "0000000000", "System Serial Number"] {
            assert_eq!(serie_de_verdad(r.into()), None, "{r}");
        }
    }

    #[test]
    fn json_escapa() {
        assert_eq!(cadena("a\"b\\c\n\u{1}é"), "\"a\\\"b\\\\c\\n\\u0001é\"");
    }
}
