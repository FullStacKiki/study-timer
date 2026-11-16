import Cocoa

// Obiettivi di studio come CRONOLOGIA di periodi: ogni periodo vale dalla data `from` fino all'inizio del successivo
// e contiene un obiettivo per ogni giorno della settimana. Cosi' ogni giorno e' valutato con l'obiettivo valido
// in quel giorno e i periodi passati non cambiano mai. Non tocca sessions.json (le ore registrate).
//
// File: ~/Library/Application Support/StudyTimer/goals.json

struct GoalPeriod: Codable, Equatable {
    var from: String          // "yyyy-MM-dd": primo giorno di validita'
    var perDay: [Int]         // secondi, lunedi' → domenica (7 valori)
    var weekly: Int?          // override dell'obiettivo settimanale; assente = somma dei 7 giorni
}

enum GoalAddResult { case added, exists, inPast, invalid }

/// "yyyy-MM-dd" di oggi, o STUDYTIMER_TODAY (solo test) per simulare un'altra data.
func today() -> Date {
    if let t = env["STUDYTIMER_TODAY"] {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: t) { return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: d) ?? d }
    }
    return Date()
}

final class GoalStore {
    static let shared = GoalStore()

    /// Periodi ordinati per `from`. Il primo copre tutto cio' che lo precede.
    private(set) var periods: [GoalPeriod] = []
    let url: URL
    private let cal = StudyStore.shared.cal

    static let firstFrom = "1970-01-01"
    /// Nuovo obiettivo dal 12 ottobre 2026: lun–ven 3h30, sab 4h, dom 1h30 (23h a settimana).
    static let oct12 = GoalPeriod(from: "2026-10-12", perDay: [12600, 12600, 12600, 12600, 12600, 14400, 5400], weekly: nil)

