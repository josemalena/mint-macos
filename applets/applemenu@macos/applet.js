/*
 * Menú Apple — applet de Cinnamon (applemenu@macos)
 *
 * El menú  de Catalina, medido en capturas de la Mac mini a 1x (c28):
 *
 *   About This Mac
 *   ─────────────
 *   System Preferences…
 *   App Store…
 *   ─────────────
 *   Recent Items                     ▸
 *   ─────────────
 *   Force Quit…                 ⌥⌘⎋   (con Shift: «Force Quit <app>» ⌥⇧⌘⎋)
 *   ─────────────
 *   Sleep
 *   Restart…
 *   Shut Down…
 *   ─────────────
 *   Lock Screen                  ⌃⌘Q
 *   Log Out <nombre completo>…   ⇧⌘Q
 *
 * Los atajos van alineados a la derecha, como en la Mac, y son los mismos que
 * tiene Cinnamon (cinnamon/keybindings.dconf). El estilo (fondo, borde,
 * renglones de 19 px, fuente SF, blanco) es la clase común del tema,
 * .constanza-menu, la misma de los menús de la app (appmenu y globalmenu):
 * los menús de la barra no pueden verse distintos (José, 10-10-2026).
 *
 * Restart, Shut Down y Log Out abren el diálogo de applemenu.py (la cuenta
 * regresiva de 60 s); Force Quit… abre forcekill.py.
 */
const Gio = imports.gi.Gio;
const GLib = imports.gi.GLib;
const St = imports.gi.St;
const Clutter = imports.gi.Clutter;
const Cinnamon = imports.gi.Cinnamon;
const Applet = imports.ui.applet;
const PopupMenu = imports.ui.popupMenu;
const Main = imports.ui.main;
const Util = imports.misc.util;
const Settings = imports.ui.settings;
const DocInfo = imports.misc.docInfo;
const Meta = imports.gi.Meta;
const Pango = imports.gi.Pango;

// La manzana de la Mac: el carácter U+F8FF de SFNS.ttf, que Constanza (Infra)
// saca vectorial a esta ruta. Fuera del repo: nada de Apple va al repo.
const MANZANA = GLib.build_filenamev([GLib.get_home_dir(), ".local/share/constanza/manzana/apple-menu.svg"]);
// El valor que traía la configuración antes: no cuenta como elección propia.
const ICONO_VIEJO = "/usr/share/icons/WhiteSur-dark/places@2x/16/folder-apple.svg";

// Los atajos se escriben como en la Mac: ⌃ Control, ⌥ Option, ⇧ Shift,
// ⌘ Command, ⎋ Escape.
const ATAJO_FORCE_QUIT = "⌥⌘⎋";
const ATAJO_FORCE_QUIT_APP = "⌥⇧⌘⎋";
const ATAJO_LOCK = "⌃⌘Q";
const ATAJO_LOGOUT = "⇧⌘Q";

// Cuántos documentos enseña «Recent Items», como la Mac por defecto.
const RECIENTES = 10;

function spawn(cmd) {
  Util.spawnCommandLine(cmd);
}

class AppleMenuApplet extends Applet.IconApplet {
  constructor(metadata, orientation, panel_height, instance_id) {
    super(orientation, panel_height, instance_id);
    this._appletPath = metadata.path;
    this._orientation = orientation;

    this.setAllowedLayout(Applet.AllowedLayout.BOTH);

    this.settings = new Settings.AppletSettings(this, metadata.uuid, instance_id);
    this.settings.bind("icon-path", "iconPath", this._syncIcon.bind(this));

    this.set_applet_tooltip("");

    this.menuManager = new PopupMenu.PopupMenuManager(this);
    this.menu = new Applet.AppletPopupMenu(this, orientation);
    this.menu.actor.add_style_class_name("constanza-menu");
    this.menu.box.add_style_class_name("constanza-menu-box");
    // 353 px por dentro, como la Mac (c28). En línea: el tema le gana al CSS.
    this.menu.box.set_style("min-width: 353px;");
    this.menuManager.addMenu(this.menu);

    this._ventanaActiva = null;
    this._conShift = false;

    this._buildMenu();
    this._syncIcon();


    this.menu.connect("open-state-changed", (menu, abierto) => {
      if (abierto) {
        // Lo que estaba al frente ANTES de abrir el menú: es la app a la que
        // se le fuerza la salida con Shift.
        this._ventanaActiva = global.display.focus_window;
        let [, , mods] = global.get_pointer();
        this._conShift = (mods & Clutter.ModifierType.SHIFT_MASK) !== 0;
        this._syncForceQuit();
        this._llenarRecientes();
      } else {
        this._cerrarRecientes();
      }
    });

    // Shift cambia «Force Quit…» por «Force Quit <app>» mientras el menú está
    // abierto, igual que en la Mac.
    this.menu.actor.connect("key-press-event", (actor, event) => this._onTecla(event, true));
    this.menu.actor.connect("key-release-event", (actor, event) => this._onTecla(event, false));
  }

