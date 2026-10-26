-- ui.applescript: ayudantes de interfaz para extraer.sh. Buscan los controles por
-- su nombre en TODA la ventana (entire contents, hojas incluidas), en vez de
-- rutas fijas que cambian entre versiones de macOS.
--
--   osascript ui.applescript clic <proceso> <texto>       clic en el botón, pestaña o casilla cuyo
--                                                         nombre o descripción empieza con <texto>
--   osascript ui.applescript clic-valor <proceso> <texto> clic en el elemento cuyo valor empieza con <texto>
--   osascript ui.applescript fila <proceso> <texto>       selecciona la fila (tabla o lista) que contiene <texto>
--   osascript ui.applescript filas <proceso>              el texto de cada fila de la PRIMERA lista, una por línea
--   osascript ui.applescript popups <proceso>             cuántos menús desplegables tiene la ventana
--   osascript ui.applescript popup <proceso> <n>          abre el desplegable n (y lo deja abierto)
--   osascript ui.applescript popup-item <proceso> <n> <ítem>  abre el desplegable n y escoge <ítem>
--   osascript ui.applescript marcado <proceso> <texto>     «si» o «no»: si el botón de radio o la casilla <texto> está marcado
--   osascript ui.applescript candado <proceso>            «abierto», «cerrado» o «sin candado»
--   osascript ui.applescript arbol <proceso>              rol y nombre de cada elemento (para la bitácora)
--
-- System Settings (macOS 13 en adelante), para el bloque 08:
--   osascript ui.applescript titulo <proceso>             el título de la ventana 1
--   osascript ui.applescript hoja-hay <proceso>           «si» si hay una hoja o un diálogo encima
--   osascript ui.applescript barra <proceso>              «n<TAB>texto» por cada fila de la barra lateral (la primera AXOutline)
--   osascript ui.applescript barra-ir <proceso> <n>       selecciona la fila n de la barra lateral
--   osascript ui.applescript clic-igual <proceso> <texto> clic en el BOTÓN cuyo nombre o descripción es exactamente <texto>
--   osascript ui.applescript desplazar <proceso>          lleva al fondo el área con scroll que no es la barra lateral («ok» si se movió)
--   osascript ui.applescript desplazar-arriba <proceso>   la devuelve arriba
--   Con «<proceso>::hoja» los comandos miran dentro de la hoja (sheet 1 de la ventana 1), no de la ventana.
--
-- Contesta «ok» o «no» (o el dato pedido). Nunca escribe texto ni cambia un ajuste
-- por su cuenta: los clics los decide extraer.sh.

on texto_de(e, campo)
	tell application "System Events"
		try
			if campo is "name" then set v to name of e
			if campo is "description" then set v to description of e
			if campo is "value" then set v to value of e
			if campo is "title" then set v to title of e
			if v is missing value then return ""
			return v as text
		on error
			return ""
		end try
	end tell
end texto_de

on empieza(a, b)
	if b is "" then return false
	return a starts with b
end empieza

