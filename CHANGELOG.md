# Cambios

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
