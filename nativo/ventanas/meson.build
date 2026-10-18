# El residente de las ventanas chicas: diálogos de sesión, Force Quit, ⇧⌘5 (y lo que venga). Compila las mismas fuentes que
# los binarios sueltos, que siguen existiendo para la vuelta atrás y las pruebas.
executable('mac-ventanas',
  files('main.vala') + sesion_lib_fuentes + forcequit_lib_fuentes + captura_lib_fuentes + acerca_lib_fuentes,
  dependencies: [libmacos_dep, json_dep, wnck_dep, gio_unix_dep, gtk_dep, gtk_x11_dep, glib_dep, gio_dep, posix_dep, m_dep],
  c_args: ['-DWNCK_I_KNOW_THIS_IS_UNSTABLE'],
  install: false)
