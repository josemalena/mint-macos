# mac-bloqueo: la pantalla de bloqueo en la sesión. PAM va por su ABI (pam_ayuda.c declara lo mínimo), sin libpam0g-dev.
executable('mac-bloqueo',
  files('main.vala', 'estado.vala', 'supervisor.vala', 'pantalla.vala', 'pam_ayuda.c', 'pam_ayuda.vapi'),
  dependencies: [gtk_dep, glib_dep, gio_dep, posix_dep, m_dep],
  include_directories: include_directories('.'),
  link_args: ['-l:libpam.so.0'],
  vala_args: ['--vapidir=' + meson.current_source_dir()],
  install: false)
