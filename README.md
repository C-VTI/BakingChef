# BakingChef 🍞

Back-Zeitplan als abhakbare Taskliste mit Erinnerungen – für iPhone und Apple Watch.

- **Rezepte** als JSON (eingebaut: *Sauerteig Brot*, *Anstellgut auffrischen*), eigene per „Importieren“
- **Menge** mit Multiplikator (0.5er-Schritte)
- **Start jetzt** → Zeitplan wird vorwärts berechnet
- **Benachrichtigungen** (lokal, kein Server): 5 min vorher, bei Fälligkeit (mit Knopf „Erledigt ✓“), bei Fertig. Optional pro Schritt eine eigene Erinnerung (z. B. Ofen vorheizen)
- **Verspätung** wird angezeigt („Du bist 5 min später dran“) und lässt sich mit einem Tipp übernehmen. Der Plan verschiebt sich nie automatisch
- **Pause** (Kühlschrank): Countdown friert ein, beim Fortsetzen verschieben sich alle offenen Schritte um die Pausendauer
- **Zeit anpassen** mit dem iOS-Timer-Scrollrad: Restzeit direkt setzen oder Plan später/früher verschieben (auch: Tipp auf den Countdown)
- **Live Activity**: Countdown auf dem Sperrbildschirm / in der Dynamic Island
- **Apple Watch**: Countdown, Erledigt, +5 min, Pause. Benachrichtigungen kommen auf die Uhr, wenn das iPhone gesperrt ist

## Einrichten (gratis Apple-ID)

1. Xcode öffnen → **Settings → Accounts** → Apple-ID hinzufügen (ergibt ein „Personal Team“).
2. `BakingChef.xcodeproj` öffnen.
3. In `project.yml` (danach `xcodegen generate`) oder im Projekt **BakingChef** → Tab *Build Settings* (Ebene Projekt, nicht Target):
   - `BASE_BUNDLE_ID` auf etwas Eindeutiges ändern, z. B. `ch.<deinname>.bakingchef`
   - `DEVELOPMENT_TEAM` → die ID deines Personal Teams (eingetragen ist die des Repo-Besitzers; alternativ in jedem der 3 Targets unter *Signing & Capabilities* das Team wählen)
4. iPhone per Kabel verbinden, auf dem iPhone **Einstellungen → Datenschutz & Sicherheit → Entwicklermodus** aktivieren.
5. Schema **BakingChef** + dein iPhone wählen → ▶︎ Run.
6. Beim ersten Start auf dem iPhone: **Einstellungen → Allgemein → VPN & Geräteverwaltung** → Entwickler-App vertrauen.
7. Watch: Die Watch-App wird mit der iPhone-App installiert (ggf. in der Watch-App auf dem iPhone unter „Verfügbare Apps“ installieren). Alternativ Schema **BakingChefWatch** mit deiner Uhr als Ziel starten. Auf der Uhr ebenfalls den Entwicklermodus aktivieren.

> ⚠️ Mit der **gratis** Apple-ID läuft die App nach **7 Tagen** ab → einfach erneut aus Xcode starten (Daten bleiben erhalten). Mit dem Developer Program (99 USD/Jahr) 1 Jahr + TestFlight.

Projektdatei neu erzeugen (nach Änderungen an `project.yml` oder neuen Dateien):

```sh
brew install xcodegen   # einmalig
xcodegen generate
```

## App-Icon

Das Icon (Brotlaib im Vintage-Stil) wird per Script gezeichnet und liegt als 1024×1024-PNG in
`BakingChef/Assets.xcassets` und `BakingChefWatch/Assets.xcassets`. Nach Änderungen an Farben/Formen neu erzeugen:

```sh
swiftc Tools/make-icon.swift -o /tmp/make-icon
/tmp/make-icon BakingChef/Assets.xcassets/AppIcon.appiconset/AppIcon.png
cp BakingChef/Assets.xcassets/AppIcon.appiconset/AppIcon.png BakingChefWatch/Assets.xcassets/AppIcon.appiconset/
```

## Rezept-Format (JSON)

```json
{
  "id": "sauerteig-brot",
  "name": "Sauerteig Brot",
  "description": "optional",
  "steps": [
    {
      "title": "Zutaten mischen",
      "ingredients": [
        { "name": "Wasser", "amount": 400, "amountMax": 450, "unit": "g" },
        { "name": "Salz", "amount": 10, "unit": "g" }
      ],
      "wait": "01:30"
    },
    {
      "title": "Backen 240° mit Deckel",
      "reminder": { "before": "00:45", "text": "Ofen mit Topf auf 240° vorheizen" },
      "wait": "00:20"
    }
  ]
}
```

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `id` | nein | Eindeutige ID; gleiche ID ersetzt ein vorhandenes Rezept. Fehlt sie, wird sie aus dem Namen gebildet |
| `name` | ja | Anzeigename |
| `steps[].title` | ja | Name des Schritts |
| `steps[].wait` | nein | Wartezeit **nach** diesem Schritt bis zum nächsten bzw. bis fertig (`"HH:MM"`). Ohne `wait` überall → Rezept ohne Zeitplan |
| `steps[].ingredients` | nein | `name`, `amount`, optional `amountMax` (Bereich) und `unit` (Standard `g`) |
| `steps[].note` | nein | Notiz (erscheint in der Benachrichtigung, wenn keine Zutaten) |
| `steps[].reminder` | nein | Zusätzliche Erinnerung `before` (`"HH:MM"`) vor dem Schritt |

Eine Datei darf ein Rezept, ein Array von Rezepten oder `{ "recipes": [...] }` enthalten.
Import: JSON-Datei in iCloud Drive / „Auf meinem iPhone“ ablegen (oder per AirDrop) → in der App **Importieren**.

## Aufbau

| Ordner | Inhalt |
|---|---|
| `Shared/Core` | Rezept-Modell, Zeitplan-Logik (`BakeSession`), Sync – plattformunabhängig |
| `Shared/UI` | Countdown-View (iPhone + Watch) |
| `Shared/LiveActivity` | Daten der Live Activity |
| `BakingChef` | iPhone-App (Views, Benachrichtigungen, Live Activity, Watch-Sync) |
| `BakingChefWidget` | Live Activity / Dynamic Island |
| `BakingChefWatch` | Watch-App |
| `Recipes` | Eingebaute Rezepte |
| `Tools` | Hilfsscripts (App-Icon erzeugen) |
