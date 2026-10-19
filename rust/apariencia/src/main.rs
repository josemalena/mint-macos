//! mint-macos-apariencia: Light, Dark y Auto, el color de acento y el de resaltado de General ▸
//! Appearance (org.mintmacos.Apariencia1, ver DBUS.md). José, 18-10-2026: cambian el tema
//! Constanza activo.
//!
//! Sin ventana y sin root. Lo arranca la activación por D-Bus y se va solo al minuto sin
//! llamadas. Auto no deja nada corriendo: cada vez que cambia calcula la próxima salida o puesta
//! del sol y deja un temporizador de systemd del usuario que lo vuelve a llamar a esa hora
//! (`--auto-ahora`).
//!
//!   mint-macos-apariencia               el servicio de D-Bus
//!   mint-macos-apariencia --auto-ahora  aplica lo que toca ahora en Auto y programa el próximo
//!   mint-macos-apariencia --estado      lo escogido y el próximo cambio, en JSON
//!
//! Para las pruebas: APARIENCIA_SIMULAR=<archivo> anota los comandos en vez de correrlos;
//! APARIENCIA_AHORA=<segundos desde 1970> fija la hora; XDG_CONFIG_HOME y XDG_RUNTIME_DIR,
//! dónde lee y escribe.

use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use zbus::interface;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{OwnedValue, Value};

const NOMBRE: &str = "org.mintmacos.Apariencia1";
const RUTA: &str = "/org/mintmacos/Apariencia1";
const SIN_LLAMADAS: Duration = Duration::from_secs(60);
const UNIDAD_AUTO: &str = "mint-macos-apariencia-auto";

/// Los acentos de la Mac (los de Catalina; Multicolor llegó en Big Sur), con el sufijo del tema.
const ACENTOS: &[(&str, &str)] = &[
    ("Blue", ""), ("Purple", "-Purple"), ("Pink", "-Pink"), ("Red", "-Red"), ("Orange", "-Orange"),
    ("Yellow", "-Yellow"), ("Green", "-Green"), ("Graphite", "-Graphite"),
];
/// Los colores de resaltado por omisión, los de acento de la Mac (medidos en Monterey).
const COLORES: &[(&str, &str)] = &[
    ("Blue", "#007AFF"), ("Purple", "#AF52DE"), ("Pink", "#FF2D55"), ("Red", "#FF3B30"), ("Orange", "#FF9500"),
    ("Yellow", "#FFCC00"), ("Green", "#28CD41"), ("Graphite", "#8E8E93"),
];

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
struct Escogido {
    /// "light", "dark" o "auto".
    apariencia: String,
    acento: String,
    /// "acento" (el mismo color del acento) o un color «#RRGGBB».
    resaltado: String,
}

impl Default for Escogido {
    fn default() -> Self {
        // Lo que había antes de este servicio: Constanza-Oscuro, azul.
        Escogido { apariencia: "dark".into(), acento: "Blue".into(), resaltado: "acento".into() }
    }
}

fn config() -> PathBuf {
    let base = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).unwrap_or_else(|| {
        PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config")
    });
    base
}

fn archivo() -> PathBuf {
    config().join("mint-macos").join("apariencia.json")
}

fn leer() -> Escogido {
    fs::read_to_string(archivo()).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
}

fn guardar(e: &Escogido) -> std::io::Result<()> {
    let a = archivo();
    fs::create_dir_all(a.parent().unwrap())?;
    let tmp = a.with_extension("json.nuevo");
    fs::write(&tmp, serde_json::to_string_pretty(e).unwrap_or_default())?;
    fs::rename(tmp, a)
}

fn ahora() -> i64 {
    std::env::var("APARIENCIA_AHORA").ok().and_then(|v| v.parse().ok()).unwrap_or_else(|| {
        SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
    })
}

// --- el sol ----------------------------------------------------------------------

