sesion_fuentes = files(
  'acciones.vala',
  'dialogos.vala',
  'main.vala',
)

executable('mac-sesion', sesion_fuentes,
  dependencies: [libmacos_dep, gtk_dep, glib_dep, gio_dep, posix_dep],
  install: false)
