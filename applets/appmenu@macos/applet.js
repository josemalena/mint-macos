/*
 * Application Menu (macOS-style) — Cinnamon Applet
 * UUID: appmenu@macos
 *
 * What it does:
 * - Shows focused app name (WM_CLASS), fallback "Finder"
 * - Treats nemo-desktop as Finder
 * - Menu items:
 *    - Quit <App>…  (kills process tree of focused PID: TERM then KILL)
 *    - About <App>… (shows dialog with PID, exe, cmdline, dpkg package/version if available)
 *
 * Notes:
 * - No dependency on imports.ui.windowTracker (some Cinnamon builds lack it).
 */

const Applet = imports.ui.applet;
const PopupMenu = imports.ui.popupMenu;
const Util = imports.misc.util;
const Settings = imports.ui.settings;
const GLib = imports.gi.GLib;
const St = imports.gi.St;
const ModalDialog = imports.ui.modalDialog;

function spawn(cmd) {
  Util.spawnCommandLine(cmd);
}

function shellQuote(s) {
  return "'" + String(s).replace(/'/g, "'\"'\"'") + "'";
}

function readFileTrim(path) {
  try {
    let [ok, bytes] = GLib.file_get_contents(path);
    if (!ok) return "";
    return (imports.byteArray.toString(bytes) || "").trim();
  } catch (e) {
    return "";
  }
}

function getWmClass(w) {
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
  if (s === s.toLowerCase()) return s.charAt(0).toUpperCase() + s.slice(1);
  return s;
}

function procNameFromPid(pid) {
  let name = readFileTrim(`/proc/${pid}/comm`);
  if (name) return name;
  try {
    let exe = GLib.file_read_link(`/proc/${pid}/exe`);
    if (exe) {
      let parts = exe.split("/");
      return parts[parts.length - 1] || "";
    }
  } catch (e) {}
  return "";
}

function getFocusedWindow() {
  try { return global.display.get_focus_window ? global.display.get_focus_window() : null; }
  catch (e) { return null; }
}

function isDesktopWindow(w) {
  try { return (w && w.get_window_type && w.get_window_type() === 6); }
  catch (e) { return false; }
}

function getFocusedPid() {
  let w = getFocusedWindow();
  if (!w || isDesktopWindow(w)) return 0;
  try { return w.get_pid ? w.get_pid() : 0; } catch (e) { return 0; }
}

function killProcessTree(pid) {
  const root = Number(pid);
  if (!root || root <= 0) return;

  const qpid = shellQuote(String(root));

  const bash = `
set -e
ROOT=${qpid}

collect_children_pgrep() { local p="$1"; pgrep -P "$p" 2>/dev/null || true; }
collect_children_proc()  { local p="$1"; local f="/proc/$p/task/$p/children"; [ -r "$f" ] && cat "$f" 2>/dev/null || true; }

collect_all() {
  local queue="$1"
  local out=""
  while [ -n "$queue" ]; do
    local p="\${queue%% *}"
    queue="\${queue#* }"
    [ -z "$p" ] && continue
    out="$out $p"

    local kids=""
    kids="$(collect_children_pgrep "$p")"
    [ -z "$kids" ] && kids="$(collect_children_proc "$p")"

    for k in $kids; do queue="$queue $k"; done
  done
  echo "$out"
}

PIDS="$(collect_all "$ROOT")"

# TERM children-first
for p in $(echo "$PIDS" | awk '{for(i=NF;i>=1;i--) printf $i" ";}'); do
  kill -TERM "$p" 2>/dev/null || true
done

sleep 1.2

# KILL children-first
for p in $(echo "$PIDS" | awk '{for(i=NF;i>=1;i--) printf $i" ";}'); do
  kill -KILL "$p" 2>/dev/null || true
done
`;
  spawn(`bash -lc ${shellQuote(bash)}`);
}

class AboutAppDialog extends ModalDialog.ModalDialog {
  constructor(title, bodyText) {
    super({ styleClass: null });

    this.contentLayout.add(new St.Label({
      text: title,
      style_class: "dialog-title",
      x_align: St.Align.START
    }));

    let scroll = new St.ScrollView({ style_class: "vfade", overlay_scrollbars: true });
    let label = new St.Label({
      text: bodyText,
      style_class: "dialog-description",
      x_align: St.Align.START
    });
    label.clutter_text.line_wrap = true;
    label.clutter_text.selectable = true;

    scroll.add_actor(label);
    this.contentLayout.add(scroll);

    this.setButtons([
      {
        label: "OK",
        action: () => this.close(),
        key: 0
      }
    ]);
  }
}

