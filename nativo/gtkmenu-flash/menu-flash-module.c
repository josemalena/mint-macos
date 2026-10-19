/*
 * El parpadeo de la Mac al escoger un ítem de menú, en cualquier programa GTK3 (GTK_MODULES): al soltar el botón o pulsar Enter sobre un
 * ítem de un GtkMenu, el menú sigue abierto, el ítem alterna su resaltado N veces y entonces se activa con gtk_menu_shell_activate_item.
 * Solo API pública: se conecta a «button-release-event» y «key-press-event» de cada GtkMenu cuando se mapea, antes del manejador de GTK, y
 * lo frena (devuelve TRUE) para activar al final del parpadeo. No toca atajos de teclado (no pasan por el menú), el inhibit ni la
 * accesibilidad. No cubre a Electron, Chromium ni Firefox: dibujan sus propios menús.
 *
 * Ajustes: org.mintmacos.menus (menu-flash, flash-count, flash-duration-ms). Apagado por defecto: con menu-flash en false (o sin el
 * esquema) el módulo no hace nada. Se lee cada vez, así que encenderlo no pide reiniciar los programas.
 */
#include <gtk/gtk.h>
#include <gmodule.h>

#define CLAVE_CONECTADO "mint-macos-menu-flash-conectado"
#define CLAVE_ACTIVANDO "mint-macos-menu-flash-activando"
#define CLAVE_MAPEADO "mint-macos-menu-flash-mapeado"
// Un clic que se suelta enseguida después de abrir el menú no escoge nada (GTK también lo descarta)
#define MICROS_SIN_ESCOGER 400000

static GSettings *ajustes = NULL;
static gboolean ajustes_buscados = FALSE;

static GSettings *
buscar_ajustes (void)
{
    if (ajustes_buscados)
        return ajustes;
    GSettingsSchemaSource *def = g_settings_schema_source_get_default ();
    GSettingsSchema *esquema = def ? g_settings_schema_source_lookup (def, "org.mintmacos.menus", TRUE) : NULL;
    if (!esquema) {
        // Instalado con la sesión ya abierta: la carpeta del usuario
        gchar *carpeta = g_build_filename (g_get_user_data_dir (), "glib-2.0", "schemas", NULL);
        gchar *compilado = g_build_filename (carpeta, "gschemas.compiled", NULL);
        if (g_file_test (compilado, G_FILE_TEST_EXISTS)) {
            GError *error = NULL;
            GSettingsSchemaSource *fuente = g_settings_schema_source_new_from_directory (carpeta, def, FALSE, &error);
            if (fuente) {
                esquema = g_settings_schema_source_lookup (fuente, "org.mintmacos.menus", TRUE);
                g_settings_schema_source_unref (fuente);
            }
            g_clear_error (&error);
        }
        g_free (compilado);
        g_free (carpeta);
    }
    if (esquema) {
        ajustes = g_settings_new_full (esquema, NULL, NULL);
        g_settings_schema_unref (esquema);
        ajustes_buscados = TRUE;     // solo se da por buscado si lo hallamos: si se instala después, se encuentra
    }
    return ajustes;
}

typedef struct {
    GtkMenuShell *shell;
    GtkWidget *item;
    int paso;
    int total;
} Parpadeo;

static void
liberar_parpadeo (Parpadeo *p)
{
    g_object_set_data (G_OBJECT (p->shell), CLAVE_ACTIVANDO, NULL);
    g_object_unref (p->shell);
    g_object_unref (p->item);
    g_free (p);
}

static gboolean
paso_de_parpadeo (gpointer dato)
{
    Parpadeo *p = dato;
    if (p->total == 0) {                                        // sin apagar: se quedó resaltado fijo y ahora se ejecuta
        if (gtk_widget_get_mapped (GTK_WIDGET (p->shell)))
            gtk_menu_shell_activate_item (p->shell, p->item, TRUE);
        liberar_parpadeo (p);
        return G_SOURCE_REMOVE;
    }
    if (!gtk_widget_get_mapped (GTK_WIDGET (p->shell))) {      // lo cerraron mientras tanto (Esc, clic fuera)
        liberar_parpadeo (p);
        return G_SOURCE_REMOVE;
    }
    p->paso++;
    if (p->paso % 2 == 1)
        gtk_menu_shell_deselect (p->shell);
    else
        gtk_menu_shell_select_item (p->shell, p->item);
    if (p->paso < p->total)
        return G_SOURCE_CONTINUE;
    gtk_menu_shell_activate_item (p->shell, p->item, TRUE);
    liberar_parpadeo (p);
    return G_SOURCE_REMOVE;
}

