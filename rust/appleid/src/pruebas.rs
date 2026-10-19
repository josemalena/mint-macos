//! Con un rclone, un systemctl, un CalDAV, un llavero y un Thunderbird de mentira: nada sale a la
//! red ni toca la cuenta de José (un 2FA de verdad le llega al teléfono).
use super::*;
use std::io::{BufRead, BufReader, Read};
use std::net::TcpListener;
use std::os::unix::fs::PermissionsExt;

const CLAVE: &str = "clave buena con espacios y $ y '";
const CODIGO: &str = "123456";
const CLAVE_APP: &str = "abcd-efgh-ijkl-mnop";

/// Imita lo que este servicio le pide a rclone: obscure, config file, config update (alta y
/// --continue por entorno) y config delete. Anota cada argv para comprobar que no lleva secretos.
const RCLONE: &str = r#"#!/bin/bash
printf '%s\n' "$*" >> "$PRUEBA_DIR/argv"
seccion() { awk -v s="[$1]" '/^\[/{d=($0==s)} !d' "$RCLONE_CONFIG"; }
case "$1 $2" in
  "obscure -") printf 'OBS:%s\n' "$(base64 -w0)";;
  "config file") printf 'Configuration file is stored at:\n%s\n' "$RCLONE_CONFIG";;
  "config delete") seccion "$3" > "$RCLONE_CONFIG.n"; mv "$RCLONE_CONFIG.n" "$RCLONE_CONFIG";;
  "config update")
    if [ "$RCLONE_CONTINUE" = true ]; then
      [ "$RCLONE_STATE" = "*2fa_do" ] || { echo "Fatal error: unknown state" >&2; exit 1; }
      if [ "$RCLONE_RESULT" = "$PRUEBA_CODIGO" ]; then printf 'trust_token = tok\n' >> "$RCLONE_CONFIG"; echo '{}'
      else printf '2026/10/18 22:18:42 NOTICE: Fatal error: Invalid verification code\n' >&2; exit 1; fi
    else
      esperada="OBS:$(printf '%s' "$PRUEBA_CLAVE" | base64 -w0)"
      grep -qxF "password = $esperada" "$RCLONE_CONFIG" || { printf '{\n "Error": "Your Apple ID or password was incorrect."\n}\n'; exit 1; }
      echo '{"State":"*2fa_do","Option":{"Help":"Two-factor authentication: please enter your 2FA code"}}'
    fi;;
  *) exit 2;;
esac
"#;

struct Mundo {
    dir: PathBuf,
    e: Entorno,
}

impl Drop for Mundo {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.dir);
    }
}

