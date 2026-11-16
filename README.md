# Study Timer

Pillola-timer per macOS (design "Study Timer JP"). Overlay su tutti gli Spaces e sopra le app a schermo intero,
segue il desktop attivo. **⇧⌘T** la mostra/nasconde. Il timer continua a girare anche quando è nascosta.

    ./build.sh && open "build/Study Timer.app"

- Cronometro da 00:00:00 (ore sempre visibili). Pulsante: start / pausa / riprendi; in pausa chip FINISH ✓ e RESET ↺.
- Ridimensiona: maniglie negli angoli in alto a sinistra e in basso a destra (doppio click = dimensione originale) o dal menu barra (Ingrandisci / Rimpicciolisci).
- Trascina la pillola per spostarla (posizione ricordata); menu barra: "Ripristina posizione", "Esci".
- Fine timer: suono + la pillola compare da sola se era nascosta.
- Font Dela Gothic One caricato da Google Fonts (online); offline ripiega su Hiragino Sans W8.
- Test: `pkill -USR1 StudyTimer` = ⇧⌘T; `STUDYTIMER_QUERY="state=running&elapsed=1122"` forza uno stato;
  `STUDYTIMER_SNAPSHOT=x.png` + `pkill -USR2` salva un PNG della pagina (non serve il permesso registrazione schermo).

## Widget
Tre taglie (Small 170×170, Medium 364×170, Large 364×382) come finestre al livello della scrivania, su ogni Space.
- Menu barra → Widget → Aggiungi Small/Medium/Large; tasto destro su un widget → obiettivi / Rimuovi. Trascina per spostare, click = apre il timer.
- I secondi studiati (timer in corso) vanno in `~/Library/Application Support/StudyTimer/sessions.json` (giorno → secondi); i widget li leggono.
- Obiettivi: giornaliero (default 3 h) e settimanale (default 20 h) dal menu. Settimana da lunedì.
- Test: `STUDYTIMER_SUITE`, `STUDYTIMER_DATA` isolano preferenze e dati; `STUDYTIMER_SNAPSHOT_WIDGETS=<dir>` + `pkill -USR2` salva un PNG per widget.

## Study Grid
Widget a griglia stile contributi (Grid Small 184×184 · Medium 480×170 · Large 804×256), da `StudyGrid.dc.html`.
Una cella per giorno, colorata in 6 livelli (0 · <30 · <60 · <120 · <240 · ≥240 min) dalle ore del timer; oggi ha l'anello e pulsa a timer in corso.
Large = anno accademico (1 set → 31 ago). Sfondo bianco e font Dela Gothic One (come il widget settimanale). Menu → Widget → Aggiungi Grid …

## Obiettivo giornaliero (anello)
Anello che si riempie con le ore di oggi rispetto all'obiettivo giornaliero (Obiettivo Small 170×170 · Medium 364×170). Si aggiorna in tempo reale
a timer in corso; superato l'obiettivo diventa rosso scuro e mostra "COMPLETATO ✓" e le ore in più. Menu → Widget → Aggiungi Obiettivo …

## Obiettivi (cronologia)
Gli obiettivi sono una **cronologia di periodi** in `~/Library/Application Support/StudyTimer/goals.json`: ogni periodo vale da `from` (yyyy-MM-dd) fino
all'inizio del successivo e ha 7 obiettivi in secondi (lun→dom). Ogni giorno è valutato con l'obiettivo valido *in quel giorno*; `sessions.json` (le ore) non viene mai toccato.
- `weekly` (opzionale): override dell'obiettivo settimanale; se assente è la somma dei 7 giorni (23 h dal 12/10/2026, 20 h prima).
- Migrazione idempotente: `goals.json` viene creato solo se manca (3h/giorno + 20h/sett. fino all'11/10/2026, poi lun–ven 3h30 · sab 4h · dom 1h30).
- Menu → "Modifica obiettivi…" **aggiunge** un periodo ("Valido da", default lunedì prossimo; non nel passato). Se la data esiste già chiede conferma e salva prima `goals-backup-*.json`.
- Widget: "Oggi" (percentuale, barra e linea a gradini per giorno), anello (si completa all'obiettivo del giorno), Study Medium ("44% · 23H" sotto le ore della settimana). Rinfresco ogni minuto e al risveglio.
- Test: `./tests/run.sh` (modello obiettivi, isolato). `STUDYTIMER_TODAY=2026-10-12` simula la data, `STUDYTIMER_GOALS=<file>` isola goals.json.
- Backup dei dati: `backups/` (export JSON + copia di sessions.json con data nel nome).
