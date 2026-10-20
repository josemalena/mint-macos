// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * Accessibility: la lista de la izquierda con las secciones de Catalina (Vision, Hearing, Motor, General) y la página de la derecha
 * (captura 08-pref-com.apple.preference.universalaccess--Mouse). Lo que Cinnamon tiene se sirve con sus ajustes (Zoom = el magnificador,
 * Keyboard = teclas especiales, VoiceOver = el lector de pantalla, Display = el tamaño del cursor, Pointer Control = el doble clic y el
 * spring-loading de Fynder); lo que Linux no tiene (Voice Control, Switch Control, Captions, Audio, Descriptions, Spoken Content, Siri y el
 * atajo de accesibilidad) se dibuja en gris, como en una Mac sin esa función. PROVISIONAL: solo se tiene la captura de Pointer Control; el
 * resto de las páginas sale de la lista de la barra lateral y de sus ajustes, sin captura propia.
 */
namespace Preferencias {

    public class PanelAccessibility : Panel {
        const string A11Y_TECLADO = "org.cinnamon.desktop.a11y.keyboard";
        const string A11Y_APPS = "org.cinnamon.desktop.a11y.applications";
        const string A11Y_LUPA = "org.cinnamon.desktop.a11y.magnifier";
        const string FYNDER = "io.github.josemalena.fynder.preferences";
        bool prueba = Environment.get_variable ("MINT_ACCESIBILIDAD_PRUEBA") != null;
        bool cargando = false;
        Gtk.Stack paginas;

        // (grupo, título, clave de la página, disponible)
        const string[,] SECCIONES = {
            { "Vision", "VoiceOver", "voiceover", "1" },
            { "Vision", "Zoom", "zoom", "1" },
            { "Vision", "Display", "display", "1" },
            { "Vision", "Spoken Content", "spoken", "0" },
            { "Vision", "Descriptions", "descriptions", "0" },
            { "Hearing", "Audio", "audio", "0" },
            { "Hearing", "Captions", "captions", "0" },
            { "Motor", "Voice Control", "voicecontrol", "0" },
            { "Motor", "Keyboard", "keyboard", "1" },
            { "Motor", "Pointer Control", "pointer", "1" },
            { "Motor", "Switch Control", "switch", "0" },
            { "General", "Siri", "siri", "0" },
            { "General", "Shortcut", "shortcut", "0" }
        };

        public PanelAccessibility () {
            id = "com.apple.preference.universalaccess";
            nombre = "Accessibility";
            palabras = "accessibility, zoom, voiceover, keyboard, mouse, contrast, pointer control, spring-loading, sticky keys, cursor size";
            icono_tema = "preferences-desktop-accessibility";
        }

        static Gtk.Widget gris_acc (Gtk.Widget w, string motivo = "Not available on this computer.") {
            w.set_sensitive (false);
            w.set_tooltip_text (motivo);
            return w;
        }

        Gtk.Widget titulo_pagina (string texto) {
            var l = new Gtk.Label (texto);
            l.get_style_context ().add_class ("mp-titulo-negrita");
            l.halign = Gtk.Align.START;
            return l;
        }

        Gtk.CheckButton casilla (string texto, Settings? cfg, string clave) {
            var c = new Gtk.CheckButton.with_label (texto);
            bool hay = cfg != null && cfg.settings_schema.has_key (clave);
            c.active = hay && cfg.get_boolean (clave);
            c.sensitive = hay;
            if (hay) {
                c.toggled.connect (() => { if (!cargando && !prueba) cfg.set_boolean (clave, c.active); });
            }
            return c;
        }

        Gtk.Scale deslizador_acc (double minimo, double maximo, double valor, double paso, string izq, string der, owned EscalaCambioD al_cambiar) {
            var esc = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, minimo, maximo, paso);
            esc.draw_value = false;
            esc.set_value (valor);
            esc.set_size_request (210, -1);
            esc.add_mark (minimo, Gtk.PositionType.BOTTOM, izq);
            esc.add_mark (maximo, Gtk.PositionType.BOTTOM, der);
            esc.value_changed.connect (() => al_cambiar (esc.get_value ()));
            return esc;
        }

        public delegate void EscalaCambioD (double valor);

        Gtk.Widget pagina_vacia (string titulo) {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            caja.margin = 24;
            caja.pack_start (titulo_pagina (titulo), false, false, 0);
            var l = new Gtk.Label ("%s is not available on this computer.".printf (titulo));
            l.halign = Gtk.Align.START;
            caja.pack_start (gris_acc (l), false, false, 0);
            return caja;
        }

