# Theft Alert — Frequently Asked Questions

**Project:** Phishing-and-Fraud-Detection-Extension / Theft Alert  
**Repository:** https://github.com/Anshika9838/Phishing-and-Fraud-Detection-Extension  
**Repository snapshot reviewed:** `4cd8fc4e755c244de0c6a41c0dfe3ea094c13ac5`  
**License:** MIT License  
**FAQ date:** 15 August 2026

## How to read these answers

These answers describe the workflow and architecture implemented in the reviewed repository. They distinguish between:

- **Current behavior:** what the source code does now.
- **Existing safeguards:** controls already present in the code.
- **Recommended production direction:** changes needed before presenting the project as a production security service.

The project is an open-source prototype, not a guarantee that phishing, fraud or scams will always be detected. A warning system should complement browser, endpoint, network and user-security controls rather than replace them.

---

## 1. How does the project handle user privacy? Does sending page content violate privacy even when the content is sanitized?

This is a valid concern. Sanitization reduces exposure, but it does not eliminate the privacy impact of transmitting webpage content.

### Current behavior

The Chromium content script sends the backend:

- Full page URL and domain
- Page title and favicon URL
- The first 1,500 characters of visible `document.body.innerText`
- Hyperlinks
- Image, script and stylesheet URLs
- Form actions, methods and field metadata such as name, type, ID and placeholder
- Iframe URLs
- Selected network-request metadata

The extension deliberately does **not** collect values typed into form controls. That protects passwords, OTPs and entered card details from direct form-value collection. However, the remaining payload may still contain sensitive information. URLs can contain query parameters, document IDs or tokens; visible page text can include account, health, customer or internal-business information; placeholders and resource URLs can reveal workflow context.

The FastAPI backend currently writes full scan payloads to `scan_reports.log` and analysis details to `analysis_results.log`. The repository does not currently define authentication, encryption-at-rest, redaction, retention, deletion, access control or a user-facing privacy policy. Therefore, the current code should not be described as fully privacy-preserving.

### Self-hosting option

The project is released under the **MIT License**. An organization may clone and modify it, deploy the backend on its own controlled server, configure the extension to use that server, and distribute the extension across organization-managed devices. This keeps page telemetry within infrastructure controlled by the organization rather than a public project-operated service, subject to any third-party threat-intelligence and LLM API calls the organization enables.

Self-hosting improves data control, but it does not automatically resolve privacy obligations. The organization still needs lawful authorization, employee notice, access restrictions, data minimization, retention limits, incident response and appropriate regional/compliance review.

### Recommended production privacy model

1. Run URL-only and local heuristic checks first.
2. Remove URL fragments and redact sensitive query parameters before transmission.
3. Send hashes, hostnames or bounded features instead of raw content where possible.
4. Submit page text to the backend or LLM only when risk remains uncertain and policy allows it.
5. Make content logging disabled by default.
6. Encrypt data in transit and at rest.
7. Define strict retention and deletion schedules.
8. Allow organizations to disable Gemini and selected external providers.
9. Document exactly which fields leave the browser and which third parties receive them.

---

## 2. Why should someone use this project instead of an existing solution?

The project should not presently be positioned as universally better than established products. Existing browser, operating-system and telecom protections have larger threat datasets, earlier blocking, mature operations and measured scale.

The project offers a different value proposition:

- **Open source and inspectable:** organizations can review and modify the detection rules and backend.
- **MIT licensed:** it can be cloned, adapted, self-hosted and internally distributed in accordance with the license.
- **Organization-controlled deployment:** a company can run the backend on its own server and distribute a configured extension to proprietary or organization-managed devices.
- **Multiple evidence layers:** it combines threat feeds, DNS/WHOIS/TLS/Certificate Transparency signals, URL heuristics, rendered page structure and optional Gemini analysis.
- **Detailed explanations:** the UI can show source-level evidence rather than only a binary block page.
- **Carrier independence:** the browser layer is not limited to a particular telecom network.
- **Custom policy potential:** an organization can add internal allowlists, blocklists, brand/domain mappings and private threat intelligence.

A reasonable enterprise use would be as an **additional organization-controlled analysis layer** alongside Chrome Safe Browsing, Microsoft Defender, DNS filtering, email security and endpoint protection. The objective is to reduce the probability that staff interact with scam, phishing or fraudulent pages while keeping relevant telemetry on the organization’s own server for authorized analysis and verification.

