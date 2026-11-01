# ps5-bazzite-toolbox

Caja de herramientas para **Linux en la PS5** con la imagen
[VivaLaVent/ps5-bazzite-deck](https://github.com/VivaLaVent/ps5-bazzite-deck) (Bazzite Deck: Steam en modo juego
y escritorio KDE). Es **un solo fichero** que se ejecuta en la consola y sirve para:

- **Diagnosticar** problemas sin cambiar nada, y dejar un informe para pedir ayuda.
- **Recuperar la pantalla o la sesión gráfica** cuando se queda en negro.
- **Poner a punto un sistema recién instalado**: idioma, VRAM, ventilador, NAS, EmuDeck/ES-DE… bloque a bloque,
  explicando cada cambio y preguntando antes. Incluye montar un NAS para las ROMs, BIOS e imágenes de
  EmuDeck/ES-DE.
- **Añadir y quitar juegos de Windows** en PortProton y Steam en un paso, con ajustes por defecto pensados para
  que funcionen el máximo de juegos sin tocar nada.
- **Actualizar la imagen** desde GitHub con comprobación de SHA-256.

Todo está en español. Probado en una PS5 (FW 4.50) con las versiones v1.4 – v1.8 de la imagen, arrancando desde un
disco USB. No es un proyecto oficial de la imagen ni de sus autores.

## Uso rápido

En la PS5 (terminal o SSH):

```sh
curl -LO https://github.com/fitamix/ps5-bazzite-toolbox/releases/latest/download/ps5-bazzite-toolbox.sh
bash ps5-bazzite-toolbox.sh
```

Ese enlace descarga siempre la **última versión publicada**. La rama `main` puede llevar cambios aún sin publicar.

La primera vez se ofrece a **instalarse** como el comando `ps5-bazzite-toolbox` (en `~/.local/bin`, sin `sudo`; las
actualizaciones de la imagen no lo borran) y como «Caja de herramientas PS5» en el menú de aplicaciones de KDE.
A partir de ahí:

```sh
ps5-bazzite-toolbox
```

y el fichero descargado ya se puede borrar. Si prefieres no instalarla, sigue funcionando con `bash ps5-bazzite-toolbox.sh`.

Sin opciones muestra un menú. Se ejecuta con tu usuario (no como root). La contraseña de `sudo` la pide solo la
primera vez que eliges algo que la necesita, y ya no vuelve a pedirla hasta que la cierras.

```
 Diagnóstico (solo mira, no cambia nada)
   1) Revisión completa de este arranque (y guarda el informe)
   2) Revisar el arranque anterior (tras un cuelgue o un apagado forzado)
   3) Vigilar el kernel en directo
   4) Vigilar en directo: CPU, GPU, VRAM, RAM, swap, temperatura y qué gasta más
 Pantalla y sesión gráfica
   5) Ver en qué modo arranca la consola y qué sesión hay ahora
   6) Pantalla en negro: recuperar la imagen (cambia de consola y vuelve; no cierra nada)
   7) Pantalla en negro que no se arregla con el 6: reiniciar la sesión (cierra Steam y lo abierto)
   8) Pasar al escritorio KDE ahora y arrancar siempre en él
   9) Pasar al modo juego ahora y arrancar siempre en él
 PortProton y Steam
  10) Instalar un juego de Windows: elige su aislamiento, pruébalo y, si va bien, a Steam y a la colección
  11) Mis juegos: cambiar su aislamiento o desinstalarlos (de Steam, PortProton y el disco)
  12) Sincronizar la colección «PortProton» de Steam
 Utilidades
  13) Ver lo que ocupa cada carpeta
 Ajustes de la consola (cambian el sistema; cada uno explica y pregunta)
  14) Ver qué ajustes están aplicados
  15) Aplicar los ajustes pendientes, uno a uno
  16) Revisar o cambiar ajustes concretos
 Sistema
  17) Actualizar la imagen desde GitHub
  18) Actualizar esta caja de herramientas
  19) Instalarla como comando y en el menú de aplicaciones, o desinstalarla
```

