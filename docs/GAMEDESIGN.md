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
- Side-View, Springen, Schwert. Umsetzung v0.3: Boden, Seitenwände, 3 einseitige Plattformen (von unten durchspringbar), Spieler läuft 2 px/Frame, Sprung ca. 63 px hoch (A loslassen = niedriger), Schwert 8 Frames sichtbar mit 14 Frames Abklingzeit, Trefferbox 20 px breit. Details und Zahlen: `TECH.md` „Dungeon (v0.3)". Dungeon 1 hat den Imp (siehe unten), Dungeon 2 hat den Geist, Dungeon 3 den Knochenhund, Dungeon 4 die Lavaschlange, Dungeon 5 den Geflügelten Dämon (beide siehe unten), Dungeons 6–10 vorläufig einen Test-Dummy (5 HP, läuft hin und her). Intro: Boss-Name groß in der Bildmitte, 1,25 s, alles steht.
- **3 Herzen.** Pro Treffer −1 Herz, danach 2 s (120 Frames) unverwundbar (Spieler blinkt) plus kleiner Rückstoß weg vom Gegner. Herzen stehen als HUD oben links. Bei 0 Herzen: Dungeon startet sofort neu, Boss wieder auf vollen HP.
- **Gegner-HP-Balken** (seit v0.3-Fix, Wunsch aus dem Nutzer-Test): oben rechts, Kachelzeile 2, 10 Kacheln = 20 Halbschritte, rechtsbündig innerhalb der Wände. Voll = hell, leer = dunkel, halbe Kachel = ein Halbschritt. Länge = aufgerundet HP/Max-HP (jede HP > 0 zeigt mindestens einen Halbschritt). Gilt für jeden Dämon und den Test-Dummy, erscheint schon im Intro, sinkt bei jedem Treffer, leer bei 0 HP.
- Kein Heilen im Dungeon. Bei jedem (Wieder-)Betreten gibt es wieder 3 Herzen.
- **Sieg** (Umsetzung v0.3): Beim letzten Treffer verschwindet der Dämon, 2 s Sieg-Bildschirm („VICTORY" in der Mitte, bei neuer Fähigkeit darunter „GOT DASH"), Eingaben aus. Dann Dungeon als geschafft markieren, Fähigkeit freischalten, **Autosave**, zurück in die Overworld an die Tür (nächstes Tor offen). Dungeon 3 (Knochenhund) zeigt „GOT DOUBLE JUMP" und schaltet den Doppelsprung frei. Dungeon 5 (Geflügelter Dämon) zeigt „GOT FIREBALL“ und schaltet den Feuerball frei. Dungeon 2 (Geist), 4 (Lavaschlange) und 6–10 (Test-Dummy) laufen gleich ab, nur ohne Fähigkeit.
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
| 4 | Lavaschlange | groß, lang | steigt aus Lava am Rand, spuckt Feuer, taucht ab | – |
| 5 | Geflügelter Dämon | mittel | fliegt, stürzt herab | **Feuerball** |
| 6 | Spiegeldämon | mittel | teleportiert, erzeugt Scheinkopien | – |
| 7 | Riesenkröte | sehr groß | hüpft schwer, Zunge frisst, Schleim | **Schild** |
| 8 | Spinnenkönigin | groß | klettert an der Decke, Netze | – |
| 9 | Oni-Kriegsherr | groß | rennt, schlägt, Schockwellen | **Schwertwelle** |
| 10 | Höllenfürst | riesig | Teleport, Flug, Feuer, Unsichtbarkeit | – (Ende) |

