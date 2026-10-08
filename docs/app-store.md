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
Can't read the scoreboard from the stands? Follow every race live on your phone: the clock, splits, places and results, plus a heads-up before your swimmer's heat.
```

### Keywords

```text
swimming,swim meet,scoreboard,live results,heat,splits,timing,pool,race,club,natation
```

### Description

```text
Can't read the scoreboard from the stands? Stuck at work while your swimmer races? Splouch puts the pool's scoreboard in your hand, live from the timing console.

Made for swim parents, swimmers, coaches and officials, at the pool or far from it.

• Live scoreboard: the race clock as it runs, then each lane's splits and finish times, with places as they land.
• Results: every heat of the meet as soon as it is swum, with each lane's seed, console and official times.
• Schedule: the meet's events, heats and start lists. Add a swimmer or a club to the filter and see only their heats.
• Heat notifications: follow a swimmer and get a heads-up when their heat is about 5 minutes away, then again when it reaches the console (where the meet's organizer allows it).

Find your meet on splouch.org, or connect straight to the pool's own Splouch server on the venue's wifi and follow along with no internet connection. Scan the QR code posted at the pool to add its server in one step.

Each meet shows in its own colours, in light or dark. Splouch speaks English, French and Spanish, and runs on iPhone and iPad.

Free, with no account, no ads and no in-app purchases. To estimate attendance, Splouch counts visitors with a random identifier kept on your device — never your name, email or IP address — and you can turn it off in Settings.

Splouch is open source: the app, the pool server and the cloud relay are all on GitHub.

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
Le tableau est illisible des gradins? Suivez chaque course en direct : chrono, temps de passage, places et résultats, et une alerte avant la série de votre nageur.
```

### Mots-clés

```text
natation,compétition,tableau,résultats en direct,série,temps de passage,chronométrage,piscine,club
```

### Description

```text
Le tableau est illisible des gradins? Coincé au bureau pendant que votre nageur plonge? Splouch met le tableau d'affichage de la piscine dans votre main, en direct de la console de chronométrage.

Pour les parents, les nageurs, les entraîneurs et les officiels, à la piscine comme à distance.

• Tableau en direct : le chrono de la course, puis les temps de passage et d'arrivée de chaque couloir, avec les places à mesure qu'elles tombent.
• Résultats : chaque série de la compétition dès qu'elle est nagée, avec les temps d'inscription, de console et officiels de chaque couloir.
• Horaire : les épreuves, les séries et les listes de départ. Ajoutez un nageur ou un club au filtre pour ne voir que leurs séries.
• Notifications : suivez un nageur et soyez averti quand sa série est à environ 5 minutes, puis quand elle passe à la console (si l'organisateur de la compétition le permet).

Trouvez votre compétition sur splouch.org, ou branchez-vous directement au serveur Splouch de la piscine par le wifi du site pour suivre même sans connexion Internet. Balayez le code QR affiché à la piscine pour ajouter son serveur en un geste.

Chaque compétition s'affiche à ses couleurs, en mode clair ou sombre. Splouch parle français, anglais et espagnol, et fonctionne sur iPhone et iPad.

Gratuit, sans compte, sans publicité et sans achat intégré. Pour estimer l'assistance, Splouch compte les visiteurs à l'aide d'un identifiant aléatoire conservé sur votre appareil — jamais votre nom, votre courriel ni votre adresse IP — et vous pouvez le désactiver dans les Réglages.

Splouch est un logiciel libre : l'app, le serveur de piscine et le relais infonuagique sont sur GitHub.

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
¿No alcanzas a leer el marcador desde las gradas? Sigue cada carrera en vivo: cronómetro, parciales, lugares y resultados, y un aviso antes de la serie de tu nadador.
```

### Palabras clave

```text
natación,competencia,marcador,resultados en vivo,serie,parciales,cronometraje,piscina,club,nado
```

### Descripción

```text
¿No alcanzas a leer el marcador desde las gradas? ¿En el trabajo mientras tu nadador compite? Splouch pone el marcador de la alberca en tu mano, en vivo desde la consola de cronometraje.

Para papás, nadadores, entrenadores y jueces, en la alberca o lejos de ella.

• Marcador en vivo: el cronómetro de la carrera, luego los parciales y tiempos finales de cada carril, con los lugares a medida que llegan.
• Resultados: cada serie de la competencia en cuanto se nada, con los tiempos de inscripción, de consola y oficiales de cada carril.
• Programa: las pruebas, series y listas de salida. Agrega un nadador o un club al filtro para ver solo sus series.
• Notificaciones: sigue a un nadador y recibe un aviso cuando su serie esté a unos 5 minutos, y otro cuando llegue a la consola (si el organizador de la competencia lo permite).

Encuentra tu competencia en splouch.org, o conéctate directamente al servidor Splouch de la alberca por el wifi del lugar para seguirla incluso sin conexión a Internet. Escanea el código QR de la alberca para agregar su servidor en un solo paso.

Cada competencia se muestra con sus propios colores, en modo claro u oscuro. Splouch habla español, inglés y francés, y funciona en iPhone y iPad.

Gratis, sin cuenta, sin anuncios y sin compras dentro de la app. Para estimar la asistencia, Splouch cuenta a los visitantes con un identificador aleatorio guardado en tu dispositivo —nunca tu nombre, tu correo ni tu dirección IP— y puedes desactivarlo en Ajustes.

Splouch es de código abierto: la app, el servidor de la alberca y el relé en la nube están en GitHub.

Los resultados que muestra Splouch son en vivo y no oficiales. Los resultados validados los publica el organizador de la competencia.
```

## Review notes

Sign-in required: no. The same text goes in the reply to App Review and in the
Notes field of App Review Information (English, 4000 characters at most).

```text
Splouch is a free, read-only spectator app for swim meets. There is no account or sign-in, no user-generated content and no paid content or in-app purchase.

1. SCREEN RECORDING
Attached: recorded on an iPhone running the latest iOS, from launch through the typical flow — introduction, meet list, a live meet's Scoreboard, Results and Schedule, following a swimmer and receiving the heat notification, and Settings.

2. PURPOSE AND AUDIENCE
For swim parents, swimmers, coaches and officials. At a meet the pool's scoreboard is often too far or too small to read from the stands, and family who cannot attend have no way to follow the races. Splouch shows the meet live on the phone, straight from the timing console: the race clock, each lane's splits, finish times and places, every heat's results and the schedule, and it notifies spectators shortly before a swimmer they follow is due to swim.

3. HOW TO TEST
No login or sample file is needed.
1. Launch the app. A short introduction can be paged through or skipped.
2. The meet list shows the meets published on splouch.org. Meets badged "Test" are demo meets that run around the clock: a few events of two or three heats swum in real time, then they start over.
3. Tap a Test meet. Scoreboard shows the heat in the water: the running clock, then splits, finish times and places. Results lists the finished heats; Schedule the events, heats and start lists.
4. Heat notifications: on Schedule, tap the bell at the top and add a swimmer from the start list. iOS asks for notification permission at that moment, never at launch. A Time Sensitive notification arrives when the swimmer's heat is about 5 minutes away and again when it reaches the console; tapping it opens that heat.
5. Settings (gear icon on the meet list): display options and the attendance counting toggle.

Local Network permission: at a pool, the timing console also feeds a small Splouch server on the venue's wifi, which the app finds over Bonjour (_splouch._tcp) so spectators can follow without internet. Declining it only hides those local servers. The QR code posted at a pool opens https://splouch.org/add?server=..., a universal link that offers to add that pool's server.

4. EXTERNAL SERVICES
- Splouch Cloud at splouch.org (see below): the meet list and live meet data.
- Apple Push Notification service: heat notifications, sent directly from Splouch Cloud.
- Optionally, a pool's own Splouch server on its local network.
No third-party SDK, analytics, advertising, authentication, payment or AI service.

WHAT SPLOUCH CLOUD IS
Splouch is an open-source (MIT) live scoreboard system for swimming. At the pool, a Raspberry Pi reads the timing console's serial feed, adds swimmer and club names from the organizer's meet file, and drives the scoreboard TV. The Pi can also relay the meet over one outbound connection to a Splouch Cloud server, which serves it to spectators' phones. splouch.org is the public Splouch Cloud, operated by the developer of this app. Organizers publish with a revocable key, and only scoreboard, results and schedule data leave the pool.
Source code:
- Server, scoreboard and Splouch Cloud: https://github.com/olivierouellet/Splouch
- This iOS app: https://github.com/olivierouellet/Splouch-ios
- Android app: https://github.com/olivierouellet/Splouch-android

5. REGIONS
The app works the same in every region, in English, French and Spanish. Which meets are listed depends only on what organizers publish, not on the user's region.

6. REGULATION AND THIRD-PARTY MATERIAL
Not a regulated industry, and no protected third-party material. Start lists, times and results are published by each meet's organizer from their own timing system; Splouch displays them, labelled as live and unofficial.

Attendance: Splouch counts visitors with a random identifier per server, never derived from the device and never used for tracking. It can be turned off in Settings.
```

## Review screen recording

Physical iPhone on the latest iOS, Screen Recording from Control Centre. Delete the app
first so it launches fresh. One take:

1. Home screen, tap Splouch.
2. Page through the introduction.
3. Meet list on splouch.org; open a Test meet.
4. Scoreboard through a race to the finish and its places.
5. Results, open a heat; Schedule, scroll.
6. Bell, add a swimmer, allow notifications; lock the phone until the notification
   arrives (about 5 minutes before the heat), tap it.
7. Back on the meet list, open Settings, show the counting toggle.
