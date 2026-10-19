# org.mintmacos.AppleID1

El Apple ID de System Preferences, sin ventana. Es una sola cuenta para dos cosas:
- **iCloud Drive**, con rclone: la contraseña del Apple ID y el código de 2FA.
- **Mail y Calendar**, en Thunderbird: con una contraseña de app de appleid.apple.com.

Sale de `settings/apple_id.py`. La hoja de Sign In la hace Dev-Dock en Vala; mientras tanto el panel de Python sigue igual.

- **Servicio:** `mint-macos-appleid` (rust/appleid), sin root.
- **Bus y ruta:** bus de sesión, nombre `org.mintmacos.AppleID1`, ruta `/org/mintmacos/AppleID1`.
- **Activación:** la arranca D-Bus. Sin llamadas se va a los 2 minutos; con un código de 2FA pendiente espera 10, porque ese estado vive solo en el proceso.

## Interfaz

| | |
|---|---|
| `Estado() → a{sv}` | `apple_id` (s, `""` sin sesión), `icloud_con_sesion` (b), `icloud_montado` (b), `mail_configurado` (b) |
| `IniciarSesion(s apple_id, s clave) → a{sv}` | `resultado` (s): `ok`, `necesita_codigo` o `error`; `mensaje` (s), para enseñarlo tal cual |
| `EnviarCodigo(s codigo) → a{sv}` | Lo mismo. Si Apple pide otro código, vuelve `necesita_codigo` |
| `ConfigurarMail(s apple_id, s nombre, s clave_app) → a{sv}` | `resultado` (s): `ok` o `error`; `cuantos_calendarios` (i); `mensaje` (s) |
| `CerrarSesion()` | Sign Out: quita el montaje, la sesión de rclone, la contraseña de app y la cuenta de Thunderbird |
| Señal `Cambio()` | Un Sign In, un Mail o un Sign Out terminó: la ventana vuelve a pedir `Estado` |

**Mensajes:** van en inglés, como en la Mac. Son los de rclone o Apple (por ejemplo «Your Apple ID or password was incorrect.»), o uno fijo de aquí.

**`ok` en `IniciarSesion` o `EnviarCodigo`:** la sesión quedó y se reinició el montaje (`rclone-icloud`). Si `icloud.sh montar` no está instalado, el `mensaje` lo dice.

**Duración:** las llamadas pueden tardar hasta un par de minutos, porque rclone habla con Apple. Hay que llamarlas en async: el servicio atiende `Estado` mientras tanto.

## Qué se guarda y dónde

**Regla (José, 18-10-2026):** la contraseña del Apple ID no queda recuperable en el disco. `rclone.conf` va entero cifrado con el cifrado propio de rclone, y la clave de ese cifrado vive en el llavero.

| Qué | Dónde | Notas |
|---|---|---|
| Contraseña del Apple ID | `rclone.conf`, sección `[icloud]`, **cifrado entero** | El backend de iCloud la exige (`Required: true`) para renovar la sesión. Sin la clave del llavero, el archivo no se lee: ni esto ni los otros remotos. Si Apple la rechaza, se borra en el acto |
| Sesión de iCloud (`trust_token`, `cookies`) | `rclone.conf`, cifrado | La escribe rclone. Dura 30 días; después toca `icloud.sh renovar` |
| Clave de `rclone.conf` | El llavero (Secret Service) | Atributos `xdg:schema=org.mintmacos.AppleID` y `servicio=rclone-config`. Son 32 bytes al azar (`/dev/urandom`) en base64. Se crea una vez; Sign Out no la borra, porque el archivo sigue cifrado con los otros remotos |
| Contraseña de app (Mail y Calendar) | El llavero | Atributos `xdg:schema=org.mintmacos.AppleID`, `servicio=mail` y `apple_id`: el mismo esquema que el panel de Python, así que lo que guardó él se encuentra |
| Cuenta IMAP/SMTP y calendarios CalDAV | `user.js` del perfil de Thunderbird, entre las marcas `// >>> mint-macos Apple ID` | Sin claves: Thunderbird la pide la primera vez o la toma del llavero. Lo demás que haya en `user.js` no se toca |
| Código de 2FA | En ningún lado | Solo pasa a rclone |
| Estado del 2FA de rclone | En la memoria del servicio | Se pierde si el servicio se va |

**Cómo abre rclone su configuración:**
- `~/.local/bin/rclone` es un envoltorio (lo pone `icloud.sh instalar`), y el binario de verdad está en `~/.local/lib/mint-macos/rclone/rclone`.
- El envoltorio pone `RCLONE_PASSWORD_COMMAND="~/.local/lib/mint-macos/mint-macos-appleid --clave-config"`, salvo que ya venga uno.
- Así lo usa igual cualquiera que llame a rclone:
  - el montaje (`rclone-icloud.service`, que además lleva `RCLONE_ASK_PASSWORD=false`);
  - el índice de Spotlyte (`rclone lsf`);
  - el panel de Python;
  - la terminal.
- Fynder solo habla con el socket `--rc` del montaje y no lee la configuración.

**`--clave-config` (el ayudante):**
- imprime la clave;
- si el llavero está cerrado, pide abrirlo con el diálogo de gnome-keyring y espera hasta 2 minutos;
- si no se abre, falla con «The keyring is locked.» en el journal y una notificación.

