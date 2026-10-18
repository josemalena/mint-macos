//! mint-macos-tienda: el motor del App Store (ver DBUS.md).

mod catalogo;
mod indice;

fn main() {
    let t = std::time::Instant::now();
    let idiomas = catalogo::Idiomas::del_entorno();
    let apps = catalogo::cargar(&catalogo::Rutas::del_sistema(), &idiomas);
    let fp = apps.iter().filter(|a| a.origen == catalogo::Origen::Flatpak).count();
    eprintln!("{} apps ({} flatpak, {} apt) en {:?}", apps.len(), fp, apps.len() - fp, t.elapsed());
}
