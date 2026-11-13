# Escaping From Hell

NES-Spiel: Ein Held flieht aus der Hölle, besiegt 10 Dämonen in 10 Dungeons und kommt frei.

Läuft auf echter NES-Hardware (NTSC, MMC3 mit Batterie-RAM) und in Emulatoren wie Mesen oder FCEUX. Die ROM gibt es als Anhang am GitHub-Release (`EscapingFromHell-vX.Y.nes`).

## Spielen

- **Titelmenü:** CONTINUE (wenn ein Spielstand da ist), NEW GAME, CHEAT, DELETE SAVE.
- **CHEAT:** alle 10 Dungeons offen, keine Herzen verlieren, es wird nichts gespeichert. Pro Dungeon hast du genau die Fähigkeiten, die du dort normalerweise hättest.
- **Overworld:** sicher, keine Gegner. Zum offenen Tor laufen, **A** = Dungeon betreten. Die Dungeons sind der Reihe nach 1 bis 10 freigeschaltet.
- **Dungeon:** ein Boss-Kampf, 3 Herzen. Jeder Dämon hat 3 Phasen und wird mit jeder stärker. Bei 0 Herzen startet der Kampf neu.
- **Sieg:** Autosave, zurück in die Overworld, das nächste Tor ist offen. Nach Dämon 10 kommt das Ende, danach frei weiterspielen.

### Steuerung im Dungeon

| Taste | Wirkung |
|---|---|
| D-Pad links/rechts | laufen |
| A | springen (länger halten = höher) |
| B | Schwert |
| Start | Pause |
| Start, dann Select | Kampf aufgeben |

### Fähigkeiten (dauerhaft, gespeichert)

| Von Dämon | Fähigkeit | Taste |
|---|---|---|
| 1 Imp | Dash (kurz unverwundbar) | Select |
| 3 Knochenhund | Doppelsprung | A in der Luft |
| 5 Geflügelter Dämon | Feuerball | Hoch + B |
| 7 Riesenkröte | Schild (blockt von vorn) | Runter halten am Boden |
| 9 Oni-Kriegsherr | Schwertwelle | B bei vollen 3 Herzen |

Alle Dungeons sind auch ohne Fähigkeiten schaffbar. In Dungeon n wirken nur die Fähigkeiten der Dämonen 1 bis n−1 (auch beim Wiederholen alter Dungeons).

FCEUX unter Ubuntu/Wayland flackert: `QT_QPA_PLATFORM=xcb fceux <rom>`.

## Bauen und testen

- Bauen: `make` → `build/EscapingFromHell.nes`
- Testen: `make test` (Mesen2 headless, ca. 5 min)
- Werkzeuge und Einrichtung: `docs/TECH.md`

## Dokumentation

- Plan und Regeln: `CLAUDE.md`, `docs/PLAN.md`
- Spielidee, Bosse, Balance: `docs/GAMEDESIGN.md`
- Technik, Build, Entscheidungslog: `docs/TECH.md`
- Releases: `docs/RELEASE.md`
- Ursprüngliches Konzept: `Concept/`

Status: v1.0 – komplettes Spiel: 10 Dämonen, 5 Fähigkeiten, Pixelgrafik, Soundeffekte, Titel, Intro, Ende, Cheat-Modus. Musik folgt nach v1.0.
