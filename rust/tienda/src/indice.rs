//! El catálogo ya junto: qué está instalado, una ficha por app, la búsqueda y las
//! categorías.
//!
//! Una ficha por app (decisión de José, 18-10-2026): las variantes con el mismo
//! `appstream_id` se juntan y gana, en este orden, la que está instalada, la de
//! Flatpak de usuario, la de Flatpak de sistema y la de APT. Las demás van en
//! `otras_fuentes`.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};

use crate::catalogo::{App, Origen, Rutas};

/// Lo instalado: los paquetes de dpkg y los Flatpak de cada instalación.
#[derive(Debug, Default)]
pub struct Instaladas {
    /// paquete → versión.
    pub apt: HashMap<String, String>,
    /// (instalación, ref) → versión (de su metainfo; vacío si no la trae).
    pub flatpak: HashMap<(String, String), String>,
}

/// /var/lib/dpkg/status: los párrafos con «Status: install ok installed».
pub fn leer_dpkg(t: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    for p in t.split("\n\n") {
        let (mut paquete, mut version, mut ok) = (None, None, false);
        for l in p.lines() {
            if let Some(v) = l.strip_prefix("Package: ") {
                paquete = Some(v.trim());
            } else if let Some(v) = l.strip_prefix("Version: ") {
                version = Some(v.trim());
            } else if let Some(v) = l.strip_prefix("Status: ") {
                ok = v.trim().ends_with(" installed") && v.starts_with("install ");
            }
        }
        if let (Some(p), true) = (paquete, ok) {
            out.insert(p.to_string(), version.unwrap_or("").to_string());
        }
    }
    out
}

/// La versión de la release más nueva de un metainfo (lo que la app instalada dice ser).
fn version_metainfo(p: &Path) -> Option<String> {
    let t = fs::read_to_string(p).ok()?;
    let mut mejor: Option<(i64, String)> = None;
    for trozo in t.split("<release ").skip(1) {
        let cab = trozo.split('>').next().unwrap_or("");
        let attr = |n: &str| cab.split(&format!("{n}=\"")).nth(1).and_then(|r| r.split('"').next()).map(String::from);
        let Some(v) = attr("version") else { continue };
        let ts = attr("timestamp").and_then(|x| x.parse().ok()).unwrap_or(0);
        if mejor.as_ref().map(|(m, _)| ts > *m).unwrap_or(true) {
            mejor = Some((ts, v));
        }
    }
    mejor.map(|(_, v)| v)
}

/// Los Flatpak instalados: <dir>/app/<id>/<arch>/<rama>/active.
fn leer_flatpak(inst: &str, dir: &Path, out: &mut HashMap<(String, String), String>) {
    let Ok(ids) = fs::read_dir(dir.join("app")) else { return };
    for id in ids.flatten() {
        let Ok(arcos) = fs::read_dir(id.path()) else { continue };
        for arco in arcos.flatten() {
            let Ok(ramas) = fs::read_dir(arco.path()) else { continue };
            for rama in ramas.flatten() {
                let activo = rama.path().join("active");
                if !activo.exists() {
                    continue;
                }
                let n = id.file_name().to_string_lossy().into_owned();
                let referencia = format!("app/{n}/{}/{}", arco.file_name().to_string_lossy(), rama.file_name().to_string_lossy());
                let meta = activo.join("files/share/metainfo");
                let v = [format!("{n}.metainfo.xml"), format!("{n}.appdata.xml")]
                    .iter()
                    .find_map(|f| version_metainfo(&meta.join(f)).or_else(|| version_metainfo(&activo.join("files/share/appdata").join(f))))
                    .unwrap_or_default();
                out.insert((inst.to_string(), referencia), v);
            }
        }
    }
}

pub fn leer_instaladas(rutas: &Rutas, dpkg: &Path) -> Instaladas {
    let mut i = Instaladas { apt: fs::read_to_string(dpkg).map(|t| leer_dpkg(&t)).unwrap_or_default(), ..Default::default() };
    for (inst, dir) in &rutas.flatpak {
        leer_flatpak(inst, dir, &mut i.flatpak);
    }
    i
}

