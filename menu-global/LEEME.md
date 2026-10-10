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
| VS Code | Solo con `"window.titleBarStyle": "native"` | Pendiente del sí de José: pierde la barra de título propia |
| kitty, GTK4/libadwaita | No tienen menú | La barra pone el menú genérico |

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
