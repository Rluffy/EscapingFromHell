# PLAN – Escaping From Hell

Umsetzbar durch einen Orchestrator-Agenten. Zuerst `CLAUDE.md` lesen. Spielregeln: `GAMEDESIGN.md`. Technik: `TECH.md`.

## Arbeitsweise

- **Orchestrator:** starkes Modell (Opus 5.5). Liest den Plan, zerlegt den Meilenstein in Arbeitspakete, verteilt sie, prüft Build/Tests, committet. Schreibt selbst nur wenig Code.
- **Subagenten:** `general-purpose` mit explizitem Modell. Haiku 5.5 für Dateiarbeit, Skripte, Doku, Palette. Sonnet 5.5 für C/Assembler, Boss-Logik, Tests. **Kein Bruno/Carli.** Alle mit `/ponytail`.
- **Arbeitspaket:** klein, eine Aufgabe, klare Abnahme („`make` und `make test` grün" plus ggf. konkretes Ergebnis). Der Subagent bekommt nur das, was er braucht (relevante Doc-Abschnitte, Dateipfade).
- **Autonom pro Meilenstein:** Der Orchestrator arbeitet den Meilenstein allein ab. Fragen an den Nutzer nur, wenn es ohne Antwort nicht weitergeht. Sonst selbst entscheiden, in den Docs festhalten.
- **Definition of Done (Arbeitspaket):** `make` grün, `make test` grün, Docs aktualisiert, ein Commit.
- **Meilenstein-Ende:** Stopp und Bericht an den Nutzer: was fertig ist, Teststatus, Screenshot in `docs/screenshots/`, ROM in `dist/` zum Selbstspielen, Liste „Entscheidungen, die ich selbst getroffen habe". **Erst nach Okay** Tag setzen und Release (`RELEASE.md`), dann nächsten Meilenstein starten.
- Status unten in der Tabelle nachführen.

**Nutzer-Entscheidung 2026-11-12:** v0.5 bis v1.0 ohne Zwischenstopp durcharbeiten. Pro Meilenstein trotzdem: Tests grün, Docs, Commits, ROM in `dist/`, kurzer Bericht an den Nutzer (ROM schicken). Tags und GitHub-Releases v0.5 bis v1.0 erst gesammelt nach Okay des Nutzers. Repo bleibt privat, bis der Nutzer die Freigabe gibt. Musik bleibt Folge-Meilenstein nach v1.0.

## Meilensteine

| Version | Inhalt | Status |
|---|---|---|
| v0.1 | Rough Design: Repo, Docs, Regeln, Plan | erledigt |
| v0.2 | Toolchain, Hello-ROM, Test-Pipeline, Overworld mit Scrolling, Spielerbewegung, gesperrte/offene Dungeon-Tore, Dungeon-Eingang (Platzhalter-Grafik) | erledigt |
| v0.3 | Vertikal-Slice: Arena, Spielersteuerung, Schwert, 3 Herzen, Boss 1 (Imp) mit 3 Phasen, Sieg, Autosave, Dash | erledigt |
| v0.4 | Boss 2 (Geist), Boss 3 (Knochenhund), Doppelsprung | erledigt |
| v0.5 | Boss 4 (Lavaschlange), Boss 5 (Geflügelter Dämon), Feuerball | in Arbeit |
| v0.6 | Boss 6 (Spiegeldämon), Boss 7 (Riesenkröte), Schild | offen |
| v0.7 | Boss 8 (Spinnenkönigin), Boss 9 (Oni-Kriegsherr), Schwertwelle | offen |
| v0.8 | Boss 10 (Höllenfürst), komplette Spielreihenfolge, Ende-Logik | offen |
| v0.9 | Art-Pass (Pixelkunst im Stil von DesignIdea1/2), Soundeffekte, Titelbildschirm, Intro, Ende, Overworld-Dekor mit Idle-Animationen | offen |
| v1.0 | Balance, Fehlerbehebung, Release mit ROM | offen |

Musik (Overworld, Dungeon, Boss) ist ein Folge-Meilenstein nach v1.0 oder, falls der Nutzer es will, Teil von v0.9.

## Arbeitspakete v0.2 (Vorschlag, Orchestrator darf anpassen)

1. Tools installieren (`TECH.md`): cc65, gh, xvfb, python3-pil, Mesen2 nach `tools/mesen/`. Haiku.
2. `Makefile`, Linker-Config (MMC3), iNES-Header, minimales Hello-ROM (Hintergrundfarbe). Sonnet.
3. Test-Pipeline: Lua-Smoke-Test, `make test`, Screenshot-Skript. `emu.stop`/`emu.exit` klären. Sonnet.
4. `tools/png2chr.py` plus Platzhalter-PNGs (Spieler, Kacheln). Haiku.
5. Overworld: Scrolling-Karte, Spieler läuft, Kollision, 10 Dungeon-Tore (gesperrt/offen), Dungeon betreten mit A (Platzhalter-Bildschirm). Sonnet.
6. Tests und Screenshot, Docs aktualisieren, Bericht. Orchestrator.

Umsetzung v0.2: Paket 1 hat der Orchestrator selbst erledigt (nur Installationen). Pakete 2 und 3 liefen als ein Sonnet-Auftrag und ein Commit, weil sich ihre TECH.md-Abschnitte überschneiden. Screenshots: `docs/screenshots/v0.2-overworld.png`, `v0.2-dungeon.png`.

## Arbeitspakete v0.3

1. Arena (ein Bildschirm, Side-View, Boden/Plattformen), Spieler-Physik (laufen, springen, Schwerkraft), Schwert (B), 3 Herzen als HUD, Treffer → −1 Herz, ca. 1,5 s unverwundbar + Rückstoß, 0 Herzen → Dungeon-Neustart. Test-Dummy statt Boss. Sonnet.
2. Boss-Rahmen (Datentabelle HP/Phasen-Grenzen, Phasenwechsel-Effekt, Boss-Name-Intro) und Dämon 1 Imp: hüpft, spuckt Feuerbälle, 3 sichtbar verschiedene Phasen, ca. 20 Treffer (nach Nutzer-Test auf 10 gesenkt, plus Boss-HP-Balken). Sonnet. **Erledigt** (Screenshots `v0.3-imp-phase1.png`, `v0.3-imp-phase3.png`).
3. Sieg-Moment, Autosave in PRG-RAM (Format `TECH.md`, Laden beim Start), Fähigkeit Dash. Sonnet. **Erledigt** (Screenshot `v0.3-victory.png`; Steuerung: Select = Dash, Start dann Select = Kampf aufgeben).
4. Tests, Screenshots, Docs, Bericht. Orchestrator. **Erledigt.**

Hinweis für v0.4: Code im festen 16-KB-Bereich belegt nach v0.3 ca. 9,3 KB. Ab v0.4 Boss-Code in umschaltbare PRG-Bänke ($8000/$A000) legen, erstes Paket von v0.4.

## Arbeitspakete v0.4

1. PRG-Banking: Boss-Code/-Daten in umschaltbare Bänke ($8000/$A000), fester Bereich nur Kern (NMI, Hauptschleife, Overworld, Arena-Grundlage). Sonnet. **Erledigt** (Details `TECH.md` „PRG-Banking (v0.4)").
2. Dämon 2 Geist (Dungeon 2): schwebt, flackert, zeitweise unsichtbar, 3 Phasen, HP-Balken. Sonnet. **Erledigt** (`src/ghost.c` in Bank 1, `tests/ghost.lua`, Screenshots `v0.4-ghost-phase1.png`, `v0.4-ghost-phase3.png`).
3. Dämon 3 Knochenhund (Dungeon 3): rennt quer durch die Arena, Biss/Sprungangriff, 3 Phasen. Gibt Doppelsprung (zweites A in der Luft). Sonnet. **Erledigt** (`src/hound.c` in Bank 2, `tests/hound.lua`, Doppelsprung-Tests in `tests/progress.lua`, Screenshots `v0.4-hound-phase1.png`, `v0.4-hound-phase3.png`).
4. Tests, Screenshots, Docs, Bericht. Orchestrator. **Erledigt.**

Schwierigkeit: Nutzer fand den Imp mit 20 HP zu schwer, mit 10 HP passend. Neue Bosse daher in derselben Größenordnung (Geist ca. 12, Knochenhund ca. 14 HP), Angriffe gut lesbar und ausweichbar.

## Arbeitspakete v0.5

1. Dämon 4 Lavaschlange (Dungeon 4, Bank 3): groß und lang, schlängelt am Arena-Rand (Boden/Wände), taucht in Lava ab und wieder auf, spuckt Feuer, 3 Phasen, ca. 14 HP. Sonnet. **Erledigt** (`src/snake.c` in Bank 3, `tests/snake.lua`, Screenshots `v0.5-snake-phase1.png`, `v0.5-snake-phase3.png`; Test-Dummy-Tests nach Dungeon 6 verschoben).
2. Dämon 5 Geflügelter Dämon (Dungeon 5, Bank 4): fliegt, stürzt herab, 3 Phasen, ca. 14 HP. Gibt **Feuerball** (Steuerung: **Hoch + B**, ein Projektil geradeaus, Abklingzeit). Sonnet. **Erledigt** (`src/winged.c` in Bank 4, `tests/winged.lua`, `tests/fireball.lua`, Screenshots `v0.5-winged-phase1.png`, `v0.5-winged-phase3.png`, `v0.5-fireball.png`; Test-Dummy bleibt in Dungeon 6).
3. Tests, Screenshots, Docs, Bericht. Orchestrator.

Entscheidung: Feuerball auf Hoch + B (B bleibt Schwert, Select bleibt Dash). Test-Dummy wandert in Dungeon 6.

Pakete für v0.6 ff. legt der Orchestrator selbst am Start des Meilensteins fest und trägt sie hier ein.

## Parallel-Aufgabe des Nutzers

`gh auth login` (im Terminal mit `! gh auth login`), sobald `gh` installiert ist. Danach legt der Orchestrator das private Repo `EscapingFromHell` an (`gh repo create`) und pusht. Bis dahin lokal bauen und committen.

## Risiken

- Mesen2 headless nicht verifiziert (`TECH.md`). Ausweichlösung: fceux + xvfb.
- 8 Sprites pro Zeile: große Dämonen aus Sprites und Hintergrund bauen.
- ROM-Größe: MMC3-Größen früh festlegen und in `TECH.md` eintragen.
