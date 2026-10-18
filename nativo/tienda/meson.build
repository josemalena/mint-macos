# El App Store (Discover, Create, Work, Play, Develop, Categories, Updates). Solo pantallas: el motor es
# mint-macos-tienda (Rust), que habla por D-Bus en org.mintmacos.Tienda1. Las capturas de las fichas se bajan con GIO.
tienda_lib_fuentes = files('tienda_motor.vala', 'tienda_widgets.vala', 'tienda_ventana.vala')

executable('mac-tienda', tienda_lib_fuentes + files('tienda_main.vala'),
  dependencies: [libmacos_dep, gtk_dep, glib_dep, gio_dep, dependency('gio-unix-2.0'), posix_dep, m_dep],
  install: false)
