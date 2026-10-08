/*
 * Apple Menu — Cinnamon Applet
 * UUID: applemenu@macos
 *
 * Panel target: 20px
 *
 * Features:
 * - Smaller icon (14px) + spacing between icon and label (macOS-like)
 * - Label next to icon: active application name (fallback "Finder")
 * - Force Quit… launches external script forcekill.py
 * - Restart/Shut Down/Log Out use Cinnamon-native dialogs via cinnamon-session-quit
 * - About This Computer opens mintreport
 * - App Store... opens mintinstall
 * - Recent Items submenu placeholder
 * - Log Out shows username
 */
const Gio = imports.gi.Gio;
const Applet = imports.ui.applet;
const PopupMenu = imports.ui.popupMenu;
const Util = imports.misc.util;
const Settings = imports.ui.settings;
const GLib = imports.gi.GLib;

function spawn(cmd) {
  Util.spawnCommandLine(cmd);
}

function getWmClass(w) {
  // Best-effort: class instance first, then class
  try {
    if (w.get_wm_class_instance) {
      let inst = w.get_wm_class_instance();
      if (inst && inst.length) return inst;
    }
  } catch (e) {}
  try {
    if (w.get_wm_class) {
      let c = w.get_wm_class();
      if (c && c.length) return c;
    }
  } catch (e) {}
  return "";
}

function prettifyName(s) {
  if (!s) return "";
  // If all lowercase, Title-case first letter.
  if (s === s.toLowerCase()) return s.charAt(0).toUpperCase() + s.slice(1);  
  return s;
}

function shellQuote(s) {
  // comillas seguras para shell
  return "'" + String(s).replace(/'/g, "'\"'\"'") + "'";
}

class AppleMenuApplet extends Applet.TextIconApplet {
  constructor(metadata, orientation, panel_height, instance_id) {
    super(orientation, panel_height, instance_id);
    this._appletPath = metadata.path || GLib.build_filenamev([
      GLib.get_home_dir(),
      ".local/share/cinnamon/applets",
      metadata.uuid
    ]);

    this.setAllowedLayout(Applet.AllowedLayout.BOTH);

    this.settings = new Settings.AppletSettings(this, metadata.uuid, instance_id);
    this.settings.bind("icon-path", "iconPath", this._syncIcon.bind(this));

    this.set_applet_tooltip("Menu");

    this.menuManager = new PopupMenu.PopupMenuManager(this);
    this.menu = new Applet.AppletPopupMenu(this, orientation);
    this.menuManager.addMenu(this.menu);

    this._buildMenu();
    this._syncIcon();

    // ── Panel 20px tweaks (macOS-ish) ──────────────────────────────────────────
    // Icon size: 14px fits nicely in a 20px panel (Monterey vibe)
    try {
      if (this.set_applet_icon_size) this.set_applet_icon_size(14);
    } catch (e) {}
    try {
      if (this._applet_icon && this._applet_icon.set_icon_size) this._applet_icon.set_icon_size(14);
    } catch (e) {}
    // Space between icon and label
    try {
      if (this._label && this._label.set_style) this._label.set_style("padding-left: 6px;");
    } catch (e) {}
    // ─────────────────────────────────────────────────────────────────────────

    

    

  }

  _syncIcon() {
    try {
      if (this.iconPath && this.iconPath.trim().length > 0) {
        this.set_applet_icon_path(this.iconPath.trim());
        return;
      }
    } catch (e) {}
    this.set_applet_icon_symbolic_name("start-here-symbolic");
  }

