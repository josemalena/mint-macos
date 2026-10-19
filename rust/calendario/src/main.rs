//! mint-macos-calendario: los eventos del calendario de Thunderbird para el widget Calendar del
//! Notification Center (org.mintmacos.Calendario1, ver DBUS.md). Solo lectura.
//!
//! - Lee una COPIA de calendar-data/cache.sqlite (y local.sqlite) con su WAL, hecha en
//!   $XDG_RUNTIME_DIR (0700) y borrada al terminar: el original nunca se abre.
//! - Las recurrencias (RRULE, EXDATE, RDATE) con el crate rrule; las excepciones de una
//!   ocurrencia (RECURRENCE-ID) reemplazan a la que cambian.
//! - Zonas horarias: la de cada evento (su TZID); los flotantes y los de todo el día, en la hora
//!   local, sin correrse de día.
//! - Avisa con Cambio cuando Thunderbird escribe (inotify, sin sondeo), y se va solo a los 2
//!   minutos sin llamadas.
//! - Nada de títulos, lugares ni asistentes en los registros: son eventos personales.
//!
//! CALENDARIO_PERFIL: la carpeta del perfil de Thunderbird (las pruebas).

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use chrono::{DateTime, Local, TimeZone, Utc};
use rusqlite::{Connection, OpenFlags};
use zbus::interface;
use zbus::zvariant::{OwnedValue, Value};

const NOMBRE: &str = "org.mintmacos.Calendario1";
const RUTA: &str = "/org/mintmacos/Calendario1";
const SIN_LLAMADAS: Duration = Duration::from_secs(120);
/// Bits de calStorageCalendar: el evento es de todo el día.
const TODO_EL_DIA: i64 = 8;
/// Colores de los calendarios sin color propio, los de Calendar de la Mac.
const PALETA: &[&str] = &["#1BADF8", "#63DA38", "#FF9500", "#CC73E1", "#FF2968", "#FFCC00", "#A2845E"];

type Dict = HashMap<String, OwnedValue>;

#[derive(Clone, Debug, PartialEq)]
pub struct Evento {
    pub id: String,
    pub titulo: String,
    pub lugar: String,
    /// Milisegundos desde 1970 (UTC).
    pub inicio: i64,
    pub fin: i64,
    pub todo_el_dia: bool,
    pub calendario: String,
    pub color: String,
}

#[derive(Clone, Debug)]
struct Calendario {
    nombre: String,
    color: String,
}

// --- el perfil -------------------------------------------------------------------

/// La carpeta del perfil de Thunderbird: CALENDARIO_PERFIL, o el de profiles.ini (Default=1, o el
/// primero), o el primero que tenga calendar-data.
fn perfil() -> Option<PathBuf> {
    if let Some(p) = std::env::var_os("CALENDARIO_PERFIL") {
        return Some(PathBuf::from(p));
    }
    let base = PathBuf::from(std::env::var_os("HOME")?).join(".thunderbird");
    let ini = fs::read_to_string(base.join("profiles.ini")).unwrap_or_default();
    let mut rutas = Vec::new();
    let mut ruta: Option<String> = None;
    let mut defecto = false;
    for l in ini.lines().chain(std::iter::once("[fin]")) {
        let l = l.trim();
        if l.starts_with('[') {
            if let Some(r) = ruta.take() {
                if defecto { rutas.insert(0, r) } else { rutas.push(r) }
            }
            defecto = false;
        } else if let Some(v) = l.strip_prefix("Path=") {
            ruta = Some(v.to_string());
        } else if l == "Default=1" {
            defecto = true;
        }
    }
    rutas.into_iter().map(|r| if r.starts_with('/') { PathBuf::from(r) } else { base.join(r) })
        .find(|p| p.join("calendar-data").is_dir())
}

