const BACKEND_API_URL = "http://localhost:8000/api/report";
const MANUAL_REPORT_API_URL = "http://localhost:8000/api/manual_report";
const BACKEND_WS_URL = "ws://localhost:8000/ws/chrome-extension";
const RECENT_ANALYSIS_TTL_MS = 15000;
const SCAN_STATE_TTL_MS = 180000;

// ===================================================
// Service Worker Lifecycle Management
// ===================================================
// These listeners ensure that the new service worker activates and takes
// control immediately upon an extension update, preventing duplicate workers
// from running simultaneously.
self.addEventListener('install', (event) => {
    self.skipWaiting();
    event.waitUntil(
        (async () => {
            await chrome.storage.local.set({ activeWorkerId: WORKER_INSTANCE_ID });
        })()
    );
});

self.addEventListener('activate', (event) => {
    event.waitUntil(self.clients.claim());
});

// Unique ID for this service worker instance to prevent stale workers from processing messages.
const WORKER_INSTANCE_ID = self.crypto.randomUUID();
console.log(`[DEBUG ANCHOR] service_worker.js | NEW INSTANCE STARTED | ID: ${WORKER_INSTANCE_ID}`);

let ws = null;
let isWsConnected = false;
let reconnectionTimer = null;
let activeScans = new Map(); // Track active scans by tabId
const recentAnalysisByTab = new Map();

async function setScanState(tabId, scanState) {
    if (!tabId) return;

    if (scanState) {
        activeScans.set(tabId, scanState);
        await chrome.storage.local.set({ [`scan_state_${tabId}`]: scanState });
        chrome.runtime.sendMessage({
            type: 'SCAN_STARTED',
            tabId,
            url: scanState.url,
            scanTrigger: scanState.scanTrigger
        }, () => { if (chrome.runtime.lastError) { /* Popup not open, ignore */ } });
        return;
    }

    activeScans.delete(tabId);
    await chrome.storage.local.remove(`scan_state_${tabId}`);
}

/**
 * Establishes a WebSocket connection with the backend.
 * Handles connection, messages, errors, and automatic reconnection.
 */
function connectWebSocket() {
    if (ws || reconnectionTimer) {
        return;
    }

    console.log("Attempting to connect to WebSocket...");
    ws = new WebSocket(BACKEND_WS_URL);

    ws.onopen = () => {
        console.log("WebSocket connection established.");
        isWsConnected = true;
        broadcastWsStatus();
        if (reconnectionTimer) {
            clearTimeout(reconnectionTimer);
            reconnectionTimer = null;
        }
    };

    ws.onmessage = (event) => {
        console.log("Analysis from server:", event.data);
        try {
            const analysis = JSON.parse(event.data);
            renderBroadcastAnalysis(analysis);
        } catch (error) {
            console.error("Failed to parse analysis from server:", error);
        }
    };

    ws.onerror = () => {
        console.warn("WebSocket error. This is expected if the backend is unavailable.");
    };

    ws.onclose = () => {
        console.log("WebSocket connection closed.");
        isWsConnected = false;
        broadcastWsStatus();
        ws = null;

        if (!reconnectionTimer) {
            console.log("Reconnecting in 5 seconds...");
            reconnectionTimer = setTimeout(() => {
                reconnectionTimer = null;
                connectWebSocket();
            }, 5000);
        }
    };
}

/**
 * Sends data to the backend and returns the parsed JSON response.
 * @param {object} pageData - The data collected from the content script.
 * @param {string} apiUrl - The backend endpoint to send data to.
 */
async function sendDataToBackend(pageData, apiUrl) {
    console.log(`[DEBUG ANCHOR 5/5] service_worker.js | ID: ${WORKER_INSTANCE_ID} | Sending data to backend API: ${apiUrl}`);
    try {
        const response = await fetch(apiUrl, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(pageData),
        });

        if (!response.ok) {
            throw new Error(`HTTP error! Status: ${response.status}`);
        }

        const result = await response.json();
        console.log("Backend response:", result);
        return result;
    } catch (error) {
        console.error("Failed to send data to backend:", error);
        return null;
    }
}

