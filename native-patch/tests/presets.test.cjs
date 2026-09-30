const { test, afterEach } = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const React = require("react");
const jsx = require("react/jsx-runtime");
const { JSDOM } = require("jsdom");
const { createRoot } = require("react-dom/client");
const dom = new JSDOM("<div id='root'></div>", { runScripts: "outside-only" });
global.window = dom.window; global.document = window.document;
global.IS_REACT_ACT_ENVIRONMENT = true;
window.eval(readFileSync(require.resolve("../presets.js"), "utf8"));
let root;
afterEach(async () => { if (root) await React.act(() => root.unmount()); root = null; });

async function setup(overrides = {}) {
  const calls = [];
  let state = {
    conversationId: "current-chat", model: "gpt-6.1-sol", effort: "medium", tier: null, disabled: false,
    models: [{ model: "gpt-6.1-sol", supportedReasoningEfforts: [{ reasoningEffort: "xhigh" }] },
      { model: "gpt-6-luna", supportedReasoningEfforts: [{ reasoningEffort: "max" }] }],
    options: [{ model: { model: "gpt-6.1-sol" } }, { model: { model: "gpt-6-luna" } }],
    tiers: [{ value: null }, { value: "priority", iconKind: "fast" }],
    onBeforeSelectModel: () => true,
    onSelectModelOption: () => calls.push(["explicit"]),
    onComplete: () => calls.push(["close-and-focus"]),
    apply: async (model, effort, tier) => { calls.push(["apply", model, effort, tier]); update({ model, effort }); return true; },
    setTier: async tier => { calls.push(["tier", tier]); update({ tier }); return true; },
    ...overrides,
  };
  root = createRoot(document.getElementById("root"));
  function render() { root.render(window.CodexModelPresets.render(jsx, React, jsx.jsx("span", { children: "原模型菜单" }), state)); }
  function update(change) { state = { ...state, ...change }; render(); }
  await React.act(render);
  const button = label => [...document.querySelectorAll("button")].find(b => b.textContent.startsWith(label));
  const click = label => React.act(async () => { button(label).dispatchEvent(new window.MouseEvent("click", { bubbles: true })); });
  return { calls, button, click, update };
}

test("Luna commits current-chat model, Max, Fast and then closes/focuses", async () => {
  const h = await setup(); await h.click("Luna");
  assert.deepEqual(h.calls, [["explicit"], ["apply", "gpt-6-luna", "max", "priority"], ["tier", "priority"], ["close-and-focus"]]);
  assert.equal(h.button("Luna").getAttribute("aria-pressed"), "true");
  assert.equal(document.querySelectorAll("button").length, 2);
});
test("Sol clears Fast and applies XHigh", async () => {
  const h = await setup({ model: "gpt-6-luna", effort: "max", tier: "priority" }); await h.click("Sol");
  assert.deepEqual(h.calls, [["explicit"], ["apply", "gpt-6.1-sol", "xhigh", null], ["tier", null], ["close-and-focus"]]);
});
test("Fast uses the native catalog's concrete tier id", async () => {
  const h = await setup({ tiers: [{ value: null }, { value: "fast", iconKind: "fast" }] }); await h.click("Luna");
  assert.equal(h.calls[1][3], "fast");
  assert.equal(h.button("Luna").getAttribute("aria-pressed"), "true");
});
test("matching preset only closes the picker and restores focus", async () => {
  const h = await setup({ effort: "xhigh" }); await h.click("Sol");
  assert.deepEqual(h.calls, [["close-and-focus"]]);
});
test("native eligibility cancellation prevents all writes", async () => {
  const h = await setup({ onBeforeSelectModel: () => false }); await h.click("Luna");
  assert.deepEqual(h.calls, []);
});
test("failed model write keeps focus unchanged and reports error", async () => {
  const h = await setup({ apply: async () => false }); await h.click("Luna");
  assert.deepEqual(h.calls, [["explicit"]]);
  assert.match(document.querySelector('[role="alert"]').textContent, /失败/);
});
test("failed speed write cannot be presented as success", async () => {
  const h = await setup({ setTier: async () => false }); await h.click("Luna");
  assert.ok(!h.calls.some(c => c[0] === "close-and-focus"));
  assert.match(document.querySelector('[role="alert"]').textContent, /速度设置失败/);
});
test("RPC success alone does not complete; all displayed settings must match", async () => {
  const h = await setup({ apply: async () => true, setTier: async () => true }); await h.click("Luna");
  assert.ok(!h.calls.some(c => c[0] === "close-and-focus"));
  await React.act(() => h.update({ model: "gpt-6-luna", effort: "max", tier: "priority" }));
  assert.equal(h.calls.filter(c => c[0] === "close-and-focus").length, 1);
});
test("locked/loading composer, unavailable model/effort and missing Fast disable buttons", async () => {
  const h = await setup({ disabled: true }); assert.ok(h.button("Sol").disabled); assert.ok(h.button("Luna").disabled);
  await React.act(() => h.update({ disabled: false, tiers: [{ value: null }] }));
  assert.equal(h.button("Sol").disabled, false); assert.ok(h.button("Luna").disabled);
  await React.act(() => h.update({ models: [] })); assert.ok(h.button("Sol").disabled);
});
test("leaving the chat during a model write prevents further writes or stale focus", async () => {
  let finish;
  const h = await setup({ apply: () => new Promise(resolve => { finish = resolve; }) });
  await h.click("Luna"); await React.act(() => root.unmount()); root = null;
  await React.act(async () => finish(true));
  assert.deepEqual(h.calls, [["explicit"]]);
});