Lo mismo sin menú:

```sh
ps5-bazzite-toolbox --check [--boot -1]       # diagnóstico de este arranque (o del anterior) + informe
ps5-bazzite-toolbox --watch                   # kernel en directo
ps5-bazzite-toolbox --mem                     # CPU, GPU y memoria en directo
ps5-bazzite-toolbox --screen                  # pantalla en negro: recuperar la imagen
ps5-bazzite-toolbox --session status|restart|desktop|gamemode
ps5-bazzite-toolbox --add-game "/ruta/Juego.exe"
ps5-bazzite-toolbox --remove-game ["/ruta/Juego.exe" | "Nombre"]
ps5-bazzite-toolbox --games                           # mis juegos: cambiar aislamiento o desinstalar
ps5-bazzite-toolbox --change-level "/ruta/Juego.exe"  # cambiar cómo se ejecuta un juego instalado
ps5-bazzite-toolbox --run "/ruta/Juego.exe"           # lanzarlo como lo dejó --add-game (lo usa Steam)
ps5-bazzite-toolbox --pp-collection [--dry-run|--yes]
ps5-bazzite-toolbox --space [carpeta]
ps5-bazzite-toolbox --setup                   # ajustes, bloque a bloque
ps5-bazzite-toolbox --setup --status          # solo el estado de cada bloque
ps5-bazzite-toolbox --setup --all             # la respuesta recomendada en todo, sin preguntar
ps5-bazzite-toolbox --setup --only vram,nas   # solo esos bloques (vuelve a preguntar)
ps5-bazzite-toolbox --update [v1.8.4]         # actualizar la imagen
ps5-bazzite-toolbox --self-update [v1.1.0]    # actualizar esta caja de herramientas
ps5-bazzite-toolbox --install | --uninstall
ps5-bazzite-toolbox --version
```

(Sin instalar, lo mismo con `bash ps5-bazzite-toolbox.sh --check`, etc.)

## Diagnóstico

Solo lee. Al final ofrece guardar el informe (sin contraseñas) y repasa lo que ha dado problemas en esta
consola:

- **Disco USB:** atascos (`timing out command`), resets, errores de E/S y espacio libre.
- **Gráfica:** reinicios de la GPU, errores de memoria, VRAM disponible.
- **Sistema:** cuelgues del kernel, procesos bloqueados, falta de memoria, programas que se cierran de golpe, si el
  arranque anterior terminó mal.
- **Temperatura y ventilador**, **red** (router, DNS, Wi-Fi, Bluetooth, NAS), **sesión gráfica** y el estado de cada
  bloque de ajustes.

**Vigilar en directo** (opción 4): cada 2 s muestra la carga de CPU (media y el hilo más cargado) y de GPU, VRAM, GTT (RAM que la gráfica toma prestada), RAM y swap, todo
como usado/total, la temperatura de CPU y GPU y los programas que más VRAM usan. La swap de Bazzite es zram (RAM comprimida):
`2.5/4.3 GB (0.8)` son 2,5 GB en la swap que ocupan 0,8 GB de RAM. Al parar (Ctrl+C) resume los picos y dice si
falta VRAM, RAM o las dos, si se llenó la swap y si el límite es la GPU o un hilo de la CPU. Al pararlo ofrece guardar cada medida en `ps5-mem-FECHA.csv`.

## Pantalla y sesión gráfica

- **Recuperar la imagen** (6): pasar a otra consola virtual y volver hace que la gráfica vuelva a configurar la
  salida HDMI. No cierra nada.
- **Reiniciar la sesión** (7): `systemctl restart sddm` deja vivo el compositor anterior y la pantalla sigue en
  negro. El toolbox cierra primero las sesiones y el compositor, y luego arranca SDDM.
- **Escritorio / modo juego** (8, 9): cambia en qué sesión entra la consola al arrancar y la reinicia ya.

## Ajustes de la consola

