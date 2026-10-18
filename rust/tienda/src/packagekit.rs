//! PackageKit por D-Bus (bus de sistema), con zbus: lo mismo que hace mintinstall por
//! su biblioteca, sin ella. Cada operación es una transacción: CreateTransaction,
//! SetHints (interactiva, para que polkit pregunte por mac-polkit), el método, y las
//! señales hasta Finished.
//!
//! Los valores de los enums salen de la biblioteca de PackageKit 1.2.8 de esta
//! máquina (PackageKitGlib por gi): filtros installed=4, ~installed=8,
//! newest=65536, arch=262144; only-trusted=2; Status, Exit, Info y Error abajo.
//!
//! TIENDA_BUS_SISTEMA=dirección usa otro bus en vez del de sistema (las pruebas
//! ponen ahí un PackageKit de mentira).

use std::collections::HashMap;

use zbus::blocking::{Connection, MessageIterator};
use zbus::message::Type as TipoMensaje;
use zbus::zvariant::{OwnedObjectPath, OwnedValue};
use zbus::MatchRule;

const PK: &str = "org.freedesktop.PackageKit";
const PK_RUTA: &str = "/org/freedesktop/PackageKit";
const PK_TX: &str = "org.freedesktop.PackageKit.Transaction";

pub const FILTRO_NINGUNO: u64 = 2;
pub const FILTRO_INSTALADOS: u64 = 4;
pub const FILTRO_NO_INSTALADOS: u64 = 8;
pub const FILTRO_MAS_NUEVO: u64 = 65536;
pub const FILTRO_ARQUITECTURA: u64 = 262144;
const SOLO_CONFIABLES: u64 = 2;

/// Un paquete como lo da PackageKit: «nombre;versión;arquitectura;datos».
#[derive(Debug, Clone, PartialEq)]
pub struct Paquete {
    pub info: u32,
    pub id: String,
    pub resumen: String,
}

