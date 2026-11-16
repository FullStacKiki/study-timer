import Cocoa
import WebKit

// MARK: - Ambiente / preferenze
// Le variabili STUDYTIMER_* servono solo ai test: non toccano i dati veri.

let env = ProcessInfo.processInfo.environment
let defaults: UserDefaults = env["STUDYTIMER_SUITE"].flatMap { UserDefaults(suiteName: $0) } ?? .standard


// MARK: - Log (~/Library/Logs/StudyTimer.log)

func log(_ msg: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/StudyTimer.log")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

// MARK: - Costanti di layout (devono combaciare con timer.html)

let baseCard = NSSize(width: 660, height: 150)     // dimensione naturale (scala 1)
let basePad: CGFloat = 44                          // margine trasparente attorno alla card, per l'ombra
let screenInset: CGFloat = 16                      // --screen-inset
let scaleRange: ClosedRange<CGFloat> = 0.6...2.2

// MARK: - Finestra: pannello che non ruba il focus

final class TimerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class TimerWebView: WKWebView {
    var onPointer: ((NSPoint?) -> Void)?
    var contextMenu: ((NSEvent) -> NSMenu?)?      // menu del tasto destro (widget); nil = comportamento standard

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // La finestra non e' mai key: senza .activeAlways non arriverebbe nessun hover.
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        var p = convert(event.locationInWindow, from: nil)
        if !isFlipped { p.y = bounds.height - p.y }
        onPointer?(p)
    }
    override func rightMouseDown(with event: NSEvent) {
        if let m = contextMenu?(event) { NSMenu.popUpContextMenu(m, with: event, for: self) } else { super.rightMouseDown(with: event) }
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointer?(nil)
    }
}


// MARK: - Dati di studio (condivisi tra popup e widget)

/// Secondi studiati per giorno ("yyyy-MM-dd" → secondi), salvati in
/// ~/Library/Application Support/StudyTimer/sessions.json. Il popup li alimenta, i widget li leggono.
final class StudyStore {
    static let shared = StudyStore()

    private(set) var days: [String: Int] = [:]
    var running = false
    private var dirty = false
    private let url: URL
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.firstWeekday = 2; return c }()   // settimana da lunedi'
    private lazy var keyFormat: DateFormatter = {
        let f = DateFormatter(); f.calendar = cal; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    init() {
        if let p = env["STUDYTIMER_DATA"] { url = URL(fileURLWithPath: p) }
        else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StudyTimer")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            url = dir.appendingPathComponent("sessions.json")
        }
        if let d = try? Data(contentsOf: url), let m = try? JSONDecoder().decode([String: Int].self, from: d) { days = m }
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.flush() }
    }

    func key(_ d: Date) -> String { keyFormat.string(from: d) }

    func add(seconds: Int, at date: Date = Date()) {
        guard seconds > 0 else { return }
        days[key(date), default: 0] += seconds
        dirty = true
    }

    func flush() {
        guard dirty, let data = try? JSONEncoder().encode(days) else { return }
        do { try data.write(to: url, options: .atomic); dirty = false } catch { log("salvataggio dati: \(error)") }
    }

    /// JSON per la Study Grid: tutti i giorni studiati ("yyyy-MM-dd" → secondi) e se il timer e' in corso.
    func gridPayload() -> String {
        let now = today()
        let obj: [String: Any] = ["days": days, "running": running, "today": key(now),
                                  "weeklyGoal": GoalStore.shared.weeklyGoal(of: now)]
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// JSON per i widget: ore di oggi, settimana lun→dom, obiettivi, media e serie di giorni.
    func payload() -> String {
        let now = today()
        let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        let week: [Int] = (0..<7).map { days[key(cal.date(byAdding: .day, value: $0, to: start)!)] ?? 0 }
        let idx = min(max(cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: now)).day ?? 0, 0), 6)
        let total = week.reduce(0, +)
        let goals = GoalStore.shared

        var streak = 0
        var d = cal.startOfDay(for: now)
        if (days[key(d)] ?? 0) < 60 { d = cal.date(byAdding: .day, value: -1, to: d)! }   // oggi non ancora iniziato: non spezza la serie
        while (days[key(d)] ?? 0) >= 60 && streak < 3650 { streak += 1; d = cal.date(byAdding: .day, value: -1, to: d)! }

        let obj: [String: Any] = [
            "today": week[idx], "week": week, "todayIdx": idx, "weekTotal": total,
            "avg": total / (idx + 1), "streak": streak,
            // obiettivo di oggi, dei 7 giorni della settimana (a gradini) e della settimana, dalla cronologia obiettivi
            "dailyGoal": goals.goal(on: now), "weekGoals": goals.weekGoals(of: now), "weeklyGoal": goals.weeklyGoal(of: now),
            "running": running,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