/// Latitud y longitud de la zona horaria del sistema (zone1970.tab: «+1828-06954» para
/// America/Santo_Domingo). Sin red ni GPS: alcanza para saber cuándo sale y se pone el sol.
fn ubicacion() -> Option<(f64, f64)> {
    let zona = fs::read_to_string("/etc/timezone").ok().map(|z| z.trim().to_string()).or_else(|| {
        fs::read_link("/etc/localtime").ok()?.to_string_lossy().split("zoneinfo/").nth(1).map(String::from)
    })?;
    let tabla = fs::read_to_string("/usr/share/zoneinfo/zone1970.tab").ok()?;
    let linea = tabla.lines().find(|l| !l.starts_with('#') && l.split('\t').nth(2) == Some(zona.as_str()))?;
    let c = linea.split('\t').nth(1)?;
    // ±DDMM[SS]±DDDMM[SS]
    let corte = c[1..].find(['+', '-'])? + 1;
    let gms = |s: &str, grados: usize| -> Option<f64> {
        let signo = if s.starts_with('-') { -1.0 } else { 1.0 };
        let d = &s[1..];
        let g: f64 = d.get(..grados)?.parse().ok()?;
        let m: f64 = d.get(grados..grados + 2)?.parse().ok()?;
        let seg: f64 = d.get(grados + 2..grados + 4).and_then(|x| x.parse().ok()).unwrap_or(0.0);
        Some(signo * (g + m / 60.0 + seg / 3600.0))
    };
    Some((gms(&c[..corte], 2)?, gms(&c[corte..], 3)?))
}

/// Salida y puesta del sol (segundos desde 1970, UTC) del día que contiene `t`, con la ecuación de
/// la salida del sol (la de la NOAA, simplificada; un par de minutos de error alcanzan aquí).
fn sol(t: i64, lat: f64, lon: f64) -> Option<(i64, i64)> {
    let r = |g: f64| g.to_radians();
    // n: los días desde el mediodía del 1-1-2000, redondeados hacia arriba.
    let n = (t as f64 / 86400.0 + 2440587.5 - 2451545.0 + 0.0008).ceil();
    let j = n - lon / 360.0;
    let m = (357.5291 + 0.98560028 * j).rem_euclid(360.0);
    let c = 1.9148 * r(m).sin() + 0.02 * r(2.0 * m).sin() + 0.0003 * r(3.0 * m).sin();
    let l = (m + c + 180.0 + 102.9372).rem_euclid(360.0);
    let transito = 2451545.0 + j + 0.0053 * r(m).sin() - 0.0069 * r(2.0 * l).sin();
    let dec = (r(l).sin() * r(23.4397).sin()).asin();
    let cos_w = (r(-0.833).sin() - r(lat).sin() * dec.sin()) / (r(lat).cos() * dec.cos());
    if !(-1.0..=1.0).contains(&cos_w) {
        return None; // noche o día polar
    }
    let w = cos_w.acos().to_degrees();
    let a_unix = |jd: f64| ((jd - 2440587.5) * 86400.0) as i64;
    Some((a_unix(transito - w / 360.0), a_unix(transito + w / 360.0)))
}

/// En Auto: (oscuro ahora, cuándo cambia). Sin ubicación, claro de 7:00 a 19:00 hora local.
fn auto_en(t: i64) -> (bool, i64) {
    let mut eventos = Vec::new();
    if let Some((lat, lon)) = ubicacion() {
        for d in -1..=2 {
            if let Some((sale, pone)) = sol(t + d * 86400, lat, lon) {
                eventos.push((sale, false));
                eventos.push((pone, true));
            }
        }
    }
    if eventos.is_empty() {
        let desfase = local_desfase(t);
        let dia = (t + desfase).div_euclid(86400) * 86400 - desfase;
        for d in -1..=2 {
            eventos.push((dia + d * 86400 + 7 * 3600, false));
            eventos.push((dia + d * 86400 + 19 * 3600, true));
        }
    }
    eventos.sort();
    let oscuro = eventos.iter().rev().find(|(e, _)| *e <= t).map(|(_, o)| *o).unwrap_or(true);
    let proximo = eventos.iter().find(|(e, _)| *e > t).map(|(e, _)| *e).unwrap_or(t + 12 * 3600);
    (oscuro, proximo)
}

