const BACKEND_API_URL = "http://localhost:8000/api/report";
const BACKEND_WS_URL = "ws://localhost:8000/ws/chrome-extension";

let ws = null;
let isWsConnected = false;

/**
 * Establishes a WebSocket connection with the backend.
 * Handles connection, messages, errors, and automatic reconnection.
 */
function connectWebSocket() {
    console.log("Attempting to connect to WebSocket...");
    ws = new WebSocket(BACKEND_WS_URL);

    ws.onopen = () => {
        console.log("WebSocket connection established.");
        isWsConnected = true;
        broadcastWsStatus();
    };

    ws.onmessage = (event) => {
        console.log("Message from server:", event.data);
        // Show a notification to the user
        chrome.notifications.create({
            type: 'basic',
            iconUrl: '../resources/icon128.png',
            title: 'Theft Alert',
            message: event.data,
        });
    };

    ws.onerror = (error) => {
        console.error("WebSocket error:", error);
    };

    ws.onclose = () => {
        console.log("WebSocket connection closed. Reconnecting in 5 seconds...");
        isWsConnected = false;
        broadcastWsStatus();
        ws = null;
        setTimeout(connectWebSocket, 5000); // Attempt to reconnect after 5 seconds
    };
}

/**
 * Sends the collected page data to the backend via a POST request.
 * @param {object} pageData - The data collected from the content script.
 */
async function sendDataToBackend(pageData) {
    try {
        const response = await fetch(BACKEND_API_URL, {
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
    chrome.runtime.sendMessage({ type: 'WS_STATUS', isConnected: isWsConnected });
}

// Listen for messages from content scripts or popup
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === "PAGE_DATA") {
        console.log("Received page data from tab:", sender.tab.id);
        sendDataToBackend(message.data);
    } else if (message.type === 'GET_WS_STATUS') {
        sendResponse({ isConnected: isWsConnected });
        // Also broadcast to ensure popup gets it if it opens after the initial connection
        broadcastWsStatus();
    }
    // Return true to indicate you wish to send a response asynchronously
    return true;
});

// Initialize WebSocket connection when the extension starts
connectWebSocket();