# shellcheck shell=bash
# El manifiesto: la versión exacta de todo lo de afuera que usa mint-macos.
# Los scripts lo cargan con «source» (construir.sh, login/instalar.sh,
# requisitos.sh, apfs/instalar-fsapfs.sh, paquete.sh); ninguno lleva un hash
# o una versión propia. Para mover un fork se cambia su _HASH aquí y se corre
#
#   ./verificar-versiones.sh --escribir
#
# que comprueba el manifiesto contra los repos y reescribe VERSIONES.md (la
# lista de parches de cada fork sobre su upstream). Sin --escribir, solo
# comprueba, y falla si VERSIONES.md quedó viejo.
#
# Cada fork:
#   _REPO       de dónde se clona (vacío: no tiene repo publicado)
#   _HASH       el commit que se compila e instala
#   _LOCAL      cómo se llama su carpeta junto a mint-macos (../<nombre>) y en
#               ~/.cache/mint-macos/src/<nombre>: ahí se busca sin red
#   _UPSTREAM   el proyecto del que sale, y _RAMA la rama de la que se apartó
#   _BASE       el último commit de upstream que tiene (git merge-base)

FORKS=(FYNDER PLANK GREETER SPOTLYTE)

# Fynder: el administrador de archivos con la cara del Finder
FYNDER_NOMBRE=Fynder
FYNDER_REPO=https://github.com/josemalena/fynder.git
FYNDER_HASH=7a3a01194002129197f3776ad94a496c00067a90
FYNDER_LOCAL=fynder
FYNDER_UPSTREAM=https://github.com/linuxmint/nemo.git
FYNDER_RAMA=master
FYNDER_BASE=66eabf459bc86d03c24797274d0e3f60b9b7a7d8

# mint-macos-dock: el Dock de Catalina (se instala como plank)
PLANK_NOMBRE=mint-macos-dock
PLANK_REPO=https://github.com/josemalena/mint-macos-dock.git
PLANK_HASH=68d01f049de8653aa52f685774666bac13900fb4
PLANK_LOCAL=plank-reloaded
PLANK_UPSTREAM=https://github.com/zquestz/plank-reloaded.git
PLANK_RAMA=master
PLANK_BASE=e8e2b1fe2e9b13664b1402e2e68246a974ea1a4b

# slick-greeter-mac: la pantalla de inicio (login/instalar.sh)
GREETER_NOMBRE=slick-greeter-mac
GREETER_REPO=https://github.com/josemalena/mint-macos-greeter.git
GREETER_HASH=13ae3286979c42de30b6f30e884ce8eec25a7c6d
GREETER_LOCAL=slick-greeter
GREETER_UPSTREAM=https://github.com/linuxmint/slick-greeter.git
GREETER_RAMA=master
GREETER_BASE=d1f81b4406d5a756d2274c3dbbbd39bd1bd0f6d4

# Spotlyte: el Spotlight (fork de Ulauncher 5). Sin repo publicado, y sin
# hash fijado todavía: paquete.sh toma el HEAD de ../spotlyte.
SPOTLYTE_NOMBRE=Spotlyte
SPOTLYTE_REPO=https://github.com/josemalena/spotlyte.git
SPOTLYTE_HASH=a62cdb91edc803f042ee654e60f0e9d56186d655
SPOTLYTE_LOCAL=spotlyte
SPOTLYTE_UPSTREAM=https://github.com/Ulauncher/Ulauncher.git
SPOTLYTE_RAMA=v5
SPOTLYTE_BASE=5ba6eb1ec507d0c90cae80a8b4c33df473ade7be

# Lo que se compila de una versión publicada (requisitos.sh).
KEYD_VERSION=v2.6.0
LIBFSAPFS_VERSION=20260921

