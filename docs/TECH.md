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
- `src/debug.s`: Testvariablen (Segment `DEBUG`). `src/chr.s`: CHR-Daten (`.incbin build/tiles.chr` = Pattern-Table 0 / Hintergrund, `build/player.chr` = Pattern-Table 1 / Sprites, je auf 4 KB aufgefüllt). `src/map.s`: Overworld-Karte (`.incbin build/overworld.bin`, Symbol `_overworld_map`). `src/main.c`, `src/nes.h`: C-Seite (Spiellogik, PPU-Register-Makros, Prototypen).
- Makefile-Regeln: `assets/sprites/<n>.png` → `build/<n>.chr` (`png2chr.py --pad 4096`); `assets/overworld.txt` → `build/overworld.bin` (`tools/mapconv.py`).
- CHR-Bänke: `crt0.s` setzt beim Reset R0..R5 linear (R0=0, R1=2, R2..R5=4..7), also CHR-Offset `$0000-$1FFF` = PPU `$0000-$1FFF`. Hintergrund `$0000`, Sprites `$1000` (PPUCTRL `$88`).

### Linker-Konfiguration `cfg/mmc3.cfg`

- CPU-Speicher: `$0000-$00FF` Zeropage (cc65 + eigene), `$0100` Stack, `$0200-$02FF` OAM-Puffer, `$0300-$030F` `DEBUG`, `$0310-$05FF` BSS/DATA (752 Byte), `$0600-$07FF` C-Parameterstack (512 Byte, wächst abwärts von `$0800`), `$6000-$7FFF` Segment `SAVE` (Batterie-RAM, noch leer).
- PRG-ROM: MMC3 im PRG-Modus 0. Fest: `$C000-$FFFF` = Bänke 14 und 15 (hier liegen `STARTUP`, `CODE`, `RODATA`, `DATA`-Ladebild, `VECTORS`). Umschaltbar: `$8000-$BFFF`, beim Reset Bänke 0 und 1 (R6/R7). Bänke 0-13 sind im Config als ein Füllbereich `BANKS` (112 KB) reserviert und leer. Sobald Code gebankt wird, wird `BANKS` in Einzelbereiche aufgeteilt.
- Aktuell passt alles in die festen 16 KB. Reicht das nicht mehr, wird Code in Bänke ausgelagert (Entscheidungslog).
- CHR: ein Bereich `CHR` mit 128 KB, Segment `CHARS`. Kachel 0 leer, Kachel 1 voll (Farbe 1).
- Reset-Init des MMC3: PRG-Modus 0, Bänke 0/1, vertikale Spiegelung (`$A000` = 0, `1` = horizontal), PRG-RAM an (`$A001` = `$80`), IRQ aus (`$E000`).

### Debug-Adressen (fest, für Tests)

| Adresse | Name (C) | Bedeutung |
|---|---|---|
| `$0300/$0301` | `frame_count` | 16 Bit little-endian, +1 pro NMI |
| `$0302` | `game_state` | 0 = Boot, 2 = Overworld, 3 = Dungeon-Platzhalter (1 = altes Hello-ROM, unbenutzt) |
| `$0303/$0304` | `player_x` | 16 Bit, Welt-X (Pixel) der linken oberen Ecke des 16x16-Sprites |
| `$0305` | `player_y` | Welt-Y (Pixel), 0..239 |
| `$0306/$0307` | `cam_x` | 16 Bit, Kamera-X (Welt-Pixel am linken Bildrand), 0..768 |
| `$0308/$0309` | `dungeons_cleared` | 16 Bit, Bit n-1 = Dungeon n geschafft (Bits 0..9) |
| `$030A` | `cur_dungeon` | 1..10 im Dungeon-Platzhalter, sonst 0 |
| `$030B-$030F` | `debug_bytes` | frei für weitere Tests |

