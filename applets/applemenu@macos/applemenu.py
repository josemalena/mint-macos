#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
macOS-style dialogs (theme-driven, NO CSS) for Cinnamon/Mint using GTK3.

Modes:
  - forcequit : "Force Quit Applications" window; auto-builds app list using wmctrl (X11),
               ignores Plank, maps nemo-desktop -> Finder with Nemo icon from current theme,
               and does TERM then KILL on selected app PIDs.
  - shutdown  : confirmation dialog like macOS shutdown (custom icon from script-relative path)
  - restart   : confirmation dialog like macOS restart  (custom icon from script-relative path)
  - logoff    : confirmation dialog like macOS logout   (custom icon from script-relative path)

Notes:
  - Visual styling relies on your GTK theme (you said it already matches macOS).
  - forcequit list generation requires X11 and `wmctrl -lpGx`.
  - "Reopen windows..." checkbox is captured; on Linux there is no universal equivalent,
    so we print it to stdout as JSON for your applet (optional use). We don't enforce it.

CLI examples:
  Force Quit:
    python3 macos_dialogs.py --mode forcequit

  Shutdown with 60s countdown:
    python3 macos_dialogs.py --mode shutdown --seconds 60 --icon icons/shutdown.png

  Restart:
    python3 macos_dialogs.py --mode restart --seconds 60 --icon icons/restart.png

  Log out:
    python3 macos_dialogs.py --mode logoff --seconds 60 --icon icons/logoff.png
