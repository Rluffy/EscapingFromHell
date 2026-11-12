# CLAUDE.md – Regeln für alle Agenten (EscapingFromHell)

NES-Spiel *Escaping From Hell*. Erst `docs/PLAN.md` lesen, dann `docs/GAMEDESIGN.md`, `docs/TECH.md`, `docs/GLOSSARY.md`.

## Harte Regeln

1. **Docs aktuell halten.** Jede Änderung an Spiel, Technik, Plan oder Release aktualisiert die passende Datei in `docs/` **im selben Commit**. Veraltete Docs = Aufgabe nicht fertig.
2. **Autonom pro Meilenstein.** Den nächsten offenen Meilenstein in `docs/PLAN.md` allein abarbeiten. Stopp **nur am Meilenstein-Ende** mit Bericht (siehe PLAN.md). Mitten drin nur fragen, wenn es ohne Antwort nicht weitergeht. Alles andere selbst entscheiden, in den Docs festhalten und im Bericht als „Entscheidung" markieren.
3. **Definition of Done** (pro Arbeitspaket und Meilenstein): `make` grün, `make test` grün, Meilenstein zusätzlich Screenshot in `docs/screenshots/`. Erst dann committen.
4. **Agenten:** Bruno und Carli **nicht** verwenden. Subagenten nur über `general-purpose` mit explizitem Modell: **Haiku 5.5** (Dateiarbeit, Skripte, Doku), **Sonnet 5.5** (C/Assembler, Boss-Logik, Tests). Der Orchestrator ist ein stärkeres Modell (Opus 5.5). Alle nutzen den `/ponytail`-Skill (kleinste Lösung, die reicht).
5. **Git:** Commit-Nachrichten englisch, ein kleiner Commit pro fertigem Arbeitspaket, Tag pro Meilenstein (erst nach Okay des Nutzers). Die ROM kommt **nicht** in die Git-Historie, sondern ans GitHub-Release (`docs/RELEASE.md`).

## Weitere Festlegungen

- Sprache: Docs deutsch; Code, Dateinamen, Commits und Spieltexte englisch.
- `Concept/` ist die Quelle des Nutzers und bleibt unverändert.
- Repo-Name auf GitHub: `EscapingFromHell` (CamelCase, privat bis v1.0).
- Installationen für Build/Test (`cc65`, `gh`, `xvfb`, `python3-pil`, Mesen2 in `tools/mesen/`) sind vom Nutzer erlaubt. Siehe `docs/TECH.md`.
- Der GitHub-Login (`gh auth login`) macht der Nutzer parallel. Bis dahin lokal bauen und committen, danach pushen.
