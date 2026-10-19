//! Con un rclone, un systemctl, un CalDAV, un llavero y un Thunderbird de mentira: nada sale a la
//! red ni toca la cuenta de José (un 2FA de verdad le llega al teléfono).
use super::*;
use std::io::{BufRead, BufReader, Read};
use std::net::TcpListener;
use std::os::unix::fs::PermissionsExt;

const CLAVE: &str = "clave buena con espacios y $ y '";
const CODIGO: &str = "123456";
const CLAVE_APP: &str = "abcd-efgh-ijkl-mnop";

/// Imita lo que este servicio le pide a rclone: config file, dump, delete, encryption set y un rcd
/// en un socket Unix con config/create, config/update y config/delete. Cifra «de mentira» (XOR con
/// la clave que da el --password-command): sin la clave no se lee nada. Anota cada argv.
const RCLONE: &str = r#"#!/usr/bin/env python3
import os, sys, json, subprocess, socketserver, http.server, base64
D = os.environ['PRUEBA_DIR']; CONF = os.environ['RCLONE_CONFIG']
open(os.path.join(D, 'argv'), 'a').write(' '.join(sys.argv[1:]) + '\n')
def clave():
    pc = os.environ.get('RCLONE_PASSWORD_COMMAND')
    if not pc:
        sys.exit('CRITICAL: unable to decrypt configuration and not allowed to ask for password')
    r = subprocess.run(pc.split(' '), capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        sys.exit('CRITICAL: password command failed')
    return r.stdout.strip()
def xor(b, k):
    k = k.encode()
    return bytes(x ^ k[i % len(k)] for i, x in enumerate(b))
def leer():
    try:
        t = open(CONF).read()
    except FileNotFoundError:
        return {}, False
    if 'RCLONE_ENCRYPT_V0:' in t:
        try:
            return json.loads(xor(bytes.fromhex(t.split('RCLONE_ENCRYPT_V0:\n', 1)[1].strip()), clave())), True
        except ValueError:
            sys.exit('CRITICAL: wrong password')
    r, act = {}, None
    for l in t.splitlines():
        l = l.strip()
        if l.startswith('['):
            act = l[1:-1]; r[act] = {}
        elif '=' in l and act:
            k, v = l.split('=', 1); r[act][k.strip()] = v.strip()
    return r, False
def escribir(r, cif):
    if cif:
        t = '# Encrypted rclone configuration File\n\nRCLONE_ENCRYPT_V0:\n' + xor(json.dumps(r).encode(), clave()).hex() + '\n'
    else:
        t = ''.join('[%s]\n%s\n' % (n, ''.join('%s = %s\n' % kv for kv in s.items())) for n, s in r.items())
    fd = os.open(CONF + '.n', os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.write(fd, t.encode()); os.close(fd); os.replace(CONF + '.n', CONF)
a = sys.argv[1:]
if a[:2] == ['config', 'file']:
    print('Configuration file is stored at:\n' + CONF)
elif a[:2] == ['config', 'dump']:
    print(json.dumps(leer()[0]))
elif a[:2] == ['config', 'delete']:
    r, c = leer(); r.pop(a[2], None); escribir(r, c)
elif a[:3] == ['config', 'encryption', 'set']:
    r, _ = leer(); escribir(r, True)
elif a[0] == 'rcd':
    sock = a[a.index('--rc-addr') + 1][len('unix://'):]
    class H(http.server.BaseHTTPRequestHandler):
        def address_string(self): return 'unix'
        def log_message(self, *x): pass
        def do_POST(self):
            p = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            r, c = leer(); n = p['name']; st = 200
            out = {'State': '', 'Option': None, 'Error': '', 'Result': ''}
            if self.path == '/config/delete':
                r.pop(n, None); out = {}
            elif self.path == '/config/create':
                pa = p['parameters']
                r[n] = {'type': p['type'], 'apple_id': pa['apple_id'], 'password': 'OBS:' + base64.b64encode(pa['password'].encode()).decode()}
                if pa['password'] != os.environ['PRUEBA_CLAVE']:
                    st, out = 500, {'error': 'Your Apple ID or password was incorrect.', 'status': 500}
                else:
                    out['State'] = '*2fa_do'; out['Option'] = {'Help': 'Two-factor authentication: please enter your 2FA code'}
            elif self.path == '/config/update':
                o = p['opt']
                if o.get('state') != '*2fa_do':
                    st, out = 500, {'error': 'unknown state', 'status': 500}
                elif o.get('result') != os.environ['PRUEBA_CODIGO']:
                    st, out = 500, {'error': 'Invalid verification code', 'status': 500}
                else:
                    r[n]['trust_token'] = 'tok'
            escribir(r, c)
            b = json.dumps(out).encode()
            self.send_response(st); self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(b))); self.end_headers(); self.wfile.write(b)
    class S(socketserver.UnixStreamServer):
        def get_request(self):
            s, _ = self.socket.accept()
            return s, ('unix', 0)
    S(sock, H).serve_forever()
else:
    sys.exit(2)
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
    // El --password-command: la clave de rclone.conf del llavero de mentira (falla si no está).
    let ayudante = ejecutable("ayudante", &format!("#!/bin/sh\nset -e\nc=$(cut -f2 '{}/llavero/rclone-config')\n[ -n \"$c\" ] && echo \"$c\"\n", dir.display()));
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
        ayudante: ayudante.display().to_string(),
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

