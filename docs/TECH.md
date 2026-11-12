# TECH – Escaping From Hell

Festgelegt mit dem Nutzer. Entscheidungen, die ein Agent selbst trifft, hier eintragen (Abschnitt „Entscheidungslog").

## Ziel-Hardware

- Echtes NES-Modul, **NTSC (60 Hz)**.
- **MMC3 (Mapper 4)** mit Batterie-RAM. Startwert: 128 KB PRG-ROM, 128 KB CHR-ROM, 8 KB PRG-RAM. Größen anpassen, wenn nötig (hier eintragen).
- Pro Boss und Phase eigene CHR-Bänke (Bank-Wechsel für Phasen und Overworld-Animation).

## Toolchain

- **cc65 2.19**: C für Logik, `ca65`-Assembler für Zeitkritisches (NMI, Scrolling, Sprite-DMA). Keine Fremd-Bibliothek (kein neslib): eigene Mini-Runtime in `src/crt0.s`, C-Laufzeit aus `none.lib`.
- Build: `make` baut `build/EscapingFromHell.nes`. `make clean`, `make test`.
- Python 3 mit Pillow für Skripte in `tools/`.
- Emulator/Tests: **Mesen2 2.1.1 Linux x64** in `tools/mesen/` (nicht im Git). Download: GitHub-Release `SourMesen/Mesen2`, Datei `Mesen_2.1.1_Linux_x64.zip`.
- Ausweichlösung, falls Mesen headless nicht läuft: `fceux` + `xvfb` (`xvfb-run`).
- Installationen (erlaubt): `apt install cc65 gh xvfb python3-pil`.

## Build-Layout

- `Makefile`: `src/*.c` → `cc65 -t none -O --cpu 6502` → `build/*.s` → `ca65`; `src/*.s` → `ca65`; Link mit `ld65 -C cfg/mmc3.cfg ... none.lib`. Ausgabe `build/EscapingFromHell.nes` (262160 Byte = 16 + 128 KB PRG + 128 KB CHR), dazu `.map` und `.lbl` in `build/`.
- `src/crt0.s`: iNES-Header (Mapper 4, Batterie, 8 PRG-Einheiten à 16 KB, 16 CHR-Einheiten à 8 KB, 1 PRG-RAM-Einheit à 8 KB, NTSC), Reset (PPU-Warmup, MMC3-Init, RAM löschen, C-Stack, `copydata`/`zerobss`, `main`), NMI (OAM-DMA von `$0200`, bei `col_pending` `ppu_flush`, dann `$2000` = `ppu_ctrl` und Scroll X = `scroll_x`, `frame_count` erhöhen), IRQ-Stub (`rti`), Vektoren, `wait_vblank()`.
- `src/debug.s`: Testvariablen (Segment `DEBUG`). `src/chr.s`: CHR-Daten (`.incbin build/tiles.chr` = Pattern-Table 0 / Hintergrund, `build/player.chr` = Pattern-Table 1 / Sprites, je auf 4 KB aufgefüllt). `src/map.s`: Overworld-Karte (`.incbin build/overworld.bin`, Symbol `_overworld_map`). `src/main.c`, `src/nes.h`: C-Seite (Zustandsmaschine, Overworld, PPU-Register-Makros, Prototypen). `src/dungeon.c`: Dungeon-Arena (siehe Abschnitt „Dungeon (v0.3)").
- Makefile-Regeln: `assets/sprites/<n>.png` → `build/<n>.chr` (`png2chr.py --pad 4096`); `assets/overworld.txt` → `build/overworld.bin` (`tools/mapconv.py`).
- CHR-Bänke: `crt0.s` setzt beim Reset R0..R5 linear (R0=0, R1=2, R2..R5=4..7), also CHR-Offset `$0000-$1FFF` = PPU `$0000-$1FFF`. Hintergrund `$0000`, Sprites `$1000` (PPUCTRL `$88`).

### Linker-Konfiguration `cfg/mmc3.cfg`

- CPU-Speicher: `$0000-$00FF` Zeropage (cc65 + eigene), `$0100` Stack, `$0200-$02FF` OAM-Puffer, `$0300-$031F` `DEBUG` (Spielzustand, nur `$0300-$0317` belegt), `$0320-$05FF` BSS/DATA (736 Byte), `$0600-$07FF` C-Parameterstack (512 Byte, wächst abwärts von `$0800`), `$6000-$7FFF` Segment `SAVE` (Batterie-RAM, noch leer).
- PRG-ROM: MMC3 im PRG-Modus 0. Fest: `$C000-$FFFF` = Bänke 14 und 15 (hier liegen `STARTUP`, `CODE`, `RODATA`, `DATA`-Ladebild, `VECTORS`). Umschaltbar: `$8000-$BFFF`, beim Reset Bänke 0 und 1 (R6/R7). Bänke 0-13 sind im Config als ein Füllbereich `BANKS` (112 KB) reserviert und leer. Sobald Code gebankt wird, wird `BANKS` in Einzelbereiche aufgeteilt.
- Aktuell passt alles in die festen 16 KB. Reicht das nicht mehr, wird Code in Bänke ausgelagert (Entscheidungslog).
- CHR: ein Bereich `CHR` mit 128 KB, Segment `CHARS`. Kachel 0 leer, Kachel 1 voll (Farbe 1).
- Reset-Init des MMC3: PRG-Modus 0, Bänke 0/1, vertikale Spiegelung (`$A000` = 0, `1` = horizontal), PRG-RAM an (`$A001` = `$80`), IRQ aus (`$E000`).

### Debug-Adressen (fest, für Tests)

| Adresse | Name (C) | Bedeutung |
|---|---|---|
| `$0300/$0301` | `frame_count` | 16 Bit little-endian, +1 pro NMI |
| `$0302` | `game_state` | 0 = Boot, 2 = Overworld, 3 = Dungeon-Arena (1 = altes Hello-ROM, unbenutzt) |
| `$0303/$0304` | `player_x` | 16 Bit, Welt-X (Pixel) der linken oberen Ecke des 16x16-Sprites. Im Dungeon: Arena-X, 16..224 |
| `$0305` | `player_y` | Welt-Y (Pixel), 0..239. Im Dungeon: Arena-Y der Sprite-Oberkante (Stehen auf dem Boden = 176) |
| `$0306/$0307` | `cam_x` | 16 Bit, Kamera-X (Welt-Pixel am linken Bildrand), 0..768 |
| `$0308/$0309` | `dungeons_cleared` | 16 Bit, Bit n-1 = Dungeon n geschafft (Bits 0..9) |
| `$030A` | `cur_dungeon` | 1..10 im Dungeon, sonst 0 |
| `$030B` | `hearts` | Dungeon: Herzen (3 beim Betreten/Neustart) |
| `$030C` | `invuln` | Dungeon: verbleibende Unverwundbarkeits-Frames des Spielers (90 nach Treffer) |
| `$030D` | `on_ground` | Dungeon: 1 = steht auf Boden/Plattform |
| `$030E` | `sword_t` | Dungeon: verbleibende Frames des Schwertschlags (0 = kein Schwert) |
| `$030F` | `vy` | Dungeon: vertikale Geschwindigkeit (signed, px/Frame, negativ = aufwärts) |
| `$0310-$0316` | `en` | Dungeon: Gegner-Struct `struct enemy` aus `nes.h`: `x`, `y`, `w`, `h`, `hp`, `flash` (Frames Trefferschutz, blinkt), `dir` (signed, +1/-1) |
| `$0317` | `paused` | Dungeon: 1 = pausiert |

Alle sind die echten Spielvariablen: Tests dürfen sie mit `emu.write` setzen (Teleport, Maske, Herzen, Gegner-HP/-Position). Eine Positionsänderung um mehr als eine Kachelspalte löst einen vollständigen Neuaufbau des Bildes aus (ca. 10 Frames ohne NMI), danach ca. 30 Frames warten.

Quelle: `src/debug.s` (Segment `DEBUG`, `cfg/mmc3.cfg` Bereich `DBG`). Änderungen hier, in `tests/*.lua` und `src/nes.h` gleichzeitig nachziehen.

## Grafik-Pipeline

- Quelle: PNG in `assets/sprites/` (indiziert, NES-Palette, max. 4 Farben pro Palette).
- `tools/png2chr.py` wandelt PNG → CHR-Daten beim Build. Aufruf: `python3 tools/png2chr.py in.png out.chr [--pad N]` (Breite/Höhe Vielfaches von 8; `--pad 4096` füllt auf 4 KB Pattern-Table mit Nullen, Fehler wenn größer).
- Ausgabe: 2bpp-CHR, Kacheln zeilenweise (links→rechts, oben→unten), je 16 Byte: 8 Byte Plane 0 (niedriges Bit), 8 Byte Plane 1 (hohes Bit), MSB = linkes Pixel.
- Farbzuordnung: Palette-PNG → Pixelindex 0..3 direkt. RGB/RGBA-PNG → transparent oder #000000 = 0, übrige Farben nach Helligkeit aufsteigend = 1, 2, 3. Mehr als 4 Farben im Bild = Fehler.
- `assets/sprites/tiles.png` (256×8, 32 Kacheln, Reihenfolge): 0 leer, 1 Boden/Weg, 2 Gras/Fels, 3 Lava (wellig), 4 Wand/Ziegel, 5 Tempeldach, 6 Tempeltür, 7 verschlossenes Tor (X), 8 offenes Tor, 9 Vollblock (Index 3), 10 Arena-Ziegel (Wand/Boden-Füllung), 11 Arena-Boden-Oberkante, 12 Arena-Plattform (dünn, Oberkante Index 3, Rest transparent), 13–15 leer, 16–25 Ziffern 0–9, 26 D, 27 U, 28 N, 29 G, 30 E, 31 O (Schrift 5x7, Farbe 3). Ergibt 512 Byte.
- `assets/sprites/player.png` (16×64 = 16 Kacheln, 256 Byte, Sprite-Pattern-Table; je 16×16-Block = 4 Kacheln zeilenweise): Kacheln 0–3 Overworld-Spieler (Draufsicht), 4–7 Dungeon-Spieler (Seitenansicht, nach rechts blickend), 8–11 Test-Gegner (symmetrisch), 12/13 Schwert (Griff/Spitze, 8x8), 14 volles Herz, 15 leeres Herz.
- Erst Platzhalter (einfache Formen in richtigen Größen/Farben), später Art-Pass. Nutzer kann jede PNG ersetzen.
- NES-Grenzen beachten: 64 Sprites, max. 8 pro Zeile. Große Dämonen = Sprites + Hintergrund-Kacheln.

## Overworld (v0.2)

- **Karte:** `assets/overworld.txt` (Text, 64 Spalten x 15 Zeilen Metakacheln à 16x16 px = 1024x240 px, Legende im Dateikopf). `tools/mapconv.py` macht daraus `build/overworld.bin`: spaltenweise, 16 Byte pro Spalte (Zeile 15 = Füllbyte 0), 1024 Byte. Zell-ID: 0..15 = Kachelindex (2 Fels, 3 Lava, 4 Wand, 5 Dach sind fest), 16..25 = Tor von Dungeon 1..10, 32..41 = Tür von Dungeon 1..10. Metakachel = eine 8x8-Kachel 2x2 wiederholt (Platzhalter), Palette je Metakachel.
- **Tempelraster:** Tür von Dungeon n in Spalte 6n-3, Zeile 5 (n ungerade) bzw. 3 (n gerade); Dach darüber, Tor direkt darunter, dann ein Pfadstück zum Hauptweg. Start des Spielers: x=32, y=144. Der Code (Rückkehr aus dem Dungeon) und `mapconv.py` (Assert) nutzen dieselbe Formel.
- **Tore:** offen, wenn n == 1 oder Bit n-2 in `dungeons_cleared` gesetzt ist. Zeichnen und Kollision fragen dieselbe Funktion (`is_open`). Das Tor ist als Zell-ID in der Karte, die Kachel (7 verschlossen / 8 offen) wird beim Spaltenaufbau gewählt. Ändert sich die Maske, zeichnet das Spiel alle sichtbaren Spalten neu (Bild kurz aus), ebenso beim Betreten der Overworld.
- **Scrolling:** vertikale Spiegelung (zwei Nametables nebeneinander = 512 px Ring), `PPUCTRL`-Bit 0 + `PPUSCROLL` X aus `cam_x` (Kamera zentriert auf den Spieler, 0..768). Wechselt `cam_x >> 4`, baut die Hauptschleife die nächste Metakachel-Spalte (rechts: `spalte+16`, links: `spalte`) in `colbuf` (2 Kachelspalten à 30) und `attrbuf` (8 Attribut-Bytes) und setzt `col_pending`. Der NMI kopiert nach dem OAM-DMA beides (Inkrement 32, ca. 1300 Zyklen, passt in VBlank). Attribut-Byte deckt zwei Metakachel-Spalten, wird deshalb immer aus beiden Spalten berechnet. Weiter als eine Spalte Sprung (Teleport) oder Maskenänderung: kompletter Neuaufbau bei ausgeschaltetem Bild (`redraw_overworld`).
- **Spieler:** 16x16 Metasprite (4 Sprites, Kacheln 0..3, Palette 0), 2 px/Frame, 8 Richtungen. Kollisionsbox: 8x6 px an den Füßen (x+4..x+11, y+10..y+15) gegen die Zellen. Eintritt: Fußmitte (x+8, y+12) auf Tür-Zelle eines offenen Dungeons + **A**.
- **Dungeon:** `game_state` 3, Details im nächsten Abschnitt. Rückkehr (vorläufig **Select**) setzt den Spieler auf die Tür-Zelle.
- Eingabe: Controller 1, `read_pad()` in `main.c`.
- Paletten: Hintergrund `$0F` schwarz, Pfad braun/orange, Fels/Wand rot, Lava orange, Dach/Tore rot/orange/gelb; Sprite-Palette 0 braun/blau/Haut.

## Dungeon (v0.3)

- **Code:** `src/dungeon.c`. `main.c` ruft `dungeon_enter()` (setzt `cur_dungeon` voraus: Bildschirm aus, Palette, Arena zeichnen, Sprites, `arena_reset()`, Bild an; dauert einige Frames) und danach jeden Frame `dungeon_frame()` (Rückgabe 1 = verlassen). `main.c` stellt `screen_off`/`screen_on`, `pad`/`pad_prev` und `PRESSED(b)` (Flanke) bereit. `leave_dungeon()` in `main.c` setzt die Overworld-Sprites zurück (Kacheln 0..3, Attribut 0, alle übrigen Sprites versteckt).
- **Arena:** Nametable 0, kein Scrolling. Wände = Spalten 0-1 und 30-31 (x < 16, x >= 240), Boden-Oberkante y = 192 (Kachelzeile 24, darunter Ziegel), 3 einseitige Plattformen à 48 px (Oberkante y = 152 bei x = 32 und x = 176, y = 112 bei x = 104; Tabelle `plat_x`/`plat_y` dient Zeichnen und Kollision). Attribute alles Palette 0.
- **Palette:** `dpal[10][4]` (Tabelle in `dungeon.c`, Index = Dungeon-Nr. − 1; Hintergrund, Boden, Mörtel, Kante) füllt alle 4 BG-Paletten. Sprite-Paletten gemeinsam (`spal`): 0 Spieler, 1 Gegner, 2 Herz + Schwert. Farben sind Platzhalter.
- **Spieler:** Box für Treffer x+3, y+2, 10x14. Laufen 2 px/Frame, Blickrichtung per `horizontal flip` (Attribut Bit 6, linke/rechte Kachel getauscht). Sprung: **A** auf dem Boden, `vy` = −6, Schwerkraft +1 alle 3 Frames (max. 7), Spitzenhöhe ca. 63 px, loslassen schneidet auf `vy` −2 ab (variable Höhe). Landung nur beim Fallen, wenn die Füße die Oberkante von Boden/Plattform von oben schneiden (Plattformen von unten durchspringbar, kein Durchfallen durch dünne Plattformen bei 7 px/Frame). Ein Schritt über den Plattformrand lässt den Spieler fallen. Bildschirmrand: x 16..224.
- **Schwert:** **B**, Schlag 8 Frames sichtbar (2 Sprites, Kacheln 12/13, Palette 2), Abklingzeit 20 Frames ab Schlagbeginn. Trefferbox 16x8 an x+12 (rechts) bzw. x−12 (links), y+6.
- **Herzen:** 3 Sprites oben links (x 24/34/44, y 16), volle/leere Kachel je nach `hearts`. Treffer durch Gegnerkontakt: −1 Herz, 90 Frames unverwundbar (Spieler blinkt, Sprites alle 4 Frames aus), Rückstoß 8 Frames à 3 px weg vom Gegner plus kleiner Hüpfer (`vy` −3). 0 Herzen: `arena_reset()` sofort (3 Herzen, Spieler- und Gegnerwerte neu, Bild bleibt).
- **Gegner (Test-Dummy):** Generisches `struct enemy` (`nes.h`, Debug `$0310`): Position/Größe/`hp`/`flash`/`dir`. Dummy: 16x16, 5 HP, läuft mit 1 px/Frame zwischen den Wänden hin und her, 1 Schaden pro Schwertschlag, danach 12 Frames Trefferschutz (blinkt, ein Schlag = ein Treffer), bei `hp` 0 unsichtbar, ohne Kollision und ohne Bewegung. Paket 2 ersetzt die Logik durch die Boss-Tabelle und behält `struct enemy` bzw. erweitert sie.
- **Sprites (OAM-Offsets):** Spieler 0..15, Schwert 16..23, Gegner 24..39, Herzen 40..51 (13 von 64). Höchstens ca. 6 Sprites pro Zeile (Spieler 2 + Schwert 2 + Gegner 2), Herzen liegen in einer eigenen Zeile.
- **Pause:** **Start** schaltet `paused` um (Spiel friert ein, keine Anzeige). **Select** = zurück in die Overworld, **vorläufig**: Paket 3 ersetzt das durch den Sieg-Moment, Select bleibt dann höchstens als Debug-Ausgang.

## Spielstruktur

- Frame-Loop mit NMI. Zustände: Titel, Intro, Overworld, Dungeon, Sieg, Ende.
- Overworld: horizontales Scrolling, 3 bis 4 Bildschirme. Dungeon: ein Bildschirm, kein Scrolling.
- Boss-Logik als Datentabelle pro Dämon (HP, Phasen-Grenzen in %, Bewegungsmuster) plus kleine Verhaltensfunktionen.

## Speicherstand (PRG-RAM $6000)

Ein Slot. Felder: Magic-Byte, Version, Bitmaske geschaffter Dungeons (10 Bit), Bitmaske Fähigkeiten, Prüfsumme. Ungültig = „New Game". Autosave nach jedem Sieg.

## Tests

- `make test` baut die ROM und startet jedes `tests/*.lua` mit Mesen2 headless; jedes Skript muss mit Exit-Code 0 enden, sonst schlägt `make test` fehl (je Test `timeout 60`). Befehl pro Skript:
  `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 xvfb-run -a tools/mesen/Mesen --testRunner tests/smoke.lua build/EscapingFromHell.nes`
- **Verifiziert (2026-11-12):**
  - Beendet wird mit **`emu.stop(code)`**; `emu.exit` existiert **nicht** (trotz Hilfetext; ein Skript damit läuft in einen Fehler und hängt bis zum Timeout). `emu.stop(0)` = Erfolg, `emu.stop(n)` = Prozess-Exit-Code `n`.
  - **Mesen ändert sein Arbeitsverzeichnis**; relative Pfade zu Skript/ROM gehen trotzdem (Mesen löst sie vorher auf), in Skripten selbst ist **kein `io`/`os`** verfügbar (nur `emu`, `string`, `print`, ...). `print` geht nach stdout.
  - Beim ersten Start zeigt Mesen einen Konfigurations-Dialog und blockiert. Abhilfe: `tools/mesen/settings.json` anlegen (Inhalt siehe unten, mindestens `{}`) (portabler Modus, alle Mesen-Dateien bleiben in `tools/mesen/`, das ignoriert Git). `make test` und `tools/screenshot.sh` legen sie bei Bedarf an.
  - Ohne `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` stürzt Mesen hier beim Start mit `std::bad_cast` ab.
  - Fehler im Lua-Skript ohne `emu.stop` führen zum Hängen bis `timeout` (Exit 124), also ebenfalls zu einem fehlgeschlagenen Test.
- Muster: `emu.addEventCallback(fn, emu.eventType.endFrame)`, nach N Frames `emu.read(addr, emu.memType.nesMemory)` prüfen, dann `emu.stop(0|1)`. Vorlage: `tests/smoke.lua` (prüft `game_state == 2` und `frame_count >= 100` nach 120 Frames).
- Lua kann den Speicher lesen/schreiben (`emu.read`, `emu.write`, `emu.getState`). Smoke-Tests prüfen Speicherstellen, z. B. „Titel erreicht", „Herz −1 bei Treffer", „Speicherstand geschrieben".
- **Eingabe:** Controller 1 muss in `tools/mesen/settings.json` als `NesController` konfiguriert sein (`{"Nes":{"Port1":{"Type":"NesController"}}}`; mit `{}` bleibt `emu.setInput` wirkungslos). `make test` und `screenshot.sh` legen sie bei Bedarf an. Eingabe: `emu.setInput({right=true, a=true, ...}, 0, 0)` in einem `emu.eventType.inputPolled`-Callback; Tasten `a b select start up down left right`, nicht genannte = losgelassen.
- `tests/overworld.lua`: eine Coroutine fährt alles ab: (a) Boot → Overworld, (b) Rechts halten → `player_x` und `cam_x` wachsen, (c) Tor 2 verschlossen (Kachel 7 im Nametable, Hochlaufen blockt, A auf der Tür tut nichts), (d) Dungeon 1: A → Zustand 3, B bleibt drin, Select → zurück auf Eingang 1, (e) Maske = 1 → Tor 2 wird neu gezeichnet (Kachel 8), Durchlaufen, A → Dungeon 2, Select → zurück. Nametable-Lesen: `emu.read(addr, emu.memType.nesPpuMemory)`. Lauf ca. 1 s. Nach A im Dungeon 20 Frames warten (Arena-Aufbau).
- `tests/dungeon.lua`: Coroutine wie oben. Betritt Dungeon 1 (3 Herzen, steht auf dem Boden, Gegner 5 HP), Sprung (y steigt, Landung auf dem Boden), einseitige Plattform (von unten springen landet oben, Rand → Fallen zum Boden, linke Wand stoppt), Pause (Gegner friert ein), Kontakt kostet genau 1 Herz und setzt `invuln` (kein zweiter Verlust im Schutz), 3 Treffer → Neustart mit 3 Herzen und vollem Gegner, 5 Schwertschläge → Gegner-HP 5→0 (ein Schlag = ein Treffer), Gegner unsichtbar und harmlos, B verlässt nicht, Select → Overworld mit Overworld-Sprites. Tests stellen die Lage per `emu.write` her (`setup()`), der Dummy läuft sonst zu schnell auf den Spieler zu. Lauf ca. 15 s.
- **Screenshot:** `[EXTRA_LUA='<lua>'] tools/screenshot.sh <rom> <out.png> [frames]` (Standard 120 Frames; `EXTRA_LUA` wird vorangestellt, z. B. für gehaltene Tasten oder Teleport per `emu.write`), z. B. `tools/screenshot.sh build/EscapingFromHell.nes docs/screenshots/m1.png`. Da Lua nicht schreiben kann, gibt das Skript das PNG von `emu.takeScreenshot()` als Hex auf stdout aus, Python schreibt die Datei (256x240).

## Git "dubious ownership" (gelöst)

Der Projektordner gehört UID 1000, Agenten laufen als root. Der Nutzer hat `safe.directory` für diesen Ordner global eingetragen. Falls die Meldung trotzdem auftaucht: `! git config --global --add safe.directory /root/SoftwareApplications/EscapingFromHell` vom Nutzer ausführen lassen. Agenten ändern die globale Config nicht selbst.

## Push zu GitHub

Remote `origin` ist `https://github.com/Rluffy/EscapingFromHell.git` (privat). Für root gibt es keinen SSH-Key, daher HTTPS mit `gh` als Credential-Helper, pro Befehl: `git -c credential.helper= -c credential.helper='!gh auth git-credential' push --follow-tags`. Globale Git-Config wird nicht geändert.

## Selbst spielen (FCEUX unter Ubuntu)

Die Qt-Version von FCEUX flackert unter Wayland. Abhilfe: `QT_QPA_PLATFORM=xcb fceux <rom>` oder in *Options → Video Config* den Treiber SDL statt OpenGL wählen. Die ROM selbst ist in FCEUX 2.6.5 und Mesen2 frame-stabil geprüft.

## Entscheidungslog

(Agenten tragen hier technische Entscheidungen ein: Datum, Entscheidung, Grund.)

- 2026-11-12: Eigene Mini-Runtime (`src/crt0.s`) mit `none.lib` statt `nes.lib`/neslib. Grund: volle Kontrolle über MMC3-Layout und Speicherplan, keine Fremdlizenz, wenig Code.
- 2026-11-12: Fester Bereich `$C000-$FFFF` (Bänke 14/15) enthält vorerst allen Code; Bänke 0-13 leer reserviert. Grund: kleinste Lösung für das Hello-ROM, Banking folgt mit dem ersten Bedarf.
- 2026-11-12: Testvariablen im Segment `DEBUG` fest bei `$0300` (siehe Tabelle). Grund: Lua-Tests brauchen feste Adressen, unabhängig vom Linker-Layout.
- 2026-11-12: RAM-Plan: C-Stack nur 512 Byte (`$0600-$07FF`), BSS/DATA 752 Byte; Spielzustand mit mehr Platzbedarf später ins PRG-RAM `$6000` oder Config anpassen.
- 2026-11-12: Tests beenden mit `emu.stop(code)`; Mesen läuft portabel (`tools/mesen/settings.json` = `{}`) und mit `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1`. Grund: siehe Abschnitt Tests.
- 2026-11-12: Screenshot über Hex-Ausgabe von `emu.takeScreenshot()` + Python, weil Mesen-Lua kein `io` hat.
- 2026-11-12: Overworld als Textkarte (`assets/overworld.txt`) + `mapconv.py` statt C-Array: leicht editierbar, 1 KB ROM. Metakachel = eine Kachel 2x2, Spalte 16 Byte (Adresse per Shift).
- 2026-11-12: Tempel-/Tor-Zell-IDs in der Karte (16+n Tor, 32+n Tür), Kachel und Kollision daraus abgeleitet: ein Ort für die Torlogik (`is_open`), Maske ändert nur das Zeichnen, nicht die Karte.
- 2026-11-12: Spaltenstreaming Hauptschleife -> RAM-Puffer -> NMI-Kopie (`ppu_flush` in `crt0.s`), keine PPU-Zugriffe der Hauptschleife im laufenden Bild; Vollneuaufbau bei ausgeschaltetem Bild und NMI aus (`screen_off`/`screen_on`).
- 2026-11-12: Spieler 2 px/Frame, Kollisionsbox 8x6 an den Füßen. B oder Start verlässt den Dungeon-Platzhalter. `cur_dungeon` = 0 in der Overworld.
- 2026-11-12: MMC3-CHR-Register R0..R5 werden im Reset gesetzt (waren vorher undefiniert). Controller 1 in Mesen per `settings.json` aktiviert, sonst wirkt `emu.setInput` nicht.
- 2026-11-12: Alles bleibt im festen 16-KB-Bereich (Code+Daten belegen weniger als 4 KB); kein Banking nötig.
- 2026-11-12: Dungeon-Code in `src/dungeon.c`, `main.c` bleibt Zustandsmaschine; `screen_off`/`screen_on`/`pad` dafür nicht mehr `static`. Debug-Segment auf 32 Byte (`$0300-$031F`) erweitert, BSS startet bei `$0320`: Gegner-Struct und Dungeon-Zustand sind für Tests sichtbar.
- 2026-11-12: Sprite-Sheet `player.png` ist 16 px breit und wächst nach unten (je 16x16-Block = 4 aufeinanderfolgende Kacheln), damit die Overworld-Kacheln 0..3 unverändert bleiben. Gegner-Platzhalter ist symmetrisch (kein Flip nötig).
- 2026-11-12: Herzen als Sprites (volles/leeres Herz per Kachelwechsel) statt Hintergrundkacheln: kein VRAM-Schreiben im laufenden Bild nötig.
- 2026-11-12: Physik in ganzen Pixeln: Schwerkraft +1 `vy` alle 3 Frames statt Subpixel; Landung nur durch Kreuzen der Oberkante von oben (einseitig, kein Durchtunneln). Arena-Aufbau bei ausgeschaltetem Bild (einige Frames), `arena_reset()` beim Neustart ohne Neuaufbau.
- 2026-11-12: Select verlässt den Dungeon (vorläufig, bis zum Sieg-Moment in Paket 3); Start = Pause wie im Konzept. Tests von `overworld.lua` entsprechend angepasst.
- 2026-11-12: Stand ROM nach Paket 1: CODE+RODATA+STARTUP ca. 6,1 KB von 16 KB im festen Bereich.
