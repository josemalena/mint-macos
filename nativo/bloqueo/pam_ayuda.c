/*
 * La autenticación del bloqueo, con PAM (el mismo camino que usa cualquier pantalla de bloqueo de Linux: pam_unix → unix_chkpwd, sin
 * setuid propio). Nada se guarda: la clave llega por parámetro, la conversación de PAM recibe una copia que PAM mismo libera, y las
 * dos se borran con explicit_bzero al terminar.
 */
#define _GNU_SOURCE
/* La ABI de libpam es estable desde hace décadas: se declara aquí lo mínimo para no exigir libpam0g-dev al compilar
 * (en la sesión de José solo está el runtime libpam.so.0); se enlaza con -l:libpam.so.0. */
typedef struct pam_handle pam_handle_t;
struct pam_message { int msg_style; const char *msg; };
struct pam_response { char *resp; int resp_retcode; };
struct pam_conv {
    int (*conv)(int, const struct pam_message **, struct pam_response **, void *);
    void *appdata_ptr;
};
#define PAM_SUCCESS 0
#define PAM_BUF_ERR 5
#define PAM_PROMPT_ECHO_OFF 1
#define PAM_PROMPT_ECHO_ON 2
extern int pam_start(const char *, const char *, const struct pam_conv *, pam_handle_t **);
extern int pam_authenticate(pam_handle_t *, int);
extern int pam_acct_mgmt(pam_handle_t *, int);
extern int pam_end(pam_handle_t *, int);
#include <stdlib.h>
#include <string.h>

#include "pam_ayuda.h"

typedef struct {
    const char *clave;
    size_t largo;
} Datos;

static int conversar(int n, const struct pam_message **msg, struct pam_response **resp, void *apdata)
{
    Datos *d = apdata;
    struct pam_response *r = calloc((size_t) n, sizeof(*r));
    if (!r)
        return PAM_BUF_ERR;
    for (int i = 0; i < n; i++) {
        if (msg[i]->msg_style == PAM_PROMPT_ECHO_OFF || msg[i]->msg_style == PAM_PROMPT_ECHO_ON) {
            r[i].resp = malloc(d->largo + 1);
            if (!r[i].resp) {
                for (int j = 0; j < i; j++) {
                    if (r[j].resp) {
                        explicit_bzero(r[j].resp, strlen(r[j].resp));
                        free(r[j].resp);
                    }
                }
                free(r);
                return PAM_BUF_ERR;
            }
            memcpy(r[i].resp, d->clave, d->largo);
            r[i].resp[d->largo] = '\0';
        }
    }
    *resp = r;
    return PAM_SUCCESS;
}

/* 0 = la clave es correcta y la cuenta sigue vigente; 1 = no; 2 = PAM no pudo ni empezar */
int mac_bloqueo_autenticar(const char *servicio, const char *usuario, const char *clave, size_t largo)
{
    Datos datos = { clave, largo };
    struct pam_conv conv = { conversar, &datos };
    pam_handle_t *h = NULL;
    if (pam_start(servicio, usuario, &conv, &h) != PAM_SUCCESS)
        return 2;
    int r = pam_authenticate(h, 0);
    if (r == PAM_SUCCESS)
        r = pam_acct_mgmt(h, 0);
    pam_end(h, r);
    return r == PAM_SUCCESS ? 0 : 1;
}
