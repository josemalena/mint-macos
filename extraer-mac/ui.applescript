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
--   osascript ui.applescript arbol <proceso>              rol, nombre, descripción, valor y AXIdentifier de cada elemento (para la bitácora)
--
-- System Settings (macOS 13 en adelante), para el bloque 08:
--   osascript ui.applescript titulo <proceso>             el título de la ventana 1
--   osascript ui.applescript hoja-hay <proceso>           «si» si hay una hoja o un diálogo encima
--   osascript ui.applescript barra <proceso>              «n|texto|AXIdentifier» por cada fila de la barra lateral (la primera AXOutline)
--   osascript ui.applescript botones <proceso>            «n<TAB>nombre<TAB>descripción<TAB>AXIdentifier<TAB>rol<TAB>subrol» de cada AXButton fuera de la barra lateral
--   osascript ui.applescript barra-ir <proceso> <n> [rodar]  selecciona la fila n de la barra lateral (antes la lleva a la vista)
--   osascript ui.applescript ocupado <proceso>            «si» si la ventana tiene una rueda o una barra de progreso
--   osascript ui.applescript clic-id <proceso> <id>       clic en el BOTÓN cuyo AXIdentifier es exactamente <id>
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

-- Un atributo de Accessibility como texto («» si no lo tiene).
on atributo(e, a)
	tell application "System Events"
		try
			set v to value of attribute a of e
			if v is missing value then return ""
			return v as text
		on error
			return ""
		end try
	end tell
end atributo

-- En macOS 27 las filas de la barra lateral de System Settings no tienen texto accesible y
-- «entire contents» de una fila sale vacío: se baja por UI elements (fila → celda → botón) y
-- se toma el AXIdentifier, primero el de un botón (verificado por Mint-Macos, 26-10-2026:
-- «com.apple.settings.notifications»).
on identificador_en(e, nivel, soloBoton)
	if nivel > 5 then return ""
	set r to ""
	tell application "System Events"
		try
			set r to role of e
		end try
	end tell
	if (not soloBoton) or r is "AXButton" then
		set v to my atributo(e, "AXIdentifier")
		if v is not "" then return v
	end if
	set hijos to {}
	tell application "System Events"
		try
			set hijos to UI elements of e
		end try
	end tell
	repeat with h in hijos
		set v to my identificador_en(h, nivel + 1, soloBoton)
		if v is not "" then return v
	end repeat
	return ""
end identificador_en

-- El primer texto visible bajo e (respaldo de la etiqueta), sin el genérico «button».
on texto_en(e, nivel)
	if nivel > 5 then return ""
	-- Sin «description»: en 27 trae la del rol («outline row»), y la búsqueda salió como un panel.
	repeat with campo in {"value", "name", "title"}
		set v to my texto_de(e, campo as text)
		if v is not "" and v is not "button" and v is not "0" and v is not "1" then return v
	end repeat
	set hijos to {}
	tell application "System Events"
		try
			set hijos to UI elements of e
		end try
	end tell
	repeat with h in hijos
		set v to my texto_en(h, nivel + 1)
		if v is not "" then return v
	end repeat
	return ""
end texto_en

-- Botones de la ventana que nunca se pulsan: semáforo y pantalla completa, flechas y páginas
-- del scroll, y todo lo que cuelga de una barra de scroll o de un campo de búsqueda.
on prohibido(e)
	set sr to my atributo(e, "AXSubrole")
	-- Un interruptor o un conmutador cambia un ajuste aunque su rol diga botón.
	if sr is in {"AXSwitch", "AXToggle", "AXCloseButton", "AXZoomButton", "AXMinimizeButton", "AXFullScreenButton", "AXIncrementArrow", "AXDecrementArrow", "AXIncrementPage", "AXDecrementPage", "AXSearchField"} then return true
	tell application "System Events"
		try
			set p to value of attribute "AXParent" of e
			if role of p is in {"AXScrollBar", "AXIncrementor", "AXSearchField", "AXTextField"} then return true
		end try
	end tell
	return false
end prohibido

-- Si e está dentro de la barra lateral (algún antecesor es una AXOutline).
on en_barra(e)
	set x to e
	repeat 10 times
		tell application "System Events"
			try
				set x to value of attribute "AXParent" of x
				if role of x is "AXOutline" then return true
				if role of x is "AXWindow" then return false
			on error
				return false
			end try
		end tell
	end repeat
	return false
end en_barra

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
			if cmd is "ocupado" then
				-- «si» mientras haya una rueda o una barra de progreso (Game Center cargando en 27)
				try
					if (count of (every busy indicator of entire contents of window 1)) > 0 then return "si"
				end try
				try
					if (count of (every progress indicator of entire contents of window 1)) > 0 then return "si"
				end try
				return "no"
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
						set fila to item n of fs
						-- La fila a la vista antes de escogerla: en 27 las de abajo (32-38) no abrían
						-- con la barra cortada. AXScrollToVisible y, con «rodar», también la barra de
						-- scroll de la lista por su valor (nunca las flechas).
						tell application "System Events"
							try
								perform action "AXScrollToVisible" of fila
							end try
						end tell
						if (count of argv) > 3 and item 4 of argv is "rodar" then
							tell application "System Events"
								try
									set sa to value of attribute "AXParent" of e
									if role of sa is "AXScrollArea" and (count of fs) > 1 then
										repeat with b in scroll bars of sa
											if (value of attribute "AXOrientation" of b) is "AXVerticalOrientation" then set value of b to ((n - 1) / ((count of fs) - 1))
										end repeat
									end if
								end try
							end tell
						end if
						delay 0.3
						tell application "System Events" to select fila
						return "ok"
					end if
					set salida to ""
					set i to 0
					repeat with f in fs
						set i to i + 1
						set txt to my texto_en(f, 0)
						set ident to my identificador_en(f, 0, true)
						if ident is "" then set ident to my identificador_en(f, 0, false)
						set salida to salida & i & "|" & txt & "|" & ident & linefeed
					end repeat
					return salida
				end if
			end try
		end repeat
		return "no"
	end if

	if cmd is "clic-id" then
		set t to item 3 of argv
		repeat with e in todo
			try
				tell application "System Events" to set r to role of e
				if r is "AXButton" and my atributo(e, "AXIdentifier") is t and not my prohibido(e) and not my en_barra(e) then
					tell application "System Events" to click e
					return "ok"
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

	if cmd is "botones" then
		set salida to ""
		set i to 0
		repeat with e in todo
			try
				tell application "System Events" to set r to role of e
				if r is "AXButton" and not my en_barra(e) and not my prohibido(e) then
					set i to i + 1
					set salida to salida & i & tab & my texto_de(e, "name") & tab & my texto_de(e, "description") & tab & my atributo(e, "AXIdentifier") & tab & r & tab & my atributo(e, "AXSubrole") & linefeed
				end if
			end try
		end repeat
		return salida
	end if

	if cmd is "arbol" then
		set salida to ""
		repeat with e in todo
			try
				tell application "System Events" to set r to role of e
				set salida to salida & r & " | " & my texto_de(e, "name") & " | " & my texto_de(e, "description") & " | " & my texto_de(e, "value") & " | " & my atributo(e, "AXIdentifier") & linefeed
			end try
		end repeat
		return salida
	end if
	return "no"
end run
