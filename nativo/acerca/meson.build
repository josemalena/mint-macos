# About This Mac / About This PC. Lo comparten el binario suelto y el residente mac-ventanas.
acerca_lib_fuentes = files('acerca_datos.vala', 'acerca_ventana.vala')

executable('mac-acerca', acerca_lib_fuentes + files('acerca_main.vala'),
  dependencies: [libmacos_dep, gtk_dep, glib_dep, gio_dep, json_dep, posix_dep, m_dep],
  install: false)
