# Cambios

Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Numeración: `MAYOR.MENOR.ARREGLO`
(ver «Versiones de la caja de herramientas» en el [README](README.md)).

## [Sin publicar]

### Añadido

- **Bloque `fans`: temperatura objetivo en las imágenes v2.8.1 y posteriores.** La v2.8 quitó `ps5-perf fan` y el
  objetivo quedaba en los 91 °C de Sony; la v2.8.1 lo devuelve como parámetro de arranque (`ps5_fan.target=`, 80 °C
  si no se pone). La caja lo detecta y escribe ese parámetro en `/efi/cmdline.txt` (con copia previa; 60–91 °C,
  cuenta desde el siguiente reinicio). En imágenes anteriores sigue como antes, con `ps5-perf`.

## [1.10.1] - 2026-11-09

### Arreglado

- **El monitor web ya no se para solo al mirar otra pestaña.** La página dejaba de preguntar en segundo plano y el
  monitor se paraba a los 30 s sin nadie mirando: al volver pedía guardar o descartar, como si hubieras pulsado
  «Parar». Ahora la página sigue preguntando cada 15 s aunque no esté visible, y el monitor solo se para tras
  10 minutos sin ninguna página abierta.

## [1.10.0] - 2026-11-09

### Añadido

- **Bloque `arranque`: sin la pantalla de carga** (*plymouth*: `plymouth.enable=0 rd.plymouth=0` en
  `/efi/cmdline.txt`). Solo pone el logo, y una vez dejó el arranque parado 3 minutos hasta pulsar `Ctrl+Alt+F3`.
  Recomendado; cuenta desde el siguiente reinicio. `cardwired` no se toca: el modo juego arranca Steam con
  `cardwire launch`.
- **Bloque `steambt`: el Bluetooth de Steam, siempre activado.** Con él desactivado, Steam apaga el adaptador al
  entrar al modo juego y el mando no conecta. Bazzite lo deja así cuando reinicia Steam tras varias caídas seguidas
  del modo juego. Un servicio de usuario lo vuelve a activar antes de cada sesión, con Steam cerrado; si ya está
  activado no toca nada. Recomendado; para cualquier PS5.

## [1.9.6] - 2026-11-09

### Cambiado

- **`--setup --all` respeta los «sí» que ya diste.** Antes aplicaba solo la respuesta por defecto de cada bloque, así
  que los opcionales (`gpu40`, `monitorweb`, `swapdisco`, `bios`, `media`…) se saltaban aunque los hubieras aceptado
  antes. Ahora, si `~/.config/ps5-bazzite-toolbox.conf` recuerda que dijiste que sí, los aplica también: copiando ese
  fichero a una instalación nueva y ejecutando `--setup --all` queda como la anterior.

## [1.9.5] - 2026-11-08

### Añadido

- **Bloque `zram`: elegir el compresor** además del tamaño. Explica cada uno (`lz4`: muy rápido, guarda ~1,7–2 a 1,
  recomendado para jugar; `zstd`: el de Bazzite, guarda ~2,5–3 a 1 pero con la RAM llena se nota en tirones;
  `lzo-rle`: el del kernel) y comprueba que el kernel tenga el elegido. Propone `lz4`: con Lichii (Switch 2) y Zelda
  OoT quitó las caídas a 2–5 FPS cada ~25 s y la RAM libre media pasó de 54 a 458 MB. Muestra el compresor que se usa
  ahora. Quien ya tenía el bloque aplicado lo verá pendiente hasta elegir compresor. Si existe `91-lz4.conf` (la
  prueba a mano), lo borra porque lo cubre el bloque.

## [1.9.4] - 2026-11-08

### Quitado

- **El acceso «Colección PortProton» del escritorio** (bloque `atajos`): ya no se crea ni se revisa. Instalar,
  cambiar el aislamiento o desinstalar un juego ya actualizan la colección de Steam, y la opción 12 lo hace a mano. Al
  aplicar el bloque se borra el que hubiera.

## [1.9.3] - 2026-11-08

### Añadido

