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
| v0.5 | Boss 4 (Lavaschlange), Boss 5 (Geflügelter Dämon), Feuerball | erledigt |
| v0.6 | Boss 6 (Spiegeldämon), Boss 7 (Riesenkröte), Schild | erledigt |
| v0.7 | Boss 8 (Spinnenkönigin), Boss 9 (Oni-Kriegsherr), Schwertwelle | erledigt |
| v0.8 | Boss 10 (Höllenfürst), komplette Spielreihenfolge, Ende-Logik | erledigt |
| v0.9 | Art-Pass (Pixelkunst im Stil von DesignIdea1/2), Soundeffekte, Titelbildschirm, Intro, Ende, Overworld-Dekor mit Idle-Animationen | erledigt |
| v1.0 | Balance, Fehlerbehebung, Release mit ROM | erledigt |

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
3. Tests, Screenshots, Docs, Bericht. Orchestrator. **Erledigt.**

Entscheidung: Feuerball auf Hoch + B (B bleibt Schwert, Select bleibt Dash). Test-Dummy wandert in Dungeon 6.

## Arbeitspakete v0.6

1. Dämon 6 Spiegeldämon (Dungeon 6, Bank 5): teleportiert, erzeugt Scheinkopien (nur das Original ist verwundbar, erkennbar an einem Detail), 3 Phasen, ca. 14 HP. Test-Dummy wandert nach Dungeon 8. Sonnet. **Erledigt** (`src/mirror.c` in Bank 5, `tests/mirror.lua`, Screenshots `v0.6-mirror-phase1.png`, `v0.6-mirror-phase3.png`; Test-Dummy-Tests jetzt in Dungeon 8; Linker-Bereiche `BANK6..BANK9` angelegt).
2. Dämon 7 Riesenkröte (Dungeon 7, Bank 6): sehr groß (Sprites + ggf. Hintergrund-Kacheln), schwere Sprünge, Zunge, Schleim, 3 Phasen, ca. 16 HP. Gibt **Schild** (Steuerung: **Runter halten** am Boden: blockt Projektile und Kontakt von vorn, Spieler steht still). Sonnet. **Erledigt** (`src/toad.c` in Bank 6, Schild in `src/dungeon.c`, `tests/toad.lua`, `tests/shield.lua`, Screenshots `v0.6-toad-phase1.png`, `v0.6-toad-phase3.png`, `v0.6-shield.png`; Debug-Block auf `$0300-$033F` erweitert).
3. Tests, Screenshots, Docs, Bericht. Orchestrator. **Erledigt.**

## Arbeitspakete v0.7

1. Dämon 8 Spinnenkönigin (Dungeon 8, Bank 7): klettert an der Decke, seilt sich ab, Netze (verlangsamen den Spieler), 3 Phasen, ca. 16 HP. Test-Dummy wandert nach Dungeon 10. Sonnet. **Erledigt** (Körper 24x16, Faden aus Sprites, Netze verlangsamen 90 Frames ohne Herzverlust, Phase 3 mit Spinnlingen; fester Bereich 10453 Byte, Bank 7 1515 Byte).
2. Dämon 9 Oni-Kriegsherr (Dungeon 9, Bank 8): rennt, schlägt mit Keule, Schockwellen am Boden (überspringbar), 3 Phasen, ca. 18 HP. Gibt **Schwertwelle** (Steuerung: Schwert bei vollen 3 Herzen schießt zusätzlich eine Welle). Sonnet. **Erledigt** (`src/oni.c` in Bank 8, Körper 24x32 mit eigenen Sprites, Schwertwelle in `src/dungeon.c`, `tests/oni.lua`, `tests/wave.lua`, Screenshots `v0.7-oni-phase1.png`, `v0.7-oni-phase3.png`, `v0.7-swordwave.png`; Stehbot 3 / 3 / 3 Herzen; fester Bereich 10629 Byte, Bank 8 2277 Byte).
3. Tests, Screenshots, Docs, Bericht. Orchestrator.

