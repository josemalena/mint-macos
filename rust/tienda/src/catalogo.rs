//! Los catálogos de AppStream, leídos directo (sin libappstream):
//!
//! - APT: DEP-11 YAML en /var/lib/swcatalog/yaml/*.yml.gz (los de Ubuntu; el repo de
//!   Mint no publica DEP-11). Los íconos y las capturas van por URL relativa a
//!   `MediaBaseUrl`.
//! - Flatpak: el appstream.xml.gz de cada remote, de sistema y de usuario. Los íconos
//!   están al lado, en icons/<W>x<H>/.
//!
//! Solo entran los `desktop-application`: lo que tiene ventana y ficha.

use std::collections::HashMap;
use std::fs;
use std::io::{BufReader, Read};
use std::path::{Path, PathBuf};

use flate2::read::GzDecoder;
use serde::{Deserialize, Serialize};
use quick_xml::events::{BytesStart, Event};
use yaml_rust2::{Yaml, YamlLoader};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Origen {
    Flatpak,
    Apt,
}

impl Origen {
    pub fn nombre(self) -> &'static str {
        match self {
            Origen::Flatpak => "flatpak",
            Origen::Apt => "apt",
        }
    }
}

/// De dónde sale un Flatpak: la instalación («user» o «system»), el remote y el ref
/// («app/org.gimp.GIMP/x86_64/stable»).
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct FuenteFlatpak {
    pub instalacion: String,
    pub remote: String,
    pub referencia: String,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Captura {
    pub grande: String,
    pub miniatura: String,
    pub pie: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct App {
    pub id: String,
    pub appstream_id: String,
    pub origen: Origen,
    pub nombre: String,
    pub resumen: String,
    /// El markup de AppStream (<p>, <ul>, <li>…), escapado como en el catálogo.
    pub descripcion: String,
    pub desarrollador: Option<String>,
    pub licencia: Option<String>,
    pub categorias: Vec<String>,
    pub palabras: Vec<String>,
    pub icono_archivo: Option<PathBuf>,
    pub icono_url: Option<String>,
    pub icono_tema: Option<String>,
    pub capturas: Vec<Captura>,
    pub version: Option<String>,
    pub fecha_version: Option<i64>,
    pub notas_version: Option<String>,
    /// (tipo, url): homepage, bugtracker, help, donation…
    pub urls: Vec<(String, String)>,
    /// OARS: (atributo, valor).
    pub edad: Vec<(String, String)>,
    pub paquete: Option<String>,
    /// Los <provides><binary> de AppStream: sirven para juntar un Flatpak con su
    /// paquete de APT cuando los ids no coinciden (org.aegisub.Aegisub y aegisub).
    #[serde(default)]
    pub binarios: Vec<String>,
    pub flatpak: Option<FuenteFlatpak>,
}

impl App {
    pub fn vacia(origen: Origen) -> App {
        App {
            id: String::new(),
            appstream_id: String::new(),
            origen,
            nombre: String::new(),
            resumen: String::new(),
            descripcion: String::new(),
            desarrollador: None,
            licencia: None,
            categorias: Vec::new(),
            palabras: Vec::new(),
            icono_archivo: None,
            icono_url: None,
            icono_tema: None,
            capturas: Vec::new(),
            version: None,
            fecha_version: None,
            notas_version: None,
            urls: Vec::new(),
            edad: Vec::new(),
            paquete: None,
            binarios: Vec::new(),
            flatpak: None,
        }
    }
}

/// El `appstream_id` sin el «.desktop» que DEP-11 a veces deja (libreoffice-writer.desktop):
/// así se juntan las variantes de la misma app entre APT y Flatpak.
pub fn normalizar_id(id: &str) -> String {
    id.strip_suffix(".desktop").unwrap_or(id).to_string()
}

// --- idiomas ------------------------------------------------------------------

/// Los idiomas de la persona, en orden: LANGUAGE (con «:»), LC_ALL, LC_MESSAGES y LANG,
/// cada uno con y sin país («es_DO», «es»). Al final, el texto sin idioma.
#[derive(Clone, Debug)]
pub struct Idiomas(pub Vec<String>);

impl Idiomas {
    pub fn del_entorno() -> Idiomas {
        let mut v = Vec::new();
        let mut poner = |s: &str| {
            let base = s.split(['.', '@']).next().unwrap_or("");
            if base.is_empty() || base == "C" || base == "POSIX" {
                return;
            }
            for c in [base.to_string(), base.split('_').next().unwrap_or("").to_string()] {
                if !c.is_empty() && !v.contains(&c) {
                    v.push(c);
                }
            }
        };
        if let Ok(l) = std::env::var("LANGUAGE") {
            l.split(':').for_each(&mut poner);
        }
        for k in ["LC_ALL", "LC_MESSAGES", "LANG"] {
            if let Ok(l) = std::env::var(k) {
                poner(&l);
            }
        }
        Idiomas(v)
    }

    /// De una lista (idioma, valor), el del primer idioma de la persona; si no, el sin
    /// idioma («C» en DEP-11, sin xml:lang en el XML); si no, el primero.
    pub fn elegir<'a>(&self, valores: &'a [(String, String)]) -> Option<&'a str> {
        for l in &self.0 {
            if let Some((_, v)) = valores.iter().find(|(k, _)| k == l) {
                return Some(v);
            }
        }
        valores.iter().find(|(k, _)| k.is_empty() || k == "C").or(valores.first()).map(|(_, v)| v.as_str())
    }
}