function broadcastWsStatus() {
    chrome.runtime.sendMessage({ type: 'WS_STATUS', isConnected: isWsConnected }, () => {
        if (chrome.runtime.lastError) {
            // Popup is not open; safe to ignore.
        }
    });
}

function renderBroadcastAnalysis(analysis) {
    if (!analysis || analysis.report_type !== 'full_page_scan') {
        return;
    }

    const targetUrl = analysis.page_url || analysis.url;
    chrome.tabs.query({}, (tabs) => {
        if (chrome.runtime.lastError) {
            console.warn("Could not query tabs for analysis render:", chrome.runtime.lastError.message);
            return;
        }

        const matchingTab = tabs.find((tab) => tab.id && tab.url === targetUrl);
        const activeTab = tabs.find((tab) => tab.id && tab.active && tab.currentWindow);
        const tab = matchingTab || activeTab;

        if (tab?.id) {
            renderAnalysisForTab(tab.id, analysis).catch((error) => {
                console.error("Failed to render broadcast analysis:", error);
            });
        }
    });
}

async function renderAnalysisForTab(tabId, analysis) {
    // Save the latest analysis for this tab to be retrieved by the popup later.
    await setScanState(tabId, null);
    await chrome.storage.local.set({ [`latest_analysis_${tabId}`]: analysis });
    await updateScanHistory(analysis);

    const viewModel = buildAnalysisViewModel(analysis);

    // Also send a direct message to the popup if it's open
    const { scanHistory = [] } = await chrome.storage.local.get('scanHistory');
    chrome.runtime.sendMessage({
        type: 'ANALYSIS_COMPLETE',
        analysis: analysis,
        history: scanHistory
    }, () => {
        if (chrome.runtime.lastError) { /* Popup not open, ignore */ }
    });

    if (!shouldDisplayAnalysis(tabId, viewModel)) {
        return;
    }

    // Show in-page alerts
    if (viewModel.threatType === 'SAFE' || viewModel.riskScore < 40) {
        showSafeToast(tabId, viewModel);
    } else {
        showThreatAlert(tabId, viewModel);
    }
}

function shouldDisplayAnalysis(tabId, viewModel) {
    const now = Date.now();
    const key = [viewModel.url, viewModel.threatType, viewModel.riskScore, viewModel.reason].join('|');
    const previous = recentAnalysisByTab.get(tabId);

    recentAnalysisByTab.set(tabId, { key, time: now });
    return !(previous && previous.key === key && now - previous.time < RECENT_ANALYSIS_TTL_MS);
}

/**
 * Saves the analysis to a rolling history in chrome.storage.
 * @param {object} analysis - The full analysis object from the backend.
 */
async function updateScanHistory(analysis) {
    if (!analysis || !analysis.domain) return;

    const { scanHistory: storedScanHistory = [] } = await chrome.storage.local.get('scanHistory');
    const scanHistory = Array.isArray(storedScanHistory) ? storedScanHistory : [];
    const normalizedDomain = String(analysis.domain || '').replace(/^www\./, '').toLowerCase();
    const historyEntry = {
        ...analysis,
        domain: normalizedDomain || analysis.domain,
        scan_trigger: analysis.scan_trigger || analysis.scanTrigger || 'unknown',
        checked_at: analysis.checked_at || new Date().toISOString(),
    };

    // Remove previous entry for the same domain to prevent duplicates
    const filteredHistory = scanHistory.filter(item => String(item.domain || '').replace(/^www\./, '').toLowerCase() !== historyEntry.domain);

    // Add the new analysis to the front of the array
    const newHistory = [historyEntry, ...filteredHistory];

    // Keep only the 5 most recent unique domain scans
    const trimmedHistory = newHistory.slice(0, 5);

    await chrome.storage.local.set({ scanHistory: trimmedHistory });
}

