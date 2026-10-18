//! Las dos fuentes de la red: la API de Flathub (los estantes y las instalaciones del
//! mes) y ODRS (notas y reseñas). Todo se guarda en ~/.cache/mint-macos/tienda/web:
//! 24 h fresco, que es lo que la CDN de Flathub dice en `s-maxage`; sin red se usa
//! lo guardado si tiene menos de 7 días. Más viejo, no hay estante.

use std::fs;
use std::path::PathBuf;
use std::time::{Duration, SystemTime};

use serde_json::Value;

const FLATHUB: &str = "https://flathub.org/api/v2";
const ODRS: &str = "https://odrs.gnome.org/1.0/reviews/api";
const FRESCO: Duration = Duration::from_secs(24 * 3600);
const VIEJO: Duration = Duration::from_secs(7 * 24 * 3600);
const AGENTE: &str = concat!("mint-macos-tienda/", env!("CARGO_PKG_VERSION"));

pub struct Web {
    cache: PathBuf,
    /// Otra base para las pruebas (un servidor local); None = las de verdad.
    base_flathub: String,
    base_odrs: String,
    agente: ureq::Agent,
}

fn nombre_cache(clave: &str) -> String {
    clave.chars().map(|c| if c.is_ascii_alphanumeric() || c == '.' || c == '-' { c } else { '_' }).collect::<String>() + ".json"
}

impl Web {
    pub fn nueva() -> Web {
        let casa = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
        let cache = std::env::var_os("XDG_CACHE_HOME").map(PathBuf::from).filter(|p| p.is_absolute()).unwrap_or_else(|| casa.join(".cache"));
        let agente: ureq::Agent = ureq::Agent::config_builder().timeout_global(Some(Duration::from_secs(15))).user_agent(AGENTE).build().into();
        Web {
            cache: cache.join("mint-macos/tienda/web"),
            base_flathub: std::env::var("TIENDA_FLATHUB").unwrap_or_else(|_| FLATHUB.into()),
            base_odrs: std::env::var("TIENDA_ODRS").unwrap_or_else(|_| ODRS.into()),
            agente,
        }
    }

    fn guardado(&self, clave: &str, edad: Duration) -> Option<Value> {
        let p = self.cache.join(nombre_cache(clave));
        let m = fs::metadata(&p).ok()?.modified().ok()?;
        if SystemTime::now().duration_since(m).unwrap_or_default() > edad {
            return None;
        }
        serde_json::from_slice(&fs::read(p).ok()?).ok()
    }

    fn guardar(&self, clave: &str, v: &Value) {
        let _ = fs::create_dir_all(&self.cache);
        let p = self.cache.join(nombre_cache(clave));
        let tmp = p.with_extension("tmp");
        if fs::write(&tmp, v.to_string()).is_ok() {
            let _ = fs::rename(tmp, p);
        }
    }

    /// GET (o POST con cuerpo) con caché. None si no hay red ni nada guardado reciente.
    fn json(&self, clave: &str, url: &str, cuerpo: Option<&Value>) -> Option<Value> {
        if let Some(v) = self.guardado(clave, FRESCO) {
            return Some(v);
        }
        let r = match cuerpo {
            None => self.agente.get(url).call(),
            Some(b) => self.agente.post(url).header("Content-Type", "application/json").send(b.to_string()),
        };
        match r.ok().and_then(|mut r| r.body_mut().read_to_string().ok()).and_then(|t| serde_json::from_str::<Value>(&t).ok()) {
            Some(v) => {
                self.guardar(clave, &v);
                Some(v)
            }
            None => self.guardado(clave, VIEJO),
        }
    }

    /// Los app_id de una colección de Flathub, en su orden: «popular», «trending»,
    /// «recently-added», «recently-updated» o «category/graphics».
    pub fn coleccion(&self, cual: &str, cuantas: u32) -> Option<Vec<String>> {
        // «category/graphics?sort_by=…» ya trae su «?».
        let sep = if cual.contains('?') { '&' } else { '?' };
        let ruta = format!("/collection/{cual}{sep}page=1&per_page={cuantas}");
        let v = self.json(&format!("flathub{ruta}"), &format!("{}{ruta}", self.base_flathub), None)?;
        Some(v["hits"].as_array()?.iter().filter_map(|h| h["app_id"].as_str().map(String::from)).collect())
    }

