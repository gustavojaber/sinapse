// Sinapse — casca nativa para macOS
// Abre o sinapse.html numa janela própria (WKWebView), guarda os dados numa
// pasta do app, agenda os lembretes no sistema e mostra o número no ícone do Dock.

import Cocoa
import WebKit
import UserNotifications

let fm = FileManager.default
let supportDir: URL = {
    let u = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sinapse", isDirectory: true)
    try? fm.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}()
let dataFile = supportDir.appendingPathComponent("dados.json")
let backupDir: URL = {
    let u = supportDir.appendingPathComponent("Backups", isDirectory: true)
    try? fm.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}()
let customHTML = supportDir.appendingPathComponent("sinapse.html")
/* Registro simples das notificações (para entender quando o macOS não deixa avisar) */
let notifLogFile = supportDir.appendingPathComponent("notificacoes.log")
func notifLog(_ line: String) {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
    let text = "\(f.string(from: Date())) \(line)\n"
    if let h = try? FileHandle(forWritingTo: notifLogFile) { h.seekToEndOfFile(); h.write(text.data(using: .utf8)!); try? h.close() }
    else { try? text.data(using: .utf8)!.write(to: notifLogFile) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, UNUserNotificationCenterDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var pageLoaded = false
    var pendingJS: [String] = []

    // MARK: Início
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Manutenção: apaga lembretes agendados e entregues deste identificador e sai (usado ao trocar o identificador do app)
        if ProcessInfo.processInfo.environment["SINAPSE_LIMPAR_AVISOS"] == "1" {
            let c = UNUserNotificationCenter.current()
            c.removeAllPendingNotificationRequests(); c.removeAllDeliveredNotifications()
            notifLog("avisos do identificador \(Bundle.main.bundleIdentifier ?? "?") apagados")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { NSApp.terminate(nil) }
            return
        }
        buildMenu()

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "sinapse")
        config.websiteDataStore = WKWebsiteDataStore.default()

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 820), configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Sinapse"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        window.minSize = NSSize(width: 420, height: 560)
        window.contentView = webView
        _ = window.setFrameAutosaveName("SinapseJanela")
        if !window.setFrameUsingName("SinapseJanela") { window.center() }
        window.makeKeyAndOrderFront(nil)

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let done = UNNotificationAction(identifier: "DONE", title: "Concluir", options: [])
        let open = UNNotificationAction(identifier: "OPEN", title: "Abrir", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: "TASK", actions: [done, open], intentIdentifiers: [], options: [])])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            notifLog("pedido de permissão: concedida=\(granted) erro=\(error.map { "\($0)" } ?? "nenhum")")
            center.getNotificationSettings { s in
                notifLog("estado: autorização=\(s.authorizationStatus.rawValue) alerta=\(s.alertSetting.rawValue) som=\(s.soundSetting.rawValue)")
            }
        }

        loadApp()
        NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.environment["SINAPSE_TESTE_AVISO"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.testNotification() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }

    // MARK: Carregar a página com os dados salvos
    func loadApp() {
        pageLoaded = false
        let uc = webView.configuration.userContentController
        uc.removeAllUserScripts()
        var boot = "null"
        if let d = try? Data(contentsOf: dataFile), (try? JSONSerialization.jsonObject(with: d)) != nil,
           let s = String(data: d, encoding: .utf8) { boot = s }
        let js = "window.SINAPSE_BOOT = {data: \(boot), nativo: '1.0'};"
        uc.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let url: URL
        if fm.fileExists(atPath: customHTML.path) { url = customHTML }
        else if let u = Bundle.main.url(forResource: "sinapse", withExtension: "html") { url = u }
        else { return }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
        let queued = pendingJS
        pendingJS.removeAll()
        for js in queued { webView.evaluateJavaScript(js, completionHandler: nil) }
    }

    func runJS(_ js: String) {
        DispatchQueue.main.async {
            if self.pageLoaded { self.webView.evaluateJavaScript(js, completionHandler: nil) }
            else { self.pendingJS.append(js) }
        }
    }

    // Links externos abrem no navegador
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, ["http", "https", "mailto"].contains(url.scheme ?? ""),
           navigationAction.navigationType == .linkActivated {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // Escolher arquivos (importar backup, adicionar imagens)
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { result in
            completionHandler(result == .OK ? panel.urls : nil)
        }
    }

    // MARK: Mensagens vindas do Sinapse
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "save":
            if let json = body["json"] as? String { save(json) }
        case "schedule":
            if let items = body["items"] as? [[String: Any]] { schedule(items) }
        case "badge":
            let n = (body["count"] as? NSNumber)?.intValue ?? 0
            NSApp.dockTile.badgeLabel = n > 0 ? String(n) : nil
        case "saveFile":
            if let name = body["name"] as? String, let b64 = body["b64"] as? String, let data = Data(base64Encoded: b64) {
                saveFile(name: name, data: data)
            }
        case "theme":
            // A barra de título acompanha a aparência escolhida no Sinapse
            let dark = body["dark"] as? Bool ?? false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.backgroundColor = dark ? NSColor(srgbRed: 0.133, green: 0.133, blue: 0.145, alpha: 1)
                                          : NSColor(srgbRed: 0.969, green: 0.969, blue: 0.973, alpha: 1)
        case "revealBackups":
            NSWorkspace.shared.activateFileViewerSelecting([backupDir])
        case "notifyNow":
            let title = body["title"] as? String ?? "Sinapse"
            let text = body["body"] as? String ?? ""
            notifyNow(title: title, body: text)
        default:
            break
        }
    }

    // Salva os dados e mantém uma cópia por dia (últimos 60 dias)
    func save(_ json: String) {
        guard let data = json.data(using: .utf8) else { return }
        try? data.write(to: dataFile, options: .atomic)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let daily = backupDir.appendingPathComponent("sinapse-\(f.string(from: Date())).json")
        try? data.write(to: daily, options: .atomic)
        if let files = try? fm.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil) {
            let backups = files.filter { $0.lastPathComponent.hasPrefix("sinapse-") && $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if backups.count > 60 { for old in backups.prefix(backups.count - 60) { try? fm.removeItem(at: old) } }
        }
    }

    func saveFile(name: String, data: Data) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { result in
            if result == .OK, let url = panel.url { try? data.write(to: url, options: .atomic) }
        }
    }

    // MARK: Lembretes no sistema (funcionam com o app fechado)
    func schedule(_ items: [[String: Any]]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let old = pending.map { $0.identifier }.filter { $0.hasPrefix("task-") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            let now = Date()
            notifLog("agendando \(items.filter { (($0["at"] as? NSNumber)?.doubleValue ?? 0)/1000 > now.timeIntervalSince1970 }.count) lembrete(s)")
            for item in items {
                guard let id = item["id"] as? String, let at = (item["at"] as? NSNumber)?.doubleValue else { continue }
                let date = Date(timeIntervalSince1970: at / 1000)
                if date <= now { continue }
                let content = UNMutableNotificationContent()
                content.title = item["title"] as? String ?? "Task"
                content.body = item["body"] as? String ?? ""
                content.sound = .default
                content.categoryIdentifier = "TASK"
                content.userInfo = ["id": id]
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                // Cada aviso tem a sua chave (na hora, 15 min antes, resumo do dia); o id da task vai junto para abrir/concluir
                let key = item["key"] as? String ?? id
                center.add(UNNotificationRequest(identifier: "task-\(key)", content: content, trigger: trigger)) { err in
                    if let err = err { notifLog("falha ao agendar \(id): \(err)") }
                }
            }
        }
    }

    func notifyNow(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: "agora-\(UUID().uuidString)", content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    // Com o app aberto e em primeiro plano, o próprio Sinapse mostra o aviso
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        DispatchQueue.main.async {
            if NSApp.isActive && notification.request.identifier.hasPrefix("task-") { completionHandler([]) }
            else if #available(macOS 11.0, *) { completionHandler([.banner, .sound]) }
            else { completionHandler([.alert, .sound]) }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = (response.notification.request.content.userInfo["id"] as? String ?? "")
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\\", with: "")
        if !id.isEmpty {
            if response.actionIdentifier == "DONE" {
                runJS("window.SinapseCompleteTask && window.SinapseCompleteTask('\(id)')")
            } else {
                runJS("window.SinapseOpenTask && window.SinapseOpenTask('\(id)')")
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    self.window.makeKeyAndOrderFront(nil)
                }
            }
        }
        completionHandler()
    }

    // MARK: Menus
    func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Sobre o Sinapse", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let upd = NSMenuItem(title: "Atualizar o Sinapse com um novo arquivo…", action: #selector(updateFromFile), keyEquivalent: "")
        upd.target = self
        appMenu.addItem(upd)
        let back = NSMenuItem(title: "Voltar à versão original", action: #selector(resetHTML), keyEquivalent: "")
        back.target = self
        appMenu.addItem(back)
        let test = NSMenuItem(title: "Enviar notificação de teste", action: #selector(testNotification), keyEquivalent: "")
        test.target = self
        appMenu.addItem(test)
        let folder = NSMenuItem(title: "Mostrar a pasta de dados", action: #selector(showData), keyEquivalent: "")
        folder.target = self
        appMenu.addItem(folder)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ocultar o Sinapse", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Sair do Sinapse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Editar")
        edit.addItem(withTitle: "Desfazer", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Refazer", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(withTitle: "Recortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Colar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Selecionar tudo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "Visualizar")
        let reload = NSMenuItem(title: "Recarregar", action: #selector(reloadPage), keyEquivalent: "r")
        reload.target = self
        viewMenu.addItem(reload)
        viewMenu.addItem(withTitle: "Tela cheia", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        let winItem = NSMenuItem()
        let winMenu = NSMenu(title: "Janela")
        winMenu.addItem(withTitle: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        winItem.submenu = winMenu
        main.addItem(winItem)
        NSApp.windowsMenu = winMenu

        NSApp.mainMenu = main
    }

    @objc func reloadPage() { loadApp() }

    @objc func testNotification() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async {
                if s.authorizationStatus == .authorized || s.authorizationStatus == .provisional {
                    self.notifyNow(title: "O Sinapse consegue te avisar", body: "É assim que os lembretes das suas tasks vão aparecer.")
                    notifLog("teste enviado")
                } else {
                    let alert = NSAlert()
                    alert.messageText = "As notificações do Sinapse estão desligadas"
                    alert.informativeText = "Ative em Ajustes do Sistema › Notificações › Sinapse."
                    alert.addButton(withTitle: "Abrir Ajustes")
                    alert.addButton(withTitle: "Agora não")
                    if alert.runModal() == .alertFirstButtonReturn,
                       let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    @objc func showData() { NSWorkspace.shared.activateFileViewerSelecting([dataFile]) }

    @objc func updateFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Escolha o novo arquivo sinapse.html"
        panel.beginSheetModal(for: window) { result in
            guard result == .OK, let src = panel.url else { return }
            try? fm.removeItem(at: customHTML)
            do {
                try fm.copyItem(at: src, to: customHTML)
                self.loadApp()
            } catch {
                let alert = NSAlert()
                alert.messageText = "Não foi possível atualizar"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    @objc func resetHTML() {
        try? fm.removeItem(at: customHTML)
        loadApp()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
