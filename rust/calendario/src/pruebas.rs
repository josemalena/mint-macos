//! Con un perfil de Thunderbird de mentira (prefs.js y un cache.sqlite armado aquí), nunca con
//! el de José: los eventos son de mentira.
use super::*;

fn us(s: &str) -> i64 {
    // «2026-10-18T23:30:00Z» → µs.
    DateTime::parse_from_rfc3339(s).unwrap().timestamp_micros()
}

fn ms(s: &str) -> i64 {
    DateTime::parse_from_rfc3339(s).unwrap().timestamp_millis()
}

fn perfil_de_mentira() -> tempdir::Carpeta {
    let d = tempdir::Carpeta::nueva();
    fs::create_dir_all(d.0.join("calendar-data")).unwrap();
    fs::write(d.0.join("prefs.js"), concat!(
        "user_pref(\"calendar.registry.cal_a.name\", \"Trabajo\");\n",
        "user_pref(\"calendar.registry.cal_a.color\", \"#FF2968\");\n",
        "user_pref(\"calendar.registry.cal_b.name\", \"Casa\");\n",
        "user_pref(\"calendar.registry.cal_c.name\", \"Apagado\");\n",
        "user_pref(\"calendar.registry.cal_c.disabled\", true);\n")).unwrap();
    let c = Connection::open(d.0.join("calendar-data").join("cache.sqlite")).unwrap();
    c.execute_batch("
        CREATE TABLE cal_events (cal_id TEXT, id TEXT, time_created INTEGER, last_modified INTEGER, title TEXT,
          priority INTEGER, privacy TEXT, ical_status TEXT, flags INTEGER, event_start INTEGER, event_end INTEGER,
          event_stamp INTEGER, event_start_tz TEXT, event_end_tz TEXT, recurrence_id INTEGER, recurrence_id_tz TEXT,
          alarm_last_ack INTEGER, offline_journal INTEGER);
        CREATE TABLE cal_properties (item_id TEXT, key TEXT, value TEXT, recurrence_id INTEGER, recurrence_id_tz TEXT, cal_id TEXT);
        CREATE TABLE cal_recurrence (item_id TEXT, cal_id TEXT, icalString TEXT);
        PRAGMA journal_mode=WAL;").unwrap();
    let ev = |cal: &str, id: &str, t: &str, flags: i64, ini: i64, fin: i64, tz: &str, rid: Option<i64>| {
        c.execute("INSERT INTO cal_events (cal_id, id, title, flags, event_start, event_end, event_start_tz, event_end_tz, recurrence_id, recurrence_id_tz) \
                   VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7, ?8, ?7)", rusqlite::params![cal, id, t, flags, ini, fin, tz, rid]).unwrap();
    };
    // 1. Con zona: 19:30 en Santo Domingo = 23:30 UTC (cerca de la medianoche UTC).
    ev("cal_a", "e1", "Reunión", 0, us("2026-10-18T23:30:00Z"), us("2026-10-19T00:30:00Z"), "America/Santo_Domingo", None);
    c.execute("INSERT INTO cal_properties (item_id, key, value) VALUES ('e1', 'LOCATION', 'Oficina')", []).unwrap();
    // 2. Todo el día (flotante): el 19, guardado como 00:00 «UTC» de reloj. No puede correrse al 18.
    ev("cal_b", "e2", "Cumpleaños", TODO_EL_DIA, us("2026-10-19T00:00:00Z"), us("2026-10-20T00:00:00Z"), "floating", None);
    // 3. Semanal los lunes a las 9:00 en Santo Domingo, con un EXDATE y una ocurrencia movida.
    ev("cal_a", "e3", "Semanal", 0, us("2026-10-05T13:00:00Z"), us("2026-10-05T14:00:00Z"), "America/Santo_Domingo", None);
    c.execute("INSERT INTO cal_recurrence VALUES ('e3', 'cal_a', 'RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=6')", []).unwrap();
    c.execute("INSERT INTO cal_recurrence VALUES ('e3', 'cal_a', 'EXDATE;TZID=America/Santo_Domingo:20261012T090000')", []).unwrap();
    // La del 19 se mueve a las 11:00 (15:00 UTC).
    ev("cal_a", "e3", "Semanal movida", 0, us("2026-10-19T15:00:00Z"), us("2026-10-19T16:00:00Z"), "America/Santo_Domingo", Some(us("2026-10-19T13:00:00Z")));
    // 4. Un calendario apagado: no sale.
    ev("cal_c", "e4", "No debe salir", 0, us("2026-10-19T12:00:00Z"), us("2026-10-19T13:00:00Z"), "UTC", None);
    // 5. Una zona como la escribe Exchange: GMT-0400.
    ev("cal_b", "e5", "Llamada", 0, us("2026-10-20T14:00:00Z"), us("2026-10-20T14:30:00Z"), "GMT-0400", None);
    // 6. Semanal los martes a las 10:00 en Nueva York, cruzando el 1-11-2026 (EE. UU. atrasa la hora):
    // 14:00 UTC antes del cambio, 15:00 UTC después (10:00 → 11:00 en Santo Domingo).
    ev("cal_a", "e6", "Con Nueva York", 0, us("2026-10-27T14:00:00Z"), us("2026-10-27T15:00:00Z"), "America/New_York", None);
    c.execute("INSERT INTO cal_recurrence VALUES ('e6', 'cal_a', 'RRULE:FREQ=WEEKLY;COUNT=3')", []).unwrap();
    d
}

mod tempdir {
    pub struct Carpeta(pub std::path::PathBuf);
    impl Carpeta {
        pub fn nueva() -> Self {
            let p = std::env::temp_dir().join(format!("calendario-prueba-{}-{:?}", std::process::id(), std::thread::current().id()));
            let _ = std::fs::remove_dir_all(&p);
            std::fs::create_dir_all(&p).unwrap();
            Carpeta(p)
        }
    }
    impl Drop for Carpeta {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
}

#[test]
fn eventos_con_zonas_recurrencias_y_excepciones() {
    // La hora local de la prueba es la de José (GMT-4, sin horario de verano).
    std::env::set_var("TZ", "America/Santo_Domingo");
    let d = perfil_de_mentira();
    std::env::set_var("CALENDARIO_PERFIL", &d.0);
    let run = d.0.join("run");
    fs::create_dir_all(&run).unwrap();
    std::env::set_var("XDG_RUNTIME_DIR", &run);
    let e = eventos(ms("2026-10-01T00:00:00Z"), ms("2026-11-30T00:00:00Z"));
    let titulos: Vec<_> = e.iter().map(|x| x.titulo.as_str()).collect();
    // La copia se borró.
    assert_eq!(fs::read_dir(&run).unwrap().count(), 0, "quedó la copia en XDG_RUNTIME_DIR");
    assert!(!titulos.contains(&"No debe salir"), "{titulos:?}");
    // Semanal: 6 lunes desde el 5-10, menos el 12 (EXDATE), y el 19 movido.
    assert_eq!(titulos.iter().filter(|t| **t == "Semanal").count(), 4, "{titulos:?}");
    let movida = e.iter().find(|x| x.titulo == "Semanal movida").expect("la excepción");
    assert_eq!(movida.inicio, ms("2026-10-19T15:00:00Z"));
    assert!(!e.iter().any(|x| x.titulo == "Semanal" && x.inicio == ms("2026-10-19T13:00:00Z")), "la ocurrencia movida sigue");
    // Con zona, cerca de la medianoche UTC: el instante es el mismo.
    let r = e.iter().find(|x| x.titulo == "Reunión").unwrap();
    assert_eq!(r.inicio, ms("2026-10-18T23:30:00Z"));
    assert_eq!(r.lugar, "Oficina");
    assert_eq!(r.color, "#FF2968");
    assert_eq!(r.calendario, "Trabajo");
    // Todo el día: empieza a las 00:00 del 19 en hora local (04:00 UTC), no el 18.
    let c = e.iter().find(|x| x.titulo == "Cumpleaños").unwrap();
    assert!(c.todo_el_dia);
    assert_eq!(c.inicio, ms("2026-10-19T04:00:00Z"));
    assert_eq!(c.fin, ms("2026-10-20T04:00:00Z"));
    // GMT-0400 como Etc/GMT+4.
    let l = e.iter().find(|x| x.titulo == "Llamada").unwrap();
    assert_eq!(l.inicio, ms("2026-10-20T14:00:00Z"));
    // Horario de verano en la zona del evento: la hora de Nueva York se mantiene, la de UTC se corre.
    let ny: Vec<_> = e.iter().filter(|x| x.titulo == "Con Nueva York").map(|x| (x.inicio, x.fin)).collect();
    assert_eq!(ny, vec![
        (ms("2026-10-27T14:00:00Z"), ms("2026-10-27T15:00:00Z")),
        (ms("2026-11-03T15:00:00Z"), ms("2026-11-03T16:00:00Z")),
        (ms("2026-11-10T15:00:00Z"), ms("2026-11-10T16:00:00Z")),
    ]);
    // Ordenados por inicio.
    assert!(e.windows(2).all(|w| w[0].inicio <= w[1].inicio));
}

#[test]
fn sin_perfil_ninguno() {
    std::env::set_var("CALENDARIO_PERFIL", "/no/existe");
    assert!(eventos(0, i64::MAX / 2).is_empty());
}
