//! Ayudante de root de Startup Disk (System Preferences).
//!
//! Reemplaza a settings/startup-disk/mint-macos-startup-disk (Python) con el mismo
//! comportamiento: lo corre pkexec (acción org.mintmacos.startupdisk.run) y lee el
//! menú de GRUB o cambia el arranque; nada más.
//!
//!     auth                 no hace nada (para pedir la clave y desbloquear el panel)
//!     efi-order XXXX       pone la entrada EFI XXXX primera en BootOrder
//!     efi-next XXXX        arranca con XXXX solo la próxima vez (BootNext)
//!     grub-list            JSON con las entradas de GRUB y la que está por defecto
//!     grub-default ID      grub-set-default ID (ID: «0», «1>2»…, una de grub-list)
//!     grub-enable-saved    GRUB_DEFAULT=saved en /etc/default/grub y update-grub
//!
//! Cada argumento se valida contra una lista cerrada antes de tocar nada. Los
//! programas (efibootmgr, grub-editenv, grub-set-default, update-grub) se buscan en
//! el PATH, como el Python: pkexec pone uno seguro.
//!
//! --raiz DIR (solo sin root, para las pruebas): no exige root y lee y escribe
//! DIR/boot/grub/grub.cfg y DIR/etc/default/grub. Con root «--raiz» es una orden
//! desconocida.
//!
//! Códigos de salida, los del Python: 77 sin root, 2 argumento no válido, 3
//! GRUB_DEFAULT no es «saved», 1 lo demás; si un programa falla, su propio código.
//! Donde el Python revienta con una excepción (falta grub.cfg, un programa que no
//! existe, texto que no es UTF-8) este sale con 1 y un mensaje corto.

use std::ffi::OsString;
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::process::{exit, Command};

/// El __doc__ del Python, que es lo que imprime sin argumentos.
const AYUDA: &str = "Ayudante de root de Startup Disk (System Preferences).

Lo corre pkexec (acción org.mintmacos.startupdisk.run, con clave de administrador)
y hace lo único que el panel no puede hacer como usuario: leer el menú de GRUB y
cambiar el arranque. Vive en /usr/libexec/mint-macos/ con dueño root: no se debe
correr una copia editable por el usuario.

    auth                         no hace nada (sirve para pedir la clave y desbloquear el panel)
    efi-order XXXX               pone la entrada EFI XXXX primera en BootOrder
    efi-next XXXX                arranca con XXXX solo la próxima vez (BootNext)
    grub-list                    JSON con las entradas de GRUB y la que está por defecto
    grub-default ID              grub-set-default ID (ID: «0», «1>2»…, una de grub-list)
    grub-enable-saved            pone GRUB_DEFAULT=saved en /etc/default/grub y corre update-grub

Cada argumento se valida contra una lista cerrada antes de tocar nada.
";

struct Rutas {
    grub_cfg: PathBuf,
    default_grub: PathBuf,
}

fn salir(msg: &str, codigo: i32) -> ! {
    eprintln!("{msg}");
    exit(codigo)
}

/// str.isspace() de Python (y \s de re): incluye \x1c-\x1f, que char::is_whitespace no.
fn es_espacio(c: char) -> bool {
    c.is_whitespace() || ('\u{1c}'..='\u{1f}').contains(&c)
}

/// str.strip() de Python.
fn strip(s: &str) -> &str {
    s.trim_matches(es_espacio)
}

/// str.splitlines() de Python (sin los finales): corta en \n, \r, \r\n, \v, \f,
/// \x1c, \x1d, \x1e, \x85, U+2028 y U+2029.
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

/// Los saltos de línea universales del modo texto de Python: \r\n y \r pasan a \n.
fn universal(s: &str) -> String {
    s.replace("\r\n", "\n").replace('\r', "\n")
}

/// Texto como lo da subprocess con text=True o open() en modo texto: UTF-8 estricto
/// (el Python revienta con UnicodeDecodeError) y saltos universales.
fn texto(bytes: Vec<u8>, de: &str) -> String {
    match String::from_utf8(bytes) {
        Ok(s) => universal(&s),
        Err(_) => salir(&format!("{de}: el texto no es UTF-8"), 1),
    }
}

