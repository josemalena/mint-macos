/*
 * El fondo del Launchpad: el escritorio desenfocado y oscurecido con la receta medida contra la captura de Catalina:
 * gaussiano de ~30 px y, por canal, y = a·x + k (error medio 1.6 de 255). Se guarda en caché por archivo, fecha y tamaño.
 */
namespace Launchpad {
    public const int REF_W = 1920;
    public const int REF_H = 1200;
    const double FONDO_BLUR = 30.0;
    const double[] FONDO_A = { 0.344, 0.499, 0.649 };
    const double[] FONDO_K = { 9.3, 14.4, 14.9 };

    string? fondo_de_escritorio () {
        string? prueba = Environment.get_variable ("LAUNCHPAD_FONDO");
        if (prueba != null && prueba != "") {
            return prueba;
        }
        var fuentes = SettingsSchemaSource.get_default ();
        if (fuentes == null || fuentes.lookup ("org.cinnamon.desktop.background", true) == null) {
            return null;
        }
        string uri = new Settings ("org.cinnamon.desktop.background").get_string ("picture-uri");
        return uri != "" ? File.new_for_uri (uri).get_path () : null;
    }

    /** Desenfoque gaussiano separable de un pixbuf RGB(A) de 8 bits (solo toca los tres primeros canales). */
    void desenfocar (Gdk.Pixbuf pb, double sigma) {
        int radio = (int) Math.ceil (sigma * 3);
        var nucleo = new double[2 * radio + 1];
        double suma = 0;
        for (int i = -radio; i <= radio; i++) {
            nucleo[i + radio] = Math.exp (-(i * i) / (2 * sigma * sigma));
            suma += nucleo[i + radio];
        }
        for (int i = 0; i < nucleo.length; i++) {
            nucleo[i] /= suma;
        }
        int w = pb.width, h = pb.height, nc = pb.n_channels, rs = pb.rowstride;
        unowned uint8[] px = pb.get_pixels ();
        var tmp = new double[w * h * 3];
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                double r = 0, g = 0, b = 0;
                for (int k = -radio; k <= radio; k++) {
                    int xx = int.min (w - 1, int.max (0, x + k));
                    int o = y * rs + xx * nc;
                    double c = nucleo[k + radio];
                    r += px[o] * c;
                    g += px[o + 1] * c;
                    b += px[o + 2] * c;
                }
                int t = (y * w + x) * 3;
                tmp[t] = r;
                tmp[t + 1] = g;
                tmp[t + 2] = b;
            }
        }
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                double r = 0, g = 0, b = 0;
                for (int k = -radio; k <= radio; k++) {
                    int yy = int.min (h - 1, int.max (0, y + k));
                    int t = (yy * w + x) * 3;
                    double c = nucleo[k + radio];
                    r += tmp[t] * c;
                    g += tmp[t + 1] * c;
                    b += tmp[t + 2] * c;
                }
                int o = y * rs + x * nc;
                px[o] = (uint8) Math.round (r);
                px[o + 1] = (uint8) Math.round (g);
                px[o + 2] = (uint8) Math.round (b);
            }
        }
    }

    /** La ruta del PNG del fondo (de caché si ya existe), o null si no hay con qué hacerlo. */
    public string? construir_fondo (int ancho, int alto) {
        string? ruta = fondo_de_escritorio ();
        if (ruta == null || !FileUtils.test (ruta, FileTest.EXISTS)) {
            return null;
        }
        Posix.Stat st;
        if (Posix.stat (ruta, out st) != 0) {
            return null;
        }
        string sello = "%s|%ld.%ld|%dx%d|%g|v-vala-1".printf (ruta, (long) st.st_mtim.tv_sec, (long) st.st_mtim.tv_nsec,
                                                              ancho, alto, FONDO_BLUR);
        string cache_dir = Path.build_filename (Environment.get_home_dir (), ".cache", "mint-macos");
        string cache = Path.build_filename (cache_dir,
            "launchpad-fondo-" + Checksum.compute_for_string (ChecksumType.SHA1, sello).substring (0, 16) + ".png");
        if (FileUtils.test (cache, FileTest.EXISTS)) {
            return cache;
        }
        try {
            var im = new Gdk.Pixbuf.from_file (ruta);
            // «cover»: llena la pantalla sin deformar
            double esc = double.max ((double) ancho / im.width, (double) alto / im.height);
            int sw = int.max (ancho, (int) Math.round (im.width * esc));
            int sh = int.max (alto, (int) Math.round (im.height * esc));
            var grande = im.scale_simple (sw, sh, Gdk.InterpType.HYPER);
            var rec = new Gdk.Pixbuf.subpixbuf (grande, (sw - ancho) / 2, (sh - alto) / 2, ancho, alto);
            double k = (double) ancho / REF_W;
            // se desenfoca en pequeño (es más rápido y el resultado es el mismo)
            var chico = rec.scale_simple (ancho / 4, alto / 4, Gdk.InterpType.HYPER);
            desenfocar (chico, FONDO_BLUR * k / 4);
            var salida = chico.scale_simple (ancho, alto, Gdk.InterpType.BILINEAR);
            int nc = salida.n_channels, rs = salida.rowstride;
            unowned uint8[] px = salida.get_pixels ();
            for (int y = 0; y < alto; y++) {
                for (int x = 0; x < ancho; x++) {
                    int o = y * rs + x * nc;
                    for (int c = 0; c < 3; c++) {
                        double v = px[o + c] * FONDO_A[c] + FONDO_K[c];
                        px[o + c] = (uint8) Math.round (double.min (255.0, double.max (0.0, v)));
                    }
                }
            }
            DirUtils.create_with_parents (cache_dir, 0755);
            salida.save (cache, "png");
            return cache;
        } catch (Error e) {
            stderr.printf ("Sin fondo desenfocado: %s\n", e.message);
            return null;
        }
    }
}
