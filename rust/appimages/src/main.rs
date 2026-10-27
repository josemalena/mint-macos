//! Una AppImage soltada en /Applications (o en ~/Applications, si existe) queda
//! como una app más: un lanzador con su nombre, su ícono y sus tipos de archivo,
//! que ven el menú, Spotlyte, el Launchpad y «Open With». Si se bota o se saca
//! de la carpeta, el lanzador se va. Ver aplicaciones/APPIMAGE.md.
//!
//!   mint-macos-appimages [--destino DIR]…   integra lo que haya y quita lo que ya no está
//!   mint-macos-appimages --quitar           borra todos sus lanzadores e íconos
//!   mint-macos-appimages abrir RUTA [ARG…]  la abre (el Exec de los lanzadores): la
//!                                           primera vez pregunta, como Gatekeeper
//!
//! La AppImage NUNCA se ejecuta para integrarla: el .desktop y el ícono se leen del
//! squashfs que va pegado detrás del ELF (backhand, a memoria, sin escribir nada
//! al disco). `--appimage-extract` sería correr el runtime de la AppImage.
//!
//! Lo que escribe, y lo único que borra:
//!   $XDG_DATA_HOME/applications/mint-macos-appimage-<md5>.desktop   (con X-mint-macos-AppImage=true)
//!   $XDG_DATA_HOME/mint-macos/appimages/<md5>.png|svg                el ícono
//!   $XDG_STATE_HOME/mint-macos/appimages-avisos, appimages-aprobadas
//! <md5> es el de la URI file:// de la ruta (g_file_get_uri), el mismo que la spec
//! de miniaturas: así lo calcula también el Launchpad.

use std::collections::{HashMap, HashSet};
use std::ffi::{CStr, CString, OsStr, OsString};
use std::fs;
use std::io::{BufReader, Read, Seek, SeekFrom, Write};
use std::os::raw::{c_char, c_int, c_void};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::os::unix::process::CommandExt;
use std::path::{Component, Path, PathBuf};
use std::process::{exit, Command, Stdio};

use backhand::{FilesystemReader, InnerNode, SquashfsFileReader};
use comun::{home, origen_de, preguntar, sha256_de, xdg};

const PREFIJO: &str = "mint-macos-appimage-";
const MARCA: &str = "X-mint-macos-AppImage=true";
const TOPE_DESKTOP: u64 = 64 * 1024;
const TOPE_ICONO: u64 = 4 * 1024 * 1024;
const SALTOS: usize = 8;

// --- GLib, GIO y libc ---------------------------------------------------------

const G_CHECKSUM_MD5: c_int = 0;

#[link(name = "gio-2.0")]
#[link(name = "gobject-2.0")]
#[link(name = "glib-2.0")]
extern "C" {
    fn g_file_new_for_path(path: *const c_char) -> *mut c_void;
    fn g_file_get_uri(file: *mut c_void) -> *mut c_char;
    fn g_object_unref(obj: *mut c_void);
    fn g_free(p: *mut c_void);
    fn g_compute_checksum_for_string(tipo: c_int, s: *const c_char, len: isize) -> *mut c_char;
}

/// Toma un char* de GLib y lo libera.
unsafe fn de_glib(p: *mut c_char) -> String {
    let s = CStr::from_ptr(p).to_string_lossy().into_owned();
    g_free(p as *mut c_void);
    s
}

/// La URI de la ruta como la escribe GIO (g_file_get_uri): con %20 y demás.
fn uri(ruta: &Path) -> String {
    let c = CString::new(ruta.as_os_str().as_bytes()).expect("ruta sin NUL");
    unsafe {
        let f = g_file_new_for_path(c.as_ptr());
        let u = de_glib(g_file_get_uri(f));
        g_object_unref(f);
        u
    }
}

/// El md5 de la URI: el nombre del lanzador y del ícono.
fn md5_de(ruta: &Path) -> String {
    let u = CString::new(uri(ruta)).expect("uri sin NUL");
    unsafe { de_glib(g_compute_checksum_for_string(G_CHECKSUM_MD5, u.as_ptr(), -1)) }
}

