import Foundation
import CryptoKit

let originalIntegrity: [String: Any] = ["ElectronAsarIntegrity": ["Resources/app.asar": ["algorithm": "SHA256", "hash": "original"]]]
let patchedIntegrity: [String: Any] = ["ElectronAsarIntegrity": ["Resources/app.asar": ["algorithm": "SHA256", "hash": "patched"]]]
let digest = Data(SHA256.hash(data: Data("Resources/app.asarSHA256original".utf8)))
let slot = AsarIntegrityDigest.sentinel + Data([1, 1]) + digest
let binary = Data([3, 4]) + slot + Data([5, 6])
let updated = try AsarIntegrityDigest.updated(binary, from: originalIntegrity, to: patchedIntegrity)
precondition(updated == Data([3, 4]) + AsarIntegrityDigest.sentinel + Data([1, 1]) + Data(SHA256.hash(data: Data("Resources/app.asarSHA256patched".utf8))) + Data([5, 6]))
let verified = try AsarIntegrityDigest.updated(updated, from: patchedIntegrity, to: patchedIntegrity)
precondition(verified == updated)
for invalid in [binary + slot, AsarIntegrityDigest.sentinel, AsarIntegrityDigest.sentinel + Data([1, 2]) + digest,
                AsarIntegrityDigest.sentinel + Data([1, 1]) + Data(repeating: 0, count: 32)] {
    do { _ = try AsarIntegrityDigest.updated(invalid, from: originalIntegrity, to: patchedIntegrity); preconditionFailure("必须拒绝不兼容或损坏的框架校验摘要") }
    catch { precondition(error is PatchFailure) }
}
let legacy = try AsarIntegrityDigest.updated(Data([1, 2]), from: originalIntegrity, to: patchedIntegrity)
precondition(legacy == Data([1, 2]))
let unused = AsarIntegrityDigest.sentinel + Data(repeating: 0, count: 34)
let unusedResult = try AsarIntegrityDigest.updated(unused, from: originalIntegrity, to: patchedIntegrity)
precondition(unusedResult == unused)
print("框架校验摘要同步、修改范围、重复/截断/未知版本/原版摘要拒绝和旧框架兼容验证通过。")

let app = URL(fileURLWithPath: CommandLine.arguments[1])
let patch = NativePatch(resources: URL(fileURLWithPath: CommandLine.arguments[2]))
let archive = try Asar(app.appendingPathComponent("Contents/Resources/app.asar"))
let files = try archive.record("webview/assets")["files"] as! [String: Any]
let chunk = files.keys.first { $0.hasPrefix("app-primary-") && $0.hasSuffix(".js") }!
let source = String(decoding: try archive.read("webview/assets/\(chunk)"), as: UTF8.self)
let patched = try patch.patchSource(source)
let expression = try NSRegularExpression(pattern: #"\(window.CodexModelPresets\?\.render.*?\}\)\?\?([A-Za-z_$][A-Za-z0-9_$]*)\)"#)
let edits = expression.matches(in: patched, range: NSRange(patched.startIndex..., in: patched))
precondition(edits.count == 1)
let edit = edits[0], replacement = String(patched[Range(edit.range(at: 1), in: patched)!])
precondition(patched.replacingCharacters(in: Range(edit.range, in: patched)!, with: replacement) == source,
             "补丁必须只修改选择器的最终返回表达式")
let runtime = try NSRegularExpression(pattern: #"CodexModelPresets\?\.render\(([A-Za-z_$][A-Za-z0-9_$]*),([A-Za-z_$][A-Za-z0-9_$]*),"#)
let bindings = runtime.firstMatch(in: patched, range: NSRange(patched.startIndex..., in: patched))!
let jsxName = String(patched[Range(bindings.range(at: 1), in: patched)!])
let reactName = String(patched[Range(bindings.range(at: 2), in: patched)!])
let renamed = source.replacingOccurrences(of: "\\b\(NSRegularExpression.escapedPattern(for: reactName))\\b", with: "RenamedReact", options: .regularExpression)
                    .replacingOccurrences(of: "\\b\(NSRegularExpression.escapedPattern(for: jsxName))\\b", with: "RenamedJSX", options: .regularExpression)
let renamedPatch = try patch.patchSource(renamed)
precondition(renamedPatch.contains("render(RenamedJSX,RenamedReact,"))
let applyPattern = try NSRegularExpression(pattern: #"apply:\(model,effort,tier\)=>([A-Za-z_$][A-Za-z0-9_$]*)\(model,effort,"#)
let applyMatch = applyPattern.firstMatch(in: patched, range: NSRange(patched.startIndex..., in: patched))!
let applyName = String(patched[Range(applyMatch.range(at: 1), in: patched)!])
let renamedHandler = source.replacingOccurrences(of: "\\b\(NSRegularExpression.escapedPattern(for: applyName))\\b", with: "RenamedNativeBridge", options: .regularExpression)
let renamedHandlerPatch = try patch.patchSource(renamedHandler)
precondition(renamedHandlerPatch.contains("apply:(model,effort,tier)=>RenamedNativeBridge(model,effort,"))
func rejects(_ input: String) {
    do { _ = try patch.patchSource(input); preconditionFailure("必须拒绝不兼容或不唯一的界面结构") }
    catch { precondition(error is PatchFailure) }
}
rejects(source.replacingOccurrences(of: "selectComposerModelAndReasoningEffort:", with: "changedNativeSelector:"))
rejects(source + source)
let resources = try patch.replacements(archive)
precondition(resources.count == 4)
print("界面补丁范围、混淆变量改名、不兼容结构拒绝及入口资源验证通过。")
if CommandLine.arguments.count == 4 {
    try Data(patched.utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
}

for empty in ["", "{}", "{\"presets\":[]}", "{\"presets\":[{},{}]}", "{\"presets\":[{\"label\":\" \",\"model\":\"\"},{}]}"] {
    let parsed = try PresetConfiguration.parse(Data(empty.utf8))
    precondition(parsed == .defaults)
}
let custom = Data(#"{"presets":[{"label":"Astra","model":"gpt-6-astra","effort":"medium","speed":"standard"},{"label":"极速","model":"gpt-6-luna","effort":"max","speed":"fast"}]}"#.utf8)
let configuration = try PresetConfiguration.parse(custom)
precondition(configuration.presets[0] == ModelPreset(label: "Astra", model: "gpt-6-astra", effort: "medium", speed: "standard"))
let decoded = try PresetConfiguration.parse(configuration.encoded())
precondition(decoded == configuration)
for invalid in ["[]", "{\"presets\":[{}]}", "{\"presets\":[{\"effort\":\"exhigh\"},{}]}", "{\"presets\":[{\"speed\":\"turbo\"},{}]}", "{\"presets\":[{\"model\":\"two words\"},{}]}", "{\"presets\":[{\"label\":1},{}]}"] {
    do { _ = try PresetConfiguration.parse(Data(invalid.utf8)); preconditionFailure("必须拒绝无效配置") }
    catch { precondition(error is PatchFailure) }
}
var configured = patch; configured.configuration = configuration
let script = String(decoding: try configured.replacements(archive)["webview/codex-model-presets.js"]!, as: UTF8.self)
precondition(script.hasPrefix("window.CodexModelPresetsConfig = "))
precondition(script.contains("gpt-6-astra"))
print("空配置和空字段默认值、自定义配置、JSON 往返、无效配置拒绝及配置注入验证通过。")
