# Theft Alert

Theft Alert is a Chromium browser extension that detects phishing and fraud risk on websites. It inspects a page's URL, visible text, links, forms, embedded frames, resources, and selected network activity. The result is shown as either a temporary safety notification or a threat alert with a risk score, explanation, evidence, and recommendation.

The extension also lets a user manually report the current website. Reports are sent to the local FastAPI backend for logging and future review.

## How detection works

```text
Website
  -> universal_script.js collects a privacy-preserving page snapshot
  -> service_worker.js sends the snapshot to FastAPI
  -> Google Safe Browsing checks the URL
  -> OpenPhish, Spamhaus, WHOIS, and SSL Labs add reputation evidence
  -> llm_analyzer.py sends the evidence and page signals to the embedded LLM analyzer
  -> heuristic analysis is used when the LLM analyzer is unavailable
  -> result is returned and broadcast over WebSocket
  -> the extension displays a safety toast or threat alert
```

Google Safe Browsing is checked first as a high-value reputation signal. The final analysis also considers credential fields, external form actions, suspicious language, HTTP URLs, punycode, deep subdomains, external links, iframes, and cross-domain fetch/XHR requests.

### Scanned-data flow

1. `universal_script.js` runs on the current website and creates a page report. It sends the page URL and domain, title, a truncated sample of visible text, links, resource URLs, forms and field metadata, iframe URLs, and the scan trigger. It does not send form values or passwords.
2. The same content script observes `fetch` and `XMLHttpRequest` destinations. A network-activity report contains the destination URL, HTTP method, request type, source page URL, and source page domain. This helps identify cross-domain requests made by the page.
3. `service_worker.js` posts each report to `POST /api/report`. The backend logs the received payload and checks the reported URL with Google Safe Browsing, OpenPhish, Spamhaus, WHOIS, and cached Qualys SSL Labs data.
4. The backend adds those reputation results to the original browser report as `reputation_checks` and passes the combined evidence to `llm_analyzer.py`.
5. The embedded LLM analyzer receives a compact, structured summary containing the reputation results, visible-text sample, suspicious terms, URL signals, counts of forms/links/iframes/resources, form summaries, and network-activity details. It returns a JSON risk score, threat category, reason, description, recommendation, and evidence.
6. If the LLM analyzer is not configured or its request fails, the backend uses the deterministic heuristic fallback described below. The result is normalized, broadcast over WebSocket, and rendered by the extension as a toast or threat alert.

### What generates the safe or risk score?

The score is a **risk score from 0 to 100**, not a probability. A lower score means the captured evidence looks safer; a higher score means more phishing, fraud, malware, or credential-theft indicators were found. The extension displays scores below 50 as a safety toast and scores of 50 or higher as a threat alert.

With the embedded LLM analyzer enabled, the model makes the final evidence-based judgment from these inputs:

- Google Safe Browsing verdict and threat type.
- OpenPhish listing status and Spamhaus blocklist status.
- WHOIS registration information and the cached SSL Labs result.
- URL structure: HTTP instead of HTTPS, punycode, and unusually deep subdomains.
- Page behavior: password or credential-like fields, forms posting to another domain, external links, external iframes, and cross-domain fetch/XHR requests.
- Page language: terms associated with urgency, account verification, payment, banking, OTPs, refunds, prizes, wallets, or identity information.

The model is instructed to be conservative and return strict JSON. Its score is clamped to the 0-100 range during normalization. A confirmed Google Safe Browsing hit is a hard safety override: the score is raised to at least 90 and the threat type is mapped to `PHISHING` for social engineering or `MALWARE` for malware, unwanted software, and potentially harmful applications.

When the LLM analyzer is unavailable, the local heuristic starts at **10/100** and adds these points:

| Signal | Risk added |
| --- | ---: |
| Confirmed Google Safe Browsing hit | minimum score of 90 |
| Safe Browsing unavailable or API key missing | score raised to at least 35 |
| HTTP page | +10 |
| Punycode domain | +18 |
| Three or more levels of subdomains | +8 |
| Password input | +20 |
| Form submits to another domain | +25 |
| Credential-like field | +12 |
| Each suspicious term in the URL, domain, or text | +5, capped at +20 |
| Five or more external link hosts | +8 |
| External iframe | +10 |
| Cross-domain network request | +12 |

The heuristic total is clamped to 100. Without a confirmed Safe Browsing hit, the fallback maps `0-24` to `SAFE`, `25-49` to `LOW_RISK`, `50-74` to `SUSPICIOUS`, and `75-100` to `PHISHING`. These labels are advisory: a low score means no strong indicators were found in the captured data, not that the site has been proven safe.

## Repository layout

```text
backend/
  main.py             FastAPI routes, reputation checks, logging, WebSocket server
  llm_analyzer.py     Embedded LLM integration, result normalization, heuristic fallback
  requirements.txt    Python dependencies
  env.example         Local environment variable template

Chromium Extension/
  manifest.json          Manifest V3 configuration and permissions
  Scripts/
    universal_script.js  Page inspection and DOM/network monitoring
    service_worker.js    Backend communication and in-page result rendering
    dev-tools.js         Development tooling
  frontend/
    popup.html/js         Popup UI and manual reporting
    threat_alert.html     Detailed high-risk result markup
  Styles/                 Popup, toast, alert, and injected page styles
  dependencies/           Bundled Iconify, Anime.js, and Supabase libraries
  resources/              Extension icons
```

## Requirements

- Windows, macOS, or Linux
- Python 3.10 or newer
- A Chromium-based browser with support for unpacked Manifest V3 extensions
- A Google Safe Browsing API key for URL reputation checks
- An LLM provider API key in `GEMINI_API_KEY` for generated explanations (optional; the local heuristic fallback still works)