// --- Dónde vive cada cosa ------------------------------------------------------

struct Lugares {
    destinos: Vec<PathBuf>,
    apps: PathBuf,
    iconos: PathBuf,
    estado: PathBuf,
    yo: PathBuf,
}

impl Lugares {
    fn new(destinos: Vec<PathBuf>) -> Self {
        let datos = xdg("XDG_DATA_HOME", ".local/share");
        Lugares {
            destinos,
            apps: datos.join("applications"),
            iconos: datos.join("mint-macos/appimages"),
            estado: comun::estado(),
            yo: std::env::current_exe().unwrap_or_else(|_| PathBuf::from("mint-macos-appimages")),
        }
    }

    fn lanzador(&self, md5: &str) -> PathBuf {
        self.apps.join(format!("{PREFIJO}{md5}.desktop"))
    }
}

// --- Buscar las AppImages ------------------------------------------------------

fn es_appimage_por_nombre(n: &OsStr) -> bool {
    let b = n.as_bytes();
    b.len() > 9 && b[b.len() - 9..].eq_ignore_ascii_case(b".appimage") && b[0] != b'.'
}

/// Las AppImages de cada destino y de sus subcarpetas de primer nivel
/// (/Applications/Utilities): archivos normales, no enlaces.
fn buscar(destinos: &[PathBuf]) -> Vec<PathBuf> {
    let mut v = Vec::new();
    for d in destinos {
        let mut carpetas = vec![d.clone()];
        if let Ok(it) = fs::read_dir(d) {
            for e in it.flatten() {
                if e.file_type().map(|t| t.is_dir()).unwrap_or(false) && !e.file_name().as_bytes().starts_with(b".") {
                    carpetas.push(e.path());
                }
            }
        }
        for c in carpetas {
            if let Ok(it) = fs::read_dir(&c) {
                for e in it.flatten() {
                    if e.file_type().map(|t| t.is_file()).unwrap_or(false) && es_appimage_por_nombre(&e.file_name()) {
                        v.push(e.path());
                    }
                }
            }
        }
    }
    v.sort();
    v
}

/// La spec deja que el usuario apague toda integración con un archivo.
fn integracion_apagada() -> bool {
    let datos = xdg("XDG_DATA_HOME", ".local/share");
    [datos.join("appimagekit/no_desktopintegration"),
     PathBuf::from("/usr/share/appimagekit/no_desktopintegration"),
     PathBuf::from("/etc/appimagekit/no_desktopintegration")]
        .iter()
        .any(|p| p.exists())
}

/// Lo que cambia si la AppImage cambia: tamaño, fecha e inodo.
fn sello(m: &fs::Metadata) -> String {
    format!("{}-{}.{:09}-{}", m.len(), m.mtime(), m.mtime_nsec(), m.ino())
}

// --- Leer la AppImage sin ejecutarla ------------------------------------------

/// Dónde empieza el sistema de archivos: al final del ELF, que es el final de su
/// tabla de cabeceras de sección (e_shoff + e_shentsize × e_shnum).
fn offset_del_payload(f: &mut fs::File) -> Result<u64, String> {
    let mut h = [0u8; 64];
    f.seek(SeekFrom::Start(0)).map_err(|e| e.to_string())?;
    f.read_exact(&mut h).map_err(|_| "it's too small to be an AppImage".to_string())?;
    if &h[0..4] != b"\x7fELF" {
        return Err("it isn't an AppImage (not an ELF file)".into());
    }
    match &h[8..11] {
        b"AI\x02" => {}
        b"AI\x01" => return Err("it's an old type 1 AppImage, which isn't supported".into()),
        _ => return Err("it isn't an AppImage (no AppImage signature)".into()),
    }
    if h[5] != 1 {
        return Err("it's a big-endian ELF".into());
    }
    let u16_en = |i: usize| u16::from_le_bytes([h[i], h[i + 1]]) as u64;
    let (shoff, entsize, num) = match h[4] {
        1 => (u32::from_le_bytes(h[0x20..0x24].try_into().unwrap()) as u64, u16_en(0x2E), u16_en(0x30)),
        2 => (u64::from_le_bytes(h[0x28..0x30].try_into().unwrap()), u16_en(0x3A), u16_en(0x3C)),
        _ => return Err("unknown ELF class".into()),
    };
    shoff
        .checked_add(entsize.checked_mul(num).ok_or("bad ELF header")?)
        .ok_or_else(|| "bad ELF header".to_string())
}