// --- DEP-11 -------------------------------------------------------------------

fn texto(y: &Yaml) -> Option<String> {
    match y {
        Yaml::String(s) => Some(s.clone()),
        Yaml::Integer(i) => Some(i.to_string()),
        Yaml::Real(r) => Some(r.clone()),
        _ => None,
    }
}

/// {C: …, es: …} → [(«C», …), («es», …)].
fn localizado(y: &Yaml) -> Vec<(String, String)> {
    match y {
        Yaml::Hash(h) => h.iter().filter_map(|(k, v)| Some((texto(k)?, texto(v)?))).collect(),
        Yaml::String(s) => vec![(String::new(), s.clone())],
        _ => Vec::new(),
    }
}

fn lista(y: &Yaml) -> Vec<String> {
    match y {
        Yaml::Array(a) => a.iter().filter_map(texto).collect(),
        _ => Vec::new(),
    }
}

fn unir_url(base: &str, rel: &str) -> String {
    if rel.starts_with("http://") || rel.starts_with("https://") || base.is_empty() {
        rel.to_string()
    } else {
        format!("{}/{}", base.trim_end_matches('/'), rel.trim_start_matches('/'))
    }
}

/// Un documento de componente de DEP-11.
fn app_dep11(y: &Yaml, base: &str, origen_dep11: &str, idiomas: &Idiomas, iconos: &Path) -> Option<App> {
    if y["Type"].as_str() != Some("desktop-application") {
        return None;
    }
    let id = y["ID"].as_str()?.to_string();
    let paquete = y["Package"].as_str()?.to_string();
    let mut a = App::vacia(Origen::Apt);
    a.id = format!("apt:{paquete}");
    a.appstream_id = normalizar_id(&id);
    a.paquete = Some(paquete);
    a.nombre = idiomas.elegir(&localizado(&y["Name"]))?.to_string();
    a.resumen = idiomas.elegir(&localizado(&y["Summary"])).unwrap_or("").to_string();
    a.descripcion = idiomas.elegir(&localizado(&y["Description"])).unwrap_or("").trim().to_string();
    a.desarrollador = idiomas
        .elegir(&localizado(&y["DeveloperName"]))
        .map(String::from)
        .or_else(|| idiomas.elegir(&localizado(&y["Developer"]["name"])).map(String::from));
    a.licencia = y["ProjectLicense"].as_str().map(String::from);
    a.categorias = lista(&y["Categories"]);
    if let Yaml::Hash(h) = &y["Keywords"] {
        let por_idioma: Vec<(String, String)> = h.iter().filter_map(|(k, v)| Some((texto(k)?, lista(v).join(";")))).collect();
        a.palabras = idiomas.elegir(&por_idioma).map(|s| s.split(';').map(String::from).collect()).unwrap_or_default();
    }
    // Íconos: el de caché si está en disco, si no el remoto (el más grande hasta 128).
    let ic = &y["Icon"];
    if let Yaml::Array(c) = &ic["cached"] {
        let mut mejor: Option<(i64, PathBuf)> = None;
        for e in c {
            let (Some(n), Some(w)) = (e["name"].as_str(), e["width"].as_i64()) else { continue };
            let h = e["height"].as_i64().unwrap_or(w);
            let p = iconos.join(origen_dep11).join(format!("{w}x{h}")).join(n);
            if w <= 128 && p.is_file() && mejor.as_ref().map(|(m, _)| w > *m).unwrap_or(true) {
                mejor = Some((w, p));
            }
        }
        a.icono_archivo = mejor.map(|(_, p)| p);
    }
    if let Yaml::Array(r) = &ic["remote"] {
        let mut mejor: Option<(i64, String)> = None;
        for e in r {
            let Some(u) = e["url"].as_str() else { continue };
            let w = e["width"].as_i64().unwrap_or(0);
            let mejor_w = mejor.as_ref().map(|(m, _)| *m).unwrap_or(-1);
            if (w <= 128 && w > mejor_w) || mejor.is_none() {
                mejor = Some((w, unir_url(base, u)));
            }
        }
        a.icono_url = mejor.map(|(_, u)| u);
    }
    a.icono_tema = ic["stock"].as_str().map(String::from);
    if let Yaml::Array(cs) = &y["Screenshots"] {
        for c in cs {
            let grande = c["source-image"]["url"].as_str().map(|u| unir_url(base, u));
            let mut mini: Option<(i64, String)> = None;
            if let Yaml::Array(t) = &c["thumbnails"] {
                for e in t {
                    let (Some(u), Some(w)) = (e["url"].as_str(), e["width"].as_i64()) else { continue };
                    // La que más se acerca a 624 de ancho: la de la ficha.
                    let d = (w - 624).abs();
                    if mini.as_ref().map(|(m, _)| d < (*m - 624).abs()).unwrap_or(true) {
                        mini = Some((w, unir_url(base, u)));
                    }
                }
            }
            let Some(g) = grande.or_else(|| mini.as_ref().map(|(_, u)| u.clone())) else { continue };
            let cap = Captura { miniatura: mini.map(|(_, u)| u).unwrap_or_else(|| g.clone()), grande: g, pie: idiomas.elegir(&localizado(&c["caption"])).unwrap_or("").to_string() };
            if c["default"].as_bool() == Some(true) {
                a.capturas.insert(0, cap);
            } else {
                a.capturas.push(cap);
            }
        }
    }
    if let Yaml::Array(rs) = &y["Releases"] {
        if let Some(r) = rs.first() {
            a.version = texto(&r["version"]);
            a.fecha_version = r["unix-timestamp"].as_i64();
            a.notas_version = idiomas.elegir(&localizado(&r["description"])).map(|s| s.trim().to_string());
        }
    }
    if let Yaml::Hash(h) = &y["Url"] {
        a.urls = h.iter().filter_map(|(k, v)| Some((texto(k)?, texto(v)?))).collect();
    }
    if let Yaml::Hash(cr) = &y["ContentRating"] {
        for (_, attrs) in cr {
            if let Yaml::Hash(h) = attrs {
                a.edad.extend(h.iter().filter_map(|(k, v)| Some((texto(k)?, texto(v)?))));
            }
        }
    }
    Some(a)
}

