# Una AppImage en /Applications: propuesta

**Estado: propuesta aprobada por José el 17-10-2026, sin código todavía.** Sus
decisiones están en «Decisiones», al final. En la Mac, arrastrar una `.app`
a Applications ya la deja instalada, y arrastrarla a la Trash la quita. Aquí la
pieza equivalente es la AppImage: un solo archivo, una app entera. La propuesta
es que soltar una AppImage en `/Applications` (o en `~/Applications`, si
existe) la deje integrada como cualquier otra app: con nombre e ícono en
Fynder, el Launchpad, Spotlyte y el Dock, y en «Open With». Botarla la quita de
todas partes. No hay que instalar nada.

Marcas: **[V]** está verificado en la fuente citada o en esta máquina. **[I]**
es una inferencia que hay que comprobar antes de darla por buena.

## Resumen

| Pregunta | Respuesta corta |
|---|---|
| ¿Cómo se detecta? | Un `.path` nuevo sobre `/Applications` y `~/Applications`. Se integra solo un ELF que tenga `AI\x02` en el byte 8 (tipo 2) y un squashfs (`hsqs`) a continuación del ELF. |
| ¿Se ejecuta para leerla? | **Nunca.** El `.desktop` y el ícono se leen del squashfs con el offset, igual que el miniaturizador que ya trae Mint. |
| ¿Dónde queda? | El archivo no se mueve ni se renombra. Se genera un lanzador en `~/.local/share/applications/mint-macos-appimage-<md5>.desktop` y el ícono en `~/.local/share/icons/hicolor/…`. |
| ¿Si se mueve o se bota? | Cada corrida compara las AppImages presentes con los lanzadores que ella misma creó. Lo que ya no está se quita. |
| ¿Riesgo? | Corre como jmalena y sin aislamiento. La mitigación es una confirmación la primera vez, como Gatekeeper, y nunca leerla como root. |

## 1. Detección

**Cuándo se mira.** Hoy `aplicaciones.path` vigila las carpetas de lanzadores,
pero no `/Applications` (`aplicaciones/instalar.sh`). Se propone una unidad
aparte, `appimages.path`, con `PathChanged=/Applications` y
`PathChanged=%h/Applications`, que corre el mismo binario en un modo nuevo
(`mint-macos-aplicaciones --appimages`). Va aparte porque el generador de
siempre también escribe en `/Applications`. Así cada corrida de uno no dispara
al otro dos veces, y el modo AppImage solo mira los archivos `*.AppImage` y
`*.appimage`. Si nada cambió, sale sin escribir, igual que el generador
(«dos corridas seguidas no cambian nada»).

**Qué se integra.**

