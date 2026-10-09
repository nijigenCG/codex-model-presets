import Foundation

struct ModelPreset: Codable, Equatable {
    var label: String
    var model: String
    var effort: String
    var speed: String
}

struct PresetConfiguration: Codable, Equatable {
    var presets: [ModelPreset]
    static let defaults = PresetConfiguration(presets: [
        ModelPreset(label: "Sol", model: "gpt-6.1-sol", effort: "xhigh", speed: "standard"),
        ModelPreset(label: "Luna", model: "gpt-6-luna", effort: "max", speed: "fast"),
    ])
    static let efforts = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Codex Model Presets Patch/presets.json")

    static func parse(_ data: Data) throws -> PresetConfiguration {
        if String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .defaults }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PatchFailure("配置必须是 JSON 对象。") }
        guard let value = object["presets"] else { return .defaults }
        guard let rows = value as? [[String: Any]], rows.isEmpty || rows.count == 2 else { throw PatchFailure("请配置两个按钮。") }
        if rows.isEmpty { return .defaults }
        var configuration = defaults
        for index in rows.indices {
            func field(_ key: String, _ fallback: String) throws -> String {
                guard let raw = rows[index][key] else { return fallback }
                guard let text = raw as? String else { throw PatchFailure("按钮 \(index + 1) 的 \(key) 必须是文本。") }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? fallback : trimmed
            }
            let fallback = defaults.presets[index]
            configuration.presets[index] = try ModelPreset(label: field("label", fallback.label), model: field("model", fallback.model),
                effort: field("effort", fallback.effort), speed: field("speed", fallback.speed))
        }
        try configuration.validate()
        return configuration
    }

    func validate() throws {
        guard presets.count == 2 else { throw PatchFailure("请配置两个按钮。") }
        for (index, preset) in presets.enumerated() {
            guard !preset.label.isEmpty, preset.label.count <= 16, !preset.label.contains(where: { $0.isNewline }),
                  !preset.model.isEmpty, !preset.model.contains(where: { $0.isWhitespace }),
                  Self.efforts.contains(preset.effort), ["standard", "fast"].contains(preset.speed) else {
                throw PatchFailure("按钮 \(index + 1) 的名称、模型、推理强度或速度无效。")
            }
        }
    }

    static func load() throws -> PresetConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .defaults }
        do { return try parse(Data(contentsOf: fileURL)) }
        catch { throw PatchFailure("预设配置读取失败：\(error.localizedDescription)\n\(fileURL.path)") }
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    func save() throws {
        let data = try encoded()
        try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: Self.fileURL, options: .atomic)
    }
}