/// Un archivo DEP-11 entero (ya sin gzip). Cada documento se lee por separado: así un
/// componente roto no tumba el archivo y la memoria no se dispara con universe.
pub fn leer_dep11(t: &str, idiomas: &Idiomas, iconos: &Path) -> Vec<App> {
    let mut out = Vec::new();
    let mut base = String::new();
    let mut origen = String::new();
    for doc in t.split("\n---\n") {
        let doc = doc.strip_prefix("---\n").unwrap_or(doc);
        if doc.trim().is_empty() {
            continue;
        }
        let Ok(ys) = YamlLoader::load_from_str(doc) else { continue };
        let Some(y) = ys.first() else { continue };
        if y["File"].as_str() == Some("DEP-11") {
            base = y["MediaBaseUrl"].as_str().unwrap_or("").to_string();
            origen = y["Origin"].as_str().unwrap_or("").to_string();
            continue;
        }
        out.extend(app_dep11(y, &base, &origen, idiomas, iconos));
    }
    out
}

// --- AppStream XML (Flatpak) --------------------------------------------------

fn atributo(e: &BytesStart, nombre: &str) -> Option<String> {
    e.attributes().flatten().find(|a| a.key.as_ref() == nombre).and_then(|a| a.normalized_value(quick_xml::XmlVersion::Explicit1_0).ok().map(|v| v.into_owned()))
}

fn entidad(nombre: &str) -> Option<String> {
    Some(match nombre {
        "amp" => "&".into(),
        "lt" => "<".into(),
        "gt" => ">".into(),
        "quot" => "\"".into(),
        "apos" => "'".into(),
        n if n.starts_with("#x") => char::from_u32(u32::from_str_radix(&n[2..], 16).ok()?)?.to_string(),
        n if n.starts_with('#') => char::from_u32(n[1..].parse().ok()?)?.to_string(),
        _ => return None,
    })
}

#[derive(Default)]
struct Componente {
    tipo: String,
    id: String,
    nombres: Vec<(String, String)>,
    resumenes: Vec<(String, String)>,
    /// idioma → markup de la descripción (los hijos con ese xml:lang).
    descripciones: Vec<(String, String)>,
    desarrollador: Vec<(String, String)>,
    licencia: Option<String>,
    categorias: Vec<String>,
    binarios: Vec<String>,
    palabras: Vec<(String, String)>,
    icono_cache: Vec<(u32, String)>,
    icono_remoto: Vec<(u32, String)>,
    icono_tema: Option<String>,
    capturas: Vec<(bool, Vec<(String, String)>, Vec<(String, u32, String)>)>,
    releases: Vec<(String, Option<i64>, String)>,
    urls: Vec<(String, String)>,
    edad: Vec<(String, String)>,
    bundle: Option<String>,
}

