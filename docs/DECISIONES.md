# EteroTV: decisiones

## Concepto
Catálogo y «control remoto de progreso» para el servicio IPTV de Jose. Muestra canales, películas y series del servidor, guarda favoritos y una fila «Seguir viendo», y abre cada video en VLC en el punto donde quedó, en cualquier dispositivo (celular Android, Google TV, Fire TV y PC con Windows).

## Decisiones
| Tema | Decisión | Por qué |
| --- | --- | --- |
| Tecnología | Flutter, igual que Project Cards | Una sola base de código para Android (celular y TV) y Windows; se reutiliza lo de Project Cards. |
| Servidor IPTV | API Xtream Codes (`player_api.php`) con URL, usuario y contraseña | El proveedor de Jose da esos datos. Es más liviana que la lista M3U y trae IDs, duraciones y TMDB. |
| Límite del proveedor | 2 reproducciones a la vez | Antes de abrir VLC se consulta `user_info` (conexiones máximas y activas) y se avisa si ya hay 2. |
| Listas grandes | Como Televizo: se baja la lista completa una vez, se guarda en SQLite y se refresca cada 24 h o a mano | Las pantallas leen de la base local y navegan rápido. La descarga y el análisis van en otro isolate. |
| VLC en Android | Intent `org.videolan.vlc.player.result` con `position`; VLC devuelve `extra_position` y `extra_duration` | Funciona igual en celular, Google TV y Fire TV. |
| VLC en Windows | Se abre una instancia propia con la interfaz web en 127.0.0.1 (puerto y contraseña al azar) y `--start-time`; se consulta `status.json` cada 5 s | VLC de escritorio no devuelve la posición al cerrar. |
| Historial de VLC | En Windows se abre con `--no-qt-recentplay` | La URL de cada video lleva el usuario y la contraseña. |
| Visto | Más del 90 % o menos de 3 min restantes | Los créditos no cuentan. Se reanuda 5 s antes; menos de 30 s empieza de cero. |
| Favoritos perdidos | Tras cada actualización se buscan los que ya no existen y se sugieren reemplazos por nombre limpio, año, duración (±2 min) y TMDB o canal EPG. El usuario confirma. | Los proveedores cambian IDs al reorganizar. Pedido por Jose el 2026-11-08. |
| Credenciales | Cifradas en el dispositivo (`flutter_secure_storage`). Sin frase maestra. | Decidido por Jose el 2026-11-08. En la etapa 2 se comparten por la carpeta oculta de Drive. |
| Fire TV (sin USB) | Dos formas: script `tool/instalar-eterotv-firetv.bat` desde el PC por Wi‑Fi (ADB), o Downloader con un enlace público de Drive | Jose quiere probar las dos, primero el script. El Release de GitHub es privado: Downloader no puede bajarlo. |
| Ícono | «E» ámbar con un play en el medio, sobre negro (#141414); ícono adaptativo en Android y banner 320×180 para TV | Elegido por Jose el 2026-11-09 entre 5 opciones (originales en la carpeta del proyecto `eterotv/`). |
| https vs http | Si el servidor responde http a una URL https (WRONG_VERSION_NUMBER), se reintenta con http y se guarda así | El servidor de Jose usa http en ese puerto, como casi todos los IPTV. |
| Detectar VLC en Android | No se bloquea la reproducción por la revisión previa: se intenta abrir VLC y solo si Android no lo encuentra se avisa | En el celular de Jose la búsqueda por nombre de paquete decía que no estaba aunque sí estaba (2026-11-09). |
| Carpetas propias | «A medias» (películas y series) y «Favoritos» van primero en cada categoría | Pedido por Jose el 2026-11-09 tras la primera prueba. |
| Búsqueda | Buscador en cada categoría con opción «Solo en <carpeta>» o «En todo <categoría>»; sin acentos y por palabras | Pedido por Jose el 2026-11-09. |
| Firma Android | Workflow «Create Android signing key» (una vez) y secretos `ANDROID_KEYSTORE_*` | Sin clave fija, cada APK se firma con una clave temporal y no se instala encima del anterior. |

## Pendiente
- Etapa 2: sincronización por Google Drive (`appDataFolder`, archivo de cambios por dispositivo, como Project Cards) de favoritos, progreso y credenciales.
- Etapa 3: interfaz pensada para el control remoto (ya se puede navegar con flechas, falta pulirla en TV) e inicio de sesión de Google con código en pantalla para TV.
- Etapa 4: guía EPG.
- Sin probar con el servidor real de Jose ni en dispositivos.

## Rechazado
- Reproductor propio (Jose prefiere VLC).
- Firebase o Supabase para sincronizar: datos en un tercero; Drive alcanza.
- Trakt.tv: obliga a emparejar con TMDB y no guarda canales ni credenciales.
- Frase maestra para las credenciales (Jose, 2026-11-08).

## Bitácora
| Fecha | Cambio |
| --- | --- |
| 2026-11-08 | Etapa 1 (v0.1.0): conexión Xtream, catálogo local, favoritos, progreso, VLC en Android y Windows, búsqueda, favoritos perdidos, script Fire TV, CI. |
| 2026-11-09 | v0.1.1: ícono propio y banner de TV; reintento automático con http y mensajes de conexión en español. |
| 2026-11-09 | v0.1.1 (cont.): carpetas A medias y Favoritos, buscador por categoría, detección de VLC más tolerante. |
