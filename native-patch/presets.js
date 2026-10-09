/* Local UI patch. No network calls or simulated input. */
(() => {
  const defaults = [
    { label: "Sol", model: "gpt-6.1-sol", effort: "xhigh", speed: "standard" },
    { label: "Luna", model: "gpt-6-luna", effort: "max", speed: "fast" },
  ];
  const presets = (window.CodexModelPresetsConfig?.presets ?? defaults).map((p, id) => ({ ...p, id, tier: p.speed === "fast" ? "priority" : null }));
  const speed = tier => tier === "priority" || tier === "fast" ? "fast" : tier ?? null;
  const matches = (p, preset) => p.model === preset.model && p.effort === preset.effort && speed(p.tier) === speed(preset.tier);

  function Buttons({ jsx, react, settings }) {
    const [pending, setPending] = react.useState(null);
    const [error, setError] = react.useState("");
    const latest = react.useRef(settings);
    const mounted = react.useRef(true);
    const inFlight = react.useRef(false);
    latest.current = settings;
    react.useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
    react.useEffect(() => {
      if (!pending?.committed) return;
      if (matches(settings, pending.preset)) {
        inFlight.current = false;
        setPending(null);
        settings.onComplete();
        return;
      }
      const timer = setTimeout(() => {
        inFlight.current = false;
        setPending(null);
        setError("设置未得到确认，请检查原模型菜单。");
      }, 10000);
      return () => clearTimeout(timer);
    }, [pending, settings.model, settings.effort, settings.tier]);

    async function select(preset) {
      if (inFlight.current) return;
      const p = latest.current;
      if (p.onBeforeSelectModel(preset.model) === false) return;
      if (matches(p, preset)) { p.onComplete(); return; }
      inFlight.current = true;
      setError("");
      setPending({ preset, committed: false });
      try {
        p.onSelectModelOption();
        const selected = await p.apply(preset.model, preset.effort, preset.tier);
        if (selected !== true) throw new Error("模型切换失败或被取消。");
        if (!mounted.current) return;
        // Codex may queue a model change for the next turn while a reply runs.
        // Its native tier setter also handles that queue and new-chat drafts.
        if (await latest.current.setTier(preset.tier, "composer_menu") !== true)
          throw new Error("模型已选择，但速度设置失败，请检查原模型菜单。");
        if (mounted.current) setPending({ preset, committed: true });
      } catch (e) {
        if (mounted.current) { inFlight.current = false; setPending(null); setError(e.message || "切换失败。"); }
      }
    }

    return jsx.jsxs("span", {
      className: "codex-model-presets", "aria-label": "模型预设",
      children: [
        ...presets.map(base => {
          const fast = settings.tiers?.find(t => t.iconKind === "fast" || t.value === "priority" || t.value === "fast");
          const preset = base.tier === null ? base : { ...base, tier: fast?.value ?? base.tier };
          const option = settings.options?.find(o => o.model.model === preset.model);
          const model = settings.models?.find(m => m.model === preset.model);
          const supported = model?.supportedReasoningEfforts?.some(e => e.reasoningEffort === preset.effort);
          const tierAllowed = preset.tier === null || settings.tiers?.some(t => t.value === preset.tier);
          const disabled = settings.disabled || !!pending || !model || !supported || !option || option.disabledReason != null || !tierAllowed;
          return jsx.jsx("button", {
            type: "button", disabled, title: error || `${model?.displayName ?? preset.model} · ${preset.effort} · ${preset.speed === "fast" ? "Fast" : "Standard"}`,
            "aria-label": `${preset.label}：${preset.model} · ${preset.effort} · ${preset.speed}`, "aria-pressed": matches(settings, preset),
            onClick: () => select(preset),
            children: pending?.preset.id === preset.id ? `${preset.label}…` : preset.label,
          }, String(preset.id));
        }),
        error ? jsx.jsx("span", { role: "alert", className: "codex-model-presets-error", children: error }) : null,
      ],
    });
  }

  window.CodexModelPresets = {
    render(jsx, react, original, settings) {
      return jsx.jsxs(jsx.Fragment, { children: [original, jsx.jsx(Buttons, { jsx, react, settings }, settings.conversationId ?? "draft")] });
    },
  };
})();
