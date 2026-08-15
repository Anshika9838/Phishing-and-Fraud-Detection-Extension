# Theft Alert Project Architecture and Code Review

**Repository:** https://github.com/Anshika9838/Phishing-and-Fraud-Detection-Extension  
**Snapshot:** commit `4cd8fc4e755c244de0c6a41c0dfe3ea094c13ac5` (2026-08-12)  
**Review date:** 15 August 2026  
**Method:** static source/document review and Python compilation check. No live API keys, production deployment, malicious-site execution or efficacy benchmark was available.


## Theft Alert baseline used in this comparison

The repository snapshot reviewed is commit `4cd8fc4e755c244de0c6a41c0dfe3ea094c13ac5` (2026-08-12). Theft Alert is an MIT-licensed prototype comprising a Manifest V3 Chromium extension, FastAPI backend, and Flutter URL-scanning client.

Its implemented pipeline is:

1. **Endpoint collection:** a content script injected at `document_idle` collects URL/domain/title, the first 1,500 characters of visible text, links, image/script/style URLs, iframe URLs, and form structure (not entered values). A mutation observer can rescan; patched `fetch`/XHR functions attempt to report network requests.
2. **External intelligence:** parallel checks query Google Safe Browsing v4, VirusTotal, URLhaus, OpenPhish, AbuseIPDB, Spamhaus, AlienVault OTX, Pulsedive, urlscan.io, and crt.sh. Missing/error results generally become `UNKNOWN` with a neutral risk near 50.
3. **Infrastructure/heuristics:** DNS resolution, TLS certificate inspection, WHOIS/domain-age logic, optional Qualys SSL Labs, and URL/content rules (HTTP, punycode, deep subdomains, suspicious terms, credential-like inputs, external form actions, links, and iframes).
4. **Contextual AI:** Google Gemini receives a compacted summary and returns structured risk/explanation. A deterministic heuristic fallback is used if Gemini is unavailable. A Google Safe Browsing hit creates a high-risk floor.
5. **Decision and response:** either the LLM-normalized verdict (`/api/report`) or a confidence-adjusted weighted score (`/api/scan_url`) is displayed as an in-page warning/toast or app report. The extension stores five recent domain results locally and supports manual reports.

Important qualification: this describes code present in the repository, not independently validated protection efficacy. No benchmark corpus, published false-positive/false-negative rates, production SLA, scale evidence, extension-store release, or third-party security audit was found in the repository.


## Implemented components

| Component | Implementation | Code evidence |
|---|---|---|
| Chromium extension | MV3 service worker, popup, in-page warnings, automatic + manual scan | `Chromium Extension/manifest.json`; `Scripts/service_worker.js`; `Scripts/universal_script.js` |
| Page sensor | DOM text/links/resources/forms/iframes; MutationObserver; fetch/XHR patching | `universal_script.js:43-129`, `137-175`, `180+` |
| API/orchestrator | FastAPI routes `/api/report`, `/api/check_url`, `/api/scan_url`, `/api/manual_report`, WebSocket | `backend/main.py` |
| Reputation fan-out | 10 parallel providers | `backend/threat_feeds.py:903-932` |
| Infrastructure | DNS/TLS/WHOIS/URL heuristics/optional SSL Labs | `backend/infra_analyzer.py` |
| AI analysis | Gemini structured response + deterministic fallback + GSB override | `backend/llm_analyzer.py` |
| Scoring | Confidence-adjusted weighted average and critical-source floors | `backend/scoring.py` |
| Mobile/web client | Flutter URL submission, progress UI, result/history | `scan_url_app/lib` |

## Detection layers actually present

### Layer 0 — Collection and triggers
The top frame sends a snapshot after load; iframe initial scans are skipped to reduce duplicates. It captures placeholders/names/types but not form values. Visible text is truncated to 1,500 characters. A DOM signature based on links, form structure and iframes suppresses some duplicate rescans. This is privacy-aware relative to collecting values, but full URLs can still contain tokens, search queries, document identifiers or personal data.

### Layer 1 — Reputation and threat intelligence
The project queries Google Safe Browsing, VirusTotal, URLhaus, OpenPhish, AbuseIPDB, Spamhaus, OTX, Pulsedive, urlscan.io and crt.sh concurrently. This is broad and inspectable. Weaknesses include API-key/rate-limit dependency, heterogeneous semantics, correlated sources, no provider TTL cache, and several mappings where “not found” receives a low risk despite not being affirmative evidence of safety.

### Layer 2 — Infrastructure and lexical heuristics
The code examines DNS/IP, TLS certificate fields, WHOIS age/expiry, Certificate Transparency, HTTP use, punycode, subdomain depth, URL length/characters, suspicious terms, credential fields, external form actions, external links/iframes and related indicators. These are useful weak signals but can generate false positives on legitimate SSO, payment processors, CDNs, embedded support widgets, young startups and multilingual pages.

