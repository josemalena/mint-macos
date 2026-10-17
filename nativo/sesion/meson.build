# Lo que comparten el binario suelto y el residente mac-ventanas (todo menos el main.vala de cada uno).
sesion_lib_fuentes = files(
  'acciones.vala',
  'dialogos.vala',
  'cli.vala',
)
sesion_fuentes = sesion_lib_fuentes + files('main.vala')

executable('mac-sesion', sesion_fuentes,
  dependencies: [libmacos_dep, gtk_dep, glib_dep, gio_dep, posix_dep],
  install: false)
