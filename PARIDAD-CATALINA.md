# Paridad con macOS Catalina: el inventario

- **Fecha:** 10-11-2026. **Commit medido:** `87800f4` (mint-macos), con Fynder `40be97d2` y Muelle `e7c858a26`.
- **Pregunta de José:** «¿Qué porcentaje de parecido con Catalina hemos alcanzado?». No había ninguna medición general; esta es
  la primera.

## Resultado

| Medida | Valor |
|---|---:|
| **Cobertura ponderada** (por uso diario) | **76.6 %** |
| Sin ponderar (todas las piezas pesan igual) | 70.1 % (75 de 107 puntos) |
| Ponderada, sin lo que Linux no puede hoy (Siri, Screen Time, Sidecar, Family Sharing: ocultos por las adaptaciones aprobadas, `perfiles/adaptaciones.json`) | 78.9 % |

## Método

1. Se enumeran las piezas de Catalina que ve quien viene de la Mac, por grupos.
2. Cada pieza tiene un estado:
   - **HECHA** (= 1): se usa como en la Mac;
   - **PARCIAL** (= 0.5): existe, pero le falta algo a la vista: controles en gris, la app de Mint o una web en vez de la de Apple, o sin probar en una máquina real;
   - **FALTA** (= 0): no hay nada.
3. **La evidencia sale del repo:** el código, los LEEME, los casos de `pruebas/casos` y el git log. Lo que no tiene evidencia no cuenta como hecho, y se dice.
4. **El cálculo:** el puntaje de cada grupo es el promedio de sus piezas. El total es la suma de los grupos por su peso.
5. Esto mide **cobertura**: que la pieza esté y se use como en la Mac. No mide el píxel. La precisión de menús, textos y medidas la mide después el auditor de NIB (al final).

## Los pesos (cámbialos aquí si no te cuadran)

| Grupo | Peso | Por qué |
|---|---:|---|
| A. Escritorio y ventanas | 15 | Se usa todo el tiempo |
| B. Barra de menú | 12 | Siempre a la vista |
| C. Dock | 10 | Siempre a la vista |
| D. Finder | 18 | La app más usada |
| E. Launchpad, Spotlight, Notification Center y herramientas | 10 | Uso diario, pero puntual |
| F. System Preferences | 15 | Muchos paneles; cada uno se abre poco |
| G. Apps de Catalina | 8 | Cada una es de un solo uso |
| H. Arranque, inicio de sesión y bloqueo | 5 | Una vez por sesión |
| I. Teclado y trackpad | 7 | Todo el tiempo, pero ya hereda mucho |
| **Total** | **100** | |

## Por grupo

| Grupo | Piezas | Hechas | Parciales | Faltan | Cobertura | Aporta (de su peso) |
|---|---:|---:|---:|---:|---:|---:|
| A. Escritorio y ventanas | 10 | 5 | 5 | 0 | 75.0 % | 11.3 / 15 |
| B. Barra de menú | 11 | 8 | 2 | 1 | 81.8 % | 9.8 / 12 |
| C. Dock | 7 | 7 | 0 | 0 | 100 % | 10.0 / 10 |
| D. Finder | 12 | 7 | 5 | 0 | 79.2 % | 14.3 / 18 |
| E. Launchpad, Spotlight, Notification Center y herramientas | 6 | 5 | 1 | 0 | 91.7 % | 9.2 / 10 |
| F. System Preferences | 32 | 11 | 17 | 4 | 60.9 % | 9.1 / 15 |
| G. Apps de Catalina | 18 | 2 | 14 | 2 | 50.0 % | 4.0 / 8 |
| H. Arranque, inicio de sesión y bloqueo | 6 | 2 | 4 | 0 | 66.7 % | 3.3 / 5 |
| I. Teclado y trackpad | 5 | 3 | 2 | 0 | 80.0 % | 5.6 / 7 |
| **Total** | **107** | **50** | **50** | **7** | | **76.6 / 100** |

## El detalle

### A. Escritorio y ventanas (15)