impl Paquete {
    pub fn nombre(&self) -> &str {
        self.id.split(';').next().unwrap_or("")
    }
    pub fn version(&self) -> &str {
        self.id.split(';').nth(1).unwrap_or("")
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct FalloPk {
    /// El `codigo` de la señal Terminado (DBUS.md).
    pub clase: &'static str,
    pub mensaje: String,
}

/// ErrorCode de PackageKit → la clase de DBUS.md.
pub fn clase_error(code: u32) -> &'static str {
    match code {
        48 => "sin-autorizacion",
        2 => "sin-red",
        46 => "sin-espacio",
        26 | 67 => "ocupado",
        17 => "cancelado",
        _ => "fallo",
    }
}

/// Status de PackageKit → la etapa de DBUS.md.
pub fn etapa(status: u32) -> &'static str {
    match status {
        31 => "autorizando",
        8 => "descargando",
        9 | 10 => "instalando",
        6 => "quitando",
        11 => "limpiando",
        7 => "refrescando",
        _ => "esperando",
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ProgresoPk {
    pub porcentaje: u32,
    pub etapa: &'static str,
}

/// Lo que dejó una transacción.
#[derive(Debug, Default)]
pub struct Resultado {
    pub paquetes: Vec<Paquete>,
    pub detalles: Vec<HashMap<String, OwnedValue>>,
}

pub struct PackageKit {
    bus: Connection,
}

fn error(e: zbus::Error) -> FalloPk {
    let m = e.to_string();
    FalloPk { clase: if m.contains("NotAuthorized") || m.contains("not authorized") { "sin-autorizacion" } else { "fallo" }, mensaje: m }
}

impl PackageKit {
    pub fn conectar() -> Result<PackageKit, FalloPk> {
        let bus = match std::env::var("TIENDA_BUS_SISTEMA") {
            Ok(dir) => zbus::blocking::connection::Builder::address(dir.as_str()).and_then(|b| b.build()),
            Err(_) => Connection::system(),
        }
        .map_err(error)?;
        Ok(PackageKit { bus })
    }

    /// Una transacción entera. `metodo` y `args` son los de org.freedesktop.PackageKit.Transaction.
    /// `cancelar` se consulta en cada señal: si dice true, se pide Cancel una vez.
    pub fn transaccion<A>(&self, metodo: &str, args: &A, progreso: &mut dyn FnMut(ProgresoPk), cancelar: &dyn Fn() -> bool) -> Result<Resultado, FalloPk>
    where
        A: serde::Serialize + zbus::zvariant::DynamicType,
    {
        let r = self.bus.call_method(Some(PK), PK_RUTA, Some(PK), "CreateTransaction", &()).map_err(error)?;
        let tx: OwnedObjectPath = r.body().deserialize().map_err(error)?;
        // La escucha antes de la llamada: Finished no se pierde.
        let regla = MatchRule::builder().msg_type(TipoMensaje::Signal).sender(PK).map_err(error)?.path(tx.as_str()).map_err(error)?.build();
        let mensajes = MessageIterator::for_match_rule(regla, &self.bus, None).map_err(error)?;
        let locale = std::env::var("LANG").unwrap_or_else(|_| "C".into());
        let hints = vec!["interactive=true".to_string(), format!("locale={locale}"), "background=false".to_string()];
        self.bus.call_method(Some(PK), tx.as_str(), Some(PK_TX), "SetHints", &(hints,)).map_err(error)?;
        self.bus.call_method(Some(PK), tx.as_str(), Some(PK_TX), metodo, args).map_err(error)?;
        let mut res = Resultado::default();
        let mut fallo: Option<FalloPk> = None;
        let (mut pct, mut st) = (101u32, 0u32);
        let mut cancelado = false;
        for m in mensajes {
            let Ok(m) = m else { break };
            if cancelar() && !cancelado {
                cancelado = true;
                let _ = self.bus.call_method(Some(PK), tx.as_str(), Some(PK_TX), "Cancel", &());
            }
            let h = m.header();
            let (Some(iface), Some(miembro)) = (h.interface().map(|i| i.to_string()), h.member().map(|m| m.to_string())) else { continue };
            match (iface.as_str(), miembro.as_str()) {
                (PK_TX, "Package") => {
                    if let Ok((info, id, resumen)) = m.body().deserialize::<(u32, String, String)>() {
                        res.paquetes.push(Paquete { info, id, resumen });
                    }
                }
                (PK_TX, "Details") => {
                    if let Ok(d) = m.body().deserialize::<HashMap<String, OwnedValue>>() {
                        res.detalles.push(d);
                    }
                }
                (PK_TX, "ErrorCode") => {
                    if let Ok((code, detalle)) = m.body().deserialize::<(u32, String)>() {
                        fallo = Some(FalloPk { clase: clase_error(code), mensaje: detalle });
                    }
                }
                ("org.freedesktop.DBus.Properties", "PropertiesChanged") => {
                    if let Ok((_, cambios, _)) = m.body().deserialize::<(String, HashMap<String, OwnedValue>, Vec<String>)>() {
                        if let Some(v) = cambios.get("Percentage").and_then(|v| u32::try_from(v).ok()) {
                            pct = v;
                        }
                        if let Some(v) = cambios.get("Status").and_then(|v| u32::try_from(v).ok()) {
                            st = v;
                        }
                        progreso(ProgresoPk { porcentaje: pct, etapa: etapa(st) });
                    }
                }
                (PK_TX, "Finished") => {
                    let (exit, _) = m.body().deserialize::<(u32, u32)>().unwrap_or((2, 0));
                    return match (exit, fallo) {
                        (1, _) => Ok(res),
                        (3, _) | (9, _) => Err(FalloPk { clase: "cancelado", mensaje: String::new() }),
                        (_, Some(f)) => Err(f),
                        (e, None) => Err(FalloPk { clase: "fallo", mensaje: format!("PackageKit terminó con exit {e}") }),
                    };
                }
                _ => {}
            }
        }
        Err(FalloPk { clase: "fallo", mensaje: "PackageKit se fue sin terminar la transacción".into() })
    }

    fn sin_progreso(&self, metodo: &str, args: &(impl serde::Serialize + zbus::zvariant::DynamicType)) -> Result<Resultado, FalloPk> {
        self.transaccion(metodo, args, &mut |_| {}, &|| false)
    }

    /// Los ids de PackageKit de esos paquetes, con el filtro dado.
    pub fn resolver(&self, filtro: u64, nombres: &[String]) -> Result<Vec<Paquete>, FalloPk> {
        Ok(self.sin_progreso("Resolve", &(filtro, nombres.to_vec()))?.paquetes)
    }

    pub fn actualizaciones(&self) -> Result<Vec<Paquete>, FalloPk> {
        Ok(self.sin_progreso("GetUpdates", &(FILTRO_NINGUNO,))?.paquetes)
    }

    pub fn detalles(&self, ids: &[String]) -> Result<Vec<HashMap<String, OwnedValue>>, FalloPk> {
        Ok(self.sin_progreso("GetDetails", &(ids.to_vec(),))?.detalles)
    }

    pub fn instalar(&self, ids: &[String], p: &mut dyn FnMut(ProgresoPk), c: &dyn Fn() -> bool) -> Result<(), FalloPk> {
        self.transaccion("InstallPackages", &(SOLO_CONFIABLES, ids.to_vec()), p, c).map(|_| ())
    }

    /// Sin arrastrar lo que depende del paquete (allow_deps = false): si algo más lo
    /// necesita, PackageKit falla y no se quita nada.
    pub fn quitar(&self, ids: &[String], p: &mut dyn FnMut(ProgresoPk), c: &dyn Fn() -> bool) -> Result<(), FalloPk> {
        self.transaccion("RemovePackages", &(SOLO_CONFIABLES, ids.to_vec(), false, false), p, c).map(|_| ())
    }

    pub fn actualizar(&self, ids: &[String], p: &mut dyn FnMut(ProgresoPk), c: &dyn Fn() -> bool) -> Result<(), FalloPk> {
        self.transaccion("UpdatePackages", &(SOLO_CONFIABLES, ids.to_vec()), p, c).map(|_| ())
    }

    pub fn refrescar(&self, p: &mut dyn FnMut(ProgresoPk), c: &dyn Fn() -> bool) -> Result<(), FalloPk> {
        self.transaccion("RefreshCache", &(false,), p, c).map(|_| ())
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn enums() {
        assert_eq!(clase_error(48), "sin-autorizacion");
        assert_eq!(clase_error(26), "ocupado");
        assert_eq!(etapa(31), "autorizando");
        assert_eq!(etapa(8), "descargando");
        let p = Paquete { info: 2, id: "gimp;2.10.36-3;amd64;ubuntu".into(), resumen: String::new() };
        assert_eq!((p.nombre(), p.version()), ("gimp", "2.10.36-3"));
    }
}
