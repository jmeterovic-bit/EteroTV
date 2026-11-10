# Cambios

## 1.1.0
- Reproductor propio (prueba): EteroTV reproduce dentro de la app por defecto, en todos los aparatos. VLC, Just Player y MX Player siguen en Ajustes → Reproductor.
  - Usa el idioma de audio y subtítulos del perfil también en Android. Si el video no lo tiene, usa su pista original. No elige subtítulos forzados por su cuenta.
  - Control remoto: OK pausa, ◀ ▶ 10 s (mantener: 30 s), ▲ audio y subtítulos, ▼ muestra u oculta la barra, Atrás sale.
  - Celular: toque muestra la barra, doble toque a la izquierda o derecha salta 10 s, al centro pausa.
  - PC: espacio pausa, flechas 10 s, F o doble clic pantalla completa, Esc sale.
  - Guarda hasta dónde viste igual que antes, y en las series el aviso del siguiente episodio aparece sobre el video al llegar a los créditos.
  - Ocupa toda la pantalla en la TV (sin los márgenes grises de la app).
  - Barra con el control: ◀ ▶ recorren los botones y OK los usa; ▲ va a la línea de tiempo, donde ◀ ▶ mueven el video; Atrás oculta la barra. Con la barra oculta, ◀ ▶ mueven el video y OK pausa.
  - Ajustes → «Decodificar»: con el chip (normal), con el chip directo a la pantalla (más nítido, solo Android) o sin el chip. «Audio y subtítulos» muestra el códec, la resolución y cómo se decodifica, para comparar.
  - Un error de una pista que no impide ver el video (en la Bravia: «Could not open codec») ya no se muestra.
- Siguiente episodio: el aviso es una tarjeta chica en la esquina, con un círculo que se vacía en 30 s (antes una ventana de 10 s), y aparece en los últimos 100 s (antes a los 90 %, unos 3 minutos antes de que terminara el capítulo). Lo visto sigue igual (90 % o menos de 3 min).
- Al salir del reproductor ya no aparece el mensaje con el tiempo guardado (solo si el reproductor no dijo dónde quedaste).
- Inicio → «Lo nuevo»: series de tu historial con una temporada nueva (marca morada «NUEVA TEMPORADA») o capítulos nuevos (marca verde «NUEVO CAPÍTULO»). Se revisa al actualizar la lista. Lo anotado y las marcas viajan con cada perfil por Google Drive: lo que un aparato encuentra aparece en todos, y al verlo en uno se quita en todos. La primera revisión solo toma nota. La marca se va al ver un capítulo nuevo, o a los 30 días.
- Canales en vivo: «Ahora» y «Después» de la guía del proveedor, en la lista de canales y sobre el video.
- Perfiles: en el celular y el PC se puede usar una imagen tuya como ícono (además de los dibujos). Llega a los otros aparatos con el perfil.
- El APK es solo para aparatos ARM (todos los celulares, Google TV y Fire TV), para que no pese el doble.

## 1.0.0
- Perfiles, como en Netflix: al abrir la app aparece «¿Quién va a ver?». Cada perfil tiene sus favoritos, «Seguir viendo», lo visto, el idioma de la app y el de audio y subtítulos. La cuenta IPTV, el PIN y las carpetas protegidas son de todos.
- Hasta 5 perfiles. «Agregar perfil» y «Administrar perfiles» (nombre, dibujo, eliminar). Se cambia de perfil con el dibujo de arriba del menú izquierdo, o en Ajustes → Perfil.
- 32 dibujos para elegir (animales, magos, hadas, sirenas, superhéroes, dragones, robots…). Son los emoji del sistema: los personajes de Disney, DreamWorks, Star Wars o Harry Potter tienen dueño y no se pueden incluir.
- Los perfiles se sincronizan por Google Drive. Lo que había antes queda en el primer perfil («Mi perfil»; se le puede poner nombre). Eliminar un perfil lo borra, con lo suyo, en todos los aparatos.

## 0.8.0
- Idioma de la app: español, inglés o francés (Ajustes → Idioma, solo en ese aparato).
- Idioma de audio y subtítulos:
  - Windows (VLC): se eligen en Ajustes → Idioma. Si el video no tiene ese idioma, VLC usa la pista del video (normalmente la original). «Sin subtítulos» no muestra ninguno, tampoco los forzados.
  - Android: VLC, Just Player y MX Player no aceptan el idioma desde otra app. Ajustes → Idioma muestra los pasos para dejarlo elegido en el reproductor de ese aparato.
- Buscar desde el menú izquierdo deja el cursor en la barra y abre el teclado. Al escribir aparecen «Todo», «Series», «Películas» y «Canales» para elegir dónde buscar.
- Mantener OK sobre «Seguir viendo» (y en cualquier póster): el menú ya no elige solo «Ver ficha» con el OK que sigue apretado. Por eso no se podía llegar a «Quitar de Seguir viendo».
- TV, Inicio: al mantener la flecha o apretarla rápido, la lista salta en vez de deslizarse, y el foco ya no queda fuera de la pantalla.

