# Airtel AI Spam, Malicious-Link and OTP Fraud Protection vs Theft Alert

**Competitive class:** Adjacent but strategically important Indian network-level competitor  
**Research cutoff:** 15 August 2026  
**Evidence rule:** Competitor internals are described only to the level disclosed in linked official materials.

Airtel protects eligible mobile and broadband customers inside the operator network. Its portfolio combines network-behavior spam classification, malicious-domain blocking, and (from February 2026) contextual warnings when a bank OTP arrives during a potentially risky incoming call. Theft Alert instead analyzes browser-visible pages at an endpoint and can explain page/form/infrastructure evidence in detail.


## Theft Alert baseline used in this comparison

The repository snapshot reviewed is commit `4cd8fc4e755c244de0c6a41c0dfe3ea094c13ac5` (2026-08-12). Theft Alert is an MIT-licensed prototype comprising a Manifest V3 Chromium extension, FastAPI backend, and Flutter URL-scanning client.

Its implemented pipeline is:

1. **Endpoint collection:** a content script injected at `document_idle` collects URL/domain/title, the first 1,500 characters of visible text, links, image/script/style URLs, iframe URLs, and form structure (not entered values). A mutation observer can rescan; patched `fetch`/XHR functions attempt to report network requests.
2. **External intelligence:** parallel checks query Google Safe Browsing v4, VirusTotal, URLhaus, OpenPhish, AbuseIPDB, Spamhaus, AlienVault OTX, Pulsedive, urlscan.io, and crt.sh. Missing/error results generally become `UNKNOWN` with a neutral risk near 50.
3. **Infrastructure/heuristics:** DNS resolution, TLS certificate inspection, WHOIS/domain-age logic, optional Qualys SSL Labs, and URL/content rules (HTTP, punycode, deep subdomains, suspicious terms, credential-like inputs, external form actions, links, and iframes).
4. **Contextual AI:** Google Gemini receives a compacted summary and returns structured risk/explanation. A deterministic heuristic fallback is used if Gemini is unavailable. A Google Safe Browsing hit creates a high-risk floor.
5. **Decision and response:** either the LLM-normalized verdict (`/api/report`) or a confidence-adjusted weighted score (`/api/scan_url`) is displayed as an in-page warning/toast or app report. The extension stores five recent domain results locally and supports manual reports.

Important qualification: this describes code present in the repository, not independently validated protection efficacy. No benchmark corpus, published false-positive/false-negative rates, production SLA, scale evidence, extension-store release, or third-party security audit was found in the repository.

## How the existing solution detects threats

Official materials describe three connected controls: (1) call/SMS spam detection using behavioral and network intelligence—usage patterns, frequency, duration, suspicious URLs, IMEI and 250+ derived parameters; (2) real-time domain/link checks using internet-traffic scanning, global repositories and Airtel's threat-actor repository, with network-level block and redirect; and (3) an OTP Fraud Alert that detects a bank OTP during a potentially risky incoming call and warns the customer. Airtel's exact models, thresholds, feeds, encrypted-traffic visibility, and validation protocol are not public.

## Layer-by-layer comparison