- **Bloque `swapdisco`: swap en el disco** detrás de la zram, para que los programas que se quedan sin memoria vayan
  más lentos en vez de cerrarse («escasez de memoria evitada»). Tamaño a elegir (8, 16, 24 o 32 GB; 0 = quitarla),
  prioridad 10 (solo se usa con la zram llena) y activa en cada arranque. No se aplica por defecto: en un disco USB,
  mucha escritura en la swap puede congelar el sistema unos segundos, y lo explica. Probado con Lichii (Switch 2) y
  Zelda OoT: sin ella el kernel lo cerraba a los 9 minutos; con ella siguió.
- **Monitor (opción 4 y web): la swap en disco aparte.** Cuánto hay en el disco, el pico al parar, un aviso si se
  usó (el juego siguió, pero más lento) y la columna `swap_disco_mb` en el CSV de las dos vistas. El aviso de «la swap
  se llenó» propone también este bloque.

### Cambiado

- **Vigilar en directo (opción 4):** una sola temperatura, la del chip, leída del mismo sensor que el monitor web
  (antes CPU/GPU, que salían iguales). Su CSV tiene ahora **las mismas columnas que el del monitor web**
  (`hora,cpu_pct,cpu_hilo_max_pct,gpu_pct,vram_usada_mb,gtt_mb,ram_usada_mb,ram_disponible_mb,swap_usada_mb,`
  `zram_en_ram_mb,swap_disco_mb,temp_c,errores_gpu,top_vram,top_ram`), así que las sesiones de las dos vistas se comparan
  directamente. Ya no usa `sensors` cada 2 s.

## [1.9.2] - 2026-11-07

### Cambiado

- **Borrar la carpeta de un juego** (al desinstalarlo, o al descartar una instalación que no convence): para
  confirmar se escribe `BORRAR` (en mayúsculas o minúsculas) en vez del nombre de la carpeta, que podía ser largo. Antes
  sigue mostrando la carpeta completa y lo que ocupa.

## [1.9.1] - 2026-11-07

### Añadido

- **Generación de fotogramas por juego** (Lossless Scaling de PortProton), en «Mis juegos» (opción 11) y con
  `--framegen Juego.exe`: activarla (×2, calidad 0.5, modelo de calidad, probado en Gears of War E-Day), cambiar el
  multiplicador, la calidad o el modelo, o quitarla. Explica el retraso del mando que añade. Nunca activada por defecto.

### Cambiado

- **Instalar un juego (opción 10):** con Intro se elige **1) Normal**, no «aislado con red». Un juego ya instalado
  sigue proponiendo el nivel que tiene.
- **Monitor web:** una sola temperatura (CPU y GPU son el mismo chip y salían iguales; en el CSV, `temp_c` en vez de
  `temp_cpu_c` y `temp_gpu_c`), y cada recuadro explica qué es al pulsarlo o pasar el ratón por encima, además de
  «¿Qué es cada cosa?» al final de la página.
- **bootc [EN PRUEBAS]:** el arreglo de «Failed to start ostree-finalize-staged.service» se ofrece también en
  consolas instaladas con las imágenes v2.5.1, v2.6.1 y v2.6.2 que lo tengan (servicio de greenboot enmascarado), no
  solo en la v2.5, como dicen las notas de la v2.6.3.

## [1.9.0] - 2026-11-05

Lo marcado **EN PRUEBAS** aún no se ha probado en una consola de verdad: el modo bootc (no había ninguna instalación
bootc a mano) y montar otro disco al recuperar. En una instalación Legacy y sin otro disco no cambia nada. Si lo
pruebas, cuenta cómo te ha ido.

### Añadido
- Bloque de ajustes **`firewall`** (recomendado): el cortafuegos de la imagen arranca **fallido** porque la zona
  `FedoraWorkstation` usa `samba-client`, cuyo módulo (`nf_conntrack_netbios_ns`) no trae el kernel de la PS5: va con
  una zona mínima y no admite cambios. El bloque encuentra esos servicios por el módulo que les falta, los quita de
  la zona y reinicia firewalld. El diagnóstico lo avisa, y `monitorweb` lo pide antes de abrir su puerto.
- **Monitor en el móvil** (bloque de ajustes `monitorweb`, no recomendado por defecto): el monitor en directo de la
  opción 4 siempre disponible en `http://<consola>:8765`, sin SSH. «Empezar» mide cada 2 s, con gráficas, picos y
  veredicto; sin nadie mirando 30 s, para solo, y al parar pregunta si guardar las medidas en la PS5 (CSV, en
  `~/.local/share/ps5-bazzite-toolbox/monitor/`). Servicio de tu usuario (sin root), ~25 MB de RAM esperando; el cortafuegos abre el puerto solo para tu red. Sin clave. La opción 4 dice la dirección si está activo.