Hinweis: fester Bereich nach v0.7 Paket 2 ca. 10,4 KB (10629 Byte) von 16 KB (nach Paket 1: 10453 Byte, nach v0.6: 10286 Byte). Boss-spezifischer Code gehört in die Boss-Bank, gemeinsamer Code nur, wenn mehrere Bosse ihn brauchen.

## Arbeitspakete v0.8

1. Dämon 10 Höllenfürst (Dungeon 10, Bank 9): riesig, Teleport, Flug, Feuer, Unsichtbarkeit; kombiniert Muster früherer Bosse, 3 Phasen, ca. 20 HP. Test-Dummy entfällt (alle Dungeons haben Bosse), Dummy-Tests wandern auf Bosse. Sonnet. **Erledigt** (`src/lord.c` in Bank 9, 20 HP, 32x32 aus 12 Sprites mit gespiegelten Hälften, `tests/lord.lua`, Dummy-Code entfernt, Dummy-Tests jetzt auf dem Imp; Stehbot 3 / 3 / 4 Herzen; fester Bereich 10497 Byte, Bank 9 2334 Byte; Screenshots `v0.8-lord-phase1.png`, `v0.8-lord-phase3.png`).
2. Startmenü (Nutzerwunsch 2026-11-13): Auswahl **NORMAL** / **CHEAT**. Cheat: alle Dungeons offen, keine Herzen verlieren, kein Speichern (Normal-Spielstand bleibt unberührt). Menü so bauen, dass v0.9 Continue/Delete ergänzen kann. Sonnet. **Erledigt** (`src/menu.c`, `game_state` 1 = Menü, Eintragstabelle `item[]`; Cheat: `dungeons_cleared` = 1023 im RAM, `hit()` zieht keine Herzen ab, `save_game()` kehrt sofort zurück; keine neuen Buchstaben nötig; `tests/menu.lua`, alle anderen Tests drücken beim Boot Start; Screenshot `v0.8-menu.png`).
3. Ende-Logik: nach Sieg über Dämon 10 Endbild „YOU ESCAPED" (Platzhalter, v0.9 macht es schön), dann frei weiterspielbar in der Overworld; End-Flag im Speicherstand. Test über die komplette Reihenfolge 1–10 (Tore, Fähigkeiten, Autosave). Sonnet. **Erledigt** (`game_state` 4 = Endbild in `src/menu.c`, Hook in `main.c`: `cur_dungeon == 10 && boss_dead`; End-Flag = Bit 7 von `$6004`, Version bleibt 1; `tests/ending.lua`, `tests/lord.lua` angepasst; Screenshot `v0.8-ending.png`).
4. Tests, Screenshots, Docs, Bericht. Orchestrator. **Erledigt.**

## Arbeitspakete v0.9

Ausgangslage: fester PRG-Bereich ca. 11,4 KB von 16 KB, Sprite-Pattern-Table voll (256 Kacheln).

