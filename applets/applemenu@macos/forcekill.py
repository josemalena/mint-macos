#!/usr/bin/env python3
import os
import re
import signal
import subprocess
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set, Tuple

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gio, GLib  # noqa


TITLE = "Force Quit Applications"
SUBTITLE = "If an app doesn’t respond for a while, select its name and click Force Quit."
HINT = "You can open this window by pressing Command-Option-Escape."


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
    # remove weird stuff
    s = re.sub(r"[_\-]+", " ", s)
    # title-ish
    if s == s.lower():
        s = s[:1].upper() + s[1:]
    return s


def _run_wmctrl() -> str:
    # wmctrl -lpGx:
    # 0x04600007  0  1234  X  Y  W  H  wmclass.instance  title...
    return subprocess.check_output(["wmctrl", "-lpGx"], text=True, stderr=subprocess.DEVNULL)


def _parse_wmctrl(text: str) -> List[Tuple[str, int, str, str]]:
    out = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split(None, 8)
        if len(parts) < 9:
            continue
        wid_hex = parts[0]
        # desktop = parts[1]  (not used)
        pid_s = parts[2]
        wmclass = parts[7]
        title = parts[8]
        try:
            pid = int(pid_s)
        except Exception:
            pid = -1
        if pid <= 0:
            continue

        # skip obvious desktop / panels if they appear
        low = title.lower()
        if "cinnamon" == wmclass.lower() and ("panel" in low or "applet" in low):
            continue

        out.append((wid_hex, pid, wmclass, title))
    return out


def _resolve_icon_and_name(wmclass: str) -> Tuple[str, str]:
    """
    Try to map WM_CLASS -> desktop app -> icon + display name.
    Fallback: prettify class.
    """
    # wmclass looks like: instance.class OR just class
    # We prefer the "class" portion if there is a dot
    cls = wmclass
    if "." in wmclass:
        cls = wmclass.split(".")[-1]
    cls_low = cls.lower()

    # Best-effort search in installed desktop apps
    # (Gio.DesktopAppInfo can look up by desktop id, but we don't have it)
    # So we iterate and match StartupWMClass or id-ish names.
    try:
        for appinfo in Gio.AppInfo.get_all():
            if not isinstance(appinfo, Gio.DesktopAppInfo):
                continue
            d: Gio.DesktopAppInfo = appinfo

            startup = d.get_startup_wm_class() or ""
            if startup and startup.lower() == cls_low:
                icon = d.get_icon()
                icon_name = icon.to_string() if icon else ""
                name = d.get_display_name() or d.get_name() or prettify(cls)
                return (icon_name, name)

            # fallback: match desktop id / executable-ish
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
        grouped.setdefault(wmclass, set()).add(pid)

    apps: List[AppEntry] = []
    for wmclass, pids_set in grouped.items():
        icon_name, name = _resolve_icon_and_name(wmclass)
        pids = sorted(list(pids_set))
        apps.append(AppEntry(wmclass_raw=wmclass, name=name, icon_name=icon_name, pids=pids))

    apps.sort(key=lambda a: a.name.lower())
    return apps


class ForceQuitWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title=TITLE)
        self.set_default_size(560, 420)
        self.set_border_width(12)

        self._apps: List[AppEntry] = collect_apps()
        self._selected: Optional[AppEntry] = None

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)

        subtitle = Gtk.Label(label=SUBTITLE)
        subtitle.set_xalign(0.0)
        subtitle.set_line_wrap(True)
        vbox.pack_start(subtitle, False, False, 0)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        vbox.pack_start(scroller, True, True, 0)

        self.listbox = Gtk.ListBox()
        self.listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.listbox.connect("row-selected", self._on_row_selected)
        scroller.add(self.listbox)

        self._populate()

        bottom = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        vbox.pack_start(bottom, False, False, 0)

        hint = Gtk.Label(label=HINT)
        hint.set_xalign(0.0)
        hint.set_line_wrap(True)
        hint.set_hexpand(True)
        bottom.pack_start(hint, True, True, 0)

        self.force_btn = Gtk.Button(label="Force Quit")
        self.force_btn.set_sensitive(False)
        self.force_btn.connect("clicked", self._on_force_quit)
        bottom.pack_start(self.force_btn, False, False, 0)

        self.connect("destroy", Gtk.main_quit)

    def _populate(self):
        for child in self.listbox.get_children():
            self.listbox.remove(child)

        if not self._apps:
            row = Gtk.ListBoxRow()
            lbl = Gtk.Label(label="No running applications")
            lbl.set_xalign(0.0)
            lbl.set_line_wrap(True)
            lbl.set_margin_top(8)
            lbl.set_margin_bottom(8)
            lbl.set_margin_start(8)
            lbl.set_margin_end(8)
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

            icon_name = app.icon_name or "application-x-executable"
            # icon_name may be "something-symbolic" or a full icon string; we try name first
            if isinstance(icon_name, str) and theme.has_icon(icon_name):
                img = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.DND)
            else:
                # fallback (works almost always)
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
            return False  # stop timer

        GLib.timeout_add(1200, kill_later)

        self.close()


def main():
    win = ForceQuitWindow()
    win.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()