/// Un argumento como lo ve sys.argv (surrogateescape) y lo escribe stderr
/// (backslashreplace): cada byte que no es UTF-8 sale como \udcXX.
fn como_python(a: &OsString) -> String {
    let mut b = a.as_bytes();
    let mut s = String::new();
    loop {
        match std::str::from_utf8(b) {
            Ok(v) => {
                s.push_str(v);
                return s;
            }
            Err(e) => {
                let (bien, resto) = b.split_at(e.valid_up_to());
                s.push_str(std::str::from_utf8(bien).unwrap());
                let malos = e.error_len().unwrap_or(resto.len());
                for x in &resto[..malos] {
                    s.push_str(&format!("\\udc{x:02x}"));
                }
                b = &resto[malos..];
            }
        }
    }
}

/// sys.exit(n) de Python con el código de un proceso: un número negativo (señal)
/// sale como 256 + n.
fn codigo_de(st: &std::process::ExitStatus) -> i32 {
    use std::os::unix::process::ExitStatusExt;
    match st.code() {
        Some(c) => c,
        None => (256 - st.signal().unwrap_or(1)) & 0xff,
    }
}

/// subprocess.run(cmd, capture_output=True, text=True): (código, stdout, stderr).
/// Si el programa no existe el Python revienta (FileNotFoundError): sale 1.
fn ejecutar(cmd: &[&str]) -> (std::process::ExitStatus, String, String) {
    match Command::new(cmd[0]).args(&cmd[1..]).output() {
        Ok(o) => (o.status, texto(o.stdout, cmd[0]), texto(o.stderr, cmd[0])),
        Err(e) => salir(&format!("{}: {e}", cmd[0]), 1),
    }
}

/// correr() del Python: si falla, sale con su mensaje y su código.
fn correr(cmd: &[&str]) -> String {
    let (st, out, err) = ejecutar(cmd);
    if !st.success() {
        let base = if !err.is_empty() { &err } else { &out };
        let msg = strip(base);
        let msg = if msg.is_empty() { format!("{} falló", cmd[0]) } else { msg.to_string() };
        salir(&msg, codigo_de(&st));
    }
    out
}

fn es_hex(c: u8) -> bool {
    c.is_ascii_hexdigit()
}

/// re.match(r"^…$") de Python: el $ también acepta un \n al final.
fn sin_salto_final(s: &str) -> &str {
    s.strip_suffix('\n').unwrap_or(s)
}

/// HEX4 = ^[0-9A-Fa-f]{4}$
fn hex4(s: &str) -> bool {
    let s = sin_salto_final(s).as_bytes();
    s.len() == 4 && s.iter().all(|&c| es_hex(c))
}

/// ID_GRUB = ^[0-9]+(>[0-9]+)*$
fn id_grub(s: &str) -> bool {
    sin_salto_final(s).split('>').all(|p| !p.is_empty() && p.bytes().all(|c| c.is_ascii_digit()))
}

/// La línea «BootOrder: 0001,0002» de efibootmgr, como lista.
fn efi_orden() -> Vec<String> {
    for linea in splitlines(&correr(&["efibootmgr"])) {
        if let Some(resto) = linea.strip_prefix("BootOrder:") {
            return strip(resto).split(',').filter(|x| !x.is_empty()).map(String::from).collect();
        }
    }
    Vec::new()
}

/// re.finditer(r"^Boot([0-9A-Fa-f]{4})\*?\s", salida, re.M): el número de cada
/// entrada, en mayúsculas. ^ con re.M es el principio o lo que sigue a un \n.
fn efi_entradas() -> Vec<String> {
    let salida = correr(&["efibootmgr"]);
    let mut out = Vec::new();
    let mut inicio = 0;
    loop {
        let r = &salida[inicio..];
        if let Some(resto) = r.strip_prefix("Boot") {
            let b = resto.as_bytes();
            if b.len() >= 4 && b[..4].iter().all(|&c| es_hex(c)) {
                let tras = &resto[4..];
                let espacio = |t: &str| t.chars().next().map(es_espacio).unwrap_or(false);
                if (tras.starts_with('*') && espacio(&tras[1..])) || espacio(tras) {
                    out.push(resto[..4].to_ascii_uppercase());
                }
            }
        }
        match r.find('\n') {
            Some(i) => inicio += i + 1,
            None => break,
        }
    }
    out
}

/// «menuentry 'Título'» o «submenu "Título"» al principio de la línea (con espacios
/// delante): (es submenu, título).
fn entrada_de(linea: &str) -> Option<(bool, &str)> {
    let l = linea.trim_start_matches(es_espacio);
    let (submenu, resto) = if let Some(r) = l.strip_prefix("menuentry") {
        (false, r)
    } else if let Some(r) = l.strip_prefix("submenu") {
        (true, r)
    } else {
        return None;
    };
    let tras = resto.trim_start_matches(es_espacio);
    if tras.len() == resto.len() {
        return None; // \s+: hace falta al menos un espacio
    }
    let comilla = tras.chars().next()?;
    if comilla != '\'' && comilla != '"' {
        return None;
    }
    let dentro = &tras[1..];
    let fin = dentro.find(comilla)?;
    Some((submenu, &dentro[..fin]))
}

