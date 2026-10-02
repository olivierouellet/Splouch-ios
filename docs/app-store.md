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
| Support URL | <https://splouch.ca/support> (page still to publish) |
| Privacy policy URL | <https://splouch.ca/privacy> (page still to publish) |
| Age rating | 4+ (every questionnaire answer "None" / "No") |
| App Privacy | Device ID: collected, used for Analytics, not linked to the user, not used for tracking. Matches `App/PrivacyInfo.xcprivacy`. |
| Export compliance | Answered by `ITSAppUsesNonExemptEncryption = NO` in Info.plist |

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

Meets come from splouch.ca, or straight from the pool's own Splouch server on the venue's wifi, so you can follow along even without an internet connection. Scan the QR code posted at the pool to add its server in one step.

Each meet shows in its own colours, in light or dark. Splouch speaks English, French and Spanish, and runs on iPhone and iPad.

No account, no ads. Splouch only counts visitors anonymously to estimate attendance; no personal information is collected or shared.

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

Les compétitions viennent de splouch.ca, ou directement du serveur Splouch de la piscine par le wifi du site, pour suivre même sans connexion Internet. Balayez le code QR affiché à la piscine pour ajouter son serveur en un geste.

Chaque compétition s'affiche à ses couleurs, en mode clair ou sombre. Splouch parle français, anglais et espagnol, et fonctionne sur iPhone et iPad.

Aucun compte, aucune publicité. Splouch compte seulement les visiteurs de façon anonyme pour estimer l'assistance; aucun renseignement personnel n'est recueilli ni partagé.

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

Las competencias vienen de splouch.ca, o directamente del servidor Splouch de la alberca por el wifi del lugar, para seguirlas incluso sin conexión a Internet. Escanea el código QR de la alberca para agregar su servidor en un solo paso.

Cada competencia se muestra con sus propios colores, en modo claro u oscuro. Splouch habla español, inglés y francés, y funciona en iPhone y iPad.

Sin cuenta, sin anuncios. Splouch solo cuenta visitantes de forma anónima para estimar la asistencia; no se recopila ni comparte información personal.

Los resultados que muestra Splouch son en vivo y no oficiales. Los resultados validados los publica el organizador de la competencia.
```

## Review notes

Sign-in required: no. Notes (English, for App Review):

```text
Splouch is the spectator app for swim meets timed with the Splouch scoreboard. No account or sign-in is needed.

How to see it working:
1. Launch the app. The first screen lists the meets currently published on splouch.ca.
2. Tap "Finale régionale Est-du-Québec - Régionaux". A demo recording is replaying on this meet for the whole review period, so races start and finish every few minutes.
3. The Scoreboard tab shows the live race clock, then splits, finish times and places. The Results tab lists every heat swum so far, the Schedule tab the meet's events.

An empty meet list means no meet is running on the server at that moment; this is the normal state between meets, not an error.

Local network permission: at a pool, the timing console feeds a small Splouch server on the venue's wifi, which the app finds over Bonjour (_splouch._tcp). This lets spectators follow a meet without internet access. Declining the permission only hides those local servers; meets on splouch.ca still work.

The QR code posted at a pool opens https://splouch.ca/add?server=..., a universal link that offers to add that pool's server to the app.

Splouch counts visitors anonymously to estimate attendance: a random identifier per server, never derived from the device and never used for tracking. Results are live and unofficial, as stated in the app.
```