**Imp (umgesetzt, v0.3):** 10 HP (1 Schaden pro Schwertschlag), 16x16, hüpft nur am Boden, Kontakt = −1 Herz (nicht während seines Trefferblinkens). Ein Schwerttreffer schiebt ihn 16 px vom Spieler weg (nicht aus der Arena). Phase 1 (10–8 HP, grün, schlicht): hüpft langsam (1 px/Frame, Pause 120 Frames), spuckt alle 300 Frames einen langsamen Feuerball (1 px/Frame). Phase 2 (7–6 HP, orange, Hörner): Tempo 1, Pause 80, Feuerball alle 200 Frames. Phase 3 (5–0 HP, rot-gelb, große Hörner): Tempo 2, Pause 56, alle 240 Frames ein Dreifach-Fächer (Feuerbälle 1 px/Frame; der untere Schuss trifft sofort den Boden, der mittlere ist überspringbar, der obere fliegt meist über den Spieler). Balance nach Nutzer-Test („zu schwer“): HP 20 → 16, alle Zahlen sanfter als in der ersten Fassung (Phase 1: Pause 40, Feuerball alle 100; Phase 2: 24 / 60, Feuerball 2 px; Phase 3: Tempo 3, Pause 14, alle 75, Feuerball 2 px). Nach dem 2. Nutzer-Test („immer noch zu schwer“) halbiert: HP 16 → 10, Pausen und Feuerraten ungefähr verdoppelt (siehe oben). Phasenwechsel: 0,5 s Blinken, Imp steht und ist harmlos, Feuerbälle verschwinden. Feuerbälle (max. 3) sind per Sprung zu überspringen. Genaue Zahlen: `TECH.md` „Boss-Rahmen (v0.3)". Werte beim nächsten Nutzer-Test weiter prüfen.

**Geist (umgesetzt, v0.4):** 12 HP (1 Schaden pro Schwertschlag, Phase 2 ab 8 HP, Phase 3 ab 6 HP), 16x24 (Platzhalter-Kacheln), schwebt ohne Schwerkraft. Er driftet seitlich vom Spieler (40 px Abstand, wechselt alle ca. 2 s die Seite, an den Wänden geklemmt) und wippt dabei zwischen y = 104 und 168 (Dreieckswelle, 128 Frames): im tiefsten Punkt trifft das Schwert ihn vom Boden aus, sonst per Sprung plus Schlag (von Plattformen auch). Kontakt = −1 Herz, Schwerttreffer schiebt ihn 16 px weg wie beim Imp. **Unsichtbarkeit:** nach einem sichtbaren Fenster (Phase 1 / 2 / 3: 250 / 220 / 160 Frames) flackert er 20 Frames (noch treffbar), ist dann 90 Frames unsichtbar und **nicht treffbar, ohne Kontaktschaden**, und flackert vor dem Wiedererscheinen 30 Frames (sichtbar im Wechsel, aber noch nicht treffbar und harmlos), dann wieder fest. Phase 1 (weiß, runder Kopf, 12–9 HP): nur Driften (Tempo 0,5 px/Frame) und Kontakt. Phase 2 (8–7 HP, violett, Arme und größere Augen): Drift 0,75 px/Frame, alle 150 Frames (nur im festen Zustand) **Sturzflug**: 30 Frames Warnung (steht still, flackert), Ziel = Spielerposition zu Beginn der Warnung, Flug mit 3 px/Frame, dann 20 Frames Pause am Ziel, danach zurück in die Wippe. Phase 3 (6–0 HP, rot-rosa, Hörner, Krallen, zackiger Mund): Drift 1 px/Frame, alle 180 Frames Angriff im Wechsel Sturzflug und **langsamer Feuerball** (Warnung wie oben, ein Schuss, 1 px/Frame, aufs Spielerniveau zielend; der Feuerball ist wie beim Imp per Sprung ausweichbar). Phasenwechsel wie beim Imp (0,5 s Blinken, harmlos). Gibt **keine Fähigkeit** (Sieg-Bildschirm nur „VICTORY"). Eigene Dungeon-Palette (rot/schwarz). Messung mit einem stehenden Bot (1200 Frames je Phase, Spieler ohne Eingabe auf dem Boden): 0 / 4 / 2 Herzverluste, ähnlich leicht wie der halbierte Imp. Genaue Zahlen: `TECH.md` „Geist (v0.4)".

**Knochenhund (umgesetzt, v0.4):** 14 HP (1 Schaden pro Schwertschlag, Phase 2 ab 9 HP, Phase 3 ab 7 HP), 24x16 (Platzhalter, symmetrisch), rennt nur am Boden. Name im Intro „BONE HOUND". Kontakt = −1 Herz, Schwerttreffer schiebt ihn 16 px weg. **Patrouille:** läuft hin und her (Phase 1 / 2 / 3: 1 / 1 / 2 px/Frame), kehrt an den Wänden um. **Anlauf:** alle 180 / 150 / 120 Frames Ankündigung (30 / 24 / 20 Frames: steht still und flackert, Richtung zum Spieler), dann Anlauf über die ganze Arena (4 / 5 / 5 px/Frame, ein gehaltener Sprung reicht locker; mit Doppelsprung noch leichter). An der Wand ist er **benommen** (40 Frames, steht still, blinkt langsam, treffbar) = das Hauptfenster für das Schwert. **Biss:** ist der Spieler am Boden und weniger als ca. 28 px entfernt, kurzer Vorstoß (10 Frames, 3 px/Frame), danach 20 Frames Pause, dann 90 Frames Abklingzeit. Phase 2 (9–8 HP, orange): schnellerer Anlauf, kürzere Ankündigung, in 25 % der Angriffe stattdessen ein **Sprung** (Bogen zur Spielerposition beim Absprung, ca. 33 Frames Flug, 45 px hoch, danach 20 Frames Pause). Phase 3 (7–0 HP, weiß-rot, Stacheln): zwei Anläufe hintereinander (nach dem ersten an der Wand 10 Frames Ankündigung, dann zurück), Sprung in 50 % der Angriffe, Lauftempo 2. Kein Knochenwurf. Gibt den **Doppelsprung** (Sieg-Text „GOT DOUBLE JUMP"). Messung mit stehendem Bot (1200 Frames je Phase): 4 / 4 / 5 Herzverluste, ähnlich wie Imp und Geist. Genaue Zahlen: `TECH.md` „Knochenhund (v0.4)".

