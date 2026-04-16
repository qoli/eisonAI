var PageAgentPageController = (function(exports) {
  "use strict";
  function isHTMLElement(el) {
    return !!el && el.nodeType === 1;
  }
  function isInputElement(el) {
    return el?.nodeType === 1 && el.tagName === "INPUT";
  }
  function isTextAreaElement(el) {
    return el?.nodeType === 1 && el.tagName === "TEXTAREA";
  }
  function isSelectElement(el) {
    return el?.nodeType === 1 && el.tagName === "SELECT";
  }
  function isAnchorElement(el) {
    return el?.nodeType === 1 && el.tagName === "A";
  }
  function getIframeOffset(element) {
    const frame = element.ownerDocument.defaultView?.frameElement;
    if (!frame) return { x: 0, y: 0 };
    const rect = frame.getBoundingClientRect();
    return { x: rect.left, y: rect.top };
  }
  function getNativeValueSetter(element) {
    return Object.getOwnPropertyDescriptor(Object.getPrototypeOf(element), "value").set;
  }
  async function waitFor(seconds) {
    await new Promise((resolve) => setTimeout(resolve, seconds * 1e3));
  }
  async function movePointerToElement(element, x, y) {
    const offset = getIframeOffset(element);
    window.dispatchEvent(
      new CustomEvent("PageAgent::MovePointerTo", {
        detail: { x: x + offset.x, y: y + offset.y }
      })
    );
    await waitFor(0.3);
  }
  async function clickPointer() {
    window.dispatchEvent(new CustomEvent("PageAgent::ClickPointer"));
  }
  async function enablePassThrough() {
    window.dispatchEvent(new CustomEvent("PageAgent::EnablePassThrough"));
  }
  async function disablePassThrough() {
    window.dispatchEvent(new CustomEvent("PageAgent::DisablePassThrough"));
  }
  function getElementByIndex(selectorMap, index) {
    const interactiveNode = selectorMap.get(index);
    if (!interactiveNode) {
      throw new Error(`No interactive element found at index ${index}`);
    }
    const element = interactiveNode.ref;
    if (!element) {
      throw new Error(`Element at index ${index} does not have a reference`);
    }
    if (!isHTMLElement(element)) {
      throw new Error(`Element at index ${index} is not an HTMLElement`);
    }
    return element;
  }
  let lastClickedElement = null;
  function blurLastClickedElement() {
    if (lastClickedElement) {
      lastClickedElement.dispatchEvent(new PointerEvent("pointerout", { bubbles: true }));
      lastClickedElement.dispatchEvent(new PointerEvent("pointerleave", { bubbles: false }));
      lastClickedElement.dispatchEvent(new MouseEvent("mouseout", { bubbles: true }));
      lastClickedElement.dispatchEvent(new MouseEvent("mouseleave", { bubbles: false }));
      lastClickedElement.blur();
      lastClickedElement = null;
    }
  }
  async function clickElement(element) {
    blurLastClickedElement();
    lastClickedElement = element;
    await scrollIntoViewIfNeeded(element);
    const frame = element.ownerDocument.defaultView?.frameElement;
    if (frame) await scrollIntoViewIfNeeded(frame);
    const rect = element.getBoundingClientRect();
    const x = rect.left + rect.width / 2;
    const y = rect.top + rect.height / 2;
    await movePointerToElement(element, x, y);
    await clickPointer();
    await waitFor(0.1);
    const doc = element.ownerDocument;
    await enablePassThrough();
    const hitTarget = doc.elementFromPoint(x, y);
    await disablePassThrough();
    const target = hitTarget instanceof HTMLElement && element.contains(hitTarget) ? hitTarget : element;
    const pointerOpts = {
      bubbles: true,
      cancelable: true,
      clientX: x,
      clientY: y,
      pointerType: "mouse"
    };
    const mouseOpts = { bubbles: true, cancelable: true, clientX: x, clientY: y, button: 0 };
    target.dispatchEvent(new PointerEvent("pointerover", pointerOpts));
    target.dispatchEvent(new PointerEvent("pointerenter", { ...pointerOpts, bubbles: false }));
    target.dispatchEvent(new MouseEvent("mouseover", mouseOpts));
    target.dispatchEvent(new MouseEvent("mouseenter", { ...mouseOpts, bubbles: false }));
    target.dispatchEvent(new PointerEvent("pointerdown", pointerOpts));
    target.dispatchEvent(new MouseEvent("mousedown", mouseOpts));
    element.focus({ preventScroll: true });
    target.dispatchEvent(new PointerEvent("pointerup", pointerOpts));
    target.dispatchEvent(new MouseEvent("mouseup", mouseOpts));
    target.click();
    await waitFor(0.2);
  }
  async function inputTextElement(element, text) {
    const isContentEditable = element.isContentEditable;
    if (!isInputElement(element) && !isTextAreaElement(element) && !isContentEditable) {
      throw new Error("Element is not an input, textarea, or contenteditable");
    }
    await clickElement(element);
    if (isContentEditable) {
      if (element.dispatchEvent(
        new InputEvent("beforeinput", {
          bubbles: true,
          cancelable: true,
          inputType: "deleteContent"
        })
      )) {
        element.innerText = "";
        element.dispatchEvent(
          new InputEvent("input", {
            bubbles: true,
            inputType: "deleteContent"
          })
        );
      }
      if (element.dispatchEvent(
        new InputEvent("beforeinput", {
          bubbles: true,
          cancelable: true,
          inputType: "insertText",
          data: text
        })
      )) {
        element.innerText = text;
        element.dispatchEvent(
          new InputEvent("input", {
            bubbles: true,
            inputType: "insertText",
            data: text
          })
        );
      }
      const planASucceeded = element.innerText.trim() === text.trim();
      if (!planASucceeded) {
        element.focus();
        const doc = element.ownerDocument;
        const selection = (doc.defaultView || window).getSelection();
        const range = doc.createRange();
        range.selectNodeContents(element);
        selection?.removeAllRanges();
        selection?.addRange(range);
        doc.execCommand("delete", false);
        doc.execCommand("insertText", false, text);
      }
      element.dispatchEvent(new Event("change", { bubbles: true }));
      element.blur();
    } else {
      getNativeValueSetter(element).call(element, text);
    }
    if (!isContentEditable) {
      element.dispatchEvent(new Event("input", { bubbles: true }));
    }
    await waitFor(0.1);
    blurLastClickedElement();
  }
  async function selectOptionElement(selectElement, optionText) {
    if (!isSelectElement(selectElement)) {
      throw new Error("Element is not a select element");
    }
    const options = Array.from(selectElement.options);
    const option = options.find((opt) => opt.textContent?.trim() === optionText.trim());
    if (!option) {
      throw new Error(`Option with text "${optionText}" not found in select element`);
    }
    selectElement.value = option.value;
    selectElement.dispatchEvent(new Event("change", { bubbles: true }));
    await waitFor(0.1);
  }
  async function scrollIntoViewIfNeeded(element) {
    const el = element;
    if (typeof el.scrollIntoViewIfNeeded === "function") {
      el.scrollIntoViewIfNeeded();
    } else {
      element.scrollIntoView({ behavior: "auto", block: "center", inline: "nearest" });
    }
  }
  async function scrollVertically(scroll_amount, element) {
    if (element) {
      const targetElement = element;
      let currentElement = targetElement;
      let scrollSuccess = false;
      let scrolledElement = null;
      let scrollDelta = 0;
      let attempts = 0;
      const dy2 = scroll_amount;
      while (currentElement && attempts < 10) {
        const computedStyle = window.getComputedStyle(currentElement);
        const hasScrollableY = /(auto|scroll|overlay)/.test(computedStyle.overflowY) || computedStyle.scrollbarWidth && computedStyle.scrollbarWidth !== "auto" || computedStyle.scrollbarGutter && computedStyle.scrollbarGutter !== "auto";
        const canScrollVertically = currentElement.scrollHeight > currentElement.clientHeight;
        if (hasScrollableY && canScrollVertically) {
          const beforeScroll = currentElement.scrollTop;
          const maxScroll = currentElement.scrollHeight - currentElement.clientHeight;
          let scrollAmount = dy2 / 3;
          if (scrollAmount > 0) {
            scrollAmount = Math.min(scrollAmount, maxScroll - beforeScroll);
          } else {
            scrollAmount = Math.max(scrollAmount, -beforeScroll);
          }
          currentElement.scrollTop = beforeScroll + scrollAmount;
          const afterScroll = currentElement.scrollTop;
          const actualScrollDelta = afterScroll - beforeScroll;
          if (Math.abs(actualScrollDelta) > 0.5) {
            scrollSuccess = true;
            scrolledElement = currentElement;
            scrollDelta = actualScrollDelta;
            break;
          }
        }
        if (currentElement === document.body || currentElement === document.documentElement) {
          break;
        }
        currentElement = currentElement.parentElement;
        attempts++;
      }
      if (scrollSuccess) {
        return `Scrolled container (${scrolledElement?.tagName}) by ${scrollDelta}px`;
      } else {
        return `No scrollable container found for element (${targetElement.tagName})`;
      }
    }
    const dy = scroll_amount;
    const bigEnough = (el2) => el2.clientHeight >= window.innerHeight * 0.5;
    const canScroll = (el2) => el2 && /(auto|scroll|overlay)/.test(getComputedStyle(el2).overflowY) && el2.scrollHeight > el2.clientHeight && bigEnough(el2);
    let el = document.activeElement;
    while (el && !canScroll(el) && el !== document.body) el = el.parentElement;
    el = canScroll(el) ? el : Array.from(document.querySelectorAll("*")).find(canScroll) || document.scrollingElement || document.documentElement;
    if (el === document.scrollingElement || el === document.documentElement || el === document.body) {
      const scrollBefore = window.scrollY;
      const scrollMax = document.documentElement.scrollHeight - window.innerHeight;
      window.scrollBy(0, dy);
      const scrollAfter = window.scrollY;
      const scrolled = scrollAfter - scrollBefore;
      if (Math.abs(scrolled) < 1) {
        return dy > 0 ? `⚠️ Already at the bottom of the page, cannot scroll down further.` : `⚠️ Already at the top of the page, cannot scroll up further.`;
      }
      const reachedBottom = dy > 0 && scrollAfter >= scrollMax - 1;
      const reachedTop = dy < 0 && scrollAfter <= 1;
      if (reachedBottom) return `✅ Scrolled page by ${scrolled}px. Reached the bottom of the page.`;
      if (reachedTop) return `✅ Scrolled page by ${scrolled}px. Reached the top of the page.`;
      return `✅ Scrolled page by ${scrolled}px.`;
    } else {
      const warningMsg = `The document is not scrollable. Falling back to container scroll.`;
      console.log(`[PageController] ${warningMsg}`);
      const scrollBefore = el.scrollTop;
      const scrollMax = el.scrollHeight - el.clientHeight;
      el.scrollBy({ top: dy, behavior: "smooth" });
      await waitFor(0.1);
      const scrollAfter = el.scrollTop;
      const scrolled = scrollAfter - scrollBefore;
      if (Math.abs(scrolled) < 1) {
        return dy > 0 ? `⚠️ ${warningMsg} Already at the bottom of container (${el.tagName}), cannot scroll down further.` : `⚠️ ${warningMsg} Already at the top of container (${el.tagName}), cannot scroll up further.`;
      }
      const reachedBottom = dy > 0 && scrollAfter >= scrollMax - 1;
      const reachedTop = dy < 0 && scrollAfter <= 1;
      if (reachedBottom)
        return `✅ ${warningMsg} Scrolled container (${el.tagName}) by ${scrolled}px. Reached the bottom.`;
      if (reachedTop)
        return `✅ ${warningMsg} Scrolled container (${el.tagName}) by ${scrolled}px. Reached the top.`;
      return `✅ ${warningMsg} Scrolled container (${el.tagName}) by ${scrolled}px.`;
    }
  }
  async function scrollHorizontally(scroll_amount, element) {
    if (element) {
      const targetElement = element;
      let currentElement = targetElement;
      let scrollSuccess = false;
      let scrolledElement = null;
      let scrollDelta = 0;
      let attempts = 0;
      const dx2 = scroll_amount;
      while (currentElement && attempts < 10) {
        const computedStyle = window.getComputedStyle(currentElement);
        const hasScrollableX = /(auto|scroll|overlay)/.test(computedStyle.overflowX) || computedStyle.scrollbarWidth && computedStyle.scrollbarWidth !== "auto" || computedStyle.scrollbarGutter && computedStyle.scrollbarGutter !== "auto";
        const canScrollHorizontally = currentElement.scrollWidth > currentElement.clientWidth;
        if (hasScrollableX && canScrollHorizontally) {
          const beforeScroll = currentElement.scrollLeft;
          const maxScroll = currentElement.scrollWidth - currentElement.clientWidth;
          let scrollAmount = dx2 / 3;
          if (scrollAmount > 0) {
            scrollAmount = Math.min(scrollAmount, maxScroll - beforeScroll);
          } else {
            scrollAmount = Math.max(scrollAmount, -beforeScroll);
          }
          currentElement.scrollLeft = beforeScroll + scrollAmount;
          const afterScroll = currentElement.scrollLeft;
          const actualScrollDelta = afterScroll - beforeScroll;
          if (Math.abs(actualScrollDelta) > 0.5) {
            scrollSuccess = true;
            scrolledElement = currentElement;
            scrollDelta = actualScrollDelta;
            break;
          }
        }
        if (currentElement === document.body || currentElement === document.documentElement) {
          break;
        }
        currentElement = currentElement.parentElement;
        attempts++;
      }
      if (scrollSuccess) {
        return `Scrolled container (${scrolledElement?.tagName}) horizontally by ${scrollDelta}px`;
      } else {
        return `No horizontally scrollable container found for element (${targetElement.tagName})`;
      }
    }
    const dx = scroll_amount;
    const bigEnough = (el2) => el2.clientWidth >= window.innerWidth * 0.5;
    const canScroll = (el2) => el2 && /(auto|scroll|overlay)/.test(getComputedStyle(el2).overflowX) && el2.scrollWidth > el2.clientWidth && bigEnough(el2);
    let el = document.activeElement;
    while (el && !canScroll(el) && el !== document.body) el = el.parentElement;
    el = canScroll(el) ? el : Array.from(document.querySelectorAll("*")).find(canScroll) || document.scrollingElement || document.documentElement;
    if (el === document.scrollingElement || el === document.documentElement || el === document.body) {
      const scrollBefore = window.scrollX;
      const scrollMax = document.documentElement.scrollWidth - window.innerWidth;
      window.scrollBy(dx, 0);
      const scrollAfter = window.scrollX;
      const scrolled = scrollAfter - scrollBefore;
      if (Math.abs(scrolled) < 1) {
        return dx > 0 ? `⚠️ Already at the right edge of the page, cannot scroll right further.` : `⚠️ Already at the left edge of the page, cannot scroll left further.`;
      }
      const reachedRight = dx > 0 && scrollAfter >= scrollMax - 1;
      const reachedLeft = dx < 0 && scrollAfter <= 1;
      if (reachedRight)
        return `✅ Scrolled page by ${scrolled}px. Reached the right edge of the page.`;
      if (reachedLeft) return `✅ Scrolled page by ${scrolled}px. Reached the left edge of the page.`;
      return `✅ Scrolled page horizontally by ${scrolled}px.`;
    } else {
      const warningMsg = `The document is not scrollable. Falling back to container scroll.`;
      console.log(`[PageController] ${warningMsg}`);
      const scrollBefore = el.scrollLeft;
      const scrollMax = el.scrollWidth - el.clientWidth;
      el.scrollBy({ left: dx, behavior: "smooth" });
      await waitFor(0.1);
      const scrollAfter = el.scrollLeft;
      const scrolled = scrollAfter - scrollBefore;
      if (Math.abs(scrolled) < 1) {
        return dx > 0 ? `⚠️ ${warningMsg} Already at the right edge of container (${el.tagName}), cannot scroll right further.` : `⚠️ ${warningMsg} Already at the left edge of container (${el.tagName}), cannot scroll left further.`;
      }
      const reachedRight = dx > 0 && scrollAfter >= scrollMax - 1;
      const reachedLeft = dx < 0 && scrollAfter <= 1;
      if (reachedRight)
        return `✅ ${warningMsg} Scrolled container (${el.tagName}) by ${scrolled}px. Reached the right edge.`;
      if (reachedLeft)
        return `✅ ${warningMsg} Scrolled container (${el.tagName}) by ${scrolled}px. Reached the left edge.`;
      return `✅ ${warningMsg} Scrolled container (${el.tagName}) horizontally by ${scrolled}px.`;
    }
  }
  const domTree = (args = {
    doHighlightElements: true,
    focusHighlightIndex: -1,
    viewportExpansion: 0,
    debugMode: false,
    /**
     * @edit
     */
    /** @type {Element[]} */
    interactiveBlacklist: [],
    /** @type {Element[]} */
    interactiveWhitelist: [],
    highlightOpacity: 0.1,
    highlightLabelOpacity: 0.5
  }) => {
    const { interactiveBlacklist, interactiveWhitelist, highlightOpacity, highlightLabelOpacity } = args;
    const { doHighlightElements, focusHighlightIndex, viewportExpansion, debugMode } = args;
    let highlightIndex = 0;
    const extraData = /* @__PURE__ */ new WeakMap();
    function addExtraData(element, data) {
      if (!element || element.nodeType !== Node.ELEMENT_NODE) return;
      extraData.set(element, { ...extraData.get(element), ...data });
    }
    const DOM_CACHE = {
      boundingRects: /* @__PURE__ */ new WeakMap(),
      clientRects: /* @__PURE__ */ new WeakMap(),
      computedStyles: /* @__PURE__ */ new WeakMap(),
      clearCache: () => {
        DOM_CACHE.boundingRects = /* @__PURE__ */ new WeakMap();
        DOM_CACHE.clientRects = /* @__PURE__ */ new WeakMap();
        DOM_CACHE.computedStyles = /* @__PURE__ */ new WeakMap();
      }
    };
    function getCachedBoundingRect(element) {
      if (!element) return null;
      if (DOM_CACHE.boundingRects.has(element)) {
        return DOM_CACHE.boundingRects.get(element);
      }
      const rect = element.getBoundingClientRect();
      if (rect) {
        DOM_CACHE.boundingRects.set(element, rect);
      }
      return rect;
    }
    function getCachedComputedStyle(element) {
      if (!element) return null;
      if (DOM_CACHE.computedStyles.has(element)) {
        return DOM_CACHE.computedStyles.get(element);
      }
      const style = window.getComputedStyle(element);
      if (style) {
        DOM_CACHE.computedStyles.set(element, style);
      }
      return style;
    }
    function getCachedClientRects(element) {
      if (!element) return null;
      if (DOM_CACHE.clientRects.has(element)) {
        return DOM_CACHE.clientRects.get(element);
      }
      const rects = element.getClientRects();
      if (rects) {
        DOM_CACHE.clientRects.set(element, rects);
      }
      return rects;
    }
    const DOM_HASH_MAP = {};
    const ID = { current: 0 };
    const HIGHLIGHT_CONTAINER_ID = "playwright-highlight-container";
    function highlightElement(element, index, parentIframe = null) {
      if (!element) return index;
      const overlays = [];
      let label = null;
      let labelWidth = 20;
      let labelHeight = 16;
      let cleanupFn = null;
      try {
        let container = document.getElementById(HIGHLIGHT_CONTAINER_ID);
        if (!container) {
          container = document.createElement("div");
          container.id = HIGHLIGHT_CONTAINER_ID;
          container.style.position = "fixed";
          container.style.pointerEvents = "none";
          container.style.top = "0";
          container.style.left = "0";
          container.style.width = "100%";
          container.style.height = "100%";
          container.style.zIndex = "2147483640";
          container.style.backgroundColor = "transparent";
          document.body.appendChild(container);
        }
        const rects = element.getClientRects();
        if (!rects || rects.length === 0) return index;
        const colors = [
          "#FF0000",
          "#00FF00",
          "#0000FF",
          "#FFA500",
          "#800080",
          "#008080",
          "#FF69B4",
          "#4B0082",
          "#FF4500",
          "#2E8B57",
          "#DC143C",
          "#4682B4"
        ];
        const colorIndex = index % colors.length;
        let baseColor = colors[colorIndex];
        const backgroundColor = baseColor + Math.floor(highlightOpacity * 255).toString(16).padStart(2, "0");
        baseColor = baseColor + Math.floor(highlightLabelOpacity * 255).toString(16).padStart(2, "0");
        let iframeOffset = { x: 0, y: 0 };
        if (parentIframe) {
          const iframeRect = parentIframe.getBoundingClientRect();
          iframeOffset.x = iframeRect.left;
          iframeOffset.y = iframeRect.top;
        }
        const fragment = document.createDocumentFragment();
        for (const rect of rects) {
          if (rect.width === 0 || rect.height === 0) continue;
          const overlay = document.createElement("div");
          overlay.style.position = "fixed";
          overlay.style.border = `2px solid ${baseColor}`;
          overlay.style.backgroundColor = backgroundColor;
          overlay.style.pointerEvents = "none";
          overlay.style.boxSizing = "border-box";
          const top = rect.top + iframeOffset.y;
          const left = rect.left + iframeOffset.x;
          overlay.style.top = `${top}px`;
          overlay.style.left = `${left}px`;
          overlay.style.width = `${rect.width}px`;
          overlay.style.height = `${rect.height}px`;
          fragment.appendChild(overlay);
          overlays.push({ element: overlay, initialRect: rect });
        }
        const firstRect = rects[0];
        label = document.createElement("div");
        label.className = "playwright-highlight-label";
        label.style.position = "fixed";
        label.style.background = baseColor;
        label.style.color = "white";
        label.style.padding = "1px 4px";
        label.style.borderRadius = "4px";
        label.style.fontSize = `${Math.min(12, Math.max(8, firstRect.height / 2))}px`;
        label.textContent = index.toString();
        labelWidth = label.offsetWidth > 0 ? label.offsetWidth : labelWidth;
        labelHeight = label.offsetHeight > 0 ? label.offsetHeight : labelHeight;
        const firstRectTop = firstRect.top + iframeOffset.y;
        const firstRectLeft = firstRect.left + iframeOffset.x;
        let labelTop = firstRectTop + 2;
        let labelLeft = firstRectLeft + firstRect.width - labelWidth - 2;
        if (firstRect.width < labelWidth + 4 || firstRect.height < labelHeight + 4) {
          labelTop = firstRectTop - labelHeight - 2;
          labelLeft = firstRectLeft + firstRect.width - labelWidth;
          if (labelLeft < iframeOffset.x) labelLeft = firstRectLeft;
        }
        labelTop = Math.max(0, Math.min(labelTop, window.innerHeight - labelHeight));
        labelLeft = Math.max(0, Math.min(labelLeft, window.innerWidth - labelWidth));
        label.style.top = `${labelTop}px`;
        label.style.left = `${labelLeft}px`;
        fragment.appendChild(label);
        const updatePositions = () => {
          const newRects = element.getClientRects();
          let newIframeOffset = { x: 0, y: 0 };
          if (parentIframe) {
            const iframeRect = parentIframe.getBoundingClientRect();
            newIframeOffset.x = iframeRect.left;
            newIframeOffset.y = iframeRect.top;
          }
          overlays.forEach((overlayData, i) => {
            if (i < newRects.length) {
              const newRect = newRects[i];
              const newTop = newRect.top + newIframeOffset.y;
              const newLeft = newRect.left + newIframeOffset.x;
              overlayData.element.style.top = `${newTop}px`;
              overlayData.element.style.left = `${newLeft}px`;
              overlayData.element.style.width = `${newRect.width}px`;
              overlayData.element.style.height = `${newRect.height}px`;
              overlayData.element.style.display = newRect.width === 0 || newRect.height === 0 ? "none" : "block";
            } else {
              overlayData.element.style.display = "none";
            }
          });
          if (newRects.length < overlays.length) {
            for (let i = newRects.length; i < overlays.length; i++) {
              overlays[i].element.style.display = "none";
            }
          }
          if (label && newRects.length > 0) {
            const firstNewRect = newRects[0];
            const firstNewRectTop = firstNewRect.top + newIframeOffset.y;
            const firstNewRectLeft = firstNewRect.left + newIframeOffset.x;
            let newLabelTop = firstNewRectTop + 2;
            let newLabelLeft = firstNewRectLeft + firstNewRect.width - labelWidth - 2;
            if (firstNewRect.width < labelWidth + 4 || firstNewRect.height < labelHeight + 4) {
              newLabelTop = firstNewRectTop - labelHeight - 2;
              newLabelLeft = firstNewRectLeft + firstNewRect.width - labelWidth;
              if (newLabelLeft < newIframeOffset.x) newLabelLeft = firstNewRectLeft;
            }
            newLabelTop = Math.max(0, Math.min(newLabelTop, window.innerHeight - labelHeight));
            newLabelLeft = Math.max(0, Math.min(newLabelLeft, window.innerWidth - labelWidth));
            label.style.top = `${newLabelTop}px`;
            label.style.left = `${newLabelLeft}px`;
            label.style.display = "block";
          } else if (label) {
            label.style.display = "none";
          }
        };
        const throttleFunction = (func, delay) => {
          let lastCall = 0;
          return (...args2) => {
            const now = performance.now();
            if (now - lastCall < delay) return;
            lastCall = now;
            return func(...args2);
          };
        };
        const throttledUpdatePositions = throttleFunction(updatePositions, 16);
        window.addEventListener("scroll", throttledUpdatePositions, true);
        window.addEventListener("resize", throttledUpdatePositions);
        cleanupFn = () => {
          window.removeEventListener("scroll", throttledUpdatePositions, true);
          window.removeEventListener("resize", throttledUpdatePositions);
          overlays.forEach((overlay) => overlay.element.remove());
          if (label) label.remove();
        };
        container.appendChild(fragment);
        return index + 1;
      } finally {
        if (cleanupFn) {
          (window._highlightCleanupFunctions = window._highlightCleanupFunctions || []).push(
            cleanupFn
          );
        }
      }
    }
    function isScrollableElement(element) {
      if (!element || element.nodeType !== Node.ELEMENT_NODE) {
        return null;
      }
      const style = getCachedComputedStyle(element);
      if (!style) return null;
      const display = style.display;
      if (display === "inline" || display === "inline-block") {
        return null;
      }
      const overflowX = style.overflowX;
      const overflowY = style.overflowY;
      const hasScrollbarSignal = style.scrollbarWidth && style.scrollbarWidth !== "auto" || style.scrollbarGutter && style.scrollbarGutter !== "auto";
      const scrollableX = overflowX === "auto" || overflowX === "scroll";
      const scrollableY = overflowY === "auto" || overflowY === "scroll";
      if (!scrollableX && !scrollableY && !hasScrollbarSignal) {
        return null;
      }
      const scrollWidth = element.scrollWidth - element.clientWidth;
      const scrollHeight = element.scrollHeight - element.clientHeight;
      const threshold = 4;
      if (scrollWidth < threshold && scrollHeight < threshold) {
        return null;
      }
      if (!scrollableY && !hasScrollbarSignal && scrollWidth < threshold) {
        return null;
      }
      if (!scrollableX && !hasScrollbarSignal && scrollHeight < threshold) {
        return null;
      }
      const distanceToTop = element.scrollTop;
      const distanceToLeft = element.scrollLeft;
      const distanceToRight = element.scrollWidth - element.clientWidth - element.scrollLeft;
      const distanceToBottom = element.scrollHeight - element.clientHeight - element.scrollTop;
      const scrollData = {
        top: distanceToTop,
        right: distanceToRight,
        bottom: distanceToBottom,
        left: distanceToLeft
      };
      addExtraData(element, {
        scrollable: true,
        scrollData
      });
      console.log("scrollData!!!", scrollData);
      return scrollData;
    }
    function isTextNodeVisible(textNode) {
      try {
        if (viewportExpansion === -1) {
          const parentElement2 = textNode.parentElement;
          if (!parentElement2) return false;
          try {
            return parentElement2.checkVisibility({
              checkOpacity: true,
              checkVisibilityCSS: true
            });
          } catch (e) {
            const style = window.getComputedStyle(parentElement2);
            return style.display !== "none" && style.visibility !== "hidden" && style.opacity !== "0";
          }
        }
        const range = document.createRange();
        range.selectNodeContents(textNode);
        const rects = range.getClientRects();
        if (!rects || rects.length === 0) {
          return false;
        }
        let isAnyRectVisible = false;
        let isAnyRectInViewport = false;
        for (const rect of rects) {
          if (rect.width > 0 && rect.height > 0) {
            isAnyRectVisible = true;
            if (!(rect.bottom < -viewportExpansion || rect.top > window.innerHeight + viewportExpansion || rect.right < -viewportExpansion || rect.left > window.innerWidth + viewportExpansion)) {
              isAnyRectInViewport = true;
              break;
            }
          }
        }
        if (!isAnyRectVisible || !isAnyRectInViewport) {
          return false;
        }
        const parentElement = textNode.parentElement;
        if (!parentElement) return false;
        try {
          return parentElement.checkVisibility({
            checkOpacity: true,
            checkVisibilityCSS: true
          });
        } catch (e) {
          const style = window.getComputedStyle(parentElement);
          return style.display !== "none" && style.visibility !== "hidden" && style.opacity !== "0";
        }
      } catch (e) {
        console.warn("Error checking text node visibility:", e);
        return false;
      }
    }
    function isElementAccepted(element) {
      if (!element || !element.tagName) return false;
      const alwaysAccept = /* @__PURE__ */ new Set([
        "body",
        "div",
        "main",
        "article",
        "section",
        "nav",
        "header",
        "footer"
      ]);
      const tagName = element.tagName.toLowerCase();
      if (alwaysAccept.has(tagName)) return true;
      const leafElementDenyList = /* @__PURE__ */ new Set([
        "svg",
        "script",
        "style",
        "link",
        "meta",
        "noscript",
        "template"
      ]);
      return !leafElementDenyList.has(tagName);
    }
    function isElementVisible(element) {
      const style = getCachedComputedStyle(element);
      return element.offsetWidth > 0 && element.offsetHeight > 0 && style?.visibility !== "hidden" && style?.display !== "none";
    }
    function isInteractiveElement(element) {
      if (!element || element.nodeType !== Node.ELEMENT_NODE) {
        return false;
      }
      if (interactiveBlacklist.includes(element)) {
        return false;
      }
      if (interactiveWhitelist.includes(element)) {
        return true;
      }
      const tagName = element.tagName.toLowerCase();
      const style = getCachedComputedStyle(element);
      const interactiveCursors = /* @__PURE__ */ new Set([
        "pointer",
        // Link/clickable elements
        "move",
        // Movable elements
        "text",
        // Text selection
        "grab",
        // Grabbable elements
        "grabbing",
        // Currently grabbing
        "cell",
        // Table cell selection
        "copy",
        // Copy operation
        "alias",
        // Alias creation
        "all-scroll",
        // Scrollable content
        "col-resize",
        // Column resize
        "context-menu",
        // Context menu available
        "crosshair",
        // Precise selection
        "e-resize",
        // East resize
        "ew-resize",
        // East-west resize
        "help",
        // Help available
        "n-resize",
        // North resize
        "ne-resize",
        // Northeast resize
        "nesw-resize",
        // Northeast-southwest resize
        "ns-resize",
        // North-south resize
        "nw-resize",
        // Northwest resize
        "nwse-resize",
        // Northwest-southeast resize
        "row-resize",
        // Row resize
        "s-resize",
        // South resize
        "se-resize",
        // Southeast resize
        "sw-resize",
        // Southwest resize
        "vertical-text",
        // Vertical text selection
        "w-resize",
        // West resize
        "zoom-in",
        // Zoom in
        "zoom-out"
        // Zoom out
      ]);
      const nonInteractiveCursors = /* @__PURE__ */ new Set([
        "not-allowed",
        // Action not allowed
        "no-drop",
        // Drop not allowed
        "wait",
        // Processing
        "progress",
        // In progress
        "initial",
        // Initial value
        "inherit"
        // Inherited value
        //? Let's just include all potentially clickable elements that are not specifically blocked
        // 'none',        // No cursor
        // 'default',     // Default cursor
        // 'auto',        // Browser default
      ]);
      function doesElementHaveInteractivePointer(element2) {
        if (element2.tagName.toLowerCase() === "html") return false;
        if (style?.cursor && interactiveCursors.has(style.cursor)) return true;
        return false;
      }
      let isInteractiveCursor = doesElementHaveInteractivePointer(element);
      if (isInteractiveCursor) {
        return true;
      }
      const interactiveElements = /* @__PURE__ */ new Set([
        "a",
        // Links
        "button",
        // Buttons
        "input",
        // All input types (text, checkbox, radio, etc.)
        "select",
        // Dropdown menus
        "textarea",
        // Text areas
        "details",
        // Expandable details
        "summary",
        // Summary element (clickable part of details)
        "label",
        // Form labels (often clickable)
        "option",
        // Select options
        "optgroup",
        // Option groups
        "fieldset",
        // Form fieldsets (can be interactive with legend)
        "legend"
        // Fieldset legends
      ]);
      const explicitDisableTags = /* @__PURE__ */ new Set([
        "disabled",
        // Standard disabled attribute
        // 'aria-disabled',      // ARIA disabled state
        "readonly"
        // Read-only state
        // 'aria-readonly',     // ARIA read-only state
        // 'aria-hidden',       // Hidden from accessibility
        // 'hidden',            // Hidden attribute
        // 'inert',             // Inert attribute
        // 'aria-inert',        // ARIA inert state
        // 'tabindex="-1"',     // Removed from tab order
        // 'aria-hidden="true"' // Hidden from screen readers
      ]);
      if (interactiveElements.has(tagName)) {
        if (style?.cursor && nonInteractiveCursors.has(style.cursor)) {
          return false;
        }
        for (const disableTag of explicitDisableTags) {
          if (element.hasAttribute(disableTag) || element.getAttribute(disableTag) === "true" || element.getAttribute(disableTag) === "") {
            return false;
          }
        }
        if (element.disabled) {
          return false;
        }
        if (element.readOnly) {
          return false;
        }
        if (element.inert) {
          return false;
        }
        return true;
      }
      const role = element.getAttribute("role");
      const ariaRole = element.getAttribute("aria-role");
      if (element.getAttribute("contenteditable") === "true" || element.isContentEditable) {
        return true;
      }
      if (element.classList && (element.classList.contains("button") || element.classList.contains("dropdown-toggle") || element.getAttribute("data-index") || element.getAttribute("data-toggle") === "dropdown" || element.getAttribute("aria-haspopup") === "true")) {
        return true;
      }
      const interactiveRoles = /* @__PURE__ */ new Set([
        "button",
        // Directly clickable element
        // 'link',            // Clickable link
        "menu",
        // Menu container (ARIA menus)
        "menubar",
        // Menu bar container
        "menuitem",
        // Clickable menu item
        "menuitemradio",
        // Radio-style menu item (selectable)
        "menuitemcheckbox",
        // Checkbox-style menu item (toggleable)
        "radio",
        // Radio button (selectable)
        "checkbox",
        // Checkbox (toggleable)
        "tab",
        // Tab (clickable to switch content)
        "switch",
        // Toggle switch (clickable to change state)
        "slider",
        // Slider control (draggable)
        "spinbutton",
        // Number input with up/down controls
        "combobox",
        // Dropdown with text input
        "searchbox",
        // Search input field
        "textbox",
        // Text input field
        "listbox",
        // Selectable list
        "option",
        // Selectable option in a list
        "scrollbar"
        // Scrollable control
      ]);
      const hasInteractiveRole = interactiveElements.has(tagName) || role && interactiveRoles.has(role) || ariaRole && interactiveRoles.has(ariaRole);
      if (hasInteractiveRole) return true;
      try {
        if (typeof getEventListeners === "function") {
          const listeners = getEventListeners(element);
          const mouseEvents = ["click", "mousedown", "mouseup", "dblclick"];
          for (const eventType of mouseEvents) {
            if (listeners[eventType] && listeners[eventType].length > 0) {
              return true;
            }
          }
        }
        const getEventListenersForNode = element?.ownerDocument?.defaultView?.getEventListenersForNode || window.getEventListenersForNode;
        if (typeof getEventListenersForNode === "function") {
          const listeners = getEventListenersForNode(element);
          const interactionEvents = [
            "click",
            "mousedown",
            "mouseup",
            "keydown",
            "keyup",
            "submit",
            "change",
            "input",
            "focus",
            "blur"
          ];
          for (const eventType of interactionEvents) {
            for (const listener of listeners) {
              if (listener.type === eventType) {
                return true;
              }
            }
          }
        }
        const commonMouseAttrs = ["onclick", "onmousedown", "onmouseup", "ondblclick"];
        for (const attr of commonMouseAttrs) {
          if (element.hasAttribute(attr) || typeof element[attr] === "function") {
            return true;
          }
        }
      } catch (e) {
      }
      if (isScrollableElement(element)) {
        return true;
      }
      return false;
    }
    function isTopElement(element) {
      if (viewportExpansion === -1) {
        return true;
      }
      const rects = getCachedClientRects(element);
      if (!rects || rects.length === 0) {
        return false;
      }
      let isAnyRectInViewport = false;
      for (const rect2 of rects) {
        if (rect2.width > 0 && rect2.height > 0 && !// Only check non-empty rects
        (rect2.bottom < -viewportExpansion || rect2.top > window.innerHeight + viewportExpansion || rect2.right < -viewportExpansion || rect2.left > window.innerWidth + viewportExpansion)) {
          isAnyRectInViewport = true;
          break;
        }
      }
      if (!isAnyRectInViewport) {
        return false;
      }
      let doc = element.ownerDocument;
      if (doc !== window.document) {
        return true;
      }
      let rect = Array.from(rects).find((r) => r.width > 0 && r.height > 0);
      if (!rect) {
        return false;
      }
      const shadowRoot = element.getRootNode();
      if (shadowRoot instanceof ShadowRoot) {
        const centerX = rect.left + rect.width / 2;
        const centerY = rect.top + rect.height / 2;
        try {
          const topEl = shadowRoot.elementFromPoint(centerX, centerY);
          if (!topEl) return false;
          let current = topEl;
          while (current && current !== shadowRoot) {
            if (current === element) return true;
            current = current.parentElement;
          }
          return false;
        } catch (e) {
          return true;
        }
      }
      const margin = 5;
      const checkPoints = [
        // Initially only this was used, but it was not enough
        { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 },
        { x: rect.left + margin, y: rect.top + margin },
        // top left
        // { x: rect.right - margin, y: rect.top + margin },    // top right
        // { x: rect.left + margin, y: rect.bottom - margin },  // bottom left
        { x: rect.right - margin, y: rect.bottom - margin }
        // bottom right
      ];
      return checkPoints.some(({ x, y }) => {
        try {
          const topEl = document.elementFromPoint(x, y);
          if (!topEl) return false;
          let current = topEl;
          while (current && current !== document.documentElement) {
            if (current === element) return true;
            current = current.parentElement;
          }
          return false;
        } catch (e) {
          return true;
        }
      });
    }
    function isInExpandedViewport(element, viewportExpansion2) {
      if (viewportExpansion2 === -1) {
        return true;
      }
      const rects = element.getClientRects();
      if (!rects || rects.length === 0) {
        const boundingRect = getCachedBoundingRect(element);
        if (!boundingRect || boundingRect.width === 0 || boundingRect.height === 0) {
          return false;
        }
        return !(boundingRect.bottom < -viewportExpansion2 || boundingRect.top > window.innerHeight + viewportExpansion2 || boundingRect.right < -viewportExpansion2 || boundingRect.left > window.innerWidth + viewportExpansion2);
      }
      for (const rect of rects) {
        if (rect.width === 0 || rect.height === 0) continue;
        if (!(rect.bottom < -viewportExpansion2 || rect.top > window.innerHeight + viewportExpansion2 || rect.right < -viewportExpansion2 || rect.left > window.innerWidth + viewportExpansion2)) {
          return true;
        }
      }
      return false;
    }
    const INTERACTIVE_ARIA_ATTRS = [
      "aria-expanded",
      "aria-checked",
      "aria-selected",
      "aria-pressed",
      "aria-haspopup",
      "aria-controls",
      "aria-owns",
      "aria-activedescendant",
      "aria-valuenow",
      "aria-valuetext",
      "aria-valuemax",
      "aria-valuemin",
      "aria-autocomplete"
    ];
    function hasInteractiveAria(el) {
      for (let i = 0; i < INTERACTIVE_ARIA_ATTRS.length; i++) {
        if (el.hasAttribute(INTERACTIVE_ARIA_ATTRS[i])) return true;
      }
      return false;
    }
    function isInteractiveCandidate(element) {
      if (!element || element.nodeType !== Node.ELEMENT_NODE) return false;
      const tagName = element.tagName.toLowerCase();
      const interactiveElements = /* @__PURE__ */ new Set([
        "a",
        "button",
        "input",
        "select",
        "textarea",
        "details",
        "summary",
        "label"
      ]);
      if (interactiveElements.has(tagName)) return true;
      const hasQuickInteractiveAttr = element.hasAttribute("onclick") || element.hasAttribute("role") || element.hasAttribute("tabindex") || hasInteractiveAria(element) || element.hasAttribute("data-action") || element.getAttribute("contenteditable") === "true";
      return hasQuickInteractiveAttr;
    }
    const DISTINCT_INTERACTIVE_TAGS = /* @__PURE__ */ new Set([
      "a",
      "button",
      "input",
      "select",
      "textarea",
      "summary",
      "details",
      "label",
      "option",
      "li"
    ]);
    const DISTINCT_INTERACTIVE_ROLES = /* @__PURE__ */ new Set([
      "button",
      "link",
      "menuitem",
      "menuitemradio",
      "menuitemcheckbox",
      "radio",
      "checkbox",
      "tab",
      "switch",
      "slider",
      "spinbutton",
      "combobox",
      "searchbox",
      "textbox",
      "listbox",
      "listitem",
      "treeitem",
      "row",
      "option",
      "scrollbar"
    ]);
    function isHeuristicallyInteractive(element) {
      if (!element || element.nodeType !== Node.ELEMENT_NODE) return false;
      if (!isElementVisible(element)) return false;
      const hasInteractiveAttributes = element.hasAttribute("role") || element.hasAttribute("tabindex") || element.hasAttribute("onclick") || typeof element.onclick === "function";
      const hasInteractiveClass = /\b(btn|clickable|menu|item|entry|link)\b/i.test(
        element.className || ""
      );
      const isInKnownContainer = Boolean(
        element.closest('button,a,[role="button"],.menu,.dropdown,.list,.toolbar')
      );
      const hasVisibleChildren = [...element.children].some(isElementVisible);
      const isParentBody = element.parentElement && element.parentElement.isSameNode(document.body);
      return (isInteractiveElement(element) || hasInteractiveAttributes || hasInteractiveClass) && hasVisibleChildren && isInKnownContainer && !isParentBody;
    }
    function isElementDistinctInteraction(element) {
      if (!element || element.nodeType !== Node.ELEMENT_NODE) {
        return false;
      }
      const tagName = element.tagName.toLowerCase();
      const role = element.getAttribute("role");
      if (tagName === "iframe") {
        return true;
      }
      if (DISTINCT_INTERACTIVE_TAGS.has(tagName)) {
        return true;
      }
      if (role && DISTINCT_INTERACTIVE_ROLES.has(role)) {
        return true;
      }
      if (element.isContentEditable || element.getAttribute("contenteditable") === "true") {
        return true;
      }
      if (element.hasAttribute("data-testid") || element.hasAttribute("data-cy") || element.hasAttribute("data-test")) {
        return true;
      }
      if (element.hasAttribute("onclick") || typeof element.onclick === "function") {
        return true;
      }
      if (hasInteractiveAria(element)) {
        return true;
      }
      try {
        const getEventListenersForNode = element?.ownerDocument?.defaultView?.getEventListenersForNode || window.getEventListenersForNode;
        if (typeof getEventListenersForNode === "function") {
          const listeners = getEventListenersForNode(element);
          const interactionEvents = [
            "click",
            "mousedown",
            "mouseup",
            "keydown",
            "keyup",
            "submit",
            "change",
            "input",
            "focus",
            "blur"
          ];
          for (const eventType of interactionEvents) {
            for (const listener of listeners) {
              if (listener.type === eventType) {
                return true;
              }
            }
          }
        }
        const commonEventAttrs = [
          "onmousedown",
          "onmouseup",
          "onkeydown",
          "onkeyup",
          "onsubmit",
          "onchange",
          "oninput",
          "onfocus",
          "onblur"
        ];
        if (commonEventAttrs.some((attr) => element.hasAttribute(attr))) {
          return true;
        }
      } catch (e) {
      }
      if (isHeuristicallyInteractive(element)) {
        return true;
      }
      if (extraData.get(element)?.scrollable) {
        return true;
      }
      return false;
    }
    function handleHighlighting(nodeData, node, parentIframe, isParentHighlighted) {
      if (!nodeData.isInteractive) return false;
      let shouldHighlight = false;
      if (!isParentHighlighted) {
        shouldHighlight = true;
      } else {
        if (isElementDistinctInteraction(node)) {
          shouldHighlight = true;
        } else {
          shouldHighlight = false;
        }
      }
      if (shouldHighlight) {
        nodeData.isInViewport = isInExpandedViewport(node, viewportExpansion);
        if (nodeData.isInViewport || viewportExpansion === -1) {
          nodeData.highlightIndex = highlightIndex++;
          if (doHighlightElements) {
            if (focusHighlightIndex >= 0) {
              if (focusHighlightIndex === nodeData.highlightIndex) {
                highlightElement(node, nodeData.highlightIndex, parentIframe);
              }
            } else {
              highlightElement(node, nodeData.highlightIndex, parentIframe);
            }
            return true;
          }
        }
      }
      return false;
    }
    function buildDomTree(node, parentIframe = null, isParentHighlighted = false) {
      if (!node || node.id === HIGHLIGHT_CONTAINER_ID || node.nodeType !== Node.ELEMENT_NODE && node.nodeType !== Node.TEXT_NODE) {
        return null;
      }
      if (!node || node.id === HIGHLIGHT_CONTAINER_ID) {
        return null;
      }
      if (node.dataset?.browserUseIgnore === "true" || node.dataset?.pageAgentIgnore === "true") {
        return null;
      }
      if (node.getAttribute && node.getAttribute("aria-hidden") === "true") {
        return null;
      }
      if (node === document.body) {
        const nodeData2 = {
          tagName: "body",
          attributes: {},
          xpath: "/body",
          children: []
        };
        for (const child of node.childNodes) {
          const domElement = buildDomTree(child, parentIframe, false);
          if (domElement) nodeData2.children.push(domElement);
        }
        const id2 = `${ID.current++}`;
        DOM_HASH_MAP[id2] = nodeData2;
        return id2;
      }
      if (node.nodeType !== Node.ELEMENT_NODE && node.nodeType !== Node.TEXT_NODE) {
        return null;
      }
      if (node.nodeType === Node.TEXT_NODE) {
        const textContent = node.textContent?.trim();
        if (!textContent) {
          return null;
        }
        const parentElement = node.parentElement;
        if (!parentElement || parentElement.tagName.toLowerCase() === "script") {
          return null;
        }
        const id2 = `${ID.current++}`;
        DOM_HASH_MAP[id2] = {
          type: "TEXT_NODE",
          text: textContent,
          isVisible: isTextNodeVisible(node)
        };
        return id2;
      }
      if (node.nodeType === Node.ELEMENT_NODE && !isElementAccepted(node)) {
        return null;
      }
      if (viewportExpansion !== -1 && !node.shadowRoot) {
        const rect = getCachedBoundingRect(node);
        const style = getCachedComputedStyle(node);
        const isFixedOrSticky = style && (style.position === "fixed" || style.position === "sticky");
        const hasSize = node.offsetWidth > 0 || node.offsetHeight > 0;
        if (!rect || !isFixedOrSticky && !hasSize && (rect.bottom < -viewportExpansion || rect.top > window.innerHeight + viewportExpansion || rect.right < -viewportExpansion || rect.left > window.innerWidth + viewportExpansion)) {
          return null;
        }
      }
      const nodeData = {
        tagName: node.tagName.toLowerCase(),
        attributes: {},
        /**
         * @edit no need for xpath
         */
        // xpath: getXPathTree(node, true),
        children: []
      };
      if (isInteractiveCandidate(node) || node.tagName.toLowerCase() === "iframe" || node.tagName.toLowerCase() === "body") {
        const attributeNames = node.getAttributeNames?.() || [];
        for (const name of attributeNames) {
          const value = node.getAttribute(name);
          nodeData.attributes[name] = value;
        }
        if (node.tagName.toLowerCase() === "input" && (node.type === "checkbox" || node.type === "radio")) {
          nodeData.attributes.checked = node.checked ? "true" : "false";
        }
      }
      let nodeWasHighlighted = false;
      if (node.nodeType === Node.ELEMENT_NODE) {
        nodeData.isVisible = isElementVisible(node);
        if (nodeData.isVisible) {
          nodeData.isTopElement = isTopElement(node);
          const role = node.getAttribute("role");
          const isMenuContainer = role === "menu" || role === "menubar" || role === "listbox";
          if (nodeData.isTopElement || isMenuContainer) {
            nodeData.isInteractive = isInteractiveElement(node);
            nodeWasHighlighted = handleHighlighting(nodeData, node, parentIframe, isParentHighlighted);
            nodeData.ref = node;
            if (nodeData.isInteractive && Object.keys(nodeData.attributes).length === 0) {
              const attributeNames = node.getAttributeNames?.() || [];
              for (const name of attributeNames) {
                const value = node.getAttribute(name);
                nodeData.attributes[name] = value;
              }
            }
          }
        }
      }
      if (node.tagName) {
        const tagName = node.tagName.toLowerCase();
        if (tagName === "iframe") {
          try {
            const iframeDoc = node.contentDocument || node.contentWindow?.document;
            if (iframeDoc) {
              for (const child of iframeDoc.childNodes) {
                const domElement = buildDomTree(child, node, false);
                if (domElement) nodeData.children.push(domElement);
              }
            }
          } catch (e) {
            console.warn("Unable to access iframe:", e);
          }
        } else if (node.isContentEditable || node.getAttribute("contenteditable") === "true" || node.id === "tinymce" || node.classList.contains("mce-content-body") || tagName === "body" && node.getAttribute("data-id")?.startsWith("mce_")) {
          for (const child of node.childNodes) {
            const domElement = buildDomTree(child, parentIframe, nodeWasHighlighted);
            if (domElement) nodeData.children.push(domElement);
          }
        } else {
          if (node.shadowRoot) {
            nodeData.shadowRoot = true;
            for (const child of node.shadowRoot.childNodes) {
              const domElement = buildDomTree(child, parentIframe, nodeWasHighlighted);
              if (domElement) nodeData.children.push(domElement);
            }
          }
          for (const child of node.childNodes) {
            const passHighlightStatusToChild = nodeWasHighlighted || isParentHighlighted;
            const domElement = buildDomTree(child, parentIframe, passHighlightStatusToChild);
            if (domElement) nodeData.children.push(domElement);
          }
        }
      }
      if (nodeData.tagName === "a" && nodeData.children.length === 0 && !nodeData.attributes.href) {
        const rect = getCachedBoundingRect(node);
        const hasSize = rect && rect.width > 0 && rect.height > 0 || node.offsetWidth > 0 || node.offsetHeight > 0;
        if (!hasSize) {
          return null;
        }
      }
      nodeData.extra = extraData.get(node) || null;
      const id = `${ID.current++}`;
      DOM_HASH_MAP[id] = nodeData;
      return id;
    }
    const rootId = buildDomTree(document.body);
    DOM_CACHE.clearCache();
    return { rootId, map: DOM_HASH_MAP };
  };
  const DEFAULT_VIEWPORT_EXPANSION = -1;
  function resolveViewportExpansion(viewportExpansion) {
    return viewportExpansion ?? DEFAULT_VIEWPORT_EXPANSION;
  }
  const SEMANTIC_TAGS = /* @__PURE__ */ new Set([
    "nav",
    "menu",
    // 'main',
    "header",
    "footer",
    "aside",
    // 'article',
    // 'form',
    "dialog"
  ]);
  const newElementsCache = /* @__PURE__ */ new WeakMap();
  function getFlatTree(config) {
    const viewportExpansion = resolveViewportExpansion(config.viewportExpansion);
    const interactiveBlacklist = [];
    for (const item of config.interactiveBlacklist || []) {
      if (typeof item === "function") {
        interactiveBlacklist.push(item());
      } else {
        interactiveBlacklist.push(item);
      }
    }
    const interactiveWhitelist = [];
    for (const item of config.interactiveWhitelist || []) {
      if (typeof item === "function") {
        interactiveWhitelist.push(item());
      } else {
        interactiveWhitelist.push(item);
      }
    }
    const elements = domTree({
      doHighlightElements: true,
      debugMode: true,
      focusHighlightIndex: -1,
      viewportExpansion,
      interactiveBlacklist,
      interactiveWhitelist,
      highlightOpacity: config.highlightOpacity ?? 0,
      highlightLabelOpacity: config.highlightLabelOpacity ?? 0.1
    });
    const currentUrl = window.location.href;
    for (const nodeId in elements.map) {
      const node = elements.map[nodeId];
      if (node.isInteractive && node.ref) {
        const ref = node.ref;
        if (!newElementsCache.has(ref)) {
          newElementsCache.set(ref, currentUrl);
          node.isNew = true;
        }
      }
    }
    return elements;
  }
  const globRegexCache = /* @__PURE__ */ new Map();
  function globToRegex(pattern) {
    let regex = globRegexCache.get(pattern);
    if (!regex) {
      const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&");
      regex = new RegExp(`^${escaped.replace(/\*/g, ".*")}$`);
      globRegexCache.set(pattern, regex);
    }
    return regex;
  }
  function matchAttributes(attrs, patterns) {
    const result2 = {};
    for (const pattern of patterns) {
      if (pattern.includes("*")) {
        const regex = globToRegex(pattern);
        for (const key of Object.keys(attrs)) {
          if (regex.test(key) && attrs[key].trim()) {
            result2[key] = attrs[key].trim();
          }
        }
      } else {
        const value = attrs[pattern];
        if (value && value.trim()) {
          result2[pattern] = value.trim();
        }
      }
    }
    return result2;
  }
  function flatTreeToString(flatTree, includeAttributes = [], keepSemanticTags = false) {
    const DEFAULT_INCLUDE_ATTRIBUTES = [
      "title",
      "type",
      "checked",
      "name",
      "role",
      "value",
      "placeholder",
      "data-date-format",
      "alt",
      "aria-label",
      "aria-expanded",
      "data-state",
      "aria-checked",
      // @edit added for better form handling
      "id",
      "for",
      // for jump check
      "target",
      // absolute position dropdown menu
      "aria-haspopup",
      "aria-controls",
      "aria-owns",
      // content editable
      "contenteditable"
    ];
    const includeAttrs = [...includeAttributes, ...DEFAULT_INCLUDE_ATTRIBUTES];
    const capTextLength = (text, maxLength) => {
      if (text.length > maxLength) {
        return text.substring(0, maxLength) + "...";
      }
      return text;
    };
    const buildTreeNode = (nodeId) => {
      const node = flatTree.map[nodeId];
      if (!node) return null;
      if (node.type === "TEXT_NODE") {
        const textNode = node;
        return {
          type: "text",
          text: textNode.text,
          isVisible: textNode.isVisible,
          parent: null,
          children: []
        };
      } else {
        const elementNode = node;
        const children = [];
        if (elementNode.children) {
          for (const childId of elementNode.children) {
            const child = buildTreeNode(childId);
            if (child) {
              child.parent = null;
              children.push(child);
            }
          }
        }
        return {
          type: "element",
          tagName: elementNode.tagName,
          attributes: elementNode.attributes ?? {},
          isVisible: elementNode.isVisible ?? false,
          isInteractive: elementNode.isInteractive ?? false,
          isTopElement: elementNode.isTopElement ?? false,
          isNew: elementNode.isNew ?? false,
          highlightIndex: elementNode.highlightIndex,
          parent: null,
          children,
          extra: elementNode.extra ?? {}
        };
      }
    };
    const setParentReferences = (node, parent = null) => {
      node.parent = parent;
      for (const child of node.children) {
        setParentReferences(child, node);
      }
    };
    const rootNode = buildTreeNode(flatTree.rootId);
    if (!rootNode) return "";
    setParentReferences(rootNode);
    const hasParentWithHighlightIndex = (node) => {
      let current = node.parent;
      while (current) {
        if (current.type === "element" && current.highlightIndex !== void 0) {
          return true;
        }
        current = current.parent;
      }
      return false;
    };
    const processNode = (node, depth, result22) => {
      let nextDepth = depth;
      const depthStr = "	".repeat(depth);
      if (node.type === "element") {
        const isSemantic = keepSemanticTags && node.tagName && SEMANTIC_TAGS.has(node.tagName);
        if (node.highlightIndex !== void 0) {
          nextDepth += 1;
          const text = getAllTextTillNextClickableElement(node);
          let attributesHtmlStr = "";
          if (includeAttrs.length > 0 && node.attributes) {
            const attributesToInclude = matchAttributes(node.attributes, includeAttrs);
            const keys = Object.keys(attributesToInclude);
            if (keys.length > 1) {
              const keysToRemove = /* @__PURE__ */ new Set();
              const seenValues = {};
              for (const key of keys) {
                const value = attributesToInclude[key];
                if (value.length > 5) {
                  if (value in seenValues) {
                    keysToRemove.add(key);
                  } else {
                    seenValues[value] = key;
                  }
                }
              }
              for (const key of keysToRemove) {
                delete attributesToInclude[key];
              }
            }
            if (attributesToInclude.role === node.tagName) {
              delete attributesToInclude.role;
            }
            const attrsToRemoveIfTextMatches = ["aria-label", "placeholder", "title"];
            for (const attr of attrsToRemoveIfTextMatches) {
              if (attributesToInclude[attr] && attributesToInclude[attr].toLowerCase().trim() === text.toLowerCase().trim()) {
                delete attributesToInclude[attr];
              }
            }
            if (Object.keys(attributesToInclude).length > 0) {
              attributesHtmlStr = Object.entries(attributesToInclude).map(([key, value]) => `${key}=${capTextLength(value, 20)}`).join(" ");
            }
          }
          const highlightIndicator = node.isNew ? `*[${node.highlightIndex}]` : `[${node.highlightIndex}]`;
          let line = `${depthStr}${highlightIndicator}<${node.tagName ?? ""}`;
          if (attributesHtmlStr) {
            line += ` ${attributesHtmlStr}`;
          }
          if (node.extra) {
            if (node.extra.scrollable) {
              let scrollDataText = "";
              if (node.extra.scrollData?.left)
                scrollDataText += `left=${node.extra.scrollData.left}, `;
              if (node.extra.scrollData?.top) scrollDataText += `top=${node.extra.scrollData.top}, `;
              if (node.extra.scrollData?.right)
                scrollDataText += `right=${node.extra.scrollData.right}, `;
              if (node.extra.scrollData?.bottom)
                scrollDataText += `bottom=${node.extra.scrollData.bottom}`;
              line += ` data-scrollable="${scrollDataText}"`;
            }
          }
          if (text) {
            const trimmedText = text.trim();
            if (!attributesHtmlStr) {
              line += " ";
            }
            line += `>${trimmedText}`;
          } else if (!attributesHtmlStr) {
            line += " ";
          }
          line += " />";
          result22.push(line);
        }
        const emitSemantic = isSemantic && node.highlightIndex === void 0;
        const mark = emitSemantic ? result22.length : -1;
        if (emitSemantic) {
          result22.push(`${depthStr}<${node.tagName}>`);
          nextDepth += 1;
        }
        for (const child of node.children) {
          processNode(child, nextDepth, result22);
        }
        if (emitSemantic) {
          if (result22.length === mark + 1) {
            result22.pop();
          } else {
            result22.push(`${depthStr}</${node.tagName}>`);
          }
        }
      } else if (node.type === "text") {
        if (hasParentWithHighlightIndex(node)) {
          return;
        }
        if (node.parent && node.parent.type === "element" && node.parent.isVisible && node.parent.isTopElement) {
          result22.push(`${depthStr}${node.text ?? ""}`);
        }
      }
    };
    const result2 = [];
    processNode(rootNode, 0, result2);
    return result2.join("\n");
  }
  const getAllTextTillNextClickableElement = (node, maxDepth = -1) => {
    const textParts = [];
    const collectText = (currentNode, currentDepth) => {
      if (maxDepth !== -1 && currentDepth > maxDepth) {
        return;
      }
      if (currentNode.type === "element" && currentNode !== node && currentNode.highlightIndex !== void 0) {
        return;
      }
      if (currentNode.type === "text" && currentNode.text) {
        textParts.push(currentNode.text);
      } else if (currentNode.type === "element") {
        for (const child of currentNode.children) {
          collectText(child, currentDepth + 1);
        }
      }
    };
    collectText(node, 0);
    return textParts.join("\n").trim();
  };
  function getSelectorMap(flatTree) {
    const selectorMap = /* @__PURE__ */ new Map();
    const keys = Object.keys(flatTree.map);
    for (const key of keys) {
      const node = flatTree.map[key];
      if (node.isInteractive && typeof node.highlightIndex === "number") {
        selectorMap.set(node.highlightIndex, node);
      }
    }
    return selectorMap;
  }
  function getElementTextMap(simplifiedHTML) {
    const lines = simplifiedHTML.split("\n").map((line) => line.trim()).filter((line) => line.length > 0);
    const elementTextMap = /* @__PURE__ */ new Map();
    for (const line of lines) {
      const regex = /^\[(\d+)\]<[^>]+>([^<]*)/;
      const match = regex.exec(line);
      if (match) {
        const index = parseInt(match[1], 10);
        elementTextMap.set(index, line);
      }
    }
    return elementTextMap;
  }
  function cleanUpHighlights() {
    const cleanupFunctions = window._highlightCleanupFunctions || [];
    for (const cleanup of cleanupFunctions) {
      if (typeof cleanup === "function") {
        cleanup();
      }
    }
    window._highlightCleanupFunctions = [];
  }
  window.addEventListener("popstate", () => {
    cleanUpHighlights();
  });
  window.addEventListener("hashchange", () => {
    cleanUpHighlights();
  });
  window.addEventListener("beforeunload", () => {
    cleanUpHighlights();
  });
  const navigation = window.navigation;
  if (navigation && typeof navigation.addEventListener === "function") {
    navigation.addEventListener("navigate", () => {
      cleanUpHighlights();
    });
  } else {
    let currentUrl = window.location.href;
    setInterval(() => {
      if (window.location.href !== currentUrl) {
        currentUrl = window.location.href;
        cleanUpHighlights();
      }
    }, 500);
  }
  function getPageInfo() {
    const viewport_width = window.innerWidth;
    const viewport_height = window.innerHeight;
    const page_width = Math.max(document.documentElement.scrollWidth, document.body.scrollWidth || 0);
    const page_height = Math.max(
      document.documentElement.scrollHeight,
      document.body.scrollHeight || 0
    );
    const scroll_x = window.scrollX || window.pageXOffset || document.documentElement.scrollLeft || 0;
    const scroll_y = window.scrollY || window.pageYOffset || document.documentElement.scrollTop || 0;
    const pixels_below = Math.max(0, page_height - (window.innerHeight + scroll_y));
    const pixels_right = Math.max(0, page_width - (window.innerWidth + scroll_x));
    return {
      // Current viewport dimensions
      viewport_width,
      viewport_height,
      // Total page dimensions
      page_width,
      page_height,
      // Current scroll position
      scroll_x,
      scroll_y,
      pixels_above: scroll_y,
      pixels_below,
      pages_above: viewport_height > 0 ? scroll_y / viewport_height : 0,
      pages_below: viewport_height > 0 ? pixels_below / viewport_height : 0,
      total_pages: viewport_height > 0 ? page_height / viewport_height : 0,
      current_page_position: scroll_y / Math.max(1, page_height - viewport_height),
      pixels_left: scroll_x,
      pixels_right
    };
  }
  function patchReact(pageController) {
    const reactRootElements = document.querySelectorAll(
      '[data-reactroot], [data-reactid], [data-react-checksum], #root, #app, [id^="root-"], [id^="app-"], #adex-wrapper, #adex-root'
    );
    for (const element of reactRootElements) {
      element.setAttribute("data-page-agent-not-interactive", "true");
    }
  }
  class PageController extends EventTarget {
    config;
    /** Corresponds to eval_page in browser-use */
    flatTree = null;
    /**
     * All highlighted index-mapped interactive elements
     * Corresponds to DOMState.selector_map in browser-use
     */
    selectorMap = /* @__PURE__ */ new Map();
    /** Index -> element text description mapping */
    elementTextMap = /* @__PURE__ */ new Map();
    /**
     * Simplified HTML for LLM consumption.
     * Corresponds to clickable_elements_to_string in browser-use
     */
    simplifiedHTML = "<EMPTY>";
    /** last time the tree was updated */
    lastTimeUpdate = 0;
    /** Whether the tree has been indexed at least once */
    isIndexed = false;
    /** Visual mask overlay for blocking user interaction during automation */
    mask = null;
    maskReady = null;
    constructor(config = {}) {
      super();
      this.config = config;
      patchReact();
      if (config.enableMask) this.initMask();
    }
    /**
     * Initialize mask asynchronously (dynamic import to avoid CSS loading in Node)
     */
    initMask() {
      if (this.maskReady !== null) return;
      this.maskReady = (async () => {
        const { SimulatorMask: SimulatorMask2 } = await Promise.resolve().then(() => SimulatorMask$1);
        this.mask = new SimulatorMask2();
      })();
    }
    // ======= State Queries =======
    /**
     * Get current page URL
     */
    async getCurrentUrl() {
      return window.location.href;
    }
    /**
     * Get last tree update timestamp
     */
    async getLastUpdateTime() {
      return this.lastTimeUpdate;
    }
    /**
     * Get structured browser state for LLM consumption.
     * Automatically calls updateTree() to refresh the DOM state.
     */
    async getBrowserState() {
      const url = window.location.href;
      const title = document.title;
      const pi = getPageInfo();
      const viewportExpansion = resolveViewportExpansion(this.config.viewportExpansion);
      await this.updateTree();
      const content = this.simplifiedHTML;
      const titleLine = `Current Page: [${title}](${url})`;
      const pageInfoLine = `Page info: ${pi.viewport_width}x${pi.viewport_height}px viewport, ${pi.page_width}x${pi.page_height}px total page size, ${pi.pages_above.toFixed(1)} pages above, ${pi.pages_below.toFixed(1)} pages below, ${pi.total_pages.toFixed(1)} total pages, at ${(pi.current_page_position * 100).toFixed(0)}% of page`;
      const elementsLabel = viewportExpansion === -1 ? "Interactive elements from top layer of the current page (full page):" : "Interactive elements from top layer of the current page inside the viewport:";
      const hasContentAbove = pi.pixels_above > 4;
      const scrollHintAbove = hasContentAbove && viewportExpansion !== -1 ? `... ${pi.pixels_above} pixels above (${pi.pages_above.toFixed(1)} pages) - scroll to see more ...` : "[Start of page]";
      const header = `${titleLine}
${pageInfoLine}

${elementsLabel}

${scrollHintAbove}`;
      const hasContentBelow = pi.pixels_below > 4;
      const footer = hasContentBelow && viewportExpansion !== -1 ? `... ${pi.pixels_below} pixels below (${pi.pages_below.toFixed(1)} pages) - scroll to see more ...` : "[End of page]";
      return { url, title, header, content, footer };
    }
    // ======= DOM Tree Operations =======
    /**
     * Update DOM tree, returns simplified HTML for LLM.
     * This is the main method to refresh the page state.
     * Automatically bypasses mask during DOM extraction if enabled.
     */
    async updateTree() {
      this.dispatchEvent(new Event("beforeUpdate"));
      this.lastTimeUpdate = Date.now();
      if (this.mask) {
        this.mask.wrapper.style.pointerEvents = "none";
      }
      cleanUpHighlights();
      const blacklist = [
        ...this.config.interactiveBlacklist || [],
        ...Array.from(document.querySelectorAll("[data-page-agent-not-interactive]"))
      ];
      this.flatTree = getFlatTree({
        ...this.config,
        interactiveBlacklist: blacklist
      });
      this.simplifiedHTML = flatTreeToString(
        this.flatTree,
        this.config.includeAttributes,
        this.config.keepSemanticTags
      );
      this.selectorMap.clear();
      this.selectorMap = getSelectorMap(this.flatTree);
      this.elementTextMap.clear();
      this.elementTextMap = getElementTextMap(this.simplifiedHTML);
      this.isIndexed = true;
      if (this.mask) {
        this.mask.wrapper.style.pointerEvents = "auto";
      }
      this.dispatchEvent(new Event("afterUpdate"));
      return this.simplifiedHTML;
    }
    /**
     * Clean up all element highlights
     */
    async cleanUpHighlights() {
      console.log("[PageController] cleanUpHighlights");
      cleanUpHighlights();
    }
    // ======= Element Actions =======
    /**
     * Ensure the tree has been indexed before any index-based operation.
     * Throws if updateTree() hasn't been called yet.
     */
    assertIndexed() {
      if (!this.isIndexed) {
        throw new Error("DOM tree not indexed yet. Can not perform actions on elements.");
      }
    }
    /**
     * Click element by index
     */
    async clickElement(index) {
      try {
        this.assertIndexed();
        const element = getElementByIndex(this.selectorMap, index);
        const elemText = this.elementTextMap.get(index);
        await clickElement(element);
        if (isAnchorElement(element) && element.target === "_blank") {
          return {
            success: true,
            message: `✅ Clicked element (${elemText ?? index}). ⚠️ Link opened in a new tab.`
          };
        }
        return {
          success: true,
          message: `✅ Clicked element (${elemText ?? index}).`
        };
      } catch (error) {
        return {
          success: false,
          message: `❌ Failed to click element: ${error}`
        };
      }
    }
    /**
     * Input text into element by index
     */
    async inputText(index, text) {
      try {
        this.assertIndexed();
        const element = getElementByIndex(this.selectorMap, index);
        const elemText = this.elementTextMap.get(index);
        await inputTextElement(element, text);
        return {
          success: true,
          message: `✅ Input text (${text}) into element (${elemText ?? index}).`
        };
      } catch (error) {
        return {
          success: false,
          message: `❌ Failed to input text: ${error}`
        };
      }
    }
    /**
     * Select dropdown option by index and option text
     */
    async selectOption(index, optionText) {
      try {
        this.assertIndexed();
        const element = getElementByIndex(this.selectorMap, index);
        const elemText = this.elementTextMap.get(index);
        await selectOptionElement(element, optionText);
        return {
          success: true,
          message: `✅ Selected option (${optionText}) in element (${elemText ?? index}).`
        };
      } catch (error) {
        return {
          success: false,
          message: `❌ Failed to select option: ${error}`
        };
      }
    }
    /**
     * Scroll vertically
     */
    async scroll(options) {
      try {
        const { down, numPages, pixels, index } = options;
        this.assertIndexed();
        const scrollAmount = (pixels ?? numPages * window.innerHeight) * (down ? 1 : -1);
        const element = index !== void 0 ? getElementByIndex(this.selectorMap, index) : null;
        const message = await scrollVertically(scrollAmount, element);
        return {
          success: true,
          message
        };
      } catch (error) {
        return {
          success: false,
          message: `❌ Failed to scroll: ${error}`
        };
      }
    }
    /**
     * Scroll horizontally
     */
    async scrollHorizontally(options) {
      try {
        const { right, pixels, index } = options;
        this.assertIndexed();
        const scrollAmount = pixels * (right ? 1 : -1);
        const element = index !== void 0 ? getElementByIndex(this.selectorMap, index) : null;
        const message = await scrollHorizontally(scrollAmount, element);
        return {
          success: true,
          message
        };
      } catch (error) {
        return {
          success: false,
          message: `❌ Failed to scroll horizontally: ${error}`
        };
      }
    }
    /**
     * Execute arbitrary JavaScript on the page
     */
    async executeJavascript(script) {
      try {
        const asyncFunction = eval(`(async () => { ${script} })`);
        const result = await asyncFunction();
        return {
          success: true,
          message: `✅ Executed JavaScript. Result: ${result}`
        };
      } catch (error) {
        return {
          success: false,
          message: `❌ Error executing JavaScript: ${error}`
        };
      }
    }
    // ======= Mask Operations =======
    /**
     * Show the visual mask overlay.
     * Only works after mask is setup.
     */
    async showMask() {
      await this.maskReady;
      this.mask?.show();
    }
    /**
     * Hide the visual mask overlay.
     * Only works after mask is setup.
     */
    async hideMask() {
      await this.maskReady;
      this.mask?.hide();
    }
    /**
     * Dispose and clean up resources
     */
    dispose() {
      cleanUpHighlights();
      this.flatTree = null;
      this.selectorMap.clear();
      this.elementTextMap.clear();
      this.simplifiedHTML = "<EMPTY>";
      this.isIndexed = false;
      this.mask?.dispose();
      this.mask = null;
    }
  }
  function computeBorderGeometry(pixelWidth, pixelHeight, borderWidth, glowWidth) {
    const shortSide = Math.max(1, Math.min(pixelWidth, pixelHeight));
    const borderWidthPx = Math.min(borderWidth, 20);
    const glowWidthPx = glowWidth;
    const totalThick = Math.min(borderWidthPx + glowWidthPx, shortSide);
    const insetX = Math.min(totalThick, Math.floor(pixelWidth / 2));
    const insetY = Math.min(totalThick, Math.floor(pixelHeight / 2));
    const toClipX = (x) => x / pixelWidth * 2 - 1;
    const toClipY = (y) => y / pixelHeight * 2 - 1;
    const x0 = 0;
    const x1 = pixelWidth;
    const y0 = 0;
    const y1 = pixelHeight;
    const xi0 = insetX;
    const xi1 = pixelWidth - insetX;
    const yi0 = insetY;
    const yi1 = pixelHeight - insetY;
    const X0 = toClipX(x0);
    const X1 = toClipX(x1);
    const Y0 = toClipY(y0);
    const Y1 = toClipY(y1);
    const Xi0 = toClipX(xi0);
    const Xi1 = toClipX(xi1);
    const Yi0 = toClipY(yi0);
    const Yi1 = toClipY(yi1);
    const u0 = 0;
    const v0 = 0;
    const u1 = 1;
    const v1 = 1;
    const ui0 = insetX / pixelWidth;
    const ui1 = 1 - insetX / pixelWidth;
    const vi0 = insetY / pixelHeight;
    const vi1 = 1 - insetY / pixelHeight;
    const positions = new Float32Array([
      // Top strip
      X0,
      Y0,
      X1,
      Y0,
      X0,
      Yi0,
      X0,
      Yi0,
      X1,
      Y0,
      X1,
      Yi0,
      // Bottom strip
      X0,
      Yi1,
      X1,
      Yi1,
      X0,
      Y1,
      X0,
      Y1,
      X1,
      Yi1,
      X1,
      Y1,
      // Left strip
      X0,
      Yi0,
      Xi0,
      Yi0,
      X0,
      Yi1,
      X0,
      Yi1,
      Xi0,
      Yi0,
      Xi0,
      Yi1,
      // Right strip
      Xi1,
      Yi0,
      X1,
      Yi0,
      Xi1,
      Yi1,
      Xi1,
      Yi1,
      X1,
      Yi0,
      X1,
      Yi1
    ]);
    const uvs = new Float32Array([
      // Top strip
      u0,
      v0,
      u1,
      v0,
      u0,
      vi0,
      u0,
      vi0,
      u1,
      v0,
      u1,
      vi0,
      // Bottom strip
      u0,
      vi1,
      u1,
      vi1,
      u0,
      v1,
      u0,
      v1,
      u1,
      vi1,
      u1,
      v1,
      // Left strip
      u0,
      vi0,
      ui0,
      vi0,
      u0,
      vi1,
      u0,
      vi1,
      ui0,
      vi0,
      ui0,
      vi1,
      // Right strip
      ui1,
      vi0,
      u1,
      vi0,
      ui1,
      vi1,
      ui1,
      vi1,
      u1,
      vi0,
      u1,
      vi1
    ]);
    return { positions, uvs };
  }
  function compileShader(gl, type, source) {
    const shader = gl.createShader(type);
    if (!shader) throw new Error("Failed to create shader");
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      const info = gl.getShaderInfoLog(shader) || "Unknown shader error";
      gl.deleteShader(shader);
      throw new Error(info);
    }
    return shader;
  }
  function createProgram(gl, vertexSource, fragmentSource) {
    const vs = compileShader(gl, gl.VERTEX_SHADER, vertexSource);
    const fs = compileShader(gl, gl.FRAGMENT_SHADER, fragmentSource);
    const program = gl.createProgram();
    if (!program) throw new Error("Failed to create program");
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      const info = gl.getProgramInfoLog(program) || "Unknown link error";
      gl.deleteProgram(program);
      gl.deleteShader(vs);
      gl.deleteShader(fs);
      throw new Error(info);
    }
    gl.deleteShader(vs);
    gl.deleteShader(fs);
    return program;
  }
  const fragmentShaderSource = `#version 300 es
precision lowp float;
in vec2 vUV;
out vec4 outColor;
uniform vec2 uResolution;
uniform float uTime;
uniform float uBorderWidth;
uniform float uGlowWidth;
uniform float uBorderRadius;
uniform vec3 uColors[4];
uniform float uGlowExponent;
uniform float uGlowFactor;
const float PI = 3.14159265359;
const float TWO_PI = 2.0 * PI;
const float HALF_PI = 0.5 * PI;
const vec4 startPositions = vec4(0.0, PI, HALF_PI, 1.5 * PI);
const vec4 speeds = vec4(-1.9, -1.9, -1.5, 2.1);
const vec4 innerRadius = vec4(PI * 0.8, PI * 0.7, PI * 0.3, PI * 0.1);
const vec4 outerRadius = vec4(PI * 1.2, PI * 0.9, PI * 0.6, PI * 0.4);
float random(vec2 st) {
return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}
vec2 random2(vec2 st) {
return vec2(random(st), random(st + 1.0));
}
float aaStep(float edge, float d) {
float width = fwidth(d);
return smoothstep(edge - width * 0.5, edge + width * 0.5, d);
}
float aaFract(float x) {
float f = fract(x);
float w = fwidth(x);
float smooth_f = f * (1.0 - smoothstep(1.0 - w, 1.0, f));
return smooth_f;
}
float sdRoundedBox(in vec2 p, in vec2 b, in float r) {
vec2 q = abs(p) - b + r;
return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}
float getInnerGlow(vec2 p, vec2 b, float radius) {
float dist_x = b.x - abs(p.x);
float dist_y = b.y - abs(p.y);
float glow_x = smoothstep(radius, 0.0, dist_x);
float glow_y = smoothstep(radius, 0.0, dist_y);
return 1.0 - (1.0 - glow_x) * (1.0 - glow_y);
}
float getVignette(vec2 uv) {
vec2 vignetteUv = uv;
vignetteUv = vignetteUv * (1.0 - vignetteUv);
float vignette = vignetteUv.x * vignetteUv.y * 25.0;
vignette = pow(vignette, 0.16);
vignette = 1.0 - vignette;
return vignette;
}
float uvToAngle(vec2 uv) {
vec2 center = vec2(0.5);
vec2 dir = uv - center;
return atan(dir.y, dir.x) + PI;
}
void main() {
vec2 uv = vUV;
vec2 pos = uv * uResolution;
vec2 centeredPos = pos - uResolution * 0.5;
vec2 size = uResolution - uBorderWidth;
vec2 halfSize = size * 0.5;
float dBorderBox = sdRoundedBox(centeredPos, halfSize, uBorderRadius);
float border = aaStep(0.0, dBorderBox);
float glow = getInnerGlow(centeredPos, halfSize, uGlowWidth);
float vignette = getVignette(uv);
glow *= vignette;
float posAngle = uvToAngle(uv);
vec4 lightCenter = mod(startPositions + speeds * uTime, TWO_PI);
vec4 angleDist = abs(posAngle - lightCenter);
vec4 disToLight = min(angleDist, TWO_PI - angleDist) / TWO_PI;
float intensityBorder[4];
intensityBorder[0] = 1.0;
intensityBorder[1] = smoothstep(0.4, 0.0, disToLight.y);
intensityBorder[2] = smoothstep(0.4, 0.0, disToLight.z);
intensityBorder[3] = smoothstep(0.2, 0.0, disToLight.w) * 0.5;
vec3 borderColor = vec3(0.0);
for(int i = 0; i < 4; i++) {
borderColor = mix(borderColor, uColors[i], intensityBorder[i]);
}
borderColor *= 1.1;
borderColor = clamp(borderColor, 0.0, 1.0);
float intensityGlow[4];
intensityGlow[0] = smoothstep(0.9, 0.0, disToLight.x);
intensityGlow[1] = smoothstep(0.7, 0.0, disToLight.y);
intensityGlow[2] = smoothstep(0.4, 0.0, disToLight.z);
intensityGlow[3] = smoothstep(0.1, 0.0, disToLight.w) * 0.7;
vec4 breath = smoothstep(0.0, 1.0, sin(uTime * 1.0 + startPositions * PI) * 0.2 + 0.8);
vec3 glowColor = vec3(0.0);
glowColor += uColors[0] * intensityGlow[0] * breath.x;
glowColor += uColors[1] * intensityGlow[1] * breath.y;
glowColor += uColors[2] * intensityGlow[2] * breath.z;
glowColor += uColors[3] * intensityGlow[3] * breath.w * glow;
glow = pow(glow, uGlowExponent);
glow *= random(pos + uTime) * 0.1 + 1.0;
glowColor *= glow * uGlowFactor;
glowColor = clamp(glowColor, 0.0, 1.0);
vec3 color = mix(glowColor, borderColor + glowColor * 0.2, border);
float alpha = mix(glow, 1.0, border);
outColor = vec4(color, alpha);
}`;
  const vertexShaderSource = `#version 300 es
in vec2 aPosition;
in vec2 aUV;
out vec2 vUV;
void main() {
vUV = aUV;
gl_Position = vec4(aPosition, 0.0, 1.0);
}`;
  const DEFAULT_COLORS = [
    "rgb(57, 182, 255)",
    "rgb(189, 69, 251)",
    "rgb(255, 87, 51)",
    "rgb(255, 214, 0)"
  ];
  function parseColor(colorStr) {
    const match = colorStr.match(/rgb\((\d+),\s*(\d+),\s*(\d+)\)/);
    if (!match) {
      throw new Error(`Invalid color format: ${colorStr}`);
    }
    const [, r, g, b] = match;
    return [parseInt(r) / 255, parseInt(g) / 255, parseInt(b) / 255];
  }
  class Motion {
    element;
    canvas;
    options;
    running = false;
    disposed = false;
    startTime = 0;
    lastTime = 0;
    rafId = null;
    glr;
    observer;
    constructor(options = {}) {
      this.options = {
        width: options.width ?? 600,
        height: options.height ?? 600,
        ratio: options.ratio ?? window.devicePixelRatio ?? 1,
        borderWidth: options.borderWidth ?? 8,
        glowWidth: options.glowWidth ?? 200,
        borderRadius: options.borderRadius ?? 8,
        mode: options.mode ?? "light",
        ...options
      };
      this.canvas = document.createElement("canvas");
      if (this.options.classNames) {
        this.canvas.className = this.options.classNames;
      }
      if (this.options.styles) {
        Object.assign(this.canvas.style, this.options.styles);
      }
      this.canvas.style.display = "block";
      this.canvas.style.transformOrigin = "center";
      this.canvas.style.pointerEvents = "none";
      this.element = this.canvas;
      this.setupGL();
      if (!this.options.skipGreeting) this.greet();
    }
    start() {
      if (this.disposed) throw new Error("Motion instance has been disposed.");
      if (this.running) return;
      if (!this.glr) {
        console.error("WebGL resources are not initialized.");
        return;
      }
      this.running = true;
      this.startTime = performance.now();
      this.resize(this.options.width ?? 600, this.options.height ?? 600, this.options.ratio);
      this.glr.gl.viewport(0, 0, this.canvas.width, this.canvas.height);
      this.glr.gl.useProgram(this.glr.program);
      this.glr.gl.uniform2f(this.glr.uResolution, this.canvas.width, this.canvas.height);
      this.checkGLError(this.glr.gl, "start: after initial setup");
      const loop = () => {
        if (!this.running || !this.glr) return;
        this.rafId = requestAnimationFrame(loop);
        const now = performance.now();
        const delta = now - this.lastTime;
        if (delta < 1e3 / 32) return;
        this.lastTime = now;
        const t = (now - this.startTime) * 1e-3;
        this.render(t);
      };
      this.rafId = requestAnimationFrame(loop);
    }
    pause() {
      if (this.disposed) throw new Error("Motion instance has been disposed.");
      this.running = false;
      if (this.rafId !== null) cancelAnimationFrame(this.rafId);
    }
    dispose() {
      if (this.disposed) return;
      this.disposed = true;
      this.running = false;
      if (this.rafId !== null) cancelAnimationFrame(this.rafId);
      const { gl, vao, positionBuffer, uvBuffer, program } = this.glr;
      if (vao) gl.deleteVertexArray(vao);
      if (positionBuffer) gl.deleteBuffer(positionBuffer);
      if (uvBuffer) gl.deleteBuffer(uvBuffer);
      gl.deleteProgram(program);
      if (this.observer) this.observer.disconnect();
      this.canvas.remove();
    }
    resize(width, height, ratio) {
      if (this.disposed) throw new Error("Motion instance has been disposed.");
      this.options.width = width;
      this.options.height = height;
      if (ratio) this.options.ratio = ratio;
      if (!this.running) return;
      const { gl, program, vao, positionBuffer, uvBuffer, uResolution } = this.glr;
      const dpr = ratio ?? this.options.ratio ?? window.devicePixelRatio ?? 1;
      const desiredWidth = Math.max(1, Math.floor(width * dpr));
      const desiredHeight = Math.max(1, Math.floor(height * dpr));
      this.canvas.style.width = `${width}px`;
      this.canvas.style.height = `${height}px`;
      if (this.canvas.width !== desiredWidth || this.canvas.height !== desiredHeight) {
        this.canvas.width = desiredWidth;
        this.canvas.height = desiredHeight;
      }
      gl.viewport(0, 0, this.canvas.width, this.canvas.height);
      this.checkGLError(gl, "resize: after viewport setup");
      const { positions, uvs } = computeBorderGeometry(
        this.canvas.width,
        this.canvas.height,
        this.options.borderWidth * dpr,
        this.options.glowWidth * dpr
      );
      gl.bindVertexArray(vao);
      gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, positions, gl.STATIC_DRAW);
      const aPosition = gl.getAttribLocation(program, "aPosition");
      gl.enableVertexAttribArray(aPosition);
      gl.vertexAttribPointer(aPosition, 2, gl.FLOAT, false, 0, 0);
      this.checkGLError(gl, "resize: after position buffer update");
      gl.bindBuffer(gl.ARRAY_BUFFER, uvBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, uvs, gl.STATIC_DRAW);
      const aUV = gl.getAttribLocation(program, "aUV");
      gl.enableVertexAttribArray(aUV);
      gl.vertexAttribPointer(aUV, 2, gl.FLOAT, false, 0, 0);
      this.checkGLError(gl, "resize: after UV buffer update");
      gl.useProgram(program);
      gl.uniform2f(uResolution, this.canvas.width, this.canvas.height);
      gl.uniform1f(this.glr.uBorderWidth, this.options.borderWidth * dpr);
      gl.uniform1f(this.glr.uGlowWidth, this.options.glowWidth * dpr);
      gl.uniform1f(this.glr.uBorderRadius, this.options.borderRadius * dpr);
      this.checkGLError(gl, "resize: after uniform updates");
      const now = performance.now();
      this.lastTime = now;
      const t = (now - this.startTime) * 1e-3;
      this.render(t);
    }
    /**
     * Automatically resizes the canvas to match the dimensions of the given element.
     * @note using ResizeObserver
     */
    autoResize(sourceElement) {
      if (this.observer) {
        this.observer.disconnect();
      }
      this.observer = new ResizeObserver(() => {
        const rect = sourceElement.getBoundingClientRect();
        this.resize(rect.width, rect.height);
      });
      this.observer.observe(sourceElement);
    }
    fadeIn() {
      if (this.disposed) throw new Error("Motion instance has been disposed.");
      return new Promise((resolve, reject) => {
        const animation = this.canvas.animate(
          [
            { opacity: 0, transform: "scale(1.2)" },
            { opacity: 1, transform: "scale(1)" }
          ],
          { duration: 300, easing: "ease-out", fill: "forwards" }
        );
        animation.onfinish = () => resolve();
        animation.oncancel = () => reject("canceled");
      });
    }
    fadeOut() {
      if (this.disposed) throw new Error("Motion instance has been disposed.");
      return new Promise((resolve, reject) => {
        const animation = this.canvas.animate(
          [
            { opacity: 1, transform: "scale(1)" },
            { opacity: 0, transform: "scale(1.2)" }
          ],
          { duration: 300, easing: "ease-in", fill: "forwards" }
        );
        animation.onfinish = () => resolve();
        animation.oncancel = () => reject("canceled");
      });
    }
    checkGLError(gl, context) {
      let error = gl.getError();
      if (error !== gl.NO_ERROR) {
        console.group(`🔴 WebGL Error in ${context}`);
        while (error !== gl.NO_ERROR) {
          const errorName = this.getGLErrorName(gl, error);
          console.error(`${errorName} (0x${error.toString(16)})`);
          error = gl.getError();
        }
        console.groupEnd();
      }
    }
    getGLErrorName(gl, error) {
      switch (error) {
        case gl.INVALID_ENUM:
          return "INVALID_ENUM";
        case gl.INVALID_VALUE:
          return "INVALID_VALUE";
        case gl.INVALID_OPERATION:
          return "INVALID_OPERATION";
        case gl.INVALID_FRAMEBUFFER_OPERATION:
          return "INVALID_FRAMEBUFFER_OPERATION";
        case gl.OUT_OF_MEMORY:
          return "OUT_OF_MEMORY";
        case gl.CONTEXT_LOST_WEBGL:
          return "CONTEXT_LOST_WEBGL";
        default:
          return "UNKNOWN_ERROR";
      }
    }
    setupGL() {
      const gl = this.canvas.getContext("webgl2", { antialias: false, alpha: true });
      if (!gl) {
        throw new Error("WebGL2 is required but not available.");
      }
      const program = createProgram(gl, vertexShaderSource, fragmentShaderSource);
      this.checkGLError(gl, "setupGL: after createProgram");
      const vao = gl.createVertexArray();
      gl.bindVertexArray(vao);
      this.checkGLError(gl, "setupGL: after VAO creation");
      const pw = this.canvas.width || 2;
      const ph = this.canvas.height || 2;
      const { positions, uvs } = computeBorderGeometry(
        pw,
        ph,
        this.options.borderWidth,
        this.options.glowWidth
      );
      const positionBuffer = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, positions, gl.STATIC_DRAW);
      const aPosition = gl.getAttribLocation(program, "aPosition");
      gl.enableVertexAttribArray(aPosition);
      gl.vertexAttribPointer(aPosition, 2, gl.FLOAT, false, 0, 0);
      this.checkGLError(gl, "setupGL: after position buffer setup");
      const uvBuffer = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, uvBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, uvs, gl.STATIC_DRAW);
      const aUV = gl.getAttribLocation(program, "aUV");
      gl.enableVertexAttribArray(aUV);
      gl.vertexAttribPointer(aUV, 2, gl.FLOAT, false, 0, 0);
      this.checkGLError(gl, "setupGL: after UV buffer setup");
      const uResolution = gl.getUniformLocation(program, "uResolution");
      const uTime = gl.getUniformLocation(program, "uTime");
      const uBorderWidth = gl.getUniformLocation(program, "uBorderWidth");
      const uGlowWidth = gl.getUniformLocation(program, "uGlowWidth");
      const uBorderRadius = gl.getUniformLocation(program, "uBorderRadius");
      const uColors = gl.getUniformLocation(program, "uColors");
      const uGlowExponent = gl.getUniformLocation(program, "uGlowExponent");
      const uGlowFactor = gl.getUniformLocation(program, "uGlowFactor");
      gl.useProgram(program);
      gl.uniform1f(uBorderWidth, this.options.borderWidth);
      gl.uniform1f(uGlowWidth, this.options.glowWidth);
      gl.uniform1f(uBorderRadius, this.options.borderRadius);
      if (this.options.mode === "dark") {
        gl.uniform1f(uGlowExponent, 2);
        gl.uniform1f(uGlowFactor, 1.8);
      } else {
        gl.uniform1f(uGlowExponent, 1);
        gl.uniform1f(uGlowFactor, 1);
      }
      const colorVecs = (this.options.colors || DEFAULT_COLORS).map(parseColor);
      for (let i = 0; i < colorVecs.length; i++) {
        gl.uniform3f(gl.getUniformLocation(program, `uColors[${i}]`), ...colorVecs[i]);
      }
      this.checkGLError(gl, "setupGL: after uniform setup");
      gl.bindVertexArray(null);
      gl.bindBuffer(gl.ARRAY_BUFFER, null);
      this.glr = {
        gl,
        program,
        vao,
        positionBuffer,
        uvBuffer,
        uResolution,
        uTime,
        uBorderWidth,
        uGlowWidth,
        uBorderRadius,
        uColors
      };
    }
    render(t) {
      if (!this.glr) return;
      const { gl, program, vao, uTime } = this.glr;
      gl.useProgram(program);
      gl.bindVertexArray(vao);
      gl.uniform1f(uTime, t);
      gl.disable(gl.DEPTH_TEST);
      gl.disable(gl.CULL_FACE);
      gl.disable(gl.BLEND);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.drawArrays(gl.TRIANGLES, 0, 24);
      this.checkGLError(gl, "render: after draw call");
      gl.bindVertexArray(null);
    }
    greet() {
      console.log(
        `%c🌈 ai-motion ${"0.4.8"} 🌈`,
        "background: linear-gradient(90deg, #39b6ff, #bd45fb, #ff5733, #ffd600); color: white; text-shadow: 0 0 2px rgba(0, 0, 0, 0.2); font-weight: bold; font-size: 1em; padding: 2px 12px; border-radius: 6px;"
      );
    }
  }
  function hasDarkModeClass() {
    const DEFAULT_DARK_MODE_CLASSES = ["dark", "dark-mode", "theme-dark", "night", "night-mode"];
    const htmlElement = document.documentElement;
    const bodyElement = document.body || document.documentElement;
    for (const className of DEFAULT_DARK_MODE_CLASSES) {
      if (htmlElement.classList.contains(className) || bodyElement?.classList.contains(className)) {
        return true;
      }
    }
    const darkThemeAttribute = htmlElement.getAttribute("data-theme");
    if (darkThemeAttribute?.toLowerCase().includes("dark")) {
      return true;
    }
    return false;
  }
  function parseRgbColor(colorString) {
    const rgbMatch = /rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(colorString);
    if (!rgbMatch) {
      return null;
    }
    return {
      r: parseInt(rgbMatch[1]),
      g: parseInt(rgbMatch[2]),
      b: parseInt(rgbMatch[3])
    };
  }
  function isColorDark(colorString, threshold = 128) {
    if (!colorString || colorString === "transparent" || colorString.startsWith("rgba(0, 0, 0, 0)")) {
      return false;
    }
    const rgb = parseRgbColor(colorString);
    if (!rgb) {
      return false;
    }
    const luminance = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b;
    return luminance < threshold;
  }
  function isBackgroundDark() {
    const htmlStyle = window.getComputedStyle(document.documentElement);
    const bodyStyle = window.getComputedStyle(document.body || document.documentElement);
    const htmlBgColor = htmlStyle.backgroundColor;
    const bodyBgColor = bodyStyle.backgroundColor;
    if (isColorDark(bodyBgColor)) {
      return true;
    } else if (bodyBgColor === "transparent" || bodyBgColor.startsWith("rgba(0, 0, 0, 0)")) {
      return isColorDark(htmlBgColor);
    }
    return false;
  }
  function isPageDark() {
    try {
      if (hasDarkModeClass()) {
        return true;
      }
      if (isBackgroundDark()) {
        return true;
      }
      return false;
    } catch (error) {
      console.warn("Error determining if page is dark:", error);
      return false;
    }
  }
  const wrapper = "_wrapper_1ooyb_1";
  const visible = "_visible_1ooyb_11";
  const styles = {
    wrapper,
    visible
  };
  const cursor = "_cursor_1dgwb_2";
  const cursorBorder = "_cursorBorder_1dgwb_10";
  const cursorFilling = "_cursorFilling_1dgwb_25";
  const cursorRipple = "_cursorRipple_1dgwb_39";
  const clicking = "_clicking_1dgwb_57";
  const cursorStyles = {
    cursor,
    cursorBorder,
    cursorFilling,
    cursorRipple,
    clicking
  };
  class SimulatorMask extends EventTarget {
    shown = false;
    wrapper = document.createElement("div");
    motion = null;
    #disposed = false;
    #cursor = document.createElement("div");
    #currentCursorX = 0;
    #currentCursorY = 0;
    #targetCursorX = 0;
    #targetCursorY = 0;
    constructor() {
      super();
      this.wrapper.id = "page-agent-runtime_simulator-mask";
      this.wrapper.className = styles.wrapper;
      this.wrapper.setAttribute("data-browser-use-ignore", "true");
      this.wrapper.setAttribute("data-page-agent-ignore", "true");
      try {
        const motion = new Motion({
          mode: isPageDark() ? "dark" : "light",
          styles: { position: "absolute", inset: "0" }
        });
        this.motion = motion;
        this.wrapper.appendChild(motion.element);
        motion.autoResize(this.wrapper);
      } catch (e) {
        console.warn("[SimulatorMask] Motion overlay unavailable:", e);
      }
      this.wrapper.addEventListener("click", (e) => {
        e.stopPropagation();
        e.preventDefault();
      });
      this.wrapper.addEventListener("mousedown", (e) => {
        e.stopPropagation();
        e.preventDefault();
      });
      this.wrapper.addEventListener("mouseup", (e) => {
        e.stopPropagation();
        e.preventDefault();
      });
      this.wrapper.addEventListener("mousemove", (e) => {
        e.stopPropagation();
        e.preventDefault();
      });
      this.wrapper.addEventListener("wheel", (e) => {
        e.stopPropagation();
        e.preventDefault();
      });
      this.wrapper.addEventListener("keydown", (e) => {
        e.stopPropagation();
        e.preventDefault();
      });
      this.wrapper.addEventListener("keyup", (e) => {
        e.stopPropagation();
        e.preventDefault();
      });
      this.#createCursor();
      document.body.appendChild(this.wrapper);
      this.#moveCursorToTarget();
      const movePointerToListener = (event) => {
        const { x, y } = event.detail;
        this.setCursorPosition(x, y);
      };
      const clickPointerListener = () => {
        this.triggerClickAnimation();
      };
      const enablePassThroughListener = () => {
        this.wrapper.style.pointerEvents = "none";
      };
      const disablePassThroughListener = () => {
        this.wrapper.style.pointerEvents = "auto";
      };
      window.addEventListener("PageAgent::MovePointerTo", movePointerToListener);
      window.addEventListener("PageAgent::ClickPointer", clickPointerListener);
      window.addEventListener("PageAgent::EnablePassThrough", enablePassThroughListener);
      window.addEventListener("PageAgent::DisablePassThrough", disablePassThroughListener);
      this.addEventListener("dispose", () => {
        window.removeEventListener("PageAgent::MovePointerTo", movePointerToListener);
        window.removeEventListener("PageAgent::ClickPointer", clickPointerListener);
        window.removeEventListener("PageAgent::EnablePassThrough", enablePassThroughListener);
        window.removeEventListener("PageAgent::DisablePassThrough", disablePassThroughListener);
      });
    }
    #createCursor() {
      this.#cursor.className = cursorStyles.cursor;
      const rippleContainer = document.createElement("div");
      rippleContainer.className = cursorStyles.cursorRipple;
      this.#cursor.appendChild(rippleContainer);
      const fillingLayer = document.createElement("div");
      fillingLayer.className = cursorStyles.cursorFilling;
      this.#cursor.appendChild(fillingLayer);
      const borderLayer = document.createElement("div");
      borderLayer.className = cursorStyles.cursorBorder;
      this.#cursor.appendChild(borderLayer);
      this.wrapper.appendChild(this.#cursor);
    }
    #moveCursorToTarget() {
      if (this.#disposed) return;
      const newX = this.#currentCursorX + (this.#targetCursorX - this.#currentCursorX) * 0.2;
      const newY = this.#currentCursorY + (this.#targetCursorY - this.#currentCursorY) * 0.2;
      const xDistance = Math.abs(newX - this.#targetCursorX);
      if (xDistance > 0) {
        if (xDistance < 2) {
          this.#currentCursorX = this.#targetCursorX;
        } else {
          this.#currentCursorX = newX;
        }
        this.#cursor.style.left = `${this.#currentCursorX}px`;
      }
      const yDistance = Math.abs(newY - this.#targetCursorY);
      if (yDistance > 0) {
        if (yDistance < 2) {
          this.#currentCursorY = this.#targetCursorY;
        } else {
          this.#currentCursorY = newY;
        }
        this.#cursor.style.top = `${this.#currentCursorY}px`;
      }
      requestAnimationFrame(() => this.#moveCursorToTarget());
    }
    setCursorPosition(x, y) {
      if (this.#disposed) return;
      this.#targetCursorX = x;
      this.#targetCursorY = y;
    }
    triggerClickAnimation() {
      if (this.#disposed) return;
      this.#cursor.classList.remove(cursorStyles.clicking);
      void this.#cursor.offsetHeight;
      this.#cursor.classList.add(cursorStyles.clicking);
    }
    show() {
      if (this.shown || this.#disposed) return;
      this.shown = true;
      this.motion?.start();
      this.motion?.fadeIn();
      this.wrapper.classList.add(styles.visible);
      this.#currentCursorX = window.innerWidth / 2;
      this.#currentCursorY = window.innerHeight / 2;
      this.#targetCursorX = this.#currentCursorX;
      this.#targetCursorY = this.#currentCursorY;
      this.#cursor.style.left = `${this.#currentCursorX}px`;
      this.#cursor.style.top = `${this.#currentCursorY}px`;
    }
    hide() {
      if (!this.shown || this.#disposed) return;
      this.shown = false;
      this.motion?.fadeOut();
      this.motion?.pause();
      this.#cursor.classList.remove(cursorStyles.clicking);
      setTimeout(() => {
        this.wrapper.classList.remove(styles.visible);
      }, 800);
    }
    dispose() {
      this.#disposed = true;
      console.log("dispose SimulatorMask");
      this.motion?.dispose();
      this.wrapper.remove();
      this.dispatchEvent(new Event("dispose"));
    }
  }
  const SimulatorMask$1 = /* @__PURE__ */ Object.freeze(/* @__PURE__ */ Object.defineProperty({
    __proto__: null,
    SimulatorMask
  }, Symbol.toStringTag, { value: "Module" }));
  exports.PageController = PageController;
  exports.clickElement = clickElement;
  exports.getElementByIndex = getElementByIndex;
  exports.inputTextElement = inputTextElement;
  exports.scrollHorizontally = scrollHorizontally;
  exports.scrollIntoViewIfNeeded = scrollIntoViewIfNeeded;
  exports.scrollVertically = scrollVertically;
  exports.selectOptionElement = selectOptionElement;
  Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });
  return exports;
})({});