It cannot guarantee that no organization member will be scammed. That outcome also depends on secure deployment, browser policy, identity controls, user training, response procedures and the accuracy of configured feeds and models.

---

## 3. How does the solution reduce the cost of analyzing large pages with an LLM?

The current architecture already limits what is sent to Gemini:

- The browser truncates visible page text to 1,500 characters.
- The backend builds a compact scan summary instead of sending the complete DOM.
- Forms, links, external hosts and reputation checks are limited to bounded samples.
- Resource bodies and full JavaScript source are not sent to the LLM.
- Reputation and infrastructure checks are performed by deterministic code and external APIs; the LLM is used primarily for contextual judgment and explanation.
- If no Gemini API key is configured, or if Gemini fails, the system uses a deterministic heuristic fallback.

These controls make LLM cost less dependent on the complete page size. A page with a very large DOM does not result in the entire document being included in the prompt.

However, the code can still generate repeated LLM calls after meaningful DOM changes and network-activity reports. Consequently, the current version does not yet provide a complete cost-control system.

Recommended controls are:

1. Cache verdicts by canonical URL, domain and content signature.
2. Run the LLM only when reputation and deterministic rules cannot produce a sufficiently confident action.
3. Apply per-device, per-domain and per-tenant request quotas.
4. Do not invoke the LLM for every network request.
5. Batch related signals into one bounded scan window.
6. Use a smaller local or organization-hosted model for first-pass classification.
7. Set hard prompt-token and response-token limits.
8. Record token usage, model cost and cache-hit rate.

---

## 4. Scan time depends on several factors and can increase with content size. How is response time handled, or expected to be handled?

Content size has some effect, but under the current architecture it is not the only or necessarily the largest source of delay. Visible text is capped at 1,500 characters, while links, forms and resources may still take time to enumerate. Backend latency is mainly affected by:

- DNS resolution
- WHOIS and TLS checks
- Optional SSL Labs analysis
- Ten external reputation providers
- Provider rate limits and network timeouts
- Gemini response time
- Repeated scans after dynamic page changes

The backend improves latency by running reputation checks in parallel and running the reputation group and infrastructure group concurrently with `asyncio.gather`. This avoids waiting for every provider sequentially. The overall duration still tends toward the slowest required provider or timeout.

The Gemini request is made through the synchronous `requests` library while handling an asynchronous FastAPI route. Under concurrent load, that can block a worker and should be changed to an asynchronous client or moved to a bounded worker queue.

A production response-time design should use two phases:

- **Fast verdict:** local cache, canonical URL, high-confidence blocklist and lightweight URL rules, ideally before navigation.
- **Deep verdict:** infrastructure, page semantics, sandboxing and LLM explanation delivered asynchronously when needed.

Additional improvements should include provider-specific deadlines, cancellation, circuit breakers, result caching, stale-but-safe cache use, background refresh, request deduplication, and p50/p95/p99 latency monitoring. The UI should distinguish “quick check complete” from “deep analysis still running” rather than holding all protection behind one slow operation.

---

## 5. Scanning the document after every network interception or DOM manipulation can create high computational cost. How is this managed?

The browser code contains two controls:

1. DOM changes are debounced for two seconds.
2. A signature based on links, form structure and iframes is used to avoid sending an identical DOM-change report.

These are helpful, but they do not fully solve the problem. A meaningful DOM change can still trigger a new full page snapshot and backend pipeline. Network activity is also sent as a report, and `/api/report` currently executes the same broad reputation, infrastructure and LLM workflow for that report. On modern applications with frequent API calls and DOM changes, this can create excessive browser work, backend traffic, external API usage and LLM cost.

A better architecture should:

- Maintain one scan session per tab and navigation.
- Send incremental feature differences rather than a complete snapshot.
- Ignore same-origin routine API calls unless sensitive data or a new destination is involved.
- Aggregate network events into a short time window.
- Trigger rescans only for security-relevant changes, such as a newly added password form, external form action, iframe, redirect or executable resource.
- Apply a maximum number of deep scans per page and per minute.
- Cache domain and canonical-URL intelligence.
- Run the LLM once per stable page state, not once per event.
- Use backpressure when the backend or providers are degraded.

Therefore, the correct answer is that the prototype has basic debounce and deduplication, while production-grade computational control remains a required enhancement.

---

## 6. Does the extension collect passwords, OTPs, card numbers or values entered into forms?