### Layer 3 — Contextual AI
Gemini receives a compact, structured summary rather than the entire DOM. The prompt asks for a strict schema and the result is normalized. A deterministic fallback is available. This is a sound resilience idea, but no prompt-injection defense, adversarial test suite, calibration analysis or model/version regression gate is present. Page text is attacker-controlled and should be treated as untrusted data even inside a structured prompt.

### Layer 4 — Fusion
Two materially different paths exist:

- `/api/report` uses the Gemini/fallback analysis as the final risk outcome, with a Google Safe Browsing floor.
- `/api/scan_url` uses `calculate_overall_score`, a weighted arithmetic model with confidence discounts and critical-source floors, but does not run Gemini.

The split can produce inconsistent verdicts for the same URL. A single versioned policy engine should own normalization, uncertainty, correlated-source handling and final action.

### Layer 5 — Intervention and feedback
Scores below 40 produce a safe toast; higher scores produce a threat overlay. Because the content script runs at `document_idle` and cloud calls follow, this is detection-after-load, not guaranteed pre-compromise blocking. Manual reports are appended to a log but are not moderated, deduplicated, corroborated, promoted to a feed or sent to takedown providers.

## Critical production risks

| Severity | Finding | Why it matters | Required remediation |
|---|---|---|---|
| Critical | Backend URLs are hard-coded `http://localhost:8000` and `ws://localhost:8000`. | Not deployable securely; no TLS or environment configuration. | Signed remote config/build-time endpoints; HTTPS/WSS; certificate validation. |
| Critical | No authentication/authorization on REST or WebSocket endpoints. | Anyone reaching the backend can submit scans, consume resources or connect for results. | Client auth, rate limits, quotas, tenant isolation and request IDs. |
| Critical | Analysis is broadcast to every connected WebSocket. | One user may receive another user's URL/verdict, creating privacy leakage and wrong-tab alerts. | Per-request/per-client channels; never global broadcast user results. |
| Critical | Full scan payload is logged; no retention/redaction policy. | URLs and page text can contain personal/confidential information. | Default-off content logging, URL query stripping, redaction, encryption, retention/deletion controls. |
| High | CORS is `*` while credentials are enabled. | Insecure/invalid production policy and unintended callers. | Explicit origins; no credentials unless required; CSRF design. |
| High | Verdict arrives after page execution. | Drive-by code or credential entry may occur first. | Pre-navigation URL cache/check, declarative blocking, local model and/or isolation. |
| High | No SSRF/input validation boundaries are evident for URL-only scans. | Backend may resolve/connect to attacker-chosen/internal destinations through providers/infra checks. | Normalize schemes, block private/link-local/metadata IP ranges after every DNS resolution/redirect, size/time budgets. |
| High | No benchmark tests, unit tests or CI found. | Accuracy and safety regressions are invisible. | Unit/integration/adversarial tests, pinned dependencies, CI and release gates. |
| High | Unpinned seven-line requirements file. | Supply-chain drift and non-reproducible builds. | Lock hashes/versions, SBOM, SCA, dependency update policy. |
| Medium | `<all_urls>` plus page-wide content access. | Large privacy and extension compromise blast radius. | Optional/site-scoped access, least privilege, transparent permissions. |
| Medium | Missing APIs become neutral scores around 50. | Configuration failure changes verdicts and can create noisy or misleading results. | Explicit `UNKNOWN`, health state and minimum-required-source policy. |
| Medium | Popup history uses template `innerHTML` with result-derived fields. | Although browser extension isolation helps, untrusted strings should not enter HTML. | Build nodes with `textContent`; sanitize any markup. |

## Product positioning supported by the code

**Defensible:** “An open-source experimental URL/page risk analyzer that aggregates threat intelligence, infrastructure indicators, browser page structure and optional LLM explanation.”

**Not yet defensible:** “real-time prevention,” “high accuracy,” “zero-day protection,” “enterprise-grade,” “privacy-preserving,” or equivalence to network-scale products. Those require pre-navigation enforcement, measured evaluation, secure operations and external validation.

## Recommended target architecture

1. **Local preflight (<20 ms):** canonical URL, allowlist, cached verdict, IDN/brand lookalike, private-IP checks.
2. **Remote reputation budget (<300 ms):** v5 hash-prefix Safe Browsing mode where eligible, curated feed cache, consensus with source correlation.
3. **Conditional deep scan:** sandboxed fetch/browser, redirect chain, DOM/form/script hashes, OCR only when risk/uncertainty warrants.
4. **Local or privacy-minimized semantic model:** model receives bounded features; attacker text is delimited and never treated as instruction.
5. **Versioned policy engine:** outputs risk, confidence, uncertainty, action and machine-readable evidence.
6. **Actions:** allow, warn, block, disable credential entry, isolate, or require explicit re-authentication.
7. **Governance:** appeal/review, analyst labeling, feed provenance, retention, regional processing, audit logs and evaluation dashboards.

## Verification performed

`python -m compileall -q backend` completed successfully. This confirms Python syntax compilation only; it does not validate imports in a clean environment, runtime behavior, external APIs, Flutter/extension builds or detection accuracy.
