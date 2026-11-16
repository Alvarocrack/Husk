/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Fork de Alvarocrack: tasa de refresco configurable y desbloqueo de FPS de Unity. Ver husk-tl-refresh.h. */
#define _DARWIN_C_SOURCE
#include "husk-tl-refresh.h"

#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#include "husk-tl-arm32.h"
#include "husk-tl-ld.h"

void tl_log_line(const char *fmt, ...);

static atomic_int g_hz = 60;
static atomic_int g_unlock = 1;

static int clamp_hz(int hz) { return hz < 30 ? 30 : hz > 120 ? 120 : hz; }

void husk_set_refresh_rate(int hz, int unlock_unity)
{
    /* TL_REFRESH_HZ, para pruebas desde la consola, manda sobre el ajuste */
    const char *env = getenv("TL_REFRESH_HZ");
    if (env && atoi(env) > 0) hz = atoi(env);
    hz = clamp_hz(hz);
    atomic_store(&g_hz, hz);
    atomic_store(&g_unlock, unlock_unity ? 1 : 0);
    tl_log_line("refresh: the game is told the screen runs at %d Hz%s", hz,
                hz > 60 && unlock_unity ? "; Unity games are unlocked to it" : "");
}

int tl_refresh_hz(void) { return atomic_load(&g_hz); }
int64_t tl_refresh_period_ns(void) { return 1000000000ll / atomic_load(&g_hz); }
int tl_refresh_unlock_unity(void) { return atomic_load(&g_unlock) && atomic_load(&g_hz) > 60; }

/* ----------------------------------------------------------------- Unity */
/*
 * Application.targetFrameRate es un "internal call": libunity registra su implementación con il2cpp_add_internal_call (o
 * mono_add_internal_call) y el código del juego la busca por nombre la primera vez que la usa. Envolviendo el registro, el
 * juego recibe nuestro setter, que sustituye el valor que pida por la tasa elegida. Los juegos que nunca lo fijan se quedan en
 * el valor por defecto de Android (30), así que además se fija desde el bucle de frames.
 */
typedef void (*add_icall_fn)(const char *name, const void *method);
typedef void (*set_int_fn)(int32_t value);

static add_icall_fn g_real_il2cpp_add, g_real_mono_add;
static _Atomic(set_int_fn) g_real_set_tfr;
static atomic_bool g_installed;
static atomic_int g_last_asked = -2;

#define TFR "UnityEngine.Application::set_targetFrameRate"

static void set_tfr_wrap(int32_t v)
{
    set_int_fn real = atomic_load(&g_real_set_tfr);
    if (!real) return;
    int asked = v;
    if (tl_refresh_unlock_unity()) v = tl_refresh_hz();
    if (atomic_exchange(&g_last_asked, asked) != asked)
        tl_log_line("refresh: the game sets targetFrameRate %d%s", asked, v != asked ? " (unlocked)" : "");
    real(v);
}

static const void *maybe_wrap(const char *name, const void *method)
{
    if (!name || !method || strncmp(name, TFR, sizeof(TFR) - 1) != 0) return method;
    if (tl_a32_is_fn(method)) return method;     /* un juego de 32 bits: su código no es el nuestro */
    atomic_store(&g_real_set_tfr, (set_int_fn)method);
    tl_log_line("refresh: Application.targetFrameRate captured (%s)", name);
    return (const void *)set_tfr_wrap;
}

static void il2cpp_add_wrap(const char *name, const void *method)
{
    if (!g_real_il2cpp_add) g_real_il2cpp_add = (add_icall_fn)tl_ld_sym(NULL, "il2cpp_add_internal_call");
    if (g_real_il2cpp_add) g_real_il2cpp_add(name, maybe_wrap(name, method));
}

static void mono_add_wrap(const char *name, const void *method)
{
    if (!g_real_mono_add) g_real_mono_add = (add_icall_fn)tl_ld_sym(NULL, "mono_add_internal_call");
    if (g_real_mono_add) g_real_mono_add(name, maybe_wrap(name, method));
}

void tl_fps_unity_install(void)
{
    if (getenv("TL_NO_FPS_UNLOCK") || !tl_refresh_unlock_unity()) return;   /* a 60 Hz, todo como en el Husk original */
    if (atomic_exchange(&g_installed, true)) return;
    tl_ld_interpose("il2cpp_add_internal_call", (void *)il2cpp_add_wrap);
    tl_ld_interpose("mono_add_internal_call", (void *)mono_add_wrap);
}

void *tl_fps_dlsym(const char *name)
{
    if (!name || !atomic_load(&g_installed)) return NULL;
    if (!strcmp(name, "il2cpp_add_internal_call")) return tl_ld_sym(NULL, name) ? (void *)il2cpp_add_wrap : NULL;
    if (!strcmp(name, "mono_add_internal_call")) return tl_ld_sym(NULL, name) ? (void *)mono_add_wrap : NULL;
    return NULL;
}

void tl_fps_unity_frame(unsigned long frame)
{
    /* a los 30 frames (el motor ya está en marcha) y luego cada 5 segundos más o menos */
    if (frame != 30 && (frame < 30 || frame % 600 != 0)) return;
    set_int_fn real = atomic_load(&g_real_set_tfr);
    if (!real || !tl_refresh_unlock_unity()) return;
    if (frame == 30) tl_log_line("refresh: Unity's frame target set to %d", tl_refresh_hz());
    real(tl_refresh_hz());
}
