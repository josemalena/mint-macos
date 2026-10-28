//! Abre una .app de Mac con Darling, desde Fynder (doble clic u Open), el
//! Launchpad o el Dock. Fynder solo decide qué lanzar; la pregunta de la
//! primera vez y el aviso si falla los hace este lanzador, como Gatekeeper.
//!
//!   mint-macos-abrir-mac RUTA.app [ARCHIVO…]
//!
//! 1. Valida sin ejecutar nada: Contents/Info.plist con CFBundleExecutable, y
//!    Contents/MacOS/<ejecutable> Mach-O de 64 bits con código x86_64 (o fat con
//!    una tajada x86_64). Darling corre solo x86_64.
//! 2. La primera vez pregunta (comun::preguntar). Lo aprobado es el sha256 del
//!    ejecutable, en $XDG_STATE_HOME/mint-macos/mac-aprobadas («<sha256> <ruta>»).
//!    Hipótesis: alcanza con el ejecutable, porque una actualización normal lo
//!    cambia junto con los frameworks de dentro. No se hashea toda la .app.
//! 3. Se desprende al instante (setsid, sin los descriptores de quien lo llamó)
//!    y llama `darling exec <ruta del host>`: Darling traduce la ruta del binario
//!    (darling.c, antepone /Volumes/SystemRoot), pero no la de los argumentos,
//!    así que los ARCHIVOS se traducen aquí. `open` dentro de Darling no sirve:
//!    LaunchServices es stub (LSOpenURLsWithRole, -4; verificado el 27-10-2026).
//! 4. Vigila hasta 20 s: si aparece la ventana (WM_CLASS = CFBundleExecutable en
//!    _NET_CLIENT_LIST), listo. Si el proceso muere antes con error, avisa con lo
//!    que falta (framework, símbolo, clase) leído del registro. Solo lee
//!    ventanas: nunca manda teclas ni clics.
//!
//! 5. Mientras vigila, el ícono rebota en el Muelle y el cursor es el de espera:
//!    notificación de arranque de freedesktop con WMCLASS «darling-<id>»
//!    (arranque.rs).
//!
//! El registro de cada arranque queda en
//! ~/Library/Logs/mint-macos-darling/<CFBundleIdentifier>-<fecha>.log (los 10
//! últimos por app). La salida de darlingserver nunca va a un pipe: si el
//! servidor no está corriendo, darling lo levanta y este hereda los descriptores.

use std::ffi::OsString;
use std::fs;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{exit, Command, Stdio};
use std::thread::sleep;
use std::time::{Duration, Instant};

mod arranque;

use comun::mac::{leer_app, nombre_visible, revisar_macho, version, App};
use comun::{avisar, home, origen_de, preguntar, sha256_de, xattr, xdg};

const QUIEN: &str = "abrir-mac";
const SALIDA_SISTEMA: &str = "/Volumes/SystemRoot";
const DARLING: &str = "/media/jmalena/Data/darling-instalado/bin/darling";
const DPREFIX: &str = "/media/jmalena/Data/darling-prefijo";
const ESPERA_VENTANA: Duration = Duration::from_secs(20);
const ESPERA_SOCKET: Duration = Duration::from_secs(15);
const REGISTROS_POR_APP: usize = 10;
/// Lo que Darling dice ser (sw_vers, 27-10-2026).
const MACOS_DE_DARLING: (u32, u32) = (11, 7);

extern "C" {
    fn setsid() -> i32;
}

// --- Los avisos ----------------------------------------------------------------