/// El desfase de la hora local (segundos), de `date +%z`.
fn local_desfase(t: i64) -> i64 {
    let s = Command::new("date").args(["-d", &format!("@{t}"), "+%z"]).output().ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string()).unwrap_or_default();
    let n: i64 = s.get(1..).and_then(|x| x.parse().ok()).unwrap_or(0);
    let v = (n / 100) * 3600 + (n % 100) * 60;
    if s.starts_with('-') { -v } else { v }
}

// --- aplicar ---------------------------------------------------------------------

fn correr(prog: &str, args: &[&str]) {
    if let Some(f) = std::env::var_os("APARIENCIA_SIMULAR") {
        let linea = format!("{} {}\n", prog, args.join(" "));
        let _ = fs::OpenOptions::new().create(true).append(true).open(f).and_then(|mut a| {
            use std::io::Write;
            a.write_all(linea.as_bytes())
        });
        return;
    }
    let _ = Command::new(prog).args(args).status();
}

fn temas() -> PathBuf {
    PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".themes")
}

/// El tema base de la versión de macOS activa (su version.json: Constanza, Samana, ValleNuevo,
/// Ozama); Constanza si no se sabe o si el de la versión todavía no está construido.
fn tema_base() -> String {
    let leer_json = |p: PathBuf| fs::read_to_string(p).ok().and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok());
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(|| "/tmp".into());
    let version = leer_json(runtime.join("mint-macos").join("macos.json"))
        .or_else(|| leer_json(config().join("mint-macos").join("macos.json")))
        .and_then(|v| v["version"].as_str().map(String::from));
    let datos = std::env::var_os("XDG_DATA_HOME").map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/share"));
    let base = version.and_then(|v| leer_json(datos.join("mint-macos/macos").join(v).join("version.json")))
        .and_then(|v| v["tema"].as_str().map(String::from)).unwrap_or_else(|| "Constanza".into());
    if base != "Constanza" && !temas().join(format!("{base}-Oscuro")).is_dir() {
        return "Constanza".into();
    }
    base
}

/// El tema de una apariencia y un acento; si esa variante no está instalada, la azul.
fn tema(oscuro: bool, acento: &str) -> String {
    let base = format!("{}-{}", tema_base(), if oscuro { "Oscuro" } else { "Claro" });
    let base = base.as_str();
    let suf = ACENTOS.iter().find(|(a, _)| *a == acento).map(|(_, s)| *s).unwrap_or("");
    let nombre = format!("{base}{suf}");
    if std::env::var_os("APARIENCIA_SIMULAR").is_some() || temas().join(&nombre).is_dir() {
        nombre
    } else {
        base.to_string()
    }
}

/// El color de resaltado (la selección de texto): un CSS chico que importa el gtk.css del
/// usuario, entre marcas, sin tocar lo que ya tiene (la línea de cinnamon-settings).
fn resaltado_css(e: &Escogido) {
    let color = if e.resaltado == "acento" {
        COLORES.iter().find(|(a, _)| *a == e.acento).map(|(_, c)| *c).unwrap_or("#007AFF").to_string()
    } else {
        e.resaltado.clone()
    };
    let d = config().join("gtk-3.0");
    let _ = fs::create_dir_all(&d);
    let css = format!(
        "/* mint-macos-apariencia: el color de resaltado de General ▸ Appearance. */\n\
         selection, *:selected:not(row):not(button), entry selection, textview text selection {{\n  \
         background-color: alpha({color}, 0.45);\n}}\n"
    );
    let _ = fs::write(d.join("mint-macos-resaltado.css"), css);
    let gtk = d.join("gtk.css");
    let texto = fs::read_to_string(&gtk).unwrap_or_default();
    let linea = "@import url(\"mint-macos-resaltado.css\"); /* mint-macos-apariencia */";
    if !texto.contains(linea) {
        let _ = fs::write(&gtk, format!("{linea}\n{texto}"));
    }
}