- **Tipo 2**: un ELF válido (`\x7fELF`) con el magic `0x414902` (`AI\x02`) en
  el offset 8. La spec lo exige [V]
  (https://github.com/AppImage/AppImageSpec/blob/master/draft.md).
- **Dónde está el sistema de archivos**: el payload empieza donde termina el
  ELF, en `e_shoff + e_shentsize × e_shnum` [V]. Así lo calcula go-appimage
  (`internal/helpers/elfsize.go`), y así lo calcula
  `/usr/bin/xapp-appimage-thumbnailer` en esta máquina (xapp 1.2.9).
- **Squashfs o DwarFS**: en ese offset se leen 4 bytes. `hsqs` es squashfs y
  se integra. `DWARFS` es la compresión de los runtimes nuevos (uruntime,
  appimagetool de pkgforge) [V]
  (https://github.com/VHSgunzo/uruntime). En Rust no hay un lector maduro de
  DwarFS [I], así que **no se integra**: el servicio avisa con una notificación
  y la deja quieta.
- **Tipo 1** (ISO 9660, `AI\x01`): está obsoleto y no se integra. Se avisa
  igual que con DwarFS.
- **Exclusiones de la spec**: no se integra si el `.desktop` trae
  `X-AppImage-Integrate=false` o `Terminal=true`, como hace libappimage [V]. Se
  respeta además el archivo `no_desktopintegration` en
  `$XDG_DATA_HOME/appimagekit/`, `/usr/share/appimagekit/` o `/etc/appimagekit/`
  [V] (spec). Soltar el archivo en la carpeta cuenta como el consentimiento que
  pide la spec [I].

## 2. El `.desktop` y el ícono, sin ejecutarla

`--appimage-extract` y `--appimage-offset` son el runtime de la AppImage
ejecutándose [V]. Gear Lever los bloquea por defecto con
`block-unsafe-extractor=true` (`data/it.mijorus.gearlever.gschema.xml`). No se
usan.

**Cómo se lee.** Con el crate **`backhand`**, dentro del mismo proceso: el
squashfs se lee con el offset y los bytes del archivo quedan en memoria, sin
escribir nada al disco. `backhand` trae por defecto gzip, xz, zstd y lz4 [V]
(https://github.com/wcampbell0x2a/backhand). No falta ningún formato de los
comunes, y no se lanza ningún proceso por cada AppImage. Falta confirmar el
nombre de la API para abrir con offset [I]. Si no existe, basta un lector con
`Seek` que ya sume el offset.

Se descartan las otras dos vías:

- **`unsquashfs -o OFFSET`.** Es lo que usan Gear Lever y el miniaturizador de
  Mint, pero extrae a disco a partir de una imagen ajena. unsquashfs ya tuvo
  fallos de salida de carpeta (CVE-2021-40153 y CVE-2021-41072, arreglados en
  4.5.1; aquí está 4.6.1). Leer a memoria quita ese riesgo de raíz.
- **Montar con squashfuse**: deja un montaje vivo que hay que limpiar después.

**Qué se lee, con tope de tamaño:**

1. El único `*.desktop` de la raíz, hasta 64 KB. La spec pide uno solo [V].
2. El ícono: el `Icon=` del `.desktop` buscado primero en
   `usr/share/icons/hicolor/{scalable,512x512,256x256}/apps/` y después en la
   raíz (`.svg` o `.png`). Si no aparece, `.DirIcon`, que la spec hace
   obligatorio (PNG de 256) [V]. Los symlinks se siguen solo dentro de la
   imagen y hasta 8 saltos. Una ruta con `..` o absoluta se descarta. Tope de
   4 MB por ícono.

**El bit de ejecución.** Una AppImage bajada con el navegador llega sin `+x`
[I]. El servicio se lo pone (`chmod u+x`), como Gear Lever y appimaged [V].
Eso convierte «soltarla en la carpeta» en «autorizar que corra», y por eso
existe la confirmación del punto 4.

## 3. Dónde queda cada cosa, y mover o borrar

**El archivo no se toca.** No se mueve ni se renombra. Gear Lever lo mueve a
`~/AppImages` y lo renombra [V], pero aquí lo que José soltó en
`/Applications` se queda donde lo puso, como en la Mac.

**El lanzador.** Va en
`~/.local/share/applications/mint-macos-appimage-<md5>.desktop`. El `<md5>`
es el de la URI `file://` de la ruta, que es el mismo de la spec de miniaturas
y el que usan appimaged y libappimage [V]. Reglas del lanzador:

- `Exec=` apunta al abridor (punto 4) con la ruta de la AppImage;
- `Icon=` lleva la ruta absoluta del ícono extraído;
- `TryExec=` lleva la ruta de la AppImage, así GIO la esconde sola si el
  archivo desaparece antes de que corra el servicio;
- se guardan `X-AppImage-Path` y `X-AppImage-Version`;
- se copian `Name`, sus traducciones, `MimeType`, `Categories` y
  `StartupWMClass`;
- después se corre `update-desktop-database ~/.local/share/applications` para
  que aparezca en «Open With».

**El ícono.** Va en
`~/.local/share/icons/hicolor/<tamaño>/apps/mint-macos-appimage-<md5>.<ext>`.

**Quién la ve:**

- **Spotlyte, el menú y «Open With»** la toman de GIO, como cualquier lanzador
  de `~/.local/share/applications` [I] (Spotlyte es Ulauncher, que lista por
  GIO).
- **Fynder** muestra la AppImage misma con su ícono: Mint ya trae un
  miniaturizador para `application/vnd.appimage`, y Fynder tiene las
  miniaturas en `local-only` [V]. El nombre que se ve es el del archivo
  (`Obsidian-1.14.4.AppImage`), no «Obsidian.app». Ver la pregunta 2.
- **El generador de `/Applications`** tiene que **saltarse** los lanzadores
  `mint-macos-appimage-*`. Si no, saldría un «Obsidian.app» al lado de la
  AppImage: un duplicado.
- **El Launchpad** lee los lanzadores de `/Applications`
  (`nativo/launchpad/datos.vala`), así que hay que enseñarle a listar también
  las AppImages de la carpeta, con el nombre y el ícono de su lanzador. Es
  trabajo del dueño del Launchpad.
- **El Dock** reconoce la ventana por `StartupWMClass`. Si la AppImage no lo
  trae, puede salir un ícono genérico. Se mira caso por caso en la prueba [I].

**Mover y borrar.** Cada corrida vuelve a calcular qué AppImages hay y lo
compara con la lista de lo que ella creó, guardada en
`~/.local/share/mint-macos/appimages.json`. Igual que el generador, nunca
toca un archivo que no creó.

- **Botarla a la Trash**: su ruta ya no está, así que se borran el lanzador y
  el ícono. Si después se recupera de la Trash, vuelve a integrarse sola.
- **Moverla** de `/Applications` a `~/Applications`: la ruta cambia, así que
  cambia el md5. Sale de un lanzador y entra en otro en la misma corrida. Si
  se mueve fuera de las dos carpetas, se desintegra.
- **Reemplazarla por una versión nueva** con el mismo nombre: el md5 es el
  mismo y el lanzador se reescribe si cambió la fecha o el tamaño.

## 4. Riesgos

- **Corre sin aislamiento, como jmalena.** El runtime monta y ejecuta `AppRun`
  sin verificar nada [V] (https://docs.appimage.org/reference/architecture.html).
  Una AppImage es tan confiable como su origen, y no se puede leer su
  contenido como garantía. La mitigación propuesta es **un abridor al estilo
  Gatekeeper**: `mint-macos-abrir-appimage RUTA`. La primera vez que se abre
  una AppImage, enseña la ventana de Catalina «"Obsidian" is an app downloaded
  from the Internet. Are you sure you want to open it?», con el origen si se
  conoce. Si José dice que sí, guarda el sha256 aprobado y no vuelve a
  preguntar hasta que el archivo cambie. Así el `chmod +x` del servicio no
  equivale a correrla sin que nadie lo vea.
- **El origen.** Chrome y Firefox anotan la URL de descarga en el atributo
  `user.xdg.origin.url` [I], pero los archivos viejos de Downloads aquí no lo
  tienen. Si está, el abridor lo enseña. Si no, dice «origen desconocido».
- **La firma.** Existe (`.sha256_sig` en el ELF, firmada con GPG) [V], pero
  `--appimage-signature` solo la muestra; validarla necesita AppImageUpdate [V]
  (https://docs.appimage.org/packaging-guide/optional/signatures.html). Pocos
  proyectos firman, y varios publican la firma por fuera, como KeePassXC con
  `.sig` y `.DIGEST` [I]. **No se propone verificar firmas.** Se propone
  confiar en el origen y en la confirmación de la primera vez.
- **libfuse2.** Las AppImages con el runtime viejo necesitan libfuse2. En
  Ubuntu 24.04, y por tanto en Mint 22, el paquete se llama `libfuse2t64` [V]
  (https://docs.appimage.org/user-guide/troubleshooting/fuse.html). Aquí está
  instalado, pero **no está en la lista `EJECUCION` de `versiones.sh`**: hay
  que agregarlo para koralis02. El runtime estático nuevo (type2-runtime) ya no
  lo necesita [V].
- **AppArmor y las apps Electron.** En Ubuntu 24.04 las AppImages Electron
  fallan por la restricción de user namespaces (LP 2046844) [V]. **Aquí no
  aplica**: en esta máquina
  `kernel.apparmor_restrict_unprivileged_userns = 0` [V]. Falta comprobarlo en
  koralis02.
- **Nunca como root.** El servicio es de usuario y una AppImage nunca se lee ni
  se integra desde un servicio del sistema.

## 5. Cómo se prueba

En el marco de `pruebas/`, en el Xephyr, con su HOME y su bus:

- **Con una AppImage real.** Se baja una AppImage oficial con el sí de José, a
  `~/.cache/mint-macos/pruebas-appimage/` y fuera del repo, comprobando su
  sha256 contra el que publica el proyecto. Recomiendo **KeePassXC 2.7.12**:
  unos 49 MB, Qt, con firma y DIGEST publicados (github.com/keepassxreboot/
  keepassxc/releases) [V]. Una Electron (Obsidian, unos 139 MB) sirve después
  para el caso de AppArmor en koralis02.
- **Casos 50-55:**
  1. soltarla en `/Applications`: en menos de 10 s existe el lanzador, GIO
     la lista con su nombre, y el ícono extraído es un PNG o SVG válido;
  2. «Open With»: `gio mime` del tipo de su `MimeType` la ofrece;
  3. moverla a `~/Applications` y luego fuera: el lanzador cambia y después
     desaparece;
  4. botarla con `gio trash`: el lanzador y el ícono se van; restaurarla los
     trae de vuelta;
  5. **que nunca se ejecutó**: durante la integración, ningún proceso tiene la
     AppImage como ejecutable. Se mira en `/proc/*/exe` con la marca de la
     corrida, y además la AppImage de prueba está sin `+x` hasta que el
     servicio se lo pone;
  6. archivos que se rechazan sin romper nada: un ELF cualquiera, un `.AppImage`
     que es texto, una tipo 1 hecha a mano y un squashfs con `../` en un
     symlink.
- **El abridor**: la confirmación sale, Cancel no la abre, y Open la abre y
  no vuelve a preguntar.
- Antes de dar un caso por bueno se rompe a propósito y se mira que falle, como
  en el resto del marco.

## Decisiones (José, 17-10-2026)

1. **`~/Applications`**: se vigila solo si ya existe. El servicio no la crea.
2. **El nombre en Fynder**: el archivo no se toca y Fynder enseña el nombre de
   la app, «KeePassXC.app», como con los demás lanzadores. Es trabajo de Dev:
   que Fynder lea el `Name` del lanzador `mint-macos-appimage-<md5>` de esa ruta.
3. **La confirmación de la primera vez**: sí, como Gatekeeper.
4. **La AppImage de prueba**: KeePassXC 2.7.12, bajada el 17-10 a
   `~/.cache/mint-macos/pruebas-appimage/`. El sha256 coincide con el DIGEST
   oficial (`564fe8b7…13ae49`) y llegó sin `+x`, como se esperaba. Sin
   ejecutarla se comprobó que es tipo 2 (`AI\x02`), que el squashfs es gzip
   en el offset 193,728 (`hsqs`), y que la raíz trae
   `org.keepassxc.KeePassXC.desktop`, `keepassxc.svg` y `.DirIcon`.

## Las preguntas que se le hicieron

1. **¿Cuenta `~/Applications`?** En la Mac existe para las apps de un solo
   usuario. Propongo vigilarla solo si ya existe, sin crearla.
2. **¿Cómo se llama en Fynder?** El archivo se ve como
   `Obsidian-1.14.4.AppImage`. Hay tres salidas:
   - dejarlo así;
   - que el servicio lo renombre a `Obsidian.AppImage` (cambiar algo que José
     soltó);
   - que Fynder muestre el nombre del lanzador, como hace con los `.desktop`
     (trabajo de Dev).
3. **¿La confirmación de la primera vez?** La recomiendo, como Gatekeeper.
   Sin ella, soltar el archivo ya basta para que pueda correr.

## Fuentes

- AppImageSpec: https://github.com/AppImage/AppImageSpec/blob/master/draft.md
- Arquitectura y firmas: https://docs.appimage.org/reference/architecture.html,
  https://docs.appimage.org/packaging-guide/optional/signatures.html
- FUSE: https://docs.appimage.org/user-guide/troubleshooting/fuse.html,
  https://github.com/AppImage/type2-runtime
- Gear Lever: https://github.com/mijorus/gearlever (`src/providers/AppImageProvider.py`,
  `data/it.mijorus.gearlever.gschema.xml`)
- appimaged (go-appimage): https://github.com/probonopd/go-appimage
  (`src/appimaged/README.md`, `appimage.go`, `desktop.go`, `internal/helpers/elfsize.go`)
- libappimage: https://github.com/AppImageCommunity/libappimage (`include/appimage/appimage.h`)
- AppImageLauncher: https://github.com/TheAssassin/AppImageLauncher
- backhand: https://github.com/wcampbell0x2a/backhand
- DwarFS en AppImage: https://github.com/VHSgunzo/uruntime
- AppArmor y Electron: https://bugs.launchpad.net/bugs/2046844
- En esta máquina: `/usr/bin/xapp-appimage-thumbnailer` (xapp 1.2.9),
  `sysctl kernel.apparmor_restrict_unprivileged_userns`, `dpkg -l libfuse2t64`
