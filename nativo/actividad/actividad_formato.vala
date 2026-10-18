/*
 * Los números como los escribe Activity Monitor: «983.2 MB», «0 bytes», «2,016», «1:12.45», «39.00%».
 */
namespace Actividad {
    public string miles (double v) {
        var s = ((int64) Math.round (v)).to_string ();
        var sb = new StringBuilder ();
        int n = s.length;
        for (int i = 0; i < n; i++) {
            if (i > 0 && (n - i) % 3 == 0 && s[i - 1] != '-') sb.append_c (',');
            sb.append_c (s[i]);
        }
        return sb.str;
    }

    /** bytes → «0 bytes», «12.5 KB», «983.2 MB», «3.51 GB» (la memoria y los discos de la ventana). */
    public string bytes_texto (double b, int dec_gb = 2) {
        if (b < 0) return "";
        if (b < 1024) return "%s byte%s".printf (miles (b), b == 1 ? "" : "s");
        double kb = b / 1024;
        if (kb < 1024) return "%.1f KB".printf (kb);
        double mb = kb / 1024;
        if (mb < 1024) return "%.1f MB".printf (mb);
        double gb = mb / 1024;
        if (gb < 1024) return dec_gb == 1 ? "%.1f GB".printf (gb) : "%.2f GB".printf (gb);
        return "%.2f TB".printf (gb / 1024);
    }

    /** ms de CPU → «13.60» o «1:12.45». */
    public string tiempo_texto (double ms) {
        if (ms < 0) return "";
        double s = ms / 1000;
        if (s < 60) return "%.2f".printf (s);
        int m = (int) (s / 60);
        double r = s - m * 60;
        if (m < 60) return "%d:%05.2f".printf (m, r);
        return "%d:%02d:%05.2f".printf (m / 60, m % 60, r);
    }

    public string porcentaje (double v) {
        return "%.2f%%".printf (v);
    }
}