| Pieza | Estado | Evidencia | Lo que falta |
|---|---|---|---|
| Semáforos (cerrar, minimizar, zoom; hover de los tres) | HECHA | `nativo/gtk-semaforos`, `tema/muffin/0001`, caso 109 | — |
| Sombras de las ventanas | HECHA | `extensions/sombras@macos`, casos 116 y 117 | — |
| Pantalla completa (botón verde a su propio Space) | PARCIAL | Sin evidencia de un Space de pantalla completa | El verde maximiza; no hay Space aparte |
| Mission Control | PARCIAL | `extensions/misioncontrol@macos` (⌃↑), caso 112 | Usa el expo de Cinnamon; falta la franja de Spaces de Catalina |
| Spaces | PARCIAL | Escritorios de Cinnamon con ⌃← ⌃→ (`misioncontrol@macos`) | Reordenarlos y los Spaces de pantalla completa |
| App Exposé (⌃↓) | PARCIAL | `misioncontrol@macos` | El aspecto es el de Cinnamon |
| Minimizar con el genio | HECHA | `extensions/magiclamp.sh` y `parches/`, caso 111 | — |
| ⌘Tab | HECHA | `extensions/cmdtab@macos`, casos 39 y 135 | — |
| Hojas (sheets) | PARCIAL | `tema/muffin/0002` (caso 136, Xvfb) y las hojas de Fynder | El cerrar de la madre apagado y la animación de ±32 pt; el .deb sin instalar en todas las máquinas |
| La barra aparece con un fundido al entrar | HECHA | `extensions/entrada@macos` | — |

### B. Barra de menú (12)

| Pieza | Estado | Evidencia | Lo que falta |
|---|---|---|---|
| Menú Apple (About, Force Quit, sesión) | HECHA | `applets/applemenu@macos`, casos 35 y 42 | — |
| Menú de la app y menú global | HECHA | `applets/appmenu@macos`, `globalmenu@macos` y `menu-global/` (GTK, DBusMenu, Qt, Electron), casos 41, 46, 49, 55, 56, 58 y 72 | — |
| Wi-Fi | HECHA | `applets/red@macos` | — |
| Bluetooth | HECHA | `applets/bluetooth@macos` | — |
| Volumen | HECHA | `applets/sonido@macos` | — |
| Batería | PARCIAL | `applets/estado-barra.sh` no la cambia: queda el applet de Cinnamon | Un battery@macos |
| Reloj | HECHA | `applets/reloj@macos` | — |
| Spotlight (la lupa) | HECHA | `applets/buscar@macos` | — |
| Siri | FALTA | Oculta por adaptación aprobada (`perfiles/adaptaciones.json`) | No hay Siri en Linux |
| Notification Center (el ícono) | HECHA | `applets/notificaciones@macos` | — |
| Usuario (cambio rápido de usuario) | PARCIAL | `applets/usuario@macos` | Cambiar de usuario está pendiente (`nativo/bloqueo/LEEME.md`) |

### C. Dock (10)

| Pieza | Estado | Evidencia | Lo que falta |
|---|---|---|---|
| La lupa, la posición y el ocultarse | HECHA | Muelle (`repos/plank-reloaded`), casos 110, 119 y 123 | — |
| El rebote al abrir y al avisar | HECHA | Muelle (`c45620f9e`, `852396173`), casos 69 y 134 | — |
| Indicadores y apps recientes | HECHA | Muelle (`12d51dd5c`) | — |
| Pilas (Stacks: abanico y cuadrícula) | HECHA | Muelle (docklet-stacks), caso 131 | — |
| Menú del Dock (Options, Keep in Dock, Show in Finder) | HECHA | Muelle (X-Muelle-Actions, `03718def3`) | — |
| La papelera | HECHA | Muelle, caso 20 | — |
| Minimizar al ícono de la app | HECHA | Magic Lamp con su parche, Dock en System Preferences | — |

### D. Finder (18)

