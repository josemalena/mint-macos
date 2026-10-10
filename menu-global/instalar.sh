#!/bin/bash
# El lado de las apps del menú global: que cada app publique su menú para que
# la barra (applets/globalmenu@macos) lo pinte arriba, como en macOS.
#
#   ./instalar.sh            el registrador, como servicio de usuario. Seguro:
#                            ninguna app esconde su barra por esto solo, salvo
#                            las que ya publican por DBusMenu (Edge, Chrome,
#                            Electron), que la barra ya lee.
#   ./instalar.sh --sesion   además, las variables de la sesión y la opción de
#                            Firefox y Thunderbird. Solo cuando la barra pinte
#                            los dos caminos (DBusMenu y GMenuModel): las apps
#                            esconden su barra al publicar, y sin barra arriba
#                            José se queda sin menús. Pide cerrar sesión.
#
# Cada corrida respalda primero en ~/.local/share/respaldos/menu-global-<fecha>/
# y deja ahí volver.sh, que deja todo como estaba.
#
# Lo que cubre y lo que no está en LEEME.md.
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
SESION=false
[ "${1:-}" = "--sesion" ] && SESION=true

LIB="$HOME/.local/lib/menu-global"
UNIDADES="$HOME/.config/systemd/user"
DBUS_SERVICIOS="$HOME/.local/share/dbus-1/services"
RESPALDO="$HOME/.local/share/respaldos/menu-global-$(date +%Y%m%d-%H%M%S)"

FF_PERFILES="$HOME/.config/mozilla/firefox"
TB_PERFILES="$HOME/.thunderbird"

# El perfil que de verdad abre cada uno: el Default de installs.ini.
perfil_en_uso() { # carpeta
  local ini="$1/installs.ini"
  [ -f "$ini" ] || return 0
  local p; p="$(grep -m1 '^Default=' "$ini" | cut -d= -f2-)"
  [ -n "$p" ] && [ -d "$1/$p" ] && echo "$1/$p" || true
}
FF_PERFIL="$(perfil_en_uso "$FF_PERFILES")"
TB_PERFIL="$(perfil_en_uso "$TB_PERFILES")"

# --- Respaldo -------------------------------------------------------------
mkdir -p "$RESPALDO"
respaldar() { # ruta nombre-en-el-respaldo
  if [ -e "$1" ]; then cp -a "$1" "$RESPALDO/$2"; else touch "$RESPALDO/$2.no-existia"; fi
}
respaldar "$HOME/.xsessionrc" xsessionrc
respaldar "$HOME/.config/environment.d/menu-global.conf" menu-global.conf
respaldar "$UNIDADES/appmenu-registrador.service" appmenu-registrador.service
respaldar "$DBUS_SERVICIOS/com.canonical.AppMenu.Registrar.service" dbus-registrar.service
[ -n "$FF_PERFIL" ] && respaldar "$FF_PERFIL/user.js" firefox-user.js
[ -n "$TB_PERFIL" ] && respaldar "$TB_PERFIL/user.js" thunderbird-user.js
gsettings get org.appmenu.gtk-module blacklist > "$RESPALDO/blacklist.txt" 2>/dev/null || true

cat > "$RESPALDO/volver.sh" <<EOF
#!/bin/bash
# Deja el menú global como estaba antes de $(date '+%d-%m-%Y %H:%M').
set -u
R="$RESPALDO"
reponer() { # nombre-en-el-respaldo ruta
  if [ -e "\$R/\$1.no-existia" ]; then rm -f "\$2"; elif [ -e "\$R/\$1" ]; then cp -a "\$R/\$1" "\$2"; fi
}
systemctl --user disable --now appmenu-registrador.service 2>/dev/null
reponer xsessionrc "$HOME/.xsessionrc"
reponer menu-global.conf "$HOME/.config/environment.d/menu-global.conf"
reponer appmenu-registrador.service "$UNIDADES/appmenu-registrador.service"
reponer dbus-registrar.service "$DBUS_SERVICIOS/com.canonical.AppMenu.Registrar.service"
$( [ -n "$FF_PERFIL" ] && echo "reponer firefox-user.js \"$FF_PERFIL/user.js\"" )
$( [ -n "$TB_PERFIL" ] && echo "reponer thunderbird-user.js \"$TB_PERFIL/user.js\"" )
[ -s "\$R/blacklist.txt" ] && gsettings set org.appmenu.gtk-module blacklist "\$(cat "\$R/blacklist.txt")"
systemctl --user daemon-reload
[ -f "$UNIDADES/appmenu-registrador.service" ] && systemctl --user enable --now appmenu-registrador.service
echo "Listo. Las variables de la sesión vuelven al cerrar sesión y entrar de nuevo;"
echo "Firefox y Thunderbird, al reiniciarlos."
EOF
chmod +x "$RESPALDO/volver.sh"

