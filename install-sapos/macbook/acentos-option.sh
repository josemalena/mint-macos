#!/usr/bin/env bash
# Acentos con ⌥ como en la Mac, para un teclado en INGLÉS (la MacBook5,1).
#   ⌥e + vocal → á é í ó ú     ⌥n + n → ñ     ⌥u + u → ü     ⌥1 → ¡     ⌥⇧/ → ¿
#
#   bash acentos-option.sh             lo pone
#   bash acentos-option.sh --deshacer  vuelve keyd a como estaba
#
# Se corre DESPUÉS de instalar-aqui.sh: necesita el keyd de mint-macos.
# NO en una computadora con teclado español: ahí AltGr+e da €.
#
# Cómo: la distribución English (Macintosh) ya trae los acentos en AltGr (la ⌥
# derecha). keyd traduce SOLO ⌥e, ⌥n, ⌥u, ⌥i, ⌥` y ⌥1 a AltGr; lo demás con ⌥
# sigue siendo Alt, así que Force Quit (⌘⌥Esc), kitty (⌥← ⌥→) y Fynder (⌘↑)
# no se tocan. Nunca la opción lv3:lalt_switch de XKB: esa sí los rompe.
set -euo pipefail
CONF="${KEYD_CONF:-/etc/keyd/default.conf}"
RESP="$CONF.antes-acentos"
SUDO=sudo; [ -w "$CONF" ] && SUDO=

if [ "${1:-}" = "--deshacer" ]; then
  [ -f "$RESP" ] || { echo "✗ no hay $RESP: nada que deshacer"; exit 1; }
  $SUDO cp "$RESP" "$CONF"
  $SUDO keyd reload
  echo "✓ keyd como antes. La distribución sigue en English (Macintosh): se cambia en Keyboard ▸ Layouts."
  exit 0
fi

[ -f "$CONF" ] || { echo "✗ no está $CONF: corre primero instalar-aqui.sh"; exit 1; }
grep -q '^\[alt\]' "$CONF" || { echo "✗ $CONF no tiene la capa [alt] de mint-macos"; exit 1; }

echo "▸ keyd: ⌥ + letra de acento → AltGr"
if grep -q '^e = G-e' "$CONF"; then
  echo "  ya estaba"
else
  [ -f "$RESP" ] || $SUDO cp "$CONF" "$RESP"
  TMP="$(mktemp)"
  awk '
    { print }
    $0 == "[alt]" {
      print "# Acentos como en la Mac con teclado en inglés (acentos-option.sh):"
      print "# en English (Macintosh), AltGr+e es el acento, AltGr+n la tilde de la ñ…"
      print "e = G-e"; print "n = G-n"; print "u = G-u"; print "i = G-i"
      print "grave = G-grave"; print "1 = G-1"
    }
    END { print ""; print "# ⌥⇧/ → ¿ (acentos-option.sh)"; print "[alt+shift]"; print "slash = G-S-slash" }
  ' "$CONF" > "$TMP"
  $SUDO cp "$TMP" "$CONF"; rm -f "$TMP"
  echo "  listo (respaldo: $RESP)"
fi

echo "▸ distribución English (Macintosh), en la sesión y en la pantalla de inicio"
gsettings set org.gnome.libgnomekbd.keyboard layouts "['us\tmac']"
if gsettings get org.gnome.libgnomekbd.keyboard options | grep -q 'lv3'; then
  echo "  ⚠ hay una opción «3rd level» puesta: quítala en Keyboard ▸ Layouts ▸ Options…, choca con keyd"
fi
$SUDO localectl set-x11-keymap us pc105 mac

$SUDO keyd reload
echo "✓ Prueba en un editor: ⌥e y después a → á; ⌥n y después n → ñ. Para quitarlo: bash $0 --deshacer"