/// [(id, título)] del grub.cfg: «0», «1>0»… y «Advanced options > …».
fn grub_entradas(r: &Rutas) -> Vec<(String, String)> {
    let bytes = match fs::read(&r.grub_cfg) {
        Ok(b) => b,
        Err(e) => salir(&format!("{}: {e}", r.grub_cfg.display()), 1),
    };
    // errors="replace": lo que no es UTF-8 pasa a U+FFFD, como from_utf8_lossy.
    let texto = String::from_utf8_lossy(&bytes);
    let mut out = Vec::new();
    let mut idx: Vec<usize> = vec![0];
    let mut pila: Vec<&str> = Vec::new();
    for linea in splitlines(&texto) {
        if let Some((submenu, titulo)) = entrada_de(linea) {
            if submenu {
                pila.push(titulo);
                idx.push(0);
            } else {
                let ident = idx.iter().map(|i| i.to_string()).collect::<Vec<_>>().join(">");
                let mut partes = pila.clone();
                partes.push(titulo);
                out.push((ident, partes.join(" > ")));
                *idx.last_mut().unwrap() += 1;
            }
            continue;
        }
        // el cierre de un submenu: una llave sola en la columna 0
        if linea.strip_prefix('}').map(|r| r.chars().all(es_espacio)).unwrap_or(false) && idx.len() > 1 {
            pila.pop();
            idx.pop();
            *idx.last_mut().unwrap() += 1;
        }
    }
    out
}

/// El valor de CLAVE= en /etc/default/grub, sin comillas; "" si no se puede leer.
fn grub_valor(r: &Rutas, clave: &str) -> String {
    let bytes = match fs::read(&r.default_grub) {
        Ok(b) => b,
        Err(_) => return String::new(),
    };
    let texto = texto(bytes, &r.default_grub.display().to_string());
    let prefijo = format!("{clave}=");
    for linea in texto.split_inclusive('\n') {
        if let Some(v) = strip(linea).strip_prefix(prefijo.as_str()) {
            return v.trim_matches(|c| c == '"' || c == '\'').to_string();
        }
    }
    String::new()
}

/// json.dumps de una cadena (ensure_ascii: todo lo que no sea de espacio a ~ se escapa).
fn json(s: &str) -> String {
    let mut o = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            '\r' => o.push_str("\\r"),
            '\t' => o.push_str("\\t"),
            '\u{08}' => o.push_str("\\b"),
            '\u{0c}' => o.push_str("\\f"),
            ' '..='~' => o.push(c),
            _ => {
                let mut u = [0u16; 2];
                for x in c.encode_utf16(&mut u) {
                    o.push_str(&format!("\\u{x:04x}"));
                }
            }
        }
    }
    o.push('"');
    o
}

fn euid() -> Option<u32> {
    let st = fs::read_to_string("/proc/self/status").ok()?;
    let l = st.lines().find(|l| l.starts_with("Uid:"))?;
    l.split_whitespace().nth(2)?.parse().ok()
}

/// shutil.copy2: contenido, permisos y fechas.
fn copiar_con_fechas(de: &Path, a: &Path) -> std::io::Result<()> {
    fs::copy(de, a)?;
    let m = fs::metadata(de)?;
    let f = fs::OpenOptions::new().write(true).open(a)?;
    f.set_times(fs::FileTimes::new().set_accessed(m.accessed()?).set_modified(m.modified()?))
}

