# 📂 Category 1 — APIs with FREE trial tier (API key required)

These give you an API key for free. **Direct link to get the key** in the last column:

| # | Service | What it checks / returns | Free limit | 🔑 Get API key |
|---|---------|--------------------------|------------|----------------|
| 1 | **Google Safe Browsing** | Verdict on phishing / malware / unwanted software | 10,000 req/day | [console.cloud.google.com/flows/enableapi?apiid=safebrowsing.googleapis.com](https://console.cloud.google.com/flows/enableapi?apiid=safebrowsing.googleapis.com) |
| 2 | **VirusTotal** | 90+ scanners' verdicts (harmless/malicious/suspicious counts) — *can be turned into a real score* | 4 req/min, 500/day | [virustotal.com](https://www.virustotal.com) → sign up → profile icon → **API Key** |
| 3 | **APIVoid Domain Reputation** | Blacklist detections + risk score + TLD/category checks (`api.apivoid.com/v2/domain-reputation`) | ⚠️ **25 free credits one-time** (true "trial"), then paid | [app.apivoid.com/register](https://app.apivoid.com/register) → Dashboard |
| 4 | **URLScan.io** | Full website screenshot, requests, DOM, verdicts — rich forensic JSON | Generous free tier (public scans) | [urlscan.io/user/signup](https://urlscan.io/user/signup/) → profile → **+ Create API key** ([urlscan.io/user/profile](https://urlscan.io/user/profile/)) |
| 6 | **URLhaus (abuse.ch)** | Malware-hosting URL database ↔ also **ThreatFox & MalwareBazaar** with the *same key* | Free (fair use) | [auth.abuse.ch](https://auth.abuse.ch/) → free account → Auth-Key *(required since ~2025 — no key = no access)* |
| 7 | **AlienVault OTX** | Community threat intel "pulses" (phishing/malware IOCs per URL/domain/IP) | Free, unlimited lookup | [otx.alienvault.com](https://otx.alienvault.com) → sign up → **Account Settings → API key** |
| 8 | **Pulsedive** | Threat intel enrichment, risk scores per URL/domain/IP | Free tier | [pulsedive.com](https://pulsedive.com) → register → **Account → API key** |
| 9 | **AbuseIPDB** | IP abuse reports + **abuse confidence score (0–100)** | 1,000 checks/day | [abuseipdb.com/register](https://www.abuseipdb.com/register) → **Account → API tab** |

---

# 📂 Category 2 — FREE, no API key needed

| # | Service | Access |
|---|---------|--------|
| 10 | **Qualys SSL Labs** | Free public REST API (`api.ssllabs.com/api/v3/analyze?host=...`) — SSL grade A+ → F, cert issues. Just register optionally: [ssllabs.com/ssltest](https://www.ssllabs.com/ssltest/) |
| 11 | **crt.sh** | Free Certificate Transparency search — JSON via `https://crt.sh/?q=domain&output=json` or direct PostgreSQL access. No key, rate-limited |
| 12 | **OpenPhish (Community Feed)** | Free phishing URL feed: `https://openphish.com/feed.txt` (updates every 12h; free for non-commercial use) |
| 13 | **Spamhaus DNSBLs (SBL/DBL/ZEN)** | **Not a REST API** — queried via **DNS lookups**, free for low-volume/**non-commercial** use, no key. Production/commercial needs a Spamhaus [DQS key](https://www.spamhaus.org/product/data-query-service/) (30-day free trial available) |

---

# 📂 Category 3 — Datasets for training ML models 🧠

| # | Source | Contents | Link |
|---|--------|----------|------|
| 14 | **Mendeley Phishing Websites Dataset** ⭐ | **88,647 labeled URLs (58k legit / 30.6k phishing), 111 pre-extracted features, ready-to-train CSV** — the main one for ML | [data.mendeley.com/datasets/72ptz43s9v/1](https://data.mendeley.com/datasets/72ptz43s9v/1) — also the [80k-URL + raw HTML variant](https://data.mendeley.com/datasets/n96ncsr5g4/1) and [11.4k-URL / 87-feature variant](https://data.mendeley.com/datasets/c2gw7fy2j4/3) |
| 15 | **PhishTank verified feed** ⬈ dual-role | Hourly-updated CSV/XML/JSON of **verified phishing URLs** = perfect "positive" label class | [phishtank.com/developer_info.php](https://phishtank.com/developer_info.php) (needs the free key from Cat. 1) |
| 16 | **OpenPhish feed** ⬈ dual-role | Phishing URL feed = "positive" labels | [openphish.com/feed.txt](https://openphish.com/feed.txt) |
| 17 | **URLhaus CSV dumps** ⬈ dual-role | Malicious-URL bulk exports (CSV) = "malware" label class | [urlhaus.abuse.ch/browse → Downloads](https://urlhaus.abuse.ch/browse/) |
| 18 | **Spamhaus DBL/ZEN** ⬈ dual-role | Blocklisted domains = "spam/phish" labels for domain-reputation models | via DNS (Cat. 2) |
| 19 | **AlienVault OTX pulses** ⬈ dual-role | Exportable IOC pulses per campaign = labeled phishing/malware/C2 data | [otx.alienvault.com/browse/static/pulses](https://otx.alienvault.com/browse/static/pulses) |
| 20 | **crt.sh / CT logs** (supplementary) | Not *labeled*, but great for **feature engineering** (cert age, issuer, SAN count for phishing detection) | [crt.sh](https://crt.sh) |

---

# 📂 Category 4 — Neither (dev tools, not security feeds, no key)

| # | Tool | Purpose |
|---|------|---------|
| 21 | **W3C Link Checker** | CLI/web tool for finding **broken links** (website QA, not phishing detection). `npm`/Perl install, no key |
| 22 | **Linkinator** | Same — broken-link crawler (`npx linkinator https://site.com`), no key |

---

### 🎯 TL;DR for your scoring engine

- **Score sources (reputation → /10):** Google Safe Browsing + VirusTotal + AbuseIPDB (already gives 0–100!) + APIVoid + Pulsedive
- **Evidence sources:** URLScan.io + Qualys + crt.sh
- **Blacklist/enrichment:** Spamhaus + PhishTank + URLhaus + OTX
- **ML training labels:** Mendeley (ready CSV) + PhishTank + OpenPhish + URLhaus dumps