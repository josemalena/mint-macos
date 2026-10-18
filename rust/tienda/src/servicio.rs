//! org.mintmacos.Tienda1: la interfaz de DBUS.md sobre el índice, PackageKit,
//! libflatpak y la red. Lo que tarda (instalar, quitar, actualizar, refrescar) corre
//! en un hilo propio y avisa por señales; lo que lee la red va por `blocking::unblock`
//! para no trabar el bus mientras tanto.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use zbus::blocking::Connection;
use zbus::interface;
use zbus::zvariant::{OwnedValue, Value};

use crate::catalogo::{self, App, Origen, Rutas};
use crate::flatpak::{self, Cancelador, Instalacion, Operacion};
use crate::indice::{self, Indice};
use crate::packagekit::{self, PackageKit};
use crate::web::{self, Web};

pub const NOMBRE: &str = "org.mintmacos.Tienda1";
pub const RUTA: &str = "/org/mintmacos/Tienda1";

pub type Dict = HashMap<String, OwnedValue>;

fn ov<'a>(v: impl Into<Value<'a>>) -> OwnedValue {
    v.into().try_to_owned().expect("valor D-Bus sin descriptores")
}

fn ahora() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

/// ¿Está ese ícono en el tema? hicolor (cualquier tamaño) o /usr/share/pixmaps. Una app
/// de APT sin instalar trae su nombre de ícono pero no el ícono: ese no sirve.
fn tema_existe(nombre: &str) -> bool {
    use std::sync::OnceLock;
    static NOMBRES: OnceLock<std::collections::HashSet<String>> = OnceLock::new();
    let n = NOMBRES.get_or_init(|| {
        let mut h = std::collections::HashSet::new();
        let mut poner = |dir: &Path| {
            for e in fs::read_dir(dir).into_iter().flatten().flatten() {
                if let Some(base) = e.path().file_stem() {
                    h.insert(base.to_string_lossy().into_owned());
                }
            }
        };
        for tam in fs::read_dir("/usr/share/icons/hicolor").into_iter().flatten().flatten() {
            poner(&tam.path().join("apps"));
        }
        poner(Path::new("/usr/share/pixmaps"));
        h
    });
    n.contains(nombre.trim_end_matches(".png").trim_end_matches(".svg"))
}

// --- el motor -----------------------------------------------------------------

struct Trabajo {
    tipo: String,
    id: String,
    porcentaje: u32,
    cancelar: Arc<AtomicBool>,
    cancelador: Option<Arc<Cancelador>>,
}

pub struct Motor {
    rutas: Rutas,
    dpkg: PathBuf,
    /// /etc/linuxmint/info y /usr/share/mint-upgrade-info, bajo esta raíz.
    raiz: PathBuf,
    indice: Mutex<Option<Indice>>,
    listo: Condvar,
    /// La «firma» de lo instalado (mtimes de dpkg y de los deploy de Flatpak): si
    /// cambia, otro programa instaló o quitó algo.
    firma: Mutex<Vec<Option<SystemTime>>>,
    web: Web,
    trabajos: Mutex<HashMap<String, Trabajo>>,
    siguiente: AtomicU64,
    pub ultima_actividad: Mutex<Instant>,
    ultimo_refresco: Mutex<i64>,
    bus: Mutex<Option<Connection>>,
    /// Refrescar pide releer los catálogos aunque el caché diga que están al día.
    forzar: AtomicBool,
}

fn cache_indice() -> PathBuf {
    let casa = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
    std::env::var_os("XDG_CACHE_HOME").map(PathBuf::from).filter(|p| p.is_absolute()).unwrap_or_else(|| casa.join(".cache")).join("mint-macos/tienda/indice.json")
}

impl Motor {
    pub fn nuevo(rutas: Rutas, dpkg: PathBuf, raiz: PathBuf) -> Arc<Motor> {
        let m = Arc::new(Motor {
            rutas,
            dpkg,
            raiz,
            indice: Mutex::new(None),
            listo: Condvar::new(),
            firma: Mutex::new(Vec::new()),
            web: Web::nueva(),
            trabajos: Mutex::new(HashMap::new()),
            siguiente: AtomicU64::new(1),
            ultima_actividad: Mutex::new(Instant::now()),
            ultimo_refresco: Mutex::new(0),
            bus: Mutex::new(None),
            forzar: AtomicBool::new(false),
        });
        let m2 = m.clone();
        std::thread::spawn(move || m2.cargar());
        m
    }

    pub fn poner_bus(&self, c: Connection) {
        *self.bus.lock().unwrap() = Some(c);
    }

    fn firma_actual(&self) -> Vec<Option<SystemTime>> {
        let mut v = vec![fs::metadata(&self.dpkg).and_then(|m| m.modified()).ok()];
        for (_, d) in &self.rutas.flatpak {
            v.push(fs::metadata(d.join("app")).and_then(|m| m.modified()).ok());
            v.push(fs::metadata(d.join("repo/refs/heads")).and_then(|m| m.modified()).ok());
        }
        v
    }

    fn poner_apps(&self, apps: Vec<catalogo::App>) {
        let inst = indice::leer_instaladas(&self.rutas, &self.dpkg);
        *self.firma.lock().unwrap() = self.firma_actual();
        *self.indice.lock().unwrap() = Some(Indice::armar(apps, inst));
        self.listo.notify_all();
    }