| Pieza | Estado | Evidencia | Lo que falta |
|---|---|---|---|
| Ventana, barra de herramientas y vistas (íconos, lista, columnas, Gallery) | HECHA | Fynder `LEEME.md`, casos 75 y 78 | El «More…» de la Gallery |
| Barra lateral (Favorites, Locations) | HECHA | Fynder (163 commits de lateral) | — |
| Etiquetas | HECHA | Casos 74, 105 y 106 | — |
| Quick Look | PARCIAL | Fynder, ⌘Y y Espacio (`80d6e473`) | Lo muestra nemo-preview, no la ventana de Catalina |
| Get Info | HECHA | Caso 71 | — |
| Búsqueda | HECHA | Caso 77 | — |
| Smart Folders | PARCIAL | Fynder `a4e9cc19` | El LEEME de Fynder la da sin captura de la hoja |
| Open/Save del sistema | PARCIAL | Fynder (Open/Save, `09985ba8`…), caso 80 | Va en el paquete desde `87800f4`; sin probar instalado |
| iCloud Drive | PARCIAL | `icloud/` (rclone) y el progreso en el lateral | Se cae cuando Apple vence la sesión (10-11: `INCORRECT_PCS_KEY`) |
| Menús y atajos del Finder | PARCIAL | Fynder, casos 72 y 79 | En View hay ítems en gris (Use Groups, Clean Up By, Show All Tabs) |
| El escritorio (íconos, fynder-desktop) | HECHA | Fynder | — |
| Preferences y View Options | HECHA | Fynder `LEEME.md` | — |

### E. Launchpad, Spotlight, Notification Center y herramientas (10)

| Pieza | Estado | Evidencia | Lo que falta |
|---|---|---|---|
| Launchpad | PARCIAL | `launchpad/` y `nativo/launchpad`, casos 37, 60, 114, 138 y 140 | El modo de edición (íconos que tiemblan, borrar, crear carpetas) |
| Spotlight (la ventana) | HECHA | Spotlyte (`a364b3ea`: dos paneles, vista previa, índices) | — |
| Notification Center y Today | HECHA | `applets/notificaciones@macos` y `nativo/hoy` (fecha, clima, calendario), casos 61 y 113 | — |
| Force Quit | HECHA | `nativo/forcequit`, casos 30, 38, 101, 107, 129 y 132 | — |
| Capturas (⇧⌘3, ⇧⌘4, ⇧⌘5) | HECHA | `capturas/` y `nativo/captura`, casos 31, 32, 40 y 130 | En :0 no se probaron Mail ni Preview como destino |
| Emojis (⌃⌘Space) | HECHA | `nativo/emojis`, caso 44 | — |

### F. System Preferences (15)

