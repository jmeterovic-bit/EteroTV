# EteroTV

App propia (no copia de ninguna otra) para ver el catálogo de un servidor IPTV, llevar favoritos y el progreso de películas y series, y reproducir con su **reproductor propio** (media_kit, el motor de mpv), o en VLC, Just Player o MX Player como alternativa. Para Jose y su familia (perfiles), interfaz en español, inglés o francés. Flutter: un APK para celular, Google TV y Fire TV, y un ejecutable para Windows.

**Antes de cambiar algo, lee [docs/DECISIONES.md](docs/DECISIONES.md).** Tiene el diseño, cada decisión con su motivo, lo pendiente y lo rechazado. El diseño completo está en el documento «EteroTV: diseño» (https://claude.ai/artifact/Q8fuc1WAHEmM5RW2e1KGmy).

## Reglas que no se rompen
- Reproductor propio por defecto (`lib/player/own_player.dart`, media_kit). VLC (y en Android Just Player o MX Player) quedan como alternativa en Ajustes → Reproductor, por aparato. Lo decidió Jose el 2026-11-10 por las limitaciones de VLC (se cuelga en su Bravia, no recibe idioma en Android). mpv no debe registrar nada: la URL lleva la contraseña.
- No guardar en logs ni subir a ningún servicio el usuario, la contraseña o las URLs de los videos (llevan la contraseña). La única excepción es la cuenta IPTV dentro del archivo de sincronización, en la carpeta oculta del Drive del propio usuario.
- Solo se sincroniza «mi biblioteca» (perfiles, y de cada perfil favoritos, progreso, lo visto e idiomas; además credenciales, PIN y carpetas protegidas, que son de todos). El catálogo lo baja cada dispositivo del proveedor.
- Reemplazar un favorito perdido siempre lo confirma el usuario.

## Compilar
- `flutter analyze` y `flutter test`. GitHub Actions los corre y compila el APK y el zip de Windows en cada PR; cada push a `main` publica un Release con el APK, el zip y el script para Fire TV.
- La versión se cambia solo en `pubspec.yaml`, y se agrega su sección en `CHANGELOG.md`.
- La conexión con Google necesita los secretos `GOOGLE_CLIENT_ID/SECRET` (cliente de escritorio; ver `docs/CONFIGURAR-GOOGLE.md`); se pasan con `--dart-define`. Las TV reciben la sesión desde el celular o el PC por la red local (`lib/sync/tv_link.dart`): Google rechaza `drive.appdata` en el inicio de sesión con código.

## Al terminar un cambio
Agrega una fila a la bitácora de `docs/DECISIONES.md` y, si corresponde, a «Decisiones», «Rechazado» o «Pendiente».
