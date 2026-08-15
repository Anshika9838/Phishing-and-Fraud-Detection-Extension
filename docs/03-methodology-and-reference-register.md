# Methodology and Official Reference Register

## Scope and selection

The analysis covers 13 representative products as of 15 August 2026:

- **Indian network/device market:** Airtel, Vi Protect, JioSecurity.
- **Browser/OS platforms:** Google Safe Browsing/Chrome, Microsoft Defender SmartScreen.
- **Direct browser security:** Guardio, Netcraft, Malwarebytes Browser Guard, Bitdefender TrafficLight, Norton Safe Web, McAfee WebAdvisor.
- **Cross-channel scam intelligence:** Bitdefender Scamio, McAfee Scam Detector, Truecaller.
- **Enterprise architectural alternative:** Cloudflare Browser Isolation.

Some vendors are grouped where products are intentionally complementary (for example TrafficLight + Scamio). “Competitor” means an alternative for at least part of the user’s scam/phishing protection goal; it does not imply identical deployment or telemetry.

## Research method

1. Cloned the public GitHub repository at the identified commit.
2. Read architecture documents, Chromium manifest/scripts/UI, FastAPI backend, threat providers, scoring, LLM normalizer, infrastructure analyzer and Flutter client.
3. Ran Python syntax compilation.
4. Used official vendor product pages, help pages, protocol/API documentation, terms and press releases as primary evidence.
5. Distinguished **documented fact**, **vendor claim**, **code inference** and **recommendation**.
6. Did not infer undisclosed algorithms. Where documentation says “AI,” “advanced model,” or “real time” without architecture/metrics, the report preserves that limitation.

## Comparison dimensions

- Deployment and reach
- Collection/input signals
- Reputation/threat intelligence
- Domain/network infrastructure
- Rendered content, behavior and AI
- Decision fusion and uncertainty
- Intervention timing and enforcement
- Feedback, appeals and operations
- Privacy, governance and assurance

## Key official technical references

### Project dependencies
- Google Safe Browsing v5: https://developers.google.com/safe-browsing/reference
- Google Safe Browsing Real-Time Mode: https://developers.google.com/safe-browsing/reference/Real.Time.Mode
- VirusTotal “How it works”: https://docs.virustotal.com/docs/how-it-works
- urlscan.io API: https://urlscan.io/docs/api/
- URLhaus API: https://urlhaus-api.abuse.ch/
- OpenPhish: https://openphish.com/
- AlienVault OTX API: https://otx.alienvault.com/api
- AbuseIPDB API: https://docs.abuseipdb.com/
- Pulsedive API: https://pulsedive.com/api/
- Spamhaus Technology: https://www.spamhaus.com/technology/
- crt.sh Certificate Transparency search: https://crt.sh/
- Qualys SSL Labs API: https://github.com/ssllabs/ssllabs-scan/blob/master/ssllabs-api-docs.md
- Gemini API documentation: https://ai.google.dev/gemini-api/docs

### Competitors
See each individual file in `competitors/` for official product-specific links. Those files intentionally keep references next to the relevant comparison.

## Limitations

- No paid accounts, private architecture documents, source code or internal dashboards from competitors were used.
- Vendor performance/impact figures are not treated as independent laboratory results unless a reproducible test protocol is available.
- The Theft Alert backend was not exercised against malicious URLs because no API keys/isolated detonation environment were supplied.
- Product features may vary by geography, subscription, OS, browser, carrier and staged rollout.
- This is technical/product analysis, not legal, privacy, regulatory or procurement advice.

## Suggested reproducible benchmark

Create a time-boxed evaluation where URLs are tested within minutes of collection:

- 2,000 confirmed fresh phishing URLs (balanced across credential, payment, fake support, investment, delivery and UPI themes)
- 1,000 malware/drive-by URLs in an isolated sandbox
- 5,000 benign URLs, including young domains, Indian SMEs, SSO/payment redirects and multilingual sites
- 1,000 adversarial pages: cloaking, IDN homographs, URL shorteners, delayed DOM injection, prompt injection, image-only phishing and CAPTCHA gates

Report recall by class, false-positive rate, precision, coverage/unknown rate, p50/p95/p99 latency, page-load overhead, detection before first credential interaction, provider outage behavior and language slices. Freeze feed snapshots and product versions so results are reproducible.