| Pieza | Estado | Evidencia (`nativo/preferencias/paneles/`) | Lo que falta |
|---|---|---|---|
| La ventana: cuadrícula, búsqueda, Show All | HECHA | `ventana.vala`, `catalogo.vala`, caso 34 | — |
| General | HECHA | `general.vala`, casos 65, 67 y 82 | Handoff, oculto por adaptación |
| Desktop & Screen Saver | PARCIAL | `escritorio.vala` | Los protectores de Apple, en gris |
| Dock | HECHA | `dock.vala` | «Prefer tabs», en gris |
| Mission Control | PARCIAL | `misioncontrol.vala` | Rearrange Spaces y Group by app (Cinnamon no los tiene) |
| Siri | FALTA | Oculto (`perfiles/adaptaciones.json`) | No hay Siri |
| Spotlight | PARCIAL | `spotlyte.vala` | Las categorías y Privacy |
| Language & Region | PARCIAL | `idioma.vala` | Todo en gris (cambiarlo pide root); Advanced… sin hacer |
| Notifications | PARCIAL | `avisos.vala` | Dibujado, todo en gris (Cinnamon no filtra por app) |
| Internet Accounts | PARCIAL | `settings/paneles.py` (gnome-online-accounts-gtk) | Es la ventana de GNOME |
| Users & Groups | PARCIAL | `usuarios.vala` | Cambiar la foto (pendiente del 09-11) |
| Accessibility | PARCIAL | `accesibilidad.vala` | Lo que Cinnamon no tiene, en gris |
| Screen Time | FALTA | Oculto por adaptación (las diez pantallas, en gris, en `screentime.vala`) | No hay uso que contar |
| Extensions | PARCIAL | `settings/paneles.py` (los módulos de Cinnamon) | Es la interfaz de Cinnamon |
| Security & Privacy | PARCIAL | `seguridad.vala` | FileVault y Firewall solo informan; Privacy, en gris |
| Software Update | HECHA | `actualizaciones.vala`, caso 48 | — |
| Network | HECHA | `red.vala`, `settings/red_avanzado.py` | WINS, 802.1X y Proxies, en gris |
| Bluetooth | HECHA | `bluetooth.vala` | — |
| Sound | HECHA | `sonido.vala`, caso 122 | — |
| Printers & Scanners | PARCIAL | `impresoras.vala` (CUPS) | Los escáneres |
| Keyboard | PARCIAL | `teclado.vala`, Modifier Keys, caso 63 | Shortcuts casi todo en gris; Text y Dictation, en gris |
| Trackpad | PARCIAL | `raton.vala` | Sin touchpad, «No trackpad found»; con touchpad, el módulo de Cinnamon |
| Mouse | HECHA | `raton.vala` | Scrolling speed, en gris |
| Displays | HECHA | `pantallas.vala` (Display, Color, Night Shift) | — |
| Sidecar | FALTA | Oculto por adaptación | No hay iPad como pantalla |
| Energy Saver | PARCIAL | `energia.vala` | Solo dos controles reales |
| Date & Time | HECHA | `fecha.vala` | — |
| Sharing | PARCIAL | `compartir.vala` | Solo Remote Login, File y Printer Sharing son reales |
| Time Machine | PARCIAL | `respaldo.vala` (sobre Timeshift) | Enseña el estado; no es la Time Machine de Catalina |
| Startup Disk | HECHA | `arranque.vala`, `settings/startup-disk` | Target Disk Mode |
| Apple ID | PARCIAL | `nativo/preferencias/appleid.vala`, `settings/apple_id.py`, caso 68 | Solo iCloud Drive, Mail y Calendar; nada de Photos, Keychain ni Find My |
| Family Sharing | FALTA | Oculto por adaptación | — |

### G. Apps de Catalina (8)

| App | Estado | Evidencia | Lo que falta |
|---|---|---|---|
| App Store | HECHA | `nativo/tienda` y `rust/tienda`, casos 47 y 59 | — |
| Activity Monitor | HECHA | `nativo/actividad` y `rust/monitor` (CPU, Memory, Energy, Disk, Network), caso 57 | — |
| Calendar | PARCIAL | La web de iCloud (`icloud/apps-web.sh`), Thunderbird y el widget de Today | La app de Catalina |
| Disk Utility | PARCIAL | Discos de Mint, en `/Applications/Utilities` (`aplicaciones/`) | El aspecto de la Mac |
| System Information | PARCIAL | About This Mac ▸ System Report… abre System Reports de Mint (`nativo/acerca`) | El informe de la Mac |
| Terminal | PARCIAL | kitty con `kitty/macos-keys.conf` | El aspecto de Terminal |
| Preview | PARCIAL | Los visores de Mint | — |
| TextEdit | PARCIAL | xed, con menú global (casos 46 y 56) | — |
| Calculator | PARCIAL | La calculadora de Mint | — |
| Font Book | FALTA | Sin evidencia en el repo | — |
| Console | FALTA | Sin evidencia en el repo | — |
| Safari | PARCIAL | Edge, Chrome o Firefox (`settings/navegadores`) | No hay Safari |
| Mail | PARCIAL | Thunderbird configurado desde Apple ID y la web de iCloud | — |
| Contacts | PARCIAL | La web de iCloud (`icloud/apps-web.sh`) | — |
| Notes | PARCIAL | La web de iCloud | — |
| Reminders | PARCIAL | La web de iCloud | — |
| Photos | PARCIAL | La web de iCloud | — |
| Music | PARCIAL | La web de Apple Music | — |