/// Que la app no se pudo abrir: una alerta, como en macOS, no una notificación
/// que se pierde (en la prueba de José, Rechazo-script «no hizo nada»). No se
/// espera a que se cierre. Sin zenity, la notificación de siempre.
fn alertar(titulo: &str, cuerpo: &str) {
    if !comun::en_path("zenity") {
        avisar(QUIEN, titulo, cuerpo);
        return;
    }
    eprintln!("{QUIEN}: {titulo}: {cuerpo}");
    let _ = Command::new("zenity")
        .args(["--warning", "--title=", "--icon-name=dialog-warning", "--ok-label=OK", "--width=420"])
        .arg(format!("--text=<b>{}</b>\n\n{}", comun::marcado(titulo), comun::marcado(cuerpo)))
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

// --- La .app: comun::mac (lo usa también el generador de /Applications) -----

// --- Darling -------------------------------------------------------------------

struct Darling {
    binario: PathBuf,
    prefijo: PathBuf,
}

/// ~/.config/mint-macos/darling.conf, con líneas DARLING= y DPREFIX=.
fn darling() -> Darling {
    let conf = fs::read_to_string(xdg("XDG_CONFIG_HOME", ".config").join("mint-macos/darling.conf")).unwrap_or_default();
    let valor = |k: &str| conf.lines().find_map(|l| l.trim().strip_prefix(k)?.strip_prefix('=').map(|v| v.trim().to_string()));
    Darling {
        binario: PathBuf::from(valor("DARLING").unwrap_or_else(|| DARLING.into())),
        prefijo: PathBuf::from(valor("DPREFIX").unwrap_or_else(|| DPREFIX.into())),
    }
}

/// Las rutas de macOS que el fork de darlingserver monta en el prefijo desde
/// el host (las crea requisitos.sh: /Users → /home, /Volumes → /media/<usuario>).
const RUTAS_MAC: [&str; 3] = ["/Users", "/Volumes", "/Applications"];

/// Un archivo del host como lo ve Darling: con su ruta de Mac si cae bajo
/// /Users, /Volumes o /Applications (lo que apuntan en el host), y si no por
/// /Volumes/SystemRoot, la salida de Darling a la raíz del host.
fn ruta_en_darling(p: &Path) -> OsString {
    let real = fs::canonicalize(p).unwrap_or_else(|_| p.to_path_buf());
    for mac in RUTAS_MAC {
        if let Ok(destino) = fs::canonicalize(mac) {
            if let Ok(resto) = real.strip_prefix(&destino) {
                return Path::new(mac).join(resto).into_os_string();
            }
        }
    }
    let mut s = OsString::from(SALIDA_SISTEMA);
    s.push(real.as_os_str());
    s
}

fn arrancar(d: &Darling, app: &App, archivos: &[OsString], registro: &Path) -> std::io::Result<std::process::Child> {
    let log = fs::OpenOptions::new().create(true).append(true).open(registro)?;
    let mut c = Command::new(&d.binario);
    c.arg("exec").arg(&app.ejecutable);
    for a in archivos {
        c.arg(ruta_en_darling(Path::new(a)));
    }
    c.env("DPREFIX", &d.prefijo)
        .stdin(Stdio::null())
        .stdout(log.try_clone()?)
        .stderr(log)
        .spawn()
}

// --- El registro ---------------------------------------------------------------

fn carpeta_registros() -> PathBuf {
    home().join("Library/Logs/mint-macos-darling")
}

fn nuevo_registro(app: &App) -> PathBuf {
    let fecha = Command::new("date")
        .arg("+%Y%m%d-%H%M%S")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| "sin-fecha".into());
    let dir = carpeta_registros();
    let _ = fs::create_dir_all(&dir);
    podar_registros(&dir, &app.id);
    dir.join(format!("{}-{fecha}.log", app.id))
}

/// Deja los últimos REGISTROS_POR_APP - 1 de esa app, para que con el nuevo sean 10.
fn podar_registros(dir: &Path, id: &str) {
    let prefijo = format!("{id}-");
    let mut viejos: Vec<PathBuf> = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path())
        .filter(|p| {
            let n = p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            n.starts_with(&prefijo) && n.ends_with(".log")
        })
        .collect();
    viejos.sort();
    let sobran = viejos.len().saturating_sub(REGISTROS_POR_APP - 1);
    for p in viejos.into_iter().take(sobran) {
        let _ = fs::remove_file(p);
    }
}

/// Lo que falta, en una frase, a partir de lo que dejó dyld o el runtime.
fn por_que(registro: &str) -> Option<String> {
    let linea = |aguja: &str| registro.lines().find(|l| l.contains(aguja)).map(str::trim);
    let ultimo = |s: &str, sep: char| s.rsplit(sep).next().unwrap_or(s).trim().to_string();
    if let Some(l) = linea("Library not loaded:") {
        let lib = ultimo(l, ':');
        let nombre = lib.split('/').find(|c| c.ends_with(".framework")).map(|f| f.trim_end_matches(".framework").to_string());
        return Some(match nombre {
            Some(f) => format!("The {f} framework is missing."),
            None => format!("The library {} is missing.", ultimo(&lib, '/')),
        });
    }
    if let Some(l) = linea("Symbol not found:") {
        return Some(format!("The function {} is missing.", ultimo(l, ':')));
    }
    if let Some(l) = linea("unrecognized selector sent to") {
        let sel = l.split_whitespace().find(|p| p.starts_with("-[") || p.starts_with("+[")).unwrap_or(l);
        return Some(format!("{sel} is not implemented yet."));
    }
    if let Some(l) = linea("cannot decode object of class") {
        return Some(format!("Its interface can't be loaded: {l}"));
    }
    linea("dyld:").map(str::to_string)
}

// --- La ventana ----------------------------------------------------------------