fn aplicar(e: &Escogido, t: i64) -> (bool, Option<i64>) {
    let (oscuro, proximo) = match e.apariencia.as_str() {
        "light" => (false, None),
        "auto" => {
            let (o, p) = auto_en(t);
            (o, Some(p))
        }
        _ => (true, None),
    };
    let nombre = tema(oscuro, &e.acento);
    resaltado_css(e);
    correr("gsettings", &["set", "org.cinnamon.desktop.interface", "gtk-theme", &nombre]);
    correr("gsettings", &["set", "org.cinnamon.desktop.wm.preferences", "theme", &nombre]);
    correr("gsettings", &["set", "org.cinnamon.theme", "name", &nombre]);
    correr("gsettings", &["set", "org.x.apps.portal", "color-scheme", if oscuro { "prefer-dark" } else { "default" }]);
    // El Dock: un tema por apariencia (el acento no cambia el Dock).
    let plank = format!("'{}-{}'", tema_base(), if oscuro { "Oscuro" } else { "Claro" });
    correr("dconf", &["write", "/net/launchpad/plank/docks/dock1/theme", &plank]);
    // Auto: el próximo cambio, con un temporizador de systemd del usuario (nada esperando).
    correr("systemctl", &["--user", "stop", &format!("{UNIDAD_AUTO}.timer")]);
    if let Some(p) = proximo {
        let exe = std::env::current_exe().map(|x| x.to_string_lossy().into_owned()).unwrap_or_default();
        let cuando = Command::new("date").args(["-u", "-d", &format!("@{p}"), "+%Y-%m-%d %H:%M:%S UTC"]).output().ok()
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string()).unwrap_or_default();
        correr("systemd-run", &["--user", "--quiet", &format!("--unit={UNIDAD_AUTO}"), &format!("--on-calendar={cuando}"),
                                "--timer-property=AccuracySec=1min", &exe, "--auto-ahora"]);
    }
    (oscuro, proximo)
}

fn estado(e: &Escogido, t: i64) -> HashMap<String, OwnedValue> {
    let ov = |v: Value| v.try_to_owned().expect("valor sin descriptores");
    let mut d = HashMap::new();
    let (oscuro, proximo) = match e.apariencia.as_str() {
        "light" => (false, None),
        "auto" => {
            let (o, p) = auto_en(t);
            (o, Some(p))
        }
        _ => (true, None),
    };
    d.insert("apariencia".into(), ov(e.apariencia.clone().into()));
    d.insert("acento".into(), ov(e.acento.clone().into()));
    d.insert("resaltado".into(), ov(e.resaltado.clone().into()));
    d.insert("oscuro".into(), ov(oscuro.into()));
    d.insert("tema".into(), ov(tema(oscuro, &e.acento).into()));
    d.insert("acentos".into(), ov(Value::from(ACENTOS.iter().map(|(a, _)| a.to_string()).collect::<Vec<_>>())));
    if let Some(p) = proximo {
        d.insert("proximo_cambio".into(), ov(p.into()));
    }
    d
}

// --- el servicio -----------------------------------------------------------------

struct Servicio {
    ultima: Arc<Mutex<Instant>>,
}

#[interface(name = "org.mintmacos.Apariencia1")]
impl Servicio {
    /// Lo escogido, el tema que queda puesto, la lista de acentos y, en Auto, el próximo cambio.
    fn estado(&self) -> HashMap<String, OwnedValue> {
        *self.ultima.lock().unwrap() = Instant::now();
        estado(&leer(), ahora())
    }