Cada bloque explica **qué cambia, por qué y cómo deshacerlo**, y pregunta con una respuesta recomendada. Lo que
depende de cada consola (disco, idioma, NAS…) lo detecta o lo pregunta. Las respuestas quedan en
`~/.config/ps5-bazzite-toolbox.conf`; al repetirlo solo ofrece lo pendiente.

| Bloque | Qué hace | Por qué |
|---|---|---|
| `locale` | Idioma, teclado, zona horaria y NTP | La imagen viene en inglés, teclado US y UTC |
| `cmdline` | `/efi/cmdline.txt`: idioma en el arranque y `usb-storage.quirks` para el disco USB de arranque | Algunos discos USB con UAS dan resets y errores de E/S |
| `wifi` | Apaga o vuelve a encender el Wi-Fi según la versión de la imagen | El driver del IW620 se colgaba con el Wi-Fi activo antes de la v1.5.0 |
| `updates` | Bloquea las actualizaciones automáticas de kernel, Mesa, firmware y gamescope | Esos paquetes llevan parches de la PS5: actualizarlos rompe la imagen |
| `vram` | VRAM reservada para la gráfica (`/efi/vram.txt`, de 512 MB a 8 GB) | Con 512 MB, los juegos DX12/UE5 se caen con *Not enough memory* |
| `zram` | Swap zram del tamaño de toda la RAM (Bazzite pone la mitad), con un fichero aparte en `/etc/systemd/zram-generator.conf.d/` | Juegos grandes la llenan y, sin swap libre, el sistema los cierra |
| `fans` | Control del ventilador y temperatura objetivo (60–85 °C) | El objetivo de fábrica (80 °C) es silencioso pero caliente |
| `warmreboot` | Reinicio en caliente (sin pasar por el cargador) | Comodidad; experimental |
| `hdmi` | Recupera la imagen tras un reinicio en caliente | A veces el HDMI sale en negro |
| `bt` | Recarga `btusb` si el Bluetooth arranca sin adaptador | El IW620 a veces no responde a su primer reinicio |
| `disk` | Desactiva la consulta SMART de KDE | Dejaba algunos discos USB 60 s sin responder |
| `brave` | Brave sin la Cartera de KDE | Con inicio automático, Brave pide su contraseña cada vez |
| `nas` | Monta un NAS por SMB y enlaza las ROMs de EmuDeck | ROMs compartidas con otros equipos (p. ej. una Steam Deck) |
| `bios`, `media` | BIOS e imágenes de ES-DE desde el NAS | Una sola copia para todos los equipos |
| `esde` | Arregla el `es_systems.xml` que deja EmuDeck (rutas de Windows, Citra) | Sin esto 3DS falla con *citra_libretro.dll* |
| `portproton` | Ajustes globales de PortProton: FSYNC/ESYNC y trazado de rayos para todos los juegos, salvo los que su `.ppdb` cambie | PortProton los trae apagados; el Proton de Steam lleva la sincronización rápida, y hay juegos que exigen trazado de rayos |
| `atajos` | Botón derecho de Dolphin (instalar, cambiar aislamiento y desinstalar un juego; espacio por carpeta), comando `espacio`, acceso «Colección PortProton» | Tenerlo todo a mano tras instalar |

## PortProton y Steam

En Dolphin (tras el bloque `atajos`), botón derecho sobre un `.exe`: **«Instalar en PortProton y Steam»**,
**«Cambiar aislamiento»** y **«Desinstalar»**. En el menú, lo mismo con las opciones 10 y 11 («Mis juegos»).

**Instalar un juego de Windows** (opción 10, `--add-game`). Primero pregunta **cómo se ejecuta**:

- **1) Normal:** con acceso a todo, como siempre. Para juegos de tiendas fiables.
- **2) Aislado con red** (lo que se elige con Intro): sin tu carpeta personal, el NAS ni tus otros juegos. Con red,
  para juegos online o con launcher.
- **3) Aislado sin red:** lo mismo, sin red. Para juegos de origen dudoso.

