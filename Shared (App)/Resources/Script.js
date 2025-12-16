function show(platform, enabled, useSettingsInsteadOfPreferences) {
  document.body.classList.add(`platform-${platform}`);

  if (useSettingsInsteadOfPreferences) {
    document.getElementsByClassName("platform-mac state-on")[0].innerText =
      "eisonAI’s extension is currently on. You can turn it off in the Extensions section of Safari Settings.";
    document.getElementsByClassName("platform-mac state-off")[0].innerText =
      "eisonAI’s extension is currently off. You can turn it on in the Extensions section of Safari Settings.";
    document.getElementsByClassName("platform-mac state-unknown")[0].innerText =
      "You can turn on eisonAI’s extension in the Extensions section of Safari Settings.";
    document.getElementsByClassName("platform-mac open-preferences")[0].innerText =
      "Quit and Open Safari Settings…";
  }

  if (typeof enabled === "boolean") {
    document.body.classList.toggle("state-on", enabled);
    document.body.classList.toggle("state-off", !enabled);
  } else {
    document.body.classList.remove("state-on");
    document.body.classList.remove("state-off");
  }
}

function openPreferences() {
  webkit.messageHandlers.controller.postMessage("open-preferences");
}

function setSystemPromptFromNative(payload) {
  const prompt = typeof payload?.prompt === "string" ? payload.prompt : "";
  const status = typeof payload?.status === "string" ? payload.status : "";

  const textarea = document.getElementById("system-prompt");
  if (textarea) textarea.value = prompt;

  const statusEl = document.getElementById("system-prompt-status");
  if (statusEl) statusEl.textContent = status;
}

function postNative(command, payload = {}) {
  try {
    webkit.messageHandlers.controller.postMessage({ command, ...payload });
  } catch (err) {
    console.error("Failed to post native message:", err);
  }
}

document.addEventListener("DOMContentLoaded", () => {
  const button = document.querySelector("button.open-preferences");
  button?.addEventListener("click", openPreferences);

  const textarea = document.getElementById("system-prompt");
  const save = document.getElementById("save-system-prompt");
  const reset = document.getElementById("reset-system-prompt");
  const statusEl = document.getElementById("system-prompt-status");

  save?.addEventListener("click", () => {
    const prompt = textarea?.value ?? "";
    if (statusEl) statusEl.textContent = "Saving…";
    postNative("setSystemPrompt", { prompt });
  });

  reset?.addEventListener("click", () => {
    if (statusEl) statusEl.textContent = "Resetting…";
    postNative("resetSystemPrompt");
  });
});
