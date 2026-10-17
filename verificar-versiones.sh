#!/usr/bin/env bash
# Comprueba el manifiesto (versiones.sh) contra los repos de los forks y arma
# VERSIONES.md, la lista de parches de cada fork sobre su upstream.
#
#   ./verificar-versiones.sh             comprueba; falla si algo no cuadra o si
#                                        VERSIONES.md no es el que saldría
#   ./verificar-versiones.sh --escribir  igual, y reescribe VERSIONES.md
#
# No usa la red: lee los repos locales (../<_LOCAL> o ~/.cache/mint-macos/src)
# tal como quedaron del último fetch. Lo que comprueba de cada fork:
#   - que el _HASH exista en el repo local;
#   - que el repo tenga un remoto con la URL de _UPSTREAM, y que la base
#     (git merge-base del _HASH con _RAMA de ese remoto) sea _BASE;
#   - si el _HASH está en alguna rama del remoto _REPO (si no, avisa: en otra
#     computadora no se puede clonar de ahí).
# Y que ningún otro script del repo tenga un hash o una versión fijada por su
# cuenta.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
source "$REPO/versiones.sh"
ESCRIBIR=false
case "${1:-}" in
  --escribir) ESCRIBIR=true ;;
  "") ;;
  *) echo "uso: $0 [--escribir]" >&2; exit 2 ;;
esac

FALLAS=0
falla() { echo "  ✗ $*"; FALLAS=$((FALLAS + 1)); }
aviso() { echo "  ⚠ $*"; }
url() { local u="${1%/}"; echo "${u%.git}"; }

# remoto_de <repo> <url>: el nombre del remoto con esa URL, o nada.
remoto_de() {
  local r
  for r in $(git -C "$1" remote); do
    [ "$(url "$(git -C "$1" remote get-url "$r")")" = "$(url "$2")" ] && { echo "$r"; return; }
  done
  return 0
}

