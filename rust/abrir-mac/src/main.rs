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
//! El registro de cada arranque queda en
//! ~/Library/Logs/mint-macos-darling/<CFBundleIdentifier>-<fecha>.log (los 10
//! últimos por app). La salida de darlingserver nunca va a un pipe: si el
//! servidor no está corriendo, darling lo levanta y este hereda los descriptores.

use std::ffi::OsString;
use std::fs;
use std::io::Read;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{exit, Command, Stdio};
use std::thread::sleep;
use std::time::{Duration, Instant};

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
const CPU_X86_64: u32 = 0x0100_0007;

extern "C" {
    fn setsid() -> i32;
}

// --- La .app -------------------------------------------------------------------

struct App {
    ruta: PathBuf,
    ejecutable: PathBuf,
    nombre_ejecutable: String,
    nombre: String,
    id: String,
    minimo: Option<String>,
}

fn leer_app(ruta: &Path) -> Result<App, String> {
    let info = ruta.join("Contents/Info.plist");
    let datos = leer_con_tope(&info, 1 << 20).map_err(|_| "The application is missing its Info.plist.".to_string())?;
    let claves = plist::claves(&datos).ok_or("Its Info.plist can't be read.")?;
    let valor = |k: &str| claves.iter().find(|(c, _)| c == k).map(|(_, v)| v.clone()).filter(|v| !v.is_empty());
    let nombre_ejecutable = valor("CFBundleExecutable").ok_or("Its Info.plist has no CFBundleExecutable.")?;
    if nombre_ejecutable.contains('/') {
        return Err("Its CFBundleExecutable is not a plain name.".into());
    }
    let ejecutable = ruta.join("Contents/MacOS").join(&nombre_ejecutable);
    let nombre = valor("CFBundleDisplayName")
        .or_else(|| valor("CFBundleName"))
        .unwrap_or_else(|| nombre_visible(ruta));
    let id = valor("CFBundleIdentifier")
        .filter(|i| i.chars().all(|c| c.is_ascii_alphanumeric() || ".-_".contains(c)))
        .unwrap_or_else(|| nombre_ejecutable.clone());
    Ok(App { ruta: ruta.to_path_buf(), ejecutable, nombre_ejecutable, nombre, id, minimo: valor("LSMinimumSystemVersion") })
}

fn leer_con_tope(p: &Path, tope: u64) -> std::io::Result<Vec<u8>> {
    let mut v = Vec::new();
    fs::File::open(p)?.take(tope).read_to_end(&mut v)?;
    Ok(v)
}

fn nombre_visible(ruta: &Path) -> String {
    let n = ruta.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    n.strip_suffix(".app").unwrap_or(&n).to_string()
}

/// Si el ejecutable trae código que Darling puede correr. Solo lee la cabecera.
fn revisar_macho(p: &Path) -> Result<(), String> {
    let cab = leer_con_tope(p, 4096).map_err(|_| "The application's executable can't be found.".to_string())?;
    let u32_le = |o: usize| cab.get(o..o + 4).map(|b| u32::from_le_bytes(b.try_into().unwrap()));
    let u32_be = |o: usize| cab.get(o..o + 4).map(|b| u32::from_be_bytes(b.try_into().unwrap()));
    let sin_intel = "This application doesn't have a version for 64-bit Intel processors.".to_string();
    match cab.get(..4) {
        Some([0xcf, 0xfa, 0xed, 0xfe]) => (u32_le(4) == Some(CPU_X86_64)).then_some(()).ok_or(sin_intel),
        Some([0xce, 0xfa, 0xed, 0xfe]) => Err("This application is 32-bit and can't run.".into()),
        // Fat: big-endian. cafebabf es la variante de 64 bits, con entradas de 32 bytes.
        Some([0xca, 0xfe, 0xba, 0xbe]) | Some([0xca, 0xfe, 0xba, 0xbf]) => {
            let paso = if cab[3] == 0xbf { 32 } else { 20 };
            let n = u32_be(4).unwrap_or(0) as usize;
            // Un .class de Java empieza igual; ahí el «número de tajadas» es la versión (≥ 45).
            if n == 0 || n > 16 {
                return Err("The application's executable is not a Mac program.".into());
            }
            (0..n).any(|i| u32_be(8 + i * paso) == Some(CPU_X86_64)).then_some(()).ok_or(sin_intel)
        }
        _ => Err("The application's executable is not a Mac program.".into()),
    }
}

/// «10.15.8» → (10, 15).
fn version(v: &str) -> (u32, u32) {
    let mut p = v.split('.').map(|x| x.parse::<u32>().unwrap_or(0));
    (p.next().unwrap_or(0), p.next().unwrap_or(0))
}

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

