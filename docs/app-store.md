# App Store Connect text

What goes in each App Store Connect field, per listing. Character limits are
App Store Connect's: name and subtitle 30, promotional text 170, keywords 100
(commas, no spaces after them), description and review notes 4000.

Screenshots are in [`Screenshots/AppStore/`](../Screenshots/AppStore/), one folder
per listing.

## Shared fields

| Field | Value |
| --- | --- |
| Primary language | English (Canada) |
| Category | Sports |
| Support URL | <https://splouch.org/support> (page still to publish) |
| Privacy policy URL | <https://splouch.org/privacy> |
| Age rating | 4+ (every questionnaire answer "None" / "No") |
| App Privacy | See [App Privacy](#app-privacy) |
| Export compliance | Answered by `ITSAppUsesNonExemptEncryption = NO` in Info.plist |

## App Privacy

"Data Used to Track You": none. "Do you or your third-party partners collect data
from this app?" Yes, two types. Matches `App/PrivacyInfo.xcprivacy` and the Android
Data safety form.

| Data type | Purposes | Linked to the user | Tracking | What it is |
| --- | --- | --- | --- | --- |
| Identifiers › Device ID | Analytics, App Functionality | No | No | Analytics: the attendance id (app.md `C-10`), a random UUID per server sent with `join_meet` when a meet opens; Settings › Privacy turns it off and deletes it. App Functionality: the APNs device token (`N-07`), sent only once a swimmer is followed |
| User Content › Other User Content | App Functionality | No | No | The names and clubs followed for heat notifications (`N-07`, `N-09`); the meet's node deletes them when the meet leaves it or the spectator stops following |

Not linked: there is no account, the id is random per server, and the names are the
start list's. Everything else stays on the device, a pool's Pi gets no id (`C-02`),
and there is no third-party SDK: notifications go straight from the meet's cloud node
to APNs.

App Store Connect has no field for "optional", "encrypted in transit" or deletion,
which Play's form asks; the Android answers to those (optional, HTTPS, deleted on
their own, no deletion link) need no iOS counterpart.

## en-CA

### Name

```text
Splouch
```

### Subtitle

```text
Live swim meet scoreboard
```

### Promotional text

```text
Follow the race from the stands: the live clock, splits and places as they land, every heat's results and the meet schedule.
```

### Keywords

```text
swimming,swim meet,scoreboard,live results,heat,splits,timing,pool,race,club,natation
```

### Description

```text
Splouch puts the pool's scoreboard in your hand.

Pick a meet and follow it from the stands, live from the timing console:

• Scoreboard: the race clock, then each lane's splits and finish times, with places as they land.
• Results: every heat of the meet, as soon as it is swum.
• Schedule: the meet's events and heats, so you know when your swimmer is up.
• Notifications for the swimmers you follow: when their heat is coming up and when it reaches the console.

Meets come from splouch.org, or straight from the pool's own Splouch server on the venue's wifi, so you can follow along even without an internet connection. Scan the QR code posted at the pool to add its server in one step.

Each meet shows in its own colours, in light or dark. Splouch speaks English, French and Spanish, and runs on iPhone and iPad.

No account, no ads. To estimate attendance, Splouch counts visitors with a random identifier kept on your device — never your name, email or IP address — and you can turn it off in Settings.

Results shown in Splouch are live and unofficial. Validated results are published by the meet's organizer.
```

## fr-CA

### Nom

```text
Splouch
```

### Sous-titre

```text
Tableau de natation en direct
```

### Texte promotionnel

```text
Suivez la course des gradins : le chrono en direct, les temps de passage et les places à l'arrivée, les résultats de chaque série et l'horaire.
```

### Mots-clés

```text
natation,compétition,tableau,résultats en direct,série,temps de passage,chronométrage,piscine,club
```

### Description