class AppMenuApplet extends Applet.TextApplet {
  constructor(metadata, orientation, panel_height, instance_id) {
    super(orientation, panel_height, instance_id);

    this.settings = new Settings.AppletSettings(this, metadata.uuid, instance_id);
    this.settings.bind("fallback-label", "fallbackLabel", this._updateLabel.bind(this));
    this.settings.bind("label-padding-left", "labelPaddingLeft", this._applyLabelStyle.bind(this));

    this.set_applet_tooltip("Application Menu");

    this.menuManager = new PopupMenu.PopupMenuManager(this);
    this.menu = new Applet.AppletPopupMenu(this, orientation);
    this.menuManager.addMenu(this.menu);

    this._buildMenu();
    this._applyLabelStyle();
    this._updateLabel();

    // Update label + menu texts on focus change
    this._focusSig = 0;
    try {
      this._focusSig = global.display.connect("notify::focus-window", () => {
        this._updateLabel();
        this._updateMenuLabels();
      });
    } catch (e) {
      this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
        this._updateLabel();
        this._updateMenuLabels();
        return true;
      });
    }

    this.menu.connect("open-state-changed", (_m, open) => {
      if (open) this._updateMenuLabels();
    });
  }

  _applyLabelStyle() {
    try {
      let px = Number(this.labelPaddingLeft ?? 6);
      this._label.set_style(`padding-left: ${px}px; padding-right: 4px;`);
    } catch (e) {}
  }

  _getFocusedAppName() {
    let fallback = (this.fallbackLabel && this.fallbackLabel.length) ? this.fallbackLabel : "Finder";

    let w = getFocusedWindow();
    if (!w || isDesktopWindow(w)) return fallback;

    let cls = getWmClass(w);
    if (!cls) return fallback;

    let norm = cls.toLowerCase();
    if (norm === "nemo-desktop") return fallback;

    return prettifyName(cls);
  }

  _updateLabel() {
    this.set_applet_label(this._getFocusedAppName());
  }

  _buildMenu() {
    this.menu.removeAll();

    this.quitItem = new PopupMenu.PopupMenuItem("Quit…");
    this.quitItem.connect("activate", () => {
      this.menu.close();
      let pid = getFocusedPid();
      if (pid > 0) killProcessTree(pid);
    });
    this.menu.addMenuItem(this.quitItem);

    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

    this.aboutItem = new PopupMenu.PopupMenuItem("About…");
    this.aboutItem.connect("activate", () => {
      this.menu.close();
      this._showAboutDialog();
    });
    this.menu.addMenuItem(this.aboutItem);
  }

  _updateMenuLabels() {
    let name = this._getFocusedAppName();
    this.quitItem.label.text = `Quit ${name}…`;
    this.aboutItem.label.text = `About ${name}…`;
  }

  _showAboutDialog() {
    let w = getFocusedWindow();
    let name = this._getFocusedAppName();

    if (!w || isDesktopWindow(w)) {
      let dlg = new AboutAppDialog(`About ${name}`, "No focused application window.");
      dlg.open();
      return;
    }

    let pid = getFocusedPid();
    let comm = pid > 0 ? procNameFromPid(pid) : "";
    let exe = pid > 0 ? (() => { try { return GLib.file_read_link(`/proc/${pid}/exe`); } catch (e) { return ""; } })() : "";
    let cmdline = pid > 0 ? readFileTrim(`/proc/${pid}/cmdline`).split("\u0000").filter(Boolean).join(" ") : "";

    // Best-effort: dpkg package/version for the exe path (Mint/Ubuntu/Debian)
    let pkgInfo = "Package: N/A\nVersion: N/A\n";
    try {
      if (exe && exe.length) {
        let tmp = GLib.build_filenamev([GLib.get_tmp_dir(), `appmenu_about_${pid}.txt`]);
        let qtmp = shellQuote(tmp);
        let qexe = shellQuote(exe);

        // dpkg -S maps file -> package; dpkg-query prints version/details.
        let bash = `
set -e
EXE=${qexe}
OUT=${qtmp}
PKG="$(dpkg -S "$EXE" 2>/dev/null | head -n1 | cut -d: -f1 || true)"
if [ -n "$PKG" ]; then
  VER="$(dpkg-query -W -f='${Version}' "$PKG" 2>/dev/null || true)"
  echo "Package: $PKG" > "$OUT"
  echo "Version: $VER" >> "$OUT"
  echo "" >> "$OUT"
  dpkg-query -W -f='Description:\n${Description}\n' "$PKG" 2>/dev/null >> "$OUT" || true
else
  echo "Package: N/A" > "$OUT"
  echo "Version: N/A" >> "$OUT"
fi
`;
        spawn(`bash -lc ${shellQuote(bash)}`);

        // Read after a short delay
        GLib.timeout_add(GLib.PRIORITY_DEFAULT, 150, () => {
          let txt = readFileTrim(tmp);
          if (txt) pkgInfo = txt;
          try { GLib.unlink(tmp); } catch (e) {}

          let body =
`App: ${name}
PID: ${pid}
Process: ${comm || "N/A"}
Executable: ${exe || "N/A"}

${pkgInfo}

Command line:
${cmdline || "N/A"}`;

          let dlg = new AboutAppDialog(`About ${name}`, body);
          dlg.open();
          return GLib.SOURCE_REMOVE;
        });
        return;
      }
    } catch (e) {}

    let body =
`App: ${name}
PID: ${pid}
Process: ${comm || "N/A"}
Executable: ${exe || "N/A"}

${pkgInfo}

Command line:
${cmdline || "N/A"}`;

    let dlg = new AboutAppDialog(`About ${name}`, body);
    dlg.open();
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
  return new AppMenuApplet(metadata, orientation, panel_height, instance_id);
}