Alle sind die echten Spielvariablen: Tests dürfen sie mit `emu.write` setzen (Teleport, Maske). Eine Positionsänderung um mehr als eine Kachelspalte löst einen vollständigen Neuaufbau des Bildes aus (ca. 10 Frames ohne NMI), danach ca. 30 Frames warten.

Quelle: `src/debug.s` (Segment `DEBUG`, `cfg/mmc3.cfg` Bereich `DBG`). Änderungen hier, in `tests/*.lua` und `src/nes.h` gleichzeitig nachziehen.

## Grafik-Pipeline

- Quelle: PNG in `assets/sprites/` (indiziert, NES-Palette, max. 4 Farben pro Palette).
- `tools/png2chr.py` wandelt PNG → CHR-Daten beim Build. Aufruf: `python3 tools/png2chr.py in.png out.chr [--pad N]` (Breite/Höhe Vielfaches von 8; `--pad 4096` füllt auf 4 KB Pattern-Table mit Nullen, Fehler wenn größer).
- Ausgabe: 2bpp-CHR, Kacheln zeilenweise (links→rechts, oben→unten), je 16 Byte: 8 Byte Plane 0 (niedriges Bit), 8 Byte Plane 1 (hohes Bit), MSB = linkes Pixel.
- Farbzuordnung: Palette-PNG → Pixelindex 0..3 direkt. RGB/RGBA-PNG → transparent oder #000000 = 0, übrige Farben nach Helligkeit aufsteigend = 1, 2, 3. Mehr als 4 Farben im Bild = Fehler.
- `assets/sprites/tiles.png` (256×8, 32 Kacheln, Reihenfolge): 0 leer, 1 Boden/Weg, 2 Gras/Fels, 3 Lava (wellig), 4 Wand/Ziegel, 5 Tempeldach, 6 Tempeltür, 7 verschlossenes Tor (X), 8 offenes Tor, 9 Vollblock (Index 3), 10–15 leer, 16–25 Ziffern 0–9, 26 D, 27 U, 28 N, 29 G, 30 E, 31 O (Schrift 5x7, Farbe 3). Ergibt 512 Byte.
- `assets/sprites/player.png` (16×16 = 4 Kacheln, 64 Byte): Platzhalter-Humanoid.
- Erst Platzhalter (einfache Formen in richtigen Größen/Farben), später Art-Pass. Nutzer kann jede PNG ersetzen.
- NES-Grenzen beachten: 64 Sprites, max. 8 pro Zeile. Große Dämonen = Sprites + Hintergrund-Kacheln.

## Overworld (v0.2)