/// Lee un appstream.xml (ya sin gzip) de un remote de Flatpak.
pub fn leer_xml<R: std::io::BufRead>(entrada: R, instalacion: &str, remote: &str, iconos: &Path, idiomas: &Idiomas) -> Vec<App> {
    let mut r = quick_xml::Reader::from_reader(entrada);
    r.config_mut().trim_text(false);
    let mut buf = Vec::new();
    let mut out = Vec::new();
    // La pila de elementos abiertos (nombre, xml:lang).
    let mut pila: Vec<(String, String)> = Vec::new();
    let mut c: Option<Componente> = None;
    let mut txt = String::new();
    // Dentro de <description>: el markup del hijo directo en curso y su idioma.
    let mut desc_nivel: Option<usize> = None;
    let mut desc_lang = String::new();
    let mut markup = String::new();
    let mut hijo_lang = String::new();
    loop {
        let ev = match r.read_event_into(&mut buf) {
            Ok(Event::Eof) | Err(_) => break,
            Ok(e) => e,
        };
        match ev {
            Event::Start(ref e) | Event::Empty(ref e) => {
                let vacio = matches!(ev, Event::Empty(_));
                let n = e.name().as_ref().to_string();
                let lang = atributo(e, "xml:lang").unwrap_or_default();
                if let Some(nivel) = desc_nivel {
                    if pila.len() == nivel + 1 {
                        hijo_lang = if lang.is_empty() { desc_lang.clone() } else { lang.clone() };
                        markup.clear();
                    }
                    markup.push('<');
                    markup.push_str(&n);
                    markup.push_str(if vacio { "/>" } else { ">" });
                    if !vacio {
                        pila.push((n, lang));
                    }
                    continue;
                }
                txt.clear();
                if n == "component" && pila.len() == 1 {
                    c = Some(Componente { tipo: atributo(e, "type").unwrap_or_default(), ..Default::default() });
                } else if let Some(c) = c.as_mut() {
                    let padre = pila.last().map(|(p, _)| p.as_str()).unwrap_or("");
                    match n.as_str() {
                        "description" if padre == "component" => {
                            desc_nivel = Some(pila.len());
                            desc_lang = lang.clone();
                        }
                        "description" if padre == "release" => {
                            desc_nivel = Some(pila.len());
                            desc_lang = "\u{1}release".into();
                        }
                        "icon" => {
                            let w = atributo(e, "width").and_then(|w| w.parse().ok()).unwrap_or(0);
                            let t = atributo(e, "type").unwrap_or_default();
                            pila.push((format!("icon:{t}:{w}"), lang));
                            if vacio {
                                pila.pop();
                            }
                            continue;
                        }
                        "url" => {
                            pila.push((format!("url:{}", atributo(e, "type").unwrap_or_default()), lang));
                            if vacio {
                                pila.pop();
                            }
                            continue;
                        }
                        "screenshot" => c.capturas.push((atributo(e, "type").as_deref() == Some("default"), Vec::new(), Vec::new())),
                        "image" => {
                            let t = atributo(e, "type").unwrap_or_default();
                            let w = atributo(e, "width").and_then(|w| w.parse().ok()).unwrap_or(0);
                            pila.push((format!("image:{t}:{w}"), lang));
                            if vacio {
                                pila.pop();
                            }
                            continue;
                        }
                        "release" if padre == "releases" => {
                            let v = atributo(e, "version").unwrap_or_default();
                            let ts = atributo(e, "timestamp").and_then(|t| t.parse().ok());
                            c.releases.push((v, ts, String::new()));
                        }
                        "content_attribute" => {
                            pila.push((format!("oars:{}", atributo(e, "id").unwrap_or_default()), lang));
                            if vacio {
                                pila.pop();
                            }
                            continue;
                        }
                        "bundle" => {
                            pila.push((format!("bundle:{}", atributo(e, "type").unwrap_or_default()), lang));
                            if vacio {
                                pila.pop();
                            }
                            continue;
                        }
                        _ => {}
                    }
                }
                if !vacio {
                    pila.push((n, lang));
                }
            }
            Event::Text(t) => {
                if desc_nivel.is_some() {
                    // El markup se guarda escapado, tal como viene.
                    markup.push_str(&t.as_ref());
                } else {
                    txt.push_str(&t.as_ref());
                }
            }
            Event::CData(t) => {
                if desc_nivel.is_none() {
                    txt.push_str(&t.as_ref());
                }
            }
            Event::GeneralRef(g) => {
                let nombre = g.as_ref().to_string();
                if desc_nivel.is_some() {
                    markup.push('&');
                    markup.push_str(&nombre);
                    markup.push(';');
                } else if let Some(s) = entidad(&nombre) {
                    txt.push_str(&s);
                }
            }
            Event::End(e) => {
                let n = e.name().as_ref().to_string();
                if let Some(nivel) = desc_nivel {
                    if pila.len() == nivel + 1 {
                        // Se cierra <description>.
                        desc_nivel = None;
                        pila.pop();
                        continue;
                    }
                    markup.push_str("</");
                    markup.push_str(&n);
                    markup.push('>');
                    pila.pop();
                    if pila.len() == nivel + 1 {
                        if let Some(c) = c.as_mut() {
                            if desc_lang == "\u{1}release" {
                                if let Some(rel) = c.releases.last_mut() {
                                    if hijo_lang == desc_lang {
                                        rel.2.push_str(&markup);
                                    }
                                }
                            } else if let Some(d) = c.descripciones.iter_mut().find(|(l, _)| *l == hijo_lang) {
                                d.1.push_str(&markup);
                            } else {
                                c.descripciones.push((hijo_lang.clone(), markup.clone()));
                            }
                        }
                    }
                    continue;
                }
                let (abierto, lang) = pila.pop().unwrap_or_default();
                let padre = pila.last().map(|(p, _)| p.as_str()).unwrap_or("").to_string();
                let valor = txt.trim().to_string();
                txt.clear();
                if abierto == "component" && pila.len() == 1 {
                    if let Some(comp) = c.take() {
                        out.extend(app_xml(comp, instalacion, remote, iconos, idiomas));
                    }
                    continue;
                }
                let Some(c) = c.as_mut() else { continue };
                match abierto.as_str() {
                    "id" if padre == "component" => c.id = valor,
                    "name" if padre == "component" => c.nombres.push((lang, valor)),
                    "summary" if padre == "component" => c.resumenes.push((lang, valor)),
                    "developer_name" => c.desarrollador.push((lang, valor)),
                    "name" if padre == "developer" => c.desarrollador.push((lang, valor)),
                    "project_license" => c.licencia = Some(valor),
                    "category" => c.categorias.push(valor),
                    "binary" if padre == "provides" => c.binarios.push(valor),
                    "keyword" => c.palabras.push((lang, valor)),
                    "caption" if padre == "screenshot" => {
                        if let Some(s) = c.capturas.last_mut() {
                            s.1.push((lang, valor));
                        }
                    }
                    a if a.starts_with("icon:") => {
                        let mut p = a.splitn(3, ':').skip(1);
                        let (t, w) = (p.next().unwrap_or(""), p.next().and_then(|w| w.parse().ok()).unwrap_or(0));
                        match t {
                            "cached" => c.icono_cache.push((w, valor)),
                            "remote" => c.icono_remoto.push((w, valor)),
                            "stock" => c.icono_tema = Some(valor),
                            _ => {}
                        }
                    }
                    a if a.starts_with("url:") => c.urls.push((a[4..].to_string(), valor)),
                    a if a.starts_with("image:") => {
                        let mut p = a.splitn(3, ':').skip(1);
                        let (t, w) = (p.next().unwrap_or("").to_string(), p.next().and_then(|w| w.parse().ok()).unwrap_or(0));
                        if let Some(s) = c.capturas.last_mut() {
                            s.2.push((t, w, valor));
                        }
                    }
                    a if a.starts_with("oars:") => c.edad.push((a[5..].to_string(), valor)),
                    "bundle:flatpak" => c.bundle = Some(valor),
                    _ => {}
                }
            }
            _ => {}
        }
        buf.clear();
    }
    out
}

