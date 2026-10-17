# mint-macos en Wayland: qué se rompe

Estudio del 17-10-2026. Es solo el documento, sin código. Cada dato lleva su
fuente. **[inferencia]** marca lo que se deduce de las fuentes pero no se probó;
**[sin verificar]** marca lo que solo dice la prensa o un tercero.

## Resumen

Hoy mint-macos corre en X11, la sesión por defecto de Mint 22.3. Mint dice que
la próxima versión de Cinnamon soportará Wayland por completo, pero no que vaya
a ser la sesión por defecto. Si mañana se entrara en la sesión Wayland de
Cinnamon:

| Pieza | En Wayland | Por qué |
|---|---|---|
| **El Dock** (mint-macos-dock, de plank-reloaded) | **No arranca** | plank-reloaded se niega a correr en Wayland y no tiene plan de soportarlo |
| **Menú global**: Qt, Chrome/Edge/Electron/VS Code, Firefox/Thunderbird | **Se pierde** | lo publican por XID al registrador, o por el protocolo de KDE que Muffin no tiene |
| **Menú global**: apps GTK3 | **Posible, con trabajo** | Muffin guarda las propiedades GMenuModel que GTK le pasa por gtk-shell; el applet tendría que leerlas de la MetaWindow |
| **keyd**: ⌘ y ⌥ globales | **Sigue igual** | trabaja con evdev/uinput, debajo del compositor |
| **keyd**: excepciones por app (kitty, VS Code…) | **Se pierden** para las apps Wayland | keyd-application-mapper no sabe preguntarle a Muffin cuál ventana está al frente |
| xdotool, wmctrl, libwnck, bamf | **Solo ven ventanas de Xwayland** | son de X11 |
| Force Quit y «forzar la app del frente» | **Ciegos para apps Wayland** | se apoyan en wnck, wmctrl y xdotool |
| Capturas (⇧⌘3/4/5) | **Se rompen** | GDK X11, XIDs y `ffmpeg -f x11grab` |
| Emojis (⌃⌘Espacio) | **Se rompe** | `xdotool type` y `windowactivate` |
| Pantalla de inicio (slick-greeter-mac) | **Sigue igual** | el greeter corre en el X de LightDM aunque la sesión sea Wayland |
| Bloqueo de pantalla | **Cambia** | Cinnamon trae un salvapantallas propio; el nuestro (slick-greeter-mac como bloqueo) habría que revisarlo |
| Agente de polkit estilo Catalina | **Revisar** | usa `Gdk.X11` para el tiempo del servidor; como cliente Xwayland, el foco no está garantizado |
| Pruebas (pruebas/, armar.sh) | **Hay que rehacerlas** | Xephyr, Muffin anidado sobre X, xdotool, wmctrl e `import` son todo X11 |

En corto: **en Wayland no hay Dock, el menú global queda en las apps GTK3, y
todo lo que mira ventanas desde fuera (Force Quit, capturas, emojis, keyd por
app, las pruebas) hay que rehacerlo hablándole a Cinnamon/Muffin por D-Bus.**
keyd global y la pantalla de inicio no cambian.

## 1. Dónde está Cinnamon con Wayland

- **Enero de 2026:** Mint decía que el soporte de Wayland «so far has been
  "experimental"», y que cinnamon-screensaver «only works in X11».
  — Monthly News, January 2026 (11-02-2026), https://blog.linuxmint.com/?p=4991
- **Junio de 2026:** «Wayland support will no longer be considered
  "experimental"… In the next version of Cinnamon, both X11 and Wayland will be
  fully supported». Lista arreglos de colocación de ventanas, foco, HiDPI,
  pkexec como cliente Wayland, y un comando nuevo, `cinnamon-list-windows`. La
  versión sale «Christmas this year».
  — Monthly News, June 2026 (08-07-2026), https://blog.linuxmint.com/?p=5046
- **Wayland no será por eso la sesión por defecto:** «Supporting Wayland
  doesn't mean we'll start using it by default».
  — https://www.phoronix.com/news/Linux-Mint-New-Screensaver (11-02-2026)
- Que esa versión sea Cinnamon 6.8 en Mint 23 lo dice solo la prensa
  **[sin verificar]**: https://linuxiac.com/linux-mints-next-release-will-fully-support-wayland-in-cinnamon/
- **Xwayland:** Muffin lo arranca por defecto; tiene la opción `--no-x11` para
  no arrancarlo. — `src/core/main.c` en https://github.com/linuxmint/muffin
- **Rastreador de Wayland de Mint:** https://github.com/linuxmint/wayland. Los
  issues que nos tocan:
  - #239: atajos con Super solo;
  - #84 y #238: no hay portal ScreenCast;
  - #117: no hay `ext-session-lock`;
  - #25: no hay `xdg-decoration`;
  - #215: un applet de terceros roto en Wayland, y la respuesta fue que se le
    reporte al autor. **Los applets y extensiones son cosa de cada uno.**
