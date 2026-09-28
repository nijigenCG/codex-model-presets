import AppKit
import ApplicationServices

private enum Preset: String, CaseIterable {
    case luna = "luna"
    case sol = "sol"
    case astra = "astra"

    var label: String {
        switch self {
        case .luna: "5.6 Luna · Max · Fast"
        case .sol: "6 Sol · Extra High"
        case .astra: "6 Astra · Medium"
        }
    }

    var modelMenuTitle: String {
        switch self {
        case .luna: "5.6 Luna"
        case .sol: "6 Sol"
        case .astra: "6 Astra"
        }
    }

    var powerIndex: Int {
        switch self {
        case .luna: 5
        case .sol: 4
        case .astra: 2
        }
    }

    var fast: Bool { self == .luna }
}

private enum SwitchError: LocalizedError {
    case accessibility
    case appNotRunning
    case noChat
    case control(String)
    case verification(String)

    var errorDescription: String? {
        switch self {
        case .accessibility: "请在系统设置 → 隐私与安全性 → 辅助功能中允许 Codex 快捷模型。"
        case .appNotRunning: "请先打开 ChatGPT 桌面端和要切换的 Codex 聊天。"
        case .noChat: "没有找到当前聊天的模型控件。请先打开一个 Codex 聊天。"
        case .control(let name): "没有找到“\(name)”控件；Codex 界面可能已更新。"
        case .verification(let detail): "切换后验证失败：\(detail)"
        }
    }
}

private final class CodexControls {
    private let app: NSRunningApplication
    private let axApp: AXUIElement
    private var targetTitle: String?
    private let debug = ProcessInfo.processInfo.environment["CODEX_PRESETS_DEBUG"] == "1"

    private func log(_ message: String) {
        if debug { fputs("DEBUG: \(message)\n", stderr) }
    }

    private func logMenu(_ stage: String) {
        guard debug, let root = try? window() else { return }
        var titles: [String] = []
        func collect(_ element: AXUIElement) {
            if value(element, kAXRoleAttribute as String) as? String == "AXMenuItem",
               let name = value(element, kAXTitleAttribute as String) as? String { titles.append(name) }
            for child in children(of: element) { collect(child) }
        }
        collect(root)
        log("\(stage): \(titles.suffix(12))")
    }

    init() throws {
        guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) else {
            throw SwitchError.accessibility
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first else {
            throw SwitchError.appNotRunning
        }
        self.app = app
        self.axApp = AXUIElementCreateApplication(app.processIdentifier)
    }

