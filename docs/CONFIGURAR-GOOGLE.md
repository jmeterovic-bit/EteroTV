# Configurar la conexión con Google Drive (una sola vez)

EteroTV guarda tu biblioteca (favoritos, avance, cuenta IPTV, PIN y carpetas protegidas) en una carpeta **oculta** de tu Google Drive (`appDataFolder`). Ni tú ni otras apps la ven. Para eso necesita un «cliente OAuth» de Google y dos secretos en GitHub.

Se usa el mismo proyecto de Google Cloud de Project Cards (se llama **ZENDE**; ya tiene la API de Drive activada y la app publicada). Los archivos de EteroTV empiezan con `eterotv-`, así que no se mezclan con los de Project Cards.

## 1. Crear el cliente

En https://console.cloud.google.com, elige el proyecto ZENDE y entra a **APIs y servicios → Credenciales → Crear credenciales → ID de cliente de OAuth**:

- **Tipo: App de escritorio**. Nombre: `EteroTV escritorio`. Sirve para el celular y el PC (se abre el navegador).

Google muestra el **ID de cliente** y el **Secreto del cliente**: cópialos en ese momento (si después no se ve el secreto, en el cliente usa «Add secret»).

No hace falta un cliente de TV: Google no deja usar la carpeta oculta con el inicio de sesión por código de las TV. Si creaste «EteroTV TV» y sus secretos `GOOGLE_TV_*`, puedes borrarlos.

## 2. Ponerlos en GitHub

En el repo **EteroTV → Settings → Secrets and variables → Actions → New repository secret**, crea:

| Nombre | Valor |
| --- | --- |
| `GOOGLE_CLIENT_ID` | ID del cliente «EteroTV escritorio» |
| `GOOGLE_CLIENT_SECRET` | Secreto del cliente «EteroTV escritorio» |

Después, vuelve a compilar (unir el PR o correr **Build** a mano). Una versión compilada sin estos secretos dice en Ajustes «Esta versión se compiló sin la conexión con Google».

## 3. En cada dispositivo

- **Celular y PC:** Ajustes → Sincronización → **Conectar con Google** → «En este dispositivo». Se abre el navegador, eliges tu cuenta y vuelves a la app.
- **Google TV y Fire TV** (una vez por TV): en la TV, Ajustes → Sincronización → **Conectar con Google**; muestra un código de 6 números. En el celular o el PC ya conectado: Ajustes → Sincronización → **Conectar una TV**, elige la TV y escribe el código. Tienen que estar en la misma red.
- **Dispositivo nuevo:** en la pantalla de inicio, **Traer mi cuenta desde Google Drive** trae la cuenta IPTV sin escribirla (en la TV, con el código de arriba).

La pantalla de Google dirá el nombre de la app del proyecto (por ejemplo «Project Cards»). Si prefieres otro nombre, cámbialo en **APIs y servicios → Pantalla de consentimiento de OAuth → Información de la marca**.