The reviewed content script does not read form-control values. It collects structural metadata such as field name, type, ID and placeholder, together with the form action and method. This enables detection of password fields, payment-like fields and forms that submit to another domain without intentionally collecting what the user typed.

Visible page text and URLs can still contain sensitive data independently of form values, so the privacy controls described in Question 1 remain necessary.

---

## 7. Is every visited page sent to the backend?

Under the current manifest, the content script matches `<all_urls>` and runs at `document_idle`. The initial top-frame page snapshot is sent automatically, and meaningful later changes may trigger additional reports. Manual scans can also be initiated from the popup.

This broad behavior is useful for coverage but creates privacy, performance and permission concerns. An organization may modify the MIT-licensed extension to limit scanning to approved domains, high-risk categories, external websites, manual activation or managed-browser policies. A production edition should support explicit scope controls and exclusions for sensitive applications.

---

## 8. Does the project block a malicious page before it loads?

Not reliably in its current form. The content script runs at `document_idle`, collects the rendered page, sends it to the backend and waits for analysis. By that point, the page and some scripts may already have executed.

The extension can display a threat overlay after the verdict, but that is not equivalent to pre-navigation blocking. A production design should perform a URL reputation/cache check before or at navigation, then reserve DOM and LLM analysis for a secondary verdict. For uncertain high-risk pages, the project could disable credential submission, redirect to a warning page or open the destination in an isolation service.

---

## 9. What happens if Gemini is unavailable or the organization does not want to send data to an LLM provider?

The backend contains a deterministic heuristic fallback. It evaluates signals including Safe Browsing status, HTTP use, punycode, subdomain depth, password inputs, external form actions, credential-like fields, suspicious pressure terms, external links/iframes and cross-domain network activity.

An organization can omit the Gemini API key and operate using the fallback plus reputation and infrastructure layers. Because the project is MIT licensed, the organization can also replace Gemini with an internal model or remove LLM analysis entirely.

The trade-off is that fallback behavior must be independently tested and calibrated. Disabling an external LLM improves data control but does not by itself guarantee detection accuracy.

---

## 10. What happens when a threat-intelligence API key is missing, an API is down or a provider rate-limits the backend?

Provider functions generally return an `UNKNOWN` result with low confidence and a neutral risk near 50 when a key is missing or an error occurs. The other checks can still complete, and Gemini has a fallback path.

This supports graceful execution, but averaging unknown results into a numerical score can be misleading. A production policy should report provider health separately, preserve `UNKNOWN` as an uncertainty state, define a minimum set of required signals and avoid describing an incomplete scan as safe.

Caching and circuit breakers are also needed to prevent repeated calls to a failing or rate-limited provider.

---

## 11. How is the final risk score calculated?

The repository currently has two related but different decision paths:

- The browser’s `/api/report` path uses Gemini, or the deterministic fallback, to produce the principal risk score and explanation. A confirmed Google Safe Browsing threat applies a high-risk safety floor.
- The URL-only `/api/scan_url` path uses a confidence-adjusted weighted average over reputation and infrastructure checks. High-confidence malicious results from critical sources can enforce minimum scores.

The scores are heuristic risk indicators, not calibrated probabilities. A score of 80 does not mean there is an independently demonstrated 80% probability that the site is malicious.

Before production use, the two paths should be unified under one versioned policy engine and calibrated against a labeled test corpus.

---

## 12. Can a clean result guarantee that a website is safe?

No. A clean result means that the available configured signals did not identify a strong threat at that time. Newly created phishing sites, cloaked pages, compromised legitimate domains, image-only attacks and provider outages can evade detection.

The UI and documentation should distinguish:

- Confirmed malicious
- High-risk/suspicious
- No known threat indicators
- Unknown or incomplete analysis

“No known threat indicators” must not be presented as an absolute guarantee of safety.

---

## 13. Can this replace Google Safe Browsing, Microsoft Defender, antivirus, email security or telecom scam protection?

No. The project uses Google Safe Browsing as one input and complements rather than recreates operating-system, carrier and enterprise-security telemetry.

It does not currently provide full download scanning, application reputation, endpoint malware remediation, email attachment analysis, caller/SMS behavior intelligence, remote browser isolation or enterprise identity policy. Its intended strength is combining URL intelligence, infrastructure signals and rendered-page semantics into an explainable report.

A secure deployment should retain built-in browser protection and other endpoint/network controls.

---

## 14. Can an organization deploy the project entirely on its own infrastructure?

