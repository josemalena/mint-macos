#!/usr/bin/env python3
"""Tema «Constanza» de ULauncher, con el aspecto de Spotlight en Catalina oscuro.

    construir.py <Assets.car de SystemAppearance> [destino]

De ese catálogo saca el vector de la lupa (SearchMagGlass, versión oscura) y
lo dibuja a 20 y 40 px: la de Spotlight es más grande que la de la barra.
[destino] por omisión: ~/.config/ulauncher/user-themes/constanza.
La lupa se genera aquí desde el disco de la Mac; no va al repo.
"""
import json
import os
import sys

from PIL import Image

# Spotlight de Catalina, medido en una captura con la barra de menús de
# referencia (22 pt = 15 px, escala 0.70): barra de 680 × 54 pt, lupa de 20
# a 16 pt del borde, texto desde los 50 pt, letra de unos 26 px. Colores del
# modo oscuro: fondo translúcido, lupa gris y el azul de selección de macOS.
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
    font-size: 19.5pt;
    font-weight: 300;
    min-height: 42px;
    padding: 6px 12px 6px 50px;
    background-color: transparent;
    background-image: -gtk-scaled(url("lupa.png"), url("lupa@2.png"));
    background-repeat: no-repeat;
    background-position: 16px center;
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


def lupa(car_sistema, destino):
    """La lupa de Catalina dibujada de su vector a 20 y 40 px, en gris."""
    import struct
    import subprocess
    import tempfile
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "iconos"))
    import car
    pdf = None
    for atr, im in car.Catalogo(car_sistema).imagenes():
        if (im.faceta or im.nombre) == "SearchMagGlass" and im.pixeles == "PDF" and im.envoltura == "RAWD":
            if pdf is None or atr.get("apariencia"):
                pdf = im.datos[12:12 + struct.unpack("<I", im.datos[8:12])[0]]
    if pdf is None:
        raise SystemExit("  ✗ no está SearchMagGlass en el catálogo")
    with tempfile.TemporaryDirectory() as tmp:
        ent = os.path.join(tmp, "lupa.pdf")
        open(ent, "wb").write(pdf)
        for alto, nombre in ((20, "lupa.png"), (40, "lupa@2.png")):
            base = os.path.join(tmp, str(alto))
            subprocess.run(["pdftocairo", "-png", "-singlefile", "-transp", "-scale-to-y", str(alto),
                            "-scale-to-x", "-1", ent, base], check=True)
            img = Image.open(base + ".png").convert("RGBA")
            pintada = Image.new("RGBA", img.size, GRIS_LUPA + (0,))
            pintada.putalpha(img.getchannel("A"))
            pintada.save(os.path.join(destino, nombre))


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    car_sistema = sys.argv[1]
    destino = sys.argv[2] if len(sys.argv) == 3 else os.path.expanduser("~/.config/ulauncher/user-themes/constanza")
    os.makedirs(destino, exist_ok=True)
    lupa(car_sistema, destino)
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
