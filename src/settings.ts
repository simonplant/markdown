import { invoke } from "@tauri-apps/api/core";

// ---------------------------------------------------------------------------
// Cloud AI settings types
// ---------------------------------------------------------------------------

export interface CloudAiConfig {
  provider: string;
  endpoint_url: string;
  model: string;
  use_cloud: boolean;
}

const DEFAULT_ENDPOINTS: Record<string, string> = {
  openai: "https://api.openai.com",
  anthropic: "https://api.anthropic.com",
  ollama: "http://localhost:11434",
  custom: "",
};

const DEFAULT_MODELS: Record<string, string> = {
  openai: "gpt-4o",
  anthropic: "claude-sonnet-4-20250514",
  ollama: "llama3",
  custom: "",
};

// ---------------------------------------------------------------------------
// Settings state
// ---------------------------------------------------------------------------

let currentConfig: CloudAiConfig | null = null;
let settingsOpen = false;

export function getCloudConfig(): CloudAiConfig | null {
  return currentConfig;
}

export async function loadSettings(): Promise<CloudAiConfig | null> {
  try {
    const config = await invoke<CloudAiConfig | null>("load_ai_settings");
    currentConfig = config;
    return config;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Settings modal UI
// ---------------------------------------------------------------------------

function createSettingsModal(): HTMLElement {
  const overlay = document.createElement("div");
  overlay.id = "settings-overlay";
  overlay.style.cssText =
    "position:fixed;inset:0;background:rgba(0,0,0,0.4);z-index:100;display:flex;align-items:center;justify-content:center;";

  const card = document.createElement("div");
  card.id = "settings-card";
  card.style.cssText =
    "background:var(--settings-bg,#fff);border-radius:8px;padding:24px;width:420px;max-width:90vw;box-shadow:0 8px 32px rgba(0,0,0,0.2);color:var(--settings-fg,#24292F);font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Segoe UI',Roboto,sans-serif;font-size:14px;";

  const config = currentConfig || {
    provider: "openai",
    endpoint_url: DEFAULT_ENDPOINTS.openai,
    model: DEFAULT_MODELS.openai,
    use_cloud: false,
  };

  card.innerHTML = `
    <h2 style="margin:0 0 16px;font-size:18px;">AI Provider Settings</h2>

    <label style="display:block;margin-bottom:4px;font-weight:600;">Provider</label>
    <select id="settings-provider" style="width:100%;padding:6px 8px;margin-bottom:12px;border:1px solid var(--settings-border,#D0D7DE);border-radius:4px;background:var(--settings-input-bg,#fff);color:inherit;font-size:14px;">
      <option value="openai" ${config.provider === "openai" ? "selected" : ""}>OpenAI</option>
      <option value="anthropic" ${config.provider === "anthropic" ? "selected" : ""}>Anthropic</option>
      <option value="ollama" ${config.provider === "ollama" ? "selected" : ""}>Ollama</option>
      <option value="custom" ${config.provider === "custom" ? "selected" : ""}>Custom (OpenAI-compatible)</option>
    </select>

    <label style="display:block;margin-bottom:4px;font-weight:600;">API Key</label>
    <input id="settings-api-key" type="password" placeholder="Stored in OS keychain" style="width:100%;padding:6px 8px;margin-bottom:12px;border:1px solid var(--settings-border,#D0D7DE);border-radius:4px;box-sizing:border-box;background:var(--settings-input-bg,#fff);color:inherit;font-size:14px;" />

    <label id="settings-endpoint-label" style="display:block;margin-bottom:4px;font-weight:600;">Endpoint URL</label>
    <input id="settings-endpoint" type="text" value="${config.endpoint_url}" style="width:100%;padding:6px 8px;margin-bottom:12px;border:1px solid var(--settings-border,#D0D7DE);border-radius:4px;box-sizing:border-box;background:var(--settings-input-bg,#fff);color:inherit;font-size:14px;" />

    <label style="display:block;margin-bottom:4px;font-weight:600;">Model</label>
    <input id="settings-model" type="text" value="${config.model}" style="width:100%;padding:6px 8px;margin-bottom:12px;border:1px solid var(--settings-border,#D0D7DE);border-radius:4px;box-sizing:border-box;background:var(--settings-input-bg,#fff);color:inherit;font-size:14px;" />

    <div style="display:flex;align-items:center;margin-bottom:16px;">
      <input id="settings-use-cloud" type="checkbox" ${config.use_cloud ? "checked" : ""} style="margin-right:8px;" />
      <label for="settings-use-cloud" style="font-weight:600;">Use cloud AI (instead of local)</label>
    </div>

    <div id="settings-status" style="margin-bottom:12px;font-size:13px;color:#6E7781;min-height:20px;"></div>

    <div style="display:flex;gap:8px;justify-content:flex-end;">
      <button id="settings-delete-key" style="margin-right:auto;padding:6px 14px;border:1px solid #cf222e;border-radius:4px;background:transparent;color:#cf222e;cursor:pointer;font-size:14px;">Remove Key</button>
      <button id="settings-cancel" style="padding:6px 14px;border:1px solid var(--settings-border,#D0D7DE);border-radius:4px;background:transparent;color:inherit;cursor:pointer;font-size:14px;">Cancel</button>
      <button id="settings-save" style="padding:6px 14px;border:none;border-radius:4px;background:#0969DA;color:#fff;cursor:pointer;font-size:14px;">Save</button>
    </div>
  `;

  overlay.appendChild(card);

  // Wire provider dropdown to update defaults
  const providerSelect = card.querySelector("#settings-provider") as HTMLSelectElement;
  const endpointInput = card.querySelector("#settings-endpoint") as HTMLInputElement;
  const modelInput = card.querySelector("#settings-model") as HTMLInputElement;

  function updateVisibility(): void {
    const p = providerSelect.value;
    // Endpoint URL is always shown; update placeholder to guide the user
    if (p === "openai" || p === "anthropic") {
      endpointInput.placeholder = DEFAULT_ENDPOINTS[p];
    } else {
      endpointInput.placeholder = "Enter endpoint URL";
    }
  }

  providerSelect.addEventListener("change", () => {
    const p = providerSelect.value;
    // Only update defaults if field matches previous default
    const prevProvider = config.provider;
    if (
      endpointInput.value === "" ||
      endpointInput.value === DEFAULT_ENDPOINTS[prevProvider]
    ) {
      endpointInput.value = DEFAULT_ENDPOINTS[p] || "";
    }
    if (
      modelInput.value === "" ||
      modelInput.value === DEFAULT_MODELS[prevProvider]
    ) {
      modelInput.value = DEFAULT_MODELS[p] || "";
    }
    config.provider = p;
    updateVisibility();
  });

  updateVisibility();

  // Load existing API key indicator
  invoke<string>("load_api_key")
    .then((key) => {
      if (key) {
        (card.querySelector("#settings-api-key") as HTMLInputElement).placeholder =
          "\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022 (key stored in keychain)";
      }
    })
    .catch(() => {});

  // Close on overlay click
  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) closeSettings();
  });

  // Cancel button
  card.querySelector("#settings-cancel")!.addEventListener("click", closeSettings);

  // Delete key button
  card.querySelector("#settings-delete-key")!.addEventListener("click", async () => {
    const statusEl = card.querySelector("#settings-status") as HTMLElement;
    try {
      await invoke("delete_api_key");
      statusEl.textContent = "API key removed. AI will use local inference.";
      statusEl.style.color = "#cf222e";
      (card.querySelector("#settings-api-key") as HTMLInputElement).placeholder =
        "Stored in OS keychain";
      (card.querySelector("#settings-use-cloud") as HTMLInputElement).checked = false;
      currentConfig = currentConfig
        ? { ...currentConfig, use_cloud: false }
        : null;
      updateAiStatusIndicator();
    } catch (err) {
      statusEl.textContent = `Failed to remove key: ${err}`;
      statusEl.style.color = "#cf222e";
    }
  });

  // Save button
  card.querySelector("#settings-save")!.addEventListener("click", async () => {
    const statusEl = card.querySelector("#settings-status") as HTMLElement;
    const apiKeyInput = card.querySelector("#settings-api-key") as HTMLInputElement;
    const apiKey = apiKeyInput.value;

    const newConfig: CloudAiConfig = {
      provider: providerSelect.value,
      endpoint_url:
        endpointInput.value || DEFAULT_ENDPOINTS[providerSelect.value] || "",
      model: modelInput.value || DEFAULT_MODELS[providerSelect.value] || "",
      use_cloud: (card.querySelector("#settings-use-cloud") as HTMLInputElement)
        .checked,
    };

    try {
      // Save API key to keychain if provided
      if (apiKey) {
        await invoke("save_api_key", { key: apiKey });
        apiKeyInput.value = "";
        apiKeyInput.placeholder =
          "\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022 (key stored in keychain)";
      }

      // Save config
      await invoke("save_ai_settings", { config: newConfig });
      currentConfig = newConfig;

      statusEl.textContent = "Settings saved.";
      statusEl.style.color = "#1a7f37";
      updateAiStatusIndicator();

      setTimeout(closeSettings, 600);
    } catch (err) {
      statusEl.textContent = `Error: ${err}`;
      statusEl.style.color = "#cf222e";
    }
  });

  return overlay;
}

export function openSettings(): void {
  if (settingsOpen) return;
  settingsOpen = true;
  const modal = createSettingsModal();
  document.body.appendChild(modal);
}

function closeSettings(): void {
  settingsOpen = false;
  const overlay = document.getElementById("settings-overlay");
  if (overlay) overlay.remove();
}

// ---------------------------------------------------------------------------
// AI status indicator in status bar
// ---------------------------------------------------------------------------

export function updateAiStatusIndicator(): void {
  const el = document.getElementById("stat-ai-mode");
  if (!el) return;

  if (currentConfig?.use_cloud) {
    const providerName =
      currentConfig.provider.charAt(0).toUpperCase() +
      currentConfig.provider.slice(1);
    el.textContent = `AI: ${providerName}`;
    el.title = `Cloud AI via ${providerName} (${currentConfig.model})`;
    el.style.opacity = "1";
  } else {
    el.textContent = "AI: Local";
    el.title = "Using local on-device AI model";
    el.style.opacity = "1";
  }
}