Luego lo abre con PortProton en el escritorio, con ese aislamiento, para que lo configures y lo pruebes, y pregunta si
ha ido bien: si sí, sigue (accesos, Steam, colección); si no, para y deja todo como estaba (borra lo que creó la
prueba y, si quieres, la carpeta del juego). Con `r` lo vuelve a abrir: PortProton se cierra tras preparar un prefijo
nuevo (las bibliotecas recomendadas, que copia de su prefijo base, sin red), y hay que darle a iniciar otra vez.

Por qué: el Flatpak de PortProton puede ver **todo el sistema** (permiso `host`), así que un programa de Windows
lanzado con él podría borrar o cifrar tu carpeta personal, el NAS o las partidas de otros juegos. Un juego aislado se
lanza con menos permisos, quitados por el propio Flatpak:

- sin tu carpeta personal, el NAS ni otros discos, sin poder montar discos, y en el nivel 3 sin red;
- tu PortProton de verdad queda en **solo lectura**: corre en una copia para juegos aislados (sin tus prefijos, en
  `~/.local/share/ps5-bazzite-toolbox/aislado`, sincronizada en cada arranque), con un prefijo propio para el juego;
- solo puede escribir en la carpeta raíz del juego, que tiene que ser una carpeta local propia (no la carpeta
  personal, el NAS ni un disco externo).

**No es una máquina virtual:** comparte pantalla, sonido y mandos (un programa de X11 puede leer lo que se teclea en
otras ventanas X11; cierra Steam y el navegador al probarlo). Antes de probarlo da el enlace de VirusTotal con la
huella del `.exe` (sin subir nada), y después avisa si ha aparecido algo nuevo en tu PortProton real.

Un juego aislado no va en la lista de juegos de PortProton (desde ahí se abriría sin aislar): solo en el escritorio y
en Steam, que lo lanzan con `ps5-bazzite-toolbox --run` sin preguntar nada: en Steam (también en el modo juego) es
un juego más.

**Cambiar aislamiento** (en «Mis juegos», `--change-level` o en Dolphin): eliges el nivel nuevo, su prefijo (con las
partidas) se mueve entre tu PortProton y la copia aislada (preguntando), lo abre para que compruebes que va y, si
dices que sí, rehace sus accesos y su script de Steam. La entrada de Steam no cambia: conserva el tiempo jugado, las
carátulas y la colección. Si estaba en el prefijo compartido `DEFAULT`, empieza con uno nuevo y sus partidas se
quedan en `DEFAULT`. Si mueves o borras la caja de herramientas, los juegos aislados no arrancan desde Steam: instálala
(opción 19).

Después, pregunta en cada paso:

1. Abre el juego con PortProton para probarlo; PortProton guarda sus ajustes en `<exe>.ppdb`.
   - **Idioma:** si el juego lleva un emulador de Steam (`steam_emu.ini`, `steam_settings/…`, `SteamConfig.ini`,
     `cream_api.ini`) con otro idioma que el del sistema, ofrece cambiarlo: muchos juegos solo muestran el idioma que
     les dice "Steam" y no tienen selector propio. Si trae una carpeta de paquetes de idioma, ofrece copiar el tuyo.
2. Crea el acceso directo como lo hace PortProton: en su lista de juegos y en el escritorio (aislado: solo en el
   escritorio).
3. Lo añade a Steam como juego no-Steam (con Steam cerrado: si no, Steam borra la entrada al cerrarse). Hace copia
   de `shortcuts.vdf` y lo reescribe idéntico salvo la entrada nueva.
4. Lo mete en la colección «PortProton» de Steam.

**Mis juegos** (opción 11, `--games`): una sola lista, por nombre, de tus juegos de PortProton con su nivel (normal,
aislado con red o sin red), también los que instalaste antes de esta versión; elige uno para cambiar su aislamiento
o desinstalarlo.

