//! Ayudante de root de Keyboard ▸ Modifier Keys (System Preferences).
//!
//! Reemplaza a settings/modifier-keys/mint-macos-modifier-keys (Python) con el mismo
//! comportamiento, byte a byte: lo corre pkexec (acción org.mintmacos.modifierkeys.run),
//! recibe cuatro argumentos TECLA=ACCIÓN y reescribe, en /etc/keyd/default.conf, un
//! bloque [main] delimitado por marcas; el resto del archivo no se toca.
//!
//!     capslock=ACCIÓN  control=ACCIÓN  option=ACCIÓN  command=ACCIÓN
//!     ACCIÓN: capslock | control | option | command | escape | none
//!
//! Cada argumento se valida contra esa lista cerrada. Antes de dejar el archivo nuevo se
//! comprueba con `keyd check`, y si keyd no recarga se devuelve el anterior.
//!
//! Para probar SIN root (se rechazan si el usuario efectivo es root, para que nadie
//! los use a través de pkexec):
//!     --probar          escribe en la salida el archivo que quedaría; no toca nada
//!     --raiz DIR        trabaja sobre DIR/etc/keyd/default.conf
//!     MINT_MACOS_KEYD   el keyd a usar (uno de mentira en las pruebas)
//!
//! Códigos de salida (los mismos del Python): 2 argumentos, 3 el archivo no se puede
//! tocar con seguridad, 4 keyd rechaza la configuración, 5 keyd no recargó (se devolvió
//! la anterior), 1 cualquier otro error.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{exit, Command};

const INICIO: &str = "# >>> mint-macos modifier-keys (lo escribe System Preferences; no lo edites a mano)";
const FIN: &str = "# <<< mint-macos modifier-keys";
const TECLAS: [&str; 4] = ["capslock", "control", "option", "command"];
const ACCIONES: [&str; 6] = ["capslock", "control", "option", "command", "escape", "none"];

/// Las teclas físicas de cada nombre en keyd.
fn fisicas(tecla: &str) -> &'static [&'static str] {
    match tecla {
        "capslock" => &["capslock"],
        "control" => &["leftcontrol", "rightcontrol"],
        "option" => &["leftalt", "rightalt"],
        _ => &["leftmeta", "rightmeta"],
    }
}

/// Lo que se escribe en keyd para cada acción.
fn destino(accion: &str) -> &'static str {
    match accion {
        "capslock" => "capslock",
        "control" => "layer(control)",
        "option" => "layer(alt)",
        "command" => "layer(meta)",
        "escape" => "esc",
        _ => "noop",
    }
}

fn salir(msg: &str, codigo: i32) -> ! {
    eprintln!("{msg}");
    exit(codigo)
}

/// str.isspace() de Python: incluye \x1c-\x1f, que char::is_whitespace no.
fn es_espacio(c: char) -> bool {
    c.is_whitespace() || ('\u{1c}'..='\u{1f}').contains(&c)
}

/// str.strip() de Python.
fn strip(s: &str) -> &str {
    s.trim_matches(es_espacio)
}

/// str.splitlines() de Python (sin los finales): corta en \n, \r, \r\n, \v, \f,
/// \x1c, \x1d, \x1e, \x85,   y  .
fn splitlines(s: &str) -> Vec<&str> {
    let mut lineas = Vec::new();
    let mut inicio = 0;
    let mut it = s.char_indices().peekable();
    while let Some((i, c)) = it.next() {
        let corte = matches!(c, '\n' | '\r' | '\u{0b}' | '\u{0c}' | '\u{1c}' | '\u{1d}' | '\u{1e}' | '\u{85}' | '\u{2028}' | '\u{2029}');
        if !corte {
            continue;
        }
        lineas.push(&s[inicio..i]);
        let mut fin = i + c.len_utf8();
        if c == '\r' {
            if let Some(&(j, '\n')) = it.peek() {
                it.next();
                fin = j + 1;
            }
        }
        inicio = fin;
    }
    if inicio < s.len() {
        lineas.push(&s[inicio..]);
    }
    lineas
}

/// {tecla: acción} de los argumentos TECLA=ACCIÓN; cualquier otra cosa se rechaza.
fn validar(args: &[String]) -> [String; 4] {
    let mut elegido: [Option<String>; 4] = Default::default();
    for a in args {
        let partes: Vec<&str> = a.splitn(2, '=').collect();
        let ok = partes.len() == 2
            && !partes[0].is_empty()
            && !partes[1].is_empty()
            && partes[0].bytes().all(|b| b.is_ascii_lowercase())
            && partes[1].bytes().all(|b| b.is_ascii_lowercase());
        let pos = if ok { TECLAS.iter().position(|t| *t == partes[0]) } else { None };
        match pos {
            Some(p) if ACCIONES.contains(&partes[1]) && elegido[p].is_none() => elegido[p] = Some(partes[1].to_string()),
            _ => salir(&format!("Argumento no válido: {}", repr(a)), 2),
        }
    }
    if elegido.iter().any(|e| e.is_none()) {
        salir("Faltan teclas: se piden capslock, control, option y command.", 2);
    }
    elegido.map(|e| e.unwrap())
}

