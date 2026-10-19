# mint-macos: de macOS Catalina a Linux Mint

Lleva a un usuario de una Mac con macOS Catalina a Linux Mint 22 (Cinnamon)
sin que tenga que aprender otro escritorio: el mismo teclado (⌘ y ⌥), la
barra de menús arriba con el menú de cada app, el Dock, el Finder (Fynder) y
el aspecto de Catalina en oscuro. Y, aparte, sus archivos.

Todo se instala para un usuario, en su `$HOME`. Lo único que pide `sudo` es
`requisitos.sh`, en un solo bloque.

## Qué hace falta

- **Linux Mint 22** (Cinnamon) recién instalado, con el usuario ya creado.
- **El disco de la Mac** conectado (interno o por USB). Se lee en **solo
  lectura**: nunca se escribe en él.
- Internet (se bajan Fynder, Muelle, keyd, libfsapfs y los temas base).
- Para los glifos de la barra del Finder, **una vez y opcional**, la Mac
  encendida en macOS (ver «Glifos de la barra»).

## Paso a paso

### 1. Requisitos (con sudo)

    git clone https://github.com/josemalena/mint-macos && cd mint-macos
    ./requisitos.sh --simular     # dice qué va a instalar, sin tocar nada
    sudo ./requisitos.sh

Instala los paquetes de apt para compilar y correr, compila **keyd** (⌘ y ⌥
en todo el sistema) y **libfsapfs** (leer el disco de la Mac), pone
`/etc/keyd/default.conf`, activa `user_allow_other` en `/etc/fuse.conf` y
mete al usuario en los grupos `keyd` y `disk`. **Cierra sesión y vuelve a
entrar** para que valgan los grupos.

También crea las rutas de macOS como enlaces: `/Users` → `/home` y
`/Volumes` → `/media/<usuario>`, donde Linux monta los discos. Con el mismo
nombre de usuario y uid que en la Mac (en la de José, `jmalena` y 501),
`/Users/jmalena/…` y `/Volumes/<disco>/…` sirven igual en las dos, y los
archivos que vienen del disco de la Mac o de un NAS por NFS conservan su
dueño. Son enlaces a propósito:
- Los discos se siguen montando en `/media`, porque la ruta de udisks viene
  compilada y no se configura.
- `$HOME` sigue en `/home`. Moverlo rompe `fstab`, Docker, los snaps y las
  rutas guardadas.
- Si ya existe algo con ese nombre, no se toca.

`/Applications` es distinta: es una carpeta real del usuario, no un enlace,
porque Fynder tiene que verla como `/Applications` y `aplicaciones/` la llena
sin sudo (ver `aplicaciones/LEEME.md`). `--quitar-rutas-mac` solo la borra si
la creó `requisitos.sh` y ya está vacía.

### 2. Ubicar el disco y el usuario de la Mac

    lsblk -f                       # el contenedor sale como «apfs», p. ej. /dev/sdb2
    fsapfsinfo /dev/sdb2           # lista los volúmenes con su índice

En una Mac con Catalina salen cinco: `<Nombre>` (el sistema),
`<Nombre> - Data` (los datos), `Preboot`, `Recovery` y `VM`. El usuario de la
Mac es la carpeta de `/Users` en el volumen de datos.

Si hay un solo disco de Mac, todo se detecta solo; si no, se pasa con
parámetros: `--disco /dev/sdb2 --volumen-sistema 5 --volumen-datos 1
--usuario-mac jmalena`.

### 3. Instalar (sin sudo)

    ./instalar.sh --disco /dev/sdb2 --usuario-mac jmalena

En orden:

1. `construir.sh`: compila **Fynder** y **Muelle** (el Dock) en `~/.local`, cada
   uno en el hash de su repo que fija `versiones.sh`.
