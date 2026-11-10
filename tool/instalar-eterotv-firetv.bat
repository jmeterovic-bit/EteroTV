@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul
title Instalar EteroTV en el Fire TV / Google TV

rem Instala (o actualiza) EteroTV en un Fire TV o Google TV por Wi-Fi, sin cable.
rem Antes, una sola vez, en el televisor:
rem   Fire TV:   Configuracion > Mi Fire TV > Opciones para desarrolladores > Depuracion ADB: activar
rem              (si no aparece "Opciones para desarrolladores": Mi Fire TV > Acerca de, pulsar 7 veces el nombre del dispositivo)
rem   Google TV: Ajustes > Sistema > Acerca de > pulsar 7 veces "Compilacion del SO";
rem              luego Ajustes > Sistema > Opciones para desarrolladores > Depuracion USB: activar
rem Pon el APK (eterotv-X.Y.Z.apk) en la misma carpeta que este archivo. Si hay varios, usa el mas nuevo.

set "HERE=%~dp0"
set "APK="
for /f "delims=" %%F in ('dir /b /o-d "%HERE%eterotv*.apk" 2^>nul') do if not defined APK set "APK=%HERE%%%F"
if not defined APK (
  echo No encuentro el APK de EteroTV junto a este archivo.
  echo Descargalo del Release de GitHub y ponlo en: %HERE%
  pause
  exit /b 1
)

set "TOOLS=%LOCALAPPDATA%\EteroTV\platform-tools"
set "ADB=%TOOLS%\adb.exe"
where adb >nul 2>nul && set "ADB=adb"
if not "%ADB%"=="adb" if not exist "%ADB%" (
  echo Descargando las herramientas de Android de Google ^(solo la primera vez^)...
  powershell -NoProfile -Command "$ErrorActionPreference='Stop'; $z=Join-Path $env:TEMP 'platform-tools.zip'; Invoke-WebRequest 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile $z; Expand-Archive $z -DestinationPath (Join-Path $env:LOCALAPPDATA 'EteroTV') -Force; Remove-Item $z"
  if not exist "%ADB%" (
    echo No se pudieron descargar. Revisa la conexion a internet.
    pause
    exit /b 1
  )
)

set "CFG=%LOCALAPPDATA%\EteroTV\tv-ip.txt"
set "IP="
if exist "%CFG%" set /p IP=<"%CFG%"
echo.
echo La IP del televisor esta en:
echo   Fire TV:   Configuracion ^> Mi Fire TV ^> Acerca de ^> Red
echo   Google TV: Ajustes ^> Red e Internet ^> ^(tu Wi-Fi^)
if defined IP (
  set /p "NEW=IP del televisor [!IP!]: "
  if defined NEW set "IP=!NEW!"
) else (
  set /p "IP=IP del televisor (por ejemplo 192.168.1.50): "
)
if not defined IP exit /b 1
> "%CFG%" echo !IP!

echo.
echo Conectando con !IP! ... Si el televisor pregunta "Permitir depuracion", elige Permitir
echo ^(marca "Permitir siempre desde este equipo"^).
rem Segundos que espera a que se acepte en el televisor (cambialo aqui si necesitas mas).
set "WAIT=90"
echo Tienes !WAIT! segundos para ir al televisor y aceptar.
"%ADB%" disconnect !IP!:5555 >nul 2>nul
"%ADB%" connect !IP!:5555
set /a LEFT=!WAIT!
:waitauth
"%ADB%" -s !IP!:5555 get-state 2>nul | find "device" >nul
if not errorlevel 1 goto connected
if !LEFT! leq 0 goto noconnect
timeout /t 3 /nobreak >nul
set /a LEFT-=3
"%ADB%" connect !IP!:5555 >nul 2>nul
goto waitauth
:noconnect
echo.
echo No se pudo conectar. Revisa que la depuracion ADB este activada, que aceptaste el
echo aviso en el televisor y que el PC y el televisor esten en la misma red Wi-Fi.
pause
exit /b 1
:connected
echo Conectado.

echo Instalando EteroTV ^(puede tardar un minuto^)...
"%ADB%" -s !IP!:5555 install -r "%APK%"
if errorlevel 1 (
  echo.
  echo La instalacion fallo. Si dice INSTALL_FAILED_UPDATE_INCOMPATIBLE, desinstala EteroTV
  echo en el televisor y vuelve a intentarlo ^(se pierde solo lo guardado en ese televisor^).
  pause
  exit /b 1
)
"%ADB%" disconnect !IP!:5555 >nul 2>nul
echo.
echo Listo. EteroTV ya esta en el televisor ^(en Fire TV: Apps ^> Tus aplicaciones^).
echo Recuerda instalar VLC desde la tienda del televisor si todavia no lo tienes.
pause
