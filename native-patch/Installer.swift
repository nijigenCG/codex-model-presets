import AppKit

final class Installer: NSObject, NSApplicationDelegate {
    let patch = NativePatch(resources: Bundle.main.resourceURL!)
    var target = URL(fileURLWithPath: "/Applications/ChatGPT.app")
    var window: NSWindow!
    let status = NSTextField(wrappingLabelWithString: "正在检查 Codex…")
    let installButton = NSButton(title: "安装补丁", target: nil, action: nil)
    let restoreButton = NSButton(title: "卸载并恢复原版", target: nil, action: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !FileManager.default.fileExists(atPath: target.path) {
            target = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") ?? URL(fileURLWithPath: "/Applications/Codex.app")
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 320), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Codex 模型按钮补丁"
        let title = NSTextField(labelWithString: "在输入栏直接切换模型")
        title.font = .boldSystemFont(ofSize: 23)
        let presets = NSTextField(wrappingLabelWithString: "Sol    GPT-6.1 Sol · XHigh · Standard\nLuna  GPT-6 Luna · Max · Fast")
        presets.font = .systemFont(ofSize: 15)
        let detail = NSTextField(wrappingLabelWithString: "非官方本地补丁。安装会备份应用，然后退出并重启 Codex。更新 Codex 后，重新打开本安装器即可。界面结构不兼容时会停止安装。")
        detail.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)
        installButton.target = self; installButton.action = #selector(install)
        restoreButton.target = self; restoreButton.action = #selector(restore)
        installButton.bezelStyle = .rounded; restoreButton.bezelStyle = .rounded
        let buttons = NSStackView(views: [installButton, restoreButton]); buttons.spacing = 12
        let stack = NSStackView(views: [title, presets, detail, status, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 28),
        ])
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        perform(restart: false) { try self.patch.check(self.target) }
    }

    @objc func install() { perform(restart: true) { try self.patch.install(self.target) } }
    @objc func restore() { perform(restart: true) { try self.patch.restore(self.target) } }

    func perform(restart: Bool, work: @escaping () throws -> String) {
        installButton.isEnabled = false; restoreButton.isEnabled = false
        status.stringValue = restart ? "正在处理，请稍候…" : "正在检查 Codex…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try work() }
            DispatchQueue.main.async {
                switch result {
                case .success(let message):
                    self.status.stringValue = message
                    if restart {
                        NSWorkspace.shared.openApplication(at: self.target, configuration: .init()) { _, error in
                            if let error { DispatchQueue.main.async { self.status.stringValue += "\n请手动打开 Codex：\(error.localizedDescription)" } }
                        }
                    }
                case .failure(let error):
                    self.status.stringValue = error.localizedDescription
                }
                self.installButton.isEnabled = true
                self.restoreButton.isEnabled = (try? self.patch.marker(self.target)) != nil
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let args = CommandLine.arguments
if args.count > 1 {
    do {
        let patch = NativePatch(resources: Bundle.main.resourceURL!)
        guard args.count >= 3 else { throw PatchFailure("用法：--check/--install/--restore APP；--prepare-copy ORIGINAL COPY") }
        let app = URL(fileURLWithPath: args[2])
        switch args[1] {
        case "--check": print(try patch.check(app))
        case "--install": print(try patch.install(app, closeApp: false))
        case "--restore": print(try patch.restore(app, closeApp: false))
        case "--prepare-copy":
            guard args.count == 4 else { throw PatchFailure("需要副本路径。") }
            guard try patch.marker(app) == nil else { throw PatchFailure("请使用官方原版进行副本验证。") }
            print(try patch.check(app))
            try patch.prepare(app, to: URL(fileURLWithPath: args[3]), backup: app)
            print("副本补丁和签名验证通过")
        default: throw PatchFailure("未知命令。")
        }
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let application = NSApplication.shared
    let delegate = Installer()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
}