```text
Splouch met le tableau d'affichage de la piscine dans votre main.

Choisissez une compétition et suivez-la des gradins, en direct de la console de chronométrage :

• Tableau : le chrono de la course, puis les temps de passage et d'arrivée de chaque couloir, avec les places à mesure qu'elles tombent.
• Résultats : chaque série de la compétition, dès qu'elle est nagée.
• Horaire : les épreuves et les séries de la compétition, pour savoir quand votre nageur plonge.
• Notifications pour les nageurs que vous suivez : quand leur série approche et quand elle passe à la console.

Les compétitions viennent de splouch.org, ou directement du serveur Splouch de la piscine par le wifi du site, pour suivre même sans connexion Internet. Balayez le code QR affiché à la piscine pour ajouter son serveur en un geste.

Chaque compétition s'affiche à ses couleurs, en mode clair ou sombre. Splouch parle français, anglais et espagnol, et fonctionne sur iPhone et iPad.

Aucun compte, aucune publicité. Pour estimer l'assistance, Splouch compte les visiteurs à l'aide d'un identifiant aléatoire conservé sur votre appareil — jamais votre nom, votre courriel ni votre adresse IP — et vous pouvez le désactiver dans les Réglages.

Les résultats affichés dans Splouch sont en direct et non officiels. Les résultats validés sont publiés par l'organisateur de la compétition.
```

## es-MX

### Nombre

```text
Splouch
```

### Subtítulo

```text
Marcador de natación en vivo
```

### Texto promocional

```text
Sigue la carrera desde las gradas: el cronómetro en vivo, los parciales y los lugares al llegar, los resultados de cada serie y el programa.
```

### Palabras clave

```text
natación,competencia,marcador,resultados en vivo,serie,parciales,cronometraje,piscina,club,nado
```

### Descripción

```text
Splouch pone el marcador de la alberca en tu mano.

Elige una competencia y síguela desde las gradas, en vivo desde la consola de cronometraje:

• Marcador: el cronómetro de la carrera, luego los parciales y tiempos finales de cada carril, con los lugares a medida que llegan.
• Resultados: cada serie de la competencia, en cuanto se nada.
• Programa: las pruebas y series de la competencia, para saber cuándo le toca a tu nadador.
• Notificaciones para los nadadores que sigues: cuando se acerca su serie y cuando llega a la consola.

Las competencias vienen de splouch.org, o directamente del servidor Splouch de la alberca por el wifi del lugar, para seguirlas incluso sin conexión a Internet. Escanea el código QR de la alberca para agregar su servidor en un solo paso.

Cada competencia se muestra con sus propios colores, en modo claro u oscuro. Splouch habla español, inglés y francés, y funciona en iPhone y iPad.

Sin cuenta, sin anuncios. Para estimar la asistencia, Splouch cuenta a los visitantes con un identificador aleatorio guardado en su dispositivo —nunca su nombre, su correo ni su dirección IP— y puede desactivarlo en Ajustes.

Los resultados que muestra Splouch son en vivo y no oficiales. Los resultados validados los publica el organizador de la competencia.
```

## Review notes

Sign-in required: no. Notes (English, for App Review):

```text
Splouch is the spectator app for swim meets timed with the Splouch scoreboard. No account or sign-in is needed.

How to see it working:
1. Launch the app. The first screen lists the meets currently published on splouch.org.
2. Tap "Finale régionale Est-du-Québec - Régionaux". A demo recording is replaying on this meet for the whole review period, so races start and finish every few minutes.
3. The Scoreboard tab shows the live race clock, then splits, finish times and places. The Results tab lists every heat swum so far, the Schedule tab the meet's events.

An empty meet list means no meet is running on the server at that moment; this is the normal state between meets, not an error.

Heat notifications: on the Schedule tab, the bell at the top opens the Notifications sheet. Add a swimmer from the meet's start list; iOS asks for notification permission at that moment, never at launch. A Time Sensitive notification arrives when that swimmer's heat is about 5 minutes away and when it reaches the timing console; tapping it opens the meet's schedule at that heat. Declining the permission keeps the followed swimmers on the device and sends nothing.

Local network permission: at a pool, the timing console feeds a small Splouch server on the venue's wifi, which the app finds over Bonjour (_splouch._tcp). This lets spectators follow a meet without internet access. Declining the permission only hides those local servers; meets on splouch.org still work.

The QR code posted at a pool opens https://splouch.org/add?server=..., a universal link that offers to add that pool's server to the app.

Splouch counts visitors to estimate attendance, and the reader can turn it off in Settings: a random identifier per server, never derived from the device and never used for tracking. Results are live and unofficial, as stated in the app.
```
