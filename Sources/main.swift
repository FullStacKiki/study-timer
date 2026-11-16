import Cocoa
import WebKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = AppDelegate()

    var panel: TimerPanel!
    var web: TimerWebView!
    var statusItem: NSStatusItem!
    var loaded = false
    var pending: [String] = []
    var isShown = false
    var dragStart: (mouse: NSPoint, origin: NSPoint)?
    var resizeStart: (mouse: NSPoint, scale: CGFloat, corner: String, fixed: NSPoint)?

    /// Scala corrente: la finestra e la pagina (--s) crescono insieme.
    var scale: CGFloat {
        get { let v = defaults.object(forKey: "scale") as? Double ?? 1; return min(max(CGFloat(v), scaleRange.lowerBound), scaleRange.upperBound) }
        set { defaults.set(Double(min(max(newValue, scaleRange.lowerBound), scaleRange.upperBound)), forKey: "scale") }
    }
    var cardSize: NSSize { NSSize(width: baseCard.width * scale, height: baseCard.height * scale) }
    var stagePad: CGFloat { basePad * scale }
    var panelSize: NSSize { NSSize(width: cardSize.width + stagePad * 2, height: cardSize.height + stagePad * 2) }

    func applicationDidFinishLaunching(_ note: Notification) {
        // Una sola copia: se e' gia' in esecuzione (es. login item + avvio manuale) questa esce subito.
        if env["STUDYTIMER_SUITE"] == nil, let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != getpid() }) {
            log("gia' in esecuzione: esco")
            exit(0)
        }
        NSApp.setActivationPolicy(.accessory)     // niente Dock, niente menu app
        if env["STUDYTIMER_APPEARANCE"] == "light" { NSApp.appearance = NSAppearance(named: .aqua) }   // solo test
        buildPanel()
        buildStatusItem()
        registerHotKey()
        WidgetManager.shared.restore()
        if env["STUDYTIMER_SHOW_EDITOR"] != nil { GoalEditor.shared.show() }          // solo test
        log("avviata")
        show()
    }

    func applicationWillTerminate(_ note: Notification) { StudyStore.shared.flush() }

    /// Mostra il popup (senza nasconderlo se e' gia' aperto): usato dai widget.
    func showTimer() { if !isShown { show() } }

    // MARK: Pannello

    func buildPanel() {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "native")
        cfg.mediaTypesRequiringUserActionForPlayback = []      // il suono di fine deve partire anche senza click
        web = TimerWebView(frame: NSRect(origin: .zero, size: panelSize), configuration: cfg)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = self
        web.autoresizingMask = [.width, .height]
        web.onPointer = { [weak self] p in
            if let p = p { self?.js("setPointer(\(p.x),\(p.y))") } else { self?.js("setPointer(null,null)") }
        }

        panel = TimerPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.contentView = web
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                  // l'ombra la disegna il CSS
        panel.level = .screenSaver               // sopra tutto, anche app a schermo intero
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        // Presente su ogni Space e sopra le app a schermo intero: segue sempre il desktop attivo.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true

        guard let html = Bundle.main.url(forResource: "timer", withExtension: "html") else {
            fatalError("timer.html mancante nel bundle")
        }
        // Solo per i test: STUDYTIMER_QUERY="state=running&rem=1122" forza uno stato iniziale.
        var pageURL = html
        if let q = ProcessInfo.processInfo.environment["STUDYTIMER_QUERY"],
           let u = URL(string: html.absoluteString + "?" + q) { pageURL = u }
        web.loadFileURL(pageURL, allowingReadAccessTo: html.deletingLastPathComponent())
        installDebugSignals()
        // Sempre "ordinato in primo piano" ma trasparente: cosi' WebKit non sospende i timer
        // e il suono di fine arriva anche a timer nascosto.
        panel.orderFrontRegardless()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        js("setScale(\(scale))")
        pending.forEach { webView.evaluateJavaScript($0) }
        pending.removeAll()
    }

    func js(_ code: String) {
        if loaded { web.evaluateJavaScript(code) } else { pending.append(code) }
    }

    // MARK: Posizione

    /// Schermo del desktop "attivo": quello dove sta il mouse.
    func activeScreen() -> NSScreen {
        let m = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Scostamenti della card dall'angolo in basso a destra dell'area visibile.
    var offsets: (dx: CGFloat, dy: CGFloat) {
        get {
            let dx = defaults.object(forKey: "dx") as? Double ?? Double(screenInset)
            let dy = defaults.object(forKey: "dy") as? Double ?? Double(screenInset)
            return (CGFloat(dx), CGFloat(dy))
        }
        set { defaults.set(Double(newValue.dx), forKey: "dx"); defaults.set(Double(newValue.dy), forKey: "dy") }
    }

    func place(on screen: NSScreen) {
        let vf = screen.visibleFrame
        var (dx, dy) = offsets
        dx = min(max(dx, 0), vf.width - cardSize.width)
        dy = min(max(dy, 0), vf.height - cardSize.height)
        let origin = NSPoint(x: vf.maxX - dx - cardSize.width - stagePad,
                             y: vf.minY + dy - stagePad)
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: false)
    }

    func savePosition() {
        let f = panel.frame
        let screen = panel.screen ?? activeScreen()
        let vf = screen.visibleFrame
        offsets = (vf.maxX - (f.maxX - stagePad), (f.minY + stagePad) - vf.minY)
    }

    // MARK: Mostra / nascondi

    @objc func toggle() { isShown ? hide() : show() }

    func show() {
        isShown = true
        place(on: activeScreen())
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        js("nativeOpen()")
    }

    func hide() {
        isShown = false
        js("nativeClose()")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self = self, !self.isShown else { return }
            self.panel.alphaValue = 0
            self.panel.ignoresMouseEvents = true
        }
    }

    // MARK: Messaggi dalla pagina

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "study":            // secondi studiati (il timer li invia mentre conta)
            if let n = body["seconds"] as? Int { StudyStore.shared.add(seconds: n); WidgetManager.shared.refresh() }
        case "status":
            StudyStore.shared.running = (body["status"] as? String) == "running"
            if StudyStore.shared.running == false { StudyStore.shared.flush() }
            WidgetManager.shared.refresh()
        case "dragStart":
            dragStart = (NSEvent.mouseLocation, panel.frame.origin)
        case "dragMove":
            guard let s = dragStart else { return }
            let m = NSEvent.mouseLocation
            panel.setFrameOrigin(NSPoint(x: s.origin.x + m.x - s.mouse.x, y: s.origin.y + m.y - s.mouse.y))
        case "resizeStart":
            let corner = body["corner"] as? String ?? "br"
            let f = panel.frame, pad = stagePad
            // punto fisso = angolo opposto della card (senza il margine trasparente)
            let fixed = corner == "tl" ? NSPoint(x: f.maxX - pad, y: f.minY + pad) : NSPoint(x: f.minX + pad, y: f.maxY - pad)
            resizeStart = (NSEvent.mouseLocation, scale, corner, fixed)
        case "resizeMove":
            guard let r = resizeStart else { return }
            let m = NSEvent.mouseLocation
            let dx = m.x - r.mouse.x, dy = m.y - r.mouse.y
            let w = baseCard.width * r.scale, h = baseCard.height * r.scale
            let v = r.corner == "tl" ? ((w - dx) / baseCard.width + (h + dy) / baseCard.height) / 2
                                     : ((w + dx) / baseCard.width + (h - dy) / baseCard.height) / 2
            applyScale(v, corner: r.corner, fixed: r.fixed)
        case "resizeEnd":
            if resizeStart != nil { resizeStart = nil; savePosition() }
        case "resizeReset":
            let f = panel.frame, pad = stagePad
            applyScale(1, corner: "tl", fixed: NSPoint(x: f.maxX - pad, y: f.minY + pad)); savePosition()
        case "dragEnd":
            if dragStart != nil { dragStart = nil; savePosition() }
        default: break
        }
    }

    // MARK: Dimensione

    /// Cambia scala tenendo fermo un angolo della card ("tl" = la maniglia e' in alto a sinistra, quindi
    /// resta fermo l'angolo in basso a destra; "br" = resta fermo quello in alto a sinistra).
    /// La dimensione e' limitata allo spazio che c'e' sullo schermo.
    func applyScale(_ v: CGFloat, corner: String, fixed: NSPoint) {
        let vf = (panel.screen ?? activeScreen()).visibleFrame
        var maxScale = scaleRange.upperBound
        if corner == "tl" { maxScale = min((fixed.x - vf.minX) / baseCard.width, (vf.maxY - fixed.y) / baseCard.height) }
        else              { maxScale = min((vf.maxX - fixed.x) / baseCard.width, (fixed.y - vf.minY) / baseCard.height) }
        scale = min(v, max(maxScale, scaleRange.lowerBound))
        let card = cardSize, pad = stagePad
        let origin = corner == "tl" ? NSPoint(x: fixed.x - card.width - pad, y: fixed.y - pad)
                                    : NSPoint(x: fixed.x - pad, y: fixed.y - card.height - pad)
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
        js("setScale(\(scale))")
    }
    /// Zoom da menu: resta fermo l'angolo in basso a destra.
    func zoom(_ factor: CGFloat?) {
        let f = panel.frame, pad = stagePad
        applyScale(factor.map { scale * $0 } ?? 1, corner: "tl", fixed: NSPoint(x: f.maxX - pad, y: f.minY + pad))
        savePosition()
    }
    @objc func zoomIn() { zoom(1.15) }
    @objc func zoomOut() { zoom(1 / 1.15) }
    @objc func zoomReset() { zoom(nil) }

    // MARK: Icona nella barra dei menu

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            let img = NSImage(systemSymbolName: "timer", accessibilityDescription: "Study Timer")
            img?.isTemplate = true
            b.image = img
        }
        let menu = NSMenu()
        menu.delegate = self               // il contenuto si ricostruisce a ogni apertura (spunte, widget presenti)
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func item(_ title: String, _ sel: Selector, _ key: String = "") -> NSMenuItem {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: key); i.target = self; return i
        }
        let t = item("Mostra / nascondi timer", #selector(toggle))
        t.attributedTitle = NSAttributedString(string: "Mostra / nascondi timer    ⇧⌘T")
        menu.addItem(t)
        menu.addItem(.separator())
        WidgetManager.shared.addMenuItems().forEach { menu.addItem($0) }
        menu.addItem(.separator())
        GoalMenu.items().forEach { menu.addItem($0) }
        menu.addItem(.separator())
        menu.addItem(item("Ingrandisci timer", #selector(zoomIn), "+"))
        menu.addItem(item("Rimpicciolisci timer", #selector(zoomOut), "-"))
        menu.addItem(item("Dimensione originale", #selector(zoomReset), "0"))
        menu.addItem(item("Ripristina posizione timer", #selector(resetPosition)))
        menu.addItem(.separator())
        let l = item("Apri al login", #selector(toggleLogin(_:)))
        l.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(l)
        menu.addItem(.separator())
        menu.addItem(item("Esci", #selector(quit), "q"))
    }

    @objc func resetPosition() {
        defaults.removeObject(forKey: "dx"); defaults.removeObject(forKey: "dy")
        if isShown { place(on: activeScreen()) }
    }
    @objc func toggleLogin(_ item: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { log("login item: \(error)") }
        item.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    @objc func quit() { NSApp.terminate(nil) }

    // MARK: Strumenti di prova
    // `pkill -USR1 StudyTimer` = stessa azione di ⇧⌘T.
    // Con STUDYTIMER_SNAPSHOT=/percorso.png, `pkill -USR2 StudyTimer` salva un PNG della pagina.
    var signalSources: [DispatchSourceSignal] = []
    func installDebugSignals() {
        for (sig, action) in [(SIGUSR1, { AppDelegate.shared.toggle() }), (SIGUSR2, { AppDelegate.shared.snapshot() })] as [(Int32, () -> Void)] {
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            s.setEventHandler(handler: action)
            s.resume()
            signalSources.append(s)
        }
    }
    func snapshot() {
        if let dir = ProcessInfo.processInfo.environment["STUDYTIMER_SNAPSHOT_WIDGETS"] {
            for w in WidgetManager.shared.widgets {
                w.web.takeSnapshot(with: nil) { image, _ in
                    guard let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:]) else { return }
                    try? png.write(to: URL(fileURLWithPath: "\(dir)/\(w.size)-\(w.id.prefix(4)).png"))
                }
            }
        }
        if let p = env["STUDYTIMER_EDITOR_SNAPSHOT"] { GoalEditor.shared.snapshot(to: p) }
        guard let path = ProcessInfo.processInfo.environment["STUDYTIMER_SNAPSHOT"] else { return }
        if ProcessInfo.processInfo.environment["STUDYTIMER_WINDOWSHOT"] != nil {
            // Diagnostica: la pagina sta davvero disegnando? (rAF parte solo se WebKit la considera visibile)
            let probe = "return await new Promise(r => { let n = 0; const t = performance.now(); (function f() { n++; if (performance.now() - t > 500) r(document.visibilityState + ' rAF=' + n + ' opacity=' + getComputedStyle(document.getElementById('card')).opacity + ' status=' + document.getElementById('card').dataset.status + ' elapsed=' + S.elapsed); else requestAnimationFrame(f); })(); })"
            web.callAsyncJavaScript(probe, in: nil, in: .page) { r in
                let out = "\(r)"
                try? out.write(toFile: path, atomically: true, encoding: .utf8)
            }
            return
        }
        web.takeSnapshot(with: nil) { image, _ in
            guard let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: Scorciatoia globale ⇧⌘T

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { log("scorciatoia ⇧⌘T premuta"); AppDelegate.shared.toggle() }
            return noErr
        }, 1, &spec, nil, nil)

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5354_4D52), id: 1)   // 'STMR'
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(cmdKey | shiftKey), id,
                                         GetApplicationEventTarget(), 0, &ref)
        log("registrazione ⇧⌘T: status \(status)")
        if status != noErr {
            let a = NSAlert()
            a.messageText = "Impossibile registrare ⇧⌘T"
            a.informativeText = "Un'altra app sta già usando questa scorciatoia (errore \(status)). Chiudila e riavvia Study Timer."
            a.runModal()
        }
    }
}

let app = NSApplication.shared
app.delegate = AppDelegate.shared
app.run()
