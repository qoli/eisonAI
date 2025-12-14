console.log('[Eison-Background] loaded');

// Summary state management
let summaryState = {
  isRunning: false,
  tabId: null,
  url: null,
  status: 'idle', // idle, extracting, summarizing, completed, error
  lastUpdated: 0
};

// Safari native messaging target.
// Safari's behavior varies by platform/version; try extension bundle id first, then the containing app bundle id.
const NATIVE_APP_IDS = ['com.qoli.eisonAI.Extension', 'com.qoli.eisonAI'];

async function sendNativeMessage(request) {
  const error = new Error(
    'Native messaging is not supported from MV3 service worker on Safari. Use popup-native path.'
  );
  console.error('[Eison-Background] sendNativeMessage blocked:', { request, error });
  throw error;
}

let statusTimeoutHandle = null;

function scheduleStateTimeout(status) {
  if (statusTimeoutHandle) {
    clearTimeout(statusTimeoutHandle);
    statusTimeoutHandle = null;
  }

  const timeoutByStatus = {
    extracting: 30_000, // extraction should be quick
    summarizing: 3 * 60_000 // allow longer for LLM
  };

  const delay = timeoutByStatus[status];
  if (!delay) {
    return;
  }

  statusTimeoutHandle = setTimeout(() => {
    // Only reset if we are still in the same status when the timer fires
    if (summaryState.status === status) {
      resetSummaryState(`state timed out in '${status}' after ${delay}ms`);
    }
  }, delay);
}

function setSummaryStatus(status) {
  summaryState.status = status;
  summaryState.lastUpdated = Date.now();
  scheduleStateTimeout(status);
}

function resetSummaryState(reason) {
  if (reason) {
    console.warn(`[Eison-Background] Resetting summary state: ${reason}`);
  }
  if (statusTimeoutHandle) {
    clearTimeout(statusTimeoutHandle);
    statusTimeoutHandle = null;
  }
  summaryState.isRunning = false;
  summaryState.tabId = null;
  summaryState.url = null;
  setSummaryStatus('idle');
}

async function ensureRunningStateIsCurrent() {
  if (!summaryState.isRunning || !summaryState.tabId) {
    return;
  }

  try {
    const tab = await browser.tabs.get(summaryState.tabId);

    if (!tab || !tab.id) {
      resetSummaryState('tracked tab missing');
      return;
    }

    if (summaryState.url && tab.url !== summaryState.url) {
      resetSummaryState('tab navigated while summarizing');
    }
  } catch (error) {
    console.warn('[Eison-Background] Unable to validate running summary state, clearing it.', error);
    resetSummaryState('state validation failed');
  }
}

browser.tabs.onRemoved.addListener((tabId) => {
  if (tabId === summaryState.tabId) {
    resetSummaryState('tab closed');
  }
});

browser.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (!summaryState.isRunning) {
    return;
  }

  if (tabId === summaryState.tabId && changeInfo.url && changeInfo.url !== summaryState.url) {
    resetSummaryState('tab navigated during summary');
  }
});

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log(`[Eison-Background] Received message:`, message, 'from sender:', sender);

  if (message.command === 'getModelStatus' && !sender.tab) {
    console.error('[Eison-Background] getModelStatus called from popup; redirect to popup-native.');
    sendResponse({
      command: 'modelStatusResponse',
      state: 'failed',
      progress: 0,
      error: 'Native messaging is not supported from service worker. Please reopen popup and retry.'
    });
    return true;
  }

  // Handle summary request from popup
  if (message.command === 'runSummary' && !sender.tab) {
    console.error('[Eison-Background] runSummary called from popup; redirect to popup-native.');
    sendResponse({
      command: 'summaryResponse',
      error: 'Native messaging is not supported from service worker. Please reopen popup and retry.'
    });
    return true; // Indicates async response
  }

  // Handle summary status request from popup
  if (message.command === 'getSummaryStatus' && !sender.tab) {
    ensureRunningStateIsCurrent()
      .catch((error) => console.warn('[Eison-Background] Status validation failed:', error))
      .finally(() => {
        sendResponse({
          command: 'summaryStatusResponse',
          status: summaryState.status,
          isRunning: summaryState.isRunning
        });
      });
    return true; // Indicates async response
  }

  // Handle content extraction response from content script
  if (message.command === 'articleTextResponse' && sender.tab) {
    console.log(`[Eison-Background] Received articleTextResponse; ignored (popup-native mode).`, {
      tabId: sender.tab.id,
      hasError: Boolean(message.error),
      titleLength: (message.title || '').length,
      bodyLength: (message.body || '').length
    });
    return;
  }

  // Handle LLM response from content script
  if (message.command === 'summaryComplete') {
    console.log(`[Eison-Background] Summary completed, saving results...`);
    const tabId = sender.tab?.id || message.tabId || summaryState.tabId;
    handleSummaryComplete(message, tabId);
    return;
  }

  // Allow popup/UI to explicitly cache a completed summary
  if (message.command === 'cacheSummaryResult' && !sender.tab) {
    console.log('[Eison-Background] Caching summary result from popup/UI...');
    handleCacheSummaryRequest(message);
    return;
  }

  // Handle LLM error from content script
  if (message.command === 'summaryError' && sender.tab) {
    console.log(`[Eison-Background] Summary failed:`, message.error);
    handleSummaryError(message, sender.tab.id);
    return;
  }

  // Handle streaming updates from content script
  if (message.command === 'summaryStream' && sender.tab) {
    // Keep status up-to-date while streaming (even if service worker restarted)
    summaryState.tabId = sender.tab.id;
    summaryState.isRunning = true;
    setSummaryStatus('summarizing');

    // Forward stream updates to any listening UI (e.g., popup)
    browser.runtime.sendMessage({
      command: 'summaryStream',
      text: message.text || '',
      tabId: sender.tab.id
    });
    return;
  }

  // Forward other commands to content script (legacy support)
  if (message.command && !sender.tab) {
    console.log(`[Eison-Background] Forwarding command '${message.command}' from popup to content script.`);

    browser.tabs.query({ active: true, currentWindow: true }).then(tabs => {
      if (tabs[0] && tabs[0].id) {
        browser.tabs.sendMessage(tabs[0].id, message)
          .then(response => {
            console.log(`[Eison-Background] Received response from content script, sending back to popup.`, response);
            sendResponse(response);
          })
          .catch(e => {
            console.error("[Eison-Background] Error forwarding message to content script or receiving response:", e);
            sendResponse({ error: e.message });
          });
      } else {
        console.error("[Eison-Background] No active tab found.");
        sendResponse({ error: "No active tab found." });
      }
    });
    return true;
  }
});