/// Lo que se sacó de la AppImage para el lanzador.
struct Leido {
    desktop: Vec<(String, String)>,
    icono: Option<(Vec<u8>, &'static str)>,
}

fn leer_appimage(ruta: &Path) -> Result<Option<Leido>, String> {
    let mut f = fs::File::open(ruta).map_err(|e| e.to_string())?;
    let off = offset_del_payload(&mut f)?;
    let mut magic = [0u8; 6];
    f.seek(SeekFrom::Start(off)).map_err(|e| e.to_string())?;
    f.read_exact(&mut magic).map_err(|_| "it has no file system after the ELF".to_string())?;
    if &magic == b"DWARFS" {
        return Err("it's packed with DwarFS, which can't be read yet".into());
    }
    if &magic[0..4] != b"hsqs" {
        return Err("it has no SquashFS file system after the ELF".into());
    }
    let fs_ = FilesystemReader::from_reader_with_offset(BufReader::new(f), off)
        .map_err(|e| format!("its SquashFS can't be read ({e})"))?;
    let mut nodos: HashMap<PathBuf, &InnerNode<SquashfsFileReader>> = HashMap::new();
    for n in fs_.files() {
        nodos.insert(n.fullpath.clone(), &n.inner);
    }

    // El .desktop: el de la raíz (la spec pide uno solo).
    let mut en_raiz: Vec<&PathBuf> = nodos
        .keys()
        .filter(|p| p.parent() == Some(Path::new("/")) && p.extension() == Some(OsStr::new("desktop")))
        .collect();
    en_raiz.sort();
    let dpath = en_raiz.first().ok_or("it has no .desktop file")?;
    let texto = leer_dentro(&fs_, &nodos, dpath, TOPE_DESKTOP)?;
    let texto = String::from_utf8(texto).map_err(|_| "its .desktop file isn't UTF-8".to_string())?;
    let desktop = grupo_desktop_entry(&texto);
    let valor = |k: &str| desktop.iter().find(|(c, _)| c == k).map(|(_, v)| v.as_str());
    if valor("X-AppImage-Integrate") == Some("false") || valor("Terminal") == Some("true") {
        return Ok(None);
    }
    if valor("Name").is_none() {
        return Err("its .desktop file has no Name".into());
    }

    // El ícono: el del tema (hicolor, de grande a chico), el de la raíz y, al
    // final, .DirIcon, que la spec hace obligatorio.
    let mut candidatos: Vec<PathBuf> = Vec::new();
    if let Some(i) = valor("Icon").filter(|i| !i.contains('/') && !i.is_empty()) {
        let h = "/usr/share/icons/hicolor";
        candidatos.push(format!("{h}/scalable/apps/{i}.svg").into());
        for t in ["512x512", "256x256", "192x192", "128x128", "96x96", "64x64", "48x48"] {
            candidatos.push(format!("{h}/{t}/apps/{i}.png").into());
        }
        candidatos.push(format!("/{i}.svg").into());
        candidatos.push(format!("/{i}.png").into());
    }
    candidatos.push("/.DirIcon".into());
    let mut icono = None;
    for c in &candidatos {
        if !nodos.contains_key(c) {
            continue;
        }
        if let Ok(b) = leer_dentro(&fs_, &nodos, c, TOPE_ICONO) {
            if let Some(ext) = tipo_de_icono(&b) {
                icono = Some((b, ext));
                break;
            }
        }
    }
    Ok(Some(Leido { desktop, icono }))
}

/// Lee un archivo de la imagen siguiendo enlaces, sin salir nunca de ella.
fn leer_dentro(
    fs_: &FilesystemReader,
    nodos: &HashMap<PathBuf, &InnerNode<SquashfsFileReader>>,
    p: &Path,
    tope: u64,
) -> Result<Vec<u8>, String> {
    let mut actual = p.to_path_buf();
    for _ in 0..=SALTOS {
        match nodos.get(&actual) {
            Some(InnerNode::File(r)) => {
                let tam = match r {
                    SquashfsFileReader::Basic(b) => b.file_size as u64,
                    SquashfsFileReader::Extended(e) => e.file_size,
                };
                if tam > tope {
                    return Err(format!("{} is too big", actual.display()));
                }
                let mut v = Vec::with_capacity(tam as usize);
                fs_.file(r)
                    .reader()
                    .take(tope + 1)
                    .read_to_end(&mut v)
                    .map_err(|e| format!("{}: {e}", actual.display()))?;
                return Ok(v);
            }
            Some(InnerNode::Symlink(s)) => {
                let base = if s.link.is_absolute() { PathBuf::from("/") } else { actual.parent().unwrap_or(Path::new("/")).to_path_buf() };
                actual = normalizar(&base.join(&s.link)).ok_or_else(|| format!("{} points outside the AppImage", p.display()))?;
            }
            _ => return Err(format!("{} isn't a file", actual.display())),
        }
    }
    Err(format!("{}: too many links", p.display()))
}

/// Resuelve . y .. sin tocar el disco; None si sube más arriba de la raíz.
fn normalizar(p: &Path) -> Option<PathBuf> {
    let mut v: Vec<&OsStr> = Vec::new();
    for c in p.components() {
        match c {
            Component::RootDir | Component::CurDir | Component::Prefix(_) => {}
            Component::ParentDir => {
                v.pop()?;
            }
            Component::Normal(n) => v.push(n),
        }
    }
    let mut r = PathBuf::from("/");
    r.extend(v);
    Some(r)
}

fn tipo_de_icono(b: &[u8]) -> Option<&'static str> {
    if b.starts_with(b"\x89PNG\r\n\x1a\n") {
        return Some("png");
    }
    let inicio = String::from_utf8_lossy(&b[..b.len().min(1024)]).to_ascii_lowercase();
    if inicio.contains("<svg") || (inicio.trim_start().starts_with("<?xml") && inicio.contains("svg")) {
        return Some("svg");
    }
    None
}