  _syncIcon() {
    // Una ruta elegida en la configuración manda; si no, la manzana de la Mac;
    // si Constanza no la generó (falta SFNS.ttf), la de antes; y si nada,
    // el ícono genérico.
    let propia = (this.iconPath || "").trim();
    let ruta = null;
    if (propia.length && propia !== ICONO_VIEJO && GLib.file_test(propia, GLib.FileTest.EXISTS)) ruta = propia;
    else if (GLib.file_test(MANZANA, GLib.FileTest.EXISTS)) ruta = MANZANA;

    if (this._manzana) { this._manzana.destroy(); this._manzana = null; }

    if (ruta) {
      // A su tamaño exacto, 13×16 (c10), como fondo de un bloque propio: como
      // ícono, Cinnamon la escala al alto del panel en un cuadrado de 22×22 y
      // la estira a lo ancho. Queda en x 21–33 y y 2–17, como en la Mac.
      //
      // El botón (lo que se resalta y de donde cae el menú) va de x 9 a x 44,
      // con la manzana al centro: 12 px a la izquierda y 11 a la derecha (37
      // de ancho se comía un píxel). En x 45 empieza el de la app (appmenu),
      // como el «Finder» de la Mac; el panel ya no deja aire entre applets. En línea: después de
      // recargar el tema, el .applet-box de Mojave (padding 3px) le gana al
      // stylesheet.
      this.actor.set_style("margin-left: 9px; padding: 0 11px 0 12px;");
      // La clase es para el tema: en la Mac el botón no se resalta al pasar el
      // puntero (#panel .applemenu-boton:hover, en Constanza).
      this.actor.add_style_class_name("applemenu-boton");
      this._applet_icon_box.hide();
      let uri = Gio.File.new_for_path(ruta).get_uri();
      this._manzana = new St.Bin({ style_class: "applemenu-manzana", y_align: St.Align.MIDDLE,
        style: `width: 13px; height: 16px; background-image: url("${uri}"); background-size: 13px 16px;` });
      this.actor.add_child(this._manzana);
      return;
    }
    this._applet_icon_box.show();
    if (GLib.file_test(ICONO_VIEJO, GLib.FileTest.EXISTS)) this.set_applet_icon_path(ICONO_VIEJO);
    else this.set_applet_icon_symbolic_name("start-here-symbolic");
  }

  /** Un renglón con su texto y, si lo tiene, el atajo alineado a la derecha. */
  _item(texto, atajo, alActivar) {
    let item = this._renglon(texto, atajo, "applemenu-atajo");
    if (alActivar) item.connect("activate", alActivar);
    this.menu.addMenuItem(item);
    return item;
  }

  /** Un renglón con el texto a la izquierda y, si hay, el atajo (o la ▸)
   *  pegado al borde derecho. Van juntos en una caja que ocupa todo el ancho
   *  del renglón: puestos como dos piezas sueltas, Cinnamon no le daba al
   *  atajo su ancho y lo cortaba («⌥⌘» en vez de «⌥⌘⎋»). */
  _renglon(texto, derecha, claseDerecha) {
    let item = new PopupMenu.PopupBaseMenuItem();
    let caja = new St.BoxLayout({ x_expand: true });
    item.label = new St.Label({ text: texto, x_expand: true, y_align: Clutter.ActorAlign.CENTER });
    caja.add_child(item.label);
    if (derecha) {
      item._atajo = new St.Label({ text: derecha, style_class: claseDerecha, y_align: Clutter.ActorAlign.CENTER });
      item._atajo.clutter_text.ellipsize = Pango.EllipsizeMode.NONE;
      caja.add_child(item._atajo);
    }
    item.addActor(caja, { span: -1, expand: true });
    return item;
  }

  /** El separador de la Mac: de borde a borde, 2 px #45484B (c28). Va en
   *  línea porque el tema le resta el relleno del renglón y lo pinta de 1 px. */
  _nuevoSeparador() {
    let sep = new PopupMenu.PopupSeparatorMenuItem();
    sep.actor.add_style_class_name("applemenu-separador");
    // 12 px en total (7 + 2 + 3), con la línea donde la pone la Mac (c28);
    // sin el min-height de 17
    // que la clase común les da a los renglones.
    sep.actor.set_style("padding: 7px 0 3px 0; margin: 0; min-height: 0; spacing: 0;");
    sep._drawingArea.set_style("height: 2px; padding: 0; margin: 0; border-bottom-width: 0; -margin-horizontal: 0px; " +
      "-gradient-height: 2px; -gradient-start: #45484b; -gradient-end: #45484b;");
    return sep;
  }

