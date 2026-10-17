//! El registrador del menú global: com.canonical.AppMenu.Registrar.
//!
//! Reemplaza a menu-global/registrador.py con el mismo comportamiento. Las apps que
//! publican su menú por DBusMenu (Qt, Chrome, Edge, Electron, Thunderbird, Firefox)
//! le dicen aquí qué ventana es suya y en qué ruta está el menú; la barra
//! (globalmenu@macos) se lo pregunta al cambiar de ventana.
//!
//! Existe porque el que trae Mint (appmenu-registrar de vala-panel) se cierra solo a
//! los pocos segundos y se lleva los registros; las apps registran una sola vez, al
//! abrir la ventana.
//!
//! Corre como servicio de usuario (appmenu-registrador.service) y lleva el nombre
//! mientras viva: lo pide con REPLACE_EXISTING y, si otro no lo suelta, espera en la
//! cola. Si lo pierde después de tenerlo, o con SIGTERM, sale con 0, como el Python.
//! Una llamada con argumentos que no son los de la interfaz da
//! org.freedesktop.zbus.Error en vez del InvalidArgs de GDBus (las apps no lo miran).
//!
//! Cuando una app se va del bus sin despedirse se quitan todas sus ventanas, como
//! hace el Python con Gio.bus_watch_name_on_connection.

use std::collections::HashSet;

use zbus::fdo::{self, DBusProxy, RequestNameFlags, RequestNameReply};
use zbus::message::Header;
use zbus::names::{BusName, WellKnownName};
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{ObjectPath, OwnedObjectPath};
use futures_lite::StreamExt;
use zbus::{interface, Connection};

const NOMBRE: &str = "com.canonical.AppMenu.Registrar";
const RUTA: &str = "/com/canonical/AppMenu/Registrar";

#[derive(Default)]
struct Registrador {
    /// (xid, nombre único de la app en el bus, ruta del menú), en el orden en que
    /// se registró cada xid por primera vez (el de un dict de Python).
    ventanas: Vec<(u32, String, OwnedObjectPath)>,
    /// Nombres únicos que se vigilan: cuando se van, se van sus ventanas.
    vigilados: HashSet<String>,
}

impl Registrador {
    fn buscar(&self, xid: u32) -> Option<usize> {
        self.ventanas.iter().position(|(x, _, _)| *x == xid)
    }

    async fn quitar(&mut self, i: usize, e: &SignalEmitter<'_>) {
        let (xid, _, _) = self.ventanas.remove(i);
        let _ = Self::window_unregistered(e, xid).await;
    }

    /// La app se cerró o se cayó sin despedirse: se van todas sus ventanas.
    async fn app_salio(&mut self, nombre: &str, e: &SignalEmitter<'_>) {
        while let Some(i) = self.ventanas.iter().position(|(_, s, _)| s == nombre) {
            self.quitar(i, e).await;
        }
        self.vigilados.remove(nombre);
    }
}

#[interface(name = "com.canonical.AppMenu.Registrar")]
impl Registrador {
    async fn register_window(
        &mut self,
        window_id: u32,
        menu_object_path: OwnedObjectPath,
        #[zbus(header)] h: Header<'_>,
        #[zbus(signal_emitter)] e: SignalEmitter<'_>,
        #[zbus(connection)] c: &Connection,
    ) -> fdo::Result<()> {
        let remitente = h.sender().map(|s| s.to_string()).unwrap_or_default();
        match self.buscar(window_id) {
            Some(i) => self.ventanas[i] = (window_id, remitente.clone(), menu_object_path.clone()),
            None => self.ventanas.push((window_id, remitente.clone(), menu_object_path.clone())),
        }
        let nuevo = self.vigilados.insert(remitente.clone());
        let _ = Self::window_registered(&e, window_id, &remitente, menu_object_path.as_ref()).await;
        // Gio avisa «se fue» enseguida si el nombre ya no tiene dueño al empezar a
        // vigilarlo; la salida de después la ve la tarea de NameOwnerChanged.
        if nuevo {
            if let (Ok(p), Ok(n)) = (DBusProxy::new(c).await, BusName::try_from(remitente.as_str())) {
                if let Ok(false) = p.name_has_owner(n).await {
                    self.app_salio(&remitente, &e).await;
                }
            }
        }
        Ok(())
    }

