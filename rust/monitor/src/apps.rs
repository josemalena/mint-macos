//! El nombre y el ícono de un proceso, como en Activity Monitor: el de su app si
//! tiene un .desktop, si no el comm. Se arma una vez por arranque del servicio (los
//! .desktop de /usr/share/applications, ~/.local/share/applications y las
//! exportaciones de Flatpak) y se busca por id de Flatpak o por el ejecutable.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq)]
pub struct App {
    pub nombre: String,
    pub icono: Option<String>,
}

#[derive(Default)]
pub struct Apps {
    /// basename del ejecutable (Exec o TryExec) → app.
    por_exe: HashMap<String, App>,
    /// id del .desktop sin «.desktop» (el de Flatpak es el id de la app) → app.
    por_id: HashMap<String, App>,
    /// La carpeta propia del ejecutable de verdad (Exec con los enlaces resueltos), si no es
    /// una de las comunes: /usr/bin/google-chrome-stable lleva a /opt/google/chrome, y el
    /// proceso es /opt/google/chrome/chrome.
    por_dir: HashMap<PathBuf, App>,
}

/// Las carpetas donde viven ejecutables de muchas apps: no dicen de cuál es un proceso.
const DIRS_COMUNES: &[&str] = &["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/usr/local/bin", "/usr/games", "/usr/lib", "/usr/libexec", "/app/bin"];

/// La ruta de un ejecutable de Exec: la absoluta, o buscada en el PATH; con los enlaces resueltos.
fn ruta_real(exec: &str) -> Option<PathBuf> {
    let w = exec.split_whitespace().map(|w| w.trim_matches('"')).find(|w| *w != "env" && !w.contains('=') && !w.starts_with('%'))?;
    let p = Path::new(w);
    let p = if p.is_absolute() {
        p.to_path_buf()
    } else {
        std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default()).map(|d| d.join(w)).find(|c| c.is_file())?
    };
    fs::canonicalize(p).ok()
}

fn campo<'a>(t: &'a str, k: &str) -> Option<&'a str> {
    let mut en = false;
    for l in t.lines() {
        let l = l.trim();
        if l.starts_with('[') {
            en = l == "[Desktop Entry]";
            continue;
        }
        if en {
            if let Some(v) = l.strip_prefix(k).and_then(|r| r.strip_prefix('=')) {
                return Some(v.trim());
            }
        }
    }
    None
}

/// El ejecutable de una línea Exec: la primera palabra que no es env, flatpak run ni
/// una asignación VAR=valor.
fn ejecutable(exec: &str) -> Option<String> {
    let mut it = exec.split_whitespace().map(|w| w.trim_matches('"'));
    while let Some(w) = it.next() {
        if w == "env" || w.contains('=') || w.starts_with('%') {
            continue;
        }
        return Path::new(w).file_name().map(|n| n.to_string_lossy().into_owned());
    }
    None
}

impl Apps {
    pub fn cargar(dirs: &[PathBuf]) -> Apps {
        let mut a = Apps::default();
        for d in dirs {
            for e in fs::read_dir(d).into_iter().flatten().flatten() {
                let p = e.path();
                if p.extension().map(|x| x != "desktop").unwrap_or(true) {
                    continue;
                }
                let Ok(t) = fs::read_to_string(&p) else { continue };
                if campo(&t, "NoDisplay") == Some("true") && campo(&t, "Icon").is_none() {
                    continue;
                }
                let Some(nombre) = campo(&t, "Name") else { continue };
                let app = App { nombre: nombre.to_string(), icono: campo(&t, "Icon").map(String::from) };
                let id = p.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
                for k in ["TryExec", "Exec"] {
                    if let Some(x) = campo(&t, k).and_then(ejecutable) {
                        if x != "flatpak" {
                            a.por_exe.entry(x).or_insert_with(|| app.clone());
                        }
                    }
                }
                if let Some(w) = campo(&t, "StartupWMClass") {
                    a.por_exe.entry(w.to_lowercase()).or_insert_with(|| app.clone());
                }
                if let Some(dir) = campo(&t, "Exec").filter(|e| !e.contains("flatpak")).and_then(ruta_real).and_then(|r| r.parent().map(Path::to_path_buf)) {
                    // Ni las comunes ni ninguna …/bin (~/.local/bin, /opt/x/bin): ahí viven muchas.
                    let generica = dir.file_name().is_some_and(|n| ["bin", "sbin", "libexec", "lib", "lib64"].contains(&&*n.to_string_lossy()));
                    if !generica && !DIRS_COMUNES.iter().any(|c| dir == Path::new(c)) {
                        a.por_dir.entry(dir).or_insert_with(|| app.clone());
                    }
                }
                a.por_id.entry(id).or_insert(app);
            }
        }
        a
    }