impl Instaladas {
    pub fn version(&self, a: &App) -> Option<&str> {
        match a.origen {
            Origen::Apt => a.paquete.as_ref().and_then(|p| self.apt.get(p)).map(|s| s.as_str()),
            Origen::Flatpak => a.flatpak.as_ref().and_then(|f| self.flatpak.get(&(f.instalacion.clone(), f.referencia.clone()))).map(|s| s.as_str()),
        }
    }
}

/// Una ficha: la app que se enseña y las otras variantes.
pub struct Ficha {
    pub app: usize,
    pub otras: Vec<usize>,
}

pub struct Indice {
    pub apps: Vec<App>,
    pub instaladas: Instaladas,
    pub fichas: Vec<Ficha>,
    /// id (de cualquier variante) → ficha.
    pub por_id: HashMap<String, usize>,
    /// appstream_id → ficha.
    pub por_appstream: HashMap<String, usize>,
}

fn rango(a: &App, inst: &Instaladas) -> u8 {
    let instalada = inst.version(a).is_some();
    match (instalada, a.origen, a.flatpak.as_ref().map(|f| f.instalacion.as_str())) {
        (true, _, _) => 0,
        (false, Origen::Flatpak, Some("user")) => 1,
        (false, Origen::Flatpak, _) => 2,
        (false, Origen::Apt, _) => 3,
    }
}

impl Indice {
    pub fn armar(apps: Vec<App>, instaladas: Instaladas) -> Indice {
        let mut grupos: HashMap<&str, Vec<usize>> = HashMap::new();
        for (i, a) in apps.iter().enumerate() {
            grupos.entry(a.appstream_id.as_str()).or_default().push(i);
        }
        // Los ids de AppStream de APT y de Flathub muchas veces no coinciden (DEP-11
        // «org.aegisub.desktop», Flathub «org.aegisub.Aegisub»). Un grupo que solo tiene
        // APT se junta con uno de Flatpak si se llaman igual y además coincide algo que
        // no es casualidad: el paquete es un <provides><binary> del Flatpak o una parte
        // de su id, la última parte de los dos ids coincide (org.blender.Blender y
        // blender.desktop), el desarrollador
        // o la página web. Dos «Camera» distintas (org.gnome.Snapshot y cheese) no se juntan.
        let web = |a: &App| a.urls.iter().find(|(t, _)| t == "homepage").map(|(_, u)| u.trim_end_matches('/').trim_start_matches("https://").trim_start_matches("http://").trim_start_matches("www.").to_lowercase());
        let mut por_nombre: HashMap<String, Vec<&str>> = HashMap::new();
        for (k, g) in &grupos {
            if g.iter().any(|i| apps[*i].origen == Origen::Flatpak) {
                por_nombre.entry(plegar(&apps[g[0]].nombre)).or_default().push(k);
            }
        }
        let solo_apt: Vec<&str> = grupos.iter().filter(|(_, g)| g.iter().all(|i| apps[*i].origen == Origen::Apt)).map(|(k, _)| *k).collect();
        for k in solo_apt {
            let a = &apps[grupos[k][0]];
            let Some(candidatos) = por_nombre.get(&plegar(&a.nombre)) else { continue };
            let destino = candidatos.iter().copied().find(|c| {
                grupos[c].iter().map(|i| &apps[*i]).any(|f| {
                    let cola = |id: &str| id.rsplit('.').next().unwrap_or(id).to_lowercase();
                    let limpio = |x: &str| x.to_lowercase().replace('-', "");
                    // Una parte del id del Flatpak que es el paquete: org.freeplane.App y
                    // freeplane, org.alienarena.alienarena y alien-arena (de 4 letras o más).
                    let parte = |p: &str| { let p = limpio(p); p.len() >= 4 && f.appstream_id.split('.').any(|c| limpio(c) == p) };
                    a.paquete.as_ref().map(|p| f.binarios.contains(p) || parte(p)).unwrap_or(false)
                        || cola(&f.appstream_id) == cola(&a.appstream_id)
                        || (a.desarrollador.is_some() && plegar(a.desarrollador.as_deref().unwrap_or("")) == plegar(f.desarrollador.as_deref().unwrap_or("")))
                        || (web(a).is_some() && web(a) == web(f))
                })
            });
            if let Some(d) = destino {
                let mover = grupos.remove(k).unwrap_or_default();
                grupos.get_mut(d).unwrap().extend(mover);
            }
        }
        let mut claves: Vec<&str> = grupos.keys().copied().collect();
        claves.sort();
        let mut fichas = Vec::new();
        let mut por_id = HashMap::new();
        let mut por_appstream = HashMap::new();
        for k in claves {
            let mut g = grupos[k].clone();
            g.sort_by_key(|i| (rango(&apps[*i], &instaladas), apps[*i].id.clone()));
            let n = fichas.len();
            for i in &g {
                por_id.insert(apps[*i].id.clone(), n);
            }
            for i in &g {
                por_appstream.insert(apps[*i].appstream_id.clone(), n);
            }
            fichas.push(Ficha { app: g[0], otras: g[1..].to_vec() });
        }
        Indice { apps, instaladas, fichas, por_id, por_appstream }
    }

