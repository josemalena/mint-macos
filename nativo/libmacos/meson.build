libmacos_fuentes = files(
  'estilo.vala',
  'iconos.vala',
  'alerta.vala',
  'creditos.vala',
)

libmacos = static_library('macos', libmacos_fuentes,
  dependencies: [gtk_dep, glib_dep, gio_dep, gobject_dep, json_dep, m_dep],
  vala_header: 'macos.h',
  vala_vapi: 'macos-1.0.vapi',
  install: false)

libmacos_dep = declare_dependency(
  link_with: libmacos,
  include_directories: include_directories('.'),
  dependencies: [gtk_dep, glib_dep, gio_dep, json_dep])