// Start the summary process
async function runSummaryProcess(sendResponse) {
  try {
    await ensureRunningStateIsCurrent();

    // Check if already running
    if (summaryState.isRunning) {
      sendResponse({
        command: 'summaryResponse',
        error: '總結進行中，請稍候...'
      });
      return;
    }

    // Set state
    summaryState.isRunning = true;
    setSummaryStatus('extracting');

    // Get current tab
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    if (!tabs[0]) {
      throw new Error('No active tab found');
    }

    summaryState.tabId = tabs[0].id;
    summaryState.url = tabs[0].url;

    // Check for cached summary
    const cachedSummary = await checkCachedSummary(tabs[0].url);
    if (cachedSummary) {
      summaryState.isRunning = false;
      setSummaryStatus('completed');
      summaryState.tabId = null;
      summaryState.url = null;
      sendResponse({
        command: 'summaryResponse',
        cached: true,
        titleText: cachedSummary.titleText,
        summaryText: cachedSummary.summaryText
      });
      return;
    }

    // Send extraction request to content script
    console.log(`[Eison-Background] Requesting article extraction from tab ${tabs[0].id}`);
    const response = await browser.tabs.sendMessage(tabs[0].id, {
      command: 'getArticleText'
    });

    sendResponse({
      command: 'summaryResponse',
      status: 'started',
      message: '開始提取內容...'
    });

  } catch (error) {
    console.error('[Eison-Background] Error starting summary:', error);
    summaryState.isRunning = false;
    setSummaryStatus('error');
    summaryState.tabId = null;
    summaryState.url = null;
    sendResponse({
      command: 'summaryResponse',
      error: error.message
    });
  }
}

// Handle article extraction complete
async function handleArticleExtracted(message, tabId) {
  try {
    if (message.error) {
      throw new Error(message.error);
    }

    setSummaryStatus('summarizing');

    const tabUrl = summaryState.url || (tabId ? await getTabUrl(tabId) : null);
    const nativeResult = await summarizeViaNative({
      url: tabUrl,
      title: message.title || '',
      text: message.body || ''
    });

    await handleSummaryComplete(
      {
        titleText: nativeResult?.titleText || message.title || 'Summary',
        summaryText: nativeResult?.summaryText || '',
        url: tabUrl
      },
      tabId
    );

  } catch (error) {
    console.error('[Eison-Background] Error handling article extraction:', error);
    handleSummaryError({ error: error.message }, tabId);
  }
}

async function summarizeViaNative({ url, title, text }) {
  const requestId = crypto?.randomUUID ? crypto.randomUUID() : String(Date.now());
  const request = {
    v: 1,
    id: requestId,
    type: 'request',
    name: 'summarize.start',
    payload: {
      url: url || '',
      title: title || '',
      text: text || ''
    }
  };

  const response = await sendNativeMessage(request);

  if (!response || typeof response !== 'object') {
    throw new Error('Native response is empty');
  }

  if (response.name === 'error') {
    const message = response.payload?.message || 'Native error';
    throw new Error(message);
  }

  if (response.name !== 'summarize.done') {
    throw new Error(`Unexpected native response: ${response.name || 'unknown'}`);
  }

  const result = response.payload?.result;
  if (!result) {
    throw new Error('Native summarize result missing');
  }

  return {
    titleText: result.titleText || '',
    summaryText: result.summaryText || ''
  };
}