/// repr() de Python para el mensaje de error (comillas simples, como el Python).
fn repr(s: &str) -> String {
    let comilla = if s.contains('\'') && !s.contains('"') { '"' } else { '\'' };
    let mut r = String::new();
    r.push(comilla);
    for c in s.chars() {
        match c {
            '\\' => r.push_str("\\\\"),
            '\n' => r.push_str("\\n"),
            '\r' => r.push_str("\\r"),
            '\t' => r.push_str("\\t"),
            c if c == comilla => {
                r.push('\\');
                r.push(c)
            }
            c if (c as u32) < 0x20 || c as u32 == 0x7f => r.push_str(&format!("\\x{:02x}", c as u32)),
            c => r.push(c),
        }
    }
    r.push(comilla);
    r
}

/// Las líneas del bloque: un comentario por tecla (para que el panel lo lea) y el [main].
fn bloque(elegido: &[String; 4]) -> Vec<String> {
    let mut lineas = vec![INICIO.to_string()];
    for (i, t) in TECLAS.iter().enumerate() {
        lineas.push(format!("# {t} = {}", elegido[i]));
    }
    let mut reglas = Vec::new();
    for (i, tecla) in TECLAS.iter().enumerate() {
        if elegido[i] == *tecla {
            continue;
        }
        for f in fisicas(tecla) {
            reglas.push(format!("{f} = {}", destino(&elegido[i])));
        }
    }
    if !reglas.is_empty() {
        lineas.push("[main]".to_string());
        lineas.extend(reglas);
    }
    lineas.push(FIN.to_string());
    lineas
}

/// El archivo sin el bloque anterior y con el nuevo, antes de la primera capa (tras [ids]).
fn reescribir(texto: &str, elegido: &[String; 4]) -> String {
    let mut fuera: Vec<String> = Vec::new();
    let (mut dentro, mut tras_bloque) = (false, false);
    for l in splitlines(texto) {
        if strip(l) == INICIO {
            dentro = true;
            continue;
        }
        if dentro {
            if strip(l) == FIN {
                dentro = false;
                tras_bloque = true;
            }
            continue;
        }
        if tras_bloque && l.is_empty() {
            tras_bloque = false; // la línea en blanco que puso el propio bloque
            continue;
        }
        tras_bloque = false;
        fuera.push(l.to_string());
    }
    if dentro {
        salir("El bloque de mint-macos está sin cerrar en keyd: no toco nada.", 3);
    }
    let nuevo = bloque(elegido);
    if nuevo.iter().any(|l| l == "[main]") && fuera.iter().any(|l| strip(l) == "[main]") {
        salir("keyd ya tiene una sección [main] propia: hay que unirla a mano antes de usar este panel.", 3);
    }
    // Se inserta justo antes de la primera sección que no es [ids] (la primera capa).
    let mut pos = None;
    let mut en_ids = false;
    for (i, l) in fuera.iter().enumerate() {
        let s = strip(l);
        if s == "[ids]" {
            en_ids = true;
        } else if s.starts_with('[') && s.ends_with(']') && en_ids {
            pos = Some(i);
            break;
        }
    }
    let pos = pos.unwrap_or(fuera.len());
    let mut salida: Vec<String> = fuera[..pos].to_vec();
    salida.extend(nuevo);
    salida.push(String::new());
    salida.extend_from_slice(&fuera[pos..]);
    let mut texto = salida.join("\n").trim_end_matches('\n').to_string();
    texto.push('\n');
    texto
}

/// Usuario efectivo, de /proc/self/status (sin crates).
fn euid() -> Option<u32> {
    let st = fs::read_to_string("/proc/self/status").ok()?;
    let l = st.lines().find(|l| l.starts_with("Uid:"))?;
    l.split_whitespace().nth(2)?.parse().ok()
}

fn keyd(args: &[&str], prueba: bool) -> (bool, String) {
    let programa = if prueba { std::env::var("MINT_MACOS_KEYD").unwrap_or_else(|_| "keyd".into()) } else { "keyd".into() };
    match Command::new(&programa).args(args).output() {
        Ok(o) => {
            let mut t = String::from_utf8_lossy(&o.stdout).into_owned();
            t.push_str(&String::from_utf8_lossy(&o.stderr));
            (o.status.success(), t.trim().to_string())
        }
        Err(e) => (false, e.to_string()),
    }
}

