(() => {
  if (window.__eisonBrowserAgentBridge) {
    return;
  }

  const PageController = window.PageAgentPageController?.PageController;
  if (!PageController) {
    console.error("[eisonAI] PageAgentPageController is unavailable.");
    return;
  }

  const controller = new PageController({
    enableMask: false,
    viewportExpansion: 0,
    keepSemanticTags: true,
    includeAttributes: ["data-*", "placeholder", "name", "type", "value"],
  });

  async function wait(milliseconds) {
    await new Promise((resolve) => setTimeout(resolve, milliseconds));
    return {
      success: true,
      message: `Waited ${milliseconds}ms.`,
    };
  }

  async function pressEnter(index) {
    if (typeof index === "number") {
      const element = window.PageAgentPageController.getElementByIndex(controller.selectorMap, index);
      element.focus({ preventScroll: true });
    }

    const target = document.activeElement instanceof HTMLElement ? document.activeElement : document.body;
    const keyboardOptions = {
      bubbles: true,
      cancelable: true,
      key: "Enter",
      code: "Enter",
      keyCode: 13,
      which: 13,
    };
    target.dispatchEvent(new KeyboardEvent("keydown", keyboardOptions));
    target.dispatchEvent(new KeyboardEvent("keypress", keyboardOptions));
    target.dispatchEvent(new KeyboardEvent("keyup", keyboardOptions));
    if (typeof target.blur === "function") {
      target.blur();
    }

    return {
      success: true,
      message: "Pressed Enter on the current focus target.",
    };
  }

  window.__eisonBrowserAgentBridge = {
    async call(command, payload = {}) {
      switch (command) {
        case "observe":
          return controller.getBrowserState();
        case "click":
          return controller.clickElement(Number(payload.index));
        case "input":
          return controller.inputText(Number(payload.index), String(payload.text ?? ""));
        case "select":
          return controller.selectOption(Number(payload.index), String(payload.option ?? ""));
        case "scroll":
          return controller.scroll({
            down: String(payload.direction ?? "down").toLowerCase() !== "up",
            numPages: Math.max(1, Number(payload.pages ?? 1)),
            index: Number.isFinite(payload.index) ? Number(payload.index) : undefined,
          });
        case "wait":
          return wait(Math.max(250, Number(payload.milliseconds ?? 800)));
        case "pressEnter":
          return pressEnter(Number.isFinite(payload.index) ? Number(payload.index) : undefined);
        default:
          throw new Error(`Unsupported browser-agent command: ${command}`);
      }
    },
  };
})();
