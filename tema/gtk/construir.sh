#!/usr/bin/env bash
# Tema GTK «Constanza» en ~/.themes, en sus 16 variantes (José, 18-10-2026: Light, Dark y el color
# de acento cambian el tema activo): Constanza-Oscuro y Constanza-Claro (acento azul, el de
# siempre: el nombre del oscuro no cambia) y Constanza-<Oscuro|Claro>-<Acento> para los otros siete
# de Catalina (Purple, Pink, Red, Orange, Yellow, Green, Graphite). Cada una: ventanas (GTK 2, 3 y 4), panel y
# menús de Cinnamon, bordes con semáforos (metacity-1 para Muffin) y Plank.
# Parte de Mojave-gtk-theme (vinceliuice, GPL-3.0) en una versión fijada: se
# clona y se compila con su propio instalador, sin copiar su CSS al repo, y
# encima se le agrega _constanza.scss. Si hay disco de Mac, los semáforos
# son los de Catalina (controles.py).
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
# MOJAVE_REPO y MOJAVE_COMMIT: el manifiesto.
source "$(dirname "$(dirname "$AQUI")")/versiones.sh"
# CONSTANZA_VARIANTES: cuáles armar («Oscuro», «Claro-Green»…); por defecto, todas.
ACENTOS="blue purple pink red orange yellow green grey"
# TEMA_BASE: el tema de la versión (perfiles: Constanza en Catalina; Samana, ValleNuevo y Ozama
# cuando cada pasada lo pida; José, 18-10-2026). Por ahora solo se construye Constanza.
TEMA_BASE="${TEMA_BASE:-Constanza}"
# Los colores de la versión de ese tema: medidas.json de su perfil (extraer-mac). Constanza
# (Catalina) no tiene todavía: quedan los medidos en capturas.
MEDIDAS=""
for v in "$HOME/.local/share/mint-macos/macos/"*/version.json; do
  [ -f "$v" ] || continue
  if python3 -c "import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get('tema') == sys.argv[2] else 1)" "$v" "$TEMA_BASE"; then
    [ -s "$(dirname "$v")/medidas.json" ] && MEDIDAS="$(dirname "$v")/medidas.json" && break
  fi
done
echo "  colores de la versión: ${MEDIDAS:-ninguno (los de las capturas de Catalina)}"
DEST="${CONSTANZA_TEMAS:-$HOME/.themes}"        # CONSTANZA_TEMAS y CONSTANZA_PLANK: para probar sin tocar los activos
TMP="$(mktemp -d)"
trap 'desmontar_mac 2>/dev/null; rm -rf "${TMP:?}"' EXIT

for p in sassc glib-compile-resources; do
  command -v "$p" >/dev/null || sudo apt install -y sassc libglib2.0-dev-bin
done

echo "  Mojave-gtk-theme ${MOJAVE_COMMIT:0:7}"
git clone -q "$MOJAVE_REPO" "$TMP/mojave"
git -C "$TMP/mojave" checkout -q "$MOJAVE_COMMIT"
# Los semáforos de Catalina, si hay disco de Mac: controles.py los saca de los catálogos de
# apariencia (car.py, con liblzfse) y los pone en metacity-1 y en gtk.gresource. Nada de Apple
# entra al repo. El disco se monta una vez para todas las variantes.
source "$AQUI/../comun.sh"
AP=""
if montar_mac_sistema; then
  AP="$MAC_SISTEMA/System/Library/CoreServices/SystemAppearance.bundle/Contents/Resources"
fi