/// Las claves del grupo [Desktop Entry], en orden y con su valor tal cual (ya
/// escapado como pide la spec de .desktop).
fn grupo_desktop_entry(texto: &str) -> Vec<(String, String)> {
    let mut v = Vec::new();
    let mut dentro = false;
    for l in texto.lines() {
        let l = l.trim_end_matches('\r');
        if l.starts_with('[') {
            dentro = l.trim() == "[Desktop Entry]";
            continue;
        }
        if !dentro || l.trim_start().starts_with('#') {
            continue;
        }
        if let Some((k, val)) = l.split_once('=') {
            v.push((k.trim().to_string(), val.trim().to_string()));
        }
    }
    v
}

// --- El lanzador ---------------------------------------------------------------

/// Un valor de cadena de .desktop: barra invertida y saltos escapados.
fn escapar_valor(s: &str) -> String {
    s.replace('\\', "\\\\").replace('\n', "\\n").replace('\t', "\\t").replace('\r', "\\r")
}

/// Un argumento de Exec entre comillas: ", `, $ y \ con barra delante; % doble.
fn citar_exec(s: &str) -> String {
    let mut r = String::from("\"");
    for ch in s.chars() {
        match ch {
            '"' | '`' | '$' | '\\' => {
                r.push('\\');
                r.push(ch);
            }
            '%' => r.push_str("%%"),
            _ => r.push(ch),
        }
    }
    r.push('"');
    r
}

/// Las claves que se copian del .desktop de la AppImage (con sus traducciones).
fn se_copia(k: &str) -> bool {
    let base = k.split('[').next().unwrap_or(k);
    matches!(
        base,
        "Name" | "GenericName" | "Comment" | "Keywords" | "Categories" | "MimeType" | "StartupWMClass" | "StartupNotify" | "X-AppImage-Version"
    )
}