"""

import argparse
import json
import os
import re
import signal
import subprocess
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set, Tuple

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gio, GLib, Gdk  # noqa: E402


# ──────────────────────────────────────────────────────────────────────────────
# Force Quit strings
# ──────────────────────────────────────────────────────────────────────────────
FQ_TITLE = "Force Quit Applications"
FQ_SUBTITLE = "If an app doesn’t respond for a while, select its name and click Force Quit."
FQ_HINT = "You can open this window by pressing Command-Option-Escape."


# ──────────────────────────────────────────────────────────────────────────────
# Confirm dialog presets (wording follows your screenshots)
# ──────────────────────────────────────────────────────────────────────────────
CONF_PRESETS: Dict[str, Dict[str, object]] = {
    "shutdown": {
        "title": "Are you sure you want to shut down your computer now?",
        "countdown": "If you do nothing, the computer will shut down automatically\nin {n} seconds.",
        "action_label": "Shut Down",
        "default_reopen": True,
        "default_icon_rel": "icons/shutdown.png",
        "primary_cmd": ["cinnamon-session-quit", "--power-off", "--no-prompt"],
        "fallback_cmds": [
            ["systemctl", "poweroff"],
            ["shutdown", "-h", "now"],
        ],
    },
    "restart": {
        "title": "Are you sure you want to restart your computer now?",
        "countdown": "If you do nothing, the computer will restart automatically\nin {n} seconds.",
        "action_label": "Restart",
        "default_reopen": True,
        "default_icon_rel": "icons/restart.png",
        "primary_cmd": ["cinnamon-session-quit", "--reboot", "--no-prompt"],
        "fallback_cmds": [
            ["systemctl", "reboot"],
            ["shutdown", "-r", "now"],
        ],
    },
    "logoff": {
        "title": "Are you sure you want to quit all applications\nand log out now?",
        "countdown": "If you do nothing, you will be logged out automatically in\n{n} seconds.",
        "action_label": "Log Out",
        "default_reopen": False,
        "default_icon_rel": "icons/logoff.png",
        "primary_cmd": ["cinnamon-session-quit", "--logout", "--no-prompt"],
        "fallback_cmds": [
            # fallback: ask cinnamon-session-quit without --no-prompt (some builds)
            ["cinnamon-session-quit", "--logout"],
        ],
    },
}


DEFAULT_COUNTDOWN_SECONDS = 60


# ──────────────────────────────────────────────────────────────────────────────
# Force Quit: data + collection (wmctrl)
# ──────────────────────────────────────────────────────────────────────────────
@dataclass
class AppEntry:
    wmclass_raw: str
    name: str
    icon_name: str
    pids: List[int] = field(default_factory=list)


def prettify(s: str) -> str:
    if not s:
        return ""
    s = s.strip()
    s = re.sub(r"[_\-]+", " ", s)
    if s == s.lower():
        s = s[:1].upper() + s[1:]
    return s


def _run_wmctrl() -> str:
    return subprocess.check_output(["wmctrl", "-lpGx"], text=True, stderr=subprocess.DEVNULL)


def _parse_wmctrl(text: str) -> List[Tuple[str, int, str, str]]:
    out: List[Tuple[str, int, str, str]] = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue

        parts = line.split(None, 8)
        if len(parts) < 9:
            continue

        wid_hex = parts[0]
        pid_s = parts[2]
        wmclass = parts[7] or ""
        title = parts[8] or ""

        # Ignore Plank (any variant)
        if "plank" in wmclass.lower() or "plank" in title.lower():
            continue

        try:
            pid = int(pid_s)
        except Exception:
            pid = -1
        if pid <= 0:
            continue

        out.append((wid_hex, pid, wmclass, title))
    return out


def _resolve_icon_and_name(wmclass: str) -> Tuple[str, str]:
    """
    Map WM_CLASS -> (icon_name, display_name)
    Special cases:
      - nemo-desktop => name "Finder" + icon from Nemo (theme-based)
    """
    cls = wmclass
    if "." in wmclass:
        cls = wmclass.split(".")[-1]
    cls_low = cls.lower().strip()

    # Special-case: nemo-desktop acts as Finder
    if cls_low == "nemo-desktop":
        return ("nemo", "Finder")

    # Best-effort: match DesktopAppInfo via StartupWMClass / desktop id
    try:
        for appinfo in Gio.AppInfo.get_all():
            if not isinstance(appinfo, Gio.DesktopAppInfo):
                continue
            d: Gio.DesktopAppInfo = appinfo

            startup = (d.get_startup_wm_class() or "").lower()
            if startup and startup == cls_low:
                icon = d.get_icon()
                icon_name = icon.to_string() if icon else ""
                name = d.get_display_name() or d.get_name() or prettify(cls)
                return (icon_name, name)

            app_id = (d.get_id() or "").lower()
            if app_id.startswith(cls_low) or cls_low in app_id:
                icon = d.get_icon()
                icon_name = icon.to_string() if icon else ""
                name = d.get_display_name() or d.get_name() or prettify(cls)
                return (icon_name, name)
    except Exception:
        pass

    return ("application-x-executable", prettify(cls))


def collect_apps() -> List[AppEntry]:
    try:
        raw = _run_wmctrl()
    except Exception:
        return []

    rows = _parse_wmctrl(raw)

    grouped: Dict[str, Set[int]] = {}
    for _wid, pid, wmclass, _title in rows:
        if "plank" in (wmclass or "").lower():
            continue
        grouped.setdefault(wmclass, set()).add(pid)

    apps: List[AppEntry] = []
    for wmclass, pids_set in grouped.items():
        if "plank" in (wmclass or "").lower():
            continue
        icon_name, name = _resolve_icon_and_name(wmclass)
        pids = sorted(list(pids_set))
        apps.append(AppEntry(wmclass_raw=wmclass, name=name, icon_name=icon_name, pids=pids))

    # Finder first, then alpha
    def sort_key(a: AppEntry):
        return (0 if a.name == "Finder" else 1, a.name.lower())

    apps.sort(key=sort_key)
    return apps


# ──────────────────────────────────────────────────────────────────────────────
# Force Quit window (GTK3)
# ──────────────────────────────────────────────────────────────────────────────
class ForceQuitWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title=FQ_TITLE)
        # macOS reference size: ~360x390, resizable
        self.set_default_size(360, 390)
        self.set_resizable(True)
        # Hint as dialog so WM avoids maximize controls on Cinnamon themes.
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        self.set_border_width(12)
        self.connect("realize", self._on_realize_disable_maximize)

        self._apps: List[AppEntry] = collect_apps()
        self._selected: Optional[AppEntry] = None

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)

        subtitle = Gtk.Label(label=FQ_SUBTITLE)
        subtitle.set_xalign(0.0)
        subtitle.set_line_wrap(True)
        vbox.pack_start(subtitle, False, False, 0)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_hexpand(True)
        scroller.set_vexpand(True)
        vbox.pack_start(scroller, True, True, 0)

        self.listbox = Gtk.ListBox()
        self.listbox.set_hexpand(True)
        self.listbox.set_vexpand(True)
        self.listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.listbox.connect("row-selected", self._on_row_selected)
        scroller.add(self.listbox)

        self._populate()

        bottom = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        vbox.pack_start(bottom, False, False, 0)

        hint = Gtk.Label(label=FQ_HINT)
        hint.set_xalign(0.0)
        hint.set_line_wrap(True)
        hint.set_hexpand(True)
        bottom.pack_start(hint, True, True, 0)

        self.force_btn = Gtk.Button(label="Force Quit")
        self.force_btn.set_sensitive(False)
        self.force_btn.connect("clicked", self._on_force_quit)
        bottom.pack_start(self.force_btn, False, False, 0)

        self.connect("destroy", Gtk.main_quit)

    def _on_realize_disable_maximize(self, *_args):
        # Keep manual resize but disable maximize capability when supported by WM.
        try:
            gdk_win = self.get_window()
            if gdk_win is None:
                return
            funcs = Gdk.WMFunction.MOVE | Gdk.WMFunction.RESIZE | Gdk.WMFunction.CLOSE
            gdk_win.set_functions(funcs)
        except Exception:
            pass

    def _populate(self):
        for child in self.listbox.get_children():
            self.listbox.remove(child)

        if not self._apps:
            row = Gtk.ListBoxRow()
            lbl = Gtk.Label(label="No running applications")
            lbl.set_xalign(0.0)
            lbl.set_line_wrap(True)
            for m in ("top", "bottom", "start", "end"):
                getattr(lbl, f"set_margin_{m}")(8)
            row.add(lbl)
            row.set_selectable(False)
            self.listbox.add(row)
            self.listbox.show_all()
            return

        theme = Gtk.IconTheme.get_default()

        for app in self._apps:
            row = Gtk.ListBoxRow()
            row._app = app  # type: ignore

            h = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            h.set_margin_top(6)
            h.set_margin_bottom(6)
            h.set_margin_start(10)
            h.set_margin_end(10)

            icon_name = (app.icon_name or "").strip()
            img = None

            # 1) icon name exists in theme
            if icon_name and theme.has_icon(icon_name):
                img = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.DND)

            # 2) icon string looks like a path
            if img is None and icon_name.startswith("/"):
                try:
                    img = Gtk.Image.new_from_file(icon_name)
                except Exception:
                    img = None

            # 3) fallback
            if img is None:
                img = Gtk.Image.new_from_icon_name("application-x-executable", Gtk.IconSize.DND)

            img.set_pixel_size(20)
            h.pack_start(img, False, False, 0)

            lbl = Gtk.Label(label=app.name)
            lbl.set_xalign(0.0)
            lbl.set_hexpand(True)
            lbl.set_ellipsize(3)  # END
            h.pack_start(lbl, True, True, 0)

            row.add(h)
            self.listbox.add(row)

        self.listbox.show_all()

    def _on_row_selected(self, _lb, row):
        self._selected = None
        self.force_btn.set_sensitive(False)
        if not row:
            return
        app = getattr(row, "_app", None)
        if isinstance(app, AppEntry) and app.pids:
            self._selected = app
            self.force_btn.set_sensitive(True)

    def _on_force_quit(self, _btn):
        if not self._selected or not self._selected.pids:
            return

        pids = list(self._selected.pids)

        # TERM then (after 1.2s) KILL
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except Exception:
                pass

        def kill_later():
            for pid in pids:
                try:
                    os.kill(pid, signal.SIGKILL)
                except Exception:
                    pass
            return False

        GLib.timeout_add(1200, kill_later)
        self.close()


# ──────────────────────────────────────────────────────────────────────────────
# Confirmation dialog (Shutdown / Restart / Log Out)
# ──────────────────────────────────────────────────────────────────────────────
class ConfirmDialog(Gtk.Dialog):
    """
    Layout:
      [ icon ]  [ big bold title ]
              [ countdown text ]
              [ checkbox reopen windows ]
                        [ Cancel ] [ Action ]
    """
    def __init__(self, mode: str, countdown_seconds: int, icon_path: str, reopen_default: bool):
        if mode not in CONF_PRESETS:
            raise ValueError(f"Unknown mode: {mode}")

        self.mode = mode
        self.p = CONF_PRESETS[mode]
        self.remaining = max(1, int(countdown_seconds))
        self.reopen_default = bool(reopen_default)

        super().__init__(title="", flags=Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT)
        # macOS reference size: ~450x200, fixed size
        self.set_default_size(450, 200)
        self.set_size_request(450, 200)
        self.set_border_width(16)
        self.set_resizable(False)
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)

        # Buttons (Cancel left, Action right)
        self.add_button("Cancel", Gtk.ResponseType.CANCEL)
        self.action_button = self.add_button(str(self.p["action_label"]), Gtk.ResponseType.OK)
        self.set_default_response(Gtk.ResponseType.OK)

        content = self.get_content_area()
        content.set_spacing(12)

        # Main horizontal layout (icon left, text right)
        h = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=18)
        content.pack_start(h, True, True, 0)

        # Icon
        img = self._load_icon(icon_path)
        # Align top like macOS dialogs
        icon_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        icon_box.pack_start(img, False, False, 0)
        h.pack_start(icon_box, False, False, 0)

        # Right side
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        h.pack_start(right, True, True, 0)

        title_lbl = Gtk.Label()
        title_lbl.set_xalign(0.0)
        title_lbl.set_line_wrap(True)
        title_lbl.set_markup(f"<b>{GLib.markup_escape_text(str(self.p['title']))}</b>")
        right.pack_start(title_lbl, False, False, 0)

        self.countdown_lbl = Gtk.Label()
        self.countdown_lbl.set_xalign(0.0)
        self.countdown_lbl.set_line_wrap(True)
        right.pack_start(self.countdown_lbl, False, False, 0)

        self.reopen_cb = Gtk.CheckButton.new_with_label("Reopen windows when logging back in")
        self.reopen_cb.set_active(self.reopen_default)
        right.pack_start(self.reopen_cb, False, False, 0)

        self._timer_id = GLib.timeout_add(1000, self._tick)
        self._update_countdown()

        self.connect("destroy", self._on_destroy)
        self.show_all()

    def _load_icon(self, icon_path: str) -> Gtk.Image:
        # If path doesn't exist, fallback to a symbolic icon (still theme-driven)
        try:
            if icon_path and os.path.exists(icon_path):
                img = Gtk.Image.new_from_file(icon_path)
                # try to size-ish (GTK will keep aspect)
                img.set_pixel_size(64)
                return img
        except Exception:
            pass

        # fallback to theme icon based on mode
        fallback_icon = "system-shutdown" if self.mode == "shutdown" else "view-refresh" if self.mode == "restart" else "system-log-out"
        img = Gtk.Image.new_from_icon_name(fallback_icon, Gtk.IconSize.DIALOG)
        img.set_pixel_size(64)
        return img

    def _update_countdown(self):
        tmpl = str(self.p["countdown"])
        self.countdown_lbl.set_text(tmpl.format(n=self.remaining))

    def _tick(self):
        self.remaining -= 1
        if self.remaining <= 0:
            # Auto-confirm
            self.response(Gtk.ResponseType.OK)
            return False
        self._update_countdown()
        return True

    def _on_destroy(self, *_args):
        if self._timer_id:
            try:
                GLib.source_remove(self._timer_id)
            except Exception:
                pass
            self._timer_id = 0


def _run_command(cmd: List[str]) -> bool:
    try:
        subprocess.Popen(cmd)
        return True
    except Exception:
        return False


def execute_action(mode: str, reopen_windows: bool) -> bool:
    """
    Execute shutdown/restart/logoff. Returns True if we successfully launched a command.
    """
    preset = CONF_PRESETS[mode]
    primary = list(preset["primary_cmd"])  # type: ignore
    if _run_command(primary):
        return True

    for fb in preset.get("fallback_cmds", []):  # type: ignore
        if _run_command(list(fb)):
            return True

    return False


# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", required=True, choices=["forcequit", "shutdown", "restart", "logoff"])
    ap.add_argument("--seconds", type=int, default=DEFAULT_COUNTDOWN_SECONDS, help="Countdown seconds (confirm dialogs).")
    ap.add_argument("--icon", default="", help="Icon path (relative to script or absolute).")
    ap.add_argument("--print-json", action="store_true", help="Print result JSON to stdout (for applet).")
    args = ap.parse_args()

    if args.mode == "forcequit":
        win = ForceQuitWindow()
        win.show_all()
        Gtk.main()
        return 0

    # confirm dialogs:
    preset = CONF_PRESETS[args.mode]
    script_dir = os.path.dirname(os.path.abspath(__file__))

    icon_path = str(args.icon or "").strip()
    if not icon_path:
        icon_path = os.path.join(script_dir, str(preset["default_icon_rel"]))
    elif not os.path.isabs(icon_path):
        icon_path = os.path.join(script_dir, icon_path)

    dlg = ConfirmDialog(
        mode=args.mode,
        countdown_seconds=args.seconds,
        icon_path=icon_path,
        reopen_default=bool(preset.get("default_reopen", False)),
    )

    resp = dlg.run()
    reopen = bool(dlg.reopen_cb.get_active())
    dlg.destroy()

    did_execute = False
    if resp == Gtk.ResponseType.OK:
        did_execute = execute_action(args.mode, reopen)

    if args.print_json:
        out = {
            "mode": args.mode,
            "confirmed": (resp == Gtk.ResponseType.OK),
            "reopen": reopen,
            "executed": did_execute,
            "icon": icon_path,
            "seconds": int(args.seconds),
        }
        print(json.dumps(out, ensure_ascii=False))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