    /// El índice: del caché en disco si los catálogos no cambiaron; si cambiaron, se
    /// sirve el viejo mientras se rearma; si no hay caché, se arma y se guarda.
    fn cargar(&self) {
        let idiomas = catalogo::Idiomas::del_entorno();
        let firma = catalogo::firma(&self.rutas, &idiomas);
        let archivo = cache_indice();
        if !self.forzar.swap(false, Ordering::SeqCst) {
            if let Some((apps, fresco)) = catalogo::leer_cache(&archivo, &firma) {
                self.poner_apps(apps);
                if fresco {
                    return;
                }
            }
        }
        let apps = catalogo::cargar(&self.rutas, &idiomas);
        catalogo::guardar_cache(&archivo, &firma, &apps);
        self.poner_apps(apps);
    }

    /// Vuelve a leer lo instalado y arma el índice otra vez (sin releer los catálogos).
    fn reinstalar(&self) -> Vec<String> {
        let inst = indice::leer_instaladas(&self.rutas, &self.dpkg);
        *self.firma.lock().unwrap() = self.firma_actual();
        let mut g = self.indice.lock().unwrap();
        let Some(viejo) = g.take() else { return Vec::new() };
        let antes: HashMap<String, bool> = viejo.apps.iter().map(|a| (a.id.clone(), viejo.instaladas.version(a).is_some())).collect();
        let nuevo = Indice::armar(viejo.apps, inst);
        let cambiaron = nuevo.apps.iter().filter(|a| antes.get(&a.id).copied() != Some(nuevo.instaladas.version(a).is_some())).map(|a| a.id.clone()).collect();
        *g = Some(nuevo);
        cambiaron
    }

    /// El índice, esperando la primera carga. Si lo instalado cambió por fuera, se
    /// relee antes (y se avisa InstaladasCambiaron).
    fn con_indice<R>(&self, f: impl FnOnce(&Indice) -> R) -> R {
        *self.ultima_actividad.lock().unwrap() = Instant::now();
        if self.indice.lock().unwrap().is_some() && *self.firma.lock().unwrap() != self.firma_actual() {
            let c = self.reinstalar();
            if !c.is_empty() {
                self.emitir("InstaladasCambiaron", &(c,));
            }
        }
        let mut g = self.indice.lock().unwrap();
        while g.is_none() {
            g = self.listo.wait(g).unwrap();
        }
        f(g.as_ref().unwrap())
    }

    fn emitir<B: serde::Serialize + zbus::zvariant::DynamicType>(&self, senal: &str, cuerpo: &B) {
        if let Some(c) = self.bus.lock().unwrap().as_ref() {
            let _ = c.emit_signal(None::<&str>, RUTA, NOMBRE, senal, cuerpo);
        }
    }

    pub fn ocupado(&self) -> bool {
        !self.trabajos.lock().unwrap().is_empty()
    }

    // --- resúmenes y fichas ---

    fn resumen(&self, ix: &Indice, a: &App) -> Dict {
        let mut d = Dict::new();
        d.insert("id".into(), ov(a.id.clone()));
        d.insert("appstream_id".into(), ov(a.appstream_id.clone()));
        d.insert("nombre".into(), ov(a.nombre.clone()));
        if !a.resumen.is_empty() {
            d.insert("resumen".into(), ov(a.resumen.clone()));
        }
        // El ícono: el archivo de la app, o el de otra variante de la misma ficha (el
        // Flatpak de una app de APT trae casi siempre el suyo en disco); el del tema
        // solo si de verdad está instalado; la URL, al final.
        let hermanas: Vec<&App> = ix.por_id.get(&a.id).map(|n| &ix.fichas[*n]).map(|f| std::iter::once(f.app).chain(f.otras.iter().copied()).map(|i| &ix.apps[i]).filter(|x| x.id != a.id).collect()).unwrap_or_default();
        let tema = a.icono_tema.as_ref().filter(|t| tema_existe(t));
        if let Some(p) = a.icono_archivo.as_ref().or_else(|| hermanas.iter().find_map(|h| h.icono_archivo.as_ref())) {
            d.insert("icono".into(), ov(p.to_string_lossy().into_owned()));
        } else if tema.is_none() {
            if let Some(u) = a.icono_url.as_ref().or_else(|| hermanas.iter().find_map(|h| h.icono_url.as_ref())) {
                d.insert("icono".into(), ov(u.clone()));
            }
        }
        if let Some(t) = tema {
            d.insert("icono_tema".into(), ov(t.clone()));
        }
        d.insert("origen".into(), ov(a.origen_nombre()));
        let iv = ix.instaladas.version(a);
        d.insert("instalada".into(), ov(iv.is_some()));
        if let Some(i) = iv.filter(|i| !i.is_empty()) {
            d.insert("version_instalada".into(), ov(i.to_string()));
        }
        if let Some(v) = &a.version {
            d.insert("version".into(), ov(v.clone()));
        }
        if let Some(dev) = &a.desarrollador {
            d.insert("desarrollador".into(), ov(dev.clone()));
        }
        d
    }

    fn resumenes(&self, ix: &Indice, fichas: &[usize]) -> Vec<Dict> {
        fichas.iter().map(|n| self.resumen(ix, ix.app(&ix.fichas[*n]))).collect()
    }

