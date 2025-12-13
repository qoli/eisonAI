function show(platform, enabled, useSettingsInsteadOfPreferences) {
    document.body.classList.add(`platform-${platform}`);

    if (useSettingsInsteadOfPreferences) {
        document.getElementsByClassName('platform-mac state-on')[0].innerText = "eisonAI’s extension is currently on. You can turn it off in the Extensions section of Safari Settings.";
        document.getElementsByClassName('platform-mac state-off')[0].innerText = "eisonAI’s extension is currently off. You can turn it on in the Extensions section of Safari Settings.";
        document.getElementsByClassName('platform-mac state-unknown')[0].innerText = "You can turn on eisonAI’s extension in the Extensions section of Safari Settings.";
        document.getElementsByClassName('platform-mac open-preferences')[0].innerText = "Quit and Open Safari Settings…";
    }

    if (typeof enabled === "boolean") {
        document.body.classList.toggle(`state-on`, enabled);
        document.body.classList.toggle(`state-off`, !enabled);
    } else {
        document.body.classList.remove(`state-on`);
        document.body.classList.remove(`state-off`);
    }
}

function openPreferences() {
    webkit.messageHandlers.controller.postMessage("open-preferences");
}

document.querySelector("button.open-preferences").addEventListener("click", openPreferences);

function sendAppCommand(command) {
    try {
        webkit.messageHandlers.controller.postMessage({ command });
    } catch (e) {
        console.warn("Failed to send app command:", command, e);
    }
}

function updateModelStatus(status) {
    const statusElem = document.getElementById("ModelStatusText");
    const progressElem = document.getElementById("ModelDownloadProgress");
    const downloadButton = document.getElementById("DownloadModelButton");
    const cancelButton = document.getElementById("CancelDownloadButton");

    if (!statusElem || !progressElem || !downloadButton || !cancelButton) {
        return;
    }

    const state = status?.state || "unknown";
    const progress = typeof status?.progress === "number" ? status.progress : 0;
    const error = status?.error || null;

    let label = `Model status: ${state}`;
    if (state === "downloading" || state === "verifying") {
        label = `Model status: ${state} (${Math.round(progress * 100)}%)`;
    }
    if (state === "failed" && error) {
        label = `Model status: failed (${error})`;
    }

    statusElem.innerText = label;

    if (state === "downloading" || state === "verifying") {
        progressElem.hidden = false;
        progressElem.value = Math.min(Math.max(progress, 0), 1);
        downloadButton.disabled = true;
        cancelButton.hidden = false;
    } else if (state === "ready") {
        progressElem.hidden = true;
        downloadButton.disabled = true;
        downloadButton.innerText = "Installed";
        cancelButton.hidden = true;
    } else {
        progressElem.hidden = true;
        downloadButton.disabled = false;
        downloadButton.innerText = "Download Model";
        cancelButton.hidden = true;
    }
}

document.addEventListener("DOMContentLoaded", () => {
    const downloadButton = document.getElementById("DownloadModelButton");
    const cancelButton = document.getElementById("CancelDownloadButton");

    if (downloadButton) {
        downloadButton.addEventListener("click", () => sendAppCommand("model.download"));
    }

    if (cancelButton) {
        cancelButton.addEventListener("click", () => sendAppCommand("model.cancel"));
    }

    sendAppCommand("model.getStatus");
});
