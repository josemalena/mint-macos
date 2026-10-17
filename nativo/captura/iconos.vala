/*
 * Los íconos de la barra, dibujados con cairo: ningún archivo de Apple.
 */
namespace Captura {
    void rect_redondo (Cairo.Context cr, double x, double y, double w, double h, double r) {
        cr.new_sub_path ();
        cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
        cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
        cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
        cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
        cr.close_path ();
    }

    public void dibujar_icono (Cairo.Context cr, string modo, int w, int h) {
        cr.set_source_rgba (0.93, 0.93, 0.93, 1);
        cr.set_line_width (1.4);
        double cx = w / 2.0, cy = h / 2.0;
        double[] guion = { 3, 2.4 };
        if (modo == "pantalla") {
            rect_redondo (cr, cx - 11, cy - 8, 22, 16, 3);
            cr.stroke ();
        } else if (modo == "ventana") {
            rect_redondo (cr, cx - 11, cy - 8, 22, 16, 3);
            cr.stroke ();
            cr.move_to (cx - 11, cy - 3.5);
            cr.line_to (cx + 11, cy - 3.5);
            cr.stroke ();
            for (int i = 0; i < 3; i++) {
                cr.arc (cx - 8 + i * 3.2, cy - 5.8, 0.8, 0, 2 * Math.PI);
                cr.fill ();
            }
        } else if (modo == "porcion") {
            cr.set_dash (guion, 0);
            rect_redondo (cr, cx - 11, cy - 8, 22, 16, 2);
            cr.stroke ();
            cr.set_dash (null, 0);
        } else if (modo == "grabar-pantalla" || modo == "grabar-porcion") {
            if (modo == "grabar-porcion") cr.set_dash (guion, 0);
            rect_redondo (cr, cx - 11, cy - 8, 22, 16, 3);
            cr.stroke ();
            cr.set_dash (null, 0);
            cr.set_source_rgba (0.17, 0.17, 0.18, 1);
            cr.arc (cx + 8, cy + 6, 6, 0, 2 * Math.PI);
            cr.fill ();
            cr.set_source_rgba (0.93, 0.93, 0.93, 1);
            cr.arc (cx + 8, cy + 6, 5, 0, 2 * Math.PI);
            cr.stroke ();
            cr.arc (cx + 8, cy + 6, 2.4, 0, 2 * Math.PI);
            cr.fill ();
        } else if (modo == "cerrar") {
            cr.set_source_rgba (0.55, 0.55, 0.57, 1);
            cr.arc (cx, cy, 7, 0, 2 * Math.PI);
            cr.fill ();
            cr.set_source_rgba (0.15, 0.15, 0.16, 1);
            cr.set_line_width (1.5);
            cr.move_to (cx - 2.6, cy - 2.6); cr.line_to (cx + 2.6, cy + 2.6);
            cr.move_to (cx + 2.6, cy - 2.6); cr.line_to (cx - 2.6, cy + 2.6);
            cr.stroke ();
        }
    }

    public Gtk.DrawingArea area_icono (string modo, int ancho = 40, int alto = 30) {
        var a = new Gtk.DrawingArea ();
        a.set_size_request (ancho, alto);
        a.draw.connect ((cr) => {
            dibujar_icono (cr, modo, a.get_allocated_width (), a.get_allocated_height ());
            return false;
        });
        return a;
    }

    /** Cámara fotográfica de 32 × 32 dibujada con cairo (punto activo en el centro). */
    public Gdk.Cursor cursor_camara (Gdk.Display display) {
        var s = new Cairo.ImageSurface (Cairo.Format.ARGB32, 32, 32);
        var cr = new Cairo.Context (s);
        rect_redondo (cr, 3, 9, 26, 17, 3);
        cr.new_sub_path ();
        cr.move_to (11, 9); cr.line_to (13, 5); cr.line_to (19, 5); cr.line_to (21, 9); cr.close_path ();
        cr.set_source_rgba (1, 1, 1, 1);
        cr.set_line_width (4);
        cr.stroke_preserve ();
        cr.set_source_rgba (0.1, 0.1, 0.1, 1);
        cr.fill ();
        cr.arc (16, 17.5, 5.5, 0, 2 * Math.PI);
        cr.set_source_rgba (1, 1, 1, 1);
        cr.fill ();
        cr.arc (16, 17.5, 3.2, 0, 2 * Math.PI);
        cr.set_source_rgba (0.1, 0.1, 0.1, 1);
        cr.fill ();
        return new Gdk.Cursor.from_surface (display, s, 16, 17);
    }
}
