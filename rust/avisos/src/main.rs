//! mint-macos-avisos: los informes de System Reports (mintreport) como notificaciones.
//!
//! Reemplaza el ícono de mintreport-tray en la barra (José, 18-10-2026). Los chequeos
//! son los de Mint: un sondeo corto en Python (`python3 -I`) importa su
//! `common.InfoReportContainer` y llama a `is_pertinent()` de cada informe de
//! /usr/share/linuxmint/mintreport/reports, como hace la bandeja. Nada se copia de su
//! lógica; si Mint agrega o cambia un informe, aquí sale solo.
//!
//! Como la bandeja: una ronda al empezar la sesión y otra cada `autorefresh-seconds`
//! (com.linuxmint.report) si `autorefresh` está encendido; los uuid de
//! `ignored-reports` (la lista del botón Ignore de System Reports) ni se consultan.
//!
//! Por cada informe que aplica y no se avisó, una notificación (org.freedesktop.
//! Notifications) con «Show», que abre `mintreport --reports`, e «Ignore», que lo
//! agrega a `ignored-reports` igual que el botón de Mint. Los avisados van en
//! $XDG_STATE_HOME/mint-macos/avisos-mint; un uuid sale de ahí cuando deja de
//! aplicar, para que vuelva a avisar si algún día aplica otra vez.
//!
//! El ícono «monitor» de la bandeja (Timeshift o actualizaciones automáticas
//! corriendo) no se reemplaza: la Mac no tiene nada así.
//!
//!     mint-macos-avisos                  el servicio (avisos.service)
//!     mint-macos-avisos --espera SEG     antes de la primera ronda (45 por defecto)
//!     mint-macos-avisos --una-vez SEG    una ronda y, al terminarla, SEG más para las
//!                                        acciones; después sale
//!
//! MINT_MACOS_AVISOS_INFORMES=DIR cambia la carpeta de informes (solo las pruebas).

use std::collections::{BTreeSet, HashMap};
use std::fs;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use zbus::blocking::{Connection, MessageIterator};
use zbus::message::Type as TipoMensaje;
use zbus::zvariant::Value;
use zbus::MatchRule;

const INFORMES: &str = "/usr/share/linuxmint/mintreport/reports";
const ESQUEMA: &str = "com.linuxmint.report";

/// El sondeo: carga cada informe con el cargador de Mint y dice cuáles aplican.
/// Salida, una línea por informe: «1\tuuid\ttítulo\tícono» o «0\tuuid». Los que
/// fallan van a stderr y no salen (como en la bandeja, que los salta).
const SONDEO: &str = r#"
import os, sys
sys.path.insert(0, "/usr/lib/linuxmint/mintreport")
from common import InfoReportContainer
carpeta, ignorados = sys.argv[1], set(sys.argv[2:])
limpio = lambda s: " ".join(str(s).split())
for n in sorted(os.listdir(carpeta)):
    uuid = n.split("_")[-1]
    if uuid in ignorados:
        continue
    try:
        r = InfoReportContainer(uuid, os.path.join(carpeta, n)).instance
        if r.is_pertinent():
            print("1\t%s\t%s\t%s" % (uuid, limpio(getattr(r, "title", "")), limpio(getattr(r, "icon", ""))), flush=True)
        else:
            print("0\t%s" % uuid, flush=True)
    except Exception as e:
        print("informe %s: %s" % (n, e), file=sys.stderr)
"#;

#[derive(Debug, PartialEq)]
struct Informe {
    uuid: String,
    aplica: bool,
    titulo: String,
    icono: String,
}

fn registrar(m: &str) {
    eprintln!("mint-macos-avisos: {m}");
}

// --- gsettings ----------------------------------------------------------------

fn gsettings_get(clave: &str) -> Option<String> {
    let o = Command::new("gsettings").args(["get", ESQUEMA, clave]).stderr(Stdio::null()).output().ok()?;
    o.status.success().then(|| String::from_utf8_lossy(&o.stdout).trim().to_string())
}

