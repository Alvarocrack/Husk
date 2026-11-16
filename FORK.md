# Husk — fork hecho por Alvarocrack

Basado en [Leviidev/Husk](https://github.com/Leviidev/Husk). Todo lo del original sigue igual; esto es lo que añade el fork.

## 120 Hz y desbloqueo de FPS

El Husk original le decía a todos los juegos que la pantalla iba a 60 Hz y su reloj de vsync latía a 60 Hz, así que ningún
juego pasaba de 60 FPS aunque el iPhone tuviera ProMotion.

**Settings › Frame Rate** (para todos los juegos) y **ajustes de cada juego › Display › Frame Rate** (solo ese juego;
"Default" sigue el ajuste general). Solo afecta a la capa de traducción, no al emulador de Android.

- **Automático**: 120 Hz en pantallas ProMotion, 60 Hz en las demás.
- **60 Hz**: exactamente como el Husk original.
- **120 Hz**: siempre 120 (si la pantalla lo admite).
- **Desbloquear FPS en Unity**: fuerza `Application.targetFrameRate` del juego a la tasa elegida, como los "FPS unlocker"
  de Android. Los juegos que nunca lo fijan (que en Android van a 30) también suben.

Qué se cambia por dentro (`src/translation-layer-next/husk-tl-refresh.c`):

- `Display.getRefreshRate()`, `Display.Mode.getRefreshRate()` y el deadline de presentación anuncian la tasa elegida.
- El reloj de vsync de `AChoreographer` (el que usa Swappy, el control de ritmo de Unity), el `Choreographer` de Java,
  `APerformanceHint` y el vsync de Flutter van a esa tasa.
- Se envuelve `il2cpp_add_internal_call` / `mono_add_internal_call` para capturar `Application.set_targetFrameRate`.
- El bucle de GLSurfaceView (juegos Java / libGDX) y el de Godot iban fijos a 60; ahora van a la tasa elegida.
- El bucle de Unity duerme 0,3 ms en vez de 2 ms entre frames a más de 60 Hz (a 120 Hz un frame dura 8,3 ms).
- En iOS: `CADisableMinimumFrameDurationOnPhone`, un `CADisplayLink` que pide 120 Hz mientras el juego está en pantalla,
  y el Modo Juego (`GCSupportsGameMode`, `LSSupportsGameMode`, categoría juegos).

A 60 Hz el comportamiento es el mismo que el del original. Si un juego va mal a 120, ponlo en 60.
Desde la consola: `TL_REFRESH_HZ=60` fuerza una tasa y `TL_NO_FPS_UNLOCK=1` desactiva el desbloqueo.

## Compilación en GitHub Actions

`.github/workflows/build-ipa.yml` compila el IPA en cada push a `main` y lo publica en
[Releases](https://github.com/Alvarocrack/Husk/releases) (`Husk.ipa` para Feather / FlareStore / SideStore y `Husk.tipa`
para TrollStore). Solo se compila la app; QEMU, ANGLE, MoltenVK y la capa de PS4 se sacan del IPA de la última release
oficial (`scripts/fork/stage_prebuilt.sh`), así que tarda minutos en vez de horas.

## Sincronizar con el original

`.github/workflows/sync-upstream.yml` hace merge de `Leviidev/Husk` cada 6 horas (o a mano desde Actions) y vuelve a
compilar. Los cambios del fork se hicieron pequeños y casi todos en archivos propios para que el merge no choque. Si
choca, no se toca nada y se abre un issue. El botón **Sync fork** de GitHub también sirve.

## Idioma

**Settings › Language**: Sistema, English o Español. Se aplica al volver a abrir Husk. Las traducciones están en
`src/app/Husk/es.lproj`. Algunos textos largos del Husk original no son traducibles (se escriben como texto fijo en el
código) y siguen en inglés.