- **Instalaciones bootc** (**EN PRUEBAS**; la forma de la imagen desde la v2.5). La caja las reconoce y saca su versión de la imagen.
  La opción 17 (`--update`, `--rollback`) pasa a ser actualizar (`bootc upgrade`), volver a la anterior
  (`bootc rollback`) o cambiar de canal o versión (`bootc switch`), explicando y preguntando, y en la v2.5 ofrece
  antes el arreglo del autor sin el que no se puede actualizar. El bloque `updates` no aplica en bootc: bloquearía
  las actualizaciones buenas.
- **Recuperar desde otro disco, sin montarlo a mano** (opción 20 → 2; **EN PRUEBAS**): lista las copias y los discos Linux
  enchufados, monta el elegido solo lectura y lo desmonta al terminar. Si es un disco USB que su sistema usaba sin
  UAS (el Lexar ES3), pone ese ajuste ahora para que la copia no dé errores.

## [1.8.0] - 2026-11-05

### Añadido
- **Copia de seguridad de tu carpeta personal** (opción 20, `--backup`, `--restore [carpeta]`). Guarda en otro disco,
  el NAS o una carpeta lo que elijas: mide tu carpeta, lista lo grande y los sitios que conviene decidir aparte
  (juegos de Steam, prefijos de Proton y PortProton, juegos dentro de cada prefijo, juegos de PS3, `~/Games`…),
  deja fuera por defecto lo que se rehace solo y permite entrar en cualquier carpeta para elegir dentro. Avisa de
  los juegos de PortProton que quedarían sin sus ficheros. Los enlaces al NAS se guardan como enlace. En un disco
  Linux es una carpeta que se actualiza con `rsync`; en el NAS o exFAT, un `.tar.zst` por carpeta. Guarda también
  el servicio de Decky y la lista de Flatpaks del sistema. Al recuperar, desde una copia o desde la carpeta
  personal de otra instalación (otro disco enchufado, también bootc), reinstala Decky y los Flatpaks que falten y
  ofrece aplicar tus ajustes guardados.

## [1.7.0] - 2026-11-05

### Añadido
- Bloque de ajustes **`edge`**: Microsoft Edge (Flatpak) deja de pedir la contraseña de la Cartera de KDE en cada
  arranque, igual que el bloque `brave` (`--password-store=basic` en `edge-flags.conf`). No se recomienda por defecto:
  las sesiones y contraseñas ya guardadas en Edge dejan de leerse.

## [1.6.0] - 2026-11-04

### Añadido
- **Versiones de la imagen descargadas.** La opción 17 lista, junto a las de GitHub, las que tengas en tus carpetas
  (`l` añade una, p. ej. en el NAS; se guarda en `IMG_LOCAL`), marcadas `[descargada]` o `[descargada, ya no está en
  GitHub]`, y las instala desde ahí comprobando su SHA-256; sin red, solo las tuyas. Al instalar una de GitHub ofrece
  guardar su paquete en tu carpeta: el autor retira versiones (el 4 de noviembre solo quedaban la v2.5 y la v1.8.9).

### Arreglado
- El monitor en directo (opción 4) contaba como «errores de memoria de la GPU» las reservas que Linux niega a un
  programa que pide de golpe más memoria de la que hay (`__vm_enough_memory: … not enough memory for the
  allocation`), como RPCS3 al reservar 32 GB al arrancar un juego. No son de la GPU ni un fallo: ahora salen aparte,
  con el programa de verdad (un AppImage aparece como `AppRun.wrapped`), y no cuentan como errores.

## [1.5.0] - 2026-11-04

### Añadido
- **Volver atrás en la imagen (EN PRUEBAS).** Ya probado: la copia (17 → 3) guarda todo lo que debe en una PS5 con la
  imagen v1.8.4. Falta probar la vuelta (17 → 2) y una actualización real con su copia; úsalo sabiendo que puede
  fallar, y si lo pruebas, cuenta cómo te ha ido. Antes de cada actualización, la opción 17 guarda una copia completa de lo que cambia:
  kernel, initrd, `cmdline.txt`, módulos, scripts, servicios y reglas de la imagen, `/etc/ps5-bazzite-deck` y qué
  servicios estaban activos. La opción 17 → «Volver» (`--rollback`) la restaura sin red, aunque el kernel sea otro, y
  borra lo que añadió la versión nueva; antes guarda cómo está, así que también se deshace. Se guardan las 3 últimas.