**Lavaschlange (umgesetzt, v0.5):** 14 HP (1 Schaden pro Schwertschlag, Phase 2 ab 9 HP, Phase 3 ab 7 HP), Kopf 16x16 plus Körper aus bis zu 8 Segmenten (16x8, Platzhalter). Name im Intro „LAVA SNAKE". Die Arena hat an beiden Wänden je ein **Lavabecken** (4 Kacheln im Boden, nur Optik, harmlos: der Boden bleibt fest). Ablauf eines Besuchs: **untergetaucht** (Phase 1 / 2 / 3: 100 / 70 / 40 Frames, unsichtbar und **nicht treffbar, kein Kontaktschaden**) → **Ankündigung** 30 Frames am Becken (der Kopf flackert, noch nicht treffbar), sie taucht immer am **anderen** Becken auf als zuletzt → **steigt** senkrecht aus dem Becken (1 / 2 / 2 px/Frame) bis y 124 → **oben** 170 Frames (Kopf neigt sich bis 96 px zum Spieler, schwingt seitlich und wippt, Körper biegt sich als Säule vom Becken zum Kopf) → **sinkt** zurück ins Becken. Nur der **Kopf** ist treffbar (Schwert geht durch den Körper), Kopf und Körper tun bei Berührung −1 Herz. **Feuer:** vor jedem Spucken flackert der Kopf 20 Frames (noch treffbar), Feuerball 1 px/Frame. Phase 1 (orange, rundes Gesicht, 14–10 HP): ein Schuss pro Besuch, **waagerecht auf Kopfhöhe** (ein Spieler am Boden wird nicht getroffen, wer zum Kopf springt, muss ausweichen). Phase 2 (9–8 HP, rot, Hörner): schneller, **spuckt zweimal** pro Besuch (gezielt auf den Spieler). Phase 3 (7–0 HP, gelb-weiß, Krone und Reißzähne): **Dreifach-Fächer** (gezielt, Schüsse laufen auseinander), nur 40 Frames untergetaucht. Keine Fähigkeit (nur „VICTORY"). Eigene Palette (Lava rot/orange). Messung mit stehendem Bot (Spieler ohne Eingabe bei x 48, 1200 Frames je Phase): 0 / 1 / 2 Herzverluste. Genaue Zahlen: `TECH.md` „Lavaschlange (v0.5)".