    /// La app del día (solo el id: Flathub no trae texto).
    pub fn app_del_dia(&self, fecha: &str) -> Option<String> {
        let ruta = format!("/app-picks/app-of-the-day/{fecha}");
        let v = self.json(&format!("flathub{ruta}"), &format!("{}{ruta}", self.base_flathub), None)?;
        v["app_id"].as_str().map(String::from)
    }

    pub fn apps_de_la_semana(&self, fecha: &str) -> Option<Vec<String>> {
        let ruta = format!("/app-picks/apps-of-the-week/{fecha}");
        let v = self.json(&format!("flathub{ruta}"), &format!("{}{ruta}", self.base_flathub), None)?;
        let mut a: Vec<(i64, String)> = v["apps"].as_array()?.iter().filter_map(|x| Some((x["position"].as_i64().unwrap_or(0), x["app_id"].as_str()?.to_string()))).collect();
        a.sort();
        Some(a.into_iter().map(|(_, id)| id).collect())
    }

    /// Instalaciones del último mes según Flathub (`installs_last_month`, o la suma de
    /// los últimos 30 días si no viene).
    pub fn instalaciones_mes(&self, app_id: &str) -> Option<u64> {
        let ruta = format!("/stats/{app_id}");
        let v = self.json(&format!("flathub{ruta}"), &format!("{}{ruta}", self.base_flathub), None)?;
        if let Some(n) = v["installs_last_month"].as_u64() {
            return Some(n);
        }
        let dias = v["installs_per_day"].as_object()?;
        let mut d: Vec<(&String, u64)> = dias.iter().filter_map(|(k, v)| Some((k, v.as_u64()?))).collect();
        d.sort();
        Some(d.iter().rev().take(30).map(|(_, n)| n).sum())
    }

    /// (votos de 1 a 5 estrellas, total) de ODRS. None si no hay votos.
    pub fn nota(&self, app_id: &str) -> Option<([u64; 5], u64)> {
        let ruta = format!("/ratings/{app_id}");
        let v = self.json(&format!("odrs{ruta}"), &format!("{}{ruta}", self.base_odrs), None)?;
        let e: [u64; 5] = std::array::from_fn(|i| v[format!("star{}", i + 1)].as_u64().unwrap_or(0));
        let total = v["total"].as_u64().unwrap_or(e.iter().sum());
        (total > 0).then_some((e, total))
    }

    /// Las reseñas de ODRS, como las da (las más útiles primero). Solo lectura: el
    /// user_hash va en ceros, sin datos de la máquina.
    pub fn resenas(&self, app_id: &str, version: &str, limite: u32) -> Option<Vec<Value>> {
        let locale = std::env::var("LANG").unwrap_or_else(|_| "en_US".into());
        let cuerpo = serde_json::json!({
            "app_id": app_id, "locale": locale.split('.').next().unwrap_or("en_US"), "distro": "Linux Mint",
            "version": version, "user_hash": "0000000000000000000000000000000000000000", "limit": limite,
        });
        let v = self.json(&format!("odrs/fetch/{app_id}/{limite}"), &format!("{}/fetch", self.base_odrs), Some(&cuerpo))?;
        Some(v.as_array()?.clone())
    }
}

/// Promedio de 0 a 5 a partir de los votos por estrella.
pub fn promedio(e: &[u64; 5], total: u64) -> f64 {
    if total == 0 {
        return 0.0;
    }
    e.iter().enumerate().map(|(i, n)| (i as u64 + 1) * n).sum::<u64>() as f64 / total as f64
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn promedio_de_odrs() {
        // GIMP el 18-10-2026: 141, 49, 40, 81, 462 de 773.
        let p = promedio(&[141, 49, 40, 81, 462], 773);
        assert!((p - 3.872).abs() < 0.001, "{p}");
        assert_eq!(promedio(&[0; 5], 0), 0.0);
        assert_eq!(nombre_cache("flathub/stats/org.gimp.GIMP"), "flathub_stats_org.gimp.GIMP.json");
    }
}
