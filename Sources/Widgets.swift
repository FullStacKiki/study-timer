import Cocoa
import WebKit

// Widget da scrivania: finestre senza bordi al livello della scrivania (sopra lo sfondo e le icone, sotto le
// finestre normali), presenti su ogni Space. Mostrano i dati di StudyStore, alimentato dal popup.

let widgetPad: CGFloat = 32       // margine trasparente per l'ombra (--pad in widget.html)
let widgetSizes: [String: NSSize] = [
    "small": NSSize(width: 170, height: 170),
    "medium": NSSize(width: 364, height: 170),
    "large": NSSize(width: 364, height: 382),
    // Study Grid (stesso timer, griglia stile contributi)
    "grid-small": NSSize(width: 184, height: 184),
    "grid-medium": NSSize(width: 480, height: 170),
    "grid-large": NSSize(width: 804, height: 256),
    // Obiettivo giornaliero a cerchio
    "ring-small": NSSize(width: 170, height: 170),
    "ring-medium": NSSize(width: 364, height: 170),
]
let widgetNames = ["small": "Small", "medium": "Medium", "large": "Large",
                   "grid-small": "Grid Small", "grid-medium": "Grid Medium", "grid-large": "Grid Large",
                   "ring-small": "Obiettivo Small", "ring-medium": "Obiettivo Medium"]

final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class WidgetController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let id: String
    let size: String
    let panel: WidgetPanel
    let web: TimerWebView
    weak var manager: WidgetManager?
    private var loaded = false
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    init(id: String, size: String, origin: NSPoint, manager: WidgetManager) {
        self.id = id; self.size = size; self.manager = manager
        let card = widgetSizes[size] ?? widgetSizes["medium"]!
        let win = NSSize(width: card.width + widgetPad * 2, height: card.height + widgetPad * 2)

        let cfg = WKWebViewConfiguration()
        web = TimerWebView(frame: NSRect(origin: .zero, size: win), configuration: cfg)
        web.setValue(false, forKey: "drawsBackground")

        panel = WidgetPanel(contentRect: NSRect(origin: origin, size: win),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()

        cfg.userContentController.add(self, name: "native")
        web.navigationDelegate = self
        web.onPointer = { [weak self] p in
            if let p = p { self?.web.evaluateJavaScript("setPointer(\(p.x),\(p.y))") } else { self?.web.evaluateJavaScript("setPointer(null,null)") }
        }
        web.contextMenu = { [weak self] _ in self.flatMap { $0.manager?.contextMenu(for: $0) } }

        panel.contentView = web
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Livello della scrivania: sopra sfondo e icone, sotto tutte le finestre. Su ogni Space.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true

        // "grid-medium" → pagina grid.html?size=medium, "ring-small" → ring.html?size=small, "medium" → widget.html
        let parts = size.split(separator: "-").map(String.init)
        let page = parts.count == 2 ? parts[0] : "widget"
        let variant = parts.count == 2 ? parts[1] : size
        if let html = Bundle.main.url(forResource: page, withExtension: "html"),
           let url = URL(string: html.absoluteString + "?size=\(variant)") {
            web.loadFileURL(url, allowingReadAccessTo: html.deletingLastPathComponent())
        }
        panel.orderFrontRegardless()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true; push() }

    func push() {
        guard loaded else { return }
        let data = size.hasPrefix("grid-") ? StudyStore.shared.gridPayload() : StudyStore.shared.payload()
        web.evaluateJavaScript("update(\(data))")
    }

    func close() {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "native")
        panel.orderOut(nil)
    }

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "click":
            AppDelegate.shared.showTimer()          // click sul widget = apri il popup
        case "dragStart":
            dragStart = (NSEvent.mouseLocation, panel.frame.origin)
        case "dragMove":
            guard let s = dragStart else { return }
            let m = NSEvent.mouseLocation
            panel.setFrameOrigin(NSPoint(x: s.origin.x + m.x - s.mouse.x, y: s.origin.y + m.y - s.mouse.y))
        case "dragEnd":
            dragStart = nil
            manager?.save()
        default: break
        }
        if type == "click" { dragStart = nil }
    }
}

final class WidgetManager: NSObject {
    static let shared = WidgetManager()
    private(set) var widgets: [WidgetController] = []

    // MARK: Ciclo di vita

