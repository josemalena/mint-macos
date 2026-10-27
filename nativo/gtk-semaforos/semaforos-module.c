// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * El hover de los semáforos como en la Mac (GTK_MODULES): al pasar el puntero por uno de los tres botones de una barra de título
 * de GTK (headerbar con botones, la que usan Nemo, Fynder y las apps con barra propia), los tres se ven en hover a la vez. GTK3
 * no propaga :hover al contenedor, así que el CSS solo no puede: aquí se marca PRELIGHT en los botones hermanos mientras el
 * puntero está sobre cualquiera de ellos. Solo API pública. No cubre las ventanas que pinta Muffin (esas las pinta otro proceso).
 */
#include <gtk/gtk.h>
#include <gmodule.h>

static gboolean
es_semaforo (GtkWidget *w)
{
    return GTK_IS_BUTTON (w) && gtk_style_context_has_class (gtk_widget_get_style_context (w), "titlebutton");
}

static void
marcar_hermanos (GtkWidget *boton, gboolean encendido)
{
    GtkWidget *caja = gtk_widget_get_parent (boton);
    if (!caja || !GTK_IS_CONTAINER (caja))
        return;
    GList *hijos = gtk_container_get_children (GTK_CONTAINER (caja));
    for (GList *l = hijos; l; l = l->next) {
        GtkWidget *h = l->data;
        if (h == boton || !es_semaforo (h))
            continue;
        if (encendido)
            gtk_widget_set_state_flags (h, GTK_STATE_FLAG_PRELIGHT, FALSE);
        else
            gtk_widget_unset_state_flags (h, GTK_STATE_FLAG_PRELIGHT);
    }
    g_list_free (hijos);
}

static gboolean
al_cruzar (GSignalInvocationHint *hint, guint n, const GValue *valores, gpointer dato)
{
    GObject *objeto = g_value_get_object (&valores[0]);
    if (!objeto || !GTK_IS_WIDGET (objeto) || !es_semaforo (GTK_WIDGET (objeto)))
        return TRUE;
    GdkEventCrossing *e = (GdkEventCrossing *) g_value_get_boxed (&valores[1]);
    if (!e)
        return TRUE;
    // Al pasar de un semáforo a otro, el «leave» del primero llega antes que el «enter» del segundo: el segundo lo vuelve a encender.
    marcar_hermanos (GTK_WIDGET (objeto), ((GdkEvent *) e)->type == GDK_ENTER_NOTIFY);
    return TRUE;
}

G_MODULE_EXPORT void
gtk_module_init (gint *argc, gchar ***argv)
{
    g_signal_add_emission_hook (g_signal_lookup ("enter-notify-event", GTK_TYPE_WIDGET), 0, al_cruzar, NULL, NULL);
    g_signal_add_emission_hook (g_signal_lookup ("leave-notify-event", GTK_TYPE_WIDGET), 0, al_cruzar, NULL, NULL);
}
