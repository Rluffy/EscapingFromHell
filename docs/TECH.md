# TECH – Escaping From Hell

Festgelegt mit dem Nutzer. Entscheidungen, die ein Agent selbst trifft, hier eintragen (Abschnitt „Entscheidungslog").

## Ziel-Hardware

- Echtes NES-Modul, **NTSC (60 Hz)**.
- **MMC3 (Mapper 4)** mit Batterie-RAM. Startwert: 128 KB PRG-ROM, 128 KB CHR-ROM, 8 KB PRG-RAM. Größen anpassen, wenn nötig (hier eintragen).
- Pro Boss und Phase eigene CHR-Bänke (Bank-Wechsel für Phasen und Overworld-Animation).

## Toolchain

- **cc65**: C für Logik, `ca65`-Assembler für Zeitkritisches (NMI, Scrolling, Sprite-DMA). Basis-Bibliothek: neslib/famitone2 prüfen (Lizenz!), falls passend nach `src/lib/` übernehmen.
- Build: `make` baut `build/EscapingFromHell.nes`. `make clean`, `make test`.
- Python 3 mit Pillow für Skripte in `tools/`.
- Emulator/Tests: **Mesen2 2.1.1 Linux x64** in `tools/mesen/` (nicht im Git). Download: GitHub-Release `SourMesen/Mesen2`, Datei `Mesen_2.1.1_Linux_x64.zip`.
- Ausweichlösung, falls Mesen headless nicht läuft: `fceux` + `xvfb` (`xvfb-run`).
- Installationen (erlaubt): `apt install cc65 gh xvfb python3-pil`.

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

- `make test` startet `tests/*.lua` mit Mesen2 headless: `tools/mesen/Mesen --testRunner <lua> <rom>`.
- **Nicht verifiziert** (nur im Quellcode gesehen): die Hilfe nennt `emu.exit`, registriert ist aber `emu.stop`. Beim ersten Test prüfen und hier eintragen. Laufzeit-Limit per `timeout=<sek>`, Default 100 s.
- Lua kann den Speicher lesen/schreiben (`emu.read`, `emu.write`, `emu.getState`). Smoke-Tests prüfen Speicherstellen, z. B. „Titel erreicht", „Herz −1 bei Treffer", „Speicherstand geschrieben".
- Screenshots pro Meilenstein nach `docs/screenshots/`.

## Git "dubious ownership" (gelöst)

Der Projektordner gehört UID 1000, Agenten laufen als root. Der Nutzer hat `safe.directory` für diesen Ordner global eingetragen. Falls die Meldung trotzdem auftaucht: `! git config --global --add safe.directory /root/SoftwareApplications/EscapingFromHell` vom Nutzer ausführen lassen. Agenten ändern die globale Config nicht selbst.

## Push zu GitHub

Remote `origin` ist `https://github.com/Rluffy/EscapingFromHell.git` (privat). Für root gibt es keinen SSH-Key, daher HTTPS mit `gh` als Credential-Helper, pro Befehl: `git -c credential.helper= -c credential.helper='!gh auth git-credential' push --follow-tags`. Globale Git-Config wird nicht geändert.

## Entscheidungslog

(Agenten tragen hier technische Entscheidungen ein: Datum, Entscheidung, Grund.)
