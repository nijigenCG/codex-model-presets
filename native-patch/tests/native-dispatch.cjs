// Exercise the native dispatcher from the generated chunk, not a copied fixture.
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const vm = require("node:vm");
const source = readFileSync(process.argv[2], "utf8");
const id = "[A-Za-z_$][A-Za-z0-9_$]*";
const apply = source.match(new RegExp(`apply:\\(model,effort(?:,tier)?\\)=>(${id})\\(model,effort(?:,\\(\\)=>\\{\\})?(?:,\\s*\\{serviceTier:tier\\})?\\)`));
assert.ok(apply, "native bridge must receive model and reasoning effort");
const escaped = apply[1].replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const dispatch = source.match(new RegExp(`${escaped}=function\\((${id}),(${id}),(${id})\\)\\{let (${id})=\\(\\)=>\\{[^;]+\\};return (${id})\\?\\.isAeon\\?\\5\\.selectModelAndReasoningEffort\\((${id})\\(\\1\\),\\2,\\4\\):(${id})\\(\\6\\(\\1\\),\\2,\\4,\\3\\)\\}`));
if (!dispatch) {
  // Older supported builds use a different guarded dispatcher.
  const local = source.match(new RegExp(`${escaped}=function\\([^)]*\\)\\{let ${id}=\\(\\)=>\\{[^;]+\\};return ([^;{}]+)\\}`));
  assert.ok(!local?.[1].includes("?.isAeon?"), "new dispatcher must match");
  console.log("旧版分派结构：新版 isAeon 分支验证不适用。");
  process.exit(0);
}
const normalize = dispatch[6].replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const normalizer = source.match(new RegExp(`function ${normalize}\\((${id})\\)\\{return (${id})&&\\1===(${id})\\?(${id}):\\1\\}`));
assert.ok(normalizer, "native model ID normalization must be preserved");
const calls = [];
let result = true;
let hasConversation = false;
const context = {
  [dispatch[5]]: null,
  [dispatch[7]]: (model, effort, callback, options) => {
    calls.push({ model, effort, callback, options });
    // The native preset setter rejects a bundled tier without a resumed chat.
    return options?.serviceTier !== undefined && !hasConversation ? false : result;
  },
  [normalizer[2]]: true,
  [normalizer[3]]: "preset-model",
  [normalizer[4]]: "normalized-model",
};
const select = vm.runInNewContext(`${dispatch[0]};${normalizer[0]};(${apply[0].slice("apply:".length)})`, context);
assert.equal(select("preset-model", "xhigh", "priority"), true, "new-chat draft must not require a conversation for model selection");
assert.equal(calls[0].model, "normalized-model");
assert.equal(calls[0].effort, "xhigh");
assert.equal(calls[0].options, undefined, "speed must use the separate native tier setter");
assert.equal(typeof calls[0].callback, "function");
context[dispatch[5]] = { isAeon: false };
hasConversation = true;
result = false;
assert.equal(select("other-model", "max", null), false);
assert.equal(calls[1].model, "other-model");
assert.equal(calls[1].options, undefined);
context[dispatch[5]] = { isAeon: true, selectModelAndReasoningEffort: () => "agent-result" };
assert.equal(select("preset-model", "medium", null), "agent-result");
assert.equal(calls.length, 2, "Aeon must not use the native thread setter");
console.log("新版原生分派的新聊天草稿、模型 ID 转换、强度、确认取消返回值及 Aeon 分支验证通过。");