async function getModelStatusViaNative() {
  const requestId = crypto?.randomUUID ? crypto.randomUUID() : String(Date.now());
  const request = {
    v: 1,
    id: requestId,
    type: 'request',
    name: 'model.getStatus',
    payload: {}
  };

  const response = await sendNativeMessage(request);

  if (!response || typeof response !== 'object') {
    throw new Error('Native response is empty');
  }
  if (response.name === 'error') {
    const message = response.payload?.message || 'Native error';
    throw new Error(message);
  }
  if (response.name !== 'model.status') {
    throw new Error(`Unexpected native response: ${response.name || 'unknown'}`);
  }

  return response.payload || {};
}

// Handle summary completion
async function handleSummaryComplete(message, tabId) {
  try {
    const tabUrl = message.url || summaryState.url || (tabId ? await getTabUrl(tabId) : null);

    if (!tabUrl) {
      throw new Error('No URL available for summary cache');
    }

    // Save to cache
    await saveSummaryCache(tabUrl, {
      titleText: message.titleText,
      summaryText: message.summaryText,
      timestamp: Date.now()
    });

    console.log('[Eison-Background] Summary saved to cache for URL:', tabUrl);

    // Reset state
    summaryState.isRunning = false;
    setSummaryStatus('completed');
    summaryState.tabId = null;
    summaryState.url = null;

    // Notify any UI listeners (e.g., popup) that the summary finished
    browser.runtime.sendMessage({
      command: 'summaryStatusUpdate',
      status: 'completed',
      titleText: message.titleText,
      summaryText: message.summaryText,
      tabId,
      url: tabUrl
    }).catch((err) => {
      console.warn('[Eison-Background] Unable to notify completion:', err);
    });

  } catch (error) {
    console.error('[Eison-Background] Error handling summary completion:', error);
    handleSummaryError({ error: error.message }, tabId);
  }
}

// Handle summary error
async function handleSummaryError(message, tabId) {
  summaryState.isRunning = false;
  setSummaryStatus('error');
  summaryState.tabId = null;
  summaryState.url = null;

  console.error('[Eison-Background] Summary error:', message.error);

  browser.runtime.sendMessage({
    command: 'summaryStatusUpdate',
    status: 'error',
    error: message.error,
    tabId
  }).catch((err) => {
    console.warn('[Eison-Background] Unable to notify error:', err);
  });
}

// Cache summary result explicitly requested by popup/UI (no state updates)
async function handleCacheSummaryRequest(message) {
  try {
    const tabId = message.tabId || summaryState.tabId;
    const tabUrl = message.url || summaryState.url || (tabId ? await getTabUrl(tabId) : null);

    if (!tabUrl) {
      throw new Error('No URL available for summary cache');
    }
    if (!message.titleText || !message.summaryText) {
      throw new Error('Missing summary data for cache');
    }

    await saveSummaryCache(tabUrl, {
      titleText: message.titleText,
      summaryText: message.summaryText,
      timestamp: Date.now()
    });

    console.log('[Eison-Background] Cached summary result for URL:', tabUrl);
  } catch (error) {
    console.error('[Eison-Background] Error caching summary result:', error);
  }
}

// Check for cached summary
async function checkCachedSummary(url) {
  try {
    const result = await browser.storage.local.get('ReceiptURL');
    if (result.ReceiptURL === url) {
      const titleResult = await browser.storage.local.get('ReceiptTitleText');
      const textResult = await browser.storage.local.get('ReceiptText');

      if (titleResult.ReceiptTitleText && textResult.ReceiptText) {
        return {
          titleText: titleResult.ReceiptTitleText,
          summaryText: textResult.ReceiptText
        };
      }
    }
    return null;
  } catch (error) {
    console.error('[Eison-Background] Error checking cache:', error);
    return null;
  }
}

// Get URL for a tab, used when saving summary results
async function getTabUrl(tabId) {
  try {
    const tab = await browser.tabs.get(tabId);
    return tab?.url || null;
  } catch (error) {
    console.error('[Eison-Background] Error getting tab URL:', error);
    return null;
  }
}

// Save summary to cache
async function saveSummaryCache(url, summaryData) {
  console.log('[Eison-Background] saveSummaryCache:', url, summaryData.titleText);
  try {
    await browser.storage.local.set({
      'ReceiptURL': url,
      'ReceiptTitleText': summaryData.titleText,
      'ReceiptText': summaryData.summaryText
    });
  } catch (error) {
    console.error('[Eison-Background] Error saving cache:', error);
  }
}
