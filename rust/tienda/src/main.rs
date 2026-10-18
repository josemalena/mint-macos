//! mint-macos-tienda: el motor del App Store, sin ventana (la interfaz está en
//! DBUS.md). Lo arranca la activación por D-Bus; se va solo tras 10 minutos sin
//! uso y sin trabajos. Una vez al día actualiza los Flatpak de usuario si
//! auto-update-flatpaks está encendido, como la Mac.
//!
//!     mint-macos-tienda            el servicio (org.mintmacos.Tienda1, bus de sesión)
//!     mint-macos-tienda --contar   carga los catálogos, dice cuántas apps y cuánto tardó
//!
//! Para las pruebas: TIENDA_RAIZ cambia la raíz de los catálogos, de dpkg y de
//! /etc/linuxmint (con FLATPAK_USER_DIR y FLATPAK_SYSTEM_DIR para Flatpak),
//! TIENDA_BUS_SISTEMA el bus de PackageKit, y TIENDA_FLATHUB y TIENDA_ODRS las API.

mod catalogo;
mod flatpak;
mod indice;
mod packagekit;
mod servicio;
mod web;

use std::path::PathBuf;
use std::time::{Duration, Instant};

const INACTIVO: Duration = Duration::from_secs(600);
const DIA: Duration = Duration::from_secs(24 * 3600);

fn rutas() -> (catalogo::Rutas, PathBuf, PathBuf) {
    let mut r = catalogo::Rutas::del_sistema();
    match std::env::var_os("TIENDA_RAIZ").map(PathBuf::from) {
        Some(raiz) => {
            r.dep11 = raiz.join("var/lib/swcatalog/yaml");
            r.iconos_dep11 = raiz.join("var/lib/swcatalog/icons");
            if let Some(s) = std::env::var_os("FLATPAK_SYSTEM_DIR") {
                r.flatpak.retain(|(i, _)| i != "system");
                r.flatpak.push(("system".into(), PathBuf::from(s)));
            }
            (r, raiz.join("var/lib/dpkg/status"), raiz)
        }
        None => (r, indice::dpkg_del_sistema(), PathBuf::from("/")),
    }
}

fn main() {
    let (r, dpkg, raiz) = rutas();
    if std::env::args().nth(1).as_deref() == Some("--contar") {
        let t = Instant::now();
        let apps = catalogo::cargar(&r, &catalogo::Idiomas::del_entorno());
        let fp = apps.iter().filter(|a| a.origen == catalogo::Origen::Flatpak).count();
        println!("{} apps ({} flatpak, {} apt) en {:?}", apps.len(), fp, apps.len() - fp, t.elapsed());
        return;
    }
    let motor = servicio::Motor::nuevo(r, dpkg, raiz);
    let c = zbus::blocking::connection::Builder::session()
        .and_then(|b| b.name(servicio::NOMBRE))
        .and_then(|b| b.serve_at(servicio::RUTA, servicio::Servicio { motor: motor.clone() }))
        .and_then(|b| b.build());
    let c = match c {
        Ok(c) => c,
        Err(e) => {
            eprintln!("mint-macos-tienda: {e}");
            std::process::exit(1);
        }
    };
    motor.poner_bus(c.clone());
    let m2 = motor.clone();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(300));
        loop {
            m2.auto_actualizar();
            std::thread::sleep(DIA);
        }
    });
    loop {
        std::thread::sleep(Duration::from_secs(30));
        let quieto = motor.ultima_actividad.lock().unwrap().elapsed();
        if quieto > INACTIVO && !motor.ocupado() {
            break;
        }
    }
    drop(c);
}