    /// Ripristina i widget salvati; al primo avvio ne crea uno Medium.
    func restore() {
        startAutoRefresh()
        if let saved = defaults.array(forKey: "widgets") as? [[String: Any]] {
            for w in saved {
                guard let id = w["id"] as? String, let size = w["size"] as? String, widgetSizes[size] != nil,
                      let x = w["x"] as? Double, let y = w["y"] as? Double else { continue }
                widgets.append(WidgetController(id: id, size: size, origin: visibleOrigin(NSPoint(x: x, y: y), size: size), manager: self))
            }
        } else {
            add("medium")
        }
    }

    func add(_ size: String) {
        guard widgetSizes[size] != nil else { return }
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let card = widgetSizes[size]!
        // In alto a sinistra, a cascata sotto ai widget gia' presenti.
        var y = vf.maxY - 20 - card.height - widgetPad
        for w in widgets { y = min(y, w.panel.frame.minY - 16 - card.height) }
        if y < vf.minY { y = vf.maxY - 20 - card.height - widgetPad }
        widgets.append(WidgetController(id: UUID().uuidString, size: size,
                                        origin: NSPoint(x: vf.minX + 20 - widgetPad, y: y), manager: self))
        save()
    }

    func remove(_ w: WidgetController) {
        w.close()
        widgets.removeAll { $0 === w }
        save()
    }

    func removeAll() {
        widgets.forEach { $0.close() }
        widgets.removeAll()
        save()
    }

    func save() {
        defaults.set(widgets.map { ["id": $0.id, "size": $0.size, "x": Double($0.panel.frame.minX), "y": Double($0.panel.frame.minY)] as [String: Any] },
                     forKey: "widgets")
    }

    func refresh() { widgets.forEach { $0.push() } }

    /// I widget vengono rinfrescati solo quando il timer invia dati: senza questo, a mezzanotte (o dopo uno stop del Mac)
    /// resterebbero sul giorno e sull'obiettivo di ieri. Ogni minuto e al risveglio.
    func startAutoRefresh() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    /// Se la posizione salvata non e' piu' su nessuno schermo (monitor scollegato) riporta il widget sul principale.
    private func visibleOrigin(_ o: NSPoint, size: String) -> NSPoint {
        let card = widgetSizes[size]!
        let rect = NSRect(x: o.x + widgetPad, y: o.y + widgetPad, width: card.width, height: card.height)
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) { return o }
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSPoint(x: vf.minX + 20 - widgetPad, y: vf.maxY - 20 - card.height - widgetPad)
    }

    // MARK: Menu

    func addMenuItems() -> [NSMenuItem] {
        let sub = NSMenu()
        for group in [["small", "medium", "large"], ["grid-small", "grid-medium", "grid-large"], ["ring-small", "ring-medium"]] {
            for s in group {
                let it = NSMenuItem(title: "Aggiungi \(widgetNames[s]!)", action: #selector(addFromMenu(_:)), keyEquivalent: "")
                it.target = self; it.representedObject = s
                sub.addItem(it)
            }
            sub.addItem(.separator())
        }
        let rm = NSMenuItem(title: "Rimuovi tutti", action: #selector(removeAllFromMenu), keyEquivalent: "")
        rm.target = self; rm.isEnabled = !widgets.isEmpty
        sub.addItem(rm)
        let root = NSMenuItem(title: "Widget", action: nil, keyEquivalent: "")
        root.submenu = sub
        return [root]
    }

    func contextMenu(for w: WidgetController) -> NSMenu {
        let m = NSMenu()
        let open = NSMenuItem(title: "Apri timer", action: #selector(openTimer), keyEquivalent: "")
        open.target = self
        m.addItem(open)
        m.addItem(.separator())
        GoalMenu.items().forEach { m.addItem($0) }
        m.addItem(.separator())
        let rm = NSMenuItem(title: "Rimuovi widget", action: #selector(removeOne(_:)), keyEquivalent: "")
        rm.target = self; rm.representedObject = w
        m.addItem(rm)
        return m
    }


    @objc private func addFromMenu(_ i: NSMenuItem) { if let s = i.representedObject as? String { add(s) } }
    @objc private func removeAllFromMenu() { removeAll() }
    @objc private func removeOne(_ i: NSMenuItem) { if let w = i.representedObject as? WidgetController { remove(w) } }
    @objc private func openTimer() { AppDelegate.shared.showTimer() }
}
