#!/bin/bash
# Menú global para las apps Qt de Flatpak (OBS Studio y similares).
#
# Qt exporta su menú por dbusmenu (com.canonical.AppMenu.Registrar) solo si ve ese
# servicio en el bus de sesión, y el sandbox de Flatpak lo oculta: dentro de OBS,
# NameHasOwner("com.canonical.AppMenu.Registrar") da false. Con el permiso de
# hablarle da true y la app registra su barra de menú. No hace falta cambiar el
# platformtheme: los temas «gnome» y genérico de Qt ya exportan; «kde» ni siquiera
# existe en el sandbox de OBS (solo trae qxdgdesktopportal).
#
#   ./flatpak-qt.sh                    OBS Studio y las apps cuyo runtime es org.kde.Platform
#   ./flatpak-qt.sh ID [ID…]           además, esas apps (p. ej. com.obsproject.Studio)
#   ./flatpak-qt.sh --deshacer [ID…]   quita el permiso a lo que se lo puso este script
#   ./flatpak-qt.sh --lista            a quién se lo daría, sin cambiar nada
#
# Es un override de usuario (sin sudo) y solo vale para la próxima vez que se abra la
# app: una ya abierta hay que cerrarla y abrirla otra vez.
set -euo pipefail

NOMBRE=com.canonical.AppMenu.Registrar
MARCA="$HOME/.local/share/mint-macos/menu-global-flatpak.lista"
BASE=(com.obsproject.Studio)

deshacer=0; solo_lista=0; extra=()
for a in "$@"; do
  case "$a" in
    --deshacer) deshacer=1 ;;
    --lista) solo_lista=1 ;;
    *) extra+=("$a") ;;
  esac
done

if [ "$deshacer" = 1 ]; then
  ids=("${extra[@]}")
  [ ${#ids[@]} -eq 0 ] && [ -f "$MARCA" ] && mapfile -t ids < "$MARCA"
  for id in "${ids[@]}"; do
    flatpak override --user --no-talk-name="$NOMBRE" "$id" 2>/dev/null && echo "Quitado: $id"
  done
  rm -f "$MARCA"
  echo "Listo (vale desde la próxima vez que se abran)."
  exit 0
fi

mapfile -t kde < <(flatpak list --app --columns=application,runtime 2>/dev/null | awk '$2 ~ /^org\.kde\.Platform\// {print $1}')
mapfile -t ids < <(printf '%s\n' "${BASE[@]}" "${kde[@]}" "${extra[@]}" | awk 'NF' | sort -u)

instaladas=$(flatpak list --app --columns=application 2>/dev/null)
final=()
for id in "${ids[@]}"; do
  grep -qx "$id" <<<"$instaladas" && final+=("$id")
done
if [ "$solo_lista" = 1 ]; then printf '%s\n' "${final[@]}"; exit 0; fi

mkdir -p "$(dirname "$MARCA")"
for id in "${final[@]}"; do
  flatpak override --user --talk-name="$NOMBRE" "$id"
  grep -qx "$id" "$MARCA" 2>/dev/null || echo "$id" >> "$MARCA"
  echo "Menú global permitido: $id"
done
echo "Cierra y vuelve a abrir esas apps para que tomen el permiso."
