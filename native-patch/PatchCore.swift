import Foundation
import CryptoKit
import AppKit
import Darwin

struct PatchFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

struct AsarIntegrityDigest {
    // Electron's versioned integrity dictionary slot in the framework binary.
    static let sentinel = Data("AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A".utf8)

    static func dictionaryHash(_ metadata: [String: Any]) throws -> Data {
        guard let entries = metadata["ElectronAsarIntegrity"] as? [String: [String: String]], !entries.isEmpty else {
            throw PatchFailure("资源校验字典无效。")
        }
        var bytes = Data()
        for key in entries.keys.sorted(by: { $0.compare($1, options: .literal) == .orderedAscending }) {
            guard let algorithm = entries[key]?["algorithm"], let hash = entries[key]?["hash"] else {
                throw PatchFailure("资源校验字典无效。")
            }
            bytes.append(Data((key + algorithm + hash).utf8))
        }
        return Data(SHA256.hash(data: bytes))
    }

    static func updated(_ binary: Data, from original: [String: Any], to patched: [String: Any]) throws -> Data {
        guard let slot = binary.range(of: sentinel) else { return binary }
        guard binary.range(of: sentinel, in: slot.upperBound..<binary.endIndex) == nil,
              binary.endIndex - slot.upperBound >= 34 else { throw PatchFailure("框架资源校验结构不受支持。") }
        let flags = slot.upperBound
        if binary[flags] == 0 { return binary }
        guard binary[flags] == 1, binary[flags + 1] == 1 else { throw PatchFailure("框架资源校验版本不受支持。") }
        let range = flags + 2..<flags + 34
        guard binary.subdata(in: range) == (try dictionaryHash(original)) else {
            throw PatchFailure("框架资源校验摘要与原版不匹配。")
        }
        var result = binary
        result.replaceSubrange(range, with: try dictionaryHash(patched))
        return result
    }
}

@discardableResult
func run(_ executable: String, _ arguments: [String]) throws -> Data {
    let task = Process(), output = Pipe()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = arguments
    task.standardOutput = output; task.standardError = output
    try task.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else {
        throw PatchFailure("\(URL(fileURLWithPath: executable).lastPathComponent) 失败：\(String(decoding: data, as: UTF8.self))")
    }
    return data
}

struct Asar {
    let data: Data
    let base: Int
    let header: [String: Any]
    let headerHash: String

    init(_ url: URL) throws {
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        data = bytes
        guard bytes.count >= 16 else { throw PatchFailure("ASAR 文件不完整。") }
        func uint(_ offset: Int) -> Int {
            (0..<4).reduce(0) { $0 | Int(bytes[offset + $1]) << ($1 * 8) }
        }
        let length = uint(12)
        base = 8 + uint(4)
        guard uint(0) == 4, length > 0, 16 + length <= base, base <= data.count else {
            throw PatchFailure("无法识别 ASAR 格式。")
        }
        let json = data.subdata(in: 16..<16 + length)
        guard let value = try JSONSerialization.jsonObject(with: json) as? [String: Any] else { throw PatchFailure("ASAR 索引无效。") }
        header = value; headerHash = sha256(json)
    }

    func record(_ path: String) throws -> [String: Any] {
        var value = header
        for key in path.split(separator: "/") {
            guard let files = value["files"] as? [String: Any], let next = files[String(key)] as? [String: Any] else {
                throw PatchFailure("应用文件不存在：\(path)")
            }
            value = next
        }
        return value
    }

    func read(_ path: String) throws -> Data {
        let r = try record(path)
        guard r["unpacked"] as? Bool != true, let offset = r["offset"] as? String,
              let start = Int(offset), let size = r["size"] as? Int,
              start >= 0, size >= 0, base + start <= data.count, size <= data.count - base - start else {
            throw PatchFailure("应用文件索引无效：\(path)")
        }
        let bytes = data.subdata(in: base + start..<base + start + size)
        guard let integrity = r["integrity"] as? [String: Any], integrity["hash"] as? String == sha256(bytes) else {
            throw PatchFailure("应用文件校验失败：\(path)")
        }
        return bytes
    }

