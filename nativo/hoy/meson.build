# El servicio de la vista Today del Notification Center (org.mintmacos.Hoy1): hoy, el clima. Lo lleva mac-ventanas --residente
# y también corre suelto (mac-hoy) para las pruebas.
hoy_lib_fuentes = files('hoy_servicio.vala')

executable('mac-hoy', hoy_lib_fuentes + files('hoy_main.vala'),
  dependencies: [json_dep, glib_dep, gio_dep, gobject_dep, posix_dep, m_dep],
  install: false)