### H. Arranque, inicio de sesión y bloqueo (5)

| Pieza | Estado | Evidencia | Lo que falta |
|---|---|---|---|
| La manzana y la barra al arrancar | HECHA | `tema/arranque/instalar.sh`, `catalina.script` | — |
| Arrancar sin texto | PARCIAL | `tema/arranque/silencio.sh` | Sin probar en la MacBook |
| Al apagar, el fondo del usuario | PARCIAL | `tema/arranque/fondo-apagado.sh` | Sin probar en la MacBook |
| La pantalla de inicio | HECHA | `login/`, mint-macos-greeter | — |
| El bloqueo | PARCIAL | `nativo/bloqueo` | Bloquear al suspender y cambiar de usuario (`nativo/bloqueo/LEEME.md`) |
| El disco en el Startup Manager (⌥ al encender) | PARCIAL | `install-sapos/icono-disco.sh` | El ícono sale; el nombre (`.disk_label`) no, en la MacBook5,1 |

El sonido de arranque no se cuenta: lo da el firmware de la Mac, no el sistema.

### I. Teclado y trackpad (7)

| Pieza | Estado | Evidencia | Lo que falta |
|---|---|---|---|
| ⌘, ⌥ y ⌃ como en la Mac | HECHA | `keyd/default.conf`, Modifier Keys | — |
| Atajos del sistema (⇧⌘3/4/5, ⌥⌘⎋, ⌘Space, ⌃⌘Space, Mission Control) | HECHA | `cinnamon/keybindings.dconf` | — |
| Atajos por app (⌘Q, ⌘W…) | HECHA | `keyd/app.conf`, `nativo/menu`, casos 62 y 63 | — |
| Acentos con ⌥ en teclado inglés | PARCIAL | `install-sapos/macbook/acentos-option.sh` | En la MacBook ⌥e no funcionó; sin diagnóstico |
| Gestos del trackpad | PARCIAL | Sin evidencia en el repo: los de Cinnamon, tal cual | Llevarlos a los de la Mac |

## Las brechas más grandes (por puntos perdidos)

1. **System Preferences:** −5.9 puntos.
   - Cuatro paneles ocultos: Siri, Screen Time, Sidecar y Family Sharing.
   - 17 parciales, sobre todo controles en gris: Notifications, Keyboard ▸ Shortcuts, Language & Region, Energy Saver y Sharing.
2. **Apps de Catalina:** −4.0. Casi todas son la app de Mint o la web de iCloud, y no hay Font Book ni Console.
3. **Escritorio y ventanas:** −3.75.
   - Mission Control, Spaces y App Exposé tienen el aspecto de Cinnamon.
   - No hay pantalla completa en su propio Space.
   - Las hojas están a medias.
4. **Finder:** −3.75.
   - Quick Look es el de nemo-preview.
   - Smart Folders no tiene captura.
   - Open/Save está sin probar instalado.
   - iCloud se cae con la sesión de Apple.
   - View tiene ítems en gris.
5. **Barra de menú:** −2.2. Falta Siri, la batería es la de Cinnamon y el cambio de usuario está pendiente.

## Lo que el auditor de NIB va a medir después

`herramientas/visor-nib/auditar/` (con `menus.py`, `texto.py` y `geometria.py`) compara contra los NIB extraídos de Catalina. Mide
qué falta, qué texto se parece pero no es igual, qué atajo es distinto o no está, qué cambió de orden y qué sobra. Se corre cuando la
Mac mini esté fresca, con `nice -n 19`, sobre:

- **los menús de Fynder contra los del Finder:** File, Edit, View, Go, Window y el menú contextual;
- **los paneles de System Preferences** que aquí salen HECHA o PARCIAL (General, Dock, Keyboard, Sound, Displays, Network,
  Date & Time…), en textos y geometría;
- **el menú Apple** y los menús de las apps propias (Activity Monitor, App Store);
- **los diálogos** (Force Quit, About This Mac, los de sesión).

Con eso, «HECHA» pasa de «está y se usa como en la Mac» a un porcentaje de ítems y textos iguales.