fn armar_lanzador(l: &Lugares, ruta_s: &str, leido: &Leido, icono: Option<&Path>, sello: &str) -> String {
    let mut s = String::from("[Desktop Entry]\n");
    s.push_str("# Lo escribió mint-macos-appimages: la AppImage de X-AppImage-Path. Si se\n");
    s.push_str("# saca de /Applications, este lanzador se borra solo.\n");
    s.push_str("Type=Application\n");
    for (k, v) in &leido.desktop {
        if se_copia(k) {
            s.push_str(&format!("{k}={v}\n"));
        }
    }
    // El código de campo del Exec original (%U, %F…), para que «Open With» le pase archivos.
    let exec_orig = leido.desktop.iter().find(|(k, _)| k == "Exec").map(|(_, v)| v.as_str()).unwrap_or("");
    let campo = ["%U", "%F", "%u", "%f"].into_iter().find(|c| exec_orig.contains(c));
    let yo = l.yo.to_string_lossy();
    s.push_str(&format!(
        "Exec={}\n",
        escapar_valor(&format!("{} abrir {}{}", citar_exec(&yo), citar_exec(ruta_s), campo.map(|c| format!(" {c}")).unwrap_or_default()))
    ));
    s.push_str(&format!("TryExec={}\n", escapar_valor(ruta_s)));
    if let Some(i) = icono {
        s.push_str(&format!("Icon={}\n", escapar_valor(&i.to_string_lossy())));
    }
    s.push_str(&format!("X-AppImage-Path={}\n", escapar_valor(ruta_s)));
    s.push_str(&format!("X-mint-macos-Sello={sello}\n"));
    s.push_str(MARCA);
    s.push('\n');
    s
}

/// Escribe solo si cambió, por un temporal y rename (nadie lee un archivo a medias).
fn escribir(p: &Path, contenido: &[u8], modo: u32) -> std::io::Result<bool> {
    if fs::read(p).map(|v| v == contenido).unwrap_or(false) {
        return Ok(false);
    }
    if let Some(d) = p.parent() {
        fs::create_dir_all(d)?;
    }
    let tmp = p.with_file_name(format!(".{}.tmp", p.file_name().unwrap().to_string_lossy()));
    {
        let mut f = fs::File::create(&tmp)?;
        f.write_all(contenido)?;
        f.set_permissions(fs::Permissions::from_mode(modo))?;
    }
    fs::rename(&tmp, p)?;
    Ok(true)
}

/// Un lanzador nuestro: el prefijo en el nombre y la marca dentro.
fn es_nuestro(p: &Path) -> bool {
    p.file_name().map(|n| n.as_bytes().starts_with(PREFIJO.as_bytes())).unwrap_or(false)
        && fs::read_to_string(p).map(|t| t.lines().any(|l| l == MARCA)).unwrap_or(false)
}

fn clave(texto: &str, k: &str) -> Option<String> {
    texto.lines().find_map(|l| l.strip_prefix(k).and_then(|r| r.strip_prefix('=')).map(str::to_string))
}

// --- Avisos --------------------------------------------------------------------

fn avisar(titulo: &str, cuerpo: &str) {
    comun::avisar("appimages", titulo, cuerpo);
}

/// Un aviso por AppImage y por versión del archivo, no uno en cada corrida.
fn avisar_una_vez(l: &Lugares, md5: &str, sello: &str, titulo: &str, cuerpo: &str) {
    let p = l.estado.join("appimages-avisos");
    let linea = format!("{md5} {sello}");
    if fs::read_to_string(&p).map(|t| t.lines().any(|x| x == linea)).unwrap_or(false) {
        return;
    }
    avisar(titulo, cuerpo);
    let _ = fs::create_dir_all(&l.estado);
    if let Ok(mut f) = fs::OpenOptions::new().create(true).append(true).open(&p) {
        let _ = writeln!(f, "{linea}");
    }
}

fn nombre_visible(ruta: &Path) -> String {
    let n = ruta.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    n.get(..n.len().saturating_sub(9)).unwrap_or(&n).to_string()
}

// --- Escanear ------------------------------------------------------------------