/// Un temporal nuevo junto al archivo (create_new: nunca pisa uno que ya exista).
fn temporal(dir: &Path) -> (PathBuf, fs::File) {
    let pid = std::process::id();
    for n in 0..1000u32 {
        let ruta = dir.join(format!(".mint-macos-{pid}-{n}.conf"));
        if let Ok(f) = fs::OpenOptions::new().write(true).create_new(true).open(&ruta) {
            return (ruta, f);
        }
    }
    salir("No pude crear el archivo temporal en el directorio de keyd.", 1)
}

fn copiar_con_fechas(de: &Path, a: &Path) -> std::io::Result<()> {
    // shutil.copy2: contenido, permisos y fechas.
    fs::copy(de, a)?;
    let m = fs::metadata(de)?;
    let f = fs::OpenOptions::new().write(true).open(a)?;
    f.set_times(fs::FileTimes::new().set_accessed(m.accessed()?).set_modified(m.modified()?))
}

fn main() {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let mut probar = false;
    let mut raiz: Option<String> = None;
    // Las opciones de prueba solo valen sin root: a través de pkexec no se aceptan.
    if args.first().map(|a| a.starts_with("--")).unwrap_or(false) {
        if euid() != Some(0) {
            while let Some(a) = args.first().cloned() {
                if a == "--probar" {
                    probar = true;
                    args.remove(0);
                } else if a == "--raiz" && args.len() >= 2 {
                    raiz = Some(args[1].clone());
                    args.drain(..2);
                } else {
                    break;
                }
            }
        }
    }
    if args.len() != 4 {
        salir("uso: mint-macos-modifier-keys capslock=… control=… option=… command=…", 2);
    }
    let elegido = validar(&args);
    let dir = PathBuf::from(raiz.as_deref().unwrap_or("/")).join("etc/keyd");
    let conf = dir.join("default.conf");
    let respaldo = dir.join("default.conf.mint-macos.bak");
    let original = match fs::read(&conf) {
        // open() de Python en modo texto: \r\n y \r se leen como \n (y así se
        // devuelve el archivo si keyd no recarga).
        Ok(b) => match String::from_utf8(b) {
            Ok(s) => s.replace("\r\n", "\n").replace('\r', "\n"),
            Err(_) => salir(&format!("{} no es UTF-8: no toco nada.", conf.display()), 1),
        },
        Err(e) => salir(&format!("No puedo leer {}: {e}", conf.display()), 1),
    };
    let nuevo = reescribir(&original, &elegido);
    if probar {
        print!("{nuevo}");
        return;
    }
    let prueba = raiz.is_some();
    let (tmp, mut f) = temporal(&dir);
    let limpiar = |t: &Path| {
        let _ = fs::remove_file(t);
    };
    if f.write_all(nuevo.as_bytes()).and_then(|_| f.sync_all()).is_err() {
        limpiar(&tmp);
        salir("No pude escribir el archivo temporal.", 1);
    }
    drop(f);
    use std::os::unix::fs::PermissionsExt;
    let _ = fs::set_permissions(&tmp, fs::Permissions::from_mode(0o644));
    let (ok, salida) = keyd(&["check", &tmp.to_string_lossy()], prueba);
    if !ok {
        limpiar(&tmp);
        salir(&format!("keyd rechaza la configuración nueva: {salida}"), 4);
    }
    if !respaldo.exists() && copiar_con_fechas(&conf, &respaldo).is_err() {
        limpiar(&tmp);
        salir("No pude guardar el respaldo de keyd.", 1);
    }
    if fs::rename(&tmp, &conf).is_err() {
        limpiar(&tmp);
        salir("No pude dejar el archivo nuevo en su lugar.", 1);
    }
    let (ok, salida) = keyd(&["reload"], prueba);
    if !ok {
        let _ = fs::write(&conf, original.as_bytes());
        let _ = keyd(&["reload"], prueba);
        salir(&format!("keyd no recargó; se devolvió la configuración anterior: {salida}"), 5);
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    fn todo(c: &str, ct: &str, o: &str, cm: &str) -> [String; 4] {
        [c.into(), ct.into(), o.into(), cm.into()]
    }

    #[test]
    fn lineas_como_python() {
        assert_eq!(splitlines("a\r\nb\rc\n\nd"), vec!["a", "b", "c", "", "d"]);
        assert_eq!(splitlines("a\n"), vec!["a"]);
        assert_eq!(strip("\x1c [ids] \t"), "[ids]");
    }

    #[test]
    fn bloque_antes_de_la_primera_capa() {
        let t = "[ids]\n*\n\n[meta]\nc = C-c\n";
        let r = reescribir(t, &todo("escape", "control", "option", "command"));
        assert!(r.starts_with("[ids]\n*\n\n# >>> mint-macos"));
        assert!(r.contains("[main]\ncapslock = esc\n# <<< mint-macos modifier-keys\n\n[meta]"));
    }

    #[test]
    fn por_defecto_no_hay_main() {
        let r = reescribir("[ids]\n*\n", &todo("capslock", "control", "option", "command"));
        assert!(!r.contains("[main]"));
    }
}