/// Un archivo del host como lo ve Darling. Con el bind del home y de
/// /Applications (fork de darlingserver) esto dejará de hacer falta.
fn ruta_en_darling(p: &Path) -> OsString {
    let real = fs::canonicalize(p).unwrap_or_else(|_| p.to_path_buf());
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
    salida(Command::new("xdotool").args(["search", "--class", &format!("^{}$", regex_literal(clase))])).is_some()
}

fn regex_literal(s: &str) -> String {
    s.chars().flat_map(|c| if "\\.^$|?*+()[]{}".contains(c) { vec!['\\', c] } else { vec![c] }).collect()
}

// --- Vigilar -------------------------------------------------------------------

fn vigilar(d: &Darling, app: &App, archivos: &[OsString]) -> i32 {
    let registro = nuevo_registro(app);
    let titulo = format!("“{}” can't be opened", app.nombre);
    let mut reintento = true;
    loop {
        let mut hijo = match arrancar(d, app, archivos, &registro) {
            Ok(h) => h,
            Err(e) => {
                avisar(QUIEN, &titulo, &format!("Darling can't be started: {e}"));
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
                avisar(QUIEN, &titulo, &format!("{motivo}\nLog: {}", registro.display()));
                return 1;
            }
            if hay_ventana(&app.nombre_ejecutable) {
                return 0;
            }
            if inicio.elapsed() > ESPERA_VENTANA {
                // No se mata: puede ser una app sin ventana, o lenta.
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
            avisar(QUIEN, &format!("“{}” can't be opened", nombre_visible(ruta)), &e.to_string());
            1
        }
    }
}

// --- Abrir ---------------------------------------------------------------------

fn abrir(ruta: &Path, archivos: &[OsString]) -> i32 {
    let ruta = match fs::canonicalize(ruta) {
        Ok(r) if r.is_dir() => r,
        _ => {
            avisar(QUIEN, &format!("“{}” can't be opened", nombre_visible(ruta)), "The application can't be found.");
            return 1;
        }
    };
    let titulo = format!("“{}” can't be opened", nombre_visible(&ruta));
    let app = match leer_app(&ruta) {
        Ok(a) => a,
        Err(e) => {
            avisar(QUIEN, &titulo, &e);
            return 1;
        }
    };
    let titulo = format!("“{}” can't be opened", app.nombre);
    if let Err(e) = revisar_macho(&app.ejecutable) {
        avisar(QUIEN, &titulo, &e);
        return 1;
    }
    let darling = darling();
    if !darling.binario.is_file() {
        avisar(QUIEN, &titulo, "Darling is not installed.");
        return 1;
    }
    let sha = match sha256_de(&app.ejecutable) {
        Ok(s) => s,
        Err(e) => {
            avisar(QUIEN, &titulo, &e.to_string());
            return 1;
        }
    };
    let aprobadas = comun::estado().join("mac-aprobadas");
    if !comun::aprobada(&aprobadas, &sha) {
        if !preguntar(&app.nombre, origen(&app.ruta).as_deref(), None, &app.ruta) {
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
    desprender(&app.ruta, archivos)
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

// --- Info.plist ------------------------------------------------------------------

/// Las claves de texto del diccionario de arriba de un Info.plist, XML o binario
/// (bplist00). No hace falta más: lo que se lee son cadenas del primer nivel.
mod plist {
    pub fn claves(datos: &[u8]) -> Option<Vec<(String, String)>> {
        if datos.starts_with(b"bplist00") {
            binario(datos)
        } else {
            xml(std::str::from_utf8(datos).ok()?)
        }
    }

    /// <key>K</key> seguido de <string>V</string>, solo en el primer nivel del dict.
    fn xml(t: &str) -> Option<Vec<(String, String)>> {
        let mut r = Vec::new();
        let mut nivel = 0i32;
        let mut resto = &t[t.find("<dict>")? + 6..];
        let mut clave: Option<String> = None;
        while let Some(i) = resto.find('<') {
            resto = &resto[i..];
            let fin = resto.find('>')?;
            let etiqueta = &resto[1..fin];
            resto = &resto[fin + 1..];
            match etiqueta {
                "dict" | "array" => nivel += 1,
                "/dict" | "/array" => {
                    if nivel == 0 {
                        break;
                    }
                    nivel -= 1;
                }
                "key" | "string" if nivel == 0 => {
                    let cierre = resto.find('<')?;
                    let texto = entidades(&resto[..cierre]);
                    if etiqueta == "key" {
                        clave = Some(texto);
                    } else if let Some(k) = clave.take() {
                        r.push((k, texto));
                    }
                }
                e if nivel == 0 && !e.starts_with('/') => clave = None,
                _ => {}
            }
        }
        Some(r)
    }

    fn entidades(s: &str) -> String {
        s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'").replace("&amp;", "&")
    }

    /// bplist00: el trailer de 32 bytes dice dónde está la tabla de offsets y
    /// cuál es el objeto de arriba.
    fn binario(d: &[u8]) -> Option<Vec<(String, String)>> {
        let t = d.get(d.len().checked_sub(32)?..)?;
        let tam_offset = t[6] as usize;
        let tam_ref = t[7] as usize;
        let n = entero(&t[8..16]) as usize;
        let arriba = entero(&t[16..24]) as usize;
        let tabla = entero(&t[24..32]) as usize;
        let offset = |i: usize| -> Option<usize> {
            let o = tabla.checked_add(i.checked_mul(tam_offset)?)?;
            Some(entero(d.get(o..o + tam_offset)?) as usize)
        };
        if arriba >= n {
            return None;
        }
        let o = offset(arriba)?;
        let (tipo, cuenta, inicio) = cabecera(d, o)?;
        if tipo != 0xd {
            return None;
        }
        let mut r = Vec::new();
        for i in 0..cuenta {
            let ref_ = |j: usize| -> Option<usize> {
                let p = inicio.checked_add(j.checked_mul(tam_ref)?)?;
                Some(entero(d.get(p..p + tam_ref)?) as usize)
            };
            let (k, v) = (ref_(i)?, ref_(cuenta + i)?);
            if let (Some(k), Some(v)) = (cadena(d, offset(k)?), cadena(d, offset(v)?)) {
                r.push((k, v));
            }
        }
        Some(r)
    }

    fn entero(b: &[u8]) -> u64 {
        b.iter().fold(0, |a, &x| (a << 8) | x as u64)
    }

    /// (tipo, cuenta, donde empiezan los datos). Con cuenta 0xf, el largo va
    /// aparte como un entero (marcador 0x1n, 2^n bytes).
    fn cabecera(d: &[u8], o: usize) -> Option<(u8, usize, usize)> {
        let m = *d.get(o)?;
        let (tipo, bajo) = (m >> 4, (m & 0xf) as usize);
        if bajo != 0xf {
            return Some((tipo, bajo, o + 1));
        }
        let mi = *d.get(o + 1)?;
        if mi >> 4 != 1 {
            return None;
        }
        let tam = 1usize << (mi & 0xf);
        Some((tipo, entero(d.get(o + 2..o + 2 + tam)?) as usize, o + 2 + tam))
    }

    fn cadena(d: &[u8], o: usize) -> Option<String> {
        let (tipo, n, i) = cabecera(d, o)?;
        match tipo {
            0x5 => Some(String::from_utf8_lossy(d.get(i..i.checked_add(n)?)?).into_owned()),
            0x6 => {
                let b = d.get(i..i.checked_add(n.checked_mul(2)?)?)?;
                let u: Vec<u16> = b.chunks(2).map(|c| u16::from_be_bytes([c[0], c[1]])).collect();
                Some(String::from_utf16_lossy(&u))
            }
            _ => None,
        }
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn plist_xml_primer_nivel() {
        let t = br#"<?xml version="1.0"?><plist><dict>
            <key>CFBundleExecutable</key><string>Calc &amp; Co</string>
            <key>Anidado</key><dict><key>CFBundleName</key><string>no</string></dict>
            <key>LSUIElement</key><true/>
            <key>CFBundleName</key><string>Calculadora</string>
            </dict></plist>"#;
        let c = plist::claves(t).unwrap();
        assert_eq!(c, vec![("CFBundleExecutable".into(), "Calc & Co".into()), ("CFBundleName".into(), "Calculadora".into())]);
    }

    /// Hecho con plistlib (FMT_BINARY): un dict anidado, un booleano y una
    /// cadena UTF-16 («ñ»), que en bplist va con el marcador 0x6.
    #[test]
    fn plist_binario_primer_nivel() {
        let hex = "62706c6973743030d4010203040507080957416e696461646f5f1012434642756e646c6545786563757461626c655c434642756e646c654e616d655b4c535549456c656d656e74d10306526e6f5443616c636d00430061006c00630075006c00610064006f00720061002000f1090811192e3b474a4d526d0000000000000101000000000000000a0000000000000000000000000000006e";
        let b: Vec<u8> = (0..hex.len()).step_by(2).map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap()).collect();
        let c = plist::claves(&b).unwrap();
        assert_eq!(c, vec![("CFBundleExecutable".into(), "Calc".into()), ("CFBundleName".into(), "Calculadora ñ".into())]);
    }

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
}