El montaje reintenta a los 30 s (`Restart=on-failure`). Nunca se queda preguntando en silencio.

**Migración y vuelta atrás:**
- **`icloud.sh cifrar`:**
  1. para los montajes, porque guardan la sesión que renuevan y la escribirían en claro;
  2. crea la clave si no existe y cifra (`--cifrar-config`, que corre `rclone config encryption set`);
  3. comprueba tres cosas: el archivo cifrado, el mismo `config dump` que antes y que sin la clave no se lea;
  4. vuelve a levantar los montajes.

  El respaldo en claro (`rclone.conf.antes-de-cifrar`, 0600) solo vive durante la operación: si algo falla se restaura, y si sale bien se borra con `shred`.
- **`icloud.sh descifrar`:** la vuelta atrás (`rclone config encryption remove`). La clave se queda en el llavero.
- **`IniciarSesion`:** también cifra, si el archivo todavía no lo está, antes de escribir la contraseña.

**La línea de comando nunca lleva secretos** (cualquiera la ve en `/proc/<pid>/cmdline`):
- la contraseña y el código van a la API de rclone (`rclone rcd` en un socket Unix propio, en `$XDG_RUNTIME_DIR/mint-macos-appleid-<pid>/`, con permisos 0700), en el cuerpo de `config/create` y `config/update`;
- el `rcd` vive lo que dura la llamada, y su carpeta se borra al terminar.

**Nada de secretos en el registro.** `~/.local/share/mint-macos/settings/apple-id.log` (0600, el mismo de `apple_id.py`) guarda solo la salida de rclone cuando cifrar falla.

**El llavero, por D-Bus directo:**
- con `plain`, como libsecret cuando no negocia; el bus es solo del usuario;
- con tope de 5 s por llamada, para que `Estado` no se cuelgue.

## Cómo

**iCloud Drive:**
1. `rclone.conf` se cifra si no lo está.
2. Se borra el remoto `icloud` que hubiera.
3. Se llama `config/create` con `apple_id` y `password`, y `opt` `{obscure, nonInteractive}`. rclone escribe la sección él mismo, cifrada, y respeta las otras.
4. Si rclone devuelve `State`, se pide el código. El código va por `config/update`, con `opt` `{continue, state, result}`.

**Mail y Calendar:**
- **Antes:** si Thunderbird está abierto, se le pide cerrarlo, porque lee la configuración al abrir.
- **CalDAV:** se descubren los calendarios con PROPFIND, siguiendo `caldav.icloud.com/` → `current-user-principal` → `calendar-home-set` → los calendarios. El buzón de citas no cuenta.
- **Una clave de app mala** da 401 y no se guarda nada.
- **Después:** el llavero y el bloque de `user.js`, que mezcla las listas de cuentas y servidores SMTP de `prefs.js`, porque `user.js` las pisa enteras.

**Sign Out:** para el montaje, corre `rclone config delete icloud`, borra del llavero lo de `servicio=mail` y quita el bloque de `user.js`.

## Pruebas

- **`cargo test -p mint-macos-appleid`:** usa un rclone (Python, con un `rcd` en socket Unix y un cifrado de mentira que exige el `--password-command`), un systemctl, un CalDAV (HTTP en 127.0.0.1), un llavero (archivo) y un Thunderbird de mentira. Recorre:
  - una clave mala, que no queda en `rclone.conf`, y el otro remoto intacto;
  - una clave buena, que pide el código: con un código malo da error, y con el bueno da `ok` y reinicia el montaje;
  - `rclone.conf` en 0600 y **cifrado**: no se leen la clave, su ofuscación, el Apple ID, la sesión, el código ni el host de otro remoto;
  - sin la clave del llavero, `config dump` falla y `Estado` no ve sesión;
  - la carpeta del socket de `rcd` no queda;
  - **ni la clave ni el código en argv ni en el registro**;
  - una clave de app mala, que no guarda nada;
  - la buena, con 2 calendarios (sin el buzón, con `&amp;` en el nombre y uno sin nombre, que sale como «iCloud»);
  - `user.js` sin perder lo de José y sin duplicar el bloque;
  - Sign Out.

  Comprobado al revés: si el código va en argv, si una clave rechazada se queda en el archivo, o si no se cifra, la prueba falla.
- **`appleid/prueba-llavero.sh`:** el Secret Service de verdad, contra un gnome-keyring aparte con su propio HOME, `XDG_RUNTIME_DIR` y bus. Guarda, reemplaza sin duplicar, busca por Apple ID y borra. Además crea la clave de `rclone.conf` una sola vez y la lee, y el Sign Out de Mail no la toca.
- **A mano, el 18-10-2026,** en una caja con HOME, bus y gnome-keyring propios, con el rclone de verdad y sin red. Salió bien:
  - `icloud.sh instalar` pone el envoltorio;
  - `cifrar` deja el archivo ilegible y sin respaldo;
  - con el envoltorio se lee y sin la clave no;
  - un segundo `cifrar` no cambia nada;
  - `Estado` responde con el archivo cifrado;
  - `descifrar` lo devuelve en claro.

  Con el llavero cerrado y sin pantalla, `--clave-config` falla a los 120 s con «The keyring is locked.».
- **Nada contra la cuenta real de José sin su sí:** un 2FA le llega al teléfono.

## Costo

- **RSS:** 4.4 MB.
- **`Estado`:** 30 ms.