        Gtk.Widget pagina_pointer () {
            var tabs = new Gtk.Notebook ();
            var mouse = new Gtk.Box (Gtk.Orientation.VERTICAL, 18);
            mouse.margin = 24;

            // Double-click speed: el mismo ajuste que el panel Mouse (de lento, 900 ms, a rápido, 250 ms)
            var cfg_mouse = abrir_settings ("org.cinnamon.desktop.peripherals.mouse");
            var fila_dc = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            fila_dc.pack_start (new Gtk.Label ("Double-click speed:"), false, false, 0);
            double dc = cfg_mouse != null ? (900.0 - cfg_mouse.get_int ("double-click")) / 650.0 : 0.5;
            fila_dc.pack_start (deslizador_acc (0, 1, dc.clamp (0, 1), 0.01, "Slow", "Fast", (v) => {
                if (!cargando && !prueba && cfg_mouse != null) cfg_mouse.set_int ("double-click", (int) (900 - v * 650));
            }), false, false, 0);
            mouse.pack_start (fila_dc, false, false, 0);

            // Spring-loading delay: las dos claves de Fynder; sin ellas (Fynder viejo) el control sale en gris
            var cfg_f = abrir_settings (FYNDER);
            bool hay_resorte = cfg_f != null && cfg_f.settings_schema.has_key ("spring-loading") && cfg_f.settings_schema.has_key ("spring-loading-delay");
            var fila_sl = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            var activar = new Gtk.CheckButton.with_label ("Spring-loading delay:");
            activar.active = hay_resorte ? cfg_f.get_boolean ("spring-loading") : true;
            var desliza = deslizador_acc (0, 1, hay_resorte ? cfg_f.get_double ("spring-loading-delay") : 0.5, 0.01, "Short", "Long", (v) => {
                if (!cargando && !prueba && hay_resorte) cfg_f.set_double ("spring-loading-delay", v);
            });
            desliza.sensitive = activar.active;
            activar.toggled.connect (() => {
                desliza.sensitive = activar.active;
                if (!cargando && !prueba && hay_resorte) cfg_f.set_boolean ("spring-loading", activar.active);
            });
            fila_sl.pack_start (activar, false, false, 0);
            fila_sl.pack_start (desliza, false, false, 0);
            if (!hay_resorte) {
                gris_acc (fila_sl, "Spring-loading needs a newer Fynder.");
            }
            mouse.pack_start (fila_sl, false, false, 0);

            var opciones = new Gtk.Button.with_label ("Mouse Options…");
            opciones.halign = Gtk.Align.END;
            opciones.valign = Gtk.Align.END;
            opciones.vexpand = true;
            gris_acc (opciones, "Mouse Options (Ignore built-in trackpad, scroll speed and Control-scroll zoom) are not available on this computer.");
            mouse.pack_end (opciones, false, false, 0);

            tabs.append_page (mouse, new Gtk.Label ("Mouse & Trackpad"));
            var alt = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            alt.margin = 24;
            alt.pack_start (gris_acc (new Gtk.CheckButton.with_label ("Enable alternate pointer actions")), false, false, 0);
            tabs.append_page (alt, new Gtk.Label ("Alternate Control Methods"));
            return tabs;
        }

        Gtk.Widget pagina_keyboard () {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            caja.margin = 24;
            var cfg = abrir_settings (A11Y_TECLADO);
            caja.pack_start (titulo_pagina ("Keyboard"), false, false, 0);
            caja.pack_start (casilla ("Enable Sticky Keys", cfg, "stickykeys-enable"), false, false, 0);
            caja.pack_start (casilla ("Enable Slow Keys", cfg, "slowkeys-enable"), false, false, 0);
            caja.pack_start (casilla ("Enable Bounce Keys", cfg, "bouncekeys-enable"), false, false, 0);
            caja.pack_start (casilla ("Enable Mouse Keys", cfg, "mousekeys-enable"), false, false, 0);
            return caja;
        }

        Gtk.Widget pagina_zoom () {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
            caja.margin = 24;
            var apps = abrir_settings (A11Y_APPS);
            var lupa = abrir_settings (A11Y_LUPA);
            caja.pack_start (titulo_pagina ("Zoom"), false, false, 0);
            caja.pack_start (casilla ("Enable Zoom", apps, "screen-magnifier-enabled"), false, false, 0);
            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            fila.pack_start (new Gtk.Label ("Maximum zoom:"), false, false, 0);
            bool hay = lupa != null && lupa.settings_schema.has_key ("mag-factor");
            var d = deslizador_acc (1, 10, hay ? lupa.get_double ("mag-factor") : 2, 0.5, "1×", "10×", (v) => {
                if (!cargando && !prueba && hay) lupa.set_double ("mag-factor", v);
            });
            if (!hay) gris_acc (d);
            fila.pack_start (d, false, false, 0);
            caja.pack_start (fila, false, false, 0);
            return caja;
        }

