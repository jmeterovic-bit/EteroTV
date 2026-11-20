# Cambios

## 2.4.1
- Siguiente episodio: vuelve a aparecer la tarjeta al final de un capítulo abierto desde «Continuar viendo» después de usar la ventana pequeña. Al cambiar el tamaño de la ventana, Inicio se rearma y la tarjeta se perdía junto con la pantalla que abrió el video; el reproductor terminaba y volvía a Inicio sin ofrecer el siguiente. Ahora la tarjeta sale igual.
- Windows: si el capítulo terminó (o elegiste «Ver ahora») en la ventana pequeña, el siguiente también se abre en la ventana pequeña.

## 2.4.0
- Windows: «Ventana pequeña encima», un botón nuevo en la barra del reproductor. La ventana de EteroTV se achica a la esquina de abajo a la derecha (480 de ancho, con la forma del video) y queda encima de los otros programas mientras trabajas. Se puede mover por su barra de título. Al pasar el mouse aparecen pausa, volver al tamaño normal y salir; doble clic o Esc también la devuelven a su tamaño. Al salir del video la ventana vuelve a como estaba.
- Subtítulos en la ventanita (Windows y la imagen en imagen de Android): si están activados, se siguen viendo, con un tamaño pensado para la ventana chica (antes se habrían achicado hasta no leerse). Respetan el tamaño elegido (Pequeña…Muy grande).
- Idioma de subtítulos y audio del perfil: ahora toma cualquier variante del idioma, como «Español (Latinoamérica)», «Castellano», «Latino», es-419 o es-MX (antes solo las pistas marcadas exactamente «es» o «spa»). Nunca elige por su cuenta una pista que diga «Forzado», «Forzados» o «Forced». Si eliges otra pista a mano, se respeta.

## 2.3.1
- Ajustes → Acerca de muestra la versión instalada de verdad, con su número de compilación. Antes decía siempre 2.0.0.

## 2.3.0
- Reproductor propio: guarda hasta dónde vas cada 10 s de video. Si la app se cierra o se cae sin salir del video, la próxima vez sigue desde ahí (con unos segundos de diferencia como mucho). Lo visto y «Mi lista» se deciden al salir, como antes. Con VLC en Windows también.
- Sincronizar el audio: botón del reloj en la barra del reproductor. «Solo este video» corrige el desfase del video que estás viendo y se olvida al salir; «Todos los videos en este aparato» queda guardado (también en Ajustes → Reproductor). − y + mueven el sonido 50 ms (mantener repite), hasta 5 s; «0» lo deja como venía. Si el sonido llega antes que la imagen, usa +.
- TV: la sombra detrás de la barra de arriba y de abajo del reproductor llega a los bordes de la pantalla. Antes se cortaba antes de cada costado. Los botones y el texto siguen con su margen.
- Android (celular y TV): imagen en imagen. Si sales a otra app (Inicio, o las apps recientes) con el video andando, sigue en una ventanita encima de todo. Tocarla vuelve al video; cerrarla sale del video y guarda hasta dónde viste. Con el video en pausa no se achica. En aparatos que no lo permiten (algunas TV) no cambia nada.

## 2.2.2
- Canales: vuelve la revisión de 2.2.0 (2 s sobre un canal lo revisa), también justo después de ver uno. En 2.2.1 no se revisaba ningún canal durante 90 s tras salir del reproductor.
- El canal que acabas de ver no se revisa (el reproductor ya dijo si funcionó), así que no queda en gris al volver.
- Si otro canal falla en el primer minuto después de salir del reproductor, no se marca: el servidor puede estar contando todavía la conexión que se cerró. Se mantiene que solo queda en gris si falla dos veces seguidas.

## 2.2.1
- Canales: un canal que funciona ya no queda en gris al volver del reproductor. Dos causas: un aviso del video antes de empezar (como «Could not open codec», que no impide verlo) contaba como falla, y la revisión del canal enfocado corría justo al salir, cuando el servidor todavía cuenta la conexión que se cerró. Ahora solo cuenta como falla si el canal no muestra nada en 20 s, pierde la señal, o sales antes de que empiece con un error en pantalla. La revisión espera 90 s después de ver un canal, y lo marca en gris solo si falla dos veces seguidas.