    func write(_ replacements: [String: Data], to url: URL) throws -> String {
        var root = header, appended = Data()
        func update(_ node: inout [String: Any], _ keys: ArraySlice<String>, _ value: [String: Any]) {
            var files = node["files"] as? [String: Any] ?? [:]
            let key = keys.first!
            if keys.count == 1 { files[key] = value }
            else {
                var child = files[key] as? [String: Any] ?? ["files": [:]]
                update(&child, keys.dropFirst(), value); files[key] = child
            }
            node["files"] = files
        }
        for path in replacements.keys.sorted() {
            let bytes = replacements[path]!, blockSize = 4194304
            var blocks: [String] = []
            for start in stride(from: 0, to: bytes.count, by: blockSize) {
                blocks.append(sha256(bytes.subdata(in: start..<min(bytes.count, start + blockSize))))
            }
            let value: [String: Any] = ["size": bytes.count, "offset": String(data.count - base + appended.count),
                "integrity": ["algorithm": "SHA256", "hash": sha256(bytes), "blockSize": blockSize, "blocks": blocks]]
            update(&root, path.split(separator: "/").map(String.init)[...], value)
            appended.append(bytes)
        }
        let json = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes])
        let padded = (json.count + 3) / 4 * 4
        var prefix = Data()
        for value in [4, padded + 8, padded + 4, json.count] {
            var little = UInt32(value).littleEndian
            withUnsafeBytes(of: &little) { prefix.append(contentsOf: $0) }
        }
        prefix.append(json); prefix.append(Data(repeating: 0, count: padded - json.count))
        let temp = url.appendingPathExtension("preset-tmp")
        FileManager.default.createFile(atPath: temp.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temp)
        do {
            try handle.write(contentsOf: prefix)
            for start in stride(from: base, to: data.count, by: 8 * 1024 * 1024) {
                try handle.write(contentsOf: data.subdata(in: start..<min(start + 8 * 1024 * 1024, data.count)))
            }
            try handle.write(contentsOf: appended); try handle.close()
            let result = try Asar(temp)
            for (path, bytes) in replacements { guard try result.read(path) == bytes else { throw PatchFailure("补丁写入校验失败。") } }
            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: temp, to: url)
        } catch {
            try? handle.close(); try? FileManager.default.removeItem(at: temp); throw error
        }
        return sha256(json)
    }
}

struct NativePatch {
    static let version = "1.1.2"
    static let markerPath = "Contents/Resources/codex-model-presets-patch.json"
    static let backupRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Codex Model Presets Patch/Backups", isDirectory: true)
    let resources: URL
    var configuration = PresetConfiguration.defaults