    private func value(_ element: AXUIElement, _ key: String) -> Any? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }

    private func find(_ element: AXUIElement, role: String, title: String? = nil) -> AXUIElement? {
        if value(element, kAXRoleAttribute as String) as? String == role,
           title == nil || value(element, kAXTitleAttribute as String) as? String == title {
            return element
        }
        for child in value(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? [] {
            if let match = find(child, role: role, title: title) { return match }
        }
        return nil
    }

    private func window() throws -> AXUIElement {
        for candidate in value(axApp, kAXWindowsAttribute as String) as? [AXUIElement] ?? [] {
            if find(candidate, role: "AXTextArea", title: "Do anything") != nil {
                let currentTitle = find(candidate, role: "AXWebArea")
                    .flatMap { value($0, kAXTitleAttribute as String) as? String }
                if let targetTitle, currentTitle != targetTitle {
                    throw SwitchError.verification("切换过程中打开了另一个聊天")
                }
                return candidate
            }
        }
        throw SwitchError.noChat
    }

    private func focusInput() throws {
        _ = app.activate(options: .activateAllWindows)
        guard let input = find(try window(), role: "AXTextArea", title: "Do anything") else {
            throw SwitchError.control("Codex 输入框")
        }
        let result = AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard result == .success, value(input, kAXFocusedAttribute as String) as? Bool == true else {
            throw SwitchError.control("输入框焦点")
        }
    }

    private func waitFor(_ role: String, title: String, seconds: TimeInterval = 2) throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if let control = find(try window(), role: role, title: title) { return control }
            Thread.sleep(forTimeInterval: 0.06)
        } while Date() < deadline
        if debug {
            var titles: [String] = []
            func collect(_ element: AXUIElement) {
                if value(element, kAXRoleAttribute as String) as? String == "AXMenuItem",
                   let name = value(element, kAXTitleAttribute as String) as? String { titles.append(name) }
                for child in children(of: element) { collect(child) }
            }
            if let candidate = try? window() { collect(candidate) }
            log("missing \(title); menus=\(titles.suffix(20)); active=\(app.isActive)")
        }
        throw SwitchError.control(title)
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
    }

    private func frame(_ element: AXUIElement) throws -> CGRect {
        guard let positionValue = value(element, kAXPositionAttribute as String),
              let sizeValue = value(element, kAXSizeAttribute as String) else {
            throw SwitchError.control("位置")
        }
        let position = positionValue as! AXValue
        let size = sizeValue as! AXValue
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        AXValueGetValue(position, .cgPoint, &point)
        AXValueGetValue(size, .cgSize, &dimensions)
        return CGRect(origin: point, size: dimensions)
    }

    private func click(_ point: CGPoint) throws {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left) else {
            throw SwitchError.control("鼠标点击")
        }
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        up.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.25)
    }

    private func click(_ element: AXUIElement) throws {
        let box = try frame(element)
        log("click \(value(element, kAXTitleAttribute as String) ?? "") at \(box.midX),\(box.midY)")
        try click(CGPoint(x: box.midX, y: box.midY))
    }

    private func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
        let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)!
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
    }

    private func activate() throws {
        _ = app.activate(options: .activateAllWindows)
        let script = NSAppleScript(source: "tell application \"System Events\" to tell process \"ChatGPT\" to set frontmost to true")
        var error: NSDictionary?
        _ = script?.executeAndReturnError(&error)
        if error != nil { throw SwitchError.control("激活 ChatGPT") }
        log("activated; active=\(app.isActive)")
    }

    private func effortMenu() throws -> AXUIElement {
        if let menu = find(try window(), role: "AXGroup", title: "Select effort") { return menu }
        func modelPopup(_ element: AXUIElement) -> AXUIElement? {
            if value(element, kAXRoleAttribute as String) as? String == "AXPopUpButton",
               let title = value(element, kAXTitleAttribute as String) as? String,
               ["6 Sol", "6 Astra", "6 Luna", "5.6 Sol", "5.6 Terra", "5.6 Luna", "5.5"].contains(where: title.hasPrefix) {
                return element
            }
            for child in children(of: element) {
                if let match = modelPopup(child) { return match }
            }
            return nil
        }
        if let popup = modelPopup(try window()) {
            try click(popup)
            if let menu = try? waitFor("AXGroup", title: "Select effort", seconds: 0.6) { return menu }
        }
        key(46, flags: [.maskControl, .maskShift]) // Codex: Control-Shift-M
        return try waitFor("AXGroup", title: "Select effort")
    }

    private func pickerIsOpen() throws -> Bool {
        let root = try window()
        return find(root, role: "AXGroup", title: "Select effort") != nil
            || find(root, role: "AXMenuItem", title: "Default Recommended set of models") != nil
    }

    private func closePicker() throws {
        for _ in 0..<3 {
            if try !pickerIsOpen() { return }
            key(53)
        }
        guard try !pickerIsOpen() else { throw SwitchError.verification("选择菜单没有关闭") }
    }

    private func menuText(prefix: String) throws -> String {
        var seen: [String] = []
        func search(_ element: AXUIElement) -> String? {
            if value(element, kAXRoleAttribute as String) as? String == "AXStaticText",
               let text = value(element, kAXValueAttribute as String) as? String {
                seen.append(text)
                if text.hasPrefix(prefix), text.contains(" of ") { return text }
            }
            for child in children(of: element) {
                if let text = search(child) { return text }
            }
            return nil
        }
        let deadline = Date().addingTimeInterval(2)
        repeat {
            seen.removeAll()
            if let text = search(try effortMenu()) { return text }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        log("static texts=\(seen)")
        throw SwitchError.control("推理强度状态")
    }

    private func isFast() throws -> Bool {
        let menu = try effortMenu()
        if find(menu, role: "AXMenuItem", title: "Enable standard mode") != nil { return true }
        if find(menu, role: "AXMenuItem", title: "Enable fast mode") != nil { return false }
        throw SwitchError.control("Fast 模式状态")
    }

    func apply(_ preset: Preset) throws {
        try activate()
        let current = try window()
        targetTitle = find(current, role: "AXWebArea")
            .flatMap { value($0, kAXTitleAttribute as String) as? String }
        log("target chat=\(targetTitle ?? "unknown")")
        try closePicker()
        var modelItem: AXUIElement?
        for _ in 0..<5 {
            if let visible = find(try window(), role: "AXMenuItem", title: preset.modelMenuTitle) {
                modelItem = visible
                break
            }
            let menu = try effortMenu()
            guard let select = find(menu, role: "AXMenuItem", title: "Select model") else {
                throw SwitchError.control("Select model")
            }
            try click(select)
            logMenu("after Select model")
            modelItem = find(try window(), role: "AXMenuItem", title: preset.modelMenuTitle)
            if modelItem != nil { break }
        }
        guard let modelItem else { throw SwitchError.control(preset.modelMenuTitle) }
        try click(modelItem)
        log("clicked \(preset.modelMenuTitle)")
        logMenu("after model")
        _ = try menuText(prefix: "\(preset.modelMenuTitle) ")
        let menu = try effortMenu()
        guard let power = find(menu, role: "AXMenuItem", title: "Power"),
              let first = children(of: power).first,
              let second = children(of: first).first,
              let slider = children(of: second).first else {
            throw SwitchError.control("推理强度滑条")
        }
        let box = try frame(slider)
        try click(CGPoint(x: box.minX + (CGFloat(preset.powerIndex) - 0.5) * box.width / 5,
                          y: box.midY))

        if try isFast() != preset.fast {
            let toggle = preset.fast ? "Enable fast mode" : "Enable standard mode"
            try click(waitFor("AXMenuItem", title: toggle))
        }

        let expected = "\(preset.modelMenuTitle) "
        let text = try menuText(prefix: expected)
        guard text.hasPrefix(expected), text.contains(", \(preset.powerIndex) of 5.") else {
            throw SwitchError.verification(text)
        }
        guard try isFast() == preset.fast else { throw SwitchError.verification("Fast 状态不符") }
        try closePicker()
        try focusInput()
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItems: [NSStatusItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        for preset in Preset.allCases {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.title = preset == .luna ? "Luna" : preset == .sol ? "Sol" : "Astra"
            item.button?.toolTip = preset.label
            item.button?.identifier = NSUserInterfaceItemIdentifier(preset.rawValue)
            item.button?.target = self
            item.button?.action = #selector(selectPreset(_:))
            statusItems.append(item)
        }
        let utility = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        utility.button?.title = "◉"
        utility.button?.toolTip = "Codex 快捷模型"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: ""))
        menu.items.forEach { $0.target = self }
        utility.menu = menu
        statusItems.append(utility)
    }

    @objc private func selectPreset(_ sender: AnyObject) {
        let name = (sender as? NSButton)?.identifier?.rawValue
        if ProcessInfo.processInfo.environment["CODEX_PRESETS_DEBUG"] == "1" {
            fputs("DEBUG: button sender=\(type(of: sender)), preset=\(name ?? "nil")\n", stderr)
        }
        guard let name, let preset = Preset(rawValue: name) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            do {
                try CodexControls().apply(preset)
            } catch {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "模型切换失败"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--once",
   let preset = Preset(rawValue: CommandLine.arguments[2]) {
    do {
        try CodexControls().apply(preset)
        print("OK: \(preset.label)")
    } catch {
        fputs("ERROR: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