| Layer | Theft Alert project | Existing solution | Assessment |
|---|---|---|---|
| **Deployment & reach** | Opt-in Chromium extension plus separately configured backend; only instrumented browser pages and manual mobile URL scans. | Auto-enabled network service for Airtel mobile/broadband customers; covers links reached from browsers, SMS, email and OTT apps when traffic traverses Airtel. | Airtel wins frictionless, cross-app and cross-device reach on its network; Theft Alert is carrier-independent and can inspect rendered DOM. |
| **Input/telemetry** | URL + rendered text, forms, links/resources/iframes and attempted page-request telemetry. | Network traffic/domain requests plus telco call/SMS metadata and behavior; OTP/call co-occurrence for the new alert. | Theft Alert has richer page semantics; Airtel has unique call/SMS/network graph signals unavailable to an extension. |
| **Reputation layer** | Ten third-party/repository checks, including Google, VirusTotal, OpenPhish and URLhaus. | Global threat repositories, partner APIs and Airtel proprietary threat-actor/domain intelligence. | Theft Alert is more transparent about named sources; Airtel likely has much larger proprietary observations but does not disclose feed-level logic. |
| **Infrastructure layer** | DNS/IP, WHOIS age, TLS/certificate/CT and optional SSL Labs checks. | Public descriptions emphasize real-time domain filtering and network intelligence, not per-site WHOIS/TLS reports. | This is a Theft Alert differentiator for analyst-readable evidence; it is not proof of better classification. |
| **Content/AI layer** | Visible text and form semantics summarized to Gemini; deterministic fallback. | AI/ML over call/SMS behavior and link/domain intelligence; no public claim of rendered webpage DOM/LLM inspection. | Theft Alert can reason over cloned login wording and forms; Airtel can detect coordinated campaigns and suspicious callers earlier. |
| **Decision/fusion** | Gemini-normalized 0–100 risk or weighted-source score; GSB safety floor. | Proprietary multi-tier intelligence; flags spam, blocks malicious domains, and issues contextual OTP warning. | Airtel has operational enforcement; Theft Alert exposes evidence and score but its two endpoint paths use different fusion logic. |
| **Intervention timing** | `document_idle` means the page has already loaded/executed before the main verdict; overlay/toast is shown after cloud analysis. | Network-level malicious domain block before destination use; call/SMS label at delivery; OTP alert during call. | Airtel is stronger for prevention latency. Theft Alert must add pre-navigation checks to make “before compromise” defensible. |
| **Feedback/operations** | Manual report logs a URL locally on server; no moderation, reputation update or takedown workflow shown. | Operator-scale telemetry, user/network feedback and continuously enriched repository; grievance/false-block process in terms. | Airtel is far ahead operationally; Theft Alert can differentiate with open rules, explainability and auditable appeals. |
| **Privacy/control** | Full URL and sampled page content/forms are sent to project backend and logged; no auth/retention policy in code. | Traffic/network metadata is processed by the operator under terms; no app install. Exact retention/model governance is not disclosed in product pages. | Neither can be treated as privacy-equivalent. Theft Alert needs minimization, consent, retention and tenant-isolation controls. |

## What Theft Alert should do next
1. Add a pre-navigation URL-reputation gate and cache before `document_idle`.
2. Treat call/SMS/OTP protection as an integration opportunity (Android share sheet, accessibility-safe copy/paste analyzer, or carrier API), not something a browser extension can reproduce alone.
3. Publish evaluation against fresh Indian phishing domains, Hindi/Hinglish content, false-positive rates, and median verdict latency.
4. Do not repeat Airtel “accuracy” or impact figures as independently audited model metrics; official claims do not disclose methodology.

## Bottom line

Airtel protects eligible mobile and broadband customers inside the operator network. Its portfolio combines network-behavior spam classification, malicious-domain blocking, and (from February 2026) contextual warnings when a bank OTP arrives during a potentially risky incoming call. Theft Alert instead analyzes browser-visible pages at an endpoint and can explain page/form/infrastructure evidence in detail. The correct conclusion is architectural, not an unmeasured claim of accuracy: Theft Alert’s opportunity is transparent, semantic, carrier-independent analysis; its immediate weaknesses are late intervention, immature operations, privacy/security defaults and missing efficacy evidence.

## Official references
- [Airtel Fraud Detection launch (15 May 2025)](https://www.airtel.in/press-release/05-2025/airtel-launches-fraud-detection-solution-a-first-in-the-world/)
- [Airtel Spam Identifier/Fraud Link terms](https://www.airtel.in/mobile/terms-conditions/spamidentifer)
- [Airtel OTP Fraud Alert (11 Feb 2026)](https://www.airtel.in/press-release/02-2026/airtel-launches-new-ai-powered-protection-from-frauds-caused-by-otp-leakages/)
- [GSMA Airtel case study](https://www.gsma.com/solutions-and-impact/technologies/security/scams/general/bharti-airtel-spam-and-scam-prevention-with-ai/)

## Evidence limitations

Public product pages describe capabilities but usually omit training data, thresholds, feature weights, full feed lists, false-positive/false-negative rates and reproducible test sets. Statements above are therefore capability comparisons, not independent certifications. Product availability and features can vary by country, plan, browser and device.