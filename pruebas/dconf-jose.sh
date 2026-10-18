# Revisar el dconf de José durante las pruebas (lo cargan correr.sh y sesion.sh).
#
# Antes de las pruebas correr.sh deja una copia en $PRUEBAS_DCOPIA/dconf-antes
# (0600, en ~/.local/share/mint-macos/pruebas-dconf: lleva sus ajustes). Después de
# cada caso se compara el hash; si cambió, se ve qué claves cambiaron:
#   - si alguna es de lo que tocan las pruebas (PREFIJOS_FUGA), es una fuga: la
#     corrida se para (2);
#   - si no (José usando su sesión: mintinstall, el reloj, una app suya), se anota
#     como aviso en dconf-avisos.txt, la copia pasa a ser la de ahora y se sigue (1).
# El detalle queda en dconf.diff.

# Los esquemas que tocan las pruebas: Cinnamon y sus atajos, el Dock, Fynder (y
# Nemo, de donde viene), GNOME y GTK, y las de XApp.
PREFIJOS_FUGA='^/(org/cinnamon|net/launchpad/plank|io/github/josemalena|org/nemo|org/gnome/desktop|org/gtk|org/x)/'

# dconf dump de una copia: lee el archivo directo (sin dconf-service) con un
# perfil que solo tiene esa base.
volcar_dconf() {
  printf 'user-db:user\n' > "$1/perfil"
  XDG_CONFIG_HOME="$1" DCONF_PROFILE="$1/perfil" dconf dump / 2>/dev/null
}

# «[a/b]\nclave=valor» → «/a/b/clave=valor», una línea por clave.
aplanar() {
  awk '/^\[/ { s = substr($0, 2, length($0) - 2); next } /=/ { print "/" s "/" $0 }'
}

dconf_hash() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1 || true; }

# revisar_dconf ARCHIVO_DE_JOSE → 0 sin cambios, 1 solo avisos, 2 fuga.
revisar_dconf() {
  local jose="$1" d="$PRUEBAS_DCOPIA" ahora claves fugas
  [ "$(dconf_hash "$jose")" != "$(cat "$d/sha" 2>/dev/null)" ] || return 0
  (umask 077; rm -rf "$d/dconf-despues"; mkdir -p "$d/dconf-despues/dconf")
  install -m 600 "$jose" "$d/dconf-despues/dconf/user" 2>/dev/null || true
  (umask 077; diff <(volcar_dconf "$d/dconf-antes") <(volcar_dconf "$d/dconf-despues") > "$d/dconf.diff" || true)
  # Las claves que aparecen, desaparecen o cambian de valor.
  claves="$(diff <(volcar_dconf "$d/dconf-antes" | aplanar | sort) <(volcar_dconf "$d/dconf-despues" | aplanar | sort) |
    sed -n 's/^[<>] \([^=]*\)=.*/\1/p' | sort -u)"
  fugas="$(printf '%s\n' "$claves" | grep -E "$PREFIJOS_FUGA" || true)"
  if [ -n "$fugas" ]; then
    printf '%s\n' "$fugas" > "$d/dconf-fugas.txt"
    return 2
  fi
  # Solo cosas de José: se anotan y la copia pasa a ser la de ahora.
  printf '%s  %s\n' "$(date +%H:%M:%S)" "$(printf '%s ' $claves)" >> "$d/dconf-avisos.txt"
  rm -rf "$d/dconf-antes"; mv "$d/dconf-despues" "$d/dconf-antes"
  dconf_hash "$jose" > "$d/sha"
  return 1
}
