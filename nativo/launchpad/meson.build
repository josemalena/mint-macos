pangocairo_dep = dependency('pangocairo')
gio_unix_dep_lp = dependency('gio-unix-2.0')

executable('mac-launchpad-vala', files('datos.vala', 'fondo.vala', 'ventana.vala', 'main.vala'),
  dependencies: [pangocairo_dep, gio_unix_dep_lp, gtk_dep, glib_dep, gio_dep, posix_dep, m_dep],
  install: false)