    init() {
        if let p = env["STUDYTIMER_GOALS"] { url = URL(fileURLWithPath: p) }
        else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StudyTimer")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            url = dir.appendingPathComponent("goals.json")
        }
        if FileManager.default.fileExists(atPath: url.path) {
            if let d = try? Data(contentsOf: url), let m = try? JSONDecoder().decode([GoalPeriod].self, from: d),
               !m.isEmpty, m.allSatisfy({ $0.perDay.count == 7 }) {
                periods = m.sorted { $0.from < $1.from }
            } else {
                // File presente ma illeggibile: non lo si riscrive mai. Si usa in memoria 3h al giorno.
                log("goals.json illeggibile: non lo modifico, uso 3h/giorno")
                periods = [GoalPeriod(from: Self.firstFrom, perDay: Array(repeating: 10800, count: 7), weekly: 72000)]
            }
        } else {
            migrate()
        }
    }

    /// Migrazione idempotente: gira SOLO se goals.json non esiste. Il primo periodo riproduce l'obiettivo di prima
    /// (preferenze dailyGoal/weeklyGoal, default 3h e 20h), il secondo e' il nuovo obiettivo dal 12 ottobre 2026.
    private func migrate() {
        let d = defaults.double(forKey: "dailyGoal"), w = defaults.integer(forKey: "weeklyGoal")
        let daily = Int((d > 0 ? d : 3) * 3600), weekly = (w > 0 ? w : 20) * 3600
        periods = [GoalPeriod(from: Self.firstFrom, perDay: Array(repeating: daily, count: 7), weekly: weekly), Self.oct12]
        do { try write(); log("goals.json creato (migrazione)") } catch { log("goals.json: \(error)") }
    }

    private func write() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(periods).write(to: url, options: .atomic)
    }

    // MARK: Lettura

    func key(_ d: Date) -> String { StudyStore.shared.key(d) }
    func period(onKey k: String) -> GoalPeriod { periods.last(where: { $0.from <= k }) ?? periods[0] }
    func period(on d: Date) -> GoalPeriod { period(onKey: key(d)) }
    func weekdayIndex(_ d: Date) -> Int { (cal.component(.weekday, from: d) + 5) % 7 }       // lun = 0 … dom = 6
    func weekStart(of d: Date) -> Date { cal.dateInterval(of: .weekOfYear, for: d)?.start ?? cal.startOfDay(for: d) }

    /// Obiettivo (secondi) valido in quel giorno.
    func goal(on d: Date) -> Int { period(on: d).perDay[weekdayIndex(d)] }

    /// Gli obiettivi dei 7 giorni (lun→dom) della settimana che contiene `d`, ognuno con il suo periodo.
    func weekGoals(of d: Date) -> [Int] {
        let s = weekStart(of: d)
        return (0..<7).map { goal(on: cal.date(byAdding: .day, value: $0, to: s)!) }
    }

    /// Obiettivo settimanale della settimana che contiene `d`: se tutti i giorni stanno nello stesso periodo vale il suo
    /// `weekly` (o la somma), altrimenti la somma degli obiettivi dei singoli giorni.
    func weeklyGoal(of d: Date) -> Int {
        let s = weekStart(of: d)
        let ps = (0..<7).map { period(on: cal.date(byAdding: .day, value: $0, to: s)!) }
        if let p = ps.first, ps.allSatisfy({ $0.from == p.from }) { return p.weekly ?? p.perDay.reduce(0, +) }
        return weekGoals(of: d).reduce(0, +)
    }

    // MARK: Scrittura (sempre e solo aggiungendo)

    /// Aggiunge un nuovo periodo. Non modifica ne' cancella nulla: se `from` esiste gia' restituisce `.exists`
    /// senza scrivere (serve la conferma dell'utente e `replace`); se e' nel passato restituisce `.inPast`.
    func add(from: String, perDay: [Int]) -> GoalAddResult {
        guard perDay.count == 7, perDay.allSatisfy({ $0 > 0 }), from.count == 10 else { return .invalid }
        if from < key(today()) { return .inPast }                  // i giorni passati restano come sono
        if periods.contains(where: { $0.from == from }) { return .exists }
        let previous = periods
        periods.append(GoalPeriod(from: from, perDay: perDay, weekly: nil))
        periods.sort { $0.from < $1.from }
        do { try write() } catch { periods = previous; log("goals.json: \(error)"); return .invalid }
        return .added
    }

    /// Sostituisce il periodo con lo stesso `from`, SOLO dopo conferma esplicita. Prima salva una copia del file.
    @discardableResult
    func replace(from: String, perDay: [Int]) -> Bool {
        guard perDay.count == 7, perDay.allSatisfy({ $0 > 0 }), from >= key(today()),
              let i = periods.firstIndex(where: { $0.from == from }) else { return false }
        let stamp = { () -> String in let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: Date()) }()
        let backup = url.deletingLastPathComponent().appendingPathComponent("goals-backup-\(stamp).json")
        try? FileManager.default.copyItem(at: url, to: backup)
        let previous = periods
        periods[i] = GoalPeriod(from: from, perDay: perDay, weekly: nil)
        do { try write() } catch { periods = previous; log("goals.json: \(error)"); return false }
        return true
    }

    // MARK: Testo

    static let dayNames = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]
    static let months = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]

    /// 12600 → "3h30", 10800 → "3h", 2700 → "45m".
    static func fmt(_ s: Int) -> String {
        let h = s / 3600, m = s % 3600 / 60
        if h > 0 && m > 0 { return "\(h)h" + String(format: "%02d", m) }
        return h > 0 ? "\(h)h" : "\(m)m"
    }

    /// "Lun–Ven 3h30 · Sab 4h · Dom 1h30" (giorni consecutivi uguali raggruppati).
    static func summary(_ p: GoalPeriod) -> String {
        var parts: [String] = [], i = 0
        while i < 7 {
            var j = i
            while j + 1 < 7 && p.perDay[j + 1] == p.perDay[i] { j += 1 }
            parts.append((i == j ? dayNames[i] : "\(dayNames[i])–\(dayNames[j])") + " " + fmt(p.perDay[i]))
            i = j + 1
        }
        return parts.joined(separator: " · ")
    }

    /// "2026-10-12" → "12 ott".
    static func shortDate(_ key: String) -> String {
        let p = key.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? "\(p[2]) \(months[max(0, min(11, p[1] - 1))])" : key
    }
}