2. `desde-mac.sh`: saca de la Mac las fuentes San Francisco, la manzana, los
   íconos del Finder y del Dock, y el fondo de Catalina (`--cuadro 7`, el
   atardecer; `--cuadro 1`, la noche).
3. `install.sh`: el teclado (keyd por app, kitty, VS Code, y Ulauncher en
   ⌘Espacio si está instalado: viene de su PPA, no de requisitos.sh), los
   applets de la barra y el menú global de las apps.
   Además, el ⌘Tab de Catalina (`extensions/cmdtab@macos`) y el **efecto
   genio** al minimizar (`extensions/magiclamp.sh`: Magic Lamp de klangman,
   de Cinnamon Spices, bajado en un commit fijo y con el hash verificado).
4. `tema/instalar.sh`: el tema **Constanza** (GTK, Cinnamon, íconos, fuentes,
   fondo, el Dock).
5. `cinnamon/barra.sh`: la barra de menús arriba, a 22 px, con los applets en
   el orden de la Mac.
6. Fynder como administrador de archivos y el Dock del fork al entrar.

El arranque con la manzana y la barra de progreso (Plymouth) cambia el
initramfs y pide sudo; instalar.sh deja la vista previa y dice el comando:
`sudo tema/arranque/instalar.sh` (vuelta atrás: `--deshacer`).

Sin el disco de la Mac: `./instalar.sh --sin-mac` (Inter en vez de la SF,
los íconos de Adwaita y el fondo que haya).

**Al terminar, cierra sesión y vuelve a entrar.**

### 4. Probar

- La barra: la manzana, el nombre de la app en negrita y su menú (en Fynder,
  Firefox, Edge, Thunderbird); About y Quit desde el nombre.
- ⌘C/⌘V, ⌘Tab, ⌘Espacio (Ulauncher), ⌘Q en las apps.
- El Dock: el punto bajo las apps abiertas, el separador y la pila de Descargas.
- Fynder: el lateral, la barra, las vistas (⌘1…⌘4), ⌘J, Quick Look (⌘Y).

### 5. Los datos del usuario (aparte)

    ./migrar-datos.sh --usuario-mac jmalena --simular     # primero, siempre
    ./migrar-datos.sh --usuario-mac jmalena

Copia Desktop, Documents, Downloads, Pictures, Movies y Music de la Mac a las
carpetas del usuario de Linux (las de xdg-user-dirs). **Nunca sobrescribe**:
lo que ya existe se queda y sale en el informe. Si `~/Documents` es un enlace a
otro disco, copia allá. Antes de copiar mide el tamaño y el espacio libre y
no empieza si no cabe. La fototeca (`.photoslibrary`) se copia entera, como
carpeta: las fotos están dentro, en `originals`.

### 6. iCloud Drive (opcional)

    icloud/icloud.sh alta      # una vez: pide el Apple ID, su contraseña y el código del iPhone, nada más
    icloud/icloud.sh montar    # ~/iCloud Drive, en el lateral de Fynder (iCloud → iCloud Drive)
    icloud/icloud.sh fotos     # opcional: Fotos en solo lectura, en ~/Pictures/iCloud Photos

Usa rclone (su backend `iclouddrive`, desde v1.69; se instala el oficial
v1.75.1 en `~/.local/bin` con su checksum, sin tocar el de Mint, que es viejo).
Lo que hay que saber:

- **Del lado de Apple:** en el iPhone, Ajustes → [nombre] → iCloud → «Access
  iCloud Data on the Web» encendido. La contraseña es la **normal** del Apple ID
  (no una de aplicación) y pide el código de 2FA. Con Advanced Data Protection
  también funciona, pero hay que aprobar en un dispositivo de confianza; si
  rclone dice «Missing PCS cookies», es eso: aprobar y volver a hacer el alta.
- **La sesión dura 30 días.** Un aviso del escritorio sale desde el día 26;
  se renueva con `icloud/icloud.sh renovar` (otro código al iPhone).