- Si cabe, deja además el kernel anterior en la partición de arranque (`anterior-toolbox/`, con un `LEEME.txt`) para
  volver desde otro ordenador si la versión nueva no arranca.
- Opción 17 → «Guardar ahora una copia» de la imagen tal como está.

### Cambiado
- **README reescrito:** cada opción del menú con su equivalente sin menú y, si lo hay, el comando del sistema; cada
  bloque de ajustes en detalle (qué cambia, por qué, qué pregunta, los comandos para hacerlo a mano y cómo
  deshacerlo); y una sección nueva con todos los ficheros que usa o crea, dónde, qué opción los genera y cómo
  quitarlos.
- La opción 17 pregunta primero: instalar una versión de GitHub, volver a una copia o guardar una.
- Antes de instalar, avisa si el `update.sh` del autor no admite el cambio de kernel (hasta la v2.4) y dice cómo
  hacerlo.

## [1.4.0] - 2026-11-02

### Añadido
- Bloque **`gpu40`**: activar las 40 unidades de cálculo de la GPU (o volver a las 36 de fábrica) con
  `amdgpu.ps5_cu_unlock=3`, la opción que trae la imagen. Explica la «lotería del silicio» (en algunas consolas dan
  fallos gráficos o cuelgues), guarda copia de `cmdline.txt` y se cambia en cualquier momento con la opción 16 →
  `gpu40`. Solo PS5 original y Slim; la respuesta recomendada es «no».
- El diagnóstico avisa si hay fallos de la GPU con las 40 unidades activas.

## [1.3.0] - 2026-11-01

### Añadido
- **Juegos aislados.** Al instalar un juego (opción 10) pregunta cómo se ejecuta: normal, aislado con red (Intro) o
  aislado sin red. Aislado = el propio Flatpak de PortProton le quita la carpeta personal, el NAS, los otros discos
  (y la red en el nivel 3); tu PortProton queda en solo lectura y el juego corre en una copia aparte con su propio
  prefijo. Se prueba igual que siempre (abre, pruebas, «¿ha ido bien?») y Steam y el escritorio lo lanzan con `--run`,
  que no pregunta nada: en Steam es un juego más. Antes de probarlo da el enlace de VirusTotal con su huella.
- Al aislarlo enseña la carpeta del juego que podrá ver y deja cambiarla (para un `.exe` en una subcarpeta con los
  datos más arriba); se guarda y Steam la usa.
- Tras la prueba, «¿Ha arrancado bien?» admite `r` para volver a abrirlo (PortProton se cierra después de preparar
  un prefijo nuevo).
- **Mis juegos** (opción 11, `--games`): una sola lista, por nombre, de tus juegos de PortProton con su nivel (también
  los de antes), para cambiar su aislamiento o desinstalarlos.
- **Cambiar aislamiento** (`--change-level`): mueve su prefijo, lo prueba y reescribe sus accesos y su script de
  Steam; la entrada de Steam no cambia (tiempo jugado, carátulas, colección).
- En Dolphin, botón derecho sobre un `.exe`: «Instalar en PortProton y Steam», «Cambiar aislamiento» y «Desinstalar»
  (vuelve a aplicar el bloque `atajos` para tenerlos).

### Cambiado
- La opción 11 «Quitar un juego» pasa a ser «Mis juegos» (desinstalar está dentro).
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

[Sin publicar]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.10.1...HEAD
[1.10.1]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.10.0...v1.10.1
[1.10.0]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.9.6...v1.10.0
[1.9.6]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.9.5...v1.9.6
[1.9.5]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.9.4...v1.9.5
[1.9.4]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.9.3...v1.9.4
[1.9.3]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.9.2...v1.9.3
[1.9.2]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.9.1...v1.9.2
[1.9.1]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.9.0...v1.9.1
[1.9.0]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.1.0...v1.3.0
[1.1.0]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/fitamix/ps5-bazzite-toolbox/releases/tag/v1.0.0