    pub fn del_sistema() -> Apps {
        let casa = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
        Apps::cargar(&[
            casa.join(".local/share/applications"),
            casa.join(".local/share/flatpak/exports/share/applications"),
            "/var/lib/flatpak/exports/share/applications".into(),
            "/usr/local/share/applications".into(),
            "/usr/share/applications".into(),
        ])
    }

    /// La app de un proceso: por su Flatpak; por el ejecutable (/proc/<pid>/exe, cmdline[0],
    /// el guion de un intérprete o el nombre completo) contra Exec y StartupWMClass; o por la
    /// carpeta del ejecutable. Los demonios y los hilos del kernel no tienen .desktop y se
    /// quedan sin app, como en la Mac. El bool dice si es el proceso de la app (toma su
    /// nombre) o uno de sus ayudantes (solo el ícono: «Web Content» con el de Firefox).
    pub fn de(&self, flatpak: Option<&str>, cmdline: &[String], comm: &str, exe: Option<&str>) -> Option<(&App, bool)> {
        if let Some(f) = flatpak {
            if let Some(a) = self.por_id.get(f) {
                return Some((a, true));
            }
        }
        let base = |c: &str| Path::new(c).file_name().map(|n| n.to_string_lossy().into_owned());
        let buscar = |c: &str| self.por_exe.get(c).or_else(|| self.por_exe.get(&c.to_lowercase()));
        let nombre = crate::proc::nombre_completo(comm, cmdline);
        // Un intérprete solo cuenta por su guion: «python3» encontraría el .desktop de Python.
        let directos = [exe.and_then(base), cmdline.first().and_then(|c| base(c)), crate::proc::guion(cmdline), Some(nombre)];
        for c in directos.iter().flatten().filter(|c| !crate::proc::es_interprete(c)) {
            if let Some(a) = buscar(c) {
                return Some((a, true));
            }
        }
        // firefox-bin: el binario de verdad detrás del guion /usr/bin/firefox del Exec.
        if let Some(a) = exe.and_then(base).and_then(|b| b.strip_suffix("-bin").map(String::from)).and_then(|b| buscar(&b)) {
            return Some((a, false));
        }
        let dir = exe.or(cmdline.first().map(String::as_str).filter(|c| c.starts_with('/'))).and_then(|e| Path::new(e).parent());
        dir.and_then(|d| self.por_dir.get(d)).map(|a| (a, false))
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn por_ejecutable_y_por_flatpak() {
        let d = std::env::temp_dir().join(format!("monitor-apps-{}", std::process::id()));
        fs::create_dir_all(&d).unwrap();
        fs::write(d.join("org.gnome.TextEditor.desktop"), "[Desktop Entry]\nName=Text Editor\nExec=env FOO=1 /usr/bin/gnome-text-editor %U\nIcon=org.gnome.TextEditor\n").unwrap();
        fs::write(d.join("com.obsproject.Studio.desktop"), "[Desktop Entry]\nName=OBS Studio\nExec=/usr/bin/flatpak run --branch=stable com.obsproject.Studio\nIcon=com.obsproject.Studio\n").unwrap();
        let a = Apps::cargar(&[d.clone()]);
        assert_eq!(a.de(None, &["/usr/bin/gnome-text-editor".into()], "gnome-text-edi", None).map(|x| x.0.nombre.as_str()), Some("Text Editor"));
        assert_eq!(a.de(Some("com.obsproject.Studio"), &["/app/bin/obs".into()], "obs", None).map(|x| x.0.nombre.as_str()), Some("OBS Studio"));
        assert_eq!(a.de(None, &["/usr/bin/bash".into()], "bash", Some("/usr/bin/bash")), None);
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn por_wmclass_por_carpeta_y_nombre_cortado() {
        let d = std::env::temp_dir().join(format!("monitor-apps2-{}", std::process::id()));
        let opt = d.join("opt/navegador");
        fs::create_dir_all(&opt).unwrap();
        fs::write(opt.join("navegador-lanzador"), "#!/bin/sh\n").unwrap();
        fs::write(opt.join("navegador"), "").unwrap();
        let ap = d.join("apps");
        fs::create_dir_all(&ap).unwrap();
        fs::write(ap.join("nav.desktop"), format!("[Desktop Entry]\nName=Navegador\nExec={} %U\nIcon=nav\nStartupWMClass=Navegador-Raro\n", opt.join("navegador-lanzador").display())).unwrap();
        fs::write(ap.join("mapper.desktop"), "[Desktop Entry]\nName=Mapper\nExec=keyd-application-mapper\nIcon=mapper\n").unwrap();
        let a = Apps::cargar(&[ap]);
        // El proceso de verdad está en la misma carpeta que el lanzador.
        let nav = opt.join("navegador").display().to_string();
        assert_eq!(a.de(None, &[nav.clone(), "--type=renderer".into()], "navegador", Some(&nav)).map(|x| x.0.nombre.as_str()), Some("Navegador"));
        // Por StartupWMClass, sin importar mayúsculas.
        assert_eq!(a.de(None, &["navegador-raro".into()], "navegador-raro", None).map(|x| x.0.nombre.as_str()), Some("Navegador"));
        // El comm cortado en 15 y argv[0] = python3: el nombre sale de argv[1].
        assert_eq!(a.de(None, &["/usr/bin/python3".into(), "/usr/bin/keyd-application-mapper".into()], "keyd-applicatio", None).map(|x| x.0.nombre.as_str()), Some("Mapper"));
        // El binario «-bin» detrás de un guion (firefox-bin y el Exec=firefox).
        assert_eq!(a.de(None, &["/opt/x/keyd-application-mapper-bin -contentproc".into()], "Web Content", Some("/opt/x/keyd-application-mapper-bin")).map(|x| x.0.nombre.as_str()), Some("Mapper"));
        // Un ayudante (por «-bin» o por la carpeta) no es la app: solo su ícono.
        assert_eq!(a.de(None, &[nav.clone()], "navegador", Some(&nav)).map(|x| x.1), Some(false));
        // Un intérprete no busca el .desktop de Python: busca su guion.
        fs::write(d.join("apps/python.desktop"), "[Desktop Entry]\nName=Python\nExec=python3\nIcon=py\n").unwrap();
        let a = Apps::cargar(&[d.join("apps")]);
        assert_eq!(a.de(None, &["/usr/bin/python3".into(), "-u".into(), "/x/keyd-application-mapper".into()], "python3", None).map(|x| x.0.nombre.as_str()), Some("Mapper"));
        assert_eq!(a.de(None, &["/usr/bin/python3".into(), "/x/otro.py".into()], "python3", None), None);
        assert_eq!(crate::proc::nombre_completo("python3", &["python3".into(), "-m".into(), "ulauncher.main".into()]), "ulauncher.main");
        // Una carpeta …/bin tampoco (~/.local/bin trae lanzadores de muchas).
        fs::create_dir_all(d.join("local/bin")).unwrap();
        fs::write(d.join("local/bin/visor"), "").unwrap();
        fs::write(d.join("apps/visor.desktop"), format!("[Desktop Entry]\nName=Visor\nExec={}\nIcon=v\n", d.join("local/bin/visor").display())).unwrap();
        let a = Apps::cargar(&[d.join("apps")]);
        let otro = d.join("local/bin/otro").display().to_string();
        assert_eq!(a.de(None, &[otro.clone()], "otro", Some(&otro)), None);
        // Una carpeta común no dice nada.
        assert_eq!(a.de(None, &["/usr/bin/otra".into()], "otra", Some("/usr/bin/otra")), None);
        fs::remove_dir_all(&d).unwrap();
    }
}