fn app_xml(c: Componente, instalacion: &str, remote: &str, iconos: &Path, idiomas: &Idiomas) -> Option<App> {
    if c.tipo != "desktop-application" && c.tipo != "desktop" {
        return None;
    }
    let referencia = c.bundle?;
    let mut a = App::vacia(Origen::Flatpak);
    a.id = format!("flatpak:{instalacion}/{remote}/{referencia}");
    a.appstream_id = normalizar_id(&c.id);
    a.flatpak = Some(FuenteFlatpak { instalacion: instalacion.into(), remote: remote.into(), referencia });
    a.nombre = idiomas.elegir(&c.nombres)?.to_string();
    a.resumen = idiomas.elegir(&c.resumenes).unwrap_or("").to_string();
    a.descripcion = idiomas.elegir(&c.descripciones).unwrap_or("").to_string();
    a.desarrollador = idiomas.elegir(&c.desarrollador).map(String::from);
    a.licencia = c.licencia;
    a.categorias = c.categorias;
    a.binarios = c.binarios;
    let pal: Vec<(String, String)> = {
        let mut m: Vec<(String, String)> = Vec::new();
        for (l, p) in c.palabras {
            match m.iter_mut().find(|(k, _)| *k == l) {
                Some(e) => {
                    e.1.push(';');
                    e.1.push_str(&p);
                }
                None => m.push((l, p)),
            }
        }
        m
    };
    a.palabras = idiomas.elegir(&pal).map(|s| s.split(';').map(String::from).collect()).unwrap_or_default();
    // El de caché más grande hasta 128 que esté en disco.
    let mut cache = c.icono_cache;
    cache.sort_by(|x, y| y.0.cmp(&x.0));
    a.icono_archivo = cache.iter().filter(|(w, _)| *w <= 128).find_map(|(w, n)| {
        let p = iconos.join(format!("{w}x{w}")).join(n);
        p.is_file().then_some(p)
    });
    let mut rem = c.icono_remoto;
    rem.sort_by(|x, y| y.0.cmp(&x.0));
    a.icono_url = rem.iter().find(|(w, _)| *w <= 128).or(rem.first()).map(|(_, u)| u.clone());
    a.icono_tema = c.icono_tema;
    for (def, pies, imgs) in c.capturas {
        let grande = imgs.iter().find(|(t, _, _)| t == "source").or(imgs.iter().max_by_key(|(_, w, _)| *w)).map(|(_, _, u)| u.clone());
        let Some(grande) = grande else { continue };
        let mini = imgs
            .iter()
            .filter(|(t, _, _)| t == "thumbnail")
            .min_by_key(|(_, w, _)| (*w as i64 - 624).abs())
            .map(|(_, _, u)| u.clone())
            .unwrap_or_else(|| grande.clone());
        let cap = Captura { grande, miniatura: mini, pie: idiomas.elegir(&pies).unwrap_or("").to_string() };
        if def {
            a.capturas.insert(0, cap);
        } else {
            a.capturas.push(cap);
        }
    }
    // La release más nueva: la de timestamp mayor (el orden del XML no siempre lo es).
    if let Some((v, ts, notas)) = c.releases.into_iter().max_by_key(|(_, ts, _)| ts.unwrap_or(i64::MIN)) {
        a.version = (!v.is_empty()).then_some(v);
        a.fecha_version = ts;
        a.notas_version = (!notas.is_empty()).then_some(notas);
    }
    a.urls = c.urls;
    a.edad = c.edad;
    Some(a)
}

