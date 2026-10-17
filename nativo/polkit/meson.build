executable('mac-polkit', files('dialogo.vala', 'usuarios.vala', 'agente.vala', 'main.vala'),
  dependencies: [polkit_agent_dep, polkit_dep, gtk_dep, glib_dep, gio_dep, posix_dep, m_dep],
  c_args: ['-DPOLKIT_AGENT_I_KNOW_API_IS_SUBJECT_TO_CHANGE'],
  install: false)