- **Karte:** `assets/overworld.txt` (Text, 64 Spalten x 15 Zeilen Metakacheln à 16x16 px = 1024x240 px, Legende im Dateikopf). `tools/mapconv.py` macht daraus `build/overworld.bin`: spaltenweise, 16 Byte pro Spalte (Zeile 15 = Füllbyte 0), 1024 Byte. Zell-ID: 0..15 = Kachelindex (2 Fels, 3 Lava, 4 Wand, 5 Dach sind fest), 16..25 = Tor von Dungeon 1..10, 32..41 = Tür von Dungeon 1..10. Metakachel = eine 8x8-Kachel 2x2 wiederholt (Platzhalter), Palette je Metakachel.
- **Tempelraster:** Tür von Dungeon n in Spalte 6n-3, Zeile 5 (n ungerade) bzw. 3 (n gerade); Dach darüber, Tor direkt darunter, dann ein Pfadstück zum Hauptweg. Start des Spielers: x=32, y=144. Der Code (Rückkehr aus dem Dungeon) und `mapconv.py` (Assert) nutzen dieselbe Formel.
- **Tore:** offen, wenn n == 1 oder Bit n-2 in `dungeons_cleared` gesetzt ist. Zeichnen und Kollision fragen dieselbe Funktion (`is_open`). Das Tor ist als Zell-ID in der Karte, die Kachel (7 verschlossen / 8 offen) wird beim Spaltenaufbau gewählt. Ändert sich die Maske, zeichnet das Spiel alle sichtbaren Spalten neu (Bild kurz aus), ebenso beim Betreten der Overworld.
- **Scrolling:** vertikale Spiegelung (zwei Nametables nebeneinander = 512 px Ring), `PPUCTRL`-Bit 0 + `PPUSCROLL` X aus `cam_x` (Kamera zentriert auf den Spieler, 0..768). Wechselt `cam_x >> 4`, baut die Hauptschleife die nächste Metakachel-Spalte (rechts: `spalte+16`, links: `spalte`) in `colbuf` (2 Kachelspalten à 30) und `attrbuf` (8 Attribut-Bytes) und setzt `col_pending`. Der NMI kopiert nach dem OAM-DMA beides (Inkrement 32, ca. 1300 Zyklen, passt in VBlank). Attribut-Byte deckt zwei Metakachel-Spalten, wird deshalb immer aus beiden Spalten berechnet. Weiter als eine Spalte Sprung (Teleport) oder Maskenänderung: kompletter Neuaufbau bei ausgeschaltetem Bild (`redraw_overworld`).
- **Spieler:** 16x16 Metasprite (4 Sprites, Kacheln 0..3, Palette 0), 2 px/Frame, 8 Richtungen. Kollisionsbox: 8x6 px an den Füßen (x+4..x+11, y+10..y+15) gegen die Zellen. Eintritt: Fußmitte (x+8, y+12) auf Tür-Zelle eines offenen Dungeons + **A**.
- **Dungeon-Platzhalter:** `game_state` 3, Hintergrund blau (`$02`), Text „DUNGEON n", Spieler-Sprites versteckt, kein Scrolling. **B** oder **Start** = zurück, Spieler steht auf der Tür-Zelle.
- Eingabe: Controller 1, `read_pad()` in `main.c`.
- Paletten: Hintergrund `$0F` schwarz, Pfad braun/orange, Fels/Wand rot, Lava orange, Dach/Tore rot/orange/gelb; Sprite-Palette 0 braun/blau/Haut.

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
- `tests/overworld.lua`: eine Coroutine fährt alles ab: (a) Boot → Overworld, (b) Rechts halten → `player_x` und `cam_x` wachsen, (c) Tor 2 verschlossen (Kachel 7 im Nametable, Hochlaufen blockt, A auf der Tür tut nichts), (d) Dungeon 1: A → Zustand 3, B → zurück auf Eingang 1, (e) Maske = 1 → Tor 2 wird neu gezeichnet (Kachel 8), Durchlaufen, A → Dungeon 2, Start → zurück. Nametable-Lesen: `emu.read(addr, emu.memType.nesPpuMemory)`. Lauf ca. 1 s.
- **Screenshot:** `[EXTRA_LUA='<lua>'] tools/screenshot.sh <rom> <out.png> [frames]` (Standard 120 Frames; `EXTRA_LUA` wird vorangestellt, z. B. für gehaltene Tasten oder Teleport per `emu.write`), z. B. `tools/screenshot.sh build/EscapingFromHell.nes docs/screenshots/m1.png`. Da Lua nicht schreiben kann, gibt das Skript das PNG von `emu.takeScreenshot()` als Hex auf stdout aus, Python schreibt die Datei (256x240).

## Git "dubious ownership" (gelöst)

Der Projektordner gehört UID 1000, Agenten laufen als root. Der Nutzer hat `safe.directory` für diesen Ordner global eingetragen. Falls die Meldung trotzdem auftaucht: `! git config --global --add safe.directory /root/SoftwareApplications/EscapingFromHell` vom Nutzer ausführen lassen. Agenten ändern die globale Config nicht selbst.

## Push zu GitHub

Remote `origin` ist `https://github.com/Rluffy/EscapingFromHell.git` (privat). Für root gibt es keinen SSH-Key, daher HTTPS mit `gh` als Credential-Helper, pro Befehl: `git -c credential.helper= -c credential.helper='!gh auth git-credential' push --follow-tags`. Globale Git-Config wird nicht geändert.

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