// --- todo junto ---------------------------------------------------------------

fn abrir_gz(p: &Path) -> Option<Box<dyn Read>> {
    let f = fs::File::open(p).ok()?;
    Some(if p.extension().map(|e| e == "gz").unwrap_or(false) { Box::new(GzDecoder::new(f)) } else { Box::new(f) })
}

/// Las rutas de donde se leen los catálogos; las pruebas las cambian por una raíz falsa.
#[derive(Clone, Debug)]
pub struct Rutas {
    pub dep11: PathBuf,
    pub iconos_dep11: PathBuf,
    /// (instalación, carpeta de Flatpak): ("system", /var/lib/flatpak), ("user", ~/.local/share/flatpak).
    pub flatpak: Vec<(String, PathBuf)>,
}

impl Rutas {
    pub fn del_sistema() -> Rutas {
        let casa = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
        let usuario = std::env::var_os("FLATPAK_USER_DIR").map(PathBuf::from).unwrap_or_else(|| {
            std::env::var_os("XDG_DATA_HOME").map(PathBuf::from).filter(|p| p.is_absolute()).unwrap_or_else(|| casa.join(".local/share")).join("flatpak")
        });
        Rutas {
            dep11: "/var/lib/swcatalog/yaml".into(),
            iconos_dep11: "/var/lib/swcatalog/icons".into(),
            flatpak: vec![("user".into(), usuario), ("system".into(), "/var/lib/flatpak".into())],
        }
    }
}

/// Los catálogos que se leen, en orden: los DEP-11 y el appstream.xml de cada remote.
fn archivos(rutas: &Rutas) -> (Vec<PathBuf>, Vec<(String, String, PathBuf, PathBuf)>) {
    let mut dep11: Vec<PathBuf> = fs::read_dir(&rutas.dep11).map(|d| d.flatten().map(|e| e.path()).filter(|p| p.to_string_lossy().ends_with(".yml.gz") || p.to_string_lossy().ends_with(".yml")).collect()).unwrap_or_default();
    dep11.sort();
    let mut xml = Vec::new();
    for (inst, dir) in &rutas.flatpak {
        let Ok(remotes) = fs::read_dir(dir.join("appstream")) else { continue };
        let mut remotes: Vec<_> = remotes.flatten().collect();
        remotes.sort_by_key(|e| e.file_name());
        for rem in remotes {
            let activo = rem.path().join(std::env::consts::ARCH).join("active");
            if let Some(p) = ["appstream.xml.gz", "appstream.xml"].iter().map(|n| activo.join(n)).find(|p| p.is_file()) {
                xml.push((inst.clone(), rem.file_name().to_string_lossy().into_owned(), p, activo.join("icons")));
            }
        }
    }
    (dep11, xml)
}

/// Lo que hace válido un caché: la ruta, el tamaño y la fecha de cada catálogo, y los
/// idiomas (el caché guarda los textos ya elegidos).
pub fn firma(rutas: &Rutas, idiomas: &Idiomas) -> String {
    let (dep11, xml) = archivos(rutas);
    let mut v: Vec<String> = vec![format!("v2 {}", idiomas.0.join(":"))];
    for p in dep11.iter().chain(xml.iter().map(|(_, _, p, _)| p)) {
        let m = fs::metadata(p).ok();
        let fecha = m.as_ref().and_then(|m| m.modified().ok()).and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| d.as_nanos()).unwrap_or(0);
        v.push(format!("{} {} {}", p.display(), m.map(|m| m.len()).unwrap_or(0), fecha));
    }
    v.join("\n")
}

#[derive(Serialize, Deserialize)]
struct Cache {
    firma: String,
    apps: Vec<App>,
}

/// El índice guardado: (apps, si la firma coincide). None si no hay o no se lee.
pub fn leer_cache(archivo: &Path, firma: &str) -> Option<(Vec<App>, bool)> {
    let c: Cache = serde_json::from_reader(BufReader::new(fs::File::open(archivo).ok()?)).ok()?;
    let fresco = c.firma == firma;
    Some((c.apps, fresco))
}

pub fn guardar_cache(archivo: &Path, firma: &str, apps: &[App]) {
    let Some(dir) = archivo.parent() else { return };
    let _ = fs::create_dir_all(dir);
    let tmp = archivo.with_extension("tmp");
    let r = fs::File::create(&tmp).map(std::io::BufWriter::new).and_then(|mut f| {
        serde_json::to_writer(&mut f, &Cache { firma: firma.into(), apps: apps.to_vec() }).map_err(std::io::Error::other)?;
        std::io::Write::flush(&mut f)
    });
    if r.is_ok() {
        let _ = fs::rename(&tmp, archivo);
    }
}

