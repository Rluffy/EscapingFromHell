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
- `src/crt0.s`: iNES-Header (Mapper 4, Batterie, 8 PRG-Einheiten à 16 KB, 16 CHR-Einheiten à 8 KB, 1 PRG-RAM-Einheit à 8 KB, NTSC), Reset (PPU-Warmup, MMC3-Init, RAM löschen, C-Stack, `copydata`/`zerobss`, `main`), NMI (OAM-DMA von `$0200`, `frame_count` erhöhen), IRQ-Stub (`rti`), Vektoren, `wait_vblank()`.
- `src/debug.s`: Testvariablen (Segment `DEBUG`). `src/chr.s`: CHR-Daten. `src/main.c`, `src/nes.h`: C-Seite (PPU-Register-Makros, Prototypen).
- Nachträglich CHR aus PNG: `src/chr.s` bekommt `.incbin "../build/<name>.chr"` im Segment `CHARS` (Ausgabe von `tools/png2chr.py`, Paket folgt).

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
| `$0302` | `game_state` | 0 = Boot, 1 = Hello-ROM läuft (später Spielzustand) |
| `$0303-$030F` | `debug_bytes` | frei für weitere Tests |

Quelle: `src/debug.s` (Segment `DEBUG`, `cfg/mmc3.cfg` Bereich `DBG`). Änderungen hier, in `tests/*.lua` und `src/nes.h` gleichzeitig nachziehen.

## Grafik-Pipeline

- Quelle: PNG in `assets/sprites/` (indiziert, NES-Palette, max. 4 Farben pro Palette).
- `tools/png2chr.py` wandelt PNG → CHR-Daten beim Build. Aufruf: `python3 tools/png2chr.py in.png out.chr [--pad N]` (Breite/Höhe Vielfaches von 8; `--pad 4096` füllt auf 4 KB Pattern-Table mit Nullen, Fehler wenn größer).
- Ausgabe: 2bpp-CHR, Kacheln zeilenweise (links→rechts, oben→unten), je 16 Byte: 8 Byte Plane 0 (niedriges Bit), 8 Byte Plane 1 (hohes Bit), MSB = linkes Pixel.
- Farbzuordnung: Palette-PNG → Pixelindex 0..3 direkt. RGB/RGBA-PNG → transparent oder #000000 = 0, übrige Farben nach Helligkeit aufsteigend = 1, 2, 3. Mehr als 4 Farben im Bild = Fehler.
- `assets/sprites/tiles.png` (128×8, 16 Kacheln, Reihenfolge): 0 leer, 1 Boden/Weg, 2 Gras/Fels, 3 Lava (wellig), 4 Wand/Ziegel, 5 Tempeldach, 6 Tempeltür, 7 verschlossenes Tor (X), 8 offenes Tor, 9 Vollblock (Index 3), 10–15 leer. Ergibt 256 Byte.
- `assets/sprites/player.png` (16×16 = 4 Kacheln, 64 Byte): Platzhalter-Humanoid.
- Erst Platzhalter (einfache Formen in richtigen Größen/Farben), später Art-Pass. Nutzer kann jede PNG ersetzen.
- NES-Grenzen beachten: 64 Sprites, max. 8 pro Zeile. Große Dämonen = Sprites + Hintergrund-Kacheln.

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
  - Beim ersten Start zeigt Mesen einen Konfigurations-Dialog und blockiert. Abhilfe: `tools/mesen/settings.json` mit Inhalt `{}` anlegen (portabler Modus, alle Mesen-Dateien bleiben in `tools/mesen/`, das ignoriert Git). `make test` und `tools/screenshot.sh` legen sie bei Bedarf an.
  - Ohne `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` stürzt Mesen hier beim Start mit `std::bad_cast` ab.
  - Fehler im Lua-Skript ohne `emu.stop` führen zum Hängen bis `timeout` (Exit 124), also ebenfalls zu einem fehlgeschlagenen Test.
- Muster: `emu.addEventCallback(fn, emu.eventType.endFrame)`, nach N Frames `emu.read(addr, emu.memType.nesMemory)` prüfen, dann `emu.stop(0|1)`. Vorlage: `tests/smoke.lua` (prüft `game_state == 1` und `frame_count >= 100` nach 120 Frames).
- Lua kann den Speicher lesen/schreiben (`emu.read`, `emu.write`, `emu.getState`). Smoke-Tests prüfen Speicherstellen, z. B. „Titel erreicht", „Herz −1 bei Treffer", „Speicherstand geschrieben".
- **Screenshot:** `tools/screenshot.sh <rom> <out.png> [frames]` (Standard 120 Frames), z. B. `tools/screenshot.sh build/EscapingFromHell.nes docs/screenshots/m1.png`. Da Lua nicht schreiben kann, gibt das Skript das PNG von `emu.takeScreenshot()` als Hex auf stdout aus, Python schreibt die Datei (256x240).

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