/// Los calendarios del registro de prefs.js: nombre, color y si está apagado.
fn calendarios(perfil: &Path) -> HashMap<String, (Calendario, bool)> {
    let texto = fs::read_to_string(perfil.join("prefs.js")).unwrap_or_default();
    let mut campos: HashMap<String, HashMap<String, String>> = HashMap::new();
    for l in texto.lines() {
        let Some(resto) = l.trim().strip_prefix("user_pref(\"calendar.registry.") else { continue };
        let Some((clave, valor)) = resto.split_once("\",") else { continue };
        let Some((id, campo)) = clave.rsplit_once('.') else { continue };
        let valor = valor.trim().trim_end_matches(");").trim().trim_matches('"').to_string();
        campos.entry(id.to_string()).or_default().insert(campo.to_string(), valor);
    }
    let mut ids: Vec<_> = campos.keys().cloned().collect();
    ids.sort();
    ids.into_iter().enumerate().map(|(i, id)| {
        let c = &campos[&id];
        let color = c.get("color").cloned().unwrap_or_else(|| PALETA[i % PALETA.len()].to_string());
        let apagado = c.get("disabled").map(|v| v == "true").unwrap_or(false);
        (id.clone(), (Calendario { nombre: c.get("name").cloned().unwrap_or(id), color }, apagado))
    }).collect()
}

// --- la copia --------------------------------------------------------------------

/// Copia la base y su WAL a una carpeta propia de $XDG_RUNTIME_DIR (0700) y la abre; la carpeta se
/// borra cuando se suelta. El original no se abre nunca: Thunderbird puede estar escribiéndolo.
struct Copia {
    carpeta: PathBuf,
}

impl Drop for Copia {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.carpeta);
    }
}

fn copiar(original: &Path) -> Option<(Copia, Connection)> {
    use std::os::unix::fs::DirBuilderExt;
    if !original.is_file() {
        return None;
    }
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    let carpeta = runtime.join(format!("mint-macos-calendario-{}-{}", std::process::id(),
                                       original.file_stem().unwrap_or_default().to_string_lossy()));
    let _ = fs::remove_dir_all(&carpeta);
    fs::DirBuilder::new().mode(0o700).create(&carpeta).ok()?;
    let copia = Copia { carpeta: carpeta.clone() };
    let destino = carpeta.join("cal.sqlite");
    fs::copy(original, &destino).ok()?;
    for ext in ["-wal", "-shm"] {
        let o = PathBuf::from(format!("{}{}", original.display(), ext));
        if o.is_file() {
            let _ = fs::copy(&o, PathBuf::from(format!("{}{}", destino.display(), ext)));
        }
    }
    // De la copia sí se escribe: SQLite pasa ahí el WAL al abrirla. El original sigue intacto.
    let c = Connection::open_with_flags(&destino, OpenFlags::SQLITE_OPEN_READ_WRITE).ok()?;
    Some((copia, c))
}

// --- zonas y fechas --------------------------------------------------------------

/// La zona de un TZID de Thunderbird: el nombre de la base IANA, «GMT-0400» como Etc/GMT+4,
/// «floating» (y lo que no se reconozca) como la hora local.
fn zona(tzid: &str) -> Option<chrono_tz::Tz> {
    if tzid.is_empty() || tzid == "floating" {
        return None;
    }
    if tzid == "UTC" || tzid == "Z" {
        return Some(chrono_tz::UTC);
    }
    if let Ok(z) = chrono_tz::Tz::from_str(tzid) {
        return Some(z);
    }
    let t = tzid.trim_start_matches("GMT").trim_start_matches("UTC");
    if t.len() == 5 && (t.starts_with('+') || t.starts_with('-')) && &t[3..] == "00" {
        let h: i32 = t[1..3].parse().ok()?;
        // Etc/GMT invierte el signo: GMT-0400 es Etc/GMT+4.
        let nombre = if h == 0 { "Etc/GMT".to_string() } else { format!("Etc/GMT{}{}", if t.starts_with('-') { '+' } else { '-' }, h) };
        return chrono_tz::Tz::from_str(&nombre).ok();
    }
    None
}

/// Un instante de Thunderbird (µs) con su zona → (DTSTART para rrule, milisegundos UTC).
/// Thunderbird guarda los flotantes y los de todo el día con la hora de reloj como si fuera UTC.
fn instante(us: i64, tzid: &str) -> (String, i64) {
    let utc = DateTime::<Utc>::from_timestamp_micros(us).unwrap_or_default();
    match zona(tzid) {
        Some(z) => {
            let local = utc.with_timezone(&z);
            (format!("DTSTART;TZID={}:{}", z.name(), local.format("%Y%m%dT%H%M%S")), utc.timestamp_millis())
        }
        None => {
            // Flotante: la hora de reloj, en la hora local de esta máquina.
            let reloj = utc.naive_utc();
            let ms = Local.from_local_datetime(&reloj).earliest().map(|d| d.timestamp_millis()).unwrap_or(utc.timestamp_millis());
            (format!("DTSTART:{}", reloj.format("%Y%m%dT%H%M%S")), ms)
        }
    }
}

