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

    /// La app de un proceso: por su Flatpak, por el ejecutable de cmdline[0] o por comm.
    pub fn de(&self, flatpak: Option<&str>, cmdline: &[String], comm: &str) -> Option<&App> {
        if let Some(f) = flatpak {
            if let Some(a) = self.por_id.get(f) {
                return Some(a);
            }
        }
        let exe = cmdline.first().and_then(|c| Path::new(c).file_name()).map(|n| n.to_string_lossy().into_owned());
        exe.as_deref().and_then(|e| self.por_exe.get(e)).or_else(|| self.por_exe.get(comm)).or_else(|| self.por_exe.get(&comm.to_lowercase()))
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
        assert_eq!(a.de(None, &["/usr/bin/gnome-text-editor".into()], "gnome-text-edi").map(|x| x.nombre.as_str()), Some("Text Editor"));
        assert_eq!(a.de(Some("com.obsproject.Studio"), &["/app/bin/obs".into()], "obs").map(|x| x.nombre.as_str()), Some("OBS Studio"));
        assert_eq!(a.de(None, &["/usr/bin/bash".into()], "bash"), None);
        fs::remove_dir_all(&d).unwrap();
    }
}