    pub fn app(&self, f: &Ficha) -> &App {
        &self.apps[f.app]
    }

    /// Búsqueda local: nombre exacto, nombre que empieza, nombre que contiene, palabra
    /// clave, resumen. A igual puntaje, lo instalado primero y después por nombre.
    pub fn buscar(&self, texto: &str, origenes: &[String], limite: usize) -> Vec<usize> {
        let q = plegar(texto.trim());
        if q.is_empty() {
            return Vec::new();
        }
        let mut v: Vec<(u8, bool, String, usize)> = Vec::new();
        for (n, f) in self.fichas.iter().enumerate() {
            let a = self.app(f);
            if !origenes.is_empty() && !origenes.iter().any(|o| o == a.origen_nombre()) {
                continue;
            }
            let nombre = plegar(&a.nombre);
            let p = if nombre == q {
                0
            } else if nombre.starts_with(&q) {
                1
            } else if nombre.split(|c: char| !c.is_alphanumeric()).any(|w| w.starts_with(&q)) {
                2
            } else if nombre.contains(&q) {
                3
            } else if a.palabras.iter().any(|k| plegar(k).starts_with(&q)) {
                4
            } else if plegar(&a.resumen).contains(&q) || plegar(&a.appstream_id).contains(&q) {
                5
            } else {
                continue;
            };
            v.push((p, self.instaladas.version(a).is_none(), nombre, n));
        }
        v.sort();
        v.into_iter().take(limite).map(|(_, _, _, n)| n).collect()
    }

    /// Las fichas que tienen alguna de esas categorías, por nombre.
    pub fn en_categorias(&self, cats: &[&str]) -> Vec<usize> {
        let quiero: HashSet<&str> = cats.iter().copied().collect();
        let mut v: Vec<(String, usize)> = self
            .fichas
            .iter()
            .enumerate()
            .filter(|(_, f)| self.app(f).categorias.iter().any(|c| quiero.contains(c.as_str())))
            .map(|(n, f)| (plegar(&self.app(f).nombre), n))
            .collect();
        v.sort();
        v.into_iter().map(|(_, n)| n).collect()
    }
}

impl App {
    pub fn origen_nombre(&self) -> &'static str {
        self.origen.nombre()
    }
}

/// Minúsculas y sin tildes: «Fotografía» encuentra «fotografia».
pub fn plegar(s: &str) -> String {
    s.chars()
        .flat_map(|c| c.to_lowercase())
        .map(|c| match c {
            'á' | 'à' | 'ä' | 'â' | 'ã' => 'a',
            'é' | 'è' | 'ë' | 'ê' => 'e',
            'í' | 'ì' | 'ï' | 'î' => 'i',
            'ó' | 'ò' | 'ö' | 'ô' | 'õ' => 'o',
            'ú' | 'ù' | 'ü' | 'û' => 'u',
            'ñ' => 'n',
            'ç' => 'c',
            c => c,
        })
        .collect()
}

// --- secciones y categorías (DBUS.md) -----------------------------------------

