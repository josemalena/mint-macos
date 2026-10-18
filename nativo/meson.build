project('mint-macos-nativo', ['c', 'vala'],
  version: '0.1.0',
  meson_version: '>= 0.60.0',
  default_options: ['warning_level=1', 'c_std=gnu11', 'buildtype=release', 'strip=true', 'b_lto=true', 'b_asneeded=true'])

# Las ventanas de mint-macos que se pasan de Python a binario: Vala + GTK3, sin intérprete.
# libmacos es lo común (alerta estilo Catalina, estilo CSS, íconos dibujados); cada binario vive en su carpeta.
# Los ayudantes de root y los servicios irán aparte, en Rust.
gtk_dep = dependency('gtk+-3.0', version: '>= 3.22')
glib_dep = dependency('glib-2.0')
gio_dep = dependency('gio-2.0')
gtk_x11_dep = dependency('gdk-x11-3.0')
gobject_dep = dependency('gobject-2.0')
json_dep = dependency('json-glib-1.0')
posix_dep = meson.get_compiler('vala').find_library('posix')
m_dep = meson.get_compiler('c').find_library('m', required: false)

subdir('libmacos')
subdir('sesion')
subdir('gatekeeper')
subdir('forcequit')
subdir('launchpad')
subdir('captura')
subdir('acerca')
subdir('emojis')
subdir('tienda')
subdir('menu')
subdir('ventanas')
subdir('preferencias')

# El agente de polkit necesita los headers de desarrollo (libpolkit-agent-1-dev); sin ellos se compila lo demás.
polkit_agent_dep = dependency('polkit-agent-1', required: false)
polkit_dep = dependency('polkit-gobject-1', required: false)
if polkit_agent_dep.found() and polkit_dep.found()
  subdir('polkit')
else
  message('sin libpolkit-agent-1-dev: no se compila mac-polkit')
endif