## Backend setup

From the repository root, create and activate a virtual environment:

```powershell
cd backend
python -m venv venv
.\venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
```

Create `backend/.env` from `backend/env.example`:

```env
GOOGLE_API_KEY=your_google_safe_browsing_key
GEMINI_API_KEY=your_gemini_key
GEMINI_MODEL=gemini-2.0-flash
```

Start the API from the `backend` directory:

```powershell
python main.py
```

The API listens on `http://localhost:8000`. Open that URL to verify that it returns an online status response.

## Load the extension

1. Open `chrome://extensions` or the equivalent extensions page in your Chromium browser.
2. Enable **Developer mode**.
3. Select **Load unpacked**.
4. Choose the repository's `Chromium Extension` directory.
5. Keep the FastAPI backend running before browsing to a page.

The service worker connects to:

- HTTP: `http://localhost:8000/api/report`
- Manual reports: `http://localhost:8000/api/manual_report`
- WebSocket: `ws://localhost:8000/ws/chrome-extension`

These URLs are hard-coded in `Chromium Extension/Scripts/service_worker.js` and should be changed for a deployed backend.

## User-facing behavior

### Automatic scanning

- An initial scan is sent after the page load event. Initial iframe scans are ignored to avoid duplicates.
- A debounced scan is sent when relevant DOM changes occur, such as new links or changed form actions.
- The content script observes page `fetch` and `XMLHttpRequest` calls and sends their URL, method, and request type as network activity.
- Form values are not collected. Only field metadata such as type, name, ID, and placeholder is sent.
- Visible page text is truncated to 1,500 characters before it is sent.

### Results

The analyzer returns:

- `risk_score`: integer from 0 to 100, where 100 is the highest risk
- `threat_type`: `SAFE`, `LOW_RISK`, `SUSPICIOUS`, `PHISHING`, `FRAUD`, `MALWARE`, or `UNKNOWN`
- `brief_reason`: short explanation
- `description`: fuller explanation of the observed signals
- `recommendation`: suggested user action
- `evidence`: up to five supporting observations

Scores below 50 appear as a temporary safety toast. Scores of 50 or higher appear as a threat alert. A confirmed Google Safe Browsing hit forces the score to at least 90 and maps social-engineering results to `PHISHING`.

### Manual reporting

The popup's **Report this site** button sends the active tab URL to `/api/manual_report`. The browser stores a timestamp locally and disables reporting for that exact URL for 24 hours. The backend writes manual reports to `manual_reports.log`.

## API endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/` | Health/status response |
| `POST` | `/api/report` | Analyze a page or network activity payload |
| `POST` | `/api/check_url` | Run a standalone Google Safe Browsing URL check |
| `POST` | `/api/manual_report` | Log a user-submitted URL report |
| `WS` | `/ws/{client_id}` | Receive analysis broadcasts and acknowledge messages |

The main page report payload includes `url`, `domain`, `title`, `cleanText`, `links`, `resources`, `forms`, `iframes`, `scanTrigger`, and `isTopFrame`. Network reports additionally include `sourcePageUrl`, `sourcePageDomain`, `method`, and `requestType`.

## Analysis modes

When `GEMINI_API_KEY` is configured, `llm_analyzer.py` calls the embedded LLM service with a strict JSON response schema. If the call fails, the analyzer returns a normalized heuristic result and explains that the fallback was used. Without an LLM provider key, the heuristic analyzer runs directly. The OpenPhish, Spamhaus, WHOIS, and SSL Labs results are provided as evidence to the LLM, but they are not independently added as fixed numeric weights in the fallback heuristic; Google Safe Browsing is the only reputation result that directly changes the fallback score.

## Logs and privacy

The backend writes:

- `backend/scan_reports.log`: received scan payloads
- `backend/manual_reports.log`: manually reported URLs

Logs may contain URLs, page titles, visible text samples, link/resource URLs, form metadata, and network request destinations. Do not commit logs or API keys. The repository's `.gitignore` excludes `.env`, virtual environments, Python caches, and log files.

No form values, passwords, or typed credentials are intentionally collected by the content script. URLs and page metadata can still be sensitive, so use a controlled backend and define an appropriate retention policy before deployment.

## Security and deployment notes

This repository is configured for local development:

- CORS currently allows every origin (`*`). Restrict it to the deployed extension origin in production.
- The backend uses HTTP and WebSocket connections to `localhost`. Use HTTPS/WSS behind a trusted reverse proxy when deployed.
- API keys belong only in `backend/.env`; never place them in extension JavaScript.
- `host_permissions` and the content script match all URLs because detection is intended to work across websites. Review this permission before publishing.
- External reputation services can rate-limit requests and may have their own data-use terms.
- A risk score is not a guarantee. Users should independently verify important domains and avoid entering sensitive information when the result is suspicious.

## Troubleshooting

### Popup says `Disconnected`

Confirm that the backend is running on port 8000, then reload the extension from the browser's extensions page. Inspect the service worker console for connection errors.

### No result appears on a page

Reload the page after loading or reloading the extension. Check the page console for `universal_script.js` messages and the service worker console for failed requests. Browser-protected pages such as browser settings and extension stores may not allow content scripts.

### Safe Browsing is skipped

Set `GOOGLE_API_KEY` in `backend/.env`, restart the backend, and confirm that the Safe Browsing API is enabled for the Google Cloud project.

### The LLM analyzer is unavailable

Set `GEMINI_API_KEY` and restart the backend. The extension still receives a heuristic result if the LLM provider key is missing or its request fails.

## License and project status

No license file is currently included. Add a license before redistributing the project. This is an active development project and should be tested with representative benign and malicious test URLs in an isolated environment before wider deployment.