fn mundo(nombre: &str, caldav: &str) -> Mundo {
    let dir = std::env::temp_dir().join(format!("appleid-prueba-{}-{nombre}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(dir.join("unidades")).unwrap();
    let ejecutable = |n: &str, t: &str| {
        let p = dir.join(n);
        fs::write(&p, t).unwrap();
        fs::set_permissions(&p, fs::Permissions::from_mode(0o755)).unwrap();
        p
    };
    let rclone = ejecutable("rclone", RCLONE);
    let systemctl = ejecutable("systemctl", "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$(dirname \"$0\")/systemctl.log\"\n");
    fs::write(dir.join("unidades/rclone-prueba.service"), "").unwrap();
    // Thunderbird: un perfil con una cuenta que ya existía.
    let tb = dir.join("tb");
    fs::create_dir_all(tb.join("abc.default-esr")).unwrap();
    fs::write(tb.join("profiles.ini"), "[Profile0]\nName=default\nIsRelative=1\nPath=abc.default\nDefault=1\n").unwrap();
    fs::write(tb.join("installs.ini"), "[ABCDEF]\nDefault=abc.default-esr\nLocked=1\n").unwrap();
    fs::write(tb.join("abc.default-esr/prefs.js"), "user_pref(\"mail.accountmanager.accounts\", \"account1\");\n").unwrap();
    fs::write(tb.join("abc.default-esr/user.js"), "user_pref(\"de.jose\", true);\n").unwrap();
    // rclone.conf con otro remoto que no se puede perder.
    fs::write(dir.join("rclone.conf"), "[nas]\ntype = sftp\nhost = 10.0.0.2\n").unwrap();
    std::env::set_var("PRUEBA_DIR", &dir);
    std::env::set_var("RCLONE_CONFIG", dir.join("rclone.conf"));
    std::env::set_var("PRUEBA_CLAVE", CLAVE);
    std::env::set_var("PRUEBA_CODIGO", CODIGO);
    let e = Entorno {
        rclone,
        remoto: "icloud".into(),
        servicio: "rclone-prueba".into(),
        unidades: dir.join("unidades"),
        carpeta: dir.join("iCloud Drive"),
        systemctl,
        caldav: caldav.into(),
        thunderbird: tb,
        llavero: Llavero::Archivo(dir.join("llavero")),
        mirar_procesos: false,
        log: dir.join("apple-id.log"),
    };
    Mundo { dir, e }
}

/// Un CalDAV como el de iCloud: principal, calendar-home en otra «máquina» (URL absoluta) y la lista
/// con dos calendarios, el buzón de citas (que no es calendario) y la propia carpeta.
fn caldav_falso() -> String {
    let l = TcpListener::bind("127.0.0.1:0").unwrap();
    let base = format!("http://{}", l.local_addr().unwrap());
    let b = base.clone();
    std::thread::spawn(move || {
        for s in l.incoming().flatten() {
            let mut r = BufReader::new(s.try_clone().unwrap());
            let mut primera = String::new();
            r.read_line(&mut primera).unwrap();
            let ruta = primera.split(' ').nth(1).unwrap_or("").to_string();
            let (mut largo, mut auth) = (0usize, String::new());
            loop {
                let mut h = String::new();
                r.read_line(&mut h).unwrap();
                if h.trim().is_empty() {
                    break;
                }
                let (k, v) = h.split_once(':').unwrap();
                match k.to_ascii_lowercase().as_str() {
                    "content-length" => largo = v.trim().parse().unwrap(),
                    "authorization" => auth = v.trim().into(),
                    _ => {}
                }
            }
            let mut cuerpo = vec![0; largo];
            r.read_exact(&mut cuerpo).unwrap();
            let bien = auth == format!("Basic {}", base64(format!("yo@icloud.com:{CLAVE_APP}").as_bytes()));
            let xml = match ruta.as_str() {
                "/" => "<d:multistatus xmlns:d=\"DAV:\"><d:response><d:href>/</d:href><d:propstat><d:prop><d:current-user-principal><d:href>/123/principal/</d:href></d:current-user-principal></d:prop></d:propstat></d:response></d:multistatus>".to_string(),
                "/123/principal/" => format!("<multistatus xmlns=\"DAV:\"><response><href>/123/principal/</href><propstat><prop><calendar-home-set xmlns=\"urn:ietf:params:xml:ns:caldav\"><href xmlns=\"DAV:\">{b}/123/calendars/</href></calendar-home-set></prop></propstat></response></multistatus>"),
                "/123/calendars/" => concat!(
                    "<d:multistatus xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\">",
                    "<d:response><d:href>/123/calendars/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>",
                    "<d:response><d:href>/123/calendars/home/</d:href><d:propstat><d:prop><d:displayname>Casa &amp; familia</d:displayname><d:resourcetype><d:collection/><c:calendar/></d:resourcetype></d:prop></d:propstat></d:response>",
                    "<d:response><d:href>/123/calendars/work/</d:href><d:propstat><d:prop><d:displayname/><d:resourcetype><d:collection/><c:calendar/></d:resourcetype></d:prop></d:propstat></d:response>",
                    "<d:response><d:href>/123/calendars/inbox/</d:href><d:propstat><d:prop><d:displayname>Inbox</d:displayname><d:resourcetype><d:collection/><c:schedule-inbox/></d:resourcetype></d:prop></d:propstat></d:response>",
                    "</d:multistatus>").to_string(),
                _ => String::new(),
            };
            let (st, xml) = if !bien { ("401 Unauthorized", String::new()) } else if xml.is_empty() { ("404 Not Found", xml) } else { ("207 Multi-Status", xml) };
            let mut s = s;
            let _ = write!(s, "HTTP/1.1 {st}\r\nContent-Type: application/xml\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{xml}", xml.len());
        }
    });
    base
}

fn conf(m: &Mundo) -> String {
    fs::read_to_string(m.dir.join("rclone.conf")).unwrap()
}

// Las variables de entorno son del proceso: las pruebas que las usan van en una sola.
#[test]
fn todo_el_recorrido() {
    let base = caldav_falso();

    // 1. Clave mala: error con el texto de Apple, sin la sección en rclone.conf y con el otro remoto intacto.
    let m = mundo("mala", &base);
    let r = iniciar(&m.e, "yo@icloud.com", "otra");
    assert_eq!(r.unwrap_err().0, "Your Apple ID or password was incorrect.");
    assert!(!conf(&m).contains("[icloud]"), "{}", conf(&m));
    assert!(conf(&m).contains("[nas]\ntype = sftp"));
    drop(m);

    // 2. Clave buena → pide el código; código malo → error; bueno → sesión y montaje.
    let m = mundo("bien", &base);
    let p = Mutex::new(Pendiente::default());
    let (d, cambio) = paso(&m.e, &p, iniciar(&m.e, " yo@icloud.com ", CLAVE));
    assert_eq!(d["resultado"], Value::from("necesita_codigo").try_to_owned().unwrap(), "{d:?}");
    assert!(!cambio);
    let st = p.lock().unwrap().estado.clone().unwrap();
    assert_eq!(st, "*2fa_do");
    let modo = fs::metadata(m.dir.join("rclone.conf")).unwrap().permissions().mode() & 0o777;
    assert_eq!(modo, 0o600, "rclone.conf debe quedar 0600");
    let r = seguir(&m.e, &st, "000000");
    assert_eq!(r.unwrap_err().0, "Invalid verification code");
    let (d, cambio) = paso(&m.e, &p, seguir(&m.e, &st, CODIGO));
    assert_eq!(d["resultado"], Value::from("ok").try_to_owned().unwrap(), "{d:?}");
    assert!(cambio);
    assert!(p.lock().unwrap().estado.is_none());
    assert_eq!(fs::read_to_string(m.dir.join("systemctl.log")).unwrap(), "--user restart rclone-prueba\n");
    let est = estado(&m.e);
    assert_eq!(est["apple_id"], Value::from("yo@icloud.com").try_to_owned().unwrap());
    assert_eq!(est["icloud_con_sesion"], Value::from(true).try_to_owned().unwrap());
    assert_eq!(est["icloud_montado"], Value::from(false).try_to_owned().unwrap());
    assert_eq!(est["mail_configurado"], Value::from(false).try_to_owned().unwrap());

    // Ni la clave ni el código pasaron por argv ni quedaron en el registro.
    let argv = fs::read_to_string(m.dir.join("argv")).unwrap();
    let log = fs::read_to_string(&m.e.log).unwrap_or_default();
    for t in [&argv, &log] {
        assert!(!t.contains(CLAVE) && !t.contains("clave buena") && !t.contains(CODIGO), "un secreto se coló: {t}");
    }

    // 3. Mail y Calendar: una clave de app mala no guarda nada; la buena, el llavero y user.js.
    let r = configurar_mail(&m.e, "yo@icloud.com", "José", "mala");
    assert_eq!(r.unwrap_err().0, "Apple did not accept the app-specific password.");
    assert!(!m.dir.join("llavero").exists());
    assert_eq!(configurar_mail(&m.e, "yo@icloud.com", "José", CLAVE_APP).unwrap(), 2);
    assert_eq!(estado(&m.e)["mail_configurado"], Value::from(true).try_to_owned().unwrap());
    let uj = fs::read_to_string(m.e.thunderbird.join("abc.default-esr/user.js")).unwrap();
    assert!(uj.starts_with("user_pref(\"de.jose\", true);\n"), "se perdió lo de José: {uj}");
    assert!(uj.contains("user_pref(\"mail.accountmanager.accounts\", \"account1,mmacos_acc\");"), "{uj}");
    assert!(uj.contains(&format!("user_pref(\"calendar.registry.mmacos_cal0.uri\", \"{base}/123/calendars/home/\");")), "{uj}");
    assert!(uj.contains("user_pref(\"calendar.registry.mmacos_cal0.name\", \"Casa & familia\");"), "{uj}");
    assert!(uj.contains("user_pref(\"calendar.registry.mmacos_cal1.name\", \"iCloud\");"), "{uj}");
    assert!(!uj.contains("inbox"), "{uj}");
    assert!(!uj.contains(CLAVE_APP), "la clave de app no va en user.js");
    // Repetirlo no duplica el bloque.
    configurar_mail(&m.e, "yo@icloud.com", "José", CLAVE_APP).unwrap();
    let uj = fs::read_to_string(m.e.thunderbird.join("abc.default-esr/user.js")).unwrap();
    assert_eq!(uj.matches(MARCA_INI).count(), 1);

    // 4. Sign Out: todo fuera menos lo ajeno.
    cerrar_sesion(&m.e);
    let est = estado(&m.e);
    assert_eq!(est["icloud_con_sesion"], Value::from(false).try_to_owned().unwrap());
    assert_eq!(est["mail_configurado"], Value::from(false).try_to_owned().unwrap());
    assert!(!conf(&m).contains("[icloud]") && conf(&m).contains("[nas]"), "{}", conf(&m));
    let uj = fs::read_to_string(m.e.thunderbird.join("abc.default-esr/user.js")).unwrap();
    assert_eq!(uj, "user_pref(\"de.jose\", true);\n");
    assert!(fs::read_to_string(m.dir.join("systemctl.log")).unwrap().ends_with("--user stop rclone-prueba\n"));
}

#[test]
fn mensajes_de_rclone() {
    let s = |o: &str, e: &str| Salida { ok: false, stdout: o.into(), stderr: e.into() };
    assert_eq!(mensaje_de_error(&s("{\n \"Error\": \"Bad code\"\n}\n", "")), "Bad code");
    assert_eq!(mensaje_de_error(&s("", "2026/10/18 22:18:42 NOTICE: Fatal error: authStart: failed\n")), "authStart: failed");
    assert_eq!(mensaje_de_error(&s("", "nada\n")), "Apple did not accept the account.");
}

#[test]
fn base64_como_el_estandar() {
    assert_eq!(base64(b"yo@icloud.com:abcd-efgh"), "eW9AaWNsb3VkLmNvbTphYmNkLWVmZ2g=");
    assert_eq!(base64(b"ab"), "YWI=");
    assert_eq!(base64(b"abc"), "YWJj");
}

/// El llavero de verdad (Secret Service), contra un gnome-keyring aparte en un bus privado, nunca
/// el de la sesión: `appleid/prueba-llavero.sh`.
#[test]
#[ignore]
fn llavero_del_sistema() {
    assert!(std::env::var("PRUEBA_LLAVERO_PRIVADO").is_ok(), "solo con prueba-llavero.sh");
    let m = mundo("llavero", "http://127.0.0.1:9");
    let mut e = m.e.clone();
    e.llavero = Llavero::Sistema;
    assert!(!llavero_hay(&e));
    llavero_guardar(&e, "yo@icloud.com", CLAVE_APP).unwrap();
    llavero_guardar(&e, "yo@icloud.com", CLAVE_APP).unwrap(); // reemplaza, no duplica
    assert!(llavero_hay(&e));
    assert!(secret::hay(&atributos(Some("yo@icloud.com"))));
    assert!(!secret::hay(&atributos(Some("otro@icloud.com"))));
    llavero_borrar(&e);
    assert!(!llavero_hay(&e));
}