/// Un `as` de GVariant en texto: «['a', 'b']» o «@as []».
fn leer_strv(t: &str) -> Vec<String> {
    let t = t.trim().trim_start_matches("@as").trim();
    let mut out = Vec::new();
    let mut it = t.chars().peekable();
    while let Some(c) = it.next() {
        if c != '\'' && c != '"' {
            continue;
        }
        let q = c;
        let mut s = String::new();
        while let Some(d) = it.next() {
            match d {
                '\\' => {
                    if let Some(e) = it.next() {
                        s.push(e);
                    }
                }
                d if d == q => break,
                d => s.push(d),
            }
        }
        out.push(s);
    }
    out
}

fn escribir_strv(v: &[String]) -> String {
    let p: Vec<String> = v.iter().map(|s| format!("'{}'", s.replace('\\', "\\\\").replace('\'', "\\'"))).collect();
    format!("[{}]", p.join(", "))
}

fn ignorados() -> Vec<String> {
    gsettings_get("ignored-reports").map(|t| leer_strv(&t)).unwrap_or_default()
}

/// Lo mismo que el botón Ignore de System Reports: el uuid al final de la lista.
fn ignorar(uuid: &str) {
    let mut v = ignorados();
    if v.iter().any(|u| u == uuid) {
        return;
    }
    v.push(uuid.to_string());
    let ok = Command::new("gsettings").args(["set", ESQUEMA, "ignored-reports", &escribir_strv(&v)]).status().map(|s| s.success()).unwrap_or(false);
    if !ok {
        registrar(&format!("no pude agregar {uuid} a ignored-reports"));
    }
}

/// Cada cuánto, como la bandeja: None si autorefresh está apagado.
fn intervalo() -> Option<Duration> {
    if gsettings_get("autorefresh").as_deref() == Some("false") {
        return None;
    }
    let s = gsettings_get("autorefresh-seconds").and_then(|t| t.rsplit(' ').next().and_then(|n| n.parse::<u64>().ok())).unwrap_or(86400);
    Some(Duration::from_secs(s.max(60)))
}

// --- el sondeo y el estado ----------------------------------------------------

fn leer_sondeo(salida: &str) -> Vec<Informe> {
    salida
        .lines()
        .filter_map(|l| {
            let c: Vec<&str> = l.split('\t').collect();
            match c.as_slice() {
                ["1", uuid, titulo, icono] => Some(Informe { uuid: uuid.to_string(), aplica: true, titulo: titulo.to_string(), icono: icono.to_string() }),
                ["0", uuid] => Some(Informe { uuid: uuid.to_string(), aplica: false, titulo: String::new(), icono: String::new() }),
                _ => None,
            }
        })
        .filter(|i| !i.uuid.is_empty())
        .collect()
}

fn sondear(ign: &[String]) -> Vec<Informe> {
    let carpeta = std::env::var("MINT_MACOS_AVISOS_INFORMES").unwrap_or_else(|_| INFORMES.to_string());
    let o = Command::new("python3")
        .arg("-I")
        .arg("-c")
        .arg(SONDEO)
        .arg(&carpeta)
        .args(ign)
        .current_dir("/")
        .stdin(Stdio::null())
        .output();
    match o {
        Ok(o) => {
            for l in String::from_utf8_lossy(&o.stderr).lines().filter(|l| l.starts_with("informe ") || l.starts_with("Traceback")) {
                registrar(l);
            }
            leer_sondeo(&String::from_utf8_lossy(&o.stdout))
        }
        Err(e) => {
            registrar(&format!("no corre python3: {e}"));
            Vec::new()
        }
    }
}

fn ruta_estado() -> PathBuf {
    let base = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state"));
    base.join("mint-macos/avisos-mint")
}

fn leer_estado() -> BTreeSet<String> {
    fs::read_to_string(ruta_estado()).map(|t| t.lines().map(str::trim).filter(|l| !l.is_empty()).map(String::from).collect()).unwrap_or_default()
}

