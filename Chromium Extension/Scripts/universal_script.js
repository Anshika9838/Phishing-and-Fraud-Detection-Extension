/**
 * This content script runs on every page to collect document information
 * and sends it to the background service worker for analysis.
 */

function collectPageData() {
    // 1. Collect all hyperlinks
    const links = Array.from(document.querySelectorAll('a')).map(a => a.href);

    // 2. Collect resource links (images, scripts, stylesheets)
    const imageSources = Array.from(document.querySelectorAll('img')).map(img => img.src);
    const scriptSources = Array.from(document.querySelectorAll('script')).map(script => script.src).filter(Boolean);
    const styleSources = Array.from(document.querySelectorAll('link[rel="stylesheet"]')).map(link => link.href);

    // 3. Collect form details
    const forms = Array.from(document.querySelectorAll('form')).map(form => {
        const formAction = form.action;
        const formMethod = form.method;
        const inputs = Array.from(form.querySelectorAll('input, textarea, select')).map(input => ({
            name: input.name,
            type: input.type,
            id: input.id,
            value: input.value, // Note: Capturing values can have privacy implications.
        }));
        return {
            action: formAction,
            method: formMethod,
            inputs: inputs,
        };
    });

    // 4. Construct the data payload
    const pageData = {
        domain: window.location.hostname,
        url: window.location.href,
        htmlContent: document.documentElement.outerHTML.substring(0, 2000), // Truncate for performance
        links: [...new Set(links)], // Unique links
        resources: {
            images: [...new Set(imageSources)],
            scripts: [...new Set(scriptSources)],
            styles: [...new Set(styleSources)],
        },
        forms: forms,
    };

    // 5. Send data to the background script
    // Check if the runtime is still available. It can become invalid if the
    // extension is reloaded, which is common during development.
    if (chrome && chrome.runtime && chrome.runtime.id) {
        chrome.runtime.sendMessage({ type: "PAGE_DATA", data: pageData });
        console.log("Theft Alert: Page data sent to background for analysis.");
    } else {
        console.warn("Theft Alert: Extension context invalidated. Cannot send page data. Please reload the page.");
    }
}

// Run the collection after the page has finished loading
window.addEventListener('load', collectPageData);