pub const SECCIONES: &[(&str, &str, &[&str])] = &[
    ("discover", "Discover", &[]),
    ("create", "Create", &["Graphics", "AudioVideo", "Video", "Audio", "AudioVideoEditing", "Recorder", "Photography", "2DGraphics", "3DGraphics", "VectorGraphics", "Publishing"]),
    ("work", "Work", &["Office", "Finance", "ProjectManagement", "Presentation", "Spreadsheet", "WordProcessor", "Calendar", "ContactManagement", "Email"]),
    ("play", "Play", &["Game"]),
    ("develop", "Develop", &["Development", "IDE", "Debugger", "RevisionControl", "WebDevelopment", "Building", "Profiling"]),
];

pub const CATEGORIAS: &[(&str, &str, &[&str])] = &[
    ("productivity", "Productivity", &["Office"]),
    ("finance", "Finance", &["Finance"]),
    ("utilities", "Utilities", &["Utility", "System"]),
    ("news", "News", &["News", "Feed"]),
    ("entertainment", "Entertainment", &["Player", "TV", "Amusement"]),
    ("reference", "Reference", &["Dictionary", "Documentation", "Education"]),
    ("health-fitness", "Health & Fitness", &["HealthFitness"]),
    ("music", "Music", &["Audio", "Music", "Midi"]),
    ("games", "Games", &["Game"]),
    ("graphics-design", "Graphics & Design", &["Graphics"]),
    ("photography", "Photography", &["Photography"]),
    ("video", "Video", &["Video"]),
    ("education", "Education", &["Education", "Science"]),
    ("social-networking", "Social Networking", &["InstantMessaging", "Chat"]),
    ("developer-tools", "Developer Tools", &["Development"]),
];

pub fn categorias_de(id: &str) -> Option<&'static [&'static str]> {
    SECCIONES.iter().chain(CATEGORIAS.iter()).find(|(i, _, _)| *i == id).map(|(_, _, c)| *c)
}

/// La ruta del dpkg real; las pruebas pasan otra.
pub fn dpkg_del_sistema() -> PathBuf {
    "/var/lib/dpkg/status".into()
}

#[cfg(test)]
mod pruebas {
    use super::*;
    use crate::catalogo::FuenteFlatpak;

    fn app(id: &str, aid: &str, origen: Origen, inst: Option<&str>, nombre: &str) -> App {
        let mut a = App::vacia(origen);
        a.appstream_id = aid.into();
        a.nombre = nombre.into();
        a.id = id.into();
        a.origen = origen;
        if origen == Origen::Apt {
            a.flatpak = None;
            a.paquete = Some(id.trim_start_matches("apt:").into());
        } else {
            a.flatpak = Some(FuenteFlatpak { instalacion: inst.unwrap().into(), remote: "flathub".into(), referencia: format!("app/{aid}/x86_64/stable") });
        }
        a
    }

    #[test]
    fn dpkg_solo_lo_instalado() {
        let t = "Package: gimp\nStatus: install ok installed\nVersion: 2.10\n\nPackage: viejo\nStatus: deinstall ok config-files\nVersion: 1\n";
        let d = leer_dpkg(t);
        assert_eq!(d.get("gimp").map(|s| s.as_str()), Some("2.10"));
        assert!(!d.contains_key("viejo"));
    }

    #[test]
    fn una_ficha_flatpak_primero_salvo_lo_instalado() {
        let apps = vec![
            app("apt:gimp", "org.gimp.GIMP", Origen::Apt, None, "GIMP"),
            app("flatpak:system/flathub/app/org.gimp.GIMP/x86_64/stable", "org.gimp.GIMP", Origen::Flatpak, Some("system"), "GIMP"),
            app("flatpak:user/flathub/app/org.gimp.GIMP/x86_64/stable", "org.gimp.GIMP", Origen::Flatpak, Some("user"), "GIMP"),
        ];
        let i = Indice::armar(apps.clone(), Instaladas::default());
        assert_eq!(i.fichas.len(), 1);
        assert_eq!(i.app(&i.fichas[0]).id, "flatpak:user/flathub/app/org.gimp.GIMP/x86_64/stable");
        assert_eq!(i.fichas[0].otras.len(), 2);
        let mut inst = Instaladas::default();
        inst.apt.insert("gimp".into(), "2.10".into());
        let i = Indice::armar(apps, inst);
        assert_eq!(i.app(&i.fichas[0]).id, "apt:gimp", "lo instalado gana: el botón dice Open");
    }