fn guardar_estado(e: &BTreeSet<String>) {
    let r = ruta_estado();
    let res = (|| {
        fs::create_dir_all(r.parent().unwrap())?;
        let tmp = r.with_extension("tmp");
        fs::write(&tmp, e.iter().map(|u| format!("{u}\n")).collect::<String>())?;
        fs::rename(&tmp, &r)
    })();
    if let Err(err) = res {
        registrar(&format!("{}: {err}", r.display()));
    }
}

/// Qué avisar y cómo queda el estado: se avisa lo que aplica y no estaba; sale del
/// estado lo que dijo que no aplica. Lo que falló al cargar no toca el estado.
fn decidir(informes: &[Informe], avisados: &BTreeSet<String>) -> (Vec<usize>, BTreeSet<String>) {
    let mut estado = avisados.clone();
    let mut nuevos = Vec::new();
    for (i, inf) in informes.iter().enumerate() {
        if !inf.aplica {
            estado.remove(&inf.uuid);
        } else if !avisados.contains(&inf.uuid) {
            nuevos.push(i);
        }
    }
    (nuevos, estado)
}

// --- notificaciones -----------------------------------------------------------

const NOTIF: &str = "org.freedesktop.Notifications";
const NOTIF_RUTA: &str = "/org/freedesktop/Notifications";

fn avisar(c: &Connection, inf: &Informe) -> zbus::Result<u32> {
    let mut hints: HashMap<&str, Value> = HashMap::new();
    hints.insert("desktop-entry", Value::from("mintreport"));
    let icono = if inf.icono.is_empty() { "mintreport" } else { inf.icono.as_str() };
    let r = c.call_method(
        Some(NOTIF),
        NOTIF_RUTA,
        Some(NOTIF),
        "Notify",
        &("System Reports", 0u32, icono, inf.titulo.as_str(), "", vec!["default", "Show", "ignore", "Ignore"], hints, -1i32),
    )?;
    r.body().deserialize::<u32>()
}

fn mostrar() {
    let r = Command::new("mintreport").arg("--reports").stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn();
    match r {
        // Que no quede zombi: se espera en otro hilo.
        Ok(mut h) => drop(std::thread::spawn(move || h.wait())),
        Err(e) => registrar(&format!("no abre mintreport: {e}")),
    }
}

type Pendientes = Arc<Mutex<HashMap<u32, String>>>;

/// Una ronda entera: consultar, avisar lo nuevo y guardar el estado. Devuelve false
/// si algún aviso no salió (todavía no hay servidor de notificaciones).
fn ronda(c: &Connection, pendientes: &Pendientes) -> bool {
    let mut ok = true;
    let informes = sondear(&ignorados());
    let (nuevos, mut estado) = decidir(&informes, &leer_estado());
    for i in nuevos {
        let inf = &informes[i];
        match avisar(c, inf) {
            Ok(id) => {
                pendientes.lock().unwrap().insert(id, inf.uuid.clone());
                estado.insert(inf.uuid.clone());
            }
            // Sin servidor de notificaciones no cuenta como avisado: la próxima ronda.
            Err(e) => {
                registrar(&format!("no se pudo avisar «{}»: {e}", inf.titulo));
                ok = false;
            }
        }
    }
    guardar_estado(&estado);
    ok
}

/// Las acciones y los cierres de las notificaciones que mandó este proceso, hasta
/// que se cierre la conexión.
fn escuchar(mensajes: MessageIterator, pendientes: Pendientes) {
    for m in mensajes {
        let Ok(m) = m else { break };
        let h = m.header();
        match h.member().map(|m| m.as_str()) {
            Some("ActionInvoked") => {
                let Ok((id, accion)) = m.body().deserialize::<(u32, String)>() else { continue };
                let uuid = pendientes.lock().unwrap().get(&id).cloned();
                if let Some(uuid) = uuid {
                    match accion.as_str() {
                        "default" => mostrar(),
                        "ignore" => ignorar(&uuid),
                        _ => {}
                    }
                }
            }
            Some("NotificationClosed") => {
                if let Ok((id, _)) = m.body().deserialize::<(u32, u32)>() {
                    pendientes.lock().unwrap().remove(&id);
                }
            }
            _ => {}
        }
    }
}

