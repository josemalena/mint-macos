-- Extraer Mac: saca de esta Mac los recursos del sistema, las medidas y las
-- capturas para mint-macos. Abre Terminal y corre extraer.sh, que está en la
-- misma carpeta; los permisos de Screen Recording y Accessibility son de
-- Terminal. La guía completa está en LEEME.md.
--
-- Se abre con Script Editor y se corre con ▶ (Run).

set aqui to do shell script "dirname " & quoted form of POSIX path of (path to me)

set opciones to {"Recursos del sistema (íconos, .car, cursores, sonidos, fondos)", "Medidas (pantalla, fuentes, colores, ventana)", "Capturas en claro y en oscuro (unos 40 minutos)", "Videos (modo oscuro)"}
set elegidas to choose from list opciones with title "Extraer Mac" with prompt "¿Qué saco de esta Mac?" default items opciones with multiple selections allowed
if elegidas is false then return

set pasos to ""
repeat with e in elegidas
	set e to e as text
	if e starts with "Recursos" then set pasos to pasos & " recursos"
	if e starts with "Medidas" then set pasos to pasos & " medidas"
	if e starts with "Capturas" then set pasos to pasos & " capturas"
	if e starts with "Videos" then set pasos to pasos & " videos"
end repeat

if pasos contains "capturas" or pasos contains "videos" then
	display dialog "Mientras corran las capturas no toques el ratón ni el teclado: el guion mueve el ratón, abre menús y cambia entre claro y oscuro." & return & return & "Antes, en System Preferences ▸ Security & Privacy ▸ Privacy, dale a Terminal permiso en «Screen Recording» y en «Accessibility»." & return & return & "Al terminar devuelve el modo, el Dock y el Finder a como estaban." with title "Extraer Mac" buttons {"Cancel", "Empezar"} default button "Empezar" cancel button "Cancel"
end if

tell application "Terminal"
	activate
	do script "cd " & quoted form of aqui & " && /bin/bash ./extraer.sh" & pasos & "; echo; echo 'Terminado. Puedes cerrar esta ventana.'"
end tell