  _separador() {
    this.menu.addMenuItem(this._nuevoSeparador());
  }

  /** Para lo que abre un diálogo: se cierra el menú primero. */
  _despuesDeCerrar(fn) {
    return () => {
      this.menu.close();
      GLib.idle_add(GLib.PRIORITY_DEFAULT, () => { fn(); return GLib.SOURCE_REMOVE; });
    };
  }

  _buildMenu() {
    this.menu.removeAll();

    this._item("About This Mac", null, () => spawn("mintreport"));
    this._separador();
    this._item("System Preferences…", null, () => spawn("cinnamon-settings"));
    this._item("App Store…", null, () => spawn("mintinstall"));
    this._separador();

    // Recent Items ▸: se abre al lado, como en la Mac, no adentro del menú.
    this._recientesItem = this._renglon("Recent Items", "▸", "applemenu-flecha");
    this._recientesItem.connect("active-changed", (item, activo) => {
      if (activo) this._abrirRecientes();
    });
    this._recientesItem.connect("activate", () => this._abrirRecientes());
    // Activar un renglón cierra el menú; este no debe cerrarlo.
    this._recientesItem.activate = () => this._abrirRecientes();
    this.menu.addMenuItem(this._recientesItem);
    this._crearMenuRecientes();

    this._separador();

    this._forceQuit = this._item("Force Quit…", ATAJO_FORCE_QUIT, () => this._onForceQuit());

    this._separador();

    this._item("Sleep", null, () => spawn("systemctl suspend"));
    this._item("Restart…", null, this._despuesDeCerrar(() => this._Dialog("restart")));
    this._item("Shut Down…", null, this._despuesDeCerrar(() => this._Dialog("shutdown")));

    this._separador();

    this._item("Lock Screen", ATAJO_LOCK, () => spawn("cinnamon-screensaver-command -l"));

    // Con el nombre completo, como la Mac: «Log Out José Alberto de la Cruz Malena…».
    let nombre = GLib.get_real_name();
    if (!nombre || nombre === "Unknown") nombre = GLib.get_user_name();
    this._item(`Log Out ${nombre}…`, ATAJO_LOGOUT, this._despuesDeCerrar(() => this._Dialog("logoff")));

    // Cualquier otro renglón al que se pase el puntero cierra «Recent Items».
    for (let item of this.menu._getMenuItems()) {
      if (item === this._recientesItem) continue;
      item.connect("active-changed", (it, activo) => { if (activo) this._cerrarRecientes(); });
    }
  }

  // ── Force Quit ────────────────────────────────────────────────────────────

  _nombreDeApp(ventana) {
    if (!ventana) return "";
    try {
      let app = Cinnamon.WindowTracker.get_default().get_window_app(ventana);
      if (app) {
        // «kitty» → «Kitty», como lo escribe el menú de la app.
        let n = app.get_name() || "";
        return n === n.toLowerCase() ? n.charAt(0).toUpperCase() + n.slice(1) : n;
      }
    } catch (e) {}
    try { return ventana.get_wm_class() || ""; } catch (e) {}
    return "";
  }

  _syncForceQuit() {
    let app = this._nombreDeApp(this._ventanaActiva);
    if (this._conShift && app) {
      this._forceQuit.label.set_text(`Force Quit ${app}`);
      this._forceQuit._atajo.set_text(ATAJO_FORCE_QUIT_APP);
    } else {
      this._forceQuit.label.set_text("Force Quit…");
      this._forceQuit._atajo.set_text(ATAJO_FORCE_QUIT);
    }
  }

  _onTecla(event, apretada) {
    let tecla = event.get_key_symbol();
    if (tecla === Clutter.KEY_Shift_L || tecla === Clutter.KEY_Shift_R) {
      this._conShift = apretada;
      this._syncForceQuit();
    }
    return Clutter.EVENT_PROPAGATE;
  }

  _onForceQuit() {
    let app = this._nombreDeApp(this._ventanaActiva);
    if (this._conShift && app && this._ventanaActiva) {
      // Con Shift, como en la Mac: la app del frente sale sin preguntar.
      // Nunca el escritorio: matarlo se lleva los íconos de José.
      let esEscritorio = false;
      try { esEscritorio = this._ventanaActiva.get_window_type() === Meta.WindowType.DESKTOP; } catch (e) {}
      let pid = 0;
      try { pid = this._ventanaActiva.get_pid(); } catch (e) {}
      if (!esEscritorio && pid > 1) {
        spawn(`kill -KILL ${pid}`);
        return;
      }
    }
    let script = GLib.build_filenamev([this._appletPath, "forcekill.py"]);
    spawn(`python3 '${script}'`);
  }