fn escanear(l: &Lugares, quitar: bool) -> i32 {
    let encontradas = if quitar || integracion_apagada() { Vec::new() } else { buscar(&l.destinos) };
    let mut quedan: HashSet<String> = HashSet::new();
    let mut cambios = 0;
    let mut errores = 0;

    for ruta in &encontradas {
        let md5 = md5_de(ruta);
        let Some(ruta_s) = ruta.to_str() else {
            eprintln!("appimages: {}: el nombre no es UTF-8, no se integra", ruta.display());
            continue;
        };
        let Ok(meta) = fs::metadata(ruta) else { continue };
        let s = sello(&meta);
        let lanz = l.lanzador(&md5);
        // Ya integrada y sin cambios: no se vuelve a leer.
        if let Ok(t) = fs::read_to_string(&lanz) {
            if t.lines().any(|x| x == MARCA)
                && clave(&t, "X-mint-macos-Sello").as_deref() == Some(s.as_str())
                && clave(&t, "X-AppImage-Path").as_deref() == Some(escapar_valor(ruta_s).as_str())
            {
                quedan.insert(md5);
                continue;
            }
        }
        match leer_appimage(ruta) {
            Ok(Some(leido)) => {
                let icono = leido.icono.as_ref().map(|(b, ext)| (l.iconos.join(format!("{md5}.{ext}")), b));
                if let Some((p, b)) = &icono {
                    if let Err(e) = escribir(p, b, 0o644) {
                        eprintln!("appimages: {}: {e}", p.display());
                        errores += 1;
                        continue;
                    }
                }
                // Soltarla en /Applications es dejar que corra (con la pregunta de
                // la primera vez, en «abrir»): el navegador la baja sin +x.
                let modo = meta.permissions().mode();
                if modo & 0o100 == 0 {
                    let _ = fs::set_permissions(ruta, fs::Permissions::from_mode(modo | 0o100));
                }
                let s = fs::metadata(ruta).map(|m| sello(&m)).unwrap_or(s);
                let texto = armar_lanzador(l, ruta_s, &leido, icono.as_ref().map(|(p, _)| p.as_path()), &s);
                match escribir(&lanz, texto.as_bytes(), 0o644) {
                    Ok(true) => {
                        cambios += 1;
                        eprintln!("appimages: integrada {ruta_s} → {}", lanz.display());
                    }
                    Ok(false) => {}
                    Err(e) => {
                        eprintln!("appimages: {}: {e}", lanz.display());
                        errores += 1;
                        continue;
                    }
                }
                quedan.insert(md5);
            }
            Ok(None) => eprintln!("appimages: {ruta_s}: su .desktop pide no integrarla"),
            Err(motivo) => avisar_una_vez(
                l,
                &md5,
                &s,
                &format!("“{}” can't be added to Applications", nombre_visible(ruta)),
                &format!("{}{}.", motivo[..1].to_uppercase(), &motivo[1..]),
            ),
        }
    }

    // Lo nuestro que ya no corresponde a ninguna AppImage presente.
    if let Ok(it) = fs::read_dir(&l.apps) {
        for e in it.flatten() {
            let p = e.path();
            let n = e.file_name();
            let Some(md5) = n.to_str().and_then(|n| n.strip_prefix(PREFIJO)).and_then(|n| n.strip_suffix(".desktop")) else { continue };
            if quedan.contains(md5) || !es_nuestro(&p) {
                continue;
            }
            if fs::remove_file(&p).is_ok() {
                cambios += 1;
                eprintln!("appimages: quitada {}", p.display());
            }
        }
    }
    if let Ok(it) = fs::read_dir(&l.iconos) {
        for e in it.flatten() {
            let n = e.file_name();
            let md5 = n.to_str().and_then(|n| n.split('.').next()).unwrap_or("");
            if md5.len() == 32 && md5.bytes().all(|b| b.is_ascii_hexdigit()) && !quedan.contains(md5) {
                let _ = fs::remove_file(e.path());
            }
        }
    }
    if cambios > 0 && l.apps.is_dir() {
        // «Open With»: la caché de tipos de archivo de los lanzadores del usuario.
        let _ = Command::new("update-desktop-database").arg(&l.apps).stderr(Stdio::null()).status();
    }
    if errores > 0 { 1 } else { 0 }
}

