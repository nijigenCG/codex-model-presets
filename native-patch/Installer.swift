import AppKit

final class Installer: NSObject, NSApplicationDelegate {
    var patch = NativePatch(resources: Bundle.main.resourceURL!)
    var target = URL(fileURLWithPath: "/Applications/ChatGPT.app")
    var window: NSWindow!
    let status = NSTextField(wrappingLabelWithString: "正在检查 Codex…")
    let installButton = NSButton(title: "保存配置并安装", target: nil, action: nil)
    let restoreButton = NSButton(title: "卸载并恢复原版", target: nil, action: nil)
    let resetButton = NSButton(title: "恢复默认配置", target: nil, action: nil)
    let addPresetButton = NSButton(title: "添加模型", target: nil, action: nil)
    var stack: NSStackView!
    var grid: NSGridView?
    var labels: [NSTextField] = []
    var models: [NSTextField] = []
    var efforts: [NSPopUpButton] = []
    var speeds: [NSPopUpButton] = []
    var removeButtons: [NSButton] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !FileManager.default.fileExists(atPath: target.path) {
            target = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") ?? URL(fileURLWithPath: "/Applications/Codex.app")
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 520), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Codex 模型按钮补丁 \(NativePatch.version)"
        let title = NSTextField(labelWithString: "在输入栏直接切换模型")
        title.font = .boldSystemFont(ofSize: 23)
        var configurationError: String?
        do { patch.configuration = try PresetConfiguration.load() }
        catch { configurationError = error.localizedDescription }
        populate(patch.configuration)
        let detail = NSTextField(wrappingLabelWithString: "最多可配置 4 个模型按钮。新增后请填写模型 ID；名称留空时自动命名。修改后点击「保存配置并安装」生效。\n非官方补丁：先备份和检查，再退出并重启 Codex；更新 Codex 后重新安装。")
        detail.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)
        status.maximumNumberOfLines = 4
        installButton.target = self; installButton.action = #selector(install)
        restoreButton.target = self; restoreButton.action = #selector(restore)
        resetButton.target = self; resetButton.action = #selector(reset)
        addPresetButton.target = self; addPresetButton.action = #selector(addPreset)
        for button in [installButton, restoreButton, resetButton] { button.bezelStyle = .rounded }
        let buttons = NSStackView(views: [installButton, resetButton, restoreButton]); buttons.spacing = 12
        grid = makeGrid()
        stack = NSStackView(views: [title, grid!, addPresetButton, detail, status, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 28),
        ])
        updatePresetActions()
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        perform(restart: false) { try self.patch.check(self.target) + (configurationError.map { "\n\($0)" } ?? "") }
    }

    func populate(_ configuration: PresetConfiguration) {
        labels = []; models = []; efforts = []; speeds = []; removeButtons = []
        for (index, preset) in configuration.presets.enumerated() {
            let label = NSTextField(string: preset.label), model = NSTextField(string: preset.model)
            label.placeholderString = "模型 \(index + 1)"
            model.placeholderString = preset.model.isEmpty ? "模型 ID（必填）" : preset.model
            let effort = NSPopUpButton(), speed = NSPopUpButton()
            effort.addItems(withTitles: PresetConfiguration.efforts)
            speed.addItems(withTitles: ["Standard", "Fast"])
            effort.selectItem(withTitle: preset.effort)
            speed.selectItem(withTitle: preset.speed == "fast" ? "Fast" : "Standard")
            let remove = NSButton(title: "删除", target: self, action: #selector(removePreset(_:)))
            remove.tag = index; remove.bezelStyle = .rounded
            label.widthAnchor.constraint(equalToConstant: 80).isActive = true
            model.widthAnchor.constraint(equalToConstant: 205).isActive = true
            effort.widthAnchor.constraint(equalToConstant: 100).isActive = true
            speed.widthAnchor.constraint(equalToConstant: 100).isActive = true
            remove.widthAnchor.constraint(equalToConstant: 48).isActive = true
            labels.append(label); models.append(model); efforts.append(effort); speeds.append(speed); removeButtons.append(remove)
        }
        rebuildGrid()
    }

    @objc func reset() { populate(.defaults) }
    @objc func addPreset() {
        guard labels.count < 4 else { return }
        var presets = currentPresets()
        presets.append(ModelPreset(label: "模型 \(presets.count + 1)", model: "", effort: "medium", speed: "standard"))
        populate(PresetConfiguration(presets: presets))
    }

    @objc func removePreset(_ sender: NSButton) {
        guard labels.count > 1, sender.tag >= 0, sender.tag < labels.count else { return }
        var presets = currentPresets()
        presets.remove(at: sender.tag)
        populate(PresetConfiguration(presets: presets))
    }

    func currentPresets() -> [ModelPreset] {
        labels.indices.map { index in
            ModelPreset(label: labels[index].stringValue, model: models[index].stringValue,
                effort: efforts[index].titleOfSelectedItem ?? "medium", speed: speeds[index].titleOfSelectedItem?.lowercased() ?? "standard")
        }
    }

    func makeGrid() -> NSGridView {
        var rows: [[NSView]] = [["按钮名称", "模型 ID", "推理强度", "速度", ""].map { NSTextField(labelWithString: $0) }]
        for index in labels.indices { rows.append([labels[index], models[index], efforts[index], speeds[index], removeButtons[index]]) }
        let result = NSGridView(views: rows); result.columnSpacing = 10; result.rowSpacing = 8
        return result
    }

    func rebuildGrid() {
        guard stack != nil else { return }
        if let grid { stack.removeArrangedSubview(grid); grid.removeFromSuperview() }
        grid = makeGrid()
        stack.insertArrangedSubview(grid!, at: 1)
        updatePresetActions()
    }

    func updatePresetActions() {
        addPresetButton.title = "添加模型（\(labels.count)/4）"
        addPresetButton.isEnabled = labels.count < 4
        for button in removeButtons { button.isEnabled = labels.count > 1 }
    }

    @objc func install() {
        do {
            let rows = labels.indices.map { index in
                ["label": labels[index].stringValue, "model": models[index].stringValue,
                 "effort": efforts[index].titleOfSelectedItem ?? "medium", "speed": speeds[index].titleOfSelectedItem?.lowercased() ?? "standard"]
            }
            patch.configuration = try PresetConfiguration.parse(JSONSerialization.data(withJSONObject: ["presets": rows]))
            try patch.configuration.save()
            populate(patch.configuration)
            let configured = patch
            perform(restart: true, recover: true) { try configured.install(self.target) }
        } catch { status.stringValue = error.localizedDescription }
    }
    @objc func restore() { perform(restart: true) { try self.patch.restore(self.target) } }

    func enableControls(_ enabled: Bool) {
        installButton.isEnabled = enabled; resetButton.isEnabled = enabled
        restoreButton.isEnabled = enabled && (try? patch.marker(target)) != nil
        for field in labels + models { field.isEnabled = enabled }
        for menu in efforts + speeds { menu.isEnabled = enabled }
        addPresetButton.isEnabled = enabled && labels.count < 4
        for button in removeButtons { button.isEnabled = enabled && labels.count > 1 }
    }

    func perform(restart: Bool, recover: Bool = false, work: @escaping () throws -> String) {
        enableControls(false)
        status.stringValue = restart ? "正在处理，请稍候…" : "正在检查 Codex…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try work() }
            DispatchQueue.main.async {
                switch result {
                case .success(let message):
                    self.status.stringValue = message
                    if restart {
                        self.relaunch(message: message, recover: recover)
                        return
                    }
                case .failure(let error):
                    self.status.stringValue = error.localizedDescription
                }
                self.enableControls(true)
            }
        }
    }

    func relaunch(message: String, recover: Bool) {
        status.stringValue = message + "\n正在启动 Codex…"
        NSWorkspace.shared.openApplication(at: target, configuration: .init()) { application, error in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if let application, error == nil, !application.isTerminated {
                    self.status.stringValue = message + "\nCodex 进程已启动。"
                    self.enableControls(true)
                } else {
                    let reason = error?.localizedDescription ?? "Codex 进程启动后退出。"
                    if recover {
                        self.perform(restart: true) { "启动失败：\(reason)\n" + (try self.patch.restore(self.target)) }
                    } else {
                        self.status.stringValue = message + "\n请手动打开 Codex：\(reason)"
                        self.enableControls(true)
                    }
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let args = CommandLine.arguments
if args.count > 1 {
    do {
        var patch = NativePatch(resources: Bundle.main.resourceURL!)
        guard args.count >= 3 else { throw PatchFailure("用法：--check/--install/--restore/--startup-check APP；--prepare-copy ORIGINAL COPY [CONFIG.json]") }
        let app = URL(fileURLWithPath: args[2])
        switch args[1] {
        case "--check": print(try patch.check(app))
        case "--install":
            patch.configuration = try args.count == 4 ? PresetConfiguration.parse(Data(contentsOf: URL(fileURLWithPath: args[3]))) : PresetConfiguration.load()
            print(try patch.install(app, closeApp: false))
        case "--restore": print(try patch.restore(app, closeApp: false))
        case "--startup-check": try patch.verifyLocalLaunch(app); print("系统启动许可检查通过（不启动应用界面）")
        case "--prepare-copy":
            guard args.count == 4 || args.count == 5 else { throw PatchFailure("需要副本路径。") }
            patch.configuration = try args.count == 5 ? PresetConfiguration.parse(Data(contentsOf: URL(fileURLWithPath: args[4]))) : PresetConfiguration.load()
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
