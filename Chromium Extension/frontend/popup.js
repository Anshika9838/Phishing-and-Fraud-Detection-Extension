const viewContainer = document.getElementById('view-container');
const homeBtn = document.getElementById('home-btn');
const historyBtn = document.getElementById('history-btn');
const statusIndicator = document.getElementById('status-indicator');

let currentTab = null;
let currentAnalysis = null;
let scanHistory = [];

const templates = {
    home: document.getElementById('home-view-template'),
    loading: document.getElementById('loading-view-template'),
    results: document.getElementById('results-view-template'),
    history: document.getElementById('history-view-template'),
};

/**
 * Main initialization function.
 */
document.addEventListener('DOMContentLoaded', async () => {
    // Request initial data from the service worker
    const popupData = await chrome.runtime.sendMessage({ type: 'GET_POPUP_DATA' });

    currentTab = popupData.tab;
    currentAnalysis = popupData.analysis;
    scanHistory = popupData.history;
    updateStatusIndicator(popupData.isConnected);

    if (popupData.isScanning) { // Show loading if a scan is in progress
        renderLoadingView();
    } else if (currentAnalysis) {
        renderResultsView(currentAnalysis);
    } else {
        renderHomeView();
    }

    homeBtn.addEventListener('click', () => showView('home'));
    historyBtn.addEventListener('click', () => showView('history'));
});

/**
 * Listen for messages from the service worker (e.g., new analysis, status updates).
 */
chrome.runtime.onMessage.addListener((message, sender) => {
    console.log('[DEBUG] popup.js: Received message', message);

    const normalizeUrl = (url) => {
        if (!url) return '';
        try {
            const urlObj = new URL(url);
            // Compare only origin and pathname, ignoring hash, search params, and trailing slashes.
            return (urlObj.origin + urlObj.pathname).replace(/\/$/, '');
        } catch {
            return url; // Fallback for invalid URLs
        }
    };

    if (message.type === 'ANALYSIS_COMPLETE' && normalizeUrl(message.analysis.page_url) === normalizeUrl(currentTab?.url)) {
        currentAnalysis = message.analysis;
        scanHistory = message.history; // History is updated with the new scan
        renderResultsView(currentAnalysis);
    } else if (message.type === 'SCAN_STARTED' && message.tabId === currentTab?.id) {
        // If a scan starts for the current tab, show loading view
        renderLoadingView();
    } else if (message.type === 'WS_STATUS') {
        updateStatusIndicator(message.isConnected);
    } else if (message.type === 'ANALYSIS_COMPLETE') {
        // Log why the analysis was not displayed if the URLs didn't match
        console.warn(`[DEBUG] popup.js: Ignored ANALYSIS_COMPLETE because URLs did not match. Popup URL: ${normalizeUrl(currentTab?.url)}, Analysis URL: ${normalizeUrl(message.analysis.page_url)}`);
    }
});

function updateStatusIndicator(isConnected) {
    statusIndicator.className = isConnected ? 'connected' : 'disconnected';
    statusIndicator.title = `Backend: ${isConnected ? 'Connected' : 'Disconnected'}`;
}

function showView(viewName) {
    homeBtn.classList.toggle('active', viewName === 'home');
    historyBtn.classList.toggle('active', viewName === 'history');

    if (viewName === 'home') {
        currentAnalysis ? renderResultsView(currentAnalysis) : renderHomeView();
    } else if (viewName === 'history') {
        renderHistoryView();
    }
}

function renderView(templateId, setupFn) {
    const template = templates[templateId];
    if (!template) return;
    viewContainer.innerHTML = '';
    const view = template.content.cloneNode(true);
    if (setupFn) {
        setupFn(view);
    }
    viewContainer.appendChild(view);
}

function renderHomeView() {
    renderView('home', (view) => {
        const urlDisplay = view.querySelector('.url-display');
        const scanBtn = view.querySelector('#scan-current-page-btn');

        if (currentTab && currentTab.url && !currentTab.url.startsWith('chrome://')) {
            urlDisplay.textContent = currentTab.url;
            scanBtn.disabled = false;
            scanBtn.addEventListener('click', requestScan);
        } else {
            urlDisplay.textContent = currentTab ? currentTab.url : '[No active tab]';
            scanBtn.textContent = 'Cannot scan this page';
        }
    });
}