fn main() {
    let mut args: Vec<OsString> = std::env::args_os().skip(1).collect();
    let mut raiz = PathBuf::from("/");
    if euid() != Some(0) {
        if args.len() >= 2 && args[0] == "--raiz" {
            raiz = PathBuf::from(args.remove(1));
            args.remove(0);
        } else {
            salir("Solo root (lo corre pkexec).", 77);
        }
    }
    let r = Rutas { grub_cfg: raiz.join("boot/grub/grub.cfg"), default_grub: raiz.join("etc/default/grub") };
    let a: Vec<String> = args.iter().map(como_python).collect();
    if a.is_empty() {
        salir(AYUDA, 1);
    }
    match a[0].as_str() {
        "auth" => {}
        cmd @ ("efi-order" | "efi-next") => {
            if a.len() != 2 || !hex4(&a[1]) || !efi_entradas().contains(&a[1].to_uppercase()) {
                salir("Entrada EFI no válida.", 2);
            }
            let ident = a[1].to_uppercase();
            if cmd == "efi-next" {
                correr(&["efibootmgr", "-n", &ident]);
            } else {
                let mut orden = vec![ident.clone()];
                orden.extend(efi_orden().into_iter().filter(|x| x.to_uppercase() != ident));
                correr(&["efibootmgr", "-o", &orden.join(",")]);
            }
        }
        "grub-list" => {
            let (_, out, _) = ejecutar(&["grub-editenv", "list"]);
            let mut saved = "";
            for l in splitlines(&out) {
                if let Some(v) = l.strip_prefix("saved_entry=") {
                    saved = v;
                }
            }
            let entradas: Vec<String> =
                grub_entradas(&r).iter().map(|(id, t)| format!("{{\"id\": {}, \"title\": {}}}", json(id), json(t))).collect();
            println!(
                "{{\"entries\": [{}], \"default\": {}, \"saved_entry\": {}}}",
                entradas.join(", "),
                json(&grub_valor(&r, "GRUB_DEFAULT")),
                json(saved)
            );
        }
        "grub-default" => {
            if a.len() != 2 || !id_grub(&a[1]) || !grub_entradas(&r).iter().any(|(id, _)| *id == a[1]) {
                salir("Entrada de GRUB no válida.", 2);
            }
            if grub_valor(&r, "GRUB_DEFAULT") != "saved" {
                salir("GRUB_DEFAULT no es «saved»: usa grub-enable-saved primero.", 3);
            }
            correr(&["grub-set-default", &a[1]]);
        }
        "grub-enable-saved" => {
            if grub_valor(&r, "GRUB_DEFAULT") == "saved" {
                return;
            }
            let mut respaldo = r.default_grub.clone().into_os_string();
            respaldo.push(".mint-macos.bak");
            let respaldo = PathBuf::from(respaldo);
            if !respaldo.exists() {
                if let Err(e) = copiar_con_fechas(&r.default_grub, &respaldo) {
                    salir(&format!("{}: {e}", r.default_grub.display()), 1);
                }
            }
            let bytes = fs::read(&r.default_grub).unwrap_or_else(|e| salir(&format!("{}: {e}", r.default_grub.display()), 1));
            let viejo = texto(bytes, &r.default_grub.display().to_string());
            // re.sub(r"^GRUB_DEFAULT=.*$", "GRUB_DEFAULT=saved", texto, flags=re.M):
            // toda línea que empiece así, en la columna 0.
            let nuevo = if viejo.split('\n').any(|l| l.starts_with("GRUB_DEFAULT=")) {
                viejo
                    .split('\n')
                    .map(|l| if l.starts_with("GRUB_DEFAULT=") { "GRUB_DEFAULT=saved" } else { l })
                    .collect::<Vec<_>>()
                    .join("\n")
            } else {
                format!("{viejo}\nGRUB_DEFAULT=saved\n")
            };
            // Como el Python: se reescribe el mismo archivo (mismo inodo y permisos).
            if let Err(e) = fs::write(&r.default_grub, nuevo) {
                salir(&format!("{}: {e}", r.default_grub.display()), 1);
            }
            correr(&["update-grub"]);
        }
        cmd => salir(&format!("Orden desconocida: {cmd}"), 2),
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn ids_como_la_regex() {
        assert!(id_grub("0") && id_grub("1>2") && id_grub("10>0>3") && id_grub("0\n"));
        assert!(!id_grub("") && !id_grub(">1") && !id_grub("1>") && !id_grub("1>>2") && !id_grub("a") && !id_grub("1\n\n"));
        assert!(hex4("00a1") && hex4("00A1\n") && !hex4("0001x") && !hex4("001"));
    }

    #[test]
    fn entradas_de_grub() {
        assert_eq!(entrada_de("menuentry 'Linux Mint' --class mint {"), Some((false, "Linux Mint")));
        assert_eq!(entrada_de("\tsubmenu \"Adv'anced\" {"), Some((true, "Adv'anced")));
        assert_eq!(entrada_de("menuentry'x'"), None);
        assert_eq!(entrada_de("menuentry 'sin cierre"), None);
    }

    #[test]
    fn json_como_python() {
        assert_eq!(json("a\"b\\ñ\u{7f}\u{1f600}"), "\"a\\\"b\\\\\\u00f1\\u007f\\ud83d\\ude00\"");
    }
}
