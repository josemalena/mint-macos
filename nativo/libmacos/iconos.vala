/* Los íconos de las alertas, dibujados con cairo (ningún archivo de Apple). */
namespace MacOS {

    /** El círculo gris de Catalina con su signo en blanco, a 64 × 64: «restart», «shutdown» o, si no, la persona de Log Out. */
    public void dibujar_icono (Cairo.Context cr, string modo) {
        cr.set_source_rgb (139 / 255.0, 141 / 255.0, 142 / 255.0);
        cr.arc (32, 32, 32, 0, 2 * Math.PI);
        cr.fill ();
        cr.set_source_rgb (1, 1, 1);
        cr.set_line_width (2.6);
        cr.set_line_join (Cairo.LineJoin.ROUND);
        cr.set_line_cap (Cairo.LineCap.ROUND);
        if (modo == "restart") {
            // ◁ como en c42
            cr.move_to (20, 32);
            cr.line_to (41, 19.5);
            cr.line_to (41, 44.5);
            cr.close_path ();
            cr.stroke ();
        } else if (modo == "shutdown") {
            // ⏻: el arco con la raya arriba
            cr.arc (32, 33, 13, -Math.PI / 2 + 0.55, 3 * Math.PI / 2 - 0.55);
            cr.stroke ();
            cr.move_to (32, 16);
            cr.line_to (32, 31);
            cr.stroke ();
        } else {
            // La persona: Log Out cierra la sesión de alguien. En la captura 1.32.56 PM es una silueta llena
            // (cabeza y hombros en blanco) dentro del círculo gris, no un contorno.
            cr.save ();
            cr.arc (32, 32, 32, 0, 2 * Math.PI);
            cr.clip ();
            cr.new_path ();
            cr.arc (32, 25, 10.3, 0, 2 * Math.PI);
            cr.fill ();
            cr.save ();
            cr.translate (32, 56);
            cr.scale (19, 13);
            cr.arc (0, 0, 1, 0, 2 * Math.PI);
            cr.restore ();
            cr.fill ();
            cr.restore ();
        }
    }

    /** El triángulo amarillo de aviso, a 58 × 58: va dibujado, no es un archivo de Apple. */
    public void dibujar_aviso (Cairo.Context cr) {
        cr.set_line_join (Cairo.LineJoin.ROUND);
        cr.set_line_width (5);
        cr.set_source_rgb (0.93, 0.70, 0.05);
        cr.move_to (29, 3);
        cr.line_to (55, 51);
        cr.line_to (3, 51);
        cr.close_path ();
        cr.stroke_preserve ();
        cr.fill ();
        cr.set_source_rgb (0.10, 0.09, 0.05);
        cr.set_line_width (5);
        cr.set_line_cap (Cairo.LineCap.ROUND);
        cr.move_to (29, 20);
        cr.line_to (29, 35);
        cr.stroke ();
        cr.arc (29, 43, 3.0, 0, 2 * Math.PI);
        cr.fill ();
    }
}