        Gtk.Widget pagina_voiceover () {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            caja.margin = 24;
            caja.pack_start (titulo_pagina ("VoiceOver"), false, false, 0);
            caja.pack_start (casilla ("Enable VoiceOver (screen reader)", abrir_settings (A11Y_APPS), "screen-reader-enabled"), false, false, 0);
            return caja;
        }

        Gtk.Widget pagina_display () {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
            caja.margin = 24;
            caja.pack_start (titulo_pagina ("Display"), false, false, 0);
            var cfg = abrir_settings ("org.cinnamon.desktop.interface");
            bool hay = cfg != null && cfg.settings_schema.has_key ("cursor-size");
            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            fila.pack_start (new Gtk.Label ("Cursor size:"), false, false, 0);
            var d = deslizador_acc (16, 96, hay ? cfg.get_int ("cursor-size") : 24, 8, "Normal", "Large", (v) => {
                if (!cargando && !prueba && hay) cfg.set_int ("cursor-size", (int) v);
            });
            if (!hay) gris_acc (d);
            fila.pack_start (d, false, false, 0);
            caja.pack_start (fila, false, false, 0);
            return caja;
        }

        public override Gtk.Widget? construir () {
            var raiz = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            var cuerpo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);

            // La lista de la izquierda, con los títulos de grupo en gris
            var lista = new Gtk.ListBox ();
            lista.selection_mode = Gtk.SelectionMode.SINGLE;
            paginas = new Gtk.Stack ();
            string grupo_actual = "";
            var filas = new HashTable<Gtk.ListBoxRow, string> (direct_hash, direct_equal);
            for (int i = 0; i < SECCIONES.length[0]; i++) {
                if (SECCIONES[i, 0] != grupo_actual) {
                    grupo_actual = SECCIONES[i, 0];
                    var cab = new Gtk.ListBoxRow ();
                    cab.activatable = false;
                    cab.selectable = false;
                    var t = new Gtk.Label (grupo_actual);
                    t.halign = Gtk.Align.START;
                    t.margin_start = 10;
                    t.margin_top = 8;
                    t.get_style_context ().add_class ("dim-label");
                    cab.add (t);
                    lista.add (cab);
                }
                var fila = new Gtk.ListBoxRow ();
                var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                caja.margin = 4;
                caja.margin_start = 10;
                caja.pack_start (new Gtk.Image.from_icon_name (icono_tema, Gtk.IconSize.LARGE_TOOLBAR), false, false, 0);
                var nombre_l = new Gtk.Label (SECCIONES[i, 1]);
                nombre_l.halign = Gtk.Align.START;
                caja.pack_start (nombre_l, true, true, 0);
                fila.add (caja);
                lista.add (fila);
                filas.insert (fila, SECCIONES[i, 2]);

                Gtk.Widget pag;
                switch (SECCIONES[i, 2]) {
                case "voiceover": pag = pagina_voiceover (); break;
                case "zoom": pag = pagina_zoom (); break;
                case "display": pag = pagina_display (); break;
                case "keyboard": pag = pagina_keyboard (); break;
                case "pointer": pag = pagina_pointer (); break;
                default: pag = pagina_vacia (SECCIONES[i, 1]); break;
                }
                paginas.add_named (pag, SECCIONES[i, 2]);
            }
            lista.row_selected.connect ((f) => {
                if (f != null && filas.contains (f)) {
                    paginas.visible_child_name = filas[f];
                }
            });
            var marco = new Gtk.ScrolledWindow (null, null);
            marco.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            marco.set_size_request (200, 330);
            marco.add (lista);
            cuerpo.pack_start (marco, false, false, 0);
            cuerpo.pack_start (paginas, true, true, 0);
            raiz.pack_start (cuerpo, true, true, 0);

            var estado = new Gtk.CheckButton.with_label ("Show Accessibility status in menu bar");
            estado.margin_start = 10;
            gris_acc (estado, "The Accessibility status menu is not available on this computer.");
            raiz.pack_start (estado, false, false, 0);

            // Abre en Pointer Control (donde está lo que pidió José), o en la sección que pida abrir_por_nombre
            foreach (var f in filas.get_keys ()) {
                if (filas[f] == "pointer") {
                    lista.select_row (f);
                }
            }
            return raiz;
        }
    }
}
