/*
 * mint-macos-arranque: avisa del arranque de una .app de Mac con el protocolo freedesktop de startup-notification
 * (libsn), para que el Muelle la muestre ya, saltando, y Muffin ponga el cursor de espera hasta que abra su ventana.
 *
 *   mint-macos-arranque --nombre TextEdit --clase darling-com.apple.textedit [--icono /ruta/icono.png] [--pid N] [--max-segundos 120]
 *
 * Manda «new:» con NAME, ICON y WMCLASS, y se queda esperando a que salga una ventana de esa clase (WM_CLASS res_class), a que
 * muera --pid o a que pase el máximo; entonces manda «remove:» y sale. Lo lanza mint-macos-abrir-mac antes de arrancar la app.
 */
#define WNCK_I_KNOW_THIS_IS_UNSTABLE 1
#define SN_API_NOT_YET_FROZEN 1
#include <gtk/gtk.h>
#include <gdk/gdkx.h>
#include <libwnck/libwnck.h>
#include <libsn/sn.h>
#include <signal.h>
#include <string.h>

static GMainLoop *lazo;
static SnLauncherContext *contexto;
static gchar *clase_minuscula;
static int pid_vigilado = 0;
static GHashTable *previas;      // ventanas que ya estaban abiertas: no cuentan



static void terminar(void) {
    g_printerr("mint-macos-arranque: terminar()\n");
    if (contexto) {
        sn_launcher_context_complete(contexto);
        sn_launcher_context_unref(contexto);
        contexto = NULL;
    }
    g_main_loop_quit(lazo);
}

static void al_abrir_ventana(WnckScreen *pantalla, WnckWindow *ventana, gpointer dato) {
    if (g_hash_table_contains(previas, GSIZE_TO_POINTER(wnck_window_get_xid(ventana)))) return;
    const gchar *grupo = wnck_window_get_class_group_name(ventana);
    if (grupo == NULL) return;
    gchar *g = g_ascii_strdown(grupo, -1);
    gboolean es = g_strcmp0(g, clase_minuscula) == 0;
    g_free(g);
    if (es) { g_printerr("mint-macos-arranque: ventana de la clase: %s 0x%lx\n", grupo, (unsigned long) wnck_window_get_xid(ventana)); terminar(); }
}

static gboolean vigilar(gpointer dato) {
    if (pid_vigilado > 0 && kill(pid_vigilado, 0) != 0) {
        g_printerr("mint-macos-arranque: murió el pid %d\n", pid_vigilado);
        terminar();
        return G_SOURCE_REMOVE;
    }
    return G_SOURCE_CONTINUE;
}

static gboolean tiempo_agotado(gpointer dato) {
    g_printerr("mint-macos-arranque: tiempo agotado\n");
    terminar();
    return G_SOURCE_REMOVE;
}

static void error_push(SnDisplay *d, Display *x) { gdk_x11_display_error_trap_push(gdk_display_get_default()); }
static void error_pop(SnDisplay *d, Display *x) { gdk_x11_display_error_trap_pop_ignored(gdk_display_get_default()); }

int main(int argc, char **argv) {
    gchar *nombre = NULL, *clase = NULL, *icono = NULL;
    gint max = 120;
    GOptionEntry opciones[] = {
        { "nombre", 0, 0, G_OPTION_ARG_STRING, &nombre, "Nombre de la app", "N" },
        { "clase", 0, 0, G_OPTION_ARG_STRING, &clase, "WM_CLASS (res_class) de sus ventanas", "C" },
        { "icono", 0, 0, G_OPTION_ARG_STRING, &icono, "Ruta de un PNG o nombre del tema", "I" },
        { "pid", 0, 0, G_OPTION_ARG_INT, &pid_vigilado, "Proceso a vigilar: si muere, se acaba el aviso", "PID" },
        { "max-segundos", 0, 0, G_OPTION_ARG_INT, &max, "Máximo de espera (por defecto 120)", "S" },
        { NULL }
    };
    GError *error = NULL;
    GOptionContext *oc = g_option_context_new("");
    g_option_context_add_main_entries(oc, opciones, NULL);
    g_option_context_add_group(oc, gtk_get_option_group(TRUE));
    if (!g_option_context_parse(oc, &argc, &argv, &error) || clase == NULL) {
        g_printerr("uso: mint-macos-arranque --clase CLASE [--nombre N] [--icono RUTA] [--pid N] [--max-segundos S]\n");
        return 2;
    }
    GdkDisplay *gd = gdk_display_get_default();
    if (gd == NULL) return 1;
    Display *xd = gdk_x11_display_get_xdisplay(gd);
    SnDisplay *sn = sn_display_new(xd, (SnDisplayErrorTrapPush) error_push, (SnDisplayErrorTrapPop) error_pop);
    contexto = sn_launcher_context_new(sn, DefaultScreen(xd));
    sn_launcher_context_set_name(contexto, nombre ? nombre : clase);
    sn_launcher_context_set_description(contexto, "Opening");
    if (icono) sn_launcher_context_set_icon_name(contexto, icono);
    sn_launcher_context_set_wmclass(contexto, clase);
    sn_launcher_context_set_binary_name(contexto, nombre ? nombre : clase);
    sn_launcher_context_initiate(contexto, "mint-macos-arranque", nombre ? nombre : clase, CurrentTime);
    sn_display_unref(sn);

    clase_minuscula = g_ascii_strdown(clase, -1);
    lazo = g_main_loop_new(NULL, FALSE);
    WnckScreen *pantalla = wnck_screen_get_default();
    wnck_screen_force_update(pantalla);
    previas = g_hash_table_new(g_direct_hash, g_direct_equal);
    for (GList *l = wnck_screen_get_windows(pantalla); l; l = l->next)
        g_hash_table_add(previas, GSIZE_TO_POINTER(wnck_window_get_xid(l->data)));
    // una ventana que ya estuviera abierta no cuenta: se espera una nueva
    g_signal_connect(pantalla, "window-opened", G_CALLBACK(al_abrir_ventana), NULL);
    g_timeout_add_seconds(1, vigilar, NULL);
    g_timeout_add_seconds(max, tiempo_agotado, NULL);
    g_main_loop_run(lazo);
    return 0;
}