    fn ficha_local(&self, id: &str) -> Option<(Dict, App)> {
        self.con_indice(|ix| {
            let n = *ix.por_id.get(id)?;
            let f = &ix.fichas[n];
            // La que se pidió, aunque no sea la que gana: la UI puede pedir una de otras_fuentes.
            let a = ix.apps.iter().find(|a| a.id == id)?;
            let mut d = self.resumen(ix, a);
            if !a.descripcion.is_empty() {
                d.insert("descripcion".into(), ov(a.descripcion.clone()));
            }
            let caps: Vec<(String, String, String)> = a.capturas.iter().map(|c| (c.grande.clone(), c.miniatura.clone(), c.pie.clone())).collect();
            if !caps.is_empty() {
                d.insert("capturas".into(), ov(caps));
            }
            if let Some(t) = a.fecha_version {
                d.insert("fecha_version".into(), ov(t));
            }
            if let Some(n) = &a.notas_version {
                d.insert("notas_version".into(), ov(n.clone()));
            }
            if let Some(l) = &a.licencia {
                d.insert("licencia".into(), ov(l.clone()));
            }
            for (tipo, clave) in [("homepage", "web"), ("help", "ayuda"), ("donation", "donar"), ("bugtracker", "errores")] {
                if let Some((_, u)) = a.urls.iter().find(|(t, _)| t == tipo) {
                    d.insert(clave.into(), ov(u.clone()));
                }
            }
            if !a.categorias.is_empty() {
                d.insert("categorias".into(), ov(a.categorias.clone()));
            }
            if !a.edad.is_empty() {
                let m: HashMap<String, String> = a.edad.iter().cloned().collect();
                d.insert("clasificacion_edad".into(), ov(m));
            }
            let otras: Vec<String> = std::iter::once(f.app).chain(f.otras.iter().copied()).map(|i| ix.apps[i].id.clone()).filter(|x| x != id).collect();
            if !otras.is_empty() {
                d.insert("otras_fuentes".into(), ov(otras));
            }
            Some((d, a.clone()))
        })
    }

    /// La ficha entera: lo local más tamaños, instalaciones del mes y la nota (red).
    pub fn ficha(&self, id: &str) -> Option<Dict> {
        let (mut d, a) = self.ficha_local(id)?;
        match (&a.origen, &a.flatpak, &a.paquete) {
            (Origen::Flatpak, Some(f), _) => {
                if let Ok((desc, inst)) = Instalacion::abrir(&f.instalacion).and_then(|i| i.tamanos(&f.remote, &f.referencia)) {
                    d.insert("tamano_descarga".into(), ov(desc));
                    d.insert("tamano_instalada".into(), ov(inst));
                }
                if f.remote == "flathub" {
                    if let Some(n) = self.web.instalaciones_mes(&a.appstream_id) {
                        d.insert("instalaciones_mes".into(), ov(n));
                        d.insert("fuente_instalaciones".into(), ov(format!("flathub:/stats/{}", a.appstream_id)));
                    }
                }
            }
            (Origen::Apt, _, Some(p)) => {
                if let Ok(pk) = PackageKit::conectar() {
                    if let Ok(ps) = pk.resolver(packagekit::FILTRO_MAS_NUEVO | packagekit::FILTRO_ARQUITECTURA, std::slice::from_ref(p)) {
                        let ids: Vec<String> = ps.iter().map(|x| x.id.clone()).take(1).collect();
                        if let Some(det) = pk.detalles(&ids).ok().and_then(|v| v.into_iter().next()) {
                            if let Some(t) = det.get("size").and_then(|v| u64::try_from(v).ok()).filter(|t| *t > 0) {
                                d.insert("tamano_instalada".into(), ov(t));
                            }
                            if let Some(t) = det.get("download-size").and_then(|v| u64::try_from(v).ok()).filter(|t| *t > 0) {
                                d.insert("tamano_descarga".into(), ov(t));
                            }
                        }
                    }
                }
            }
            _ => {}
        }
        if let Some((e, total)) = self.web.nota(&a.appstream_id) {
            d.insert("nota".into(), ov(web::promedio(&e, total)));
            d.insert("votos".into(), ov(total));
            d.insert("votos_por_estrella".into(), ov(e.to_vec()));
            d.insert("fuente_nota".into(), ov(format!("odrs:/1.0/reviews/api/ratings/{}", a.appstream_id)));
        }
        Some(d)
    }

    pub fn resenas(&self, appstream_id: &str, limite: u32) -> Vec<Dict> {
        let version = self.con_indice(|ix| ix.por_appstream.get(appstream_id).and_then(|n| ix.app(&ix.fichas[*n]).version.clone())).unwrap_or_default();
        let Some(v) = self.web.resenas(appstream_id, &version, limite) else { return Vec::new() };
        v.iter()
            .filter(|r| r["reported"].as_u64().unwrap_or(0) == 0)
            .map(|r| {
                let mut d = Dict::new();
                for (clave, campo) in [("resumen", "summary"), ("texto", "description"), ("autor", "user_display"), ("version", "version"), ("distro", "distro")] {
                    if let Some(s) = r[campo].as_str().filter(|s| !s.is_empty()) {
                        d.insert(clave.into(), ov(s.to_string()));
                    }
                }
                if let Some(n) = r["rating"].as_f64() {
                    d.insert("nota".into(), ov(n / 20.0));
                }
                if let Some(t) = r["date_created"].as_f64() {
                    d.insert("fecha".into(), ov(t as i64));
                }
                d
            })
            .collect()
    }

    pub fn buscar(&self, texto: &str, origenes: &[String], limite: u32) -> Vec<Dict> {
        self.con_indice(|ix| self.resumenes(ix, &ix.buscar(texto, origenes, limite.clamp(1, 500) as usize)))
    }

    pub fn listar(&self, categoria: &str, desde: u32, limite: u32) -> Vec<Dict> {
        let cats: Vec<&str> = match indice::categorias_de(categoria) {
            Some(c) => c.to_vec(),
            None => vec![categoria],
        };
        self.con_indice(|ix| {
            let v = ix.en_categorias(&cats);
            let fin = (desde as usize + limite.clamp(1, 500) as usize).min(v.len());
            self.resumenes(ix, v.get(desde as usize..fin).unwrap_or(&[]))
        })
    }