**Geflügelter Dämon (umgesetzt, v0.5):** 14 HP (1 Schaden pro Schwertschlag oder Feuerball, Phase 2 ab 9 HP, Phase 3 ab 7 HP), 16x24 (Platzhalter). Name im Intro „WINGED DEMON“ (passt komplett). Fliegt ohne Schwerkraft in der oberen Hälfte (y 56..71) und patrouilliert seitlich mit sanftem Wippen (Phase 1 / 2 / 3: 0,75 / 1,25 / 1,5 px/Frame, kehrt an den Wänden um). Nach der Patrouille (420 / 300 / 420 Frames) folgt der **Sturzangriff**: **Ankündigung** (30 / 28 / 24 Frames): er gleitet über den Spieler und flackert (noch treffbar), danach legt er sich auf dessen x fest und **stürzt** (4 / 5 / 5 px/Frame, fast senkrecht) bis auf den Boden. Dort **ruht er 40 Frames** (steht still, treffbar, das Hauptfenster für das Schwert vom Boden aus; ein Spieler daneben wird bei Berührung getroffen), dann steigt er mit 3 px/Frame wieder auf. Kontakt (Patrouille, Ankündigung, Sturz, Ruhe) = −1 Herz; in der Höhe ist er vom Boden aus nicht erreichbar (nur per Sprung von einer Plattform). Phase 1 (rosa-violett, schlichte Flügel, 14–10 HP): nur Patrouille und Sturz. Phase 2 (9–8 HP, orange-rosa, Hörner, größere Flügel): schneller, Sturz häufiger, wirft beim Aufsteigen (oberhalb y 120) **einen langsamen Feuerball** (1 px/Frame, zur Spielerseite hin schräg nach unten). Phase 3 (7–0 HP, rot, große Hörner, Stacheln): **Doppelsturz** (nach dem Aufsteigen sofort eine zweite, kürzere Ankündigung von 14 Frames und ein zweiter Sturz) und beim Aufsteigen ein **Fächer aus drei Feuerbällen** (nach links / senkrecht / nach rechts, 1 px/Frame, versetzt gestartet). Phasenwechsel wie bei den anderen (0,5 s Blinken, harmlos). Gibt den **Feuerball** (Sieg-Text „GOT FIREBALL“). Eigene Dungeon-Palette (olivgrün) und Sprite-Paletten je Phase. Messung mit stehendem Bot (Spieler ohne Eingabe bei x 48, 1200 Frames je Phase): 2 / 3 / 3 Herzverluste (beim dritten Verlust wäre der Kampf neu gestartet; ein stehender Bot wird von jedem Sturz getroffen, ein echter Spieler läuft weg). Genaue Zahlen: `TECH.md` „Geflügelter Dämon (v0.5)“.

Jeder Dungeon hat eine eigene Farbpalette. Namen und Details dürfen später geändert werden (dann hier eintragen).

## Spieler

- Start: nur Schwert. Kein Inventar, keine Shops, keine Waffen-Drops in v1.
- Fünf Fähigkeiten (siehe Tabelle), dauerhaft und gespeichert. Alle Dungeons bleiben auch ohne sie schaffbar, die Fähigkeiten machen es nur leichter.
- Steuerung: **D-Pad** laufen, **A** springen, **B** Schwert, **Start** Pause (friert das Spiel ein, kein Pausen-Bild). **Select** = Dash (erst nach Dämon 1; vorher tut Select im Kampf nichts). **Start, dann Select** = Kampf aufgeben (zurück zur Tür). In der Overworld **A** = Dungeon betreten. **Doppelsprung** (erst nach Dämon 3): **A** noch einmal in der Luft. **Feuerball** (erst nach Dämon 5): **Hoch + B** (statt Schwerthieb, Hoch allein tut nichts). Weitere Fähigkeiten legt v0.6 ff. fest.
- **Feuerball:** Hoch + B mit der Fähigkeit schießt ein kleines Projektil (8x8, hellblau-weiß, anders als die roten Dämonen-Feuerbälle) **geradeaus in Blickrichtung**, 3 px/Frame, es verschwindet an der Wand. Höchstens **eines** auf dem Bildschirm, Abklingzeit 40 Frames ab dem Schuss; auf diesen Tastendruck folgt **kein** Schwerthieb (auch nicht, wenn die Abklingzeit den Schuss blockiert). Ohne die Fähigkeit ist Hoch + B ein normaler Schwerthieb. Schaden 1 auf Bosse und Test-Dummy über denselben Weg wie das Schwert (Phasen, HP-Balken, Sieg), nur bei einem treffbaren Boss: ein untergetauchter oder unsichtbarer Dämon (`boss_hide`), Trefferblinken und Phasenwechsel-Effekt lassen das Projektil durchfliegen; bei der Lavaschlange zählt nur der Kopf.
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