/// Lee todo. Los archivos de DEP-11 en orden de nombre; entre dos componentes de APT
/// con el mismo paquete gana el de la versión más nueva (noble-updates sobre noble).
pub fn cargar(rutas: &Rutas, idiomas: &Idiomas) -> Vec<App> {
    let mut apt: HashMap<String, App> = HashMap::new();
    let (dep11, xml) = archivos(rutas);
    for p in dep11 {
        let Some(mut r) = abrir_gz(&p) else { continue };
        let mut t = String::new();
        if r.read_to_string(&mut t).is_err() {
            continue;
        }
        for a in leer_dep11(&t, idiomas, &rutas.iconos_dep11) {
            let k = a.id.clone();
            let gana = match apt.get(&k) {
                None => true,
                Some(v) => a.fecha_version.unwrap_or(0) >= v.fecha_version.unwrap_or(0),
            };
            if gana {
                apt.insert(k, a);
            }
        }
    }
    let mut todas: Vec<App> = apt.into_values().collect();
    for (inst, remote, p, iconos) in xml {
        let Some(r) = abrir_gz(&p) else { continue };
        todas.extend(leer_xml(BufReader::new(r), &inst, &remote, &iconos, idiomas));
    }
    todas.sort_by(|a, b| a.id.cmp(&b.id));
    todas
}

#[cfg(test)]
mod pruebas {
    use super::*;

    fn en() -> Idiomas {
        Idiomas(vec!["es_DO".into(), "es".into()])
    }

    const DEP11: &str = "---\nFile: DEP-11\nVersion: '0.14'\nOrigin: ubuntu-noble-main\nMediaBaseUrl: https://appstream.ubuntu.com/media/noble\n---\nType: desktop-application\nID: gimp.desktop\nPackage: gimp\nName:\n  C: GIMP\n  es: GIMP en español\nSummary:\n  C: Image editor\nDescription:\n  C: <p>Edit images.</p>\nCategories:\n- Graphics\nKeywords:\n  C:\n  - photo\n  - paint\nIcon:\n  remote:\n  - url: g/gi/gimp/icons/64x64/gimp.png\n    width: 64\n  - url: g/gi/gimp/icons/128x128/gimp.png\n    width: 128\n  stock: gimp\nScreenshots:\n- default: true\n  caption:\n    C: Main window\n  thumbnails:\n  - url: g/s/a_752x470.png\n    width: 752\n  - url: g/s/a_624x390.png\n    width: 624\n  source-image:\n    url: g/s/a.png\n    width: 1920\nReleases:\n- version: 2.10.36\n  unix-timestamp: 1700000000\nUrl:\n  homepage: https://www.gimp.org/\n---\nType: console-application\nID: htop\nPackage: htop\nName:\n  C: htop\n---\nType: desktop-application\nID: roto\n";

    #[test]
    fn dep11() {
        let v = leer_dep11(DEP11, &en(), Path::new("/no-existe"));
        assert_eq!(v.len(), 1, "solo desktop-application, y el roto (sin Package) fuera");
        let g = &v[0];
        assert_eq!((g.id.as_str(), g.appstream_id.as_str(), g.nombre.as_str()), ("apt:gimp", "gimp", "GIMP en español"));
        assert_eq!(g.resumen, "Image editor");
        assert_eq!(g.icono_url.as_deref(), Some("https://appstream.ubuntu.com/media/noble/g/gi/gimp/icons/128x128/gimp.png"));
        assert_eq!(g.icono_tema.as_deref(), Some("gimp"));
        assert_eq!(g.capturas[0].grande, "https://appstream.ubuntu.com/media/noble/g/s/a.png");
        assert_eq!(g.capturas[0].miniatura, "https://appstream.ubuntu.com/media/noble/g/s/a_624x390.png");
        assert_eq!(g.capturas[0].pie, "Main window");
        assert_eq!(g.palabras, ["photo", "paint"]);
        assert_eq!(g.version.as_deref(), Some("2.10.36"));
        assert_eq!(g.urls, [("homepage".to_string(), "https://www.gimp.org/".to_string())]);
    }

