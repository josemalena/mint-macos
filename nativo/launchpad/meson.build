pangocairo_dep = dependency('pangocairo')
gio_unix_dep_lp = dependency('gio-unix-2.0')

# La librería del perfil de macOS (perfiles/vala) vive fuera de nativo/: se copia aquí para que valac la compile con sus salidas dentro del árbol.
perfil_macos_vala = configure_file(input: '../../perfiles/vala/perfil-macos.vala', output: 'perfil-macos.vala', copy: true)

executable('mac-launchpad-vala', files('datos.vala', 'fondo.vala', 'ventana.vala', 'main.vala'), perfil_macos_vala,
  dependencies: [json_dep, pangocairo_dep, gio_unix_dep_lp, gtk_dep, glib_dep, gio_dep, posix_dep, m_dep],
  install: false)