function buildAnalysisViewModel(analysis) {
    const riskScore = normalizeRiskScore(analysis?.risk_score ?? analysis?.score);
    const threatType = normalizeThreatType(analysis?.threat_type, riskScore);
    const reason = compactText(analysis?.brief_reason || analysis?.description || fallbackReason(threatType), 180);
    const description = compactText(analysis?.description || reason, 420);
    const recommendation = compactText(analysis?.recommendation || fallbackRecommendation(threatType), 220);
    const evidence = Array.isArray(analysis?.evidence)
        ? analysis.evidence.map((item) => compactText(item, 180)).filter(Boolean).slice(0, 4)
        : [];

    return {
        riskScore,
        safetyScore: Math.max(0, 100 - riskScore),
        threatType,
        reason,
        description,
        recommendation,
        evidence,
        title: threatType === 'SAFE' ? 'Secure Site' : (riskScore < 50 ? 'Low Risk Site' : 'Potentially Unsafe Site'),
        url: analysis?.page_url || analysis?.url || '',
        source: analysis?.analysis_source || 'analysis',
    };
}

function normalizeRiskScore(value) {
    const number = Number(value);
    if (!Number.isFinite(number)) {
        return 50;
    }

    const score = number >= 0 && number <= 1 ? number * 100 : number;
    return Math.max(0, Math.min(100, Math.round(score)));
}

function normalizeThreatType(value, riskScore) {
    const threatType = String(value || '').toUpperCase().replace(/[^A-Z0-9_]+/g, '_').replace(/^_+|_+$/g, '');
    if (threatType) {
        return threatType;
    }
    if (riskScore >= 75) return 'PHISHING';
    if (riskScore >= 50) return 'SUSPICIOUS';
    if (riskScore >= 25) return 'LOW_RISK';
    return 'SAFE';
}

function compactText(value, limit) {
    const text = String(value || '').replace(/\s+/g, ' ').trim();
    if (text.length <= limit) {
        return text;
    }
    return `${text.slice(0, Math.max(0, limit - 3)).trim()}...`;
}

function fallbackReason(threatType) {
    return threatType === 'SAFE'
        ? 'No strong phishing or fraud indicators were found in the captured scan.'
        : 'The page has signals that should be reviewed before entering sensitive information.';
}

function fallbackRecommendation(threatType) {
    return threatType === 'SAFE'
        ? 'No immediate action is required, but stay alert before entering sensitive information.'
        : 'Avoid entering passwords, payment details, OTPs, or identity information until you verify the site.';
}

/**
 * Injects a full-screen threat alert into the specified tab.
 * @param {number} tabId - The ID of the tab to inject the alert into.
 * @param {object} viewModel - Normalized analysis data for display.
 */
function showProcessingIndicator(tabId) {
    chrome.scripting.insertCSS({
        target: { tabId: tabId },
        files: ["Styles/toast_style.css"] // Reuse toast styles for positioning
    });

    chrome.scripting.executeScript({
        target: { tabId: tabId },
        func: () => {
            // Remove any existing UI from this extension first
            document.getElementById('theft-alert-toast')?.remove();
            document.getElementById('theft-alert-overlay')?.remove();
            document.getElementById('theft-alert-processing-indicator')?.remove();

            const indicator = document.createElement('div');
            indicator.id = 'theft-alert-processing-indicator';
            indicator.className = 'theft-alert-toast'; 
            indicator.setAttribute('role', 'status');
            indicator.style.padding = '16px';
            indicator.innerHTML = `
                <div style="display: flex; align-items: center; justify-content: center; gap: 10px;">
                    <strong style="font-size: 16px;">Theft Alert: Analyzing page...</strong>
                </div>
            `;

            document.body.appendChild(indicator);

            setTimeout(() => {
                indicator.classList.add('show');
            }, 100);
        }
    });
}

