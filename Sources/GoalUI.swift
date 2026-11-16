import Cocoa

// Voci di menu e finestrella per gli obiettivi. Il salvataggio AGGIUNGE sempre un nuovo periodo a goals.json
// (vedi GoalStore): mai modificare o cancellare quelli esistenti, se non dopo conferma esplicita sulla stessa data.

final class GoalActions: NSObject {
    static let shared = GoalActions()
    @objc func edit() { GoalEditor.shared.show() }
    @objc func reveal() { NSWorkspace.shared.activateFileViewerSelecting([GoalStore.shared.url]) }
}

enum GoalMenu {
    /// Righe informative (obiettivo in vigore e periodi futuri), "Modifica obiettivi…" e "Mostra file obiettivi".
    static func items() -> [NSMenuItem] {
        let store = GoalStore.shared, k = store.key(today())
        var out: [NSMenuItem] = []
        func info(_ t: String) {
            let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
            i.isEnabled = false
            out.append(i)
        }
        info("Obiettivo: " + GoalStore.summary(store.period(onKey: k)))
        for p in store.periods where p.from > k { info("Dal \(GoalStore.shortDate(p.from)): " + GoalStore.summary(p)) }
        let edit = NSMenuItem(title: "Modifica obiettivi…", action: #selector(GoalActions.edit), keyEquivalent: "")
        edit.target = GoalActions.shared
        let reveal = NSMenuItem(title: "Mostra file obiettivi", action: #selector(GoalActions.reveal), keyEquivalent: "")
        reveal.target = GoalActions.shared
        out.append(contentsOf: [edit, reveal])
        return out
    }
}

final class GoalEditor: NSObject, NSWindowDelegate {
    static let shared = GoalEditor()
    private var window: NSWindow?
    private var steppers: [NSStepper] = []
    private var valueLabels: [NSTextField] = []
    private var totalLabel = NSTextField(labelWithString: "")
    private var picker = NSDatePicker()

    private static let names = ["Lunedì", "Martedì", "Mercoledì", "Giovedì", "Venerdì", "Sabato", "Domenica"]

    func show() {
        if let w = window { NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); return }
        build()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Lunedi' successivo a oggi (se oggi e' lunedi', quello dopo).
    private func nextMonday() -> Date {
        let cal = StudyStore.shared.cal
        let t = cal.startOfDay(for: today())
        let idx = GoalStore.shared.weekdayIndex(t)
        return cal.date(byAdding: .day, value: 7 - idx, to: t)!
    }

    private func build() {
        let store = GoalStore.shared
        // Parte dagli obiettivi dell'ultimo periodo (quello piu' recente), da modificare.
        let base = store.periods.last!.perDay

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 430), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Modifica obiettivi"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.level = .floating

        steppers = []; valueLabels = []
        let rows = NSStackView()
        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 8
        for i in 0..<7 {
            let name = NSTextField(labelWithString: Self.names[i]); name.font = .systemFont(ofSize: 13)
            name.widthAnchor.constraint(equalToConstant: 96).isActive = true
            let val = NSTextField(labelWithString: ""); val.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            val.alignment = .right; val.widthAnchor.constraint(equalToConstant: 72).isActive = true
            let st = NSStepper(); st.minValue = 15; st.maxValue = 720; st.increment = 15; st.valueWraps = false
            st.integerValue = max(15, base[i] / 60); st.tag = i
            st.target = self; st.action = #selector(changed)
            steppers.append(st); valueLabels.append(val)
            let row = NSStackView(views: [name, val, st]); row.orientation = .horizontal; row.spacing = 10
            rows.addArrangedSubview(row)
        }
        totalLabel.font = .systemFont(ofSize: 12); totalLabel.textColor = .secondaryLabelColor

        let from = NSTextField(labelWithString: "Valido da"); from.font = .systemFont(ofSize: 13)
        picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .yearMonthDay
        picker.locale = Locale(identifier: "it_IT")
        picker.calendar = StudyStore.shared.cal
        picker.minDate = StudyStore.shared.cal.startOfDay(for: today())
        picker.dateValue = nextMonday()
        let fromRow = NSStackView(views: [from, picker]); fromRow.orientation = .horizontal; fromRow.spacing = 12

        let note = NSTextField(wrappingLabelWithString: "Il salvataggio aggiunge un nuovo periodo: le ore registrate e i giorni passati non cambiano.")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 320

        let cancel = NSButton(title: "Annulla", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Salva", target: self, action: #selector(save))
        save.keyEquivalent = "\r"; save.bezelStyle = .rounded
        let buttons = NSStackView(views: [cancel, save]); buttons.orientation = .horizontal; buttons.spacing = 10

        let main = NSStackView(views: [rows, totalLabel, fromRow, note, buttons])
        main.orientation = .vertical; main.alignment = .leading; main.spacing = 14
        main.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        main.setCustomSpacing(6, after: rows)
        main.setCustomSpacing(18, after: totalLabel)
        buttons.setContentHuggingPriority(.required, for: .horizontal)
        w.contentView = main
        w.setContentSize(main.fittingSize)
        w.center()
        window = w
        changed()
    }

    private func fmt(_ min: Int) -> String { min % 60 == 0 ? "\(min / 60)h" : (min >= 60 ? "\(min / 60)h \(String(format: "%02d", min % 60))m" : "\(min)m") }

    @objc private func changed() {
        for (i, st) in steppers.enumerated() { valueLabels[i].stringValue = fmt(st.integerValue) }
        totalLabel.stringValue = "Totale settimana: " + fmt(steppers.reduce(0) { $0 + $1.integerValue })
    }

    @objc private func cancel() { window?.close() }

    @objc private func save() {
        let store = GoalStore.shared
        let perDay = steppers.map { $0.integerValue * 60 }
        let from = store.key(picker.dateValue)

        switch store.add(from: from, perDay: perDay) {
        case .added:
            saved()
        case .exists:
            // Esiste gia' un periodo con questa data: si sostituisce solo se l'utente lo conferma.
            let old = store.periods.first { $0.from == from }!
            let a = NSAlert()
            a.messageText = "Esiste già un periodo dal \(GoalStore.shortDate(from))"
            a.informativeText = "Attuale: \(GoalStore.summary(old))\nNuovo: \(GoalStore.summary(GoalPeriod(from: from, perDay: perDay, weekly: nil)))\n\nSostituirlo? Prima salvo una copia di goals.json."
            a.addButton(withTitle: "Annulla")
            a.addButton(withTitle: "Sostituisci")
            a.alertStyle = .warning
            if a.runModal() == .alertSecondButtonReturn, store.replace(from: from, perDay: perDay) { saved() }
        case .inPast:
            alert("Data nel passato", "I giorni passati restano valutati con l'obiettivo di allora. Scegli oggi o una data futura.")
        case .invalid:
            alert("Obiettivi non validi", "Ogni giorno deve avere almeno 15 minuti.")
        }
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }

    private func saved() {
        WidgetManager.shared.refresh()          // aggiorna subito i widget
        window?.close()
    }

    func windowWillClose(_ notification: Notification) { window = nil }

    // Solo per i test: salva un'immagine della finestra.
    func snapshot(to path: String) {
        guard let v = window?.contentView else { return }
        v.layoutSubtreeIfNeeded()
        try? v.dataWithPDF(inside: v.bounds).write(to: URL(fileURLWithPath: path))        // PDF: rende tutti i controlli
    }
}
