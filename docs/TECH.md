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
- `tools/png2chr.py` wandelt PNG → CHR-Daten beim Build.
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

## Bekannte Stolperfalle: Git "dubious ownership"

Der Projektordner gehört UID 1000, Agenten laufen als root. Git meldet dann `dubious ownership`. Dauerhafte Lösung (vom Nutzer einmal auszuführen, ändert die globale Git-Config): `! git config --global --add safe.directory /root/SoftwareApplications/EscapingFromHell`. Bis dahin pro Befehl `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0=$PWD git …` verwenden. Agenten ändern die globale Config nicht selbst.

## Entscheidungslog

(Agenten tragen hier technische Entscheidungen ein: Datum, Entscheidung, Grund.)