fn remotos(e: &Entorno) -> Vec<String> {
    volcado(e).unwrap().keys().cloned().collect()
}

/// Lo que rclone.conf no puede llevar legible: la clave, su ofuscación, el código ni lo de otros remotos.
fn sin_nada_legible(m: &Mundo) {
    let t = conf(m);
    assert!(cifrada(&m.dir.join("rclone.conf")), "rclone.conf sin cifrar: {t}");
    let ofus = base64(CLAVE.as_bytes());
    for x in [CLAVE, ofus.as_str(), "10.0.0.2", "yo@icloud.com", "trust_token", CODIGO] {
        assert!(!t.contains(x), "rclone.conf deja leer «{x}»: {t}");
    }
}

// Las variables de entorno son del proceso: las pruebas que las usan van en una sola.
#[test]
fn todo_el_recorrido() {
    let base = caldav_falso();

    // 1. Clave mala: error con el texto de Apple; rclone.conf queda cifrado, sin el remoto y con
    //    el otro intacto.
    let m = mundo("mala", &base);
    let r = iniciar(&m.e, "yo@icloud.com", "otra");
    assert_eq!(r.unwrap_err().0, "Your Apple ID or password was incorrect.");
    sin_nada_legible(&m);
    assert_eq!(remotos(&m.e), vec!["nas"]);
    assert_eq!(volcado(&m.e).unwrap()["nas"]["host"], "10.0.0.2");
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
    sin_nada_legible(&m);
    // Sin la clave del llavero no se lee nada: ni la sesión.
    let mut sin = m.e.clone();
    sin.ayudante = "false".into();
    assert!(volcado(&sin).is_err());
    assert_eq!(estado(&sin)["icloud_con_sesion"], Value::from(false).try_to_owned().unwrap());
    // El socket de rcd no queda.
    let run = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    assert!(!run.join(format!("mint-macos-appleid-{}", std::process::id())).exists());

    // Ni la clave ni el código pasaron por argv ni quedaron en el registro.
    let argv = fs::read_to_string(m.dir.join("argv")).unwrap();
    let log = fs::read_to_string(&m.e.log).unwrap_or_default();
    for t in [&argv, &log] {
        assert!(!t.contains(CLAVE) && !t.contains("clave buena") && !t.contains(CODIGO), "un secreto se coló: {t}");
    }

    // 3. Mail y Calendar: una clave de app mala no guarda nada; la buena, el llavero y user.js.
    let r = configurar_mail(&m.e, "yo@icloud.com", "José", "mala");
    assert_eq!(r.unwrap_err().0, "Apple did not accept the app-specific password.");
    assert!(!m.dir.join("llavero/mail").exists());
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

    // 4. Sign Out: todo fuera menos lo ajeno; rclone.conf sigue cifrado y su clave, en el llavero.
    cerrar_sesion(&m.e);
    let est = estado(&m.e);
    assert_eq!(est["icloud_con_sesion"], Value::from(false).try_to_owned().unwrap());
    assert_eq!(est["mail_configurado"], Value::from(false).try_to_owned().unwrap());
    assert_eq!(remotos(&m.e), vec!["nas"]);
    sin_nada_legible(&m);
    assert!(llavero_hay(&m.e, CLAVE_CONFIG));
    let uj = fs::read_to_string(m.e.thunderbird.join("abc.default-esr/user.js")).unwrap();
    assert_eq!(uj, "user_pref(\"de.jose\", true);\n");
    assert!(fs::read_to_string(m.dir.join("systemctl.log")).unwrap().ends_with("--user stop rclone-prueba\n"));

    // 5. Cifrar otra vez no cambia la clave ni lo que hay.
    let antes = fs::read_to_string(m.dir.join("llavero/rclone-config")).unwrap();
    asegurar_cifrado(&m.e).unwrap();
    assert_eq!(fs::read_to_string(m.dir.join("llavero/rclone-config")).unwrap(), antes);
    assert_eq!(remotos(&m.e), vec!["nas"]);
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
    assert!(!llavero_hay(&e, "mail"));
    llavero_guardar(&e, "mail", "Apple ID (app) yo@icloud.com", Some("yo@icloud.com"), CLAVE_APP).unwrap();
    llavero_guardar(&e, "mail", "Apple ID (app) yo@icloud.com", Some("yo@icloud.com"), CLAVE_APP).unwrap(); // reemplaza, no duplica
    assert!(llavero_hay(&e, "mail"));
    assert!(secret::hay(&atributos("mail", Some("yo@icloud.com"))));
    assert!(!secret::hay(&atributos("mail", Some("otro@icloud.com"))));
    // La clave de rclone.conf: se crea una vez, se lee y no la toca el Sign Out de Mail.
    crear_clave_config(&e).unwrap();
    let c = llavero_leer(&e, CLAVE_CONFIG, false).unwrap().unwrap();
    assert_eq!(c.len(), 44);
    crear_clave_config(&e).unwrap();
    assert_eq!(llavero_leer(&e, CLAVE_CONFIG, false).unwrap().unwrap(), c);
    llavero_borrar(&e, "mail");
    assert!(!llavero_hay(&e, "mail"));
    assert!(llavero_hay(&e, CLAVE_CONFIG));
}