Yes, subject to the MIT License and the licenses/terms of any third-party APIs it chooses to use. An organization can:

1. Clone the repository.
2. Configure and harden the FastAPI backend on an internal or organization-controlled server.
3. Replace the hard-coded localhost HTTP/WS endpoints with organization HTTPS/WSS endpoints.
4. Add authentication, device identity, rate limits and tenant isolation.
5. Configure or remove external threat-intelligence providers.
6. Disable Gemini or replace it with an internal model.
7. Distribute the extension through managed-browser enterprise policies to organization-controlled devices.
8. Keep authorized scan records on its own server for security analysis, verification and incident response.

Third-party APIs may still receive URLs, domains, IPs or summary data. A deployment is not fully internal unless those calls are removed, proxied under suitable agreements or replaced with locally maintained feeds/models.

The MIT License also includes a warranty/liability disclaimer. The deploying organization is responsible for testing, security, compliance and operational support.

---

## 15. How should self-hosted scan data be secured and used for further analysis?

The organization should treat scan data as security telemetry that may contain confidential information. Recommended controls include:

- HTTPS/WSS and service authentication
- Per-device or per-user request identity
- Role-based access for security analysts
- Encryption at rest and managed keys
- Query-string and token redaction
- Default-off raw content logging
- Short retention for raw page samples
- Longer retention only for minimized indicators and confirmed incidents
- Audit logs for access and export
- Separation between user telemetry, analyst labels and training datasets
- Human review before promoting a manual report to an internal blocklist
- Documented deletion and appeal procedures

Using organizational telemetry to retrain or evaluate a model requires separate governance. Data collected for immediate protection should not automatically become unrestricted training data.

---

## 16. How are false positives handled?

The extension shows evidence and allows a user to close a warning, but the repository does not include a complete false-positive appeal, analyst review or allowlisting workflow. The manual-report endpoint only logs reported URLs.

A production deployment should provide:

- Organization allowlists with expiry and owner approval
- User feedback tied to the scan ID and evidence
- Analyst review queues
- Source-level provenance
- Re-scan and re-evaluation after feed changes
- Temporary exceptions rather than permanent global trust
- Metrics for false-positive rate by rule, source, language and site category

This is especially important because legitimate SSO, payment gateways, young domains and third-party form processors can resemble phishing heuristics.

---

## 17. How does the project protect itself from abuse or malicious scan requests?

The reviewed backend does not yet contain the required production controls. REST routes and WebSocket connections are unauthenticated, CORS is broadly configured, and user results are broadcast to all connected WebSockets. URL-only checks also require explicit server-side request-forgery defenses before exposure to untrusted callers.

Required protections include authentication, authorization, per-client WebSocket channels, quotas, rate limiting, request-size limits, scheme restrictions, private/link-local/metadata IP blocking, redirect validation, timeouts, input normalization, abuse monitoring and audit logs.

Until these are implemented, the backend should not be exposed directly to the public internet.

---

## 18. What are the most important next steps before an organization-wide rollout?

1. Secure the backend with HTTPS/WSS, authentication, authorization and per-client responses.
2. Remove global WebSocket broadcasts.
3. Implement SSRF protection and strict URL validation.
4. Make raw content logging opt-in, redacted and retention-controlled.
5. Add pre-navigation URL checks and cached enforcement.
6. Unify LLM and weighted scoring into one policy engine.
7. Add provider caching, deadlines, circuit breakers and cost budgets.
8. Replace repeated full-page/network scans with session-based incremental analysis.
9. Create false-positive, manual-report and analyst-review workflows.
10. Build a reproducible benchmark covering fresh phishing, benign sites, Indian languages, prompt injection and provider outages.
11. Measure p50/p95/p99 scan latency, page overhead, LLM usage and external API cost.
12. Perform extension/backend security review and managed-device pilot before broad distribution.

---

## Summary

Theft Alert’s architecture demonstrates how an organization-controlled extension can combine threat intelligence, website infrastructure and page semantics. Its MIT License makes private adaptation and self-hosted distribution possible. The strongest privacy configuration is an organization-hosted backend with minimal content collection, carefully governed logs, optional internal AI and controlled external-provider access.

The current repository remains a prototype. Its existing truncation, sanitized form metadata, parallel checks, fallback heuristics, debounce and DOM signature are useful foundations, but they do not fully resolve privacy, cost, latency, repeated-computation or production-security concerns. Those limitations should be stated plainly and addressed before organization-wide use.