/// Si hay una ventana con ese WM_CLASS. Primero _NET_CLIENT_LIST (lo que lista el
/// gestor de ventanas); sin gestor (un Xvfb de prueba), xdotool search --class.
/// Hipótesis: una instancia que ya estaba abierta cuenta como la nueva.
fn hay_ventana(clase: &str) -> bool {
    let salida = |c: &mut Command| c.stderr(Stdio::null()).output().ok().filter(|o| o.status.success()).map(|o| String::from_utf8_lossy(&o.stdout).into_owned());
    if let Some(lista) = salida(Command::new("xprop").args(["-root", "_NET_CLIENT_LIST"])) {
        let ids: Vec<&str> = lista.split(['#', ',']).skip(1).map(str::trim).filter(|s| s.starts_with("0x")).collect();
        if !ids.is_empty() {
            return ids.iter().any(|id| {
                salida(Command::new("xprop").args(["-id", id, "WM_CLASS"]))
                    .map(|w| w.split('"').skip(1).step_by(2).any(|c| c == clase))
                    .unwrap_or(false)
            });
        }
    }
    // --classname: res_name, que es el ejecutable (res_class es darling-<bundle id>).
    salida(Command::new("xdotool").args(["search", "--classname", &format!("^{}$", regex_literal(clase))])).is_some()
}

fn regex_literal(s: &str) -> String {
    s.chars().flat_map(|c| if "\\.^$|?*+()[]{}".contains(c) { vec!['\\', c] } else { vec![c] }).collect()
}

// --- Vigilar -------------------------------------------------------------------

fn vigilar(d: &Darling, app: &App, archivos: &[OsString]) -> i32 {
    let registro = nuevo_registro(app);
    let titulo = format!("“{}” can't be opened", app.nombre);
    // El ícono saltando en el Muelle y el cursor de espera, hasta que salga la
    // ventana o falle; se quitan al soltarlo (en cualquier return).
    let clase = format!("darling-{}", app.id.to_lowercase());
    let mut arranque = Some(arranque::Arranque::empezar(&app.nombre, &clase, icono_png(app).as_deref(),
                                                        &app.nombre_ejecutable));
    let mut reintento = true;
    loop {
        let mut hijo = match arrancar(d, app, archivos, &registro) {
            Ok(h) => h,
            Err(e) => {
                alertar(&titulo, &format!("Darling can't be started: {e}"));
                return 1;
            }
        };
        let inicio = Instant::now();
        loop {
            if let Ok(Some(st)) = hijo.try_wait() {
                let texto = fs::read_to_string(&registro).unwrap_or_default();
                // La carrera del primer arranque: darlingserver aún no creó el socket.
                if reintento && texto.contains("Error connecting to shellspawn") {
                    reintento = false;
                    esperar_socket(&d.prefijo);
                    break;
                }
                if st.success() {
                    return 0;
                }
                let motivo = por_que(&texto).unwrap_or_else(|| "It quit unexpectedly.".into());
                alertar(&titulo, &format!("{motivo}\nLog: {}", registro.display()));
                return 1;
            }
            if hay_ventana(&app.nombre_ejecutable) {
                return 0;
            }
            if inicio.elapsed() > ESPERA_VENTANA {
                // No se mata: puede ser una app sin ventana, o lenta.
                arranque.take();
                avisar(QUIEN, &format!("“{}” is still running", app.nombre), &format!("It hasn't shown a window yet.\nLog: {}", registro.display()));
                let _ = hijo.wait();
                return 0;
            }
            sleep(Duration::from_millis(500));
        }
    }
}

fn esperar_socket(prefijo: &Path) {
    let sock = prefijo.join("var/run/shellspawn.sock");
    let inicio = Instant::now();
    while !sock.exists() && inicio.elapsed() < ESPERA_SOCKET {
        sleep(Duration::from_millis(250));
    }
}

/// Se relanza a sí mismo como vigilante, en su propia sesión y sin los
/// descriptores de quien lo llamó (Fynder): quien llama vuelve al instante.
fn desprender(ruta: &Path, archivos: &[OsString]) -> i32 {
    let yo = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("mint-macos-abrir-mac"));
    let mut c = Command::new(yo);
    c.arg("--vigilar").arg(ruta).args(archivos).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    unsafe {
        c.pre_exec(|| {
            setsid();
            Ok(())
        });
    }
    match c.spawn() {
        Ok(_) => 0,
        Err(e) => {
            alertar(&format!("“{}” can't be opened", nombre_visible(ruta)), &e.to_string());
            1
        }
    }
}

// --- Abrir ---------------------------------------------------------------------