1. Platz schaffen: Menü/Ende/Text-Code in eine eigene PRG-Bank (UI-Bank, wird für Menü/Intro/Ende eingeblendet). CHR-Banking über MMC3-1-KB-Bänke: Spieler/HUD/Projektile gemeinsam, Boss-Grafik pro Dungeon in eigener CHR-Bank, beim Betreten umgeschaltet. Overworld-Animation per CHR-Bankwechsel vorbereiten. Sonnet. **Erledigt** (UI-Bank 10 mit `menu.c` und Overworld-Karte, fester Bereich 11413 → 9640 Byte; CHR: `common` fest, Boss-Blätter `boss01..10` in R3..R5 ab Kachel-ID `0x40`, Overworld-Animation über R1 (IDs 128..255, `anim_a`/`anim_b`); Details `TECH.md` „CHR-Layout (v0.9)"; `tests/chr.lua`).
2. Art-Pass Hintergrund: Overworld (asiatische Höllen-Tempel, Laternen, Lava, Berge, Pflanzen im Stil von `Concept/DesignIdea1/2`), Idle-Animationen (Lava blubbert, Pflanzen wiegen sich) per CHR-Bankwechsel, Arena-Kacheln und Paletten pro Dungeon. Grafik-Quellen bleiben PNG in `assets/`. Sonnet. **Erledigt** (`tools/art/bgart.py` erzeugt `tiles.png`, `anim_a/b.png`, `src/meta.h`, `src/arena.h`; echte 16x16-Metakacheln aus 4 Kacheln, 10 Tempel mit Tor/Siegel, Lava/Laternen/Gras/Augen animiert (R1, alle 24 Frames), Arena mit Balken/Säulen/Plattform-Enden und Steinton pro Dämon; Screenshots `v0.9-overworld.png`, `v0.9-overworld-mid.png`, `v0.9-overworld-right.png`, `v0.9-arena.png`, `v0.9-arena-lava.png`; Details `TECH.md` „Hintergrund-Kunst (v0.9)").
3. Art-Pass Sprites: Held, Projektile, Herzen, 10 Dämonen × 3 Phasen (jede Phase sichtbar schlimmer). Sonnet (ggf. in zwei Pakete geteilt). **3a erledigt** (Held mit Gehen/Sprung, Projektile, Herzen, Schild, Dämonen 1–5; `tools/art/sprart.py`, Screenshots `v0.9-hero.png`, `v0.9-boss01..05.png`; Details `TECH.md` „Sprite-Kunst (v0.9)“). **3b erledigt** (Dämonen 6–10: Spiegeldämon mit Scheinkopien (stumpfe Augen) und Original (leuchtende Augen), Riesenkröte mit Zunge/Maul/Schleim, Spinnenkönigin mit Faden/Netz/Spinnling, Oni-Kriegsherr mit Keule, Höllenfürst; `tools/art/sprart.py` reproduziert alle PNGs, nur Phasenpaletten in `src/mirror|toad|spider|oni|lord.c` und erwartete Palettenwerte in den Tests geändert; Screenshots `v0.9-boss06..10.png`; Details `TECH.md` „Sprite-Kunst (v0.9)“).
4. Soundeffekte: kleine APU-Engine (Pulse/Noise), Effekte für Sprung, Schwert, Treffer, Boss-Treffer, Phasenwechsel, Boss-Tod, Feuerball, Menü, Sieg. Sonnet. **Erledigt** (`src/sfx.s`, 18 Effekte auf 3 Kanälen mit Priorität, `sfx_play`/`sfx_update` am Ende der Hauptschleife, Debug `$0339-$033C`, `tests/sfx.lua`; fester Bereich +799 Byte; Details `TECH.md` „Soundeffekte (v0.9)“).
5. Titel/Intro/Ende: schöner Titelbildschirm, Menü um CONTINUE und DELETE SAVE erweitern, Intro (2–3 Textbildschirme: Flucht aus der Hölle), schönes Endbild „You escaped". Sonnet. **Erledigt** (Titelbild mit 2x2-Kachel-Logo, Tempeln, Laternen und animierter Lava; Menü CONTINUE (nur mit Stand) / NEW GAME / CHEAT / DELETE SAVE (nur mit Stand, Bestätigung A/B); Intro mit 3 Seiten für NEW GAME und CHEAT; Endbild Morgenröte mit Sonne, Bergen, Held, „YOU ESCAPED / THE END / THANKS FOR PLAYING"; `tools/art/uiart.py`, `src/ui.h`, UI-Kacheln R1 152..240; `tests/menu.lua`, `tests/ending.lua` neu, Boot aller Tests mit zweitem Start; UI-Bank 4447 Byte, fester Bereich 11572 Byte; Screenshots `v0.9-title.png`, `v0.9-intro.png`, `v0.9-ending.png`; Details `TECH.md` „Titel, Intro und Ende (v0.9)").
6. Tests, Screenshots, Docs, Bericht. Orchestrator. **Erledigt.**

## Arbeitspakete v1.0

1. Stabilität: Boss-Zufall pro Dungeon-Eintritt deterministisch seeden (Tests nicht mehr von Frame-Timing abhängig), gelockerte Tests wieder straffen, Compiler-Warnungen beseitigen, Bildschirmaufbau schneller (kürzeres Schwarzbild). Sonnet. **Erledigt** (Boss-`rng` je Dungeon fest geseedet beim Betreten und Neustart, Kampfuhr `ftick` statt `frame_count` in allen Bossen, `tests/determinism.lua` (alle 10 Dungeons identisch bei Eintritt, Wiedereintritt, Neustart), gelockerte Tests wieder eng, `make` ohne Warnungen, Bildaufbau per `src/ppu.s` von 7..13 auf 2..3 schwarze Frames (`tests/redraw.lua`); Details `TECH.md` „Boss-Zufall und Kampfuhr (v1.0)“, „Bildaufbau (v1.0)“; Befund für Paket 2: Lavaschlange überschreitet den VBlank in ca. 25 % der Frames).
2. Fehlersuche: Review des gesamten Codes auf Korrektheitsfehler (Grenzen, Überläufe, vblank, Sprite-Limits, Speicherstand), gefundene Fehler beheben, je mit Test. Sonnet. **Erledigt** (Frame-Überlauf aller Bosse behoben und per `tests/budget.lua` abgesichert (0 verpasste Frames, vollster Frame 78 %), Pause im Intro, `ftick`, PRG-RAM-Schreibschutz, erstes Bild nach Bildwechsel, OAMADDR; `tests/review.lua`; Details `TECH.md` „Fehlersuche v1.0“).
3. Balance: alle Bosse auf das vom Nutzer akzeptierte Niveau (Imp mit 10 HP); Steh-Bot max. 3 Herzen pro Phase bei allen, Endboss inklusive; Werte in GAMEDESIGN. Sonnet. **Erledigt** (Ziele verschärft: Steh-Bot höchstens 2 Herzen je Phase bei Dämon 1–5 und 3 bei 6–10, Ausweich-Bot angestrebt 1–2; HP-Rampe 10 / 11 / 12 / 12 / 13 / 13 / 14 / 14 / 15 / 18; Angriffe seltener, Schlagfenster länger, drei kleine Regeländerungen (Imp, Hund, Flügeldämon Phase 3); `tests/balance.lua` mit beiden Bots auf allen 10 Bossen, Übersichtstabelle in GAMEDESIGN „Balance (v1.0)“, Methode und Entscheidungen in TECH „Balance-Messung (v1.0)“ und im Entscheidungslog 2026-11-13). Vor dem Release vom Nutzer gegenzuprüfen: Imp und Hund fühlen sich jetzt anders an (siehe Log).
4. Release-Vorbereitung: README mit Steuerung und Spielanleitung, ROM `dist/EscapingFromHell-v1.0.nes`, Docs final, Bericht. Tags/Releases v0.5–v1.0 nach Okay des Nutzers. Orchestrator. **Erledigt.**

Pakete nach v1.0 (Musik) legt der Orchestrator selbst am Start des Meilensteins fest und trägt sie hier ein.

## Parallel-Aufgabe des Nutzers

`gh auth login` (im Terminal mit `! gh auth login`), sobald `gh` installiert ist. Danach legt der Orchestrator das private Repo `EscapingFromHell` an (`gh repo create`) und pusht. Bis dahin lokal bauen und committen.

## Risiken

- Mesen2 headless nicht verifiziert (`TECH.md`). Ausweichlösung: fceux + xvfb.
- 8 Sprites pro Zeile: große Dämonen aus Sprites und Hintergrund bauen.
- ROM-Größe: MMC3-Größen früh festlegen und in `TECH.md` eintragen.