# --- El registrador -------------------------------------------------------
# El de Mint (appmenu-registrar) se cierra solo a los segundos y pierde los
# registros; este vive toda la sesión. La activación por D-Bus apunta aquí
# (los servicios de ~/.local/share/dbus-1 mandan sobre los de /usr/share).
mkdir -p "$LIB" "$UNIDADES" "$DBUS_SERVICIOS"
install -m 755 "$AQUI/registrador.py" "$LIB/registrador.py"
cat > "$UNIDADES/appmenu-registrador.service" <<EOF
[Unit]
Description=Registrador del menú global (com.canonical.AppMenu.Registrar)

[Service]
Type=dbus
BusName=com.canonical.AppMenu.Registrar
ExecStart=/usr/bin/python3 $LIB/registrador.py
Restart=on-failure

[Install]
WantedBy=default.target
EOF
cat > "$DBUS_SERVICIOS/com.canonical.AppMenu.Registrar.service" <<EOF
[D-BUS Service]
Name=com.canonical.AppMenu.Registrar
Exec=/usr/bin/python3 $LIB/registrador.py
SystemdService=appmenu-registrador.service
EOF
systemctl --user daemon-reload
systemctl --user enable appmenu-registrador.service >/dev/null 2>&1
# Si corre otro (el de Mint, activado por la barra), el nuestro le quita el
# nombre al arrancar; las apps vuelven a registrarse al ver el cambio.
systemctl --user restart appmenu-registrador.service
echo "Menú global: registrador corriendo ($(systemctl --user is-active appmenu-registrador.service))."

# --- Apps GTK que no deben publicar ---------------------------------------
# Ver LEEME.md, «Exclusiones». Se agregan a la lista del módulo sin quitar las
# que trae.
EXCLUIR=(libreoffice soffice gimp gimp-2.10)
actual="$(gsettings get org.appmenu.gtk-module blacklist 2>/dev/null || echo "@as []")"
nueva="$(python3 - "$actual" "${EXCLUIR[@]}" <<'PY'
import ast, sys
txt = sys.argv[1].replace("@as ", "")
lista = ast.literal_eval(txt) if txt.strip() else []
for n in sys.argv[2:]:
    if n not in lista:
        lista.append(n)
print(str(lista))
PY
)"
gsettings set org.appmenu.gtk-module blacklist "$nueva"

if ! $SESION; then
  echo "Sin --sesion: las variables y Firefox/Thunderbird quedan como estaban."
  echo "Respaldo y vuelta atrás: $RESPALDO/volver.sh"
  exit 0
fi

# --- Variables de la sesión -----------------------------------------------
# ~/.xsessionrc lo lee la sesión X de Mint (Xsession.d/40x11-common_xsessionrc)
# antes de arrancar Cinnamon: de ahí lo heredan las apps del menú y del dock.
# environment.d cubre lo que arranca systemd --user (activación por D-Bus).
#   GTK_MODULES           appmenu-gtk-module: GTK2 y GTK3 publican GMenuModel.
#   UBUNTU_MENUPROXY=1    el mismo módulo lo pide para esconder la barra.
#   QT_QPA_PLATFORMTHEME  gnome: Qt 5.15 publica por DBusMenu. Con gtk3 NO
#                         publica (probado con keditbookmarks el 10-10-2026).
MARCA_I="# >>> menú global (mint-macos/menu-global) >>>"
MARCA_F="# <<< menú global <<<"
touch "$HOME/.xsessionrc"
sed -i "/^$MARCA_I\$/,/^$MARCA_F\$/d" "$HOME/.xsessionrc"
cat >> "$HOME/.xsessionrc" <<EOF
$MARCA_I
case ":\${GTK_MODULES:-}:" in *:appmenu-gtk-module:*) ;; *) export GTK_MODULES="\${GTK_MODULES:+\$GTK_MODULES:}appmenu-gtk-module" ;; esac
export UBUNTU_MENUPROXY=1
export QT_QPA_PLATFORMTHEME=gnome
$MARCA_F
EOF
mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/menu-global.conf" <<'EOF'
# Menú global (mint-macos/menu-global/instalar.sh --sesion).
GTK_MODULES=${GTK_MODULES:+$GTK_MODULES:}appmenu-gtk-module
UBUNTU_MENUPROXY=1
QT_QPA_PLATFORMTHEME=gnome
EOF

# --- Firefox y Thunderbird ------------------------------------------------
# Los dos (builds de Mint, 157 y 153) traen el menú global nativo apagado.
poner_pref() { # perfil
  [ -n "$1" ] || return 0
  local f="$1/user.js" l='user_pref("widget.gtk.global-menu.enabled", true);'
  touch "$f"
  grep -qF "$l" "$f" || echo "$l" >> "$f"
}
poner_pref "$FF_PERFIL"
poner_pref "$TB_PERFIL"

echo "Menú global encendido para la sesión: hace falta cerrar sesión y entrar."
echo "Firefox y Thunderbird lo toman al reiniciarlos."
echo "Respaldo y vuelta atrás: $RESPALDO/volver.sh"