    func info(_ app: URL) throws -> [String: Any] {
        let bytes = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard let value = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any],
              value["CFBundleIdentifier"] as? String == "com.openai.codex" else { throw PatchFailure("请选择官方 Codex 应用。") }
        return value
    }

    func marker(_ app: URL) throws -> [String: Any]? {
        let url = app.appendingPathComponent(Self.markerPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw PatchFailure("补丁记录已损坏。") }
        return value
    }

    func patchSource(_ source: String) throws -> String {
        let id = "[A-Za-z_$][A-Za-z0-9_$]*"
        func unique(_ pattern: String, in text: String, part: String = "界面") throws -> [String] {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(text.startIndex..., in: text), matches = regex.matches(in: text, range: range)
            guard matches.count == 1, let match = matches.first else { throw PatchFailure("此 Codex 版本的\(part)结构不受支持（匹配 \(matches.count) 处），原应用未修改。") }
            return (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
        let start = try unique("function (\(id))\\(e\\)\\{let \(id)=\\(0,\(id)\\.c\\)\\(\\d+\\),\\{serviceTierDefaults:(\(id)),conversationId:(\(id)),hideLabel:", in: source)[0]
        let bodyStart = source.range(of: start)!.lowerBound
        let suffix = String(source[bodyStart...])
        let endRegex = try NSRegularExpression(pattern: "(\(id))=\(id)\\[\\d+\\],\\1\\}function ")
        guard let end = endRegex.firstMatch(in: suffix, range: NSRange(suffix.startIndex..., in: suffix)),
              let endRange = Range(end.range, in: suffix) else { throw PatchFailure("无法定位模型选择器。") }
        let body = String(suffix[..<endRange.upperBound])
        let native = try unique("\\{modelSettings:(\(id)),selectComposerModelAndReasoningEffort:(\(id)),setDefaultModelAndReasoningEffort:\(id),setModelAndReasoningEffort:\(id)\\}", in: body)
        let tier = try unique("\\{serviceTierSettings:(\(id)),setServiceTier:(\(id))\\}", in: body)
        let selector = NSRegularExpression.escapedPattern(for: native[2])
        // Older builds coalesce the agent method with the guarded selector.
        // Newer builds use a local function that also normalizes model IDs and
        // returns the guarded result; use it rather than the void UI callback.
        let dispatch = try unique(
            "\\((\(id))\\?\\.selectModelAndReasoningEffort\\?\\?\(selector)\\)|" +
            "(\(id))=function\\((\(id)),(\(id)),(\(id))\\)\\{let (\(id))=\\(\\)=>\\{[^;]+\\};return (\(id))==null\\?\(selector)\\((\(id))\\(\\3\\),\\4,\\6,\\5\\):\\7\\.selectModelAndReasoningEffort\\(\\8\\(\\3\\),\\4,\\6\\)\\}",
            in: body, part: "模型分派")
        let agent = dispatch[1].isEmpty ? dispatch[7] : dispatch[1]
        let apply = dispatch[2].isEmpty
            ? "(model,effort,tier)=>\(native[2])(model,effort,()=>{}, {serviceTier:tier})"
            : "(model,effort,tier)=>\(dispatch[2])(model,effort,{serviceTier:tier})"
        let reactRegex = try NSRegularExpression(pattern: "\\(0,(\(id))\\.useRef\\)")
        let runtimeNames = Set(reactRegex.matches(in: body, range: NSRange(body.startIndex..., in: body)).map { String(body[Range($0.range(at: 1), in: body)!]) })
        guard runtimeNames.count == 1, let reactName = runtimeNames.first else { throw PatchFailure("React 入口无法识别。") }
        let props = try unique("\\(0,(\(id))\\.jsx\\)\\(\(id),\\{align:`end`,disabled:(\(id)),daybreak:[^{}]+?triggerButton:\(id)\\}", in: body)
        func prop(_ key: String) throws -> String { try unique("(?:[,\\{])\(key):(\(id))(?:[,\\}])", in: props[0])[1] }
        let original = String(suffix[Range(end.range(at: 1), in: suffix)!])
        let fields = [
            "conversationId": try unique("serviceTierDefaults:\(id),conversationId:(\(id)),hideLabel:", in: body)[1],
            "model": try prop("model"), "effort": try prop("reasoningEffort"), "tier": try prop("selectedServiceTier"),
            "models": try prop("models"), "options": try prop("modelOptions"), "tiers": try prop("serviceTierOptions"),
            "onBeforeSelectModel": try prop("onBeforeSelectModel"), "onSelectModelOption": try prop("onSelectModelOption"),
            "onComplete": try prop("onSelectComplete"), "setTier": tier[2],
            "disabled": "\(props[2])||\(try prop("modelOptionsDisabled"))||\(try prop("reasoningEffortDisabled"))||\(try prop("serviceTierOptionsLoading"))||\(agent)?.isAeon===!0",
            "apply": apply,
        ]
        let expression = "(window.CodexModelPresets?.render(\(props[1]),\(reactName),\(original),{\(fields.keys.sorted().map { "\($0):\(fields[$0]!)" }.joined(separator: ","))})??\(original))"
        let tail = String(suffix[endRange])
        let oldReturn = ",\(original)}function "
        guard tail.hasSuffix(oldReturn) else { throw PatchFailure("无法识别模型选择器返回值。") }
        let newTail = String(tail.dropLast(oldReturn.count)) + ",\(expression)}function "
        let local = suffix.replacingCharacters(in: endRange, with: newTail)
        return String(source[..<bodyStart]) + local
    }

    func replacements(_ archive: Asar) throws -> [String: Data] {
        let files = try archive.record("webview/assets")["files"] as? [String: Any] ?? [:]
        let candidates = files.keys.filter { $0.hasPrefix("app-primary-") && $0.hasSuffix(".js") }
        guard candidates.count == 1, let chunk = candidates.first else { throw PatchFailure("无法唯一定位 Codex 界面代码。") }
        let path = "webview/assets/\(chunk)"
        let source = String(decoding: try archive.read(path), as: UTF8.self)
        let patched = try patchSource(source)
        let html = String(decoding: try archive.read("webview/index.html"), as: UTF8.self)
        guard html.components(separatedBy: "</head>").count == 2, !html.contains("codex-model-presets.js") else { throw PatchFailure("页面入口无法识别或已有补丁。") }
        let injection = "<script src=\"./codex-model-presets.js\"></script><link rel=\"stylesheet\" href=\"./codex-model-presets.css\">\n</head>"
        var script = Data("window.CodexModelPresetsConfig = ".utf8)
        script.append(try configuration.encoded()); script.append(Data(";\n".utf8))
        script.append(try Data(contentsOf: resources.appendingPathComponent("presets.js")))
        return [path: Data(patched.utf8), "webview/index.html": Data(html.replacingOccurrences(of: "</head>", with: injection).utf8),
            "webview/codex-model-presets.js": script,
            "webview/codex-model-presets.css": try Data(contentsOf: resources.appendingPathComponent("presets.css"))]
    }

    func check(_ app: URL) throws -> String {
        let metadata = try info(app), archive = try Asar(app.appendingPathComponent("Contents/Resources/app.asar"))
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        if let marker = try marker(app) {
            guard marker["patchedHeaderHash"] as? String == archive.headerHash else { throw PatchFailure("应用更新或补丁已变化，请先安装官方版本再重新打补丁。") }
            return "已安装补丁 \(marker["patchVersion"] ?? "")"
        }
        guard let integrity = metadata["ElectronAsarIntegrity"] as? [String: Any],
              let entry = integrity["Resources/app.asar"] as? [String: Any], entry["hash"] as? String == archive.headerHash else { throw PatchFailure("应用完整性校验失败。") }
        _ = try AsarIntegrityDigest.updated(Data(contentsOf: frameworkBinary(app)), from: metadata, to: metadata)
        _ = try replacements(archive)
        return "支持安装：Codex \(metadata["CFBundleShortVersionString"] ?? "")"
    }

    func prepare(_ original: URL, to copy: URL, backup: URL) throws {
        var metadata = try info(original)
        let originalMetadata = metadata
        let archive = try Asar(original.appendingPathComponent("Contents/Resources/app.asar"))
        let edits = try replacements(archive)
        try run("/usr/bin/ditto", [original.path, copy.path])
        let hash = try archive.write(edits, to: copy.appendingPathComponent("Contents/Resources/app.asar"))
        var integrity = metadata["ElectronAsarIntegrity"] as! [String: Any]
        integrity["Resources/app.asar"] = ["algorithm": "SHA256", "hash": hash]
        metadata["ElectronAsarIntegrity"] = integrity
        let plist = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        try plist.write(to: copy.appendingPathComponent("Contents/Info.plist"), options: .atomic)
        let marker: [String: Any] = ["patchVersion": Self.version, "appVersion": metadata["CFBundleShortVersionString"] ?? "",
            "originalHeaderHash": archive.headerHash, "patchedHeaderHash": hash, "backupPath": backup.path,
            "configurationHash": sha256(try configuration.encoded())]
        try JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted, .sortedKeys]).write(to: copy.appendingPathComponent(Self.markerPath))
        let binaryURL = frameworkBinary(copy), binary = try Data(contentsOf: binaryURL)
        let updated = try AsarIntegrityDigest.updated(binary, from: originalMetadata, to: metadata)
        if updated != binary {
            // Keep integrity validation enabled; change only its expected digest.
            let handle = try FileHandle(forWritingTo: binaryURL)
            defer { try? handle.close() }
            try handle.write(contentsOf: updated)
            try handle.close()
            let framework = copy.appendingPathComponent("Contents/Frameworks/Codex Framework.framework")
            let helpers = framework.appendingPathComponent("Versions/Current/Helpers")
            for helper in try FileManager.default.contentsOfDirectory(at: helpers, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "app" }) {
                if try signingInfo(helper).entitlements["com.apple.security.cs.disable-library-validation"] as? Bool != true {
                    try signLocally(helper)
                }
            }
            try run("/usr/bin/codesign", ["--force", "--sign", "-", "--preserve-metadata=flags,runtime", framework.path])
        }
        try signLocally(copy)
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", copy.path])
        try verifyLocalLaunch(copy)
    }

    private func frameworkBinary(_ app: URL) -> URL {
        app.appendingPathComponent("Contents/Frameworks/Codex Framework.framework/Versions/Current/Codex Framework")
    }

    private static func requiresVendorSignature(_ key: String) -> Bool {
        key.hasPrefix("com.apple.developer.") ||
            ["com.apple.application-identifier", "com.apple.security.application-groups", "keychain-access-groups"].contains(key)
    }

    private func signingInfo(_ app: URL) throws -> (entitlements: [String: Any], adHoc: Bool) {
        let output = String(decoding: try run("/usr/bin/codesign", ["-d", "--verbose=2", "--entitlements", ":-", app.path]), as: UTF8.self)
        guard let start = output.range(of: "<?xml"), let end = output.range(of: "</plist>"),
              let entitlements = try PropertyListSerialization.propertyList(from: Data(output[start.lowerBound..<end.upperBound].utf8), format: nil) as? [String: Any] else {
            throw PatchFailure("无法读取应用运行权限。")
        }
        return (entitlements, output.contains("Signature=adhoc"))
    }

    private func signLocally(_ app: URL) throws {
        var entitlements = try signingInfo(app).entitlements
        // These claims require the vendor's certificate/provisioning profile.
        for key in entitlements.keys.filter(Self.requiresVendorSignature) {
            entitlements.removeValue(forKey: key)
        }
        // Local executables must be able to load locally or vendor signed code.
        entitlements["com.apple.security.cs.disable-library-validation"] = true
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("codex-preset-entitlements-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: file) }
        try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0).write(to: file)
        try run("/usr/bin/codesign", ["--force", "--sign", "-", "--entitlements", file.path, "--preserve-metadata=flags,runtime", app.path])
    }

    func verifyLocalLaunch(_ app: URL) throws {
        let signature = try signingInfo(app)
        // A cold AMFI check may finish after the suspended probe. Reject known
        // incompatible entitlements directly instead of depending on its timing.
        if signature.adHoc {
            guard !signature.entitlements.keys.contains(where: Self.requiresVendorSignature) else {
                throw PatchFailure("本地签名含厂商受限权限，系统会拒绝启动。原应用未被替换。")
            }
            guard signature.entitlements["com.apple.security.cs.disable-library-validation"] as? Bool == true else {
                throw PatchFailure("本地签名缺少加载官方框架所需的权限。原应用未被替换。")
            }
        }
        let metadata = try info(app)
        _ = try AsarIntegrityDigest.updated(Data(contentsOf: frameworkBinary(app)), from: metadata, to: metadata)
        guard let executable = metadata["CFBundleExecutable"] as? String, !executable.contains("/") else { throw PatchFailure("应用启动入口无效。") }
        // AMFI still validates a suspended spawn. No application code, UI or
        // app-server executes; restricted ad-hoc entitlements cause SIGKILL.
        let path = app.appendingPathComponent("Contents/MacOS/\(executable)").path
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_START_SUSPENDED))
        let argument = strdup(path)!
        defer { free(argument) }
        var arguments: [UnsafeMutablePointer<CChar>?] = [argument, nil]
        var pid: pid_t = 0
        let result = path.withCString { executable in
            arguments.withUnsafeMutableBufferPointer { argv in
                posix_spawn(&pid, executable, nil, &attributes, argv.baseAddress!, environ)
            }
        }
        guard result == 0 else { throw PatchFailure("系统启动许可检查失败：\(String(cString: strerror(result)))") }
        Thread.sleep(forTimeInterval: 0.5)
        var status: Int32 = 0
        let waited = waitpid(pid, &status, WNOHANG)
        if waited == 0 {
            kill(pid, SIGKILL)
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        } else {
            throw PatchFailure("系统拒绝启动补丁应用（进程状态 \(status)）。原应用未被替换。")
        }
    }

    func install(_ app: URL, closeApp: Bool = true) throws -> String {
        if !closeApp { try requireStopped(app) }
        _ = try check(app)
        try configuration.validate()
        let fm = FileManager.default, version = try info(app)["CFBundleShortVersionString"] as? String ?? "unknown"
        let expectedHash = try Asar(app.appendingPathComponent("Contents/Resources/app.asar")).headerHash
        let backup: URL
        if let installed = try marker(app) { backup = try originalBackup(installed) }
        else {
            backup = Self.backupRoot.appendingPathComponent("\(version)-\(UUID().uuidString)/\(app.lastPathComponent)")
            try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try run("/usr/bin/ditto", [app.path, backup.path])
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", backup.path])
        }
        let stage = app.deletingLastPathComponent().appendingPathComponent(".codex-presets-\(UUID().uuidString).app")
        defer { try? fm.removeItem(at: stage) }
        try prepare(backup, to: stage, backup: backup)
        if closeApp { try stop(app) }
        guard try Asar(app.appendingPathComponent("Contents/Resources/app.asar")).headerHash == expectedHash else { throw PatchFailure("应用在安装期间更新了，已取消替换。") }
        try swap(stage, app)
        return "安装完成，系统启动许可检查通过。\(configuration.presets.map(\.label).joined(separator: " 和 ")) 按钮将在重启 Codex 后显示。"
    }

    func restore(_ app: URL, closeApp: Bool = true) throws -> String {
        if !closeApp { try requireStopped(app) }
        _ = try check(app)
        guard let marker = try marker(app) else { throw PatchFailure("当前应用没有安装此补丁。") }
        let backup = try originalBackup(marker)
        let stage = app.deletingLastPathComponent().appendingPathComponent(".codex-restore-\(UUID().uuidString).app")
        defer { try? FileManager.default.removeItem(at: stage) }
        try run("/usr/bin/ditto", [backup.path, stage.path])
        if closeApp { try stop(app) }
        guard try Asar(app.appendingPathComponent("Contents/Resources/app.asar")).headerHash == marker["patchedHeaderHash"] as? String else {
            throw PatchFailure("应用在恢复期间更新了，已取消替换。")
        }
        try swap(stage, app)
        return "已恢复官方原版应用。"
    }

    private func originalBackup(_ marker: [String: Any]) throws -> URL {
        guard let path = marker["backupPath"] as? String else { throw PatchFailure("补丁没有原版备份记录。") }
        let backup = URL(fileURLWithPath: path).standardizedFileURL
        guard backup.path.hasPrefix(Self.backupRoot.path + "/"),
              try info(backup)["CFBundleShortVersionString"] as? String == marker["appVersion"] as? String,
              try Asar(backup.appendingPathComponent("Contents/Resources/app.asar")).headerHash == marker["originalHeaderHash"] as? String else { throw PatchFailure("找不到匹配的原版备份。") }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", backup.path])
        return backup
    }

    private func stop(_ app: URL) throws {
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.standardizedFileURL == app.standardizedFileURL }
        for process in running { guard process.terminate() else { throw PatchFailure("请退出 Codex 后重新安装。") } }
        let deadline = Date().addingTimeInterval(15)
        while running.contains(where: { !$0.isTerminated }) && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        guard running.allSatisfy({ $0.isTerminated }) else { throw PatchFailure("Codex 仍在运行，请退出后重试。") }
    }

    private func requireStopped(_ app: URL) throws {
        guard !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.standardizedFileURL == app.standardizedFileURL }) else {
            throw PatchFailure("命令行安装前请先退出 Codex。")
        }
    }

    private func swap(_ stage: URL, _ app: URL) throws {
        let fm = FileManager.default, rollback = app.deletingLastPathComponent().appendingPathComponent(".codex-rollback-\(UUID().uuidString).app")
        try fm.moveItem(at: app, to: rollback)
        do { try fm.moveItem(at: stage, to: app) }
        catch { try fm.moveItem(at: rollback, to: app); throw error }
        try? fm.removeItem(at: rollback)
    }
}