- **Es experimental** en rclone («Tier 4»): iCloud Drive se lee y se escribe;
  Fotos, solo se lee. La caché va en `~/.cache/rclone` (máximo 10 GB).
- **La configuración** queda en `~/.config/rclone/rclone.conf`, en tu `$HOME`.
  Se puede cifrar (en `rclone config`, «s»); entonces el montaje toma la
  clave del llavero de la sesión.
- **Tras un corte de luz** el equipo puede arrancar antes que el internet. El
  montaje reintenta cada 30 s y, antes de cada intento, borra el socket que deja
  el intento fallido; sin eso, ningún reintento entraba. Si Desktop o Documents
  viven dentro de iCloud Drive, `montar` apaga la reescritura de
  `xdg-user-dirs` (`~/.config/user-dirs.conf` con `enabled=False`): si no, al
  iniciar sesión con iCloud todavía sin montar, el escritorio pasa a enseñar el
  `$HOME`. `deshacer` lo devuelve como estaba.
- **Desconectar:** `icloud/icloud.sh deshacer` quita el montaje, el aviso y la
  entrada de Fynder; `rclone config delete icloud` borra la sesión.

### Volver atrás

    ./instalar.sh --deshacer

Devuelve el tema, la barra, los atajos, el menú global, el administrador de
archivos y el Dock a como estaban antes de la última instalación. Fynder y
Muelle quedan en `~/.local`, sin usarse. Lo de `requisitos.sh` (keyd,
libfsapfs, los paquetes) no se quita. Los enlaces `/Users` y `/Volumes` y la carpeta
`/Applications` (vacía) se quitan aparte con `sudo ./requisitos.sh --quitar-rutas-mac`, que solo borra
los que creó él.

## Glifos de la barra del Finder (en la Mac, una vez, opcional)

Los íconos chicos de la barra de herramientas del Finder (atrás, vistas,
acción, compartir…) están en el catálogo de recursos del aspecto del sistema
de macOS, que **solo macOS sabe abrir** (lo desempaca CoreUI); desde Linux no
se pueden sacar. Sin ellos, Fynder usa los de Adwaita.

Lo que Constanza espera, en `~/.local/share/constanza/glifos-finder/`: un
`<Nombre>@1x.png` y un `<Nombre>@2x.png` por glifo, en negro con
transparencia, con estos nombres (la lista exacta está en `BARRA`, en
`tema/iconos/finder.py`): `GoBack`, `GoForward`, `IconView`, `ListView`,
`ColumnView`, `GalleryView`, `Action`, `Share`, `SearchMagGlass`, `Cancel`,
`ToolbarTagIcon`, `ToolbarGetInfo`, `ToolbarDelete`, `ToolbarNewFolder`,
`QuickLook`, `Sidebar`, `ToolbarArrangeBy`, `Path`, `PulldownArrowSmall`,
`Refresh`, `Add` y `Remove`.

En la Mac:

- `tema/macos/exportar-glifos.swift` (`swift exportar-glifos.swift`) exporta
  a `/Users/Shared/glifos-finder/png/` las imágenes de plantilla de AppKit que
  usa la barra (`NSGoBackTemplate`, `NSIconViewTemplate`…), a 1x y 2x. Son
  las mismas formas con otros nombres.
- Los de arriba, con esos nombres, se sacaron del catálogo con una
  herramienta de CoreUI; ese exportador **todavía no está en el repo**
  (pendiente).

Se copian a Linux, a `~/.local/share/constanza/glifos-finder/`, y se vuelve
a correr `./desde-mac.sh` (o `./instalar.sh`).

## Lo que NO está en este repo, y por qué

Las fuentes San Francisco, los íconos y glifos de macOS, el fondo de Catalina
y la manzana son de Apple: su licencia no deja redistribuirlos. Por eso **no
hay ni uno en el repo** (`.gitignore` bloquea `.icns`, `.png`, `.ttf`, `.otf`,
`.heic` y `.jpg`). Cada quien los saca de **su propia Mac** con
`desde-mac.sh`, y quedan solo en su `$HOME`:

| Qué | Dónde queda |
|---|---|
| Fuentes San Francisco | `~/.local/share/fonts/san-francisco/` |
| La manzana | `~/.local/share/constanza/manzana/` |
| Íconos del Finder y del Dock | `~/.local/share/icons/Constanza/` |
| Glifos de la barra | `~/.local/share/constanza/glifos-finder/` |
| Fondo de Catalina | `~/.local/share/backgrounds/constanza/` |

## Las versiones: `versiones.sh`

Todo lo de afuera va en una versión fija, y todas están en un solo archivo,
`versiones.sh`, que los scripts cargan con `source`: el commit de cada fork
(Fynder, Muelle, slick-greeter-mac, Spotlyte) con su upstream y su
base, lo que se baja en una versión fija (keyd, libfsapfs, Magic Lamp,
Mojave-gtk-theme, rclone) y los paquetes de apt de `requisitos.sh`. Ningún otro
script fija un hash.

    ./verificar-versiones.sh             # comprueba el manifiesto contra los repos
    ./verificar-versiones.sh --escribir  # y reescribe VERSIONES.md

El paquete para otra computadora sale de un solo comando, `./armar.sh`: clona
el HEAD y cada fork en su hash, compila, corre las pruebas y arma el paquete
con `paquete.sh`. Dos corridas del mismo HEAD tienen que dar los mismos
archivos (`SUMAS.sha256` en la carpeta del paquete).

Fynder y Spotlyte están en repos privados: para clonarlos, `armar.sh` necesita
credenciales de GitHub (`gh auth login`, que deja a `gh` de ayudante de git).
Sin ellas cae al repo local de al lado, si tiene el hash, y lo avisa con ⚠. La
computadora que recibe el paquete no clona nada: todo va dentro.

`VERSIONES.md` es la lista de parches de cada fork sobre su upstream, generada;
el verificador falla si quedó vieja o si un script volvió a fijar un hash por
su cuenta.

## Las piezas

| Repo | Qué es | Licencia |
|---|---|---|
| [josemalena/fynder](https://github.com/josemalena/fynder) (privado) | El administrador de archivos (fork de Nemo) | GPL-2+ |
| [josemalena/muelle](https://github.com/josemalena/muelle) | El Dock (fork de zquestz/plank-reloaded; se instala como `muelle`) | GPL-3 |
| [josemalena/mint-macos-greeter](https://github.com/josemalena/mint-macos-greeter) | La pantalla de inicio y de bloqueo (fork de linuxmint/slick-greeter; se instala como `slick-greeter-mac`) | GPL-3 |
| [Magic Lamp](https://github.com/klangman/CinnamonMagicLamp) (klangman, Cinnamon Spices) | El efecto genio al minimizar; se baja en un commit fijo, no se copia | GPL-3 (su `LICENSE` va con ella) |
| este | Tema, applets, teclado, menú global, instaladores | ver `tema/CREDITOS.md` |

## Cosas que saber

- Cinnamon guarda en caché los módulos de los applets (`dbusmenu.js`,
  `catalina.js`…): después de actualizarlos hay que cerrar
  sesión (o `cinnamon --replace`), no basta recargar el applet.
- Sin vidrio (José, 18-10-2026: «no usemos vidrio»): los menús salen opacos y
  el panel del Notification Center casi opaco. El desenfoque de lo de detrás
  (`vidrio.js`) se quitó; las reglas `.con-vidrio` del tema quedan sin uso.
- El hinting de las fuentes queda en «none» y el suavizado en gris, como en
  macOS: afecta a todo el escritorio.
- `cinnamon/barra.sh` deja el panel arriba con el id 1; si la máquina tiene
  otros paneles, hay que revisarlo.
