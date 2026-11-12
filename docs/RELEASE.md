# RELEASE

## Versionen

Tag pro Meilenstein: `v0.1`, `v0.2`, … `v1.0`. Tag und Release erst **nach Okay des Nutzers** (siehe `PLAN.md`).

## ROM

- Name: `dist/EscapingFromHell-vX.Y.nes`.
- Die ROM kommt **nicht** in die Git-Historie (`.gitignore`), sondern als Anhang ans GitHub-Release.

## Ablauf

1. `make clean && make && make test` – alles grün.
2. `cp build/EscapingFromHell.nes dist/EscapingFromHell-vX.Y.nes`
3. `docs/PLAN.md` Status auf „erledigt", Docs aktuell prüfen, committen.
4. `git tag -a vX.Y -m "Milestone vX.Y"` und `git push && git push --tags`
5. `gh release create vX.Y dist/EscapingFromHell-vX.Y.nes --title "vX.Y" --notes-file <Notizen>`

Ohne `gh`-Login (Schritt 4/5): lokal taggen, Push und Release nachholen, sobald der Nutzer eingeloggt ist.

## Repo

GitHub: `EscapingFromHell`, privat bis zur Freigabe von v1.0.
