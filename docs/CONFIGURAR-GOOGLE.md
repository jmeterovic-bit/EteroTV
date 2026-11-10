# Configurar la conexión con Google Drive (una sola vez)

EteroTV guarda tu biblioteca (favoritos, avance, cuenta IPTV, PIN y carpetas protegidas) en una carpeta **oculta** de tu Google Drive (`appDataFolder`). Ni tú ni otras apps la ven. Para eso necesita dos «clientes OAuth» de Google y cuatro secretos en GitHub.

Se usa el mismo proyecto de Google Cloud de Project Cards (ya tiene la API de Drive activada y la app publicada). Los archivos de EteroTV empiezan con `eterotv-`, así que no se mezclan con los de Project Cards.

## 1. Crear los dos clientes

En https://console.cloud.google.com, elige el proyecto de Project Cards y entra a **APIs y servicios → Credenciales → Crear credenciales → ID de cliente de OAuth**:

1. **Tipo: App de escritorio**. Nombre: `EteroTV escritorio`. Sirve para el celular y el PC (se abre el navegador).
2. **Tipo: TV y dispositivos de entrada limitada**. Nombre: `EteroTV TV`. Sirve para Google TV y Fire TV (código en pantalla).

Cada vez, Google muestra el **ID de cliente** y el **Secreto del cliente**: cópialos en ese momento (después Google no vuelve a mostrar el secreto).

## 2. Ponerlos en GitHub

En el repo **EteroTV → Settings → Secrets and variables → Actions → New repository secret**, crea:

| Nombre | Valor |
| --- | --- |
| `GOOGLE_CLIENT_ID` | ID del cliente «EteroTV escritorio» |
| `GOOGLE_CLIENT_SECRET` | Secreto del cliente «EteroTV escritorio» |
| `GOOGLE_TV_CLIENT_ID` | ID del cliente «EteroTV TV» |
| `GOOGLE_TV_CLIENT_SECRET` | Secreto del cliente «EteroTV TV» |

Después, vuelve a compilar (unir el PR o correr **Build** a mano). Una versión compilada sin estos secretos dice en Ajustes «Esta versión se compiló sin la conexión con Google».

## 3. En cada dispositivo

- **Celular y PC:** Ajustes → Sincronización → **Conectar con Google**. Se abre el navegador, eliges tu cuenta y vuelves a la app.
- **Google TV y Fire TV:** Ajustes → Sincronización → **Conectar con Google**. La TV muestra una dirección (`google.com/device`) y un código: ábrela en el celular o el PC y escribe el código.
- **Dispositivo nuevo:** en la pantalla de inicio, **Traer mi cuenta desde Google Drive** trae la cuenta IPTV sin escribirla.

La pantalla de Google dirá el nombre de la app del proyecto (por ejemplo «Project Cards»). Si prefieres otro nombre, cámbialo en **APIs y servicios → Pantalla de consentimiento de OAuth → Información de la marca**.
