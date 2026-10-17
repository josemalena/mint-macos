# Menú global: el lado de las apps

La barra de arriba (`applets/globalmenu@macos`) pinta el menú de la ventana
activa, como en macOS. Esta carpeta hace que las apps lo publiquen.

```
./instalar.sh            # el registrador, como servicio de usuario
./instalar.sh --sesion   # + variables de la sesión y Firefox/Thunderbird
```

`--sesion` va solo cuando la barra pinte los dos caminos de abajo: al publicar,
las apps esconden su barra de menú, y sin la barra arriba se queda uno sin
menús. Pide cerrar sesión y entrar.

Cada corrida respalda en `~/.local/share/respaldos/menu-global-<fecha>/` y
deja ahí `volver.sh`. Para volver al estado de antes de todo, el `volver.sh`
del respaldo **más viejo**.

## Dos caminos

| Camino | Quién | Cómo lo encuentra la barra |
|---|---|---|
| DBusMenu (`com.canonical.dbusmenu`) | Qt, Chrome, Edge, Electron, Thunderbird, Firefox | `GetMenuForWindow(xid)` al registrador `com.canonical.AppMenu.Registrar` |
| GMenuModel (`org.gtk.Menus` + `org.gtk.Actions`) | GTK2 y GTK3 con `appmenu-gtk-module`, GtkApplication | Propiedades X11 de la ventana: `_GTK_UNIQUE_BUS_NAME`, `_GTK_MENUBAR_OBJECT_PATH` (acciones con prefijo `unity.`), `_GTK_APPLICATION_OBJECT_PATH` (`app.`), `_GTK_WINDOW_OBJECT_PATH` (`win.`) |

Las apps GTK **no** llaman al registrador; su menú no sale en `GetMenus`.

## El registrador

`registrador.py`, instalado en `~/.local/lib/menu-global/` y corriendo como
`appmenu-registrador.service` (systemd del usuario). Un `.service` de D-Bus en
`~/.local/share/dbus-1/services/` hace que la activación caiga en él y no en el
de Mint.

El de Mint (`/usr/libexec/vala-panel/appmenu-registrar`, paquete
`appmenu-registrar`) no sirve: se cierra solo a los ~10 s aunque se le pase
`-r`, y como la barra lo activa en cada cambio de foco, renace vacío. Las apps
registran su ventana una sola vez, al abrirla: un registrador que se reinicia
no sabe de nadie. Medido el 10-10-2026.

## Qué cubre (probado el 10-10-2026, cada app con un perfil o instancia de prueba)

| App | Publica | Qué hace falta |
|---|---|---|
| xed y las GTK3 de Mint | Sí, GMenuModel | `GTK_MODULES=…:appmenu-gtk-module`, `UBUNTU_MENUPROXY=1` |
| GTK2 | Igual que GTK3 (módulo gtk2 instalado) | Lo mismo |
| Qt5 (keditbookmarks, k3b, qsynth) | Sí, DBusMenu | `QT_QPA_PLATFORMTHEME=gnome`. Con `gtk3` **no** publica |
| Edge 155 (y Chrome, Electron) | Sí, DBusMenu | Nada: publica solo si el registrador está |
| Thunderbird 153 (Mint) | Sí, DBusMenu | `widget.gtk.global-menu.enabled` en `user.js` |
| Firefox 157 (Mint) | Sí, DBusMenu | Lo mismo |
| OBS Studio 32.2.2 (Flatpak, Qt 6.11) | Sí, DBusMenu | `./flatpak-qt.sh` (permiso para hablar con el registrador, abajo); **verificado por José el 14-10-2026** |
| VS Code 1.141 (Electron 43) | Sí, DBusMenu, solo con `"window.titleBarStyle": "native"` | Esa línea en `~/.config/Code/User/settings.json` (puesta el 17-10-2026 con el sí de José; vuelta atrás: borrarla). Pierde la barra de título propia (command center, botones de layout). Sin probar en pantalla todavía. Ver «VS Code» abajo |
| kitty, GTK4/libadwaita | No tienen menú | La barra pone el menú genérico |

## VS Code

El menú global sin parchear VS Code solo sale con la barra de título nativa. Es una decisión de VS Code,
no un faltante de Electron (leído en el código el 17-10-2026):

- **Electron** exporta el menú por DBusMenu y lo registra en `com.canonical.AppMenu.Registrar`. Lo hace en
  X11, con libdbusmenu-glib y al mapear la ventana. Si el registrador está, quita la barra de menú de
  dentro de la ventana. Está en `shell/browser/native_window_views.cc` (`SetMenu`) y
  `shell/browser/ui/views/global_menu_bar_x11.cc` (ruta `/com/canonical/menu/<XID>`).
- **VS Code** le da a Electron un menú nativo solo si la barra de título es la nativa.
  - En `src/vs/platform/window/common/window.ts`, `getTitleBarStyle()` devuelve `custom` por defecto
    («default to custom on all OS»).
  - En Linux, `hasNativeMenu()` da false con barra propia, aunque `window.menuStyle` sea `native`
    («Do not support native menu with custom title bar»).
  - Sin eso, `menubar.ts` hace `Menu.setApplicationMenu(null)` y no queda nada que exportar.

## Exclusiones

Apps GTK que no deben publicar, en la lista negra del módulo
(`gsettings org.appmenu.gtk-module blacklist`); `instalar.sh` las agrega sin
quitar las que trae el paquete (anjuta, freeciv, glade, gwyddion):

| App | Por qué |
|---|---|
| `libreoffice`, `soffice` | Tiene su propio camino de menú global; con el módulo encima duplica o pierde menús (fallo conocido de appmenu-gtk-module). Preventivo, sin probar aquí |
| `gimp`, `gimp-2.10` | GTK2 con menús que se rearman: el módulo los pierde. Preventivo, sin probar aquí |

Una app que se ve mal se agrega a `EXCLUIR` en `instalar.sh` y a esta tabla,
con el porqué.

## Apps Qt en Flatpak (OBS Studio)

El sandbox de Flatpak **oculta** `com.canonical.AppMenu.Registrar` y Qt solo exporta su
menú si lo ve: dentro de OBS, `NameHasOwner` da `false`; con el permiso de hablarle,
`true`. No hay que cambiar el platformtheme (el tema «gnome» ya exporta; «kde» ni siquiera
existe en el sandbox de OBS). `flatpak-qt.sh` da ese permiso con un override **de usuario**
(sin sudo):

```
./flatpak-qt.sh                    # OBS Studio y las apps con runtime org.kde.Platform
./flatpak-qt.sh ID [ID…]           # además, esas apps
./flatpak-qt.sh --lista            # a quién se lo daría, sin cambiar nada
./flatpak-qt.sh --deshacer [ID…]   # lo quita (de lo que puso el script)
```

Solo vale desde la **próxima vez que se abra** la app. Verificado con OBS Studio 32.2.2 por José el 14-10-2026: con el override, OBS publica su menú en la barra. Lo que se dio queda en
`~/.local/share/mint-macos/menu-global-flatpak.lista`.