// --- Abrir (la pregunta de la primera vez) ------------------------------------

fn abrir(l: &Lugares, ruta: &Path, args: &[OsString]) -> i32 {
    // El lanzador se busca por la ruta tal como la escribió el servicio (la del
    // Exec); la resuelta, con los enlaces seguidos, puede ser otra y dar otro md5.
    let dada = ruta.to_path_buf();
    let ruta = match fs::canonicalize(ruta) {
        Ok(r) => r,
        Err(_) => {
            avisar(&format!("“{}” can't be opened", nombre_visible(ruta)), "The application can't be found.");
            return 1;
        }
    };
    let sha = match sha256_de(&ruta) {
        Ok(s) => s,
        Err(e) => {
            avisar(&format!("“{}” can't be opened", nombre_visible(&ruta)), &e.to_string());
            return 1;
        }
    };
    let aprobadas = l.estado.join("appimages-aprobadas");
    if !comun::aprobada(&aprobadas, &sha) {
        let texto_lanz = fs::read_to_string(l.lanzador(&md5_de(&dada)))
            .or_else(|_| fs::read_to_string(l.lanzador(&md5_de(&ruta))))
            .unwrap_or_default();
        let nombre = clave(&texto_lanz, "Name").unwrap_or_else(|| nombre_visible(&ruta));
        let icono = clave(&texto_lanz, "Icon");
        let origen = origen_de(&ruta);
        if !preguntar(&nombre, origen.as_deref(), icono.as_deref(), &ruta) {
            return 0;
        }
        comun::aprobar(&aprobadas, &sha, &ruta);
    }
    if let Ok(m) = fs::metadata(&ruta) {
        let modo = m.permissions().mode();
        if modo & 0o100 == 0 {
            let _ = fs::set_permissions(&ruta, fs::Permissions::from_mode(modo | 0o100));
        }
    }
    // DESKTOPINTEGRATION: que la AppImage no se integre ella misma (ya lo está).
    let e = Command::new(&ruta).args(args).env("DESKTOPINTEGRATION", "1").exec();
    avisar(&format!("“{}” can't be opened", nombre_visible(&ruta)), &e.to_string());
    1
}

// --- main ----------------------------------------------------------------------

fn ayuda() -> ! {
    println!(
        "Uso:\n  mint-macos-appimages [--destino DIR]…   integra las AppImages de /Applications\n  \
         (y ~/Applications si existe) y quita las que ya no están\n  \
         mint-macos-appimages --quitar           borra todos sus lanzadores e íconos\n  \
         mint-macos-appimages abrir RUTA [ARG…]  la abre; la primera vez pregunta"
    );
    exit(0)
}

fn main() {
    let args: Vec<OsString> = std::env::args_os().skip(1).collect();
    if args.first().map(|a| a == "abrir").unwrap_or(false) {
        let Some(ruta) = args.get(1) else {
            eprintln!("falta la ruta de la AppImage");
            exit(2)
        };
        let l = Lugares::new(Vec::new());
        exit(abrir(&l, Path::new(ruta), &args[2..]));
    }
    let mut destinos = Vec::new();
    let mut quitar = false;
    let mut i = 0;
    while i < args.len() {
        match args[i].to_str() {
            Some("-h") | Some("--help") => ayuda(),
            Some("--quitar") => {
                quitar = true;
                i += 1;
            }
            Some("--destino") => {
                let Some(d) = args.get(i + 1) else {
                    eprintln!("--destino necesita una carpeta");
                    exit(2)
                };
                destinos.push(PathBuf::from(d));
                i += 2;
            }
            _ => {
                eprintln!("opción desconocida: {}", args[i].to_string_lossy());
                exit(2)
            }
        }
    }
    if destinos.is_empty() {
        destinos.push(PathBuf::from("/Applications"));
        // ~/Applications solo si ya existe (José, 17-10-2026): no se crea.
        let propia = home().join("Applications");
        if propia.is_dir() {
            destinos.push(propia);
        }
    }
    exit(escanear(&Lugares::new(destinos), quitar))
}
