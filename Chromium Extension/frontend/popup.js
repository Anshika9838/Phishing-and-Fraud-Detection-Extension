document.addEventListener('DOMContentLoaded', () => {
    const statusIndicator = document.getElementById('status-indicator');
    const statusText = document.getElementById('status-text');
    const githubBtn = document.getElementById('github-btn');
    const githubIcon = document.getElementById('github-icon');

    // Set GitHub icon
    githubIcon.innerHTML = Iconify.renderHTML(
        Iconify.renderIcon(Iconify.getIcon("mdi:github"), { height: 18 })
    );

    // Open GitHub repo on button click
    githubBtn.addEventListener('click', () => {
        chrome.tabs.create({ url: 'https://github.com/Aditya-S-Subramani/Phising-and-Fraud-Detection-Project' });
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

    // Request initial status when popup opens
    chrome.runtime.sendMessage({ type: 'GET_WS_STATUS' });
});