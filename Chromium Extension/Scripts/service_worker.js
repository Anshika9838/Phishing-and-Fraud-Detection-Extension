const BACKEND_API_URL = "http://localhost:8000/api/report";
const MANUAL_REPORT_API_URL = "http://localhost:8000/api/manual_report";
const BACKEND_WS_URL = "ws://localhost:8000/ws/chrome-extension";

// ===================================================
// Service Worker Lifecycle Management
// ===================================================
// These listeners ensure that the new service worker activates and takes
// control immediately upon an extension update, preventing duplicate workers
// from running simultaneously.
self.addEventListener('install', (event) => {
    self.skipWaiting();
    // Use waitUntil to ensure this logic completes before the worker moves to 'installed'.
    // This makes the "active worker" announcement atomic to the installation.
    event.waitUntil(
        (async () => {
            // Generate a unique ID for this service worker instance.
            // This is defined at the top level, so we just announce it here.
            // Announce this worker as the active one by writing its ID to shared storage.
            // This is atomic and completes before the new worker becomes active.
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
let reconnectionTimer = null; // To hold the timer ID

/**
 * Establishes a WebSocket connection with the backend.
 * Handles connection, messages, errors, and automatic reconnection.
 */
function connectWebSocket() {
    // Don't try to connect if a WebSocket instance already exists and is not closed,
    // or if a reconnection is already scheduled.
    if (ws || reconnectionTimer) {
        return;
    }

    console.log("Attempting to connect to WebSocket...");
    ws = new WebSocket(BACKEND_WS_URL);

    ws.onopen = () => {
        console.log("WebSocket connection established.");
        isWsConnected = true;
        broadcastWsStatus();
        // On successful connection, clear any potential reconnection timer.
        if (reconnectionTimer) {
            clearTimeout(reconnectionTimer);
            reconnectionTimer = null;
        }
    };

    ws.onmessage = (event) => {
        console.log("Analysis from server:", event.data);
        try {
            const analysis = JSON.parse(event.data);
            chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
                if (tabs.length > 0) {
                    const activeTabId = tabs[0].id;
                    if (analysis.threat_type !== "SAFE") {
                        showThreatAlert(activeTabId, analysis);
                    } else {
                        showSafeToast(activeTabId, analysis);
                    }
                }
            });
        } catch (error) {
            console.error("Failed to parse analysis from server:", error);
        }
    };

    ws.onerror = (error) => {
        // This is a common event when the backend is not running.
        // The onclose event will handle the reconnection logic.
        console.warn("WebSocket error. This is expected if the backend is unavailable.");
    };

    ws.onclose = () => {
        console.log("WebSocket connection closed.");
        isWsConnected = false;
        broadcastWsStatus();
        ws = null; // Ensure the old instance is cleared

        // Schedule reconnection only if one isn't already pending.
        if (!reconnectionTimer) {
            console.log("Reconnecting in 5 seconds...");
            reconnectionTimer = setTimeout(() => {
                reconnectionTimer = null; // Reset timer ID before the next attempt
                connectWebSocket();
            }, 5000);
        }
    };
}

/**
 * Sends the collected page data to the backend via a POST request.
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
    } catch (error) {
        console.error("Failed to send data to backend:", error);
    }
}

function broadcastWsStatus() {
    // Send a message to the popup if it's open.
    // The empty callback is crucial to prevent an "Uncaught (in promise)" error
    // when the popup is not open to receive the message.
    chrome.runtime.sendMessage({ type: 'WS_STATUS', isConnected: isWsConnected }, () => {
        if (chrome.runtime.lastError) {
            // This error is expected if the popup is not open, so we can safely ignore it.
        }
    });
}

/**
 * Injects a full-screen threat alert into the specified tab.
 * @param {number} tabId - The ID of the tab to inject the alert into.
 * @param {object} analysis - The analysis result from the backend.
 */
function showThreatAlert(tabId, analysis) {
    chrome.scripting.insertCSS({
        target: { tabId: tabId },
        files: ["Styles/threat_alert_style.css"]
    });

    chrome.scripting.executeScript({
        target: { tabId: tabId },
        func: (alertHtmlUrl, analysisResult) => {
            if (document.getElementById('theft-alert-overlay')) return;

            const overlay = document.createElement('div');
            overlay.id = 'theft-alert-overlay';
            
            fetch(alertHtmlUrl)
                .then(response => response.text())
                .then(html => {
                    overlay.innerHTML = html;
                    overlay.querySelector('#threat-type').textContent = analysisResult.threat_type.replace('_', ' ');
                    overlay.querySelector('#threat-description').innerHTML = analysisResult.description;
                    document.body.appendChild(overlay);

                    overlay.querySelector('#close-alert-btn').addEventListener('click', () => {
                        overlay.remove();
                    });
                });
        },
        args: [chrome.runtime.getURL("frontend/threat_alert.html"), analysis]
    });
}

/**
 * Injects a temporary "safe" toast notification into the specified tab.
 * @param {number} tabId - The ID of the tab to inject the toast into.
 * @param {object} analysis - The analysis result from the backend.
 */
function showSafeToast(tabId, analysis) {
    chrome.scripting.insertCSS({
        target: { tabId: tabId },
        files: ["Styles/toast_style.css"]
    });

    chrome.scripting.executeScript({
        target: { tabId: tabId },
        func: (analysisResult) => {
            const toast = document.createElement('div');
            toast.id = 'theft-alert-toast';
            toast.innerHTML = `✅ <strong>Secure Site</strong>`;
            document.body.appendChild(toast);

            setTimeout(() => {
                toast.classList.add('show');
            }, 100);

            setTimeout(() => {
                toast.classList.remove('show');
                setTimeout(() => toast.remove(), 500);
            }, 4000);
        },
        args: [analysis]
    });
}

// Listen for messages from content scripts or popup
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    const frameId = sender.frameId;
    console.log(`[DEBUG] service_worker.js | ID: ${WORKER_INSTANCE_ID} | Message received. Type: ${message.type}, from tab: ${sender.tab?.id}, frameId: ${frameId}`);

    // Use an async IIFE to handle the async check.
    (async () => {
        const { activeWorkerId } = await chrome.storage.local.get('activeWorkerId');
        console.log(`[DEBUG] service_worker.js | ID: ${WORKER_INSTANCE_ID} | Active worker check. My ID: ${WORKER_INSTANCE_ID}, Active ID in storage: ${activeWorkerId}`);

        // Ensure only the most recent, active service worker instance handles the message.
        // This check now reliably compares the ID from storage with this worker's constant ID.
        if (activeWorkerId !== WORKER_INSTANCE_ID) {
            console.warn(`[DEBUG] Stale service worker (ID: ${WORKER_INSTANCE_ID}) received a message, ignoring. Active ID is ${activeWorkerId}.`);
            return; // Stop further processing by this stale worker.
        }
        console.log(`[DEBUG] service_worker.js | ID: ${WORKER_INSTANCE_ID} | I am the active worker. Processing message.`);
        if (message.type === "PAGE_DATA") {
            console.log(`Received page data from tab: ${sender.tab.id}, frameId: ${frameId}`);
            // Add a field to distinguish this log type in the backend.
            const reportData = { ...message.data, reportType: 'full_page_scan' };
            await sendDataToBackend(reportData, BACKEND_API_URL);
        } else if (message.type === "NETWORK_REQUEST") {
            console.log("Received network request from tab:", sender.tab.id, message.data.url);
            // Construct a payload with network activity and its source.
            const networkData = {
                ...message.data,
                reportType: 'network_activity', // Differentiate this log entry.
                sourcePageUrl: sender.tab.url,
                sourcePageDomain: new URL(sender.tab.url).hostname,
            };
            await sendDataToBackend(networkData, BACKEND_API_URL);
        } else if (message.type === "MANUAL_REPORT") {
            console.log("Received manual report for:", message.data.url);
            await sendDataToBackend(message.data, MANUAL_REPORT_API_URL);
        } 
        else if (message.type === 'GET_WS_STATUS') {
            sendResponse({ isConnected: isWsConnected });
            // Also broadcast to ensure popup gets it if it opens after the initial connection
            broadcastWsStatus();
        }
    })();

    // Return true to indicate you wish to send a response asynchronously
    return true;
});

// Initialize WebSocket connection when the extension starts
connectWebSocket();