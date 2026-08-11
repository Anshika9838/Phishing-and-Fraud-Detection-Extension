/**
 * This content script runs on every page to collect document information
 * and sends it to the background service worker for analysis.
 */

(function() {
    // DEBUG: Add a unique ID to this script instance to track if it runs multiple times.
    const scriptInstanceId = Math.random().toString(36).substring(2, 10);
    console.log(`[DEBUG ANCHOR 1/5] universal_script.js | Instance ${scriptInstanceId} | Script starting.`);

    let lastPageDataSignature = '';
    // This flag is the correct guard against multiple 'load' events firing for the same document.
    let hasInitialLoadBeenSent = false;
    // This flag prevents initializing monitors (DOM observer, network interceptor) more than once per instance.
    let isMonitoringInitialized = false;

/**
 * Creates a simple signature of the page data to detect meaningful changes and prevent duplicate reports.
 * @param {object} data - The page data object.
 * @returns {string} A string signature (simple hash).
 */
function generateSignature(data) {
    // Stringify the most volatile and important parts of the page for the signature.
    const significantData = {
        links: data.links,
        forms: data.forms.map(f => ({ action: f.action, inputs: f.inputs.map(i => i.name) })), // Only form structure
        iframes: data.iframes,
    };
    const str = JSON.stringify(significantData);
    // Simple hash function to avoid storing the full, potentially large, string.
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
        hash = ((hash << 5) - hash) + str.charCodeAt(i);
        hash |= 0; // Convert to 32bit integer
    }
    return String(hash);
}

/**
 * Collects a snapshot of the page's data, including links, resources, and forms.
 * @param {string} scanTrigger - The reason for the scan (e.g., 'initial_load', 'dom_change').
 */
function collectPageData(scanTrigger) {
    console.log(`[DEBUG ANCHOR 3/5] universal_script.js | Instance ${scriptInstanceId} | collectPageData called. Trigger: ${scanTrigger}`);

    // 1. Collect all hyperlinks
    const links = Array.from(document.querySelectorAll('a')).map(a => a.href);

    // 2. Collect resource links (images, scripts, stylesheets)
    const imageSources = Array.from(document.querySelectorAll('img')).map(img => img.src);
    const scriptSources = Array.from(document.querySelectorAll('script')).map(script => script.src).filter(Boolean);
    const styleSources = Array.from(document.querySelectorAll('link[rel="stylesheet"]')).map(link => link.href);

    // 3. Collect form details (Sanitized for privacy)
    const forms = Array.from(document.querySelectorAll('form')).map(form => {
        const inputs = Array.from(form.querySelectorAll('input, textarea, select')).map(input => ({
            name: input.name || '',
            type: input.type || '',
            id: input.id || '',
            placeholder: input.placeholder || '', // Capture placeholder instead of value for privacy.
        }));

        let isExternalAction = false;
        try {
            const formActionUrl = new URL(form.action);
            isExternalAction = formActionUrl.hostname !== window.location.hostname;
        } catch (e) {
            // Handle cases where form.action might be an invalid URL (e.g., relative path, #anchor)
            // For relative paths, it's considered internal. For invalid, default to false.
        }
        return {
            action: form.action,
            method: form.method,
            isExternalAction: isExternalAction, // New field for cross-domain check
            inputs: inputs,
        };
    });

    // 4. Collect iFrames and other metadata
    const iframes = Array.from(document.querySelectorAll('iframe')).map(iframe => iframe.src).filter(Boolean);

    // 4. Construct the data payload
    const pageData = {
        scanTrigger: scanTrigger,
        domain: window.location.hostname,
        url: window.location.href,
        title: document.title,
        isTopFrame: (window.self === window.top),
        favicon: document.querySelector('link[rel="icon"], link[rel="shortcut icon"]')?.href || '',
        cleanText: document.body.innerText.substring(0, 1500), // Truncated clean text content to 1500 chars
        links: [...new Set(links)], // Unique links
        resources: {
            images: [...new Set(imageSources)],
            scripts: [...new Set(scriptSources)],
            styles: [...new Set(styleSources)],
        },
        forms: forms,
        iframes: [...new Set(iframes)],
    };

    // For initial load, only send data from the top-level frame to avoid duplicates from iframes.
    if (scanTrigger === 'initial_load' && !pageData.isTopFrame) {
        console.log(`[DEBUG] universal_script.js | Instance ${scriptInstanceId} | IGNORING initial_load from iframe. Aborting send.`);
        return;
    }

    console.log(`[DEBUG] universal_script.js | Instance ${scriptInstanceId} | Data collected. isTopFrame: ${pageData.isTopFrame}, URL: ${pageData.url}`);

    // Generate a signature to check for meaningful changes and prevent duplicate reports.
    const currentSignature = generateSignature(pageData);

    if (currentSignature === lastPageDataSignature && scanTrigger === 'dom_change') {
        console.log("Theft Alert: DOM changed, but no significant new features detected. Skipping report.");
        return; // Don't send duplicate data on DOM changes.
    }

    lastPageDataSignature = currentSignature;

    // 5. Send data to the background script
    // Check if the runtime is still available. It can become invalid if the
    // extension is reloaded, which is common during development.
    if (chrome && chrome.runtime && chrome.runtime.id) {
        console.log(`[DEBUG ANCHOR 4/5] universal_script.js | Instance ${scriptInstanceId} | Sending PAGE_DATA to service worker.`);
        chrome.runtime.sendMessage({ type: "PAGE_DATA", data: pageData });
        console.log(`Theft Alert: Page data sent for analysis. Trigger: ${scanTrigger}, Frame: ${pageData.isTopFrame ? 'Top' : 'iFrame'}`);
    } else {
        console.warn("Theft Alert: Extension context invalidated. Cannot send page data. Please reload the page.");
    }
}

let domChangeDebounceTimer;

/**
 * Observes the DOM for mutations and triggers a re-scan after a debounce period.
 * This helps capture data from dynamically loaded content (e.g., in SPAs).
 */
function observeDOMChanges() {
    console.log(`[DEBUG] universal_script.js | Instance ${scriptInstanceId} | Initializing MutationObserver.`);
    const observer = new MutationObserver(mutations => {
        // Filter out mutations that are clearly caused by our extension's own UI.
        const relevantMutations = mutations.filter(mutation => {
            // Ignore if the direct target is our UI element or inside it.
            if (mutation.target.closest('#theft-alert-overlay, #theft-alert-toast')) {
                return false;
            }
            // Ignore if the added node *is* our UI element.
            for (const node of mutation.addedNodes) {
                if (node.id === 'theft-alert-overlay' || node.id === 'theft-alert-toast') {
                    return false;
                }
            }
            return true;
        });

        // If after filtering, there are no relevant mutations left, do nothing.
        if (relevantMutations.length === 0) {
            console.log("[DEBUG] MutationObserver: Ignoring DOM changes as they were self-inflicted by the extension.");
            return;
        }

        // Debounce the re-scan to avoid excessive processing on rapidly changing pages.
        clearTimeout(domChangeDebounceTimer);
        domChangeDebounceTimer = setTimeout(() => {
            console.log("Theft Alert: Relevant DOM change detected. Debouncing and re-scanning page.");
            collectPageData('dom_change'); // Re-run the full data collection
        }, 2000); // Wait 2 seconds after the last change to batch mutations.
    });

    // Start observing the body for changes to its children and their attributes.
    observer.observe(document.body, {
        childList: true,    // Watch for addition/removal of nodes.
        subtree: true,      // Watch all descendants.
        attributes: true,   // Watch for attribute changes.
        attributeFilter: ['action', 'href'] // Specifically watch form actions and link hrefs.
    });

    console.log("Theft Alert: Now monitoring for DOM changes.");
}

/**
 * Intercepts fetch and XMLHttpRequest to monitor outgoing network requests made by the page.
 */
function interceptNetworkRequests() {
    const originalFetch = window.fetch;
    window.fetch = function(...args) {
        const url = args[0] instanceof Request ? args[0].url : args[0];
        const method = args[0] instanceof Request ? args[0].method : (args[1]?.method || 'GET');

        if (chrome && chrome.runtime && chrome.runtime.id) {
            chrome.runtime.sendMessage({
                type: "NETWORK_REQUEST",
                data: { url: url.toString(), method: method.toUpperCase(), requestType: 'fetch' }
            });
        }
        return originalFetch.apply(this, args);
    };

    const originalXhrOpen = XMLHttpRequest.prototype.open;
    const originalXhrSend = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function(method, url, ...rest) {
        this._requestDetails = { method, url };
        return originalXhrOpen.apply(this, [method, url, ...rest]);
    };

    XMLHttpRequest.prototype.send = function(...args) {
        if (this._requestDetails && chrome && chrome.runtime && chrome.runtime.id) {
            chrome.runtime.sendMessage({
                type: "NETWORK_REQUEST",
                data: { url: this._requestDetails.url.toString(), method: this._requestDetails.method.toUpperCase(), requestType: 'xhr' }
            });
        }
        return originalXhrSend.apply(this, args);
    };

    console.log("Theft Alert: Now monitoring for network requests (fetch/XHR).");
}

console.log(`[DEBUG ANCHOR 2/5] universal_script.js | Instance ${scriptInstanceId} | Attaching 'load' event listener.`);
window.addEventListener('load', () => {
    console.log(`[DEBUG] universal_script.js | Instance ${scriptInstanceId} | 'load' event fired. hasInitialLoadBeenSent: ${hasInitialLoadBeenSent}`);
    if (hasInitialLoadBeenSent) {
        console.warn("Theft Alert: 'load' event fired again, but initial scan was already sent. Ignoring.");
        return;
    }
    hasInitialLoadBeenSent = true; // Set flag immediately to prevent race conditions.

    collectPageData('initial_load');

    // Ensure that monitoring is only set up once per script instance.
    console.log(`[DEBUG] universal_script.js | Instance ${scriptInstanceId} | Checking monitoring status. isMonitoringInitialized: ${isMonitoringInitialized}`);
    if (isMonitoringInitialized) {
        console.warn("Theft Alert: Monitoring is already active. Skipping re-initialization.");
        return;
    }
    isMonitoringInitialized = true;
    observeDOMChanges();
    interceptNetworkRequests();
});

    // Listen for on-demand scan requests from the popup/service worker.
    chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
        if (message.type === "REQUEST_PAGE_DATA") {
            console.log(`[DEBUG] universal_script.js | Instance ${scriptInstanceId} | Received on-demand REQUEST_PAGE_DATA. Trigger: ${message.trigger}`);
            collectPageData(message.trigger || 'manual_popup');
            // Acknowledge the message.
            sendResponse({ status: "data_collection_triggered" });
        }
        // Keep the message channel open for the async response.
        return true;
    });
})();