## 2.2.0
- Canales en vivo: bajo cada canal, lo que dan ahora con una barra de cuánto lleva y a qué hora termina, y lo que viene después. Mientras ves un canal, al mostrar la barra: el programa, su avance, el horario y cuántos minutos quedan. Solo en los canales que tienen guía del proveedor.
- Canales que no cargan: si un canal no arranca (error, o nada en 20 s) o pierde la señal, queda en gris con «No cargó hace N min», en todos tus aparatos y por 3 horas. Los que sí cargaron llevan un punto verde.
- Con el control remoto (o el teclado), quedarse 2 s sobre un canal lo revisa: se abre un momento, sin reproducirlo, y queda en verde o en gris. Se revisa uno a la vez y no se repite antes de 15 minutos. Si tu cuenta ya tiene todas sus conexiones en uso, no se marca nada.
- Buscar: búsquedas guardadas. Abajo del buscador están «Filtros», «Guardar búsqueda» y tus búsquedas; OK elige una, mantener OK (o mantener apretado en el celular) permite cambiarle el nombre o borrarla. Cada perfil tiene las suyas y viajan con él a los otros aparatos.
- Filtros: buscar en todo, canales en vivo, películas o series; canal activo, con guía ahora, nunca visto, ya visto, a medias, en «Mi lista» o favoritos, y calidad (4K, FHD, HD, SD). Para canales, también buscar en lo que dan ahora y poner primero los que muestran el avance. Sin palabras, los filtros alcanzan (por ejemplo, «En Mi lista» + Películas).
- Viene de ejemplo «Real Madrid Vivo»: canales en vivo cuyo nombre o programa de ahora dice «Real Madrid», sin los que no cargaron, primero los que muestran el avance. Al abrirla se revisan hasta 8 canales encontrados que nadie abrió hace poco. Si la borras, no vuelve.
- Para buscar en lo que dan ahora, EteroTV baja la guía completa del proveedor solo cuando una búsqueda la necesita (cada 4 horas como mucho) y guarda solo las próximas 10 horas. Si el proveedor no la entrega, se busca en el nombre del canal y lo dice.

## 2.1.2
- Mi lista: una película que terminas de ver (o que marcas como vista) sale sola de «Mi lista». Queda marcada como vista, y el cambio llega a los otros aparatos del mismo perfil. Las series se quedan, porque ver un capítulo no termina la serie.
- TV: al llegar al último elemento de una fila, la flecha derecha ya no hace nada. Antes saltaba a «Ver todo» y de ahí a la fila siguiente, y era difícil quedarse en el último. «Ver todo» se sigue alcanzando con la flecha arriba.

## 2.1.1
- Reproductor: el tamaño de los subtítulos tiene su propio botón, una rueda dentada a la derecha de «Audio y subtítulos». Ese menú ya no lo incluye, para que no quede tan cargado.
- Siguiente episodio: la tarjeta queda más pegada a la esquina de abajo a la derecha (antes flotaba a media altura) y es un 20 % más grande que en 2.1.0.

## 2.1.0
- Siguiente episodio: la cuenta regresiva dura 60 s (antes 30 s) y la tarjeta es la mitad de grande. Sigue apareciendo en los últimos 100 s, así que los 60 s terminan antes que el capítulo.
- Si el capítulo termina con la tarjeta todavía en pantalla, la tarjeta ya no se cierra sola (antes se tomaba como «Cancelar»).
- Tamaño de los subtítulos: Pequeña, Normal, Grande o Muy grande. En Ajustes → Reproductor o en «Audio y subtítulos» mientras ves; se guarda en cada aparato.
- TV en vivo: si la señal se corta o el canal se queda pegado, el reproductor vuelve a conectarse solo («Reconectando…») en vez de salir a la lista. Si después de varios intentos no vuelve, lo dice en pantalla.
- TV en vivo: guarda menos video detrás del punto actual (un canal no se puede retroceder), para no llenar la memoria de la Fire TV en sesiones largas.

## 2.0.0
- Reproductor propio, ahora el de siempre (junta lo de 1.1.0 a 1.1.2 y estos arreglos de la Fire TV):
- Retroceder o adelantar varias veces seguidas (o mantener ◀ ▶) ya no traba el video: se salta directo al último punto pedido, en vez de una búsqueda por cada toque.
- Al salir de un video, el reproductor suelta la imagen antes de cerrarse. Antes la app podía quedarse congelada al salir (visto en la Fire TV).
- TV: si al volver del reproductor nada quedaba elegido, las flechas no hacían nada; ahora la selección vuelve a lo que se ve en pantalla.
- TV: después de «Ver siguiente», los márgenes grises podían quedar pegados alrededor del video hasta cerrar la app (visto en la Fire TV). Ahora el reproductor siempre ocupa toda la pantalla.

## 1.1.1
- TV: Atrás al salir del reproductor vuelve a donde estabas (por ejemplo «Canales»), no a Inicio.
- Canales: la calidad que trae el nombre (4K, FHD, HD, SD) aparece como una marca de color, y arriba de la lista se puede elegir ver solo una («Todas · 4K · FHD · HD · SD»). También en Buscar, con «Canales» elegido.

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