armar() {  # COLOR (dark|light) ACENTO (de Mojave) NOMBRE
COLOR="$1"; ACENTO="$2"; NOMBRE="$3"
rm -rf "$TMP/salida"; mkdir -p "$TMP/salida"
# El azul es el de Mojave sin -t («MacOS blue», el de siempre): -t blue es otro azul.
"$TMP/mojave/install.sh" -d "$TMP/salida" -n Constanza -c "$COLOR" $([ "$ACENTO" = blue ] || echo "-t $ACENTO") \
  -o standard -a standard -s standard >/dev/null 2>&1
BASE="$(ls -d "$TMP/salida/Constanza-"* 2>/dev/null | head -1)"
[ -f "$BASE/gtk-3.0/gtk.gresource" ] || { echo "  ✗ no se compiló el tema base"; exit 1; }

# Lo propio encima, en GTK 3 (es lo que usan Nemo y casi todo en Cinnamon).
sassc "$AQUI/_constanza.scss" "$BASE/gtk-3.0/constanza.css"
# sassc antepone @charset si hay acentos en los comentarios, y GTK no lo
# acepta («unknown @ rule»).
sed -i '/^@charset/d' "$BASE/gtk-3.0/constanza.css"
for css in gtk.css gtk-dark.css; do
  echo '@import url("constanza.css");' >> "$BASE/gtk-3.0/$css"
done

# Lo propio encima del panel y los menús de Cinnamon.
cat "$AQUI/_constanza-cinnamon.css" >> "$BASE/cinnamon/cinnamon.css"
# La fuente del shell (menú de Cinnamon, panel, menús de applets, OSD): Mojave
# pide «Futura Bk bt», que no está, y fontconfig la cambia por Noto Sans. Va
# la SF a 10 pt (13 px, como los menús de macOS), o Inter si no está. Los
# textos fijos de 10 px (about, run dialog, ventanas agrupadas) suben a 11.
# Ojo con pipefail: fc-list se lee a una variable antes del grep.
FAMILIAS="$(fc-list : family)"
if grep -q '^\.SF NS$\|,\.SF NS$\|^\.SF NS,' <<< "$FAMILIAS"; then SHELL_FUENTE='".SF NS"'
else SHELL_FUENTE='"Inter"'; fi
sed -i -e "0,/font-family: Futura[^;]*;/s//font-family: $SHELL_FUENTE, sans-serif;/" \
       -e '0,/font-size: 9pt;/s//font-size: 10pt;/' \
       -e 's/font-size: 10px;/font-size: 11px;/' "$BASE/cinnamon/cinnamon.css"

# Nombre propio y metatema.
sed -i -e "s/^Name=.*/Name=$NOMBRE/" -e "s/^GtkTheme=.*/GtkTheme=$NOMBRE/" \
       -e "s/^MetacityTheme=.*/MetacityTheme=$NOMBRE/" -e "s/^IconTheme=.*/IconTheme=Constanza/" \
       -e "s/^CursorTheme=.*/CursorTheme=$([ -d "$HOME/.local/share/icons/Constanza/cursors" ] && echo Constanza || echo McMojave-cursors)/" \
       -e "s/^Comment=.*/Comment=$NOMBRE: Mojave-gtk-theme (GPL-3.0) con retoques propios/" \
       "$BASE/index.theme"
cp "$AQUI/../CREDITOS.md" "$BASE/CREDITOS.md"

# Los semáforos de Catalina, si hay disco de Mac: controles.py los saca de
# los catálogos de apariencia (car.py, con liblzfse) y los pone en
# metacity-1 y en gtk.gresource. Nada de Apple entra al repo.
if [ -n "${AP:-}" ]; then
  python3 "$AQUI/controles.py" "$AP/SystemAppearance.car" "$AP/DarkAquaAppearance.car" "$BASE" \
    $([ "$COLOR" = light ] && echo --claro) ${ACENTO_MAC[$ACENTO]:+--acento ${ACENTO_MAC[$ACENTO]}} \
    ${MEDIDAS:+--medidas "$MEDIDAS"} >/dev/null \
    || echo "  ⚠ $NOMBRE sin semáforos de Catalina (quedan los de Mojave)"
fi

# El tema nuevo se copia al lado y se cambia de un golpe por el de siempre (el activo no se
# queda sin tema mientras se arma, ni si el guion se cae a la mitad).
mkdir -p "${DEST:?}"
cp -a "$BASE" "$DEST/${NOMBRE:?}.nuevo-$$"
if [ -e "$DEST/$NOMBRE" ]; then mv "$DEST/$NOMBRE" "$DEST/$NOMBRE.viejo-$$"; fi
mv "$DEST/$NOMBRE.nuevo-$$" "$DEST/$NOMBRE"
rm -rf "${DEST:?}/${NOMBRE:?}.viejo-$$"

# Dock: el tema de Plank de Mojave con el nombre de Constanza; uno por apariencia (el acento no
# cambia el Dock), con el nombre de la variante azul.
[ "$ACENTO" = blue ] || { echo "  tema: $DEST/$NOMBRE"; return 0; }
PLANK_FINAL="${CONSTANZA_PLANK:-$HOME/.local/share/plank/themes}/${NOMBRE:?}"
PLANK="$PLANK_FINAL.nuevo-$$"          # se arma al lado y se cambia al final
rm -rf "${PLANK:?}"; mkdir -p "$PLANK"
cp "$TMP/mojave/src/other/plank/Theme-$([ "$COLOR" = dark ] && echo Dark || echo Light)/"* "$PLANK/"
# El Dock de Catalina, medido por la sesión de Plank contra las capturas de
# José (alto 73 con íconos de 56, paso de 60, el punto de 4 px). Las claves
# nuevas de plank-reloaded (IndicatorStyle=4 es el punto, BlurRadius,
# SeparatorPadding) van en [PlankDockTheme]. Cada clave se escribe en su
# línea: plank-reloaded reescribe el archivo al cargarlo y, si una clave
# queda repetida, manda la última.
python3 - "$PLANK/dock.theme" <<'PY'
import sys
ruta = sys.argv[1]
VALORES = {
    'PlankTheme': {
        'TopRoundness': '5', 'BottomRoundness': '0', 'LineWidth': '1',
        'OuterStrokeColor': '7;;10;;15;;255',
        'FillStartColor': '22;;31;;43;;200', 'FillEndColor': '22;;31;;43;;200',
        'InnerStrokeColor': '56;;63;;75;;255',
    },
    'PlankDockTheme': {
        'HorizPadding': '1.7', 'TopPadding': '1.4', 'BottomPadding': '1.5',
        'ItemPadding': '0.75', 'IconShadowSize': '0',
        'IndicatorStyle': '4', 'IndicatorColor': '131;;140;;152;;255',
        'IndicatorSize': '0.75', 'IndicatorOffset': '-0.6',
        'BlurRadius': '30', 'SeparatorPadding': '-2.2',
        # El rebote al abrir una app, medido de un video de José (18-10-2026, un celular filmando una Mac; baja confianza):
        # ~0.7 s por rebote y ~1/3 del ícono de altura. El de «pedir atención» no tiene datos y queda como estaba.
        'LaunchBounceTime': '700', 'LaunchBounceHeight': '0.35',
    },
}
lineas, seccion, vistos = open(ruta).read().splitlines(), None, set()
salida = []
def cerrar(sec):
    for k, v in VALORES.get(sec, {}).items():
        if (sec, k) not in vistos:
            salida.append(f'{k}={v}')
for l in lineas:
    if l.startswith('['):
        cerrar(seccion); seccion = l.strip('[]')
        # Mojave usa los nombres viejos de las secciones; Plank y el fork
        # leen [PlankTheme] y [PlankDockTheme].
        NUEVO = {'PlankDrawingTheme': 'PlankTheme', 'PlankDrawingDockTheme': 'PlankDockTheme'}
        if seccion in NUEVO:
            seccion = NUEVO[seccion]; l = f'[{seccion}]'
    elif '=' in l and seccion in VALORES:
        k = l.split('=', 1)[0].strip()
        if k in VALORES[seccion]:
            if (seccion, k) in vistos:
                continue
            vistos.add((seccion, k)); l = f'{k}={VALORES[seccion][k]}'
    salida.append(l)
cerrar(seccion)
open(ruta, 'w').write('\n'.join(salida) + '\n')
PY
if [ -e "$PLANK_FINAL" ]; then mv "$PLANK_FINAL" "$PLANK_FINAL.viejo-$$"; fi
mv "$PLANK" "$PLANK_FINAL"
rm -rf "${PLANK_FINAL:?}.viejo-$$"
echo "  tema: $DEST/$NOMBRE"
}

declare -A ACENTO_MAC=([blue]="" [purple]=Purple [pink]=Pink [red]=Red [orange]=Orange [yellow]=Yellow [green]=Green [grey]=Graphite)
for color in dark light; do
  base=$([ "$color" = dark ] && echo Oscuro || echo Claro)
  for a in $ACENTOS; do
    nombre="$TEMA_BASE-$base${ACENTO_MAC[$a]:+-${ACENTO_MAC[$a]}}"
    v="${nombre#"$TEMA_BASE"-}"
    case " ${CONSTANZA_VARIANTES:-todas} " in *" todas "*|*" $v "*) ;; *) continue ;; esac
    armar "$color" "$a" "$nombre"
  done
done
[ -n "$AP" ] && desmontar_mac