fn main() {
    let mut espera = Duration::from_secs(45);
    let mut una_vez: Option<Duration> = None;
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        let seg = |v: Option<String>| v.and_then(|s| s.parse::<u64>().ok()).map(Duration::from_secs);
        match a.as_str() {
            "--espera" => espera = seg(args.next()).unwrap_or(espera),
            "--una-vez" => una_vez = Some(seg(args.next()).unwrap_or(Duration::ZERO)),
            _ => {
                eprintln!("uso: mint-macos-avisos [--espera SEG] [--una-vez SEG]");
                std::process::exit(2);
            }
        }
    }
    let c = match Connection::session() {
        Ok(c) => c,
        Err(e) => {
            registrar(&format!("sin bus de sesión: {e}"));
            std::process::exit(1);
        }
    };
    // La escucha se suscribe antes de la primera ronda: una acción no se pierde.
    let regla = MatchRule::builder().msg_type(TipoMensaje::Signal).interface(NOTIF).and_then(|r| r.path(NOTIF_RUTA)).map(|r| r.build());
    let mensajes = match regla.and_then(|r| MessageIterator::for_match_rule(r, &c, None)) {
        Ok(m) => m,
        Err(e) => {
            registrar(&format!("escuchando las notificaciones: {e}"));
            std::process::exit(1);
        }
    };
    let pendientes: Pendientes = Arc::default();
    let (c2, p2) = (c.clone(), pendientes.clone());
    std::thread::spawn(move || {
        std::thread::sleep(espera);
        let mut reintentos = 0;
        loop {
            let ok = ronda(&c2, &p2);
            if let Some(limite) = una_vez {
                // --una-vez: el tiempo de las acciones cuenta desde que terminó la ronda.
                std::thread::sleep(limite);
                let _ = c2.close();
                break;
            }
            // Al entrar a la sesión el servicio puede llegar antes que Cinnamon: lo que
            // no salió se reintenta a los 2 min (hasta 10 veces), no al día siguiente.
            if !ok && reintentos < 10 {
                reintentos += 1;
                std::thread::sleep(Duration::from_secs(120));
                continue;
            }
            reintentos = 0;
            match intervalo() {
                Some(d) => std::thread::sleep(d),
                None => break,
            }
        }
    });
    escuchar(mensajes, pendientes);
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn strv_de_gsettings() {
        assert_eq!(leer_strv("['drivers']"), ["drivers"]);
        assert_eq!(leer_strv("@as []"), Vec::<String>::new());
        assert_eq!(leer_strv("['a', 'it\\'s']"), ["a", "it's"]);
        assert_eq!(leer_strv(&escribir_strv(&["x'y".into(), "b\\c".into()])), ["x'y", "b\\c"]);
    }

    #[test]
    fn salida_del_sondeo() {
        let s = "1\tdrivers\tInstall hardware drivers\txsi-drivers\n0\ttimeshift-no-setup\nbasura\n1\t\tsin uuid\tx\n";
        let v = leer_sondeo(s);
        assert_eq!(v.len(), 2);
        assert!(v[0].aplica && v[0].titulo == "Install hardware drivers");
        assert!(!v[1].aplica);
    }

    #[test]
    fn no_repite_y_vuelve_a_avisar_si_deja_de_aplicar() {
        let inf = |u: &str, a: bool| Informe { uuid: u.into(), aplica: a, titulo: u.into(), icono: String::new() };
        let vacio = BTreeSet::new();
        let (n, e) = decidir(&[inf("a", true), inf("b", false)], &vacio);
        assert_eq!(n, [0]);
        assert_eq!(e, BTreeSet::new()); // el estado lo pone ronda() al avisar
        let ya: BTreeSet<String> = ["a".to_string()].into();
        let (n, e) = decidir(&[inf("a", true)], &ya);
        assert!(n.is_empty());
        assert_eq!(e, ya);
        let (n, e) = decidir(&[inf("a", false)], &ya);
        assert!(n.is_empty() && e.is_empty());
        // uno que falló (no viene en la salida) no sale del estado
        let (_, e) = decidir(&[], &ya);
        assert_eq!(e, ya);
    }
}