## 0.7.0
- Ajustes → Reproductor → «Reproducir con»: VLC (normal), Just Player o MX Player, solo en ese aparato. Para la Bravia, donde VLC se cuelga con cualquier video (también fuera de EteroTV). Just Player es gratis, está en la tienda de Google TV y también devuelve hasta dónde viste.
- TV, filas (idea de Jose): desde una fila, arriba va a su «Ver todo»; otra vez arriba, al primer elemento de la fila de arriba. Bajar lleva al primer elemento de la fila de abajo. Al llegar arriba del todo queda en «Continuar» del destacado.
- Arreglo: en la versión compilada (no en las pruebas), «Ver todo» no se reconocía como botón aparte de la fila, porque la marca usaba una etiqueta que solo existe en modo de desarrollo.

## 0.6.3
- TV, navegación (probada con un catálogo grande, a 960×540 como una TV 1080p):
  - Dentro de una lista o cuadrícula, arriba va a la fila de arriba aunque esté fuera de pantalla; ya no salta a «Carpetas y búsqueda» ni a «Buscar».
  - Si el elemento enfocado desaparece (una fila que se recarga), o una pantalla abre sin nada elegido (Ajustes, menús), la primera flecha elige algo visible. Antes no había cómo recuperar el foco.
  - Las listas largas (Ajustes) siguen bajando aunque lo de abajo todavía no esté dibujado.
  - «Ver todo» se alcanza con derecha al final de su fila; arriba y abajo lo saltan.
  - Buscar: después de escribir, el foco queda en el buscador y abajo lleva a «Solo en…» / «En todo…».
  - El menú de un póster o de «Continuar viendo» abre con «Ver ficha» elegido.
- Episodios: mantener OK marca o desmarca visto (también con derecha hasta el ✓).
- Canales: mantener OK agrega o quita de favoritos, en la lista y en las filas; los favoritos llevan estrella.
- VLC en Android: espera hasta 15 s antes de dar por fallido el reproductor directo; si otra vía funciona, ese aparato no vuelve a usar el reproductor directo.

## 0.6.2
- TV: navegación con las flechas rehecha. Arriba y abajo van a la fila de arriba o de abajo, a algo que se ve en pantalla (antes a veces saltaban a una tarjeta escondida y el foco «desaparecía»). En el tope de arriba el foco se queda donde está (antes daba la vuelta hasta el final de la lista y no se podía volver). A la izquierda, desde el principio de una fila, se llega al menú lateral; a la derecha desde el menú se vuelve a lo que estaba elegido.
- «Ver todo» solo se alcanza desde las tarjetas que quedan justo debajo.
- VLC en TV: si su reproductor se cierra al instante sin decir nada (pasó en la Bravia), la app lo abre por la siguiente vía. El aviso muestra las vías probadas.

## 0.6.1
- Arreglo: un dispositivo nuevo no recibía la cuenta IPTV, el PIN ni las carpetas protegidas si se habían guardado antes de la 0.4.0 (no tenían fecha y se tomaban como «más viejos» que nada). Ahora un dispositivo que no tiene cuenta toma la de los otros, aunque no tenga fecha.

## 0.6.0
- La TV se conecta a Google desde el celular o el PC: en la TV, «Conectar con Google» muestra un código de 6 números; en el celular o el PC ya conectado, Ajustes → Sincronización → «Conectar una TV» la busca en tu red, escribes el código y listo. Se hace una vez por TV. La sesión viaja cifrada y solo esa TV la puede abrir.
- Se quitó el inicio de sesión con código de google.com/device: Google no permite la carpeta oculta de Drive con ese método («Invalid device flow scope»).
- El celular y el PC también pueden conectarse así, desde otro equipo ya conectado.
- El script para instalar en la TV espera hasta 90 s a que aceptes la depuración en el televisor.

## 0.5.1
- TV: la pantalla de inicio (datos del proveedor o «Traer mi cuenta desde Google Drive») ahora se maneja con el control. Antes el teclado aparecía solo y las flechas quedaban atrapadas en el primer campo. Los campos de texto, incluido el del PIN, funcionan como los buscadores: OK abre el teclado y las flechas pasan al siguiente.

## 0.5.0
- Control remoto (etapa 3): mantener OK medio segundo, o el botón ≡ del control de Fire TV, abre el menú de pósters, «Continuar viendo» y carpetas (lo mismo que mantener presionado en el celular). Así se pueden proteger carpetas con PIN y quitar cosas de «Seguir viendo» desde la TV.
- Atrás: en Series, Películas, Canales o Buscar vuelve a Inicio; en Inicio hay que pulsarlo dos veces para salir.
- Buscadores en la TV: pasar por el campo ya no abre el teclado; OK lo abre, y las flechas arriba y abajo salen del campo.
- El botón enfocado se marca con un borde blanco, para ver siempre dónde está el control.
- En la TV la app deja un margen en los bordes, para los televisores que los cortan.
- Ajustes explica cómo usar el control remoto.

