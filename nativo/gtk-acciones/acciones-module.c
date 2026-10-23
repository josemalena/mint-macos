// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * Publica por D-Bus las acciones de ventana que una app GTK3 no exporta (GTK_MODULES). Las apps hechas con gtkmm (Transmission) arman el grupo
 * «win» con gtk_widget_insert_action_group: GtkApplicationWindow no lo exporta (org.gtk.Actions.List sale vacío en la ruta de la ventana),
 * y el menú global, que activa los ítems desde otro proceso, los veía todos apagados. Cuando la ventana se mapea y su barra de menú está
 * publicada (GtkApplication), este módulo exporta el grupo «win» en la misma ruta que la barra (<app>/menus/menubar), como hace
 * appmenu-gtk-module con «unity.»; mac-ventanas (Menu1) lo usa si el grupo de la ventana viene vacío. Solo API pública de GTK y GIO.
 */
#include <gtk/gtk.h>
#include <gmodule.h>

#define CLAVE_EXPORTADO "mint-macos-acciones-exportado"
#define CLAVE_INTENTOS "mint-macos-acciones-intentos"

static void al_destruir (GtkWidget *ventana, gpointer dato);

static gboolean
exportar (GtkWidget *ventana)
{
    if (g_object_get_data (G_OBJECT (ventana), CLAVE_EXPORTADO))
        return FALSE;
    GApplication *app = g_application_get_default ();
    GActionGroup *grupo = gtk_widget_get_action_group (ventana, "win");
    if (!app || !grupo)
        return TRUE;
    GDBusConnection *con = g_application_get_dbus_connection (app);
    const gchar *ruta_app = g_application_get_dbus_object_path (app);
    if (!con || !ruta_app)
        return TRUE;
    gchar **nombres = g_action_group_list_actions (grupo);
    gboolean hay = nombres && nombres[0];
    g_strfreev (nombres);
    if (!hay)
        return TRUE;
    gchar *ruta = g_strconcat (ruta_app, "/menus/menubar", NULL);
    GError *error = NULL;
    guint id = g_dbus_connection_export_action_group (con, ruta, grupo, &error);
    if (id) {
        g_object_set_data (G_OBJECT (ventana), CLAVE_EXPORTADO, GUINT_TO_POINTER (id));
        g_signal_connect (ventana, "destroy", G_CALLBACK (al_destruir), NULL);
    }
    g_clear_error (&error);
    g_free (ruta);
    return id == 0;
}

static void
al_destruir (GtkWidget *ventana, gpointer dato)
{
    guint id = GPOINTER_TO_UINT (g_object_get_data (G_OBJECT (ventana), CLAVE_EXPORTADO));
    GApplication *app = g_application_get_default ();
    if (id && app && g_application_get_dbus_connection (app))
        g_dbus_connection_unexport_action_group (g_application_get_dbus_connection (app), id);
    g_object_set_data (G_OBJECT (ventana), CLAVE_EXPORTADO, NULL);
}

// Las acciones pueden llegar después de mapear la ventana: se reintenta unas veces
static gboolean
reintentar (gpointer dato)
{
    GtkWidget *ventana = GTK_WIDGET (dato);
    int n = GPOINTER_TO_INT (g_object_get_data (G_OBJECT (ventana), CLAVE_INTENTOS)) + 1;
    g_object_set_data (G_OBJECT (ventana), CLAVE_INTENTOS, GINT_TO_POINTER (n));
    gboolean seguir = exportar (ventana);
    if (!seguir || n >= 10 || !gtk_widget_get_mapped (ventana)) {
        g_object_unref (ventana);
        return G_SOURCE_REMOVE;
    }
    return G_SOURCE_CONTINUE;
}

static gboolean
al_mapear (GSignalInvocationHint *hint, guint n, const GValue *valores, gpointer dato)
{
    GObject *objeto = g_value_get_object (&valores[0]);
    if (!objeto || !GTK_IS_APPLICATION_WINDOW (objeto) || g_object_get_data (objeto, CLAVE_INTENTOS))
        return TRUE;
    g_object_set_data (objeto, CLAVE_INTENTOS, GINT_TO_POINTER (1));
    g_timeout_add (500, reintentar, g_object_ref (objeto));
    return TRUE;
}

G_MODULE_EXPORT void
gtk_module_init (gint *argc, gchar ***argv)
{
    g_signal_add_emission_hook (g_signal_lookup ("map", GTK_TYPE_WIDGET), 0, al_mapear, NULL, NULL);
}
