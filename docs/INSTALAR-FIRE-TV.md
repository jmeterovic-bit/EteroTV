# Instalar EteroTV en Fire TV o Google TV (sin cable)

Primero instala **VLC** desde la tienda del televisor (Appstore de Amazon o Google Play).

## Forma 1 (recomendada): desde el PC por Wi‑Fi

1. En el Fire TV: *Configuración > Mi Fire TV > Opciones para desarrolladores > Depuración ADB*: activar.
   Si no ves «Opciones para desarrolladores», entra en *Mi Fire TV > Acerca de* y pulsa 7 veces el nombre del dispositivo.
   (Google TV: *Ajustes > Sistema > Acerca de*, pulsa 7 veces «Compilación del SO»; luego activa *Depuración USB* en *Opciones para desarrolladores*.)
2. Anota la IP del televisor: *Mi Fire TV > Acerca de > Red*.
3. En el PC, baja del Release `eterotv.apk` e `instalar-eterotv-firetv.bat` a la misma carpeta.
4. Doble clic en `instalar-eterotv-firetv.bat` y escribe la IP. La primera vez baja las herramientas de Android de Google (unos 7 MB) y el televisor pregunta si permite la depuración: elige **Permitir siempre**.
5. Para actualizar, repite el paso 3 y 4 con el APK nuevo (recuerda la IP).

## Forma 2: con la app Downloader

1. Instala **Downloader** (de AFTVnews) desde la Appstore de Amazon.
2. En el Fire TV: *Mi Fire TV > Opciones para desarrolladores > Instalar apps desconocidas*: activar para Downloader.
3. Sube `eterotv.apk` a tu Google Drive, compártelo como «Cualquier persona con el enlace» y copia el ID del archivo (lo que va entre `/d/` y `/view`).
4. En Downloader escribe: `https://drive.google.com/uc?export=download&id=ID_DEL_ARCHIVO` y acepta instalar.
5. Después de instalar, quita el permiso de compartir del archivo en Drive.

El Release de GitHub es privado, por eso Downloader no puede bajarlo directamente.