function showThreatAlert(tabId, viewModel) {
    chrome.scripting.insertCSS({
        target: { tabId: tabId },
        files: ["Styles/threat_alert_style.css"]
    });

    chrome.scripting.executeScript({
        target: { tabId: tabId },
        func: (model) => {
            // DEBUG: Log the full analysis result to the page's console.
            console.log('[DEBUG] Backend Analysis Result (Threat):', model);

            document.getElementById('theft-alert-overlay')?.remove();
            document.getElementById('theft-alert-processing-indicator')?.remove();

            const overlay = document.createElement('div');
            overlay.id = 'theft-alert-overlay';

            fetch(chrome.runtime.getURL("frontend/threat_alert.html"))
                .then((response) => response.text())
                .then((html) => {
                    overlay.innerHTML = html;

                    const setText = (selector, value) => {
                        const element = overlay.querySelector(selector);
                        if (element) {
                            element.textContent = value || '';
                        }
                    };

                    setText('#threat-type', model.threatType.replace(/_/g, ' '));
                    setText('#threat-score', `${model.riskScore}/100`);
                    setText('#threat-reason', model.reason);
                    setText('#threat-description', model.description);
                    setText('#threat-recommendation', model.recommendation);

                    const evidenceList = overlay.querySelector('#threat-evidence');
                    if (evidenceList) {
                        evidenceList.innerHTML = '';
                        model.evidence.forEach((item) => {
                            const li = document.createElement('li');
                            li.textContent = item;
                            evidenceList.appendChild(li);
                        });
                    }

                    document.body.appendChild(overlay);

                    overlay.querySelector('#close-alert-btn')?.addEventListener('click', () => {
                        overlay.remove();
                    });
                });
        },
        args: [viewModel]
    });
}

/**
 * Injects a temporary safe-site score card into the specified tab.
 * @param {number} tabId - The ID of the tab to inject the toast into.
 * @param {object} viewModel - Normalized analysis data for display.
 */
function showSafeToast(tabId, viewModel) {
    chrome.scripting.insertCSS({
        target: { tabId: tabId },
        files: ["Styles/toast_style.css"]
    });

    chrome.scripting.executeScript({
        target: { tabId: tabId },
        func: (model) => {
            document.getElementById('theft-alert-toast')?.remove();
            document.getElementById('theft-alert-processing-indicator')?.remove();

            const toast = document.createElement('div');
            toast.id = 'theft-alert-toast';
            toast.setAttribute('role', 'status');
            toast.innerHTML = `
                <div class="theft-alert-toast-header">
                    <div>
                        <div class="theft-alert-kicker">Theft Alert</div>
                        <strong data-field="title"></strong>
                    </div>
                    <button type="button" class="theft-alert-toast-close" aria-label="Dismiss Theft Alert">x</button>
                </div>
                <div class="theft-alert-score-row">
                    <span>Safety score</span>
                    <strong data-field="score"></strong>
                </div>
                <p data-field="reason"></p>
                <p class="theft-alert-recommendation" data-field="recommendation"></p>
            `;

            toast.querySelector('[data-field="title"]').textContent = model.title;
            toast.querySelector('[data-field="score"]').textContent = `${model.safetyScore}/100`;
            toast.querySelector('[data-field="reason"]').textContent = model.reason;
            toast.querySelector('[data-field="recommendation"]').textContent = model.recommendation;
            toast.querySelector('.theft-alert-toast-close')?.addEventListener('click', () => toast.remove());

            document.body.appendChild(toast);

            setTimeout(() => {
                toast.classList.add('show');
            }, 100);

            setTimeout(() => {
                toast.classList.remove('show');
                setTimeout(() => toast.remove(), 500);
            }, 10000);
        },
        args: [viewModel]
    });
}