    #[test]
    fn apt_y_flathub_con_ids_distintos_van_en_una_ficha() {
        let mut fp = app("flatpak:user/flathub/app/org.aegisub.Aegisub/x86_64/stable", "org.aegisub.Aegisub", Origen::Flatpak, Some("user"), "Aegisub");
        fp.binarios = vec!["aegisub".into()];
        let ap = app("apt:aegisub", "org.aegisub", Origen::Apt, None, "Aegisub");
        let otro = app("apt:aegisub-viejo", "otro.id", Origen::Apt, None, "Aegisub");
        let bl_f = app("flatpak:user/flathub/app/org.blender.Blender/x86_64/stable", "org.blender.Blender", Origen::Flatpak, Some("user"), "Blender");
        let bl_a = app("apt:blender", "blender", Origen::Apt, None, "Blender");
        let cam_f = app("flatpak:user/flathub/app/org.gnome.Snapshot/x86_64/stable", "org.gnome.Snapshot", Origen::Flatpak, Some("user"), "Camera");
        let cam_a = app("apt:cheese", "org.gnome.Cheese", Origen::Apt, None, "Camera");
        let i2 = Indice::armar(vec![bl_f, bl_a, cam_f, cam_a], Instaladas::default());
        assert_eq!(i2.fichas.len(), 3, "Blender se junta por el id; las dos Camera no");
        let fr_f = app("flatpak:user/flathub/app/org.freeplane.App/x86_64/stable", "org.freeplane.App", Origen::Flatpak, Some("user"), "Freeplane");
        let fr_a = app("apt:freeplane", "freeplane", Origen::Apt, None, "Freeplane");
        let al_f = app("flatpak:user/flathub/app/org.alienarena.alienarena/x86_64/stable", "org.alienarena.alienarena", Origen::Flatpak, Some("user"), "Alien Arena");
        let al_a = app("apt:alien-arena", "alien-arena", Origen::Apt, None, "Alien Arena");
        assert_eq!(Indice::armar(vec![fr_f, fr_a, al_f, al_a], Instaladas::default()).fichas.len(), 2);
        let i = Indice::armar(vec![fp, ap, otro], Instaladas::default());
        assert_eq!(i.fichas.len(), 2, "el de APT con el binario se junta; el homónimo sin nada en común, no");
        let f = &i.fichas[i.por_id["apt:aegisub"]];
        assert_eq!(i.app(f).id, "flatpak:user/flathub/app/org.aegisub.Aegisub/x86_64/stable");
        assert_eq!(i.por_appstream["org.aegisub"], i.por_id["apt:aegisub"]);
    }

    #[test]
    fn busqueda_por_puntaje_y_sin_tildes() {
        let apps = vec![
            app("flatpak:user/flathub/app/a.Foto/x86_64/stable", "a.Foto", Origen::Flatpak, Some("user"), "Fotografía Pro"),
            app("flatpak:user/flathub/app/b.Edit/x86_64/stable", "b.Edit", Origen::Flatpak, Some("user"), "Editor de fotografias"),
            app("flatpak:user/flathub/app/c.Foto/x86_64/stable", "c.Foto", Origen::Flatpak, Some("user"), "Fotografia"),
        ];
        let i = Indice::armar(apps, Instaladas::default());
        let r: Vec<String> = i.buscar("fotografia", &[], 10).iter().map(|n| i.app(&i.fichas[*n]).nombre.clone()).collect();
        assert_eq!(r, ["Fotografia", "Fotografía Pro", "Editor de fotografias"]);
        assert!(i.buscar("fotografia", &["apt".into()], 10).is_empty());
    }

    #[test]
    fn version_de_metainfo() {
        let d = std::env::temp_dir().join(format!("tienda-meta-{}", std::process::id()));
        fs::create_dir_all(&d).unwrap();
        let p = d.join("x.metainfo.xml");
        fs::write(&p, r#"<component><releases><release version="1.0" timestamp="10"/><release timestamp="30" version="1.2"/></releases></component>"#).unwrap();
        assert_eq!(version_metainfo(&p).as_deref(), Some("1.2"));
        fs::remove_dir_all(&d).unwrap();
    }
}