on run argv
	set cmd to item 1 of argv
	set proc to item 2 of argv
	set enHoja to false
	if proc ends with "::hoja" then
		set enHoja to true
		set proc to text 1 thru -7 of proc
	end if
	tell application "System Events"
		if not (exists process proc) then return "no"
		tell process proc
			if (count of windows) is 0 then return "no"
			-- Los dos primeros no necesitan recorrer la ventana (en System Settings tarda).
			if cmd is "titulo" then
				try
					return (name of window 1) as text
				on error
					return ""
				end try
			end if
			if cmd is "hoja-hay" then
				if exists sheet 1 of window 1 then return "si"
				repeat with w in windows
					try
						if subrole of w is "AXDialog" or subrole of w is "AXSystemDialog" then return "si"
					end try
				end repeat
				return "no"
			end if
			if enHoja and (exists sheet 1 of window 1) then
				set todo to entire contents of sheet 1 of window 1
			else
				set todo to entire contents of window 1
			end if
		end tell
	end tell

	if cmd is "barra" or cmd is "barra-ir" then
		repeat with e in todo
			try
				tell application "System Events" to set r to role of e
				if r is "AXOutline" then
					tell application "System Events" to set fs to rows of e
					if cmd is "barra-ir" then
						set n to (item 3 of argv) as integer
						if n > (count of fs) then return "no"
						tell application "System Events" to select item n of fs
						return "ok"
					end if
					set salida to ""
					set i to 0
					repeat with f in fs
						set i to i + 1
						tell application "System Events" to set dentro to entire contents of f
						set txt to ""
						repeat with c in dentro
							tell application "System Events" to set rc to role of c
							if rc is "AXStaticText" then
								set txt to my texto_de(c, "value")
								if txt is "" then set txt to my texto_de(c, "name")
								if txt is not "" then exit repeat
							end if
						end repeat
						set salida to salida & i & tab & txt & linefeed
					end repeat
					return salida
				end if
			end try
		end repeat
		return "no"
	end if

	if cmd is "clic-igual" then
		set t to item 3 of argv
		repeat with e in todo
			try
				tell application "System Events" to set r to role of e
				if r is "AXButton" and (my texto_de(e, "name") is t or my texto_de(e, "description") is t) then
					tell application "System Events" to click e
					return "ok"
				end if
			end try
		end repeat
		return "no"
	end if

	if cmd is "desplazar" or cmd is "desplazar-arriba" then
		set movido to false
		repeat with e in todo
			try
				tell application "System Events"
					if role of e is "AXScrollArea" and (count of outlines of e) is 0 then
						repeat with b in scroll bars of e
							if (value of attribute "AXOrientation" of b) is "AXVerticalOrientation" then
								set v to value of b
								if cmd is "desplazar" and v < 1 then
									set value of b to 1
									set movido to true
								else if cmd is "desplazar-arriba" and v > 0 then
									set value of b to 0
									set movido to true
								end if
							end if
						end repeat
					end if
				end tell
			end try
		end repeat
		if movido then return "ok"
		return "no"
	end if

	if cmd is "clic" or cmd is "clic-valor" then
		set t to item 3 of argv
		set roles to {"AXButton", "AXRadioButton", "AXCheckBox", "AXMenuButton", "AXPopUpButton", "AXDisclosureTriangle", "AXStaticText", "AXImage"}
		repeat with e in todo
			try
				tell application "System Events" to set r to role of e
				if cmd is "clic-valor" then
					if my empieza(my texto_de(e, "value"), t) then
						tell application "System Events" to click e
						return "ok"
					end if
				else if r is in roles and r is not "AXStaticText" and r is not "AXImage" then
					if my empieza(my texto_de(e, "name"), t) or my empieza(my texto_de(e, "description"), t) or my empieza(my texto_de(e, "title"), t) then
						tell application "System Events" to click e
						return "ok"
					end if
				end if
			end try
		end repeat
		return "no"
	end if

	if cmd is "fila" then
		set t to item 3 of argv
		repeat with e in todo
			try
				tell application "System Events" to set r to role of e
				if r is "AXRow" then
					tell application "System Events" to set dentro to entire contents of e
					repeat with c in dentro
						if my texto_de(c, "value") is t or my texto_de(c, "name") is t or my texto_de(c, "description") is t then
							tell application "System Events" to select e
							return "ok"
						end if
					end repeat
				end if
			end try
		end repeat
		return "no"
	end if

	if cmd is "filas" then
		set salida to ""
		repeat with e in todo
			try
				tell application "System Events" to set r to role of e
				if r is "AXTable" or r is "AXOutline" then
					tell application "System Events" to set fs to rows of e
					repeat with f in fs
						tell application "System Events" to set dentro to entire contents of f
						set txt to ""
						repeat with c in dentro
							set v to my texto_de(c, "value")
							if v is "" then set v to my texto_de(c, "name")
							if v is not "" and v is not "missing value" then
								set txt to v
								exit repeat
							end if
						end repeat
						if txt is not "" then set salida to salida & txt & linefeed
					end repeat
					return salida
				end if
			end try
		end repeat
		return salida
	end if

	if cmd is "popups" or cmd is "popup" or cmd is "popup-item" then
		set ps to {}
		repeat with e in todo
			try
				tell application "System Events" to set r to role of e
				if r is "AXPopUpButton" then set end of ps to e
			end try
		end repeat
		if cmd is "popups" then return (count of ps) as text
		set n to (item 3 of argv) as integer
		if n > (count of ps) then return "no"
		set p to item n of ps
		tell application "System Events" to click p
		if cmd is "popup" then return "ok"
		delay 0.8
		tell application "System Events"
			try
				click menu item (item 4 of argv) of menu 1 of p
				return "ok"
			on error
				key code 53
				return "no"
			end try
		end tell
	end if

	if cmd is "marcado" then
		set t to item 3 of argv
		repeat with e in todo
			try
				tell application "System Events" to set r to role of e
				if (r is "AXRadioButton" or r is "AXCheckBox") and (my empieza(my texto_de(e, "name"), t) or my empieza(my texto_de(e, "title"), t)) then
					if my texto_de(e, "value") is "1" then return "si"
					return "no"
				end if
			end try
		end repeat
		return "?"
	end if

	if cmd is "candado" then
		repeat with e in todo
			try
				set n to my texto_de(e, "name") & " " & my texto_de(e, "description")
				if n contains "lock to make changes" then return "cerrado"
				if n contains "lock to prevent further changes" then return "abierto"
			end try
		end repeat
		return "sin candado"
	end if

	if cmd is "arbol" then
		set salida to ""
		repeat with e in todo
			try
				tell application "System Events" to set r to role of e
				set salida to salida & r & " | " & my texto_de(e, "name") & " | " & my texto_de(e, "description") & " | " & my texto_de(e, "value") & linefeed
			end try
		end repeat
		return salida
	end if
	return "no"
end run
