# Cambios

Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Numeración: `MAYOR.MENOR.ARREGLO`
(ver «Versiones de la caja de herramientas» en el [README](README.md)).

## [Sin publicar]

## [1.3.0] - 2026-11-01

### Añadido
- **Juegos aislados.** Al añadir un juego (opción 10, o en Dolphin «Añadir a PortProton y Steam (normal o
  aislado)») pregunta cómo se ejecuta: normal, aislado con red (Intro) o aislado sin red. Aislado = el propio
  Flatpak de PortProton le quita la carpeta personal, el NAS, los otros discos (y la red en el nivel 3); tu
  PortProton queda en solo lectura y el juego corre en una copia aparte con su propio prefijo. Steam y el escritorio
  lo lanzan con `--run`, que no pregunta nada (vale para el modo juego).
- Para probar un juego dudoso: añádelo sin red; si no te convence, al decir que no ha ido bien borra lo que creó la
  prueba y, si quieres, la carpeta del juego. Antes da el enlace de VirusTotal con su huella.
- Cambiar el aislamiento de un juego (o darlo por bueno): vuelve a añadirlo; su prefijo, con las partidas, se mueve
  entre tu PortProton y la copia aislada, preguntando.
- «Quitar un juego» lista también los aislados y ofrece borrar su prefijo.

### Cambiado
- Al actualizarla (opción 18) guarda solo la copia de la versión anterior (`….vX.Y.Z`), no todas.

## [1.1.0] - 2026-10-31

### Cambiado
- El informe del diagnóstico, las medidas del monitor (CSV) y la salida de las actualizaciones de la imagen ya no
  se guardan solos en la carpeta personal: al terminar pregunta si guardarlos y dónde (Intro = la carpeta actual,
  otra carpeta, o no). Sin terminal, los guarda en la carpeta actual.

## [1.0.2] - 2026-10-31

### Cambiado
- La contraseña de `sudo` se pide solo al elegir algo que la necesita (no al abrir el menú), una vez por sesión:
  después se mantiene hasta cerrar la caja de herramientas. Añadir/quitar juegos, la colección, ver lo que ocupa
  cada carpeta y actualizarla no la piden.

## [1.0.1] - 2026-10-31

### Corregido
- Al instalarla (`--install`, opción 19) y cambiar los atajos, decía que se podía borrar
  `~/.local/bin/ps5-bazzite-toolbox`, que es la copia instalada. **No la borres**; si lo hiciste, vuelve a instalarla.

### Cambiado
- Al instalarla pregunta si borra el fichero descargado (salvo que esté dentro de un repositorio git).
- Solo ofrece cambiar los atajos si de verdad apuntan a otra copia.

## [1.0.0] - 2026-10-31

Primera versión publicada.

### Diagnóstico
- Revisión completa de un arranque (este o el anterior) con informe sin contraseñas: disco USB, GPU, cuelgues,
  Wi-Fi, OOM, cierres, temperatura, NAS y sesión gráfica.
- Vigilancia del kernel en directo y monitor de CPU, GPU, VRAM, GTT, RAM, swap y temperaturas.

### Pantalla y sesión
- Recuperar la imagen cuando la pantalla se queda en negro, reiniciar la sesión y elegir escritorio o modo juego.

### Ajustes (bloques)
- `locale cmdline wifi updates vram zram fans warmreboot hdmi bt disk brave nas bios media esde portproton atajos`,
  cada uno explicando qué cambia, por qué y cómo deshacerlo, y preguntando antes.

### PortProton y Steam
- Añadir y quitar juegos de Windows (PortProton, accesos directos, Steam y colección «PortProton»), idioma del
  emulador de Steam y paquetes de idioma.

### Sistema
- Actualizar la imagen VivaLaVent/ps5-bazzite-deck desde GitHub con comprobación de SHA-256.
- Versión propia (`--version`), aviso de versión nueva en el menú y autoactualización (opción 18, `--self-update`).
- Instalación como comando `ps5-bazzite-toolbox` y en el menú de aplicaciones (opción 19, `--install`/`--uninstall`).
- Quien usaba la versión sin publicar (`ps5-toolbox.sh`): las respuestas de `~/.config/ps5-bazzite-postinstall.conf`
  pasan solas a `~/.config/ps5-bazzite-toolbox.conf`; los atajos se rehacen con el bloque `atajos`.

[Sin publicar]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.1.0...v1.3.0
[1.1.0]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/fitamix/ps5-bazzite-toolbox/releases/tag/v1.0.0
