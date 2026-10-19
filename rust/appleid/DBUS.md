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

| Qué | Dónde | Notas |
|---|---|---|
| Contraseña del Apple ID | `rclone.conf`, sección `[icloud]`, campo `password` | **Ofuscada con `rclone obscure`, que es reversible.** El backend de iCloud la exige (`Required: true`) para renovar la sesión. El archivo queda en 0600 desde el primer byte. Si Apple la rechaza, se borra en el acto |
| Sesión de iCloud (`trust_token`, `cookies`) | `rclone.conf`, sección `[icloud]` | La escribe rclone. Dura 30 días; después toca `icloud.sh renovar` |
| Contraseña de app (Mail y Calendar) | El llavero de la sesión (Secret Service) | Atributos `xdg:schema=org.mintmacos.AppleID`, `servicio=mail` y `apple_id`: el mismo esquema que el panel de Python, así que lo que guardó él se encuentra |
| Cuenta IMAP/SMTP y calendarios CalDAV | `user.js` del perfil de Thunderbird, entre las marcas `// >>> mint-macos Apple ID` | Sin claves: Thunderbird la pide la primera vez o la toma del llavero. Lo demás que haya en `user.js` no se toca |
| Código de 2FA | En ningún lado | Solo pasa a rclone |
| Estado del 2FA de rclone | En la memoria del servicio | Se pierde si el servicio se va |

**La línea de comando nunca lleva secretos** (cualquiera la ve en `/proc/<pid>/cmdline`):
- la contraseña va a `rclone obscure -` por stdin;
- el estado y el código, por las variables `RCLONE_STATE` y `RCLONE_RESULT`. `/proc/<pid>/environ` solo lo lee el mismo usuario.

**Nada de secretos en el registro.** `~/.local/share/mint-macos/settings/apple-id.log` (0600, el mismo de `apple_id.py`) guarda solo la salida de rclone cuando un paso falla: nunca sus argumentos ni su entorno.

**El llavero, por D-Bus directo:**
- con `plain`, como libsecret cuando no negocia; el bus es solo del usuario;
- con tope de 5 s, para que `Estado` no se cuelgue si el llavero no contesta;
- si el llavero está bloqueado, `ConfigurarMail` devuelve error y no guarda nada.

## Cómo

**iCloud Drive:**
1. Se escribe la sección `[icloud]`: `type`, `apple_id` y la contraseña ofuscada. Las otras secciones de `rclone.conf` se respetan.
2. Se corre `rclone config update icloud` con `RCLONE_NON_INTERACTIVE=true`; sin parámetros, rclone hace el alta del backend con lo que ya está en la sección.
3. Si rclone devuelve `State`, se pide el código. El código va con `RCLONE_CONTINUE=true`, `RCLONE_STATE` y `RCLONE_RESULT`.

**Mail y Calendar:**
- **Antes:** si Thunderbird está abierto, se le pide cerrarlo, porque lee la configuración al abrir.
- **CalDAV:** se descubren los calendarios con PROPFIND, siguiendo `caldav.icloud.com/` → `current-user-principal` → `calendar-home-set` → los calendarios. El buzón de citas no cuenta.
- **Una clave de app mala** da 401 y no se guarda nada.
- **Después:** el llavero y el bloque de `user.js`, que mezcla las listas de cuentas y servidores SMTP de `prefs.js`, porque `user.js` las pisa enteras.

**Sign Out:** para el montaje, corre `rclone config delete icloud`, borra del llavero lo de `servicio=mail` y quita el bloque de `user.js`.

## Pruebas

- **`cargo test -p mint-macos-appleid`:** usa un rclone (bash), un systemctl, un CalDAV (HTTP en 127.0.0.1), un llavero (archivo) y un Thunderbird de mentira. Recorre:
  - una clave mala, que no queda en `rclone.conf`, y el otro remoto intacto;
  - una clave buena, que pide el código: con un código malo da error, y con el bueno da `ok` y reinicia el montaje;
  - `rclone.conf` en 0600;
  - **ni la clave ni el código en argv ni en el registro**;
  - una clave de app mala, que no guarda nada;
  - la buena, con 2 calendarios (sin el buzón, con `&amp;` en el nombre y uno sin nombre, que sale como «iCloud»);
  - `user.js` sin perder lo de José y sin duplicar el bloque;
  - Sign Out.

  Comprobado al revés: si el código va en argv, o si una clave rechazada se queda en el archivo, la prueba falla.
- **`appleid/prueba-llavero.sh`:** el Secret Service de verdad, contra un gnome-keyring aparte con su propio HOME, `XDG_RUNTIME_DIR` y bus. Guarda, reemplaza sin duplicar, busca por Apple ID y borra.
- **Nada contra la cuenta real de José sin su sí:** un 2FA le llega al teléfono.

## Costo

- **RSS:** 4.4 MB.
- **`Estado`:** 30 ms.