  _buildMenu() {
    this.menu.removeAll();

    // About This Computer -> mintreport
    let aboutItem = new PopupMenu.PopupMenuItem("About This Computer");
    aboutItem.connect("activate", () => spawn("mintreport"));
    this.menu.addMenuItem(aboutItem);

    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

    // System Settings…
    let settingsItem = new PopupMenu.PopupMenuItem("System Settings…");
    settingsItem.connect("activate", () => spawn("cinnamon-settings"));
    this.menu.addMenuItem(settingsItem);

    // App Store...
    let appstoreItem = new PopupMenu.PopupMenuItem("App Store...");
    appstoreItem.connect("activate", () => spawn("mintinstall"));
    this.menu.addMenuItem(appstoreItem);

    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

    // Recent Items placeholder
    this.recentSubmenu = new PopupMenu.PopupSubMenuMenuItem("Recent Items");
    this.menu.addMenuItem(this.recentSubmenu);

    let recentPlaceholder = new PopupMenu.PopupMenuItem("(Coming soon)");
    recentPlaceholder.setSensitive(false);
    this.recentSubmenu.menu.addMenuItem(recentPlaceholder);

    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

    // Force Quit…
    this.forceQuit = new PopupMenu.PopupMenuItem("Force Quit…");
    this.forceQuit.connect("activate", () => {
      this.menu.close();
      GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
        this._Dialog("forcequit");
        return GLib.SOURCE_REMOVE;
      });
    });
    this.menu.addMenuItem(this.forceQuit);

    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

    // Sleep
    let sleepItem = new PopupMenu.PopupMenuItem("Sleep");
    sleepItem.connect("activate", () => spawn("systemctl suspend"));
    this.menu.addMenuItem(sleepItem);

    // Restart…
    let restartItem = new PopupMenu.PopupMenuItem("Restart…");
    restartItem.connect("activate", () => {
      this.menu.close();
      GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
        this._Dialog("restart");
        return GLib.SOURCE_REMOVE;
      });
    });
    this.menu.addMenuItem(restartItem);

    // Shut Down…
    let shutdownItem = new PopupMenu.PopupMenuItem("Shut Down…");
    shutdownItem.connect("activate", () => {
      this.menu.close();
      GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
        this._Dialog("shutdown");
        return GLib.SOURCE_REMOVE;
      });
    });
    this.menu.addMenuItem(shutdownItem);

    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

    // Lock Screen
    let lockItem = new PopupMenu.PopupMenuItem("Lock Screen");
    lockItem.connect("activate", () => spawn("cinnamon-screensaver-command -l"));
    this.menu.addMenuItem(lockItem);

    // Log Out <username>…
    let username = "User";
    try {
      username = GLib.get_user_name();
    } catch (e) {}

    let logoutItem = new PopupMenu.PopupMenuItem(`Log Out ${username}…`);
    logoutItem.connect("activate", () => {
      this.menu.close();
      GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
        this._Dialog("logoff");
        return GLib.SOURCE_REMOVE;
      });
    });
    this.menu.addMenuItem(logoutItem);

  }

 _Dialog(mode) {
  // Ruta al script
  const scriptPath = GLib.build_filenamev([this._appletPath, "applemenu.py"]);   
  const argv = ["python3", scriptPath, "--mode", mode, "--print-json"];

  global.log(`[AppleMenu] launching dialog: ${mode}`);

  let proc;
  try {
    proc = new Gio.Subprocess({
      argv,
      flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
    });
    proc.init(null);
  } catch (e) {
    global.logError(e, `[AppleMenu] failed to spawn dialog: ${mode}`);
    return;
  }

  proc.communicate_utf8_async(null, null, (p, res) => {
    try {
      const [, stdout, stderr] = p.communicate_utf8_finish(res);

      if (stderr && stderr.trim().length) {
        global.log(`[AppleMenu] ${mode} stderr:\n${stderr.trim()}`);
      }

      const out = (stdout || "").trim();
      if (!out.length) {
        global.log(`[AppleMenu] ${mode} finished: no stdout`);
        return;
      }

      // JSON del script (confirmed/executed/etc.)
      try {
        const obj = JSON.parse(out);
        global.log(`[AppleMenu] ${mode} result: ${out}`);
        // Si quieres algo más legible:
        // global.log(`[AppleMenu] confirmed=${obj.confirmed} executed=${obj.executed} reopen=${obj.reopen}`);
      } catch (e) {
        global.logError(e, `[AppleMenu] ${mode} stdout not JSON: ${out}`);
      }
    } catch (e) {
      global.logError(e, `[AppleMenu] error reading ${mode} output`);
    }
  });
}


  on_applet_clicked() {
    this.menu.toggle();
  }

  on_applet_removed_from_panel() {
    if (this._focusSig) {
      try { global.display.disconnect(this._focusSig); } catch (e) {}
    }
    if (this._timer) {
      try { GLib.source_remove(this._timer); } catch (e) {}
    }
    if (this.settings) this.settings.finalize();
  }
}

function main(metadata, orientation, panel_height, instance_id) {
  return new AppleMenuApplet(metadata, orientation, panel_height, instance_id);
}
