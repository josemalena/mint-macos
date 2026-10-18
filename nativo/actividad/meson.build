# Activity Monitor (mac-actividad): la ventana de Catalina más una pestaña «Resources» con gráficas. Solo dibuja: los datos
# los da org.mintmacos.Monitor1 (rust/monitor/DBUS.md).
actividad_lib_fuentes = files('actividad_motor.vala', 'actividad_formato.vala', 'actividad_graficas.vala', 'actividad_ventana.vala')

executable('mac-actividad', actividad_lib_fuentes + files('actividad_main.vala'),
  dependencies: [libmacos_dep, gtk_dep, glib_dep, gio_dep, posix_dep, m_dep],
  install: false)