function renderLoadingView() {
    renderView('loading', (view) => {
        view.querySelector('.url-display').textContent = currentTab?.url || '';
    });
}

function renderResultsView(analysis) {
    renderView('results', (view) => {
        const score = analysis.risk_score;
        const scoreCircle = view.querySelector('.score-circle');
        scoreCircle.className = 'score-circle'; // Reset classes
        if (score >= 75) scoreCircle.classList.add('malicious');
        else if (score >= 40) scoreCircle.classList.add('suspicious');

        view.querySelector('.score-value').textContent = score;
        view.querySelector('.threat-type').textContent = analysis.threat_type.replace(/_/g, ' ');
        view.querySelector('.url-display').textContent = analysis.url;
        view.querySelector('.brief-reason').textContent = analysis.brief_reason;
        view.querySelector('.recommendation').textContent = analysis.recommendation;
        view.querySelector('.llm-description').textContent = analysis.description;

        // Populate evidence
        const evidenceList = view.querySelector('.evidence-list');
        evidenceList.innerHTML = '';
        analysis.evidence.forEach(item => {
            const li = document.createElement('li');
            li.textContent = item;
            evidenceList.appendChild(li);
        });

        // Populate reputation checks
        const checksContainer = view.querySelector('.reputation-checks');
        checksContainer.innerHTML = '';
        analysis.reputation_checks.forEach(check => {
            const item = document.createElement('div');
            item.className = 'check-item';
            const risk = check.risk_score ?? (check.score * 100);
            const verdict = check.verdict || 'UNKNOWN';
            item.innerHTML = `
                <div class="check-item-header">
                    <span class="check-item-source">${check.source}</span>
                    <span class="check-item-score ${verdict}">${verdict.replace(/_/g, ' ')}</span>
                </div>
                <p class="check-item-details">${check.description || check.details}</p>
            `;
            checksContainer.appendChild(item);
        });

        view.querySelector('#rescan-btn').addEventListener('click', requestScan);
        view.querySelector('#report-btn').addEventListener('click', reportSite);
    });
}

function renderHistoryView() {
    renderView('history', (view) => {
        const historyList = view.querySelector('#history-list');
        historyList.innerHTML = '';

        if (scanHistory.length === 0) {
            historyList.innerHTML = '<p>No scan history found.</p>';
            return;
        }

        scanHistory.forEach(item => {
            const div = document.createElement('div');
            div.className = 'history-item';
            const score = item.risk_score;
            let scoreClass = 'safe';
            if (score >= 75) scoreClass = 'malicious';
            else if (score >= 40) scoreClass = 'suspicious';

            div.innerHTML = `
                <span class="history-item-domain">${item.domain}</span>
                <span class="history-item-score ${scoreClass}">${score}</span>
            `;
            div.addEventListener('click', () => {
                currentAnalysis = item;
                showView('home');
            });
            historyList.appendChild(div);
        });
    });
}

/**
 * Sends a message to the service worker to initiate a manual scan.
 */
function requestScan() {
    if (!currentTab || !currentTab.id) return;
    renderLoadingView();
    chrome.runtime.sendMessage({ type: 'TRIGGER_MANUAL_SCAN', tabId: currentTab.id });
}

/**
 * Sends a message to the service worker to report the current site.
 */
function reportSite() {
    if (!currentTab || !currentTab.url) return;
    chrome.runtime.sendMessage({
        type: 'MANUAL_REPORT',
        data: { url: currentTab.url }
    });
    // Optionally show a confirmation message
    const reportBtn = document.getElementById('report-btn');
    if (reportBtn) {
        reportBtn.textContent = 'Reported!';
        setTimeout(() => {
            reportBtn.textContent = 'Report Phishing';
        }, 2000);
    }
}

/**
 * Helper to get the domain from a URL.
 * @param {string} urlString
 * @returns {string}
 */
function getDomainFromUrl(urlString) {
    try {
        return new URL(urlString).hostname;
    } catch (e) {
        return '';
    }
}