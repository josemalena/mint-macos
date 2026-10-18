# El selector de emojis (⌃⌘Espacio). Lo comparten el binario suelto y el residente mac-ventanas.
emojis_lib_fuentes = files('emojis_selector.vala')

executable('mac-emojis-vala', emojis_lib_fuentes + files('emojis_main.vala'),
  dependencies: [libmacos_dep, gtk_dep, glib_dep, gio_dep, posix_dep, m_dep],
  install: false)