  // ── Recent Items ──────────────────────────────────────────────────────────

  _crearMenuRecientes() {
    // Un menú hijo a la derecha del renglón (St.Side.LEFT: el renglón queda a
    // su izquierda). Como hijo del menú Apple, el gestor no lo trata como un
    // clic afuera.
    this._recientes = new PopupMenu.PopupMenu(this._recientesItem.actor, St.Side.LEFT);
    this._recientes.actor.add_style_class_name("constanza-menu");
    this._recientes.box.add_style_class_name("constanza-menu-box");
    Main.uiGroup.add_actor(this._recientes.actor);
    this._recientes.actor.hide();
    // Con «Recent Items» abierto el teclado lo tiene este menú: Shift también
    // se escucha aquí.
    this._recientes.actor.connect("key-press-event", (actor, event) => this._onTecla(event, true));
    this._recientes.actor.connect("key-release-event", (actor, event) => this._onTecla(event, false));
    // Hijo desde ya: si el gestor no lo sabe cuando el puntero entra al
    // renglón, cambia de menú y cierra el principal. addChildMenu también lo
    // registra en el gestor.
    this.menu.addChildMenu(this._recientes);
  }

  _llenarRecientes() {
    let menu = this._recientes;
    menu.removeAll();

    let docs = [];
    try { docs = DocInfo.getDocManager()._infosByTimestamp.slice(0, RECIENTES); } catch (e) {}

    let titulo = new PopupMenu.PopupMenuItem("Documents", { reactive: false });
    titulo.actor.add_style_class_name("applemenu-titulo");
    menu.addMenuItem(titulo);

    if (!docs.length) {
      let vacio = new PopupMenu.PopupMenuItem("No recent documents", { reactive: false });
      menu.addMenuItem(vacio);
    }
    for (let doc of docs) {
      let item = new PopupMenu.PopupIconMenuItem(doc.name, "text-x-generic", St.IconType.FULLCOLOR, {});
      try { item.setIconName(null); item._icon.set_gicon(doc.gicon); } catch (e) {}
      item.connect("activate", () => {
        this.menu.close();
        try { Gio.app_info_launch_default_for_uri(doc.uri, global.create_app_launch_context()); } catch (e) {
          global.logError(e, "[AppleMenu] no se pudo abrir " + doc.uri);
        }
      });
      menu.addMenuItem(item);
    }

    menu.addMenuItem(this._nuevoSeparador());

    let limpiar = new PopupMenu.PopupMenuItem("Clear Menu");
    limpiar.setSensitive(docs.length > 0);
    limpiar.connect("activate", () => {
      this.menu.close();
      try { imports.gi.Gtk.RecentManager.get_default().purge_items(); } catch (e) {
        global.logError(e, "[AppleMenu] no se pudo limpiar los recientes");
      }
    });
    menu.addMenuItem(limpiar);
  }

  _abrirRecientes() {
    if (!this._recientes || this._recientes.isOpen) return;
    this._recientes.open(true);
  }

  _cerrarRecientes() {
    if (this._recientes && this._recientes.isOpen) this._recientes.close(true);
  }

  // ── Restart, Shut Down y Log Out: el diálogo de applemenu.py ─────────────

  _Dialog(mode) {
    const scriptPath = GLib.build_filenamev([this._appletPath, "applemenu.py"]);
    const argv = ["python3", scriptPath, "--mode", mode, "--print-json"];
    let proc;
    try {
      proc = new Gio.Subprocess({ argv, flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE });
      proc.init(null);
    } catch (e) {
      global.logError(e, `[AppleMenu] no se pudo abrir el diálogo: ${mode}`);
      return;
    }
    proc.communicate_utf8_async(null, null, (p, res) => {
      try {
        const [, stdout, stderr] = p.communicate_utf8_finish(res);
        if (stderr && stderr.trim().length) global.log(`[AppleMenu] ${mode} stderr:\n${stderr.trim()}`);
        if (stdout && stdout.trim().length) global.log(`[AppleMenu] ${mode}: ${stdout.trim()}`);
      } catch (e) {
        global.logError(e, `[AppleMenu] error leyendo la salida de ${mode}`);
      }
    });
  }

  on_applet_clicked() {
    this.menu.toggle();
  }

  on_applet_removed_from_panel() {
    this._cerrarRecientes();
    if (this._recientes) {
      try { this._recientes.destroy(); } catch (e) {}
    }
    if (this.settings) this.settings.finalize();
  }
}

function main(metadata, orientation, panel_height, instance_id) {
  return new AppleMenuApplet(metadata, orientation, panel_height, instance_id);
}