/* ¿Hay que parpadear con este ítem? Devuelve el ítem escogido o NULL */
static GtkWidget *
item_a_parpadear (GtkMenuShell *shell, int *veces, int *fase)
{
    GSettings *cfg = buscar_ajustes ();
    if (!cfg || !g_settings_get_boolean (cfg, "menu-flash"))
        return NULL;
    if (g_object_get_data (G_OBJECT (shell), CLAVE_ACTIVANDO))
        return NULL;
    GtkWidget *item = gtk_menu_shell_get_selected_item (shell);
    if (!item || !GTK_IS_MENU_ITEM (item) || GTK_IS_SEPARATOR_MENU_ITEM (item) || !gtk_widget_get_sensitive (item)
        || gtk_menu_item_get_submenu (GTK_MENU_ITEM (item)) != NULL)
        return NULL;
    *veces = g_settings_get_int (cfg, "flash-count");
    *fase = g_settings_get_int (cfg, "flash-duration-ms");
    return item;
}

static void
empezar_parpadeo (GtkMenuShell *shell, GtkWidget *item, int veces, int fase)
{
    Parpadeo *p = g_new0 (Parpadeo, 1);
    p->shell = g_object_ref (shell);
    p->item = g_object_ref (item);
    p->total = veces * 2;
    g_object_set_data (G_OBJECT (shell), CLAVE_ACTIVANDO, GINT_TO_POINTER (1));
    g_timeout_add (fase, paso_de_parpadeo, p);
}

static gboolean
al_soltar (GtkWidget *menu, GdkEventButton *evento, gpointer dato)
{
    if (g_object_get_data (G_OBJECT (menu), CLAVE_ACTIVANDO))
        return TRUE;                                    // ya parpadeando: nada más cuenta
    gint64 mapeado = GPOINTER_TO_SIZE (g_object_get_data (G_OBJECT (menu), CLAVE_MAPEADO));
    if (mapeado && g_get_monotonic_time () - mapeado < MICROS_SIN_ESCOGER)
        return FALSE;
    int veces, fase;
    GtkWidget *item = item_a_parpadear (GTK_MENU_SHELL (menu), &veces, &fase);
    if (!item || evento->button != 1)
        return FALSE;
    empezar_parpadeo (GTK_MENU_SHELL (menu), item, veces, fase);
    return TRUE;
}

static gboolean
al_teclear (GtkWidget *menu, GdkEventKey *evento, gpointer dato)
{
    if (g_object_get_data (G_OBJECT (menu), CLAVE_ACTIVANDO))
        return TRUE;
    if (evento->keyval != GDK_KEY_Return && evento->keyval != GDK_KEY_KP_Enter && evento->keyval != GDK_KEY_ISO_Enter
        && evento->keyval != GDK_KEY_space)
        return FALSE;
    int veces, fase;
    GtkWidget *item = item_a_parpadear (GTK_MENU_SHELL (menu), &veces, &fase);
    if (!item)
        return FALSE;
    empezar_parpadeo (GTK_MENU_SHELL (menu), item, veces, fase);
    return TRUE;
}

static gboolean
al_mapear (GSignalInvocationHint *hint, guint n, const GValue *valores, gpointer dato)
{
    GObject *objeto = g_value_get_object (&valores[0]);
    if (!objeto || !GTK_IS_MENU (objeto))
        return TRUE;
    g_object_set_data (objeto, CLAVE_MAPEADO, GSIZE_TO_POINTER ((gsize) g_get_monotonic_time ()));
    if (!g_object_get_data (objeto, CLAVE_CONECTADO)) {
        g_object_set_data (objeto, CLAVE_CONECTADO, GINT_TO_POINTER (1));
        g_signal_connect (objeto, "button-release-event", G_CALLBACK (al_soltar), NULL);
        g_signal_connect (objeto, "key-press-event", G_CALLBACK (al_teclear), NULL);
    }
    return TRUE;
}

G_MODULE_EXPORT void
gtk_module_init (gint *argc, gchar ***argv)
{
    // Los menús aparecen más tarde: se engancha cada GtkMenu cuando se mapea (la señal «map» de GtkWidget)
    g_signal_add_emission_hook (g_signal_lookup ("map", GTK_TYPE_WIDGET), 0, al_mapear, NULL, NULL);
}