**Desinstalar** (en «Mis juegos», `--remove-game` o en Dolphin). Pregunta por separado: quitarlo de Steam (con copia de `shortcuts.vdf`
y sus carátulas), borrar sus accesos directos y su script, y borrar su carpeta del disco, que muestra con su tamaño y
pide escribir su nombre para confirmar. Las partidas guardadas en el prefijo de PortProton se conservan; el prefijo
propio de un juego aislado lo ofrece borrar al final («no» por defecto).

**Ajustes para todos los juegos** (bloque `portproton`):

- **Sincronización rápida (FSYNC/ESYNC):** PortProton la trae apagada; el Proton de Steam la lleva encendida. Menos
  tirones en juegos que cargan la CPU.
- **Trazado de rayos:** el driver de la PS5 en Linux (RADV) lo soporta, pero PortProton lo desactiva en AMD y los
  juegos que lo exigen no arrancan. Si un juego lo enciende solo y va lento, bájalo en sus opciones gráficas o
  desactívalo solo para él con `export PW_USE_RAY_TRACING="0"` en su `.ppdb`.

PortProton lee sus ajustes globales (`data/user.conf`) después de los de cada juego, así que el bloque solo pone el
valor cuando el `.ppdb` del juego no dice nada.

## Actualizar la imagen

Lista las versiones publicadas (estables, preliminares y «rápidas» que solo cambian el kernel), muestra sus
novedades, comprueba el espacio, descarga, verifica el SHA-256 y ejecuta el `update.sh` del autor. Después recuerda
**apagar** y arrancar con el cargador, no reiniciar.

## Dónde deja sus ficheros

En ningún sitio sin preguntar. El informe del diagnóstico (`ps5-diag-FECHA.txt`), las medidas del monitor en
directo (`ps5-mem-FECHA.csv`) y la salida de una actualización de la imagen (`update-vX.Y.Z.log`) se escriben en un
fichero temporal y, al terminar, pregunta si guardarlo: **Intro** lo guarda en la carpeta desde la que la abriste
(desde el menú de aplicaciones, tu carpeta personal), puedes escribir otra carpeta, o **n** para no guardarlo.
Sin terminal (lanzada desde otro script) lo guarda en la carpeta actual sin preguntar.

## Versiones de la caja de herramientas

Cada versión publicada está en [Releases](https://github.com/fitamix/ps5-bazzite-toolbox/releases) con sus
novedades, y el historial completo en [CHANGELOG.md](CHANGELOG.md). La numeración sigue `MAYOR.MENOR.ARREGLO`:

- **MENOR** (1.**1**.0): bloques de ajustes, opciones o comprobaciones nuevas. Tras actualizar, la opción 15
  (`--setup`) ofrece solo lo nuevo que tengas pendiente.
- **ARREGLO** (1.0.**1**): correcciones, sin nada nuevo que aplicar.
- **MAYOR** (**2**.0.0): algo que cambia cómo se usaba (opciones renombradas, formato de las respuestas guardadas).
  Las notas dicen qué hacer.

Al abrir el menú, la caja de herramientas mira (en 4 segundos como mucho, y sin decir nada si no hay red) si hay
una versión más nueva y lo avisa. La opción 18 (`--self-update`) muestra las novedades, pregunta, descarga,
comprueba el SHA-256, guarda la copia anterior como `….vX.Y.Z` (solo la última) y sustituye la instalada (o, si no la instalaste, el fichero que ejecutas). Tus respuestas
guardadas en `~/.config/ps5-bazzite-toolbox.conf` no se tocan.

## Cosas que se hacen a mano

- Cambiar la contraseña (`passwd`): la de serie es `ps5` y SSH está abierto en la red.
- Steam: zona horaria e idioma propios, rango RGB **Full** en el modo juego y en el escritorio.
- EmuDeck: instalador **SteamOS**, dispositivo **Steam Machine**, ubicación **Internal**.
- DualSense: emparejarlo por Bluetooth en un perfil propio (PS + Cuadrado).
- Para un informe de fallo al autor de la imagen: su `ps5-report`.

## Licencia

[MIT](LICENSE).
