// Summary state management
let summaryState = {
  isRunning: false,
  tabId: null,
  status: 'idle' // idle, extracting, summarizing, completed, error
};

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log(`[Eison-Background] Received message:`, message, 'from sender:', sender);
  
  // Handle summary request from popup
  if (message.command === 'runSummary' && !sender.tab) {
    console.log(`[Eison-Background] Starting summary process...`);
    runSummaryProcess(sendResponse);
    return true; // Indicates async response
  }
  
  // Handle summary status request from popup
  if (message.command === 'getSummaryStatus' && !sender.tab) {
    sendResponse({
      command: 'summaryStatusResponse',
      status: summaryState.status,
      isRunning: summaryState.isRunning
    });
    return;
  }
  
  // Handle content extraction response from content script
  if (message.command === 'articleTextResponse' && sender.tab) {
    console.log(`[Eison-Background] Received article text, starting LLM processing...`);
    handleArticleExtracted(message, sender.tab.id);
    return;
  }
  
  // Handle LLM response from content script
  if (message.command === 'summaryComplete' && sender.tab) {
    console.log(`[Eison-Background] Summary completed, saving results...`);
    handleSummaryComplete(message, sender.tab.id);
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
    // Keep status up-to-date while streaming
    if (summaryState.tabId === sender.tab.id) {
      summaryState.status = 'summarizing';
    }

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
    summaryState.status = 'extracting';
    
    // Get current tab
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    if (!tabs[0]) {
      throw new Error('No active tab found');
    }
    
    summaryState.tabId = tabs[0].id;
    
    // Check for cached summary
    const cachedSummary = await checkCachedSummary(tabs[0].url);
    if (cachedSummary) {
      summaryState.isRunning = false;
      summaryState.status = 'completed';
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
    summaryState.status = 'error';
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
    
    summaryState.status = 'summarizing';
    
    // Send to content script for LLM processing
    await browser.tabs.sendMessage(tabId, {
      command: 'processSummary',
      articleText: message.body,
      articleTitle: message.title
    });
    
  } catch (error) {
    console.error('[Eison-Background] Error handling article extraction:', error);
    handleSummaryError({ error: error.message }, tabId);
  }
}

// Handle summary completion
async function handleSummaryComplete(message, tabId) {
  try {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    const currentTab = tabs[0];
    
    if (currentTab) {
      // Save to cache
      await saveSummaryCache(currentTab.url, {
        titleText: message.titleText,
        summaryText: message.summaryText,
        timestamp: Date.now()
      });
      
      console.log('[Eison-Background] Summary saved to cache for URL:', currentTab.url);
    }
    
    // Reset state
    summaryState.isRunning = false;
    summaryState.status = 'completed';
    summaryState.tabId = null;
    
  } catch (error) {
    console.error('[Eison-Background] Error handling summary completion:', error);
    handleSummaryError({ error: error.message }, tabId);
  }
}

// Handle summary error
async function handleSummaryError(message, tabId) {
  summaryState.isRunning = false;
  summaryState.status = 'error';
  summaryState.tabId = null;
  
  console.error('[Eison-Background] Summary error:', message.error);
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

// Save summary to cache
async function saveSummaryCache(url, summaryData) {
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
