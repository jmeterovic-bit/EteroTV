# EteroTV

App propia (no copia de ninguna otra) para ver el catálogo de un servidor IPTV, llevar favoritos y el progreso de películas y series, y reproducir **en VLC** (no tiene reproductor propio). Para un solo usuario (Jose), interfaz en español. Flutter: un APK para celular, Google TV y Fire TV, y un ejecutable para Windows.

**Antes de cambiar algo, lee [docs/DECISIONES.md](docs/DECISIONES.md).** Tiene el diseño, cada decisión con su motivo, lo pendiente y lo rechazado. El diseño completo está en el documento «EteroTV: diseño» (https://claude.ai/artifact/Q8fuc1WAHEmM5RW2e1KGmy).

## Reglas que no se rompen
- Sin reproductor propio: todo se abre en VLC.
- No guardar en logs ni subir a ningún servicio el usuario, la contraseña o las URLs de los videos (llevan la contraseña). La única excepción es la cuenta IPTV dentro del archivo de sincronización, en la carpeta oculta del Drive del propio usuario.
- Solo se sincroniza «mi biblioteca» (favoritos, progreso, lo visto, credenciales, PIN y carpetas protegidas). El catálogo lo baja cada dispositivo del proveedor.
- Reemplazar un favorito perdido siempre lo confirma el usuario.

## Compilar
- `flutter analyze` y `flutter test`. GitHub Actions los corre y compila el APK y el zip de Windows en cada PR; cada push a `main` publica un Release con el APK, el zip y el script para Fire TV.
- La versión se cambia solo en `pubspec.yaml`, y se agrega su sección en `CHANGELOG.md`.
- La conexión con Google necesita los secretos `GOOGLE_CLIENT_ID/SECRET` y `GOOGLE_TV_CLIENT_ID/SECRET` (ver `docs/CONFIGURAR-GOOGLE.md`); se pasan con `--dart-define`.

## Al terminar un cambio
Agrega una fila a la bitácora de `docs/DECISIONES.md` y, si corresponde, a «Decisiones», «Rechazado» o «Pendiente».