# Lo que se baja en una versión fija, sin fork.
# Magic Lamp de klangman, el efecto genio (extensions/magiclamp.sh): el
# commit de cinnamon-spices-extensions y el git tree de su carpeta.
MAGICLAMP_REPO=https://github.com/linuxmint/cinnamon-spices-extensions.git
MAGICLAMP_COMMIT=a4ca07fa03eaff12b6ad300b80305b9d1a913583   # versión 1.1.0 (20-10-2025)
MAGICLAMP_ARBOL=4e7bbdacb993a3b58e99ad989c488c810569a468
# Mojave-gtk-theme, la base del tema GTK (tema/gtk/construir.sh).
MOJAVE_REPO=https://github.com/vinceliuice/Mojave-gtk-theme.git
MOJAVE_COMMIT=eff102568e7aa712e7cb1f246002731a1ac32c2f      # 07-12-2025
# rclone para iCloud Drive (icloud/icloud.sh), con el sha256 del zip.
RCLONE_VERSION=v1.75.1                                      # 04-09-2026; iclouddrive desde v1.69
declare -A RCLONE_SHA256=(
  [amd64]=982b5aa772841168f8e380f139e9e787b2a105403e32b94da8676a0e1c0a13ab
  [arm64]=03f2504174034b6d004152ed7369251c9a9ec1f7e0836eda420f5c7a5ec0dff9
)

# Paquetes de apt (requisitos.sh los instala).
# Fynder: lista explícita de nemo-mac-e1 (build-dep nemo pide deb-src y trae
# de más). mint-macos-dock (fork de plank-reloaded): lista de la sesión de Plank.
COMPILAR=(
  build-essential pkg-config git meson ninja-build gettext
  gobject-introspection libgirepository1.0-dev libglib2.0-dev libglib2.0-dev-bin
  libgtk-3-dev libatk1.0-dev libpango1.0-dev libjson-glib-dev libcinnamon-desktop-dev
  libgail-3-dev libx11-dev libxapp-dev libexif-dev libexempi-dev
  valac libgdk-pixbuf-2.0-dev libgee-0.8-dev libbamf3-dev libcairo2-dev libwnck-3-dev
  libgnome-menu-3-dev libcanberra-dev libdbusmenu-glib-dev libdbusmenu-gtk3-dev
  libxi-dev libxfixes-dev
  # nativo/: el agente de polkit en Vala (mac-polkit); sin ella se compila el resto
  libpolkit-agent-1-dev
  # la pantalla de inicio (slick-greeter-mac, login/instalar.sh)
  liblightdm-gobject-1-dev libpixman-1-dev
  # keyd y libfsapfs
  python3-xlib autoconf automake autopoint libtool libssl-dev libfuse3-dev fuse3 curl
)
EJECUCION=(
  # Fynder y el dock
  nemo-preview gvfs shared-mime-info bamfdaemon
  # menú global (lado apps; appmenu-registrar ya no hace falta)
  appmenu-gtk2-module appmenu-gtk3-module libdbusmenu-glib4 libdbusmenu-gtk3-4
  # tema Constanza y lo que se saca de la Mac
  sassc imagemagick libheif1 libheif-plugin-libde265 fontconfig
  python3 python3-gi gir1.2-gtk-3.0 python3-pil python3-fonttools
  # applets del menú Apple y Force Quit
  wmctrl xdotool cinnamon-screensaver
  # agente de polkit: el binario enlaza la librería; el de Python usa el typelib
  libpolkit-agent-1-0 gir1.2-polkit-1.0
  # System Preferences en Vala (nativo/preferencias): json-glib para pactl e iso-codes; ipptool para Printers & Scanners
  libjson-glib-1.0-0 cups-ipp-utils iso-codes
  # migrar-datos.sh
  rsync
  # capturas/ (⇧⌘3, ⇧⌘4…, la grabación de ⇧⌘5) y la carpeta del escritorio
  gnome-screenshot xdg-user-dirs ffmpeg
  # zsh, el shell de la Mac desde Catalina
  zsh
  # Spotlyte (el fork de Ulauncher): lo que pide el paquete ulauncher
  libkeybinder-3.0-0 gir1.2-keybinder-3.0 gir1.2-webkit2-4.1 gir1.2-notify-0.7
  gir1.2-gdkpixbuf-2.0 python3-gi-cairo python3-dbus python3-levenshtein
  python3-pyinotify python3-websocket python3-xdg gir1.2-ayatanaappindicator3-0.1
  # icloud/icloud.sh: la clave de rclone.conf cifrado en el llavero; unzip
  libsecret-tools unzip
  # tema/iconos/car.py: los íconos que vienen en Assets.car (LZFSE) y los
  # glifos del Finder, que se dibujan de su PDF
  liblzfse1 poppler-utils
  # AppImages: las del runtime viejo montan con libfuse2 (en Mint 22 / Ubuntu
  # 24.04 se llama libfuse2t64); ver aplicaciones/APPIMAGE.md
  libfuse2t64
)