    async fn unregister_window(
        &mut self,
        window_id: u32,
        #[zbus(header)] h: Header<'_>,
        #[zbus(signal_emitter)] e: SignalEmitter<'_>,
    ) {
        // Solo la app dueña quita su ventana.
        let remitente = h.sender().map(|s| s.to_string()).unwrap_or_default();
        if let Some(i) = self.buscar(window_id) {
            if self.ventanas[i].1 == remitente {
                self.quitar(i, &e).await;
            }
        }
    }

    #[zbus(out_args("service", "menuObjectPath"))]
    async fn get_menu_for_window(&self, window_id: u32) -> (String, OwnedObjectPath) {
        match self.buscar(window_id) {
            Some(i) => (self.ventanas[i].1.clone(), self.ventanas[i].2.clone()),
            None => (String::new(), ObjectPath::from_static_str_unchecked("/").into()),
        }
    }

    #[zbus(out_args("menus"))]
    async fn get_menus(&self) -> Vec<(u32, String, OwnedObjectPath)> {
        self.ventanas.clone()
    }

    #[zbus(signal)]
    async fn window_registered(e: &SignalEmitter<'_>, window_id: u32, service: &str, menu_object_path: ObjectPath<'_>) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn window_unregistered(e: &SignalEmitter<'_>, window_id: u32) -> zbus::Result<()>;
}

async fn principal() -> zbus::Result<()> {
    let c = zbus::connection::Builder::session()?.serve_at(RUTA, Registrador::default())?.build().await?;
    let bus = DBusProxy::new(&c).await?;
    let adquirido = bus.receive_name_acquired().await?;
    let perdido = bus.receive_name_lost().await?;
    let cambios = bus.receive_name_owner_changed().await?;
    let nombre = WellKnownName::from_static_str(NOMBRE)?;
    // Sin DO_NOT_QUEUE: si otro lo tiene y no lo suelta, se espera en la cola.
    let mut dueno = c.request_name_with_flags(nombre.clone(), RequestNameFlags::ReplaceExisting.into()).await?
        == RequestNameReply::PrimaryOwner;
    let iface = c.object_server().interface::<_, Registrador>(RUTA).await?;
    // Las tres señales del bus en un solo flujo, en este orden de preferencia.
    enum Aviso {
        Adquirido(fdo::NameAcquired),
        Perdido(fdo::NameLost),
        Cambio(fdo::NameOwnerChanged),
        Terminar,
    }
    // SIGTERM (systemctl stop) sale con 0, como GLib.unix_signal_add del Python.
    let terminar = async_signal::Signals::new([async_signal::Signal::Term]).map_err(|e| zbus::Error::InputOutput(e.into()))?;
    let mut avisos = adquirido
        .map(Aviso::Adquirido)
        .or(perdido.map(Aviso::Perdido))
        .or(cambios.map(Aviso::Cambio))
        .or(terminar.map(|_| Aviso::Terminar));
    while let Some(aviso) = avisos.next().await {
        match aviso {
            Aviso::Adquirido(s) => {
                if s.args().map(|a| a.name == nombre).unwrap_or(false) {
                    dueno = true;
                }
            }
            Aviso::Perdido(s) => {
                // Al arrancar con otro dueño el bus no nos lo dio: solo se sale si
                // ya lo teníamos.
                if s.args().map(|a| a.name == nombre).unwrap_or(false) && dueno {
                    eprintln!("registrador: se perdió el nombre {NOMBRE}");
                    break;
                }
            }
            Aviso::Terminar => break,
            Aviso::Cambio(s) => {
                let Ok(a) = s.args() else { continue };
                if a.new_owner.is_none() && a.name.starts_with(':') {
                    let n = a.name.to_string();
                    let mut r = iface.get_mut().await;
                    if r.vigilados.contains(&n) {
                        r.app_salio(&n, iface.signal_emitter()).await;
                    }
                }
            }
        }
    }
    Ok(())
}

fn main() {
    if let Err(e) = zbus::block_on(principal()) {
        eprintln!("registrador: {e}");
        std::process::exit(1);
    }
}
