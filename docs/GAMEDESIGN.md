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
- Umsetzung v0.2: 4 Bildschirme (1024 px), Tempel-Raster und Steuerung siehe `TECH.md` „Overworld (v0.2)". Spieler läuft mit 2 px/Frame in 8 Richtungen, Tore sind fest (verschlossen = Hindernis, offen = begehbar). Der Dungeon selbst: siehe unten (seit v0.3 echte Arena). Zurück zum Eingang geht es nach dem Sieg oder mit Start dann Select (siehe „Spieler").

## Dungeon (Boss-Arena)

- Ein Dungeon = **ein Bildschirm**, kein Scrollen, keine Vorräume. Kurzes Intro (Boss-Name), dann Kampf.
- Side-View, Springen, Schwert. Umsetzung v0.3: Boden, Seitenwände, 3 einseitige Plattformen (von unten durchspringbar), Spieler läuft 2 px/Frame, Sprung ca. 63 px hoch (A loslassen = niedriger), Schwert 8 Frames sichtbar mit 14 Frames Abklingzeit, Trefferbox 20 px breit. Details und Zahlen: `TECH.md` „Dungeon (v0.3)". Dungeon 1 hat den Imp (siehe unten), Dungeons 2–10 vorläufig einen Test-Dummy (5 HP, läuft hin und her). Intro: Boss-Name groß in der Bildmitte, 1,25 s, alles steht.
- **3 Herzen.** Pro Treffer −1 Herz, danach 2 s (120 Frames) unverwundbar (Spieler blinkt) plus kleiner Rückstoß weg vom Gegner. Herzen stehen als HUD oben links. Bei 0 Herzen: Dungeon startet sofort neu, Boss wieder auf vollen HP.
- **Gegner-HP-Balken** (seit v0.3-Fix, Wunsch aus dem Nutzer-Test): oben rechts, Kachelzeile 2, 10 Kacheln = 20 Halbschritte, rechtsbündig innerhalb der Wände. Voll = hell, leer = dunkel, halbe Kachel = ein Halbschritt. Länge = aufgerundet HP/Max-HP (jede HP > 0 zeigt mindestens einen Halbschritt). Gilt für jeden Dämon und den Test-Dummy, erscheint schon im Intro, sinkt bei jedem Treffer, leer bei 0 HP.
- Kein Heilen im Dungeon. Bei jedem (Wieder-)Betreten gibt es wieder 3 Herzen.
- **Sieg** (Umsetzung v0.3): Beim letzten Treffer verschwindet der Dämon, 2 s Sieg-Bildschirm („VICTORY" in der Mitte, bei neuer Fähigkeit darunter „GOT DASH"), Eingaben aus. Dann Dungeon als geschafft markieren, Fähigkeit freischalten, **Autosave**, zurück in die Overworld an die Tür (nächstes Tor offen). Dungeons 2–10 (Test-Dummy) laufen gleich ab, nur ohne Fähigkeit.
- **Aufgeben:** **Start** (Pause), dann **Select** bricht den Kampf ab: zurück zur Tür, nichts gespeichert, Dungeon-Fortschritt unverändert.

## Dämonen

- Unterschiedliche Größen (klein bis riesig), bewegen sich **frei** in der Arena (laufen, hüpfen, fliegen, teleportieren).
- Phasen nach HP-Prozent, für alle gleich: **Phase 1: 100–70 %**, **Phase 2: 70–50 %**, **Phase 3: 50–0 %**. Phase 1 harmlos und schwach, Phase 3 schlimmstes Aussehen und am stärksten. Phasenwechsel mit kurzem Effekt. Jede Phase sieht sichtbar anders aus.
- HP pro Dämon einstellbar (Richtwert: Dämon 1 ca. 16 Treffer, Dämon 10 ca. 60). Werte beim Testen abstimmen.

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

**Imp (umgesetzt, v0.3):** 16 HP (1 Schaden pro Schwertschlag), 16x16, hüpft nur am Boden, Kontakt = −1 Herz (nicht während seines Trefferblinkens). Ein Schwerttreffer schiebt ihn 16 px vom Spieler weg (nicht aus der Arena). Phase 1 (16–12 HP, grün, schlicht): hüpft langsam (1 px/Frame, Pause 60 Frames), spuckt alle 150 Frames einen langsamen Feuerball (1 px/Frame). Phase 2 (11–9 HP, orange, Hörner): Tempo 2, Pause 40, Feuerball alle 100 Frames. Phase 3 (8–0 HP, rot-gelb, große Hörner): Tempo 2, Pause 28, alle 120 Frames ein Dreifach-Fächer (Feuerbälle 1 px/Frame; der untere Schuss trifft sofort den Boden, der mittlere ist überspringbar, der obere fliegt meist über den Spieler). Balance nach Nutzer-Test („zu schwer“): HP 20 → 16, alle Zahlen sanfter als in der ersten Fassung (Phase 1: Pause 40, Feuerball alle 100; Phase 2: 24 / 60, Feuerball 2 px; Phase 3: Tempo 3, Pause 14, alle 75, Feuerball 2 px). Phasenwechsel: 0,5 s Blinken, Imp steht und ist harmlos, Feuerbälle verschwinden. Feuerbälle (max. 3) sind per Sprung zu überspringen. Genaue Zahlen: `TECH.md` „Boss-Rahmen (v0.3)". Werte beim nächsten Nutzer-Test weiter prüfen.

Jeder Dungeon hat eine eigene Farbpalette. Namen und Details dürfen später geändert werden (dann hier eintragen).

## Spieler

- Start: nur Schwert. Kein Inventar, keine Shops, keine Waffen-Drops in v1.
- Fünf Fähigkeiten (siehe Tabelle), dauerhaft und gespeichert. Alle Dungeons bleiben auch ohne sie schaffbar, die Fähigkeiten machen es nur leichter.
- Steuerung: **D-Pad** laufen, **A** springen, **B** Schwert, **Start** Pause (friert das Spiel ein, kein Pausen-Bild). **Select** = Dash (erst nach Dämon 1; vorher tut Select im Kampf nichts). **Start, dann Select** = Kampf aufgeben (zurück zur Tür). In der Overworld **A** = Dungeon betreten. Weitere Fähigkeiten legt v0.4 ff. fest (Doppelsprung vermutlich A in der Luft).
- **Dash:** 4 px/Frame (Laufen: 2) für 10 Frames, also ca. 40 px in Blickrichtung, **unverwundbar** währenddessen (Spieler blinkt): man kann durch den Imp und Feuerbälle hindurch. Abklingzeit 30 Frames ab Dash-Start. Auch in der Luft möglich (Schwerkraft läuft weiter). Zahlen beim Balancing prüfen.

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