# local_de <F>: la carpeta del repo del fork en esta computadora, o nada.
local_de() {
  local nombre="$1_LOCAL" repo="$1_REPO" d
  local otro=""; [ -n "${!repo}" ] && otro="$(basename "$(url "${!repo}")")"
  for d in "$(dirname "$REPO")/${!nombre}" "$HOME/.cache/mint-macos/src/${!nombre}" ${otro:+"$HOME/.cache/mint-macos/src/$otro"}; do
    [ -d "$d/.git" ] && { echo "$d"; return; }
  done
  return 0
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MD="$TMP/VERSIONES.md"
{
  echo "# Versiones fijadas"
  echo
  echo "Generado por \`verificar-versiones.sh --escribir\` a partir de \`versiones.sh\`: no se edita a mano."
  echo "Cada fork, el commit que se compila y los parches que lleva encima de su upstream."
} > "$MD"

for F in "${FORKS[@]}"; do
  v() { local n="${F}_$1"; echo "${!n}"; }
  NOMBRE="$(v NOMBRE)" HASH="$(v HASH)" BASE="$(v BASE)" UP="$(v UPSTREAM)" RAMA="$(v RAMA)" FREPO="$(v REPO)"
  printf '\n▸ %s\n' "$NOMBRE"
  {
    echo
    echo "## $NOMBRE"
    echo
    echo "- Fork: ${FREPO:-sin repo publicado}"
    echo "- Upstream: $UP, rama \`$RAMA\`"
  } >> "$MD"
  D="$(local_de "$F")"
  if [ -z "$D" ]; then
    falla "no encuentro su repo (../$(v LOCAL) ni ~/.cache/mint-macos/src/$(v LOCAL))"
    continue
  fi
  echo "  repo: $D"
  if [ -z "$HASH" ]; then
    aviso "sin hash fijado (va el HEAD de $D)"
    echo "- Commit: **sin fijar** (el paquete toma el HEAD del repo local)" >> "$MD"
    REV=HEAD
  elif ! git -C "$D" cat-file -e "$HASH^{commit}" 2>/dev/null; then
    falla "$HASH no está en $D"
    continue
  else
    REV="$HASH"
    echo "- Commit: \`$HASH\` ($(git -C "$D" log -1 --format='%ad, %s' --date=short "$HASH"))" >> "$MD"
  fi

  R="$(remoto_de "$D" "$UP")"
  if [ -z "$R" ]; then
    falla "$D no tiene un remoto con $UP (git remote add upstream $UP)"
    continue
  fi
  if ! git -C "$D" rev-parse -q --verify "refs/remotes/$R/$RAMA" >/dev/null; then
    falla "no está $R/$RAMA en $D (git -C $D fetch $R $RAMA)"
    continue
  fi
  B="$(git -C "$D" merge-base "$REV" "$R/$RAMA")"
  if [ "$B" != "$BASE" ]; then
    falla "la base es $B y el manifiesto dice $BASE"
  fi
  TAG="$(git -C "$D" describe --tags --exact-match "$B" 2>/dev/null || true)"
  echo "- Base: \`$B\`${TAG:+ ($TAG)}, $(git -C "$D" log -1 --format='%ad, %s' --date=short "$B")" >> "$MD"

  if [ -n "$FREPO" ] && [ -n "$HASH" ]; then
    RF="$(remoto_de "$D" "$FREPO")"
    if [ -z "$RF" ]; then
      aviso "$D no tiene un remoto con $FREPO: no sé si el hash está empujado"
    elif [ -z "$(git -C "$D" branch -r --contains "$HASH" --list "$RF/*")" ]; then
      aviso "${HASH:0:9} no está en ninguna rama de $RF (según el último fetch): en otra computadora no se clona"
    fi
  fi

  N="$(git -C "$D" rev-list --count --no-merges "$B..$REV")"
  M="$(git -C "$D" rev-list --count --merges "$B..$REV")"
  echo "  base ${B:0:9}${TAG:+ ($TAG)}, $N parches$([ "$M" -gt 0 ] && echo ", $M merges")"
  {
    echo "- Parches: $N$([ "$M" -gt 0 ] && echo " (y $M merges de upstream, que no se listan)")"
    if [ -n "$HASH" ]; then
      echo
      echo "| Commit | Fecha | Asunto |"
      echo "|---|---|---|"
      # una barra en el asunto partiría la fila
      git -C "$D" log --reverse --no-merges --format='%h%x09%ad%x09%s' --date=short "$B..$HASH" \
        | awk -F'\t' '{ s = $3; gsub(/\|/, "\\|", s); printf "| `%s` | %s | %s |\n", $1, $2, s }'
    fi
  } >> "$MD"
done

printf '\n▸ Hashes fuera del manifiesto\n'
# una asignación con el valor escrito (no «$…»): FOO_HASH=…, COMMIT=…, X_VERSION=v1…
SUELTOS="$(git -C "$REPO" grep -nE '^[[:space:]]*[A-Z_]*(HASH|COMMIT|ARBOL|VERSION)=[0-9a-fv]' -- '*.sh' ':!versiones.sh' || true)"
if [ -n "$SUELTOS" ]; then
  falla "estos scripts fijan un hash por su cuenta:"; echo "$SUELTOS" | sed 's/^/    /'
else
  echo "  ninguno"
fi

printf '\n▸ VERSIONES.md\n'
if $ESCRIBIR; then
  cp "$MD" "$REPO/VERSIONES.md"; echo "  escrito"
elif cmp -s "$MD" "$REPO/VERSIONES.md"; then
  echo "  al día"
else
  falla "VERSIONES.md no es el que sale del manifiesto (./verificar-versiones.sh --escribir)"
fi

[ "$FALLAS" = 0 ] || { printf '\n%s fallas\n' "$FALLAS"; exit 1; }
printf '\nTodo cuadra\n'