// --- los eventos -----------------------------------------------------------------

struct Fila {
    cal: String,
    id: String,
    titulo: String,
    flags: i64,
    inicio: i64,
    fin: i64,
    tz_inicio: String,
    recurrencia: Option<i64>,
    tz_recurrencia: String,
}

fn leer_base(c: &Connection, cals: &HashMap<String, (Calendario, bool)>, desde: i64, hasta: i64) -> Vec<Evento> {
    let mut filas = Vec::new();
    if let Ok(mut st) = c.prepare("SELECT cal_id, id, IFNULL(title,''), IFNULL(flags,0), IFNULL(event_start,0), \
                                   IFNULL(event_end,0), IFNULL(event_start_tz,''), recurrence_id, IFNULL(recurrence_id_tz,'') \
                                   FROM cal_events") {
        if let Ok(it) = st.query_map([], |r| Ok(Fila {
            cal: r.get(0)?, id: r.get(1)?, titulo: r.get(2)?, flags: r.get(3)?, inicio: r.get(4)?, fin: r.get(5)?,
            tz_inicio: r.get(6)?, recurrencia: r.get(7)?, tz_recurrencia: r.get(8)?,
        })) {
            filas.extend(it.flatten());
        }
    }
    // LOCATION de cada evento (y de cada excepción, por su recurrence_id).
    let mut lugares: HashMap<(String, Option<i64>), String> = HashMap::new();
    if let Ok(mut st) = c.prepare("SELECT item_id, recurrence_id, value FROM cal_properties WHERE key = 'LOCATION'") {
        if let Ok(it) = st.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<i64>>(1)?, r.get::<_, String>(2)?))) {
            for (i, rid, v) in it.flatten() {
                lugares.insert((i, rid), v);
            }
        }
    }
    let mut reglas: HashMap<String, Vec<String>> = HashMap::new();
    if let Ok(mut st) = c.prepare("SELECT item_id, icalString FROM cal_recurrence") {
        if let Ok(it) = st.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))) {
            for (i, s) in it.flatten() {
                reglas.entry(i).or_default().push(s.trim().replace("\r\n", "\n"));
            }
        }
    }
    // Las excepciones: (item, la ocurrencia que cambian, en ms) → la fila que la reemplaza.
    let excepciones: HashMap<(String, i64), &Fila> = filas.iter().filter_map(|f| {
        f.recurrencia.map(|r| ((f.id.clone(), instante(r, &f.tz_recurrencia).1), f))
    }).collect();
    let mut out = Vec::new();
    let mut poner = |f: &Fila, inicio: i64, fin: i64, ocurrencia: i64| {
        let Some((cal, apagado)) = cals.get(&f.cal) else { return };
        if *apagado || fin <= desde || inicio >= hasta {
            return;
        }
        out.push(Evento {
            id: format!("{}/{}/{}", f.cal, f.id, ocurrencia),
            titulo: f.titulo.clone(),
            lugar: lugares.get(&(f.id.clone(), f.recurrencia)).cloned().unwrap_or_default(),
            inicio, fin, todo_el_dia: f.flags & TODO_EL_DIA != 0,
            calendario: cal.nombre.clone(), color: cal.color.clone(),
        });
    };
    for f in filas.iter().filter(|f| f.recurrencia.is_none()) {
        let (dtstart, ini) = instante(f.inicio, &f.tz_inicio);
        let (_, fin) = instante(f.fin, &f.tz_inicio);
        let dur = (fin - ini).max(0);
        let Some(rs) = reglas.get(&f.id) else {
            poner(f, ini, fin, ini);
            continue;
        };
        let texto = format!("{dtstart}\n{}", rs.join("\n"));
        let Ok(set) = rrule::RRuleSet::from_str(&texto) else {
            // Una regla que no se entiende: el evento suelto, como mínimo.
            poner(f, ini, fin, ini);
            continue;
        };
        let tz = rrule::Tz::Tz(chrono_tz::UTC);
        let antes = Utc.timestamp_millis_opt(desde - dur - 86_400_000).single().unwrap_or_default().with_timezone(&tz);
        let despues = Utc.timestamp_millis_opt(hasta + 86_400_000).single().unwrap_or_default().with_timezone(&tz);
        let r = set.after(antes).before(despues).all(2000);
        for d in r.dates {
            let o = d.timestamp_millis();
            if let Some(e) = excepciones.get(&(f.id.clone(), o)) {
                let (_, ei) = instante(e.inicio, &e.tz_inicio);
                let (_, ef) = instante(e.fin, &e.tz_inicio);
                poner(e, ei, ef, o);
            } else {
                poner(f, o, o + dur, o);
            }
        }
    }
    out
}

