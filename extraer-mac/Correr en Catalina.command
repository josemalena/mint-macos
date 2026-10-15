#!/bin/bash
# Corrida parcial de extraer-mac en Catalina (15-10-2026), con doble clic.
# Saca los bloques que faltaban (01 05 06 09 16), capturas y videos, y al final
# copia la salida al disco HDD. No borra nada: si la carpeta ya existe en el
# HDD, no la pisa y avisa.
AQUI="$(cd "$(dirname "$0")" && pwd)"
SALIDA="$HOME/extraer-salida/macos10.15.8-parcial-20261015"
HDD="/Volumes/HDD"

echo "== Extraer Mac: corrida parcial de Catalina =="
echo
echo "Antes de seguir, revisa en Finder ▸ Preferences… ▸ Sidebar"
echo "que Documents y Downloads estén marcados."
echo
echo "Mientras corre no toques la Mac. Solo cuando te avise, escribe tu clave"
echo "en System Preferences (Users & Groups, Date & Time, Security y Network)."
echo
read -r -p "Pulsa Enter para empezar (o cierra esta ventana para cancelar)… " _

cd "$AQUI" || { echo "No encuentro la carpeta extraer-mac."; exit 1; }
SALIDA="$SALIDA" BLOQUES="01 05 06 09 16" bash extraer.sh capturas videos
r=$?
echo
echo "extraer.sh terminó con código $r. La bitácora está en $SALIDA/herramientas/capturas.log"

if [ ! -d "$SALIDA" ]; then
  echo "No se creó $SALIDA: no hay nada que copiar."; exit 1
fi
if [ ! -d "$HDD" ]; then
  echo "El disco HDD no está conectado. Copia a mano $SALIDA a HDD/extraer-salida/."; exit 1
fi
DEST="$HDD/extraer-salida/$(basename "$SALIDA")"
if [ -e "$DEST" ]; then
  echo "Ya existe $DEST: no la piso. Copia a mano si hace falta."; exit 1
fi
mkdir -p "$HDD/extraer-salida" && echo "Copiando a $DEST …" && cp -R "$SALIDA" "$DEST" \
  && echo "Copiado: $(find "$DEST" -name '*.png' | wc -l | tr -d ' ') capturas y $(find "$DEST" -name '*.mov' | wc -l | tr -d ' ') videos." \
  || echo "Falló la copia al HDD; la salida sigue en $SALIDA."
echo
echo "Listo. Ya puedes seguir con OCLP."
read -r -p "Pulsa Enter para cerrar… " _