    /// Cambia la apariencia ("light", "dark", "auto"), el acento y el resaltado ("acento" o
    /// «#RRGGBB»). Un texto vacío deja lo que había. false si algo no es válido.
    async fn poner(&self, apariencia: String, acento: String, resaltado: String,
                   #[zbus(signal_emitter)] emisor: SignalEmitter<'_>) -> bool {
        *self.ultima.lock().unwrap() = Instant::now();
        let mut e = leer();
        if !apariencia.is_empty() {
            if !["light", "dark", "auto"].contains(&apariencia.as_str()) {
                return false;
            }
            e.apariencia = apariencia;
        }
        if !acento.is_empty() {
            if !ACENTOS.iter().any(|(a, _)| *a == acento) {
                return false;
            }
            e.acento = acento;
        }
        if !resaltado.is_empty() {
            let ok = resaltado == "acento"
                || (resaltado.len() == 7 && resaltado.starts_with('#') && resaltado[1..].chars().all(|c| c.is_ascii_hexdigit()));
            if !ok {
                return false;
            }
            e.resaltado = resaltado;
        }
        if guardar(&e).is_err() {
            return false;
        }
        aplicar(&e, ahora());
        let _ = Servicio::cambio(&emisor).await;
        true
    }

    #[zbus(signal)]
    async fn cambio(emisor: &SignalEmitter<'_>) -> zbus::Result<()>;
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("--auto-ahora") {
        let e = leer();
        if e.apariencia == "auto" {
            aplicar(&e, ahora());
        }
        return;
    }
    if args.first().map(String::as_str) == Some("--estado") {
        let e = leer();
        let (oscuro, proximo) = if e.apariencia == "auto" { let (o, p) = auto_en(ahora()); (o, Some(p)) } else { (e.apariencia != "light", None) };
        println!("{}", serde_json::json!({"apariencia": e.apariencia, "acento": e.acento, "resaltado": e.resaltado,
                                          "oscuro": oscuro, "tema": tema(oscuro, &e.acento), "proximo_cambio": proximo}));
        return;
    }
    let ultima = Arc::new(Mutex::new(Instant::now()));
    let c = zbus::blocking::connection::Builder::session()
        .and_then(|b| b.name(NOMBRE))
        .and_then(|b| b.serve_at(RUTA, Servicio { ultima: ultima.clone() }))
        .and_then(|b| b.build());
    let _c = match c {
        Ok(c) => c,
        Err(e) => {
            eprintln!("mint-macos-apariencia: {e}");
            std::process::exit(1);
        }
    };
    // Sin llamadas, se va: la próxima la vuelve a arrancar la activación por D-Bus.
    loop {
        std::thread::sleep(Duration::from_secs(5));
        if ultima.lock().unwrap().elapsed() > SIN_LLAMADAS {
            break;
        }
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn sol_en_santo_domingo() {
        // 18-10-2026 (1792281600 = 00:00 UTC). En Santo Domingo el sol sale cerca de las 6:50 y se
        // pone cerca de las 18:30, hora local (GMT-4): 10:50 y 22:30 UTC.
        let (sale, pone) = sol(1792281600 + 12 * 3600, 18.4667, -69.9).unwrap();
        let hora = |t: i64| (t.rem_euclid(86400)) as f64 / 3600.0;
        assert!((hora(sale) - 10.8).abs() < 0.4, "sale a las {} UTC", hora(sale));
        assert!((hora(pone) - 22.5).abs() < 0.4, "se pone a las {} UTC", hora(pone));
    }

    #[test]
    fn tema_por_apariencia_y_acento() {
        std::env::set_var("APARIENCIA_SIMULAR", "/dev/null");
        assert_eq!(tema(true, "Blue"), "Constanza-Oscuro");
        assert_eq!(tema(false, "Blue"), "Constanza-Claro");
        assert_eq!(tema(false, "Graphite"), "Constanza-Claro-Graphite");
        assert_eq!(tema(true, "Green"), "Constanza-Oscuro-Green");
    }
}
