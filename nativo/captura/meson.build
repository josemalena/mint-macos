# Lo que comparten el binario suelto y el residente mac-ventanas (todo menos el main.vala de cada uno).
captura_lib_fuentes = files('config.vala', 'util.vala', 'iconos.vala', 'capas.vala', 'barra.vala')

executable('mac-captura-herramienta-vala', captura_lib_fuentes + files('main.vala'),
  dependencies: [gtk_dep, gtk_x11_dep, glib_dep, gio_dep, posix_dep, m_dep],
  install: false)
