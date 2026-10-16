//! Ayudante de root de Sharing (System Preferences).
//!
//! Reemplaza a settings/sharing/mint-macos-sharing (Python) con el mismo comportamiento:
//! lo corre pkexec (acción org.mintmacos.sharing.run) y enciende o apaga los servicios
//! de la lista cerrada de abajo; nada más.
//!
//!     remote-login on|off      ssh.socket y ssh.service
//!     file-sharing  on|off     smbd (y nmbd si existe)
//!     printer-sharing on|off   «cupsctl --share-printers» / «--no-share-printers»
//!
//! Cada argumento se valida contra esa lista antes de tocar nada. Los programas
//! (systemctl, cupsctl) se buscan en el PATH, como el Python: pkexec pone uno seguro.
//!
//! --probar (solo sin root): dice qué correría, sin correr systemctl enable/disable ni
//! cupsctl (sí consulta «systemctl cat» para saber qué unidades existen).
//!
//! Códigos de salida: 2 argumentos, 3 el servicio no está instalado; si un programa
//! falla, su propio código (como el Python).

use std::process::{exit, Command};

fn salir(msg: &str, codigo: i32) -> ! {
    eprintln!("{msg}");
    exit(codigo)
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

/// Corre un programa; si falla y no se tolera, sale con su mensaje y su código.
fn correr(cmd: &[&str], tolerar: bool, probar: bool) -> bool {
    if probar && !(cmd.len() >= 2 && cmd[0] == "systemctl" && cmd[1] == "cat") {
        println!("{}", cmd.join(" "));
        return true;
    }
    match Command::new(cmd[0]).args(&cmd[1..]).output() {
        Ok(o) => {
            if !o.status.success() && !tolerar {
                let err = String::from_utf8_lossy(&o.stderr);
                let out = String::from_utf8_lossy(&o.stdout);
                // (r.stderr or r.stdout).strip() or f"{cmd[0]} falló"
                let base = if !err.is_empty() { err } else { out };
                let msg = base.trim();
                let msg = if msg.is_empty() { format!("{} falló", cmd[0]) } else { msg.to_string() };
                salir(&msg, codigo_de(&o.status));
            }
            o.status.success()
        }
        Err(e) => {
            if tolerar {
                return false;
            }
            // El Python revienta con FileNotFoundError: sale 1.
            salir(&format!("{}: {e}", cmd[0]), 1)
        }
    }
}

fn existe(unidad: &str) -> bool {
    correr(&["systemctl", "cat", unidad], true, false)
}

fn euid() -> Option<u32> {
    let st = std::fs::read_to_string("/proc/self/status").ok()?;
    let l = st.lines().find(|l| l.starts_with("Uid:"))?;
    l.split_whitespace().nth(2)?.parse().ok()
}

fn repr(s: &str) -> String {
    let comilla = if s.contains('\'') && !s.contains('"') { '"' } else { '\'' };
    let mut r = String::from(comilla);
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

fn main() {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let mut probar = false;
    if args.first().map(|a| a == "--probar").unwrap_or(false) && euid() != Some(0) {
        probar = true;
        args.remove(0);
    }
    if args.len() != 2 || !(args[1] == "on" || args[1] == "off") {
        salir("uso: mint-macos-sharing remote-login|file-sharing|printer-sharing on|off", 2);
    }
    let (que, estado) = (args[0].as_str(), args[1] == "on");
    if que == "printer-sharing" {
        correr(&["cupsctl", if estado { "--share-printers" } else { "--no-share-printers" }], false, probar);
        return;
    }
    let servicios: &[&str] = match que {
        "remote-login" => &["ssh.socket", "ssh.service"],
        "file-sharing" => &["smbd.service", "nmbd.service"],
        _ => salir(&format!("Servicio no válido: {}", repr(que)), 2),
    };
    let unidades: Vec<&str> = servicios.iter().copied().filter(|u| existe(u)).collect();
    if unidades.is_empty() {
        salir("Ese servicio no está instalado en esta computadora.", 3);
    }
    if estado {
        // Con ssh se enciende el socket (lo que usa Ubuntu/Mint); smbd se enciende tal cual.
        let sockets: Vec<&str> = unidades.iter().copied().filter(|u| u.ends_with(".socket")).collect();
        let principales = if sockets.is_empty() { unidades } else { sockets };
        let mut cmd = vec!["systemctl", "enable", "--now"];
        cmd.extend(principales);
        correr(&cmd, false, probar);
    } else {
        let mut cmd = vec!["systemctl", "disable", "--now"];
        cmd.extend(unidades);
        correr(&cmd, false, probar);
    }
}