    /// Los estantes de una sección. Cada uno con su fuente; si la fuente no da nada, no viene.
    pub fn estantes(&self, seccion: &str) -> Vec<(String, String, String, String, Vec<Dict>)> {
        let hoy = {
            let o = std::process::Command::new("date").arg("+%F").output();
            o.ok().map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string()).unwrap_or_default()
        };
        let mut pedidos: Vec<(String, String, String, String, Option<Vec<String>>)> = Vec::new();
        match seccion {
            "discover" => {
                pedidos.push(("app-del-dia".into(), "App of the Day".into(), "destacada".into(), format!("flathub:/app-picks/app-of-the-day/{hoy}"), self.web.app_del_dia(&hoy).map(|a| vec![a])));
                pedidos.push(("apps-de-la-semana".into(), "Apps of the Week".into(), "fila".into(), format!("flathub:/app-picks/apps-of-the-week/{hoy}"), self.web.apps_de_la_semana(&hoy)));
                pedidos.push(("populares".into(), "Popular".into(), "lista-numerada".into(), "flathub:/collection/popular".into(), self.web.coleccion("popular", 24)));
                pedidos.push(("tendencia".into(), "Trending".into(), "lista-numerada".into(), "flathub:/collection/trending".into(), self.web.coleccion("trending", 24)));
                pedidos.push(("nuevas".into(), "New Apps".into(), "fila".into(), "flathub:/collection/recently-added".into(), self.web.coleccion("recently-added", 24)));
                pedidos.push(("actualizadas".into(), "Recently Updated".into(), "fila".into(), "flathub:/collection/recently-updated".into(), self.web.coleccion("recently-updated", 24)));
            }
            s => {
                let cats: &[&str] = match s {
                    "create" => &["graphics", "audiovideo"],
                    "work" => &["office"],
                    "play" => &["game"],
                    "develop" => &["development"],
                    _ => &[],
                };
                for c in cats {
                    let ruta = format!("category/{c}?sort_by=installs_last_month");
                    pedidos.push((format!("populares-{s}-{c}"), format!("Top {c}"), "lista-numerada".into(), format!("flathub:/collection/category/{c}?sort_by=installs_last_month"), self.web.coleccion(&ruta, 24)));
                }
            }
        }
        self.con_indice(|ix| {
            pedidos
                .into_iter()
                .filter_map(|(id, titulo, tipo, fuente, apps)| {
                    let apps = apps?;
                    let fichas: Vec<usize> = apps.iter().filter_map(|a| ix.por_appstream.get(a).copied()).collect();
                    (!fichas.is_empty()).then(|| (id, titulo, tipo, fuente, self.resumenes(ix, &fichas)))
                })
                .collect()
        })
    }

    // --- trabajos ---

    fn nuevo_trabajo(&self, tipo: &str, id: &str, cancelador: Option<Arc<Cancelador>>) -> (String, Arc<AtomicBool>) {
        let n = format!("t{}", self.siguiente.fetch_add(1, Ordering::SeqCst));
        let c = Arc::new(AtomicBool::new(false));
        self.trabajos.lock().unwrap().insert(n.clone(), Trabajo { tipo: tipo.into(), id: id.into(), porcentaje: 0, cancelar: c.clone(), cancelador });
        (n, c)
    }

    fn progreso(&self, t: &str, pct: u32, etapa: &str, bytes: u64, total: u64) {
        if let Some(j) = self.trabajos.lock().unwrap().get_mut(t) {
            j.porcentaje = pct;
        }
        self.emitir("Progreso", &(t, pct, etapa, bytes, total));
    }

    fn terminar(&self, t: &str, r: Result<(), (&'static str, String)>) {
        self.trabajos.lock().unwrap().remove(t);
        let (ok, codigo, mensaje) = match r {
            Ok(()) => (true, "", String::new()),
            Err((c, m)) => (false, c, m),
        };
        let cambiaron = self.reinstalar();
        self.emitir("Terminado", &(t, ok, codigo, mensaje));
        if !cambiaron.is_empty() {
            self.emitir("InstaladasCambiaron", &(cambiaron,));
        }
        *self.ultima_actividad.lock().unwrap() = Instant::now();
    }

    fn app_de(&self, id: &str) -> Option<App> {
        self.con_indice(|ix| ix.apps.iter().find(|a| a.id == id).cloned())
    }

    fn correr_flatpak(self: &Arc<Self>, tipo: &str, a: &App, op: Operacion) -> Result<String, String> {
        let f = a.flatpak.clone().ok_or("sin fuente de Flatpak")?;
        let canc = Arc::new(Cancelador::nuevo());
        let (t, _) = self.nuevo_trabajo(tipo, &a.id, Some(canc.clone()));
        let (m, t2) = (self.clone(), t.clone());
        std::thread::spawn(move || {
            let r = Instalacion::abrir(&f.instalacion).and_then(|i| {
                flatpak::correr(&i, &[op], &canc, &mut |p| m.progreso(&t2, p.porcentaje, p.etapa, p.bytes, p.total))
            });
            m.terminar(&t2, r.map_err(|e| (e.clase(), e.mensaje)));
        });
        Ok(t)
    }

    fn correr_apt(self: &Arc<Self>, tipo: &'static str, id: &str, paquetes: Vec<String>, filtro: u64) -> Result<String, String> {
        let (t, cancelar) = self.nuevo_trabajo(tipo, id, None);
        let (m, t2) = (self.clone(), t.clone());
        std::thread::spawn(move || {
            let r = (|| {
                let pk = PackageKit::conectar()?;
                let ids: Vec<String> = if filtro == 0 {
                    paquetes
                } else {
                    let ps = pk.resolver(filtro, &paquetes)?;
                    // Un id por nombre (Resolve puede dar varias versiones o arquitecturas).
                    let mut vistos = std::collections::HashSet::new();
                    ps.into_iter().filter(|p| vistos.insert(p.nombre().to_string())).map(|p| p.id).collect()
                };
                if ids.is_empty() && tipo != "refrescar" {
                    return Err(packagekit::FalloPk { clase: "fallo", mensaje: "PackageKit no encontró el paquete".into() });
                }
                let mut prog = |p: packagekit::ProgresoPk| m.progreso(&t2, p.porcentaje, p.etapa, 0, 0);
                let canc = || cancelar.load(Ordering::SeqCst);
                match tipo {
                    "instalar" => pk.instalar(&ids, &mut prog, &canc),
                    "quitar" => pk.quitar(&ids, &mut prog, &canc),
                    "actualizar" => pk.actualizar(&ids, &mut prog, &canc),
                    _ => pk.refrescar(&mut prog, &canc),
                }
            })();
            m.terminar(&t2, r.map_err(|e| (e.clase, e.mensaje)));
        });
        Ok(t)
    }

    pub fn instalar(self: &Arc<Self>, id: &str) -> Result<String, String> {
        let a = self.app_de(id).ok_or("no hay una app con ese id")?;
        match a.origen {
            Origen::Flatpak => {
                let f = a.flatpak.clone().unwrap();
                self.correr_flatpak("instalar", &a, Operacion::Instalar { remote: f.remote, referencia: f.referencia })
            }
            Origen::Apt => {
                let p = a.paquete.clone().unwrap();
                self.correr_apt("instalar", &a.id, vec![p], packagekit::FILTRO_NO_INSTALADOS | packagekit::FILTRO_MAS_NUEVO | packagekit::FILTRO_ARQUITECTURA)
            }
        }
    }

    pub fn quitar(self: &Arc<Self>, id: &str) -> Result<String, String> {
        let a = self.app_de(id).ok_or("no hay una app con ese id")?;
        match a.origen {
            Origen::Flatpak => {
                let f = a.flatpak.clone().unwrap();
                self.correr_flatpak("quitar", &a, Operacion::Quitar { referencia: f.referencia })
            }
            Origen::Apt => self.correr_apt("quitar", &a.id, vec![a.paquete.clone().unwrap()], packagekit::FILTRO_INSTALADOS),
        }
    }

    /// Las actualizaciones de un grupo, como Resúmenes. Para «sistema», los paquetes
    /// sin ficha llevan id «apt:<paquete>», el nombre del paquete y el resumen de
    /// PackageKit.
    pub fn actualizaciones(&self, grupo: &str) -> Result<Vec<Dict>, String> {
        let pk_updates = PackageKit::conectar().and_then(|pk| pk.actualizaciones()).map_err(|e| e.mensaje)?;
        let mut out = Vec::new();
        self.con_indice(|ix| {
            let con_ficha: HashMap<&str, &App> = ix.apps.iter().filter(|a| a.origen == Origen::Apt).filter_map(|a| Some((a.paquete.as_deref()?, a))).collect();
            for p in &pk_updates {
                match (grupo, con_ficha.get(p.nombre())) {
                    ("apps", Some(a)) => {
                        let mut d = self.resumen(ix, a);
                        d.insert("version".into(), ov(p.version().to_string()));
                        out.push(d);
                    }
                    ("sistema", None) => {
                        let mut d = Dict::new();
                        d.insert("id".into(), ov(format!("apt:{}", p.nombre())));
                        d.insert("nombre".into(), ov(p.nombre().to_string()));
                        d.insert("resumen".into(), ov(p.resumen.clone()));
                        d.insert("origen".into(), ov("apt"));
                        d.insert("version".into(), ov(p.version().to_string()));
                        if let Some(v) = ix.instaladas.apt.get(p.nombre()) {
                            d.insert("version_instalada".into(), ov(v.clone()));
                        }
                        d.insert("pk_id".into(), ov(p.id.clone()));
                        out.push(d);
                    }
                    _ => {}
                }
            }
        });
        if grupo == "apps" {
            for (inst, _) in &self.rutas.flatpak {
                let Ok(i) = Instalacion::abrir(inst) else { continue };
                for (referencia, remote) in i.actualizables().unwrap_or_default() {
                    if !referencia.starts_with("app/") {
                        continue;
                    }
                    let id = format!("flatpak:{inst}/{remote}/{referencia}");
                    if let Some(d) = self.con_indice(|ix| ix.apps.iter().find(|a| a.id == id).map(|a| self.resumen(ix, a))) {
                        out.push(d);
                    }
                }
            }
        }
        Ok(out)
    }

    pub fn actualizar(self: &Arc<Self>, grupo: &str, ids: Vec<String>) -> Result<String, String> {
        let todas = self.actualizaciones(grupo)?;
        let elegidas: Vec<&Dict> = todas.iter().filter(|d| ids.is_empty() || d.get("id").and_then(|v| <&str>::try_from(v).ok()).map(|i| ids.iter().any(|x| x == i)).unwrap_or(false)).collect();
        if elegidas.is_empty() {
            return Err("no hay nada que actualizar".into());
        }
        let texto = |d: &Dict, k: &str| d.get(k).and_then(|v| <&str>::try_from(v).ok()).unwrap_or("").to_string();
        let mut fp: HashMap<String, Vec<Operacion>> = HashMap::new();
        let mut apt: Vec<String> = Vec::new();
        for d in &elegidas {
            let id = texto(d, "id");
            if let Some(resto) = id.strip_prefix("flatpak:") {
                let mut p = resto.splitn(3, '/');
                let (inst, _remote, referencia) = (p.next().unwrap_or(""), p.next(), p.next().unwrap_or(""));
                fp.entry(inst.to_string()).or_default().push(Operacion::Actualizar { referencia: referencia.to_string() });
            } else if grupo == "sistema" {
                apt.push(texto(d, "pk_id"));
            } else {
                apt.push(id.trim_start_matches("apt:").to_string());
            }
        }
        let canc = Arc::new(Cancelador::nuevo());
        let (t, cancelar) = self.nuevo_trabajo("actualizar", grupo, Some(canc.clone()));
        let (m, t2, grupo) = (self.clone(), t.clone(), grupo.to_string());
        std::thread::spawn(move || {
            let mut r: Result<(), (&'static str, String)> = Ok(());
            for (inst, ops) in fp {
                if r.is_err() {
                    break;
                }
                r = Instalacion::abrir(&inst)
                    .and_then(|i| flatpak::correr(&i, &ops, &canc, &mut |p| m.progreso(&t2, p.porcentaje, p.etapa, p.bytes, p.total)))
                    .map_err(|e| (e.clase(), e.mensaje));
            }
            if r.is_ok() && !apt.is_empty() {
                r = (|| {
                    let pk = PackageKit::conectar()?;
                    let ids = if grupo == "sistema" {
                        apt
                    } else {
                        // De nombre a id de PackageKit: la versión nueva.
                        let todas = pk.actualizaciones()?;
                        todas.into_iter().filter(|p| apt.iter().any(|n| n == p.nombre())).map(|p| p.id).collect()
                    };
                    let canc_pk = || cancelar.load(Ordering::SeqCst);
                    pk.actualizar(&ids, &mut |p| m.progreso(&t2, p.porcentaje, p.etapa, 0, 0), &canc_pk)
                })()
                .map_err(|e| (e.clase, e.mensaje));
            }
            m.terminar(&t2, r);
            m.emitir("ActualizacionesCambiaron", &());
        });
        Ok(t)
    }

    /// Refrescar: el caché de APT (PackageKit) y el appstream de cada remote de Flatpak;
    /// después se releen los catálogos.
    pub fn refrescar(self: &Arc<Self>) -> Result<String, String> {
        let (t, cancelar) = self.nuevo_trabajo("refrescar", "", None);
        let (m, t2) = (self.clone(), t.clone());
        std::thread::spawn(move || {
            let r = PackageKit::conectar().and_then(|pk| pk.refrescar(&mut |p| m.progreso(&t2, p.porcentaje.min(90), p.etapa, 0, 0), &|| cancelar.load(Ordering::SeqCst))).map_err(|e| (e.clase, e.mensaje));
            for (inst, dir) in &m.rutas.flatpak {
                let Ok(i) = Instalacion::abrir(inst) else { continue };
                for rem in fs::read_dir(dir.join("appstream")).into_iter().flatten().flatten() {
                    let _ = i.refrescar_appstream(&rem.file_name().to_string_lossy());
                }
            }
            m.cargar();
            *m.ultimo_refresco.lock().unwrap() = ahora();
            m.terminar(&t2, r);
            m.emitir("ActualizacionesCambiaron", &());
        });
        Ok(t)
    }

    pub fn cancelar(&self, t: &str) -> bool {
        let g = self.trabajos.lock().unwrap();
        let Some(j) = g.get(t) else { return false };
        j.cancelar.store(true, Ordering::SeqCst);
        if let Some(c) = &j.cancelador {
            c.cancelar();
        }
        true
    }

    pub fn trabajos(&self) -> Vec<(String, String, String, u32)> {
        self.trabajos.lock().unwrap().iter().map(|(n, j)| (n.clone(), j.tipo.clone(), j.id.clone(), j.porcentaje)).collect()
    }

    /// La actualización de apps sola, como la Mac: los Flatpak de usuario, sin clave, si
    /// auto-update-flatpaks (com.linuxmint.updates) está encendido. Los de sistema los
    /// actualiza la automatización de Mint, que corre como root.
    pub fn auto_actualizar(self: &Arc<Self>) {
        let o = std::process::Command::new("gsettings").args(["get", "com.linuxmint.updates", "auto-update-flatpaks"]).output();
        if o.map(|o| String::from_utf8_lossy(&o.stdout).trim() != "true").unwrap_or(true) || self.ocupado() {
            return;
        }
        let Ok(i) = Instalacion::abrir("user") else { return };
        let refs: Vec<Operacion> = i.actualizables().unwrap_or_default().into_iter().map(|(r, _)| Operacion::Actualizar { referencia: r }).collect();
        if refs.is_empty() {
            return;
        }
        let canc = Arc::new(Cancelador::nuevo());
        let (t, _) = self.nuevo_trabajo("actualizar", "apps", Some(canc.clone()));
        let r = flatpak::correr(&i, &refs, &canc, &mut |p| self.progreso(&t, p.porcentaje, p.etapa, p.bytes, p.total)).map_err(|e| (e.clase(), e.mensaje));
        self.terminar(&t, r);
        self.emitir("ActualizacionesCambiaron", &());
    }

    // --- el salto de versión de Mint (DBUS.md) ---

    pub fn nueva_version(&self) -> Dict {
        nueva_version(&self.raiz, std::env::consts::ARCH)
    }

    pub fn subir_version(self: &Arc<Self>) -> Result<String, String> {
        let d = self.nueva_version();
        let herr = d.get("herramienta").and_then(|v| <&str>::try_from(v).ok()).map(String::from).ok_or("no hay una versión nueva")?;
        let instalada = d.get("herramienta_instalada").and_then(|v| bool::try_from(v).ok()).unwrap_or(false);
        let (t, cancelar) = self.nuevo_trabajo("subir-version", &herr, None);
        let (m, t2) = (self.clone(), t.clone());
        std::thread::spawn(move || {
            let mut r: Result<(), (&'static str, String)> = Ok(());
            if !instalada {
                r = PackageKit::conectar()
                    .and_then(|pk| {
                        let ids: Vec<String> = pk.resolver(packagekit::FILTRO_NO_INSTALADOS | packagekit::FILTRO_MAS_NUEVO | packagekit::FILTRO_ARQUITECTURA, &[herr.clone()])?.into_iter().map(|p| p.id).take(1).collect();
                        pk.instalar(&ids, &mut |p| m.progreso(&t2, p.porcentaje, p.etapa, 0, 0), &|| cancelar.load(Ordering::SeqCst))
                    })
                    .map_err(|e| (e.clase, e.mensaje));
            }
            if r.is_ok() {
                m.progreso(&t2, 101, "esperando", 0, 0);
                r = std::process::Command::new(&herr).status().map(|_| ()).map_err(|e| ("fallo", e.to_string()));
            }
            m.terminar(&t2, r);
        });
        Ok(t)
    }
}

/// Un archivo de /usr/share/mint-upgrade-info: [general] clave = valor.
fn leer_info(p: &Path) -> HashMap<String, String> {
    fs::read_to_string(p)
        .unwrap_or_default()
        .lines()
        .filter_map(|l| l.split_once('='))
        .map(|(k, v)| (k.trim().to_string(), v.trim().trim_matches('"').to_string()))
        .collect()
}

/// La regla de los informes 070 y 071 de mintreport.
pub fn nueva_version(raiz: &Path, arco: &str) -> Dict {
    let mut d = Dict::new();
    let info = leer_info(&raiz.join("etc/linuxmint/info"));
    let (Some(codename), Some(edicion)) = (info.get("CODENAME"), info.get("EDITION")) else { return d };
    let edicion = edicion.split_whitespace().next().unwrap_or("").to_lowercase();
    let arco_deb = match arco {
        "x86_64" => "amd64",
        "aarch64" => "arm64",
        a => a,
    };
    let base = raiz.join("usr/share/mint-upgrade-info");
    let lista = |s: &str| s.split(',').map(|x| x.trim().to_lowercase()).collect::<Vec<_>>();
    let ver = |p: &Path| raiz.join("usr/bin").join(p).exists();
    let mayor = leer_info(&base.join(format!("{codename}-major/info")));
    let menor = leer_info(&base.join(format!("{codename}/info")));
    if mayor.get("editions").map(|e| lista(e).contains(&edicion)).unwrap_or(false) && mayor.get("architectures").map(|a| lista(a).contains(&arco_deb.to_string())).unwrap_or(false) {
        d.insert("tipo".into(), ov("mayor"));
        d.insert("nombre".into(), ov(mayor.get("target_name").cloned().unwrap_or_default()));
        if let Some(l) = mayor.get("link") {
            d.insert("enlace".into(), ov(l.clone()));
        }
        d.insert("herramienta".into(), ov("mintupgrade"));
        d.insert("herramienta_instalada".into(), ov(ver(Path::new("mintupgrade"))));
    } else if menor.get("editions").map(|e| lista(e).contains(&edicion)).unwrap_or(false) {
        let destino = menor.get("target_codename").cloned().unwrap_or_default();
        d.insert("tipo".into(), ov("menor"));
        d.insert("nombre".into(), ov(menor.get("target_name").cloned().unwrap_or_default()));
        d.insert("codename".into(), ov(destino.clone()));
        let img = base.join(codename).join(format!("{edicion}.png"));
        if img.is_file() {
            d.insert("imagen".into(), ov(img.to_string_lossy().into_owned()));
        }
        d.insert("enlace".into(), ov(format!("https://www.linuxmint.com/rel_{destino}_whatsnew.php")));
        d.insert("herramienta".into(), ov("mint-release-upgrade"));
        d.insert("herramienta_instalada".into(), ov(ver(Path::new("mint-release-upgrade"))));
    }
    d
}

// --- la interfaz D-Bus ---------------------------------------------------------

pub struct Servicio {
    pub motor: Arc<Motor>,
}

fn err(m: impl Into<String>) -> zbus::fdo::Error {
    zbus::fdo::Error::Failed(m.into())
}

#[interface(name = "org.mintmacos.Tienda1")]
impl Servicio {
    async fn buscar(&self, texto: String, origenes: Vec<String>, limite: u32) -> Vec<Dict> {
        let m = self.motor.clone();
        blocking::unblock(move || m.buscar(&texto, &origenes, limite)).await
    }

    fn secciones(&self) -> Vec<(String, String, Vec<String>)> {
        indice::SECCIONES.iter().map(|(i, t, c)| (i.to_string(), t.to_string(), c.iter().map(|s| s.to_string()).collect())).collect()
    }

    fn categorias(&self) -> Vec<(String, String, Vec<String>)> {
        indice::CATEGORIAS.iter().map(|(i, t, c)| (i.to_string(), t.to_string(), c.iter().map(|s| s.to_string()).collect())).collect()
    }

    async fn listar_categoria(&self, categoria: String, desde: u32, limite: u32) -> Vec<Dict> {
        let m = self.motor.clone();
        blocking::unblock(move || m.listar(&categoria, desde, limite)).await
    }

    async fn estantes(&self, seccion: String) -> Vec<(String, String, String, String, Vec<Dict>)> {
        let m = self.motor.clone();
        blocking::unblock(move || m.estantes(&seccion)).await
    }

    async fn ficha(&self, id: String) -> zbus::fdo::Result<Dict> {
        let m = self.motor.clone();
        blocking::unblock(move || m.ficha(&id)).await.ok_or_else(|| err("no hay una app con ese id"))
    }

    async fn resenas(&self, appstream_id: String, limite: u32) -> Vec<Dict> {
        let m = self.motor.clone();
        blocking::unblock(move || m.resenas(&appstream_id, limite.clamp(1, 50))).await
    }

    async fn instalar(&self, id: String) -> zbus::fdo::Result<String> {
        let m = self.motor.clone();
        blocking::unblock(move || m.instalar(&id)).await.map_err(err)
    }

    async fn quitar(&self, id: String) -> zbus::fdo::Result<String> {
        let m = self.motor.clone();
        blocking::unblock(move || m.quitar(&id)).await.map_err(err)
    }

    async fn actualizaciones(&self, grupo: String) -> zbus::fdo::Result<Vec<Dict>> {
        if grupo != "apps" && grupo != "sistema" {
            return Err(err("el grupo es «apps» o «sistema»"));
        }
        let m = self.motor.clone();
        blocking::unblock(move || m.actualizaciones(&grupo)).await.map_err(err)
    }

    async fn actualizar(&self, grupo: String, ids: Vec<String>) -> zbus::fdo::Result<String> {
        if grupo != "apps" && grupo != "sistema" {
            return Err(err("el grupo es «apps» o «sistema»"));
        }
        let m = self.motor.clone();
        blocking::unblock(move || m.actualizar(&grupo, ids)).await.map_err(err)
    }

    async fn refrescar(&self) -> zbus::fdo::Result<String> {
        self.motor.refrescar().map_err(err)
    }

    fn cancelar(&self, trabajo: String) -> bool {
        self.motor.cancelar(&trabajo)
    }

    fn trabajos(&self) -> Vec<(String, String, String, u32)> {
        self.motor.trabajos()
    }

    fn nueva_version(&self) -> Dict {
        self.motor.nueva_version()
    }

    async fn subir_version(&self) -> zbus::fdo::Result<String> {
        self.motor.subir_version().map_err(err)
    }

    #[zbus(property)]
    fn origenes(&self) -> Vec<(String, String, bool)> {
        let flatpak = self.motor.rutas.flatpak.iter().any(|(_, d)| d.join("appstream").is_dir());
        let apt = self.motor.rutas.dep11.is_dir();
        vec![("flatpak".into(), "Flatpak".into(), flatpak), ("apt".into(), "APT".into(), apt)]
    }

    #[zbus(property)]
    fn ocupado(&self) -> bool {
        self.motor.ocupado()
    }

    #[zbus(property)]
    fn ultimo_refresco(&self) -> i64 {
        *self.motor.ultimo_refresco.lock().unwrap()
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn salto_menor_y_mayor() {
        let r = std::env::temp_dir().join(format!("tienda-salto-{}", std::process::id()));
        let _ = fs::remove_dir_all(&r);
        fs::create_dir_all(r.join("etc/linuxmint")).unwrap();
        fs::create_dir_all(r.join("usr/share/mint-upgrade-info/zena")).unwrap();
        fs::create_dir_all(r.join("usr/bin")).unwrap();
        fs::write(r.join("etc/linuxmint/info"), "RELEASE=22.3\nCODENAME=zena\nEDITION=\"Cinnamon\"\n").unwrap();
        assert!(nueva_version(&r, "x86_64").is_empty(), "sin info no hay salto");
        fs::write(r.join("usr/share/mint-upgrade-info/zena/info"), "[general]\ntarget_name = \"Linux Mint 22.4 Zola\"\ntarget_codename = zola\neditions = cinnamon, mate, xfce\n").unwrap();
        fs::write(r.join("usr/bin/mint-release-upgrade"), "").unwrap();
        let d = nueva_version(&r, "x86_64");
        assert_eq!(<&str>::try_from(&d["tipo"]).unwrap(), "menor");
        assert_eq!(<&str>::try_from(&d["nombre"]).unwrap(), "Linux Mint 22.4 Zola");
        assert_eq!(<&str>::try_from(&d["herramienta"]).unwrap(), "mint-release-upgrade");
        assert!(bool::try_from(&d["herramienta_instalada"]).unwrap());
        // El mayor gana si aplica a la edición y la arquitectura.
        fs::create_dir_all(r.join("usr/share/mint-upgrade-info/zena-major")).unwrap();
        fs::write(r.join("usr/share/mint-upgrade-info/zena-major/info"), "[general]\ntarget_name = \"Linux Mint 23 X\"\neditions = cinnamon\narchitectures = amd64\nlink = https://blog.linuxmint.com/?p=1\n").unwrap();
        let d = nueva_version(&r, "x86_64");
        assert_eq!(<&str>::try_from(&d["tipo"]).unwrap(), "mayor");
        assert!(!bool::try_from(&d["herramienta_instalada"]).unwrap(), "mintupgrade no está");
        assert_eq!(<&str>::try_from(&nueva_version(&r, "aarch64")["tipo"]).unwrap(), "menor", "arm64 no está en el mayor");
        fs::remove_dir_all(&r).unwrap();
    }
}
