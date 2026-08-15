# Vodafone Idea Vi Protect vs Theft Alert

**Competitive class:** Adjacent Indian network-level competitor  
**Research cutoff:** 15 August 2026  
**Evidence rule:** Competitor internals are described only to the level disclosed in linked official materials.

Vi Protect unifies network-native spam-call/SMS labels, malicious-link blocking, international-call display and core-network defense. It most directly overlaps Theft Alert at malicious-domain assessment, but has broader communications-channel reach and less public per-page explanation.


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

Vi states that voice spam detection combines advanced AI models, web crawlers and user feedback; SMS detection uses content behavior, usage/frequency, suspicious URLs, IMEI and derived parameters; links are assessed in real time and malicious domains blocked at network level. The public documentation does not disclose model architecture, feature weights, feed names, benchmarks or encrypted-traffic handling.

## Layer-by-layer comparison

| Layer | Theft Alert project | Existing solution | Assessment |
|---|---|---|---|
| **Deployment & reach** | Chromium endpoint plus URL-only Flutter client; backend must be deployed. | Auto-active on Vi mobile network for prepaid/postpaid customers; no app needed for link protection. | Vi wins low-friction coverage on its network; Theft Alert remains operator-independent. |
| **Input/telemetry** | Rendered page URL/text/forms/resources and some browser-request events. | Call/SMS/network signals, message content patterns, web crawlers, user feedback and domain access. | Each has exclusive signals: Theft Alert sees DOM; Vi sees telecom behavior and sender velocity. |
| **Reputation** | Named multi-source external checks. | Proprietary AI/algorithmic domain assessment; source feeds not itemized publicly. | Theft Alert offers source transparency; Vi offers proprietary network scale. |
| **Infrastructure** | WHOIS/TLS/DNS/CT/SSL rules. | No comparable per-domain infrastructure report described publicly. | Theft Alert provides deeper analyst evidence. |
| **Content/behavior** | Gemini summary of page/form context plus deterministic rules. | ML pattern recognition over messages/calls and crawler/link intelligence. | Theft Alert is stronger for rendered-page semantics; Vi for coordinated sender/call behavior. |
| **Enforcement** | Post-load overlay/toast; user can dismiss. | Network block and secure redirect for malicious domains; labels suspected calls/SMS. | Vi intervenes earlier and across apps. |
| **Feedback/appeal** | Manual-report log only. | Continuous learning/user feedback; documented grievance email for wrongly blocked domains. | Theft Alert needs a governed review and feed-update loop. |
| **Evidence & assurance** | Detailed evidence list but no measured efficacy. | Operational counts in company materials, but no public test protocol or confusion matrix. | Do not equate volume blocked with accuracy. |

## What Theft Alert should do next
1. Implement block/allow/warn policy separately from score presentation.
2. Build an appeal queue and provenance trail for every source and rule.
3. Benchmark against Vi-like requirements: real-time latency, network failures, local-language scams and false blocks.
4. Position as a semantic endpoint complement to Vi, not a replacement for carrier call/SMS telemetry.

## Bottom line

Vi Protect unifies network-native spam-call/SMS labels, malicious-link blocking, international-call display and core-network defense. It most directly overlaps Theft Alert at malicious-domain assessment, but has broader communications-channel reach and less public per-page explanation. The correct conclusion is architectural, not an unmeasured claim of accuracy: Theft Alert’s opportunity is transparent, semantic, carrier-independent analysis; its immediate weaknesses are late intervention, immature operations, privacy/security defaults and missing efficacy evidence.

## Official references
- [Vi Protect product and FAQ](https://www.myvi.in/spam-protection)
- [Vi Protect launch release (8 Oct 2025)](https://www.myvi.in/content/dam/vodafoneideadigital/StaticPages/PressReleases/2025/press-release-vi-unveils-vi-protect-aI-powered-safety-for-customers-and-enterprisess-at-iMC-2025.pdf)
- [Vi Spam SMS terms](https://www.myvi.in/content/dam/vodafoneideadigital/StaticPages/Vi-Spam-Solution-T&C.pdf)
- [Vi AI Spam SMS release (2 Dec 2024)](https://www.myvi.in/content/dam/vodafoneideadigital/StaticPages/PressReleases/2024/Press-Release-Vi-Introduces-AI-Powered-Spam-SMS-Identification-Solution-To-Safeguard-Customers.pdf)

## Evidence limitations

Public product pages describe capabilities but usually omit training data, thresholds, feature weights, full feed lists, false-positive/false-negative rates and reproducible test sets. Statements above are therefore capability comparisons, not independent certifications. Product availability and features can vary by country, plan, browser and device.