    const XML: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<components version="0.8" origin="flathub">
  <component type="desktop-application">
    <id>org.gimp.GIMP</id>
    <name>GNU Image Manipulation Program</name>
    <name xml:lang="es">Programa de manipulación de imágenes GNU</name>
    <summary>Create images &amp; edit photographs</summary>
    <description>
      <p>GIMP is an <em>image</em> editor.</p>
      <p xml:lang="es">GIMP es un editor.</p>
      <ul><li>Layers</li></ul>
      <ul xml:lang="es"><li>Capas</li></ul>
    </description>
    <developer><name>The GIMP team</name></developer>
    <project_license>GPL-3.0+</project_license>
    <categories><category>Graphics</category></categories>
    <keywords><keyword>photo</keyword><keyword xml:lang="es">foto</keyword></keywords>
    <icon type="cached" width="64" height="64">org.gimp.GIMP.png</icon>
    <icon type="remote" width="128" height="128">https://dl.flathub.org/icons/128/gimp.png</icon>
    <url type="homepage">https://www.gimp.org/</url>
    <screenshots>
      <screenshot type="default">
        <caption>Main window</caption>
        <image type="source" width="1920" height="1080">https://img/source.png</image>
        <image type="thumbnail" width="624" height="351">https://img/624.png</image>
        <image type="thumbnail" width="224" height="126">https://img/224.png</image>
      </screenshot>
    </screenshots>
    <releases>
      <release version="2.10" timestamp="1600000000"/>
      <release version="3.0.4" timestamp="1750000000"><description><p>Fixes &lt;bugs&gt;.</p></description></release>
    </releases>
    <content_rating type="oars-1.1"><content_attribute id="social-chat">mild</content_attribute></content_rating>
    <bundle type="flatpak" runtime="org.gnome.Platform/x86_64/48" sdk="org.gnome.Sdk/x86_64/48">app/org.gimp.GIMP/x86_64/stable</bundle>
  </component>
  <component type="runtime"><id>org.gnome.Platform</id><name>GNOME</name><bundle type="flatpak">runtime/org.gnome.Platform/x86_64/48</bundle></component>
</components>"#;

    #[test]
    fn appstream_xml() {
        let v = leer_xml(XML.as_bytes(), "user", "flathub", Path::new("/no-existe"), &en());
        assert_eq!(v.len(), 1, "el runtime no entra");
        let g = &v[0];
        assert_eq!(g.id, "flatpak:user/flathub/app/org.gimp.GIMP/x86_64/stable");
        assert_eq!(g.nombre, "Programa de manipulación de imágenes GNU");
        assert_eq!(g.resumen, "Create images & edit photographs");
        assert_eq!(g.descripcion, "<p>GIMP es un editor.</p><ul><li>Capas</li></ul>");
        assert_eq!(g.desarrollador.as_deref(), Some("The GIMP team"));
        assert_eq!(g.palabras, ["foto"]);
        assert_eq!(g.icono_url.as_deref(), Some("https://dl.flathub.org/icons/128/gimp.png"));
        assert_eq!(g.capturas[0].miniatura, "https://img/624.png");
        assert_eq!(g.version.as_deref(), Some("3.0.4"));
        assert_eq!(g.notas_version.as_deref(), Some("<p>Fixes &lt;bugs&gt;.</p>"));
        assert_eq!(g.edad, [("social-chat".to_string(), "mild".to_string())]);
        let ingles = leer_xml(XML.as_bytes(), "user", "flathub", Path::new("/no-existe"), &Idiomas(vec!["en".into()]));
        assert_eq!(ingles[0].descripcion, "<p>GIMP is an <em>image</em> editor.</p><ul><li>Layers</li></ul>");
        assert_eq!(ingles[0].palabras, ["photo"]);
    }

    #[test]
    fn cache_del_indice() {
        let d = std::env::temp_dir().join(format!("tienda-cache-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(d.join("yaml")).unwrap();
        fs::write(d.join("yaml/a.yml"), DEP11).unwrap();
        let rutas = Rutas { dep11: d.join("yaml"), iconos_dep11: d.join("iconos"), flatpak: vec![] };
        let f1 = firma(&rutas, &en());
        let apps = cargar(&rutas, &en());
        let archivo = d.join("indice.json");
        guardar_cache(&archivo, &f1, &apps);
        let (leidas, fresco) = leer_cache(&archivo, &f1).unwrap();
        assert!(fresco && leidas == apps);
        assert_ne!(firma(&rutas, &Idiomas(vec!["fr".into()])), f1, "otro idioma, otro caché");
        fs::write(d.join("yaml/a.yml"), format!("{DEP11}\n")).unwrap();
        let f2 = firma(&rutas, &en());
        assert_ne!(f2, f1, "el catálogo cambió");
        assert!(!leer_cache(&archivo, &f2).unwrap().1, "viejo: se sirve, pero no está fresco");
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn desarrollador_con_id() {
        let x = r#"<components origin="flathub"><component type="desktop-application"><id>org.blender.Blender</id><name>Blender</name>
    <developer id="org.blender">
      <name>Blender Foundation</name>
    </developer>
    <developer_name>Blender Foundation</developer_name>
    <url type="homepage">https://www.blender.org</url>
    <provides><binary>blender</binary></provides>
    <bundle type="flatpak">app/org.blender.Blender/x86_64/stable</bundle></component></components>"#;
        let v = leer_xml(x.as_bytes(), "user", "flathub", Path::new("/"), &Idiomas(vec![]));
        assert_eq!(v[0].desarrollador.as_deref(), Some("Blender Foundation"));
        assert_eq!(v[0].binarios, ["blender"]);
    }

    #[test]
    fn idiomas() {
        let v = vec![("C".to_string(), "Hello".to_string()), ("es".to_string(), "Hola".to_string())];
        assert_eq!(en().elegir(&v), Some("Hola"));
        assert_eq!(Idiomas(vec!["fr".into()]).elegir(&v), Some("Hello"));
        assert_eq!(normalizar_id("libreoffice-writer.desktop"), "libreoffice-writer");
    }
}
