(() => {
  const STEPS = ["Source", "Configure", "Build", "Review"];

  const state = {
    step: 0,
    isoPath: "",
    architecture: "Unknown",
    editions: [],
    probeError: "",
    edition: "Host",
    keepGaming: false,
    keepCopilot: false,
    windhawk: true,
    yasb: true,
    komorebi: true,
    nilesoft: false,
    browsers: new Set(),
    editors: new Set(),
    wsl: new Set(),
    formFactor: "Auto",
    busy: false,
    profilePath: "",
    buildResult: null,
    deltaSummary: null
  };

  const BROWSERS = [
    ["zen-browser", "Zen"],
    ["helium", "Helium"],
    ["firefox-developer-edition", "Firefox Dev"],
    ["brave", "Brave"],
    ["edge", "Edge"]
  ];
  const EDITORS = [
    ["cursor", "Cursor"],
    ["vscode", "VS Code"],
    ["zed", "Zed"],
    ["antigravity", "Antigravity"],
    ["neovim", "Neovim"]
  ];
  const WSL = [
    ["Ubuntu", "Ubuntu"],
    ["FedoraLinux", "Fedora"],
    ["archlinux", "Arch"],
    ["NixOS-WSL", "NixOS"],
    ["pengwin", "Pengwin"]
  ];
  const EDITIONS = ["Host", "Home", "Pro", "Enterprise", "Education", "SingleLanguage", "All"];
  const FORM_FACTORS = ["Auto", "Laptop", "Desktop"];

  const $root = document.getElementById("wizard-root");
  const $main = document.getElementById("wizard-main");
  const $progressFill = document.getElementById("progress-fill");
  const $stageLabel = document.getElementById("stage-label");
  const $titlebar = document.getElementById("wizard-titlebar");
  const $maximize = document.getElementById("btn-maximize");
  const $back = document.getElementById("btn-back");
  const $next = document.getElementById("btn-next");

  function parseHostMessage(raw) {
    if (raw == null) return null;
    if (typeof raw === "string") {
      try {
        return JSON.parse(raw);
      } catch {
        return null;
      }
    }
    if (typeof raw === "object") return raw;
    return null;
  }

  function hasHost() {
    return !!(window.chrome && window.chrome.webview);
  }

  function postWindow(action) {
    if (!hasHost()) return;
    window.chrome.webview.postMessage(JSON.stringify({ type: "windowControl", action }));
  }

  function setMaximizeUi(state) {
    if (!$maximize) return;
    const maximized = state === "maximized";
    $maximize.querySelector(".icon-maximize")?.classList.toggle("hidden", maximized);
    $maximize.querySelector(".icon-restore")?.classList.toggle("hidden", !maximized);
    $maximize.setAttribute("aria-label", maximized ? "Restore window" : "Maximize window");
  }

  function initChrome() {
    if (!hasHost()) {
      $root?.classList.add("is-browser");
      return;
    }

    document.getElementById("window-controls")?.addEventListener("click", (event) => {
      const btn = event.target.closest("[data-action]");
      if (!btn) return;
      postWindow(btn.getAttribute("data-action"));
    });

    $titlebar?.addEventListener("dblclick", (event) => {
      if (event.target.closest(".titlebar-controls")) return;
      postWindow("maximize");
    });

    window.chrome.webview.addEventListener("message", (event) => {
      const data = parseHostMessage(event.data);
      if (data?.type === "windowState") {
        setMaximizeUi(data.state);
      }
    });
  }

  function post(type, payload = {}) {
    if (!hasHost()) {
      return Promise.resolve(mockHost(type, payload));
    }
    const id = nextMessageId();
    return new Promise((resolve, reject) => {
      const handler = (event) => {
        const data = parseHostMessage(event.data);
        if (!data || data.id !== id) return;
        window.chrome.webview.removeEventListener("message", handler);
        if (!data.ok) {
          reject(new Error(data.error || `${type} failed`));
          return;
        }
        resolve(data.body || {});
      };
      window.chrome.webview.addEventListener("message", handler);
      window.chrome.webview.postMessage(JSON.stringify({ id, type, ...payload }));
    });
  }

  function nextMessageId() {
    if (globalThis.crypto?.randomUUID) {
      return crypto.randomUUID();
    }
    return `msg-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  }

  function mockHost(type, payload) {
    if (type === "pickIso") return Promise.resolve({ cancelled: true });
    if (type === "getRepoRoot") return Promise.resolve({ repoRoot: "." });
    if (type === "saveWizardSettings") return Promise.resolve({ path: "output/gui/wizard-settings.json" });
    if (type === "saveIntent") return Promise.resolve({ path: "output/gui/wizard-settings.json" });
    if (type === "generateProfile") return Promise.resolve({ profilePath: "output/gui/BuildProfile.json" });
    if (type === "startDryRun") {
      return Promise.resolve({
        Ok: true,
        DryRun: true,
        ManifestPath: "output/WinMint-BuildManifest.json",
        BuildDeltaPath: "output/WinMint-BuildDelta.json",
        ReportPath: "output/WinMint-BuildReport.json",
        Progress: [{ Stage: "dry-run", Message: "Preview complete" }]
      });
    }
    if (type === "readBuildDelta") {
      return Promise.resolve({ totalRecords: 0, userControlledRecords: 0, phaseCounts: {}, highlightedRecords: [] });
    }
    return Promise.resolve({});
  }

  function buildWizardSettings() {
    return {
      Profile: "WinMint",
      KeepEdge: false,
      KeepGaming: state.keepGaming,
      KeepCopilot: state.keepCopilot,
      ISOPath: state.isoPath,
      Architecture: state.architecture,
      ComputerName: "WinMint",
      AccountName: "dev",
      AccountMode: "Local",
      TargetDevice: "DifferentPC",
      FormFactor: state.formFactor,
      Edition: state.edition,
      DriverSource: "None",
      DriverPath: "",
      InstallWindhawk: state.windhawk,
      InstallYasb: state.yasb,
      InstallKomorebi: state.komorebi,
      InstallNilesoft: state.nilesoft,
      Editors: [...state.editors],
      Browsers: [...state.browsers],
      Wsl2Distros: [...state.wsl],
      PrivLocation: true,
      TweakHardwareBypass: false,
      TweakDmaInterop: true
    };
  }

  async function persistWizardSettings() {
    const settings = buildWizardSettings();
    await post("saveWizardSettings", { settings });
  }

  function setBusy(busy) {
    state.busy = busy;
    if ($back) $back.disabled = busy || state.step === 0;
    if ($next) $next.disabled = busy || !canNext();
  }

  function panel(label, content) {
    return el("div", { className: "wizard-panel" }, [
      el("p", { className: "wizard-panel-muted", text: label }),
      content
    ]);
  }

  function chipRow(label, values, selected, onPick) {
    const row = document.createElement("div");
    row.className = "chip-row";
    values.forEach((value) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = `chip${selected === value ? " is-on" : ""}`;
      btn.textContent = value === "SingleLanguage" ? "Single Language" : value;
      btn.onclick = () => onPick(value);
      row.appendChild(btn);
    });
    return panel(label, row);
  }

  function toggleRow(label, items, selectedSet, onToggle) {
    const row = document.createElement("div");
    row.className = "toggle-row";
    items.forEach(([value, text]) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = `toggle${selectedSet.has(value) ? " is-on" : ""}`;
      btn.textContent = text;
      btn.onclick = () => onToggle(value);
      row.appendChild(btn);
    });
    return panel(label, row);
  }

  function el(tag, attrs = {}, children = []) {
    const node = document.createElement(tag);
    Object.entries(attrs).forEach(([key, value]) => {
      if (key === "className") node.className = value;
      else if (key === "text") node.textContent = value;
      else node.setAttribute(key, value);
    });
    children.forEach((child) => {
      if (typeof child === "string") node.appendChild(document.createTextNode(child));
      else if (child) node.appendChild(child);
    });
    return node;
  }

  function mainWrap(children) {
    const inner = el("div", { className: "wizard-main-inner" }, children.filter(Boolean));
    $main.replaceChildren(inner);
  }

  function renderNav() {
    const pct = ((state.step + 1) / STEPS.length) * 100;
    if ($progressFill) $progressFill.style.width = `${pct}%`;
    if ($stageLabel) $stageLabel.textContent = STEPS[state.step];
  }

  function renderSource() {
    const browse = el("button", { className: "btn btn-primary", type: "button", text: state.isoPath ? "Change ISO" : "Choose ISO" });
    browse.disabled = state.busy;
    browse.onclick = async () => {
      if (state.busy) return;
      setBusy(true);
      try {
        const result = await post("pickIso");
        if (result.cancelled) {
          return;
        }
        state.isoPath = result.path || "";
        state.probeError = "";
        state.editions = [];
        const probe = await post("probeIso", { path: state.isoPath });
        state.architecture = probe.Architecture || probe.architecture || "Unknown";
        state.editions = probe.Editions || probe.editions || [];
        if (probe.Ok === false) {
          state.probeError = probe.Error || probe.error || "Probe failed";
        }
      } catch (error) {
        state.probeError = error.message;
      } finally {
        setBusy(false);
        render();
      }
    };

    const stage = el("div", { className: `iso-stage${state.isoPath ? " is-selected" : ""}` }, [
      el("p", {
        className: `iso-path${state.isoPath ? "" : " is-empty"}`,
        text: state.isoPath || "No ISO selected"
      }),
      browse
    ]);

    if (state.isoPath) {
      stage.appendChild(el("div", { className: "iso-meta" }, [
        summaryRow("Architecture", state.architecture),
        summaryRow("Editions", state.editions.join(", ") || "—"),
        state.probeError ? el("div", { className: "callout", text: state.probeError }) : null
      ].filter(Boolean)));
    }

    mainWrap([
      el("h1", { className: "wizard-hero-title", text: "Choose your Windows ISO" }),
      el("p", { className: "wizard-hero-sub", text: "WinMint services the official image you provide. Pick a source file to probe architecture and editions." }),
      stage
    ]);
  }

  function renderConfigure() {
    mainWrap([
      el("h1", { className: "wizard-hero-title", text: "Configure the build" }),
      el("p", { className: "wizard-hero-sub", text: "Adjust what stays on the image and what FirstLogon installs. Defaults already reflect the WinMint posture." }),
      el("div", { className: "wizard-columns" }, [
        chipRow("Edition", EDITIONS, state.edition, async (value) => {
          state.edition = value;
          await persistWizardSettings();
          render();
        }),
        chipRow("Form factor", FORM_FACTORS, state.formFactor, async (value) => {
          state.formFactor = value;
          await persistWizardSettings();
          render();
        }),
        toggleRow("Keep", [["gaming", "Xbox & gaming"], ["copilot", "Copilot"]], new Set([
          ...(state.keepGaming ? ["gaming"] : []),
          ...(state.keepCopilot ? ["copilot"] : [])
        ]), async (value) => {
          if (value === "gaming") state.keepGaming = !state.keepGaming;
          if (value === "copilot") state.keepCopilot = !state.keepCopilot;
          await persistWizardSettings();
          render();
        }),
        toggleRow("Browsers", BROWSERS, state.browsers, async (value) => {
          if (state.browsers.has(value)) state.browsers.delete(value);
          else state.browsers.add(value);
          await persistWizardSettings();
          render();
        }),
        toggleRow("Editors", EDITORS, state.editors, async (value) => {
          if (state.editors.has(value)) state.editors.delete(value);
          else state.editors.add(value);
          await persistWizardSettings();
          render();
        }),
        toggleRow("Shell", [
          ["windhawk", "Windhawk"],
          ["yasb", "YASB"],
          ["komorebi", "Komorebi"],
          ["nilesoft", "Nilesoft"]
        ], new Set([
          ...(state.windhawk ? ["windhawk"] : []),
          ...(state.yasb ? ["yasb"] : []),
          ...(state.komorebi ? ["komorebi"] : []),
          ...(state.nilesoft ? ["nilesoft"] : [])
        ]), async (value) => {
          if (value === "windhawk") state.windhawk = !state.windhawk;
          if (value === "yasb") state.yasb = !state.yasb;
          if (value === "komorebi") state.komorebi = !state.komorebi;
          if (value === "nilesoft") state.nilesoft = !state.nilesoft;
          await persistWizardSettings();
          render();
        }),
        toggleRow("WSL", WSL, state.wsl, async (value) => {
          if (state.wsl.has(value)) state.wsl.delete(value);
          else state.wsl.add(value);
          await persistWizardSettings();
          render();
        })
      ])
    ]);
  }

  function summaryRow(label, value) {
    const row = el("div", { className: "summary-row" });
    row.append(el("span", {}, [label]), el("span", {}, [value || "—"]));
    return row;
  }

  function renderBuild() {
    const gen = el("button", { className: "btn btn-ghost", type: "button", text: "Generate profile" });
    const dry = el("button", { className: "btn btn-primary", type: "button", text: "Dry run" });
    gen.disabled = state.busy;
    dry.disabled = state.busy;

    gen.onclick = async () => {
      if (state.busy) return;
      setBusy(true);
      try {
        await persistWizardSettings();
        const result = await post("generateProfile");
        state.profilePath = result.profilePath || "";
      } catch (error) {
        state.probeError = error.message;
      } finally {
        setBusy(false);
        render();
      }
    };

    dry.onclick = async () => {
      if (state.busy) return;
      setBusy(true);
      try {
        if (!state.profilePath) {
          await persistWizardSettings();
          const profile = await post("generateProfile");
          state.profilePath = profile.profilePath || "";
        }
        const result = await post("startDryRun");
        state.buildResult = result;
        if (result.BuildDeltaPath || result.buildDeltaPath) {
          state.deltaSummary = await post("readBuildDelta", { path: result.BuildDeltaPath || result.buildDeltaPath });
        }
      } catch (error) {
        state.probeError = error.message;
      } finally {
        setBusy(false);
        render();
      }
    };

    const rows = [
      summaryRow("Source", state.isoPath),
      summaryRow("Architecture", state.architecture),
      summaryRow("Edition", state.edition),
      summaryRow("Profile", state.profilePath || state.buildResult?.ManifestPath || "—"),
      summaryRow("Manifest", state.buildResult?.ManifestPath || "—"),
      summaryRow("BuildDelta", state.buildResult?.BuildDeltaPath || "—"),
      summaryRow("Report", state.buildResult?.ReportPath || "—")
    ];

    mainWrap([
      el("h1", { className: "wizard-hero-title", text: "Preview the build" }),
      el("p", { className: "wizard-hero-sub", text: "Generate a profile, then run a dry build to inspect engine output without writing an ISO." }),
      el("div", { className: "iso-stage is-selected" }, [
        el("div", { className: "summary-grid" }, rows),
        el("div", { className: "wizard-actions" }, [gen, dry])
      ])
    ]);
  }

  function renderReview() {
    const delta = state.deltaSummary;
    const highlights = (delta?.highlightedRecords || []).map((record) =>
      el("li", {}, [`${record.title} (${record.phase}/${record.kind}) — ${record.changeCount} changes`])
    );
    mainWrap([
      el("h1", { className: "wizard-hero-title", text: "Review output" }),
      el("p", { className: "wizard-hero-sub", text: "Confirm generated artifacts and scan highlighted BuildDelta records." }),
      el("div", { className: "iso-stage is-selected" }, [
        el("div", { className: "summary-grid" }, [
          summaryRow("Profile", state.profilePath || "—"),
          summaryRow("Manifest", state.buildResult?.ManifestPath || "—"),
          summaryRow("BuildDelta", state.buildResult?.BuildDeltaPath || "—"),
          summaryRow("Report", state.buildResult?.ReportPath || "—"),
          summaryRow("Delta records", delta ? String(delta.totalRecords ?? 0) : "—"),
          summaryRow("User-controlled", delta ? String(delta.userControlledRecords ?? 0) : "—")
        ]),
        el("ul", { className: "delta-list" }, highlights)
      ])
    ]);
  }

  function canNext() {
    if (state.busy) return false;
    if (state.step === 0) return !!state.isoPath;
    return state.step < STEPS.length - 1;
  }

  function render() {
    renderNav();
    setBusy(state.busy);
    $next.textContent = state.step === STEPS.length - 1 ? "Finish" : "Continue";

    if (state.step === 0) renderSource();
    else if (state.step === 1) renderConfigure();
    else if (state.step === 2) renderBuild();
    else renderReview();
  }

  $back.onclick = () => {
    if (state.step > 0) {
      state.step -= 1;
      render();
    }
  };

  $next.onclick = async () => {
    if (state.step === 0 && !state.isoPath) return;
    if (state.step < STEPS.length - 1) {
      if (state.step === 0) {
        try {
          await persistWizardSettings();
        } catch (error) {
          state.probeError = error.message;
          render();
          return;
        }
      }
      state.step += 1;
      render();
      return;
    }
    if (hasHost()) window.close();
  };

  initChrome();
  render();
})();