fn abrir(ruta: &Path, archivos: &[OsString]) -> i32 {
    let ruta = match fs::canonicalize(ruta) {
        Ok(r) if r.is_dir() => r,
        _ => {
            alertar(&format!("“{}” can't be opened", nombre_visible(ruta)), "The application can't be found.");
            return 1;
        }
    };
    let titulo = format!("“{}” can't be opened", nombre_visible(&ruta));
    let app = match leer_app(&ruta) {
        Ok(a) => a,
        Err(e) => {
            alertar(&titulo, &e);
            return 1;
        }
    };
    let titulo = format!("“{}” can't be opened", app.nombre);
    if let Err(e) = revisar_macho(&app.ejecutable) {
        alertar(&titulo, &e);
        return 1;
    }
    let darling = darling();
    if !darling.binario.is_file() {
        alertar(&titulo, "Darling is not installed.");
        return 1;
    }
    let sha = match sha256_de(&app.ejecutable) {
        Ok(s) => s,
        Err(e) => {
            alertar(&titulo, &e.to_string());
            return 1;
        }
    };
    let aprobadas = comun::estado().join("mac-aprobadas");
    if !comun::aprobada(&aprobadas, &sha) {
        let icono = icono_png(&app);
        if !preguntar(&app.nombre, origen(&app.ruta).as_deref(), icono.as_deref(), &app.ruta) {
            return 0;
        }
        comun::aprobar(&aprobadas, &sha, &app.ruta);
    }
    // Se avisa pero se deja intentar: muchas apps piden un mínimo que no necesitan.
    if let Some(m) = &app.minimo {
        if version(m) > MACOS_DE_DARLING {
            avisar(QUIEN, &format!("“{}” may not work", app.nombre), &format!("It requires macOS {m} or later."));
        }
    }
    // Las de fuera de las carpetas de apps quedan anotadas, para que
    // org.mintmacos.AppsMac1 sepa de quién son sus ventanas.
    if !app.ruta.starts_with("/Applications") && !app.ruta.starts_with(home().join("Applications")) {
        let _ = comun::mac::anotar_abierta(&comun::mac::archivo_abiertas(), &app.id, &app.ruta);
    }
    desprender(&app.ruta, archivos)
}

// --- El ícono ----------------------------------------------------------------

/// El ícono de la app para la ventana de Gatekeeper (sin él, mac-gatekeeper
/// ponía uno genérico de ejecutable), en ~/.cache/mint-macos/iconos-mac.
fn icono_png(app: &App) -> Option<String> {
    let dir = xdg("XDG_CACHE_HOME", ".cache").join("mint-macos/iconos-mac");
    comun::mac::icono_png(app, &dir).map(|p| p.to_string_lossy().into_owned())
}

/// user.xdg.origin.url, o el de com.apple.quarantine si vino de una Mac con él
/// («0081;5f0c…;Safari;…»: no trae URL, solo el agente).
fn origen(ruta: &Path) -> Option<String> {
    origen_de(ruta).or_else(|| {
        let q = String::from_utf8(xattr(ruta, "com.apple.quarantine")?).ok()?;
        q.split(';').nth(2).filter(|a| !a.is_empty()).map(|a| format!("app://{a}"))
    })
}

fn main() {
    let args: Vec<OsString> = std::env::args_os().skip(1).collect();
    match args.first().and_then(|a| a.to_str()) {
        None | Some("-h") | Some("--help") => {
            println!("Uso:\n  mint-macos-abrir-mac RUTA.app [ARCHIVO…]   la abre con Darling; la primera vez pregunta");
            exit(if args.is_empty() { 2 } else { 0 })
        }
        Some("--vigilar") => {
            let Some(ruta) = args.get(1) else { exit(2) };
            let app = match leer_app(Path::new(ruta)) {
                Ok(a) => a,
                Err(_) => exit(1),
            };
            exit(vigilar(&darling(), &app, &args[2..]))
        }
        _ => exit(abrir(Path::new(&args[0]), &args[1..])),
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn por_que_framework() {
        let r = "dyld: Library not loaded: /System/Library/PrivateFrameworks/SpeechDictionary.framework/Versions/A/SpeechDictionary\n";
        assert_eq!(por_que(r).as_deref(), Some("The SpeechDictionary framework is missing."));
    }

    #[test]
    fn version_minima() {
        assert!(version("12.0") > MACOS_DE_DARLING);
        assert!(version("10.15.8") <= MACOS_DE_DARLING);
    }

    /// Lo de fuera de /Users, /Volumes y /Applications va por SystemRoot; lo
    /// del HOME, por /Users si el host tiene ese enlace (requisitos.sh).
    #[test]
    fn rutas_en_darling() {
        assert_eq!(ruta_en_darling(Path::new("/etc")), OsString::from("/Volumes/SystemRoot/etc"));
        if let Ok(usuarios) = fs::canonicalize("/Users") {
            let casa = home();
            if casa.starts_with(&usuarios) {
                let esperado = Path::new("/Users").join(casa.strip_prefix(&usuarios).unwrap());
                assert_eq!(ruta_en_darling(&casa), esperado.into_os_string());
            }
        }
    }
}
