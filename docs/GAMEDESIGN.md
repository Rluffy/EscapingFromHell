# GAMEDESIGN – Escaping From Hell

Quelle: `Concept/Gameconcept.md`, `Concept/MapDesignRough.png`, `Concept/DesignIdea1.png`, `Concept/DesignIdea2.webp`. Begriffe: `GLOSSARY.md`.

## Kurz

Ein männlicher Held muss aus der Hölle fliehen. Er läuft durch eine sichere Overworld zu 10 Dungeons und besiegt dort je einen Dämon. Nach dem 10. Dämon ist das Spiel durchgespielt.

## Overworld

- Draufsicht, scrollt seitlich über ca. 3 bis 4 Bildschirme. Dungeon 1 liegt links, Dungeon 10 rechts, dazwischen ein durchgehender Weg (siehe `MapDesignRough.png`).
- **Sicher:** keine Gegner, nichts kann dem Spieler etwas tun.
- Hintergrund lebt: Lava, Pflanzen, kleine Wesen, Berge. Leichte Idle-Animationen (Lava blubbert, Pflanzen wiegen sich).
- Jeder Dungeon ist von außen ein Gebäude (Tempel-Rechteck) mit dem Dämon als Figur davor oder darin.
- Der Spieler muss die Dungeons der Reihe nach schaffen. Der nächste ist durch ein Tor/Siegel gesperrt, bis der vorherige geschafft ist. Geschaffte Dungeons sind wiederholbar.
- Dungeon betreten: Spieler steht am Eingang, **A**.

## Dungeon (Boss-Arena)

- Ein Dungeon = **ein Bildschirm**, kein Scrollen, keine Vorräume. Kurzes Intro (Boss-Name), dann Kampf.
- Side-View, Springen, Schwert.
- **3 Herzen.** Pro Treffer −1 Herz, danach ca. 1,5 s unverwundbar plus kleiner Rückstoß. Bei 0 Herzen: Dungeon startet sofort neu, Boss wieder auf vollen HP.
- Kein Heilen im Dungeon. Bei jedem (Wieder-)Betreten gibt es wieder 3 Herzen.
- Sieg: kurzer Sieg-Moment, Fähigkeit (falls vorhanden), **Autosave**, zurück in die Overworld.

## Dämonen

- Unterschiedliche Größen (klein bis riesig), bewegen sich **frei** in der Arena (laufen, hüpfen, fliegen, teleportieren).
- Phasen nach HP-Prozent, für alle gleich: **Phase 1: 100–70 %**, **Phase 2: 70–50 %**, **Phase 3: 50–0 %**. Phase 1 harmlos und schwach, Phase 3 schlimmstes Aussehen und am stärksten. Phasenwechsel mit kurzem Effekt. Jede Phase sieht sichtbar anders aus.
- HP pro Dämon einstellbar (Richtwert: Dämon 1 ca. 20 Treffer, Dämon 10 ca. 60). Werte beim Testen abstimmen.

| # | Dämon | Größe | Verhalten | Gibt dir |
|---|-------|-------|-----------|----------|
| 1 | Imp | klein | hüpft schnell, spuckt kleine Feuerbälle | **Dash** |
| 2 | Geist | mittel | schwebt, flackert, zeitweise unsichtbar | – |
| 3 | Knochenhund | mittel, breit | rennt quer durch die Arena, beißt/frisst | **Doppelsprung** |
| 4 | Lavaschlange | groß, lang | schlängelt am Rand, spuckt Feuer | – |
| 5 | Geflügelter Dämon | mittel | fliegt, stürzt herab | **Feuerball** |
| 6 | Spiegeldämon | mittel | teleportiert, erzeugt Scheinkopien | – |
| 7 | Riesenkröte | sehr groß | hüpft schwer, Zunge frisst, Schleim | **Schild** |
| 8 | Spinnenkönigin | groß | klettert an der Decke, Netze | – |
| 9 | Oni-Kriegsherr | groß | rennt, schlägt, Schockwellen | **Schwertwelle** |
| 10 | Höllenfürst | riesig | Teleport, Flug, Feuer, Unsichtbarkeit | – (Ende) |

Jeder Dungeon hat eine eigene Farbpalette. Namen und Details dürfen später geändert werden (dann hier eintragen).

## Spieler

- Start: nur Schwert. Kein Inventar, keine Shops, keine Waffen-Drops in v1.
- Fünf Fähigkeiten (siehe Tabelle), dauerhaft und gespeichert. Alle Dungeons bleiben auch ohne sie schaffbar, die Fähigkeiten machen es nur leichter.
- Steuerung: **D-Pad** laufen, **A** springen, **B** Schwert, **Start** Pause. In der Overworld **A** = Dungeon betreten. Fähigkeiten brauchen ggf. Tastenkombis: Details legt v0.3/v0.4 fest und trägt sie hier ein.

## Menüs, Story, Ende

- Titel: „New Game" und „Continue" (nur wenn Speicherstand da), Spielstand löschen im Titelmenü.
- Kurzes Intro (2 bis 3 Bildschirme Text): Du musst aus der Hölle fliehen.
- Nach Dämon 10: Endbild „You escaped". Danach frei weiterspielbar.
- Der Held hat keinen Namen und keine Dialoge. Spieltexte englisch.

## Speichern

Ein Speicherplatz, Autosave nach jedem geschafften Dungeon. Format: `TECH.md`.

## Artstyle

Asiatisch inspirierte Höllen-Tempel (Dächer, Laternen, Torbögen), nächtlich und düster, siehe `DesignIdea1.png` (blau/violett) und `DesignIdea2.webp` (rot/schwarz). Jeder Dungeon eigene Palette. Zuerst Platzhalter-Grafik, später Art-Pass (`PLAN.md`).

## Audio

v1: Soundeffekte (Treffer, Sprung, Schwert, Boss-Tod u. a.). Musik (Overworld, Dungeon, Boss) kommt danach (v0.9 oder später, siehe `PLAN.md`).
