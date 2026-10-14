#!/usr/bin/env python3
"""Tema «Constanza» de ULauncher, con el aspecto de Spotlight en Catalina oscuro.

    construir.py <carpeta de glifos> [destino]

<carpeta de glifos> es la que deja «car.py glifos --oscuro» (trae
SearchMagGlass@1x.png y @2x.png, la lupa de la barra de Catalina).
[destino] por omisión: ~/.config/ulauncher/user-themes/constanza.
La lupa se genera aquí desde el disco de la Mac; no va al repo.
"""
import json
import os
import sys

from PIL import Image

# Spotlight de Catalina, modo oscuro: barra ancha con esquinas de 10 px y
# fondo oscuro translúcido; el campo a 24 px; la lupa en gris claro; el
# resultado elegido con el azul de selección de macOS.
GRIS_LUPA = (152, 153, 155)        # #98999b, los glifos grises del Finder

CSS = """/* Constanza: ULauncher como Spotlight de Catalina (modo oscuro). */
@define-color bg_color rgba(36, 37, 39, 0.92);
@define-color window_bg @bg_color;
@define-color window_border_color rgba(255, 255, 255, 0.12);
@define-color prefs_backgroud rgba(255, 255, 255, 0.15);

@define-color selected_bg_color #0b57d0;
@define-color selected_fg_color #ffffff;
@define-color input_color #f2f2f2;
@define-color caret_color #ffffff;

@define-color item_name #f2f2f2;
@define-color item_text #9a9b9e;
@define-color item_box_selected #0b57d0;
@define-color item_text_selected rgba(255, 255, 255, 0.80);
@define-color item_name_selected #ffffff;
@define-color item_shortcut_color #8e8f93;
@define-color item_shortcut_shadow transparent;
@define-color item_shortcut_color_sel rgba(255, 255, 255, 0.85);
@define-color item_shortcut_shadow_sel transparent;

.app {
    background-color: @window_bg;
    border: 1px solid @window_border_color;
    border-radius: 10px;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.55), 0 0 0 1px rgba(0, 0, 0, 0.6);
}

.input {
    color: @input_color;
    font-family: ".SF NS", "Inter", sans-serif;
    font-size: 18pt;
    font-weight: 300;
    min-height: 40px;
    padding: 6px 8px 6px 46px;
    background-color: transparent;
    background-image: -gtk-scaled(url("lupa.png"), url("lupa@2.png"));
    background-repeat: no-repeat;
    background-position: 12px center;
    border: none;
    box-shadow: none;
}
.input *:selected,
.input *:focus,
*:selected:focus {
    background-color: alpha(@selected_bg_color, 0.85);
    color: @selected_fg_color;
}

.result-box { border-top: 1px solid rgba(255, 255, 255, 0.08); }

.item-box { border-radius: 5px; margin: 0 6px; }
.item-name {
    color: @item_name;
    font-family: ".SF NS", "Inter", sans-serif;
    font-size: 10.5pt;
}
.item-text { color: @item_text; }
.item-descr { font-size: 9pt; }
.selected.item-box { background-color: @item_box_selected; border: none; }
.selected.item-box .item-text { color: @item_text_selected; }
.selected.item-box .item-name { color: @item_name_selected; }
.item-shortcut { color: @item_shortcut_color; text-shadow: none; }
.selected.item-box .item-shortcut { color: @item_shortcut_color_sel; text-shadow: none; }

.small-result-item .item-name { font-size: 10.5pt; }

.prefs-btn { border-radius: 12px; opacity: 0.45; }
.prefs-btn:hover { background-color: @prefs_backgroud; opacity: 0.9; }

.no-window-shadow { margin: -20px; }
"""


def lupa(origen, destino):
    img = Image.open(origen).convert("RGBA")
    pintada = Image.new("RGBA", img.size, GRIS_LUPA + (0,))
    pintada.putalpha(img.getchannel("A"))
    pintada.save(destino)


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    glifos = sys.argv[1]
    destino = sys.argv[2] if len(sys.argv) == 3 else os.path.expanduser("~/.config/ulauncher/user-themes/constanza")
    os.makedirs(destino, exist_ok=True)
    for esc, nombre in (("1x", "lupa.png"), ("2x", "lupa@2.png")):
        lupa(os.path.join(glifos, f"SearchMagGlass@{esc}.png"), os.path.join(destino, nombre))
    with open(os.path.join(destino, "theme.css"), "w") as f:
        f.write(CSS)
    with open(os.path.join(destino, "theme-gtk-3.20.css"), "w") as f:
        f.write('@import url("theme.css");\n\n.input { caret-color: @caret_color; }\n'
                '.selected.item-box { border: none; }\n')
    with open(os.path.join(destino, "manifest.json"), "w") as f:
        json.dump({"manifest_version": "1", "name": "constanza", "display_name": "Constanza",
                   "extend_theme": "dark", "css_file": "theme.css",
                   "css_file_gtk_3.20+": "theme-gtk-3.20.css",
                   "matched_text_hl_colors": {"when_selected": "#ffffff", "when_not_selected": "#ffffff"}},
                  f, indent=4)
    print(f"  tema de ULauncher: {destino}")


if __name__ == "__main__":
    main()
