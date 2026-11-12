# GLOSSARY

Einheitliche Begriffe für Docs, Code und Agenten.

| Begriff | Bedeutung |
|---|---|
| **Overworld** | Sichere Karte (Draufsicht, scrollt), auf der der Spieler zu den Dungeons läuft. Keine Gegner. |
| **Dungeon** | Eine Boss-Arena: ein Bildschirm, Side-View. Von außen als Gebäude in der Overworld sichtbar. 10 Stück, Reihenfolge 1 bis 10. |
| **Tor / Siegel** | Sperre vor einem Dungeon, bis der vorherige geschafft ist. |
| **Dämon** | Der Boss eines Dungeons. Hat HP und 3 Phasen. |
| **Phase** | Entwicklungsstufe eines Dämons nach HP-Prozent: 100–70, 70–50, 50–0. Jede Phase sieht anders aus und ist stärker. |
| **Herz** | Ein Leben des Spielers im Dungeon. 3 Herzen, bei 0 Neustart des Dungeons. |
| **Fähigkeit** | Dauerhafte Spielerkraft, von einem Dämon freigeschaltet: Dash, Doppelsprung, Feuerball, Schild, Schwertwelle. |
| **Autosave** | Automatisches Speichern nach jedem geschafften Dungeon. Ein Slot. |
| **Meilenstein** | Version `v0.x` in `PLAN.md`. Wird vom Orchestrator allein abgearbeitet, am Ende Nutzer-Okay. |
| **Arbeitspaket** | Kleine Aufgabe für einen Subagenten mit klarer Abnahme. |
| **Orchestrator** | Starker Agent, der Meilensteine plant, Pakete verteilt, prüft und committet. |
| **Platzhalter-Grafik** | Einfache Formen in richtiger Größe/Farbe, vor dem Art-Pass. |
| **Art-Pass** | Meilenstein v0.9: echte Pixelkunst im Stil von `Concept/DesignIdea1/2`. |
| **Smoke-Test** | Automatischer Kurztest in Mesen2 headless (Lua), prüft Speicherstellen. |
| **CHR / Bank** | NES-Grafikdaten und das Umschalten zwischen ihnen (MMC3). |
