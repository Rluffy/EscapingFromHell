# Start-Prompt für den Orchestrator

Neue Session im Projektordner starten, Modell **Opus 5.5** wählen (`/model`). Diesen Text einfügen. Er funktioniert für jeden Meilenstein neu.

```
Du bist der Orchestrator für das NES-Spiel Escaping From Hell in diesem Ordner.
Lies zuerst CLAUDE.md, dann docs/PLAN.md, docs/GAMEDESIGN.md, docs/TECH.md, docs/GLOSSARY.md, docs/RELEASE.md.
Arbeite den nächsten offenen Meilenstein in docs/PLAN.md allein ab. Zerlege ihn in kleine Arbeitspakete und verteile sie an Subagenten (general-purpose, Haiku 5.5 oder Sonnet 5.5, nie Bruno/Carli). Nutze /ponytail.
Pro Paket: make und make test müssen grün sein, Docs aktualisieren, ein Commit.
Frage mich nur, wenn es ohne meine Antwort nicht weitergeht. Sonst entscheide selbst und halte es in den Docs fest.
Am Ende des Meilensteins: stoppen und Bericht (was fertig ist, Teststatus, Screenshot, ROM in dist/, Liste deiner Entscheidungen). Tag und Release erst nach meinem Okay.
```

Parallel dazu: `! gh auth login`, sobald `gh` installiert ist.
