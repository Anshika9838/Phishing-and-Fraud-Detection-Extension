document.addEventListener('DOMContentLoaded', () => {
    const statusIndicator = document.getElementById('status-indicator');
    const statusText = document.getElementById('status-text');
    const githubBtn = document.getElementById('github-btn');
    const reportBtn = document.getElementById('report-btn');
    const githubIcon = document.getElementById('github-icon');

    const REPORT_COOLDOWN_MS = 24 * 60 * 60 * 1000; // 24 hours
    const STORAGE_KEY = 'manual_reports_timestamps';

    // Set GitHub icon
    githubIcon.innerHTML = Iconify.renderHTML(
        Iconify.renderIcon(Iconify.getIcon("mdi:github"), { height: 18 })
    );

    // Open GitHub repo on button click
    githubBtn.addEventListener('click', () => {
        chrome.tabs.create({ url: 'https://github.com/Aditya-S-Subramani/Phising-and-Fraud-Detection-Project' });
    });

    // Updates the report button state based on whether the site has been recently reported.
    async function updateReportButtonState() {
        const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
        if (!tab || !tab.url) return;

        const url = tab.url;
        chrome.storage.local.get(STORAGE_KEY, (result) => {
            const reports = result[STORAGE_KEY] || {};
            const lastReportTime = reports[url];

            if (lastReportTime && (Date.now() - lastReportTime < REPORT_COOLDOWN_MS)) {
                reportBtn.textContent = 'Reported Recently';
                reportBtn.disabled = true;
            } else {
                reportBtn.textContent = 'Report this site';
                reportBtn.disabled = false;
            }
        });
    }

    // Handle manual site reporting
    reportBtn.addEventListener('click', async () => {
        const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
        if (!tab || !tab.url) return;

        const url = tab.url;
        
        // Disable button immediately to prevent double-clicks
        reportBtn.disabled = true;
        reportBtn.textContent = 'Reporting...';

        // Send the report
        chrome.runtime.sendMessage({ type: "MANUAL_REPORT", data: { url: url } });

        // Save the timestamp to local storage
        chrome.storage.local.get(STORAGE_KEY, (result) => {
            const reports = result[STORAGE_KEY] || {};
            reports[url] = Date.now();
            chrome.storage.local.set({ [STORAGE_KEY]: reports }, () => {
                reportBtn.textContent = 'Reported!';
            });
        });
    });

    // Listen for status updates from the background script
    chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
        if (message.type === 'WS_STATUS') {
            updateStatus(message.isConnected);
        }
    });

    function updateStatus(isConnected) {
        statusIndicator.className = isConnected ? 'connected' : 'disconnected';
        statusText.textContent = isConnected ? 'Connected' : 'Disconnected';
    }

    // Initial state updates when popup opens
    updateReportButtonState();
    chrome.runtime.sendMessage({ type: 'GET_WS_STATUS' });
});