// Listen for messages from content scripts or popup
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    const frameId = sender.frameId;
    console.log(`[DEBUG] service_worker.js | ID: ${WORKER_INSTANCE_ID} | Message received. Type: ${message.type}, from tab: ${sender.tab?.id}, frameId: ${frameId}`);

    (async () => {
        const { activeWorkerId } = await chrome.storage.local.get('activeWorkerId');
        console.log(`[DEBUG] service_worker.js | ID: ${WORKER_INSTANCE_ID} | Active worker check. My ID: ${WORKER_INSTANCE_ID}, Active ID in storage: ${activeWorkerId}`);

        if (activeWorkerId !== WORKER_INSTANCE_ID) {
            console.warn(`[DEBUG] Stale service worker (ID: ${WORKER_INSTANCE_ID}) received a message, ignoring. Active ID is ${activeWorkerId}.`);
            return;
        }

        console.log(`[DEBUG] service_worker.js | ID: ${WORKER_INSTANCE_ID} | I am the active worker. Processing message.`);
        if (message.type === "PAGE_DATA") {
            console.log(`Received page data from tab: ${sender.tab.id}, frameId: ${frameId}`);
            const reportData = { ...message.data, reportType: 'full_page_scan' };

            // Show processing indicator immediately for top-frame scans
            if (reportData.isTopFrame && sender.tab?.id) {
                await setScanState(sender.tab.id, {
                    url: reportData.url,
                    scanTrigger: reportData.scanTrigger || 'initial_load',
                    startedAt: Date.now(),
                });
                showProcessingIndicator(sender.tab.id);
            }

            const result = await sendDataToBackend(reportData, BACKEND_API_URL);

            if (result?.analysis && sender.tab?.id) {
                const fullAnalysis = result.analysis;
                await renderAnalysisForTab(sender.tab.id, fullAnalysis);
            } else if (sender.tab?.id) {
                await setScanState(sender.tab.id, null);
            }
        } else if (message.type === "NETWORK_REQUEST") {
            console.log("Received network request from tab:", sender.tab.id, message.data.url);
            const networkData = {
                ...message.data,
                reportType: 'network_activity',
                sourcePageUrl: sender.tab.url,
                sourcePageDomain: new URL(sender.tab.url).hostname,
            };
            await sendDataToBackend(networkData, BACKEND_API_URL);
        } else if (message.type === "MANUAL_REPORT") {
            console.log("Received manual report for:", message.data.url);
            await sendDataToBackend(message.data, MANUAL_REPORT_API_URL);
        } else if (message.type === 'GET_WS_STATUS') {
            sendResponse({ isConnected: isWsConnected });
            broadcastWsStatus();
        } else if (message.type === 'GET_POPUP_DATA') {
            (async () => {
                try {
                    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
                    if (!tab || !tab.id) {
                        sendResponse({ tab: null, analysis: null, history: [], isConnected: isWsConnected, isScanning: false });
                        return;
                    }
                    const { [`latest_analysis_${tab.id}`]: analysis } = await chrome.storage.local.get(`latest_analysis_${tab.id}`);
                    const { [`scan_state_${tab.id}`]: storedScanState } = await chrome.storage.local.get(`scan_state_${tab.id}`);
                    const { scanHistory: storedScanHistory = [] } = await chrome.storage.local.get('scanHistory');
                    const scanHistory = Array.isArray(storedScanHistory) ? storedScanHistory : [];
                    let scanState = activeScans.get(tab.id) || storedScanState || null;
                    if (scanState?.startedAt && Date.now() - scanState.startedAt > SCAN_STATE_TTL_MS) {
                        await setScanState(tab.id, null);
                        scanState = null;
                    }
                    sendResponse({ tab, analysis: analysis || null, history: scanHistory, isConnected: isWsConnected, isScanning: Boolean(scanState), scanState });
                } catch (error) {
                    console.error("Failed to get popup data:", error);
                    sendResponse({ tab: null, analysis: null, history: [], isConnected: isWsConnected, isScanning: false });
                }
            })();
            return true; // Keep message channel open for async response
        } else if (message.type === 'TRIGGER_MANUAL_SCAN') {
            if (message.tabId) {
                const tab = await chrome.tabs.get(message.tabId);
                await setScanState(message.tabId, {
                    url: tab?.url || '',
                    scanTrigger: 'manual_popup',
                    startedAt: Date.now(),
                });
                showProcessingIndicator(message.tabId);
                // Ask the content script in the target tab to collect and send its data.
                // Explicitly target frameId: 0 to ensure we message the main document, not an iframe.
                chrome.tabs.sendMessage(message.tabId, { type: "REQUEST_PAGE_DATA", trigger: "manual_popup" }, { frameId: 0 })
                    .catch(error => {
                        console.error(`Could not send 'REQUEST_PAGE_DATA' to tab ${message.tabId}. The content script might not be active or injected on this page. Error: ${error.message}`);
                        setScanState(message.tabId, null);
                    });
            }
        }
    })();

    return true;
});

// Initialize WebSocket connection when the extension starts
connectWebSocket();
