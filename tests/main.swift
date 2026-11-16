import Foundation
// Collaudo del modello obiettivi. Compilato con Common.swift + GoalStore.swift (vedi tests/run.sh).
var failed = 0
func check(_ ok: Bool, _ msg: String) { print((ok ? "  ok   " : "  FAIL ") + msg); if !ok { failed += 1 } }
func date(_ s: String) -> Date { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: f.date(from: s)!)! }
func sha(_ u: URL) -> String { let d = (try? Data(contentsOf: u)) ?? Data(); return String(d.hashValue) + "/\(d.count)" }

let g = GoalStore.shared
print("1) migrazione")
check(g.periods.count == 2, "creati 2 periodi (prima/dopo il 12 ott)")
check(g.periods[0].perDay == Array(repeating: 10800, count: 7) && g.periods[0].weekly == 72000, "periodo iniziale = 3h/giorno, 20h/settimana (come prima)")
check(g.periods[1] == GoalStore.oct12, "periodo dal 2026-10-12 = lun–ven 3h30, sab 4h, dom 1h30")
let h1 = sha(g.url)

print("2) obiettivo per giorno")
let cases: [(String, Int, String)] = [("2026-09-28", 10800, "lun, prima"), ("2026-10-01", 10800, "gio, prima"), ("2026-10-11", 10800, "dom 11 ott = ultimo giorno a 3h"),
    ("2026-10-12", 12600, "lun 12 ott = primo giorno a 3h30"), ("2026-10-16", 12600, "ven"), ("2026-10-17", 14400, "sab 4h"), ("2026-10-18", 5400, "dom 1h30"), ("2026-10-19", 12600, "lun dopo")]
for (d, want, why) in cases { check(g.goal(on: date(d)) == want, "\(d) → \(want / 60) min (\(why))") }

print("3) settimane")
check(g.weeklyGoal(of: date("2026-10-01")) == 72000, "settimana 28 set–4 ott: 20h (override del periodo iniziale)")
check(g.weeklyGoal(of: date("2026-10-08")) == 72000, "settimana 5–11 ott: 20h")
check(g.weeklyGoal(of: date("2026-10-14")) == 82800, "settimana dal 12 ott: 23h")
check(g.weekGoals(of: date("2026-10-14")) == [12600, 12600, 12600, 12600, 12600, 14400, 5400], "gradini della settimana dal 12 ott")
check(g.weekGoals(of: date("2026-10-08")) == Array(repeating: 10800, count: 7), "settimana 5–11 ott piatta a 3h")

print("4) idempotenza: secondo avvio non riscrive")
let g2 = GoalStore()                       // rilegge il file esistente
check(sha(g.url) == h1, "goals.json identico dopo una seconda inizializzazione")
check(g2.periods == g.periods, "stessi periodi")

print("5) aggiunta (solo append)")
setenv("STUDYTIMER_TODAY", "2026-10-02", 1)
let before = g.periods
check(g.add(from: "2026-11-02", perDay: Array(repeating: 9000, count: 7)) == .added, "nuovo periodo dal 2 nov aggiunto")
check(Array(g.periods.filter { before.contains($0) }) == before, "i periodi esistenti non sono cambiati")
check(g.periods.count == 3 && g.periods.last!.from == "2026-11-02", "ora 3 periodi, in ordine")
let h2 = sha(g.url)
check(g.add(from: "2026-11-02", perDay: Array(repeating: 7200, count: 7)) == .exists, "stessa data → .exists, nulla scritto")
check(g.add(from: "2026-10-12", perDay: Array(repeating: 7200, count: 7)) == .exists, "data di un periodo esistente (12 ott) → .exists")
check(sha(g.url) == h2, "goals.json non toccato dai tentativi con data esistente")
check(g.add(from: "2026-09-30", perDay: Array(repeating: 7200, count: 7)) == .inPast, "data nel passato rifiutata")
check(g.add(from: "2026-12-01", perDay: [0, 1, 1, 1, 1, 1, 1]) == .invalid, "obiettivo a zero rifiutato")
check(g.goal(on: date("2026-11-03")) == 9000 && g.goal(on: date("2026-10-30")) == 12600, "giorni prima del 2 nov invariati, dopo = nuovo")

print("6) sostituzione solo esplicita, con copia di sicurezza")
check(g.replace(from: "2026-11-02", perDay: Array(repeating: 7200, count: 7)), "replace dopo conferma")
check(g.goal(on: date("2026-11-03")) == 7200, "periodo sostituito")
let backups = (try? FileManager.default.contentsOfDirectory(atPath: g.url.deletingLastPathComponent().path))?.filter { $0.hasPrefix("goals-backup-") } ?? []
check(!backups.isEmpty, "creata copia goals-backup-*.json prima di sostituire")
check(!g.replace(from: "2026-10-01", perDay: Array(repeating: 7200, count: 7)), "mai sostituire periodi passati")

print("7) testo")
check(GoalStore.summary(GoalStore.oct12) == "Lun–Ven 3h30 · Sab 4h · Dom 1h30", "riga informativa: \(GoalStore.summary(GoalStore.oct12))")
check(GoalStore.summary(g.periods[0]) == "Lun–Dom 3h", "riga periodo iniziale: \(GoalStore.summary(g.periods[0]))")
print(failed == 0 ? "\nTUTTI I TEST OK" : "\n\(failed) TEST FALLITI"); exit(failed == 0 ? 0 : 1)