/// Todos los eventos entre dos instantes (ms), ordenados por inicio. Sin Thunderbird o sin
/// perfil, ninguno.
pub fn eventos(desde: i64, hasta: i64) -> Vec<Evento> {
    let Some(p) = perfil() else { return Vec::new() };
    let cals = calendarios(&p);
    let mut out = Vec::new();
    for base in ["cache.sqlite", "local.sqlite"] {
        if let Some((_copia, c)) = copiar(&p.join("calendar-data").join(base)) {
            out.extend(leer_base(&c, &cals, desde, hasta));
        }
    }
    out.sort_by(|a, b| (a.inicio, &a.id).cmp(&(b.inicio, &b.id)));
    out
}

// --- el servicio -----------------------------------------------------------------

struct Servicio {
    ultima: Arc<Mutex<Instant>>,
}

fn dict(e: &Evento) -> Dict {
    let ov = |v: Value| v.try_to_owned().expect("valor sin descriptores");
    let mut d = Dict::new();
    d.insert("id".into(), ov(e.id.clone().into()));
    d.insert("titulo".into(), ov(e.titulo.clone().into()));
    d.insert("lugar".into(), ov(e.lugar.clone().into()));
    d.insert("inicio".into(), ov(e.inicio.into()));
    d.insert("fin".into(), ov(e.fin.into()));
    d.insert("todo_el_dia".into(), ov(e.todo_el_dia.into()));
    d.insert("calendario".into(), ov(e.calendario.clone().into()));
    d.insert("color".into(), ov(e.color.clone().into()));
    d
}

#[interface(name = "org.mintmacos.Calendario1")]
impl Servicio {
    /// Los eventos entre desde_ms y hasta_ms (ms desde 1970, UTC), ordenados por inicio.
    fn eventos(&self, desde_ms: i64, hasta_ms: i64) -> Vec<Dict> {
        *self.ultima.lock().unwrap() = Instant::now();
        eventos(desde_ms, hasta_ms).iter().map(dict).collect()
    }

    /// Thunderbird cambió el calendario: el widget vuelve a pedir Eventos.
    #[zbus(signal)]
    async fn cambio(emisor: &zbus::object_server::SignalEmitter<'_>) -> zbus::Result<()>;
}

/// Vigila calendar-data con inotify (sin sondeo) y emite Cambio, una vez por ráfaga de escrituras.
fn vigilar(c: zbus::blocking::Connection) {
    let Some(p) = perfil() else { return };
    let Ok(mut ino) = inotify::Inotify::init() else { return };
    let mascara = inotify::WatchMask::MODIFY | inotify::WatchMask::CLOSE_WRITE | inotify::WatchMask::MOVED_TO | inotify::WatchMask::CREATE;
    if ino.watches().add(p.join("calendar-data"), mascara).is_err() {
        return;
    }
    let mut buf = [0u8; 4096];
    loop {
        if ino.read_events_blocking(&mut buf).is_err() {
            return;
        }
        // Thunderbird escribe a ráfagas: se espera a que termine y se descarta lo que llegó.
        std::thread::sleep(Duration::from_millis(1500));
        let _ = ino.read_events(&mut buf);
        let _ = c.emit_signal(None::<()>, RUTA, NOMBRE, "Cambio", &());
    }
}

fn main() {
    let ultima = Arc::new(Mutex::new(Instant::now()));
    let c = zbus::blocking::connection::Builder::session()
        .and_then(|b| b.name(NOMBRE))
        .and_then(|b| b.serve_at(RUTA, Servicio { ultima: ultima.clone() }))
        .and_then(|b| b.build());
    let c = match c {
        Ok(c) => c,
        Err(e) => {
            eprintln!("mint-macos-calendario: {e}");
            std::process::exit(1);
        }
    };
    let c2 = c.clone();
    std::thread::spawn(move || vigilar(c2));
    loop {
        std::thread::sleep(Duration::from_secs(10));
        if ultima.lock().unwrap().elapsed() > SIN_LLAMADAS {
            break;
        }
    }
}

#[cfg(test)]
mod pruebas;