## 0.4.0
- Sincronización con Google Drive (etapa 2): favoritos, avance, lo visto, la cuenta IPTV, el PIN y las carpetas protegidas quedan iguales en el celular, el PC y la TV. Se guardan en una carpeta oculta de tu Drive que solo EteroTV puede leer.
- Conectar con Google: en el celular y el PC con el navegador; en Google TV y Fire TV con un código que se escribe en google.com/device desde otro equipo.
- En un dispositivo nuevo, «Traer mi cuenta desde Google Drive» evita escribir la URL, el usuario y la contraseña.
- «Siguiente episodio»: al terminar un episodio aparece el siguiente con una cuenta de 10 s, «Cancelar» y «Ver ahora». En Windows aparece al empezar los créditos, encima de VLC.

## 0.3.1
- Android: VLC se abre directo en su reproductor, la única pantalla de VLC que devuelve hasta dónde viste (antes pasaba por su pantalla de inicio, que no devuelve nada). Si VLC igual no avisa, el mensaje dice cómo respondió.
- Los archivos del Release llevan la versión en el nombre (`eterotv-0.3.1.apk`), para no instalar uno viejo por error.

## 0.3.0
- Episodios: cada uno tiene su botón para marcarlo como visto o no visto sin abrirlo, y hay «Marcar temporada como vista». Muestran «Visto», «Empezado» o la barra de avance.
- «Ver» propone el primer episodio no visto (los marcados a mano cuentan).
- Al volver de VLC, un aviso dice hasta dónde quedó guardado, o que VLC no avisó la posición. La posición que devuelve VLC se lee de forma más tolerante.
- «Quitar de Seguir viendo» en la ficha de series y películas, en el menú de cada póster (mantener presionado) y en «Continuar viendo». Lo marcado como visto se conserva.
- Películas: «Marcar como vista» y «desmarcar» aunque nunca se hayan abierto.
- Carpetas protegidas con PIN de 4 números: el candado de cada carpeta la protege; aparece en la lista pero no muestra nada (ni en Inicio, búsqueda, favoritos o Seguir viendo) hasta ingresar el PIN. Se vuelve a bloquear al cerrar la app o tras una hora fuera. «Olvidé el PIN» pide la contraseña de la cuenta IPTV.
- Arreglo: la carpeta «Seguir viendo» quedaba cargando sin mostrar nada.
- Arreglo: Series, Películas y Canales quedaban vacías si la lista terminaba de bajar con la app ya abierta (por ejemplo, la primera vez).

## 0.2.0
- Diseño nuevo al estilo de las apps de streaming: pestañas Inicio, Series, Películas, Canales y Buscar (barra abajo en el celular, barra lateral en la TV y el PC).
- Inicio: destacado con «Continuar», fila «Continuar viendo» con barra de progreso y lo que falta, «Mi lista», canales favoritos y filas por categoría.
- En cada tarjeta de «Continuar viendo»: ⓘ para ver la ficha y ⋮ para marcar como visto o quitarla de la fila.
- La carpeta «A medias» ahora se llama «Seguir viendo».
- Series, Películas y Canales muestran filas por categoría con «Ver todo», y el botón «Carpetas y búsqueda» abre la vista de carpetas de 0.1.1.

## 0.1.1
- Carpetas «A medias» (películas y series empezadas) y «Favoritos» al principio de Canales, Películas y Series.
- Buscador en cada categoría: solo en la carpeta abierta o en toda la categoría. La búsqueda ignora acentos y acepta varias palabras.
- Ícono propio (E con play al medio, ámbar sobre negro) y banner para Google TV / Fire TV.
- Android: ya no dice «Falta VLC» con VLC instalado; abre VLC directamente y, si la forma con posición falla, lo abre de la forma simple.
- Si se escribe https:// para un servidor que solo usa http, la app reintenta sola con http y los errores de conexión se explican en español.

## 0.1.0
- Primera versión (etapa 1): conexión al servidor IPTV con URL, usuario y contraseña.
- Canales, películas y series del proveedor, guardados en el dispositivo y actualizados cada 24 h.
- Favoritos, «Seguir viendo» y progreso de películas y episodios.
- Reproduce en VLC y recuerda dónde paraste (Android, Google TV, Fire TV y Windows).
- Aviso cuando ya están en uso las 2 reproducciones del proveedor.
- Revisar favoritos perdidos después de una actualización de la lista.
- Script para instalar en Fire TV o Google TV por Wi‑Fi desde el PC.
