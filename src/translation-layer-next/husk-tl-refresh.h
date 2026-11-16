/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * Fork de Alvarocrack: la tasa de refresco que el juego ve (60 o 120 Hz) y el desbloqueo de FPS de Unity.
 *
 * Husk le decía a cada juego que la pantalla iba a 60 Hz y su reloj de vsync latía a 60 Hz, así que ningún juego pasaba de 60.
 * Aquí está el único valor del que todo eso depende ahora. El app lo fija antes de arrancar el juego (Ajustes › Rendimiento ›
 * Tasa de refresco); sin tocar nada vale 60, como en el Husk original.
 */
#ifndef HUSK_TL_REFRESH_H
#define HUSK_TL_REFRESH_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Lo llama el app antes de arrancar un juego. hz: 60 o 120 (otros valores se ajustan a 30..120). unlock_unity: forzar
 * Application.targetFrameRate de los juegos Unity a hz cuando hz > 60. */
void husk_set_refresh_rate(int hz, int unlock_unity);

/* La tasa que se le anuncia al juego (60 por defecto) y su periodo en nanosegundos. */
int tl_refresh_hz(void);
int64_t tl_refresh_period_ns(void);
/* Si hay que desbloquear los FPS de Unity (solo con hz > 60). */
int tl_refresh_unlock_unity(void);

/* Unity: se llama antes de cargar libmain.so. Pone un envoltorio delante de il2cpp_add_internal_call / mono_add_internal_call
 * para capturar Application.set_targetFrameRate. */
void tl_fps_unity_install(void);
/* Unity: en cada frame del hilo UnityMain; de vez en cuando vuelve a fijar el objetivo de FPS (los juegos que nunca lo fijan
 * se quedan en 30 en Android). */
void tl_fps_unity_frame(unsigned long frame);
/* El dlsym de bionic pregunta aquí primero: libunity busca la API de IL2CPP/Mono con dlsym. NULL si no es un nombre nuestro. */
void *tl_fps_dlsym(const char *name);

#ifdef __cplusplus
}
#endif

#endif