- **Protocolos de Muffin master:**
  - **Trae:** xdg-shell, gtk-shell, xdg-foreign, xdg-activation, `xapp-shell`
    (de Mint) y, desde el 02-03-2026, `wlr-layer-shell`, que no está en la 6.6.3.
  - **No trae:** wlr-foreign-toplevel, wlr-screencopy, ext-session-lock,
    kde-appmenu ni xdg-decoration.
  - `virtual-keyboard` e `input-method` llegaron el 13-07-2026, pero Muffin
    solo se los anuncia al fcitx que él mismo lanza.
  - — `src/meson.build` y `src/wayland/meta-wayland.c`, https://github.com/linuxmint/muffin

## 2. El Dock

- README de plank-reloaded: «Wayland is not supported at this time». El
  código sale con `Wayland environments are not supported.` en
  `lib/Factories/AbstractMain.vala`. Depende de `gdk-x11-3.0`, `libbamf3`,
  `libwnck-3.0` y `x11`, y reserva su espacio con struts de X11.
  — https://github.com/zquestz/plank-reloaded
- El autor: «There is no ETA for Wayland support. This project relies heavily
  on X11 libraries that do not have a Wayland equivalent» (#70, 10-06-2025), y
  «For now this is X11 only» (#148, 17-02-2026).
  — https://github.com/zquestz/plank-reloaded/issues/70,
  https://github.com/zquestz/plank-reloaded/issues/148
- **Para nosotros:** nuestro fork (`PLANK_*` en `versiones.sh`) tiene la misma
  base. **[inferencia]** En Wayland habría que pasar a otro Dock. Una opción es
  un applet o un panel de Cinnamon con la cara del Dock: wlr-layer-shell ya
  está en Muffin master, pero no hay protocolo para listar las ventanas de
  otros clientes, así que la lista de apps abiertas tendría que salir de
  Cinnamon mismo.

## 3. El menú global

Hoy el menú sale por dos caminos (`menu-global/LEEME.md`):

1. **DBusMenu con XID:** el registrador recibe la ventana X11 de cada app.
2. **GMenuModel:** las propiedades X11 `_GTK_*` de cada ventana GTK.

En Wayland no hay XID, así que el primer camino desaparece. Quien quiera
publicar el menú lo hace por el protocolo de KDE, `org_kde_kwin_appmenu`, y en
la tabla de wayland.app ese protocolo **solo lo tiene KWin**: ni Muffin, ni
Mutter, ni Sway.
— https://wayland.app/protocols/kde-appmenu

Por toolkit:

- **Qt:** `QDBusMenuBar::registerMenuBar()` solo registra la ventana si la
  plataforma es `xcb`.
  — https://github.com/qt/qtbase/blob/dev/src/gui/platform/unix/dbusmenu/qdbusmenubar.cpp
- **Chromium (Chrome, Edge):** en Wayland soporta menú global solo si el
  compositor ofrece `org_kde_kwin_appmenu_manager`.
  — https://chromium.googlesource.com/chromium/src/+/refs/heads/main/ui/ozone/platform/wayland/ozone_platform_wayland.cc
- **Electron (VS Code):** `GlobalMenuBarX11` es solo de X11.
  — https://github.com/electron/electron/blob/main/shell/browser/ui/views/global_menu_bar_x11.h
  - **[inferencia]** En Cinnamon Wayland, Chrome, Edge y VS Code dejan el menú
    dentro de la ventana. Si corren por Xwayland, siguen publicando como hoy.
- **Firefox y Thunderbird:** en Wayland usan `org_kde_kwin_appmenu`, detrás de
  `widget.gtk.global-menu.wayland.enabled`.
  — https://github.com/mozilla-firefox/firefox/blob/main/widget/gtk/NativeMenuGtk.cpp
  - **[inferencia]** En Muffin no lo publican, porque el protocolo no está.
- **GTK3 con appmenu-gtk-module:**
  - En Wayland solo corre con el gsetting `run-on-wayland`.
  - Anuncia el menú con `gdk_wayland_window_set_dbus_properties_libgtk_only`,
    que va por gtk-shell.
  - Muffin sí lo recibe: `gtk_surface_set_dbus_properties` →
    `meta_window_set_gtk_dbus_properties` guarda `gtk-menubar-object-path` y
    los demás en la MetaWindow.
  - — https://gitlab.com/vala-panel-project/vala-panel-appmenu,
    `src/wayland/meta-wayland-gtk-shell.c` en https://github.com/linuxmint/muffin
  - **[inferencia]** El applet (`applets/globalmenu@macos`) podría leer esas
    propiedades de la MetaWindow en vez de las de X11, y las apps GTK3
    seguirían con su menú.
- **Sin verificar:** GTK4 y LibreOffice.

**Para nosotros:**
- El registrador (`rust/registrador`, `menu-global/registrador.py`) y el
  applet trabajan por XID: `get_xwindow()` en `applets/globalmenu@macos/applet.js`.
- En Wayland, el menú de Qt, Chromium/Electron y Firefox solo vuelve si
  Muffin implementa `org_kde_kwin_appmenu`. Eso sería un parche a Muffin, un
  fork más.
- La otra salida es forzar esas apps a Xwayland (`--ozone-platform=x11`,
  `QT_QPA_PLATFORM=xcb`, `GDK_BACKEND=x11`), que es lo mismo que ya se hace
  con Spotlyte en `paquete/instalar-aqui.sh`.

## 4. keyd

- keyd trabaja con «kernel level input primitives (evdev, uinput)» y la
  configuración es «System wide (works in a VT)». **[inferencia]** No depende
  del compositor: ⌘ y ⌥ siguen igual.
  — https://github.com/rvaiya/keyd
- El mapeo por aplicación es «experimental» y soporta «X, Sway and Gnome».
  El script de hoy prueba, en orden, KDE, wlroots (foreign-toplevel), COSMIC,
  GNOME (con una extensión) y X. Cinnamon Wayland no está.
  — https://github.com/rvaiya/keyd/blob/master/docs/keyd-application-mapper.scdoc,
  https://github.com/rvaiya/keyd/blob/master/scripts/keyd-application-mapper
- **Para nosotros:**
  - `keyd/app.conf` deja de aplicar a las apps Wayland nativas. Por ejemplo,
    kitty recibiría ⌘ traducido y se romperían sus atajos.
  - **[inferencia]** Con `DISPLAY` puesto por Xwayland, el mapper caería en su
    modo X y solo vería las apps Xwayland.
  - Arreglo posible: un monitor para Cinnamon en el mapper que pregunte la
    ventana del frente por D-Bus (abajo).

## 5. Mirar y mover ventanas: xdotool, wmctrl, libwnck, bamf

- **xdotool:** «If you are using Wayland… this software will not work
  correctly». Recomienda ydotool o dotool.
  — https://github.com/jordansissel/xdotool
- **wmctrl:** es para un «EWMH/NetWM compatible X Window Manager».
  — https://manpages.ubuntu.com/manpages/noble/en/man1/wmctrl.1.html
- **libwnck:** «designed to work in X11 only» (`libwnck/util.c`).
  — https://gitlab.gnome.org/GNOME/libwnck
  - bamf depende de libwnck y de libx11. **[inferencia]** Ninguno de los dos ve
    ventanas Wayland nativas.
- **Lo que sí sirve en Cinnamon Wayland:**
  - `org.Cinnamon.Eval` (`js/ui/cinnamonDBus.js`), que en master no tiene la
    guarda que GNOME le puso a `Shell.Eval`.
  - `org.cinnamon.Muffin.Debug.ListWindows` y `/usr/bin/cinnamon-list-windows`.
  - — https://github.com/linuxmint/cinnamon/blob/master/js/ui/cinnamonDBus.js,
    `src/core/meta-window-debug-dbus.c` en https://github.com/linuxmint/muffin
- **Teclas:**
  - ydotool y dotool usan uinput y no dependen del compositor
    (https://github.com/ReimuNotMoe/ydotool, https://git.sr.ht/~geb/dotool).
  - wtype necesita `virtual-keyboard`, que Muffin no le anuncia
    **[inferencia]** (https://github.com/atx/wtype).

**Lo nuestro que usa esto:**

| Archivo | Qué usa |
|---|---|
| `nativo/forcequit/` (apps, frente, ventana) | libwnck |
| `nativo/ventanas/` | libwnck (meson.build) |
| `applets/applemenu@macos/forzar-app-del-frente.py` | xdotool, xprop, `_NET_WM_WINDOW_TYPE` |
| `applets/applemenu@macos/applemenu.py`, `forcekill.py` | wmctrl |
| `capturas/emojis.py` | `xdotool getactivewindow`, `windowactivate`, `type` |
| `nativo/polkit/dialogo.vala` | `Gdk.X11.get_server_time` |

**[inferencia]** Lo que hoy pregunta a X11 por la ventana del frente o por la
lista de ventanas pasaría a preguntarle a Cinnamon por D-Bus. Lo que teclea
pasaría a dotool o ydotool, que piden acceso a `/dev/uinput`.

## 6. Capturas

- **El portal:** la vía de Wayland es el portal Screenshot.
  `xdg-desktop-portal-xapp` lo trae para Cinnamon (lanza `cinnamon-screenshot`),
  pero **no trae ScreenCast**, así que no hay grabación de pantalla por portal.
  — https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Screenshot.html,
  `data/xapp.portal` y `src/screenshot.c` en https://github.com/linuxmint/xdg-desktop-portal-xapp,
  y los issues #84 y #238 de https://github.com/linuxmint/wayland
- **Muffin** tiene su propio screencast por D-Bus
  (`org.cinnamon.Muffin.ScreenCast`), pero ningún portal lo usa.
- **Las herramientas de X11** (import, scrot, maim) dan imágenes negras o
  fallan en Wayland: https://bugs.freedesktop.org/show_bug.cgi?id=98672
  (contexto GNOME; en Cinnamon **[sin verificar]**). grim necesita
  wlr-screencopy, que Muffin no tiene **[inferencia]**.
- **Lo nuestro:**
  - `nativo/captura/` toma la ventana con `Gdk.X11.Window.foreign_for_display`
    y su XID (`barra.vala`, `capas.vala`) y graba con `ffmpeg -f x11grab`.
  - `capturas/captura.sh` usa herramientas de X11.
  - Todo eso pasaría a `cinnamon-screenshot` o al portal. La grabación (⇧⌘5)
    queda sin camino hasta que Mint publique ScreenCast.

## 7. Pantalla de inicio, bloqueo y polkit

- **slick-greeter** usa Gdk.X11 y Xlib dentro del X de LightDM, y lanza
  sesiones de `/usr/share/wayland-sessions/`.
  — https://github.com/linuxmint/slick-greeter
  - **[inferencia]** slick-greeter-mac sigue igual: el greeter es X11 aunque se
    entre a una sesión Wayland.
- **Bloqueo:** cinnamon-screensaver solo funciona en X11 (blog de enero), y
  Cinnamon agregó un salvapantallas nativo el 24-02-2026 (commit 3eca4387,
  `js/ui/screensaver/`).
  - **[inferencia]** El bloqueo con la cara de Catalina (`login/bloqueo.sh`,
    `mint-macos-bloquear`) habría que rehacerlo sobre ese salvapantallas, o
    revisar cómo se lanza en Wayland.
- **polkit:** hay un agente por sesión (https://www.freedesktop.org/software/polkit/docs/latest/polkit.8.html),
  y Cinnamon registra el suyo (`js/ui/polkitAuthenticationAgent.js`).
  - **[inferencia]** El choque con nuestro agente estilo Catalina es el mismo
    que en X11.
  - Lo que cambia es `Gdk.X11.get_server_time` en `nativo/polkit/dialogo.vala`:
    corriendo como Xwayland funciona, pero el foco del diálogo sobre una app
    Wayland no está garantizado.

## 8. Las pruebas

- **Muffin:** tiene `--nested` (anidado sobre X11), `--wayland`,
  `--display-server` y `--no-x11`, pero **no `--headless`** (`src/core/main.c`).
- **Mutter:** tiene `--headless --virtual-monitor` desde GNOME 40, y en GNOME
  49 `--nested` pasó a `--devkit`.
  — https://www.phoronix.com/news/GNOME-40-Headless-Virtual,
  https://discourse.gnome.org/t/gnome-49-nested-sessions-no-longer-possible/30987
- **Weston:** tiene backend headless «useful for test suite».
  — https://wayland.pages.freedesktop.org/weston/toc/running-weston.html
- **[inferencia]** Para probar mint-macos en Wayland, el camino sería
  `muffin --nested --wayland` dentro del Xephyr de hoy. Las ayudas de
  `pruebas/lib.sh` cambiarían así:
  - `esperar_ventana` y `cerrar_ventana`: por `cinnamon-list-windows` o D-Bus,
    no por xdotool o wmctrl;
  - `captura`: por `cinnamon-screenshot`, no por `import`;
  - `esperar_texto` (AT-SPI): sigue igual, porque no depende de X11.

## Si un día se pasa a Wayland

Orden posible, de lo que más se nota a lo que menos. **[inferencia]**, para
decidir cuando llegue:

1. **El Dock:** es lo único sin salida dentro del mismo programa. Hay que
   escoger un reemplazo antes de cambiar de sesión.
2. **El menú global:** en las apps GTK3 se arregla en el applet. Para Qt,
   Chromium, Electron y Firefox, o Muffin gana `org_kde_kwin_appmenu` (un fork
   más) o esas apps se fuerzan a Xwayland.
3. **Las ventanas:** Force Quit, «forzar la app del frente», emojis y keyd por
   app, todo con una sola pieza que le pregunte a Cinnamon por D-Bus.
4. **Capturas:** por cinnamon-screenshot o el portal. La grabación espera a que
   haya ScreenCast.
5. **Las pruebas:** Muffin anidado en modo Wayland.

Mientras Mint no haga de Wayland la sesión por defecto, nada de esto apura:
mint-macos sigue en X11.
