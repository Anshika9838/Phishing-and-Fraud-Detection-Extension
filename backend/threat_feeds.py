"""
High-end threat intelligence aggregator.
Checks: Google Safe Browsing, VirusTotal, URLScan.io, URLhaus, OTX, Pulsedive, AbuseIPDB, Spamhaus, OpenPhish, crt.sh
Each check returns standardized dict:
{
  "source": str,
  "risk_score": 0-100,
  "weight": 1-10,
  "verdict": SAFE|MALICIOUS|SUSPICIOUS|UNKNOWN|LOW_RISK,
  "confidence": 0-100,
  "details": str,
  "description": str, # human readable message from source
  "raw": optional trimmed dict
}
"""
import os
import base64
import asyncio
import socket
import httpx
import dns.resolver
from urllib.parse import urlparse, quote
from typing import Dict, Any, Optional, List, Coroutine

# ---------- API KEY FLEXIBLE LOADER ----------
def get_api_key(primary_name: str, *alternatives: str) -> Optional[str]:
    """
    Tries many env var variations: exact, upper, lower, snake, and os.environ case-insensitive scan.
    primary_name is e.g. GOOGLE_API_KEY
    alternatives can be like VirusTotal, spamhaus etc that user mentioned in prompt
    """
    candidates = [primary_name] + list(alternatives)
    # also try stripping and common transformations
    env_lower = {k.lower(): v for k, v in os.environ.items() if v}
    for cand in candidates:
        # direct
        val = os.getenv(cand)
        if val and val.strip():
            return val.strip()
        # upper
        val = os.getenv(cand.upper())
        if val and val.strip():
            return val.strip()
        # lower
        val = os.getenv(cand.lower())
        if val and val.strip():
            return val.strip()
        # lower in env_lower
        if cand.lower() in env_lower and env_lower[cand.lower()].strip():
            return env_lower[cand.lower()].strip()

    # last try: look for keys that contain primary substring
    # e.g. user wrote "VirusTotal" -> env may have VT_API_KEY ?
    return None

def _clean_domain(url: str) -> str:
    try:
        parsed = urlparse(url if "://" in url else f"https://{url}")
        host = parsed.hostname or ""
        return host.lower().strip()
    except:
        return ""

def _get_ip(domain: str) -> Optional[str]:
    try:
        answers = dns.resolver.resolve(domain, 'A')
        if answers:
            return answers[0].to_text()
    except:
        pass
    # fallback socket
    try:
        return socket.gethostbyname(domain)
    except:
        return None

# ---------- GOOGLE SAFE BROWSING ----------
async def check_google_safe_browsing(url: str, client: httpx.AsyncClient) -> Dict[str, Any]:
    api_key = get_api_key("GOOGLE_API_KEY", "GOOGLE_SAFE_BROWSING_KEY", "GOOGLE_SAFE_BROWSING_API_KEY", "SAFE_BROWSING_API_KEY")
    if not api_key:
        return {
            "source": "Google Safe Browsing",
            "risk_score": 50,
            "weight": 10,
            "verdict": "UNKNOWN",
            "confidence": 0,
            "details": "API key not configured - skipping check (neutral score).",
            "description": "Could not verify with Google Safe Browsing: API key missing."
        }
    api_url = f"https://safebrowsing.googleapis.com/v4/threatMatches:find?key={api_key}"
    payload = {
        "client": {"clientId": "phishing-detection-extension", "clientVersion": "2.0.0"},
        "threatInfo": {
            "threatTypes": ["MALWARE", "SOCIAL_ENGINEERING", "UNWANTED_SOFTWARE", "POTENTIALLY_HARMFUL_APPLICATION"],
            "platformTypes": ["ANY_PLATFORM"],
            "threatEntryTypes": ["URL"],
            "threatEntries": [{"url": url}]
        }
    }
    try:
        resp = await client.post(api_url, json=payload, timeout=12)
        resp.raise_for_status()
        data = resp.json()
        if "matches" in data and data["matches"]:
            threat_type = data["matches"][0].get("threatType", "UNKNOWN")
            return {
                "source": "Google Safe Browsing",
                "risk_score": 100,
                "weight": 10,
                "verdict": "MALICIOUS",
                "confidence": 98,
                "details": f"Google flagged URL as {threat_type.replace('_',' ').title()} - confirmed threat in Google's database.",
                "description": f"Listed as malicious: {threat_type}. Google Safe Browsing considers this URL dangerous.",
                "raw": data
            }
        else:
            return {
                "source": "Google Safe Browsing",
                "risk_score": 3,
                "weight": 10,
                "verdict": "SAFE",
                "confidence": 92,
                "details": "URL not found in Google Safe Browsing threat lists - no known phishing/malware/social engineering reports.",
                "description": "Clean according to Google Safe Browsing (10k req/day free tier)."
            }
    except Exception as e:
        return {
            "source": "Google Safe Browsing",
            "risk_score": 50,
            "weight": 10,
            "verdict": "UNKNOWN",
            "confidence": 10,
            "details": f"API error: {str(e)[:250]}",
            "description": f"Could not verify with Google Safe Browsing due to error."
        }

# ---------- VIRUSTOTAL ----------
async def check_virustotal(url: str, client: httpx.AsyncClient) -> Dict[str, Any]:
    api_key = get_api_key("VIRUSTOTAL_API_KEY", "VirusTotal", "VT_API_KEY", "VIRUS_TOTAL_API_KEY", "VIRUSTOTAL_KEY")
    if not api_key:
        return {
            "source": "VirusTotal",
            "risk_score": 50,
            "weight": 9,
            "verdict": "UNKNOWN",
            "confidence": 0,
            "details": "VirusTotal API key not configured.",
            "description": "VirusTotal check skipped - API key missing. VirusTotal aggregates 90+ scanners."
        }
    try:
        url_id = base64.urlsafe_b64encode(url.encode()).decode().strip("=")
        headers = {"x-apikey": api_key, "Accept": "application/json"}
        resp = await client.get(f"https://www.virustotal.com/api/v3/urls/{url_id}", headers=headers, timeout=15)

        if resp.status_code == 404:
            # URL not scanned before -> try to submit? For now low risk but unknown
            # Optionally submit for analysis
            try:
                await client.post("https://www.virustotal.com/api/v3/urls",
                                  headers=headers,
                                  data={"url": url},
                                  timeout=15)
                # don't wait for analysis, just inform
            except:
                pass
            return {
                "source": "VirusTotal",
                "risk_score": 15,
                "weight": 9,
                "verdict": "UNKNOWN",
                "confidence": 40,
                "details": "URL not previously scanned by VirusTotal. No historical malicious detections. URL submitted for new scan.",
                "description": "No prior VirusTotal reports - considered unlisted (good sign), submitted for fresh scanning.",
                "raw": {"status": "not_found"}
            }

        resp.raise_for_status()
        data = resp.json()
        attrs = data.get("data", {}).get("attributes", {})
        stats = attrs.get("last_analysis_stats", {})
        malicious = stats.get("malicious", 0)
        suspicious = stats.get("suspicious", 0)
        harmless = stats.get("harmless", 0)
        undetected = stats.get("undetected", 0)
        timeout = stats.get("timeout", 0)
        total = malicious + suspicious + harmless + undetected + timeout
        reputation = attrs.get("reputation", 0)
        # risk calc
        if malicious >= 10:
            risk = 100
            verdict = "MALICIOUS"
        elif malicious >= 5:
            risk = 95
            verdict = "MALICIOUS"
        elif malicious >= 2:
            risk = 85
            verdict = "MALICIOUS"
        elif malicious == 1:
            risk = 70
            verdict = "SUSPICIOUS"
        elif suspicious >= 5:
            risk = 65
            verdict = "SUSPICIOUS"
        elif suspicious >= 1:
            risk = 40
            verdict = "SUSPICIOUS"
        elif harmless >= 10:
            risk = 5
            verdict = "SAFE"
        else:
            risk = 20
            verdict = "LOW_RISK"

        confidence = min(95, 40 + malicious*10 + harmless)

        # Build description
        top_engines = []
        results = attrs.get("last_analysis_results", {})
        for engine, res in list(results.items())[:90]:
            if res.get("category") in ("malicious", "suspicious"):
                top_engines.append(f"{engine}({res.get('result')})")
        engines_str = ", ".join(top_engines[:6]) if top_engines else "No engine flagged"
        details = f"{malicious} malicious, {suspicious} suspicious, {harmless} harmless out of {total} scanners. Reputation: {reputation}. Engines: {engines_str}. Last analysis: {attrs.get('last_analysis_date', 'N/A')}"
        description = (
            f"{'⚠️ FLAGGED: ' if malicious>0 else '✅ Clean: '}"
            f"VirusTotal reports {malicious} malicious detections. "
            f"{'High confidence threat.' if malicious>=3 else 'No confirmed threat, but check other sources.' if malicious==0 else 'Potential risk.'}"
        )
        return {
            "source": "VirusTotal",
            "risk_score": risk,
            "weight": 9,
            "verdict": verdict,
            "confidence": confidence,
            "details": details,
            "description": description,
            "raw": {"stats": stats, "reputation": reputation}
        }
    except Exception as e:
        return {
            "source": "VirusTotal",
            "risk_score": 50,
            "weight": 9,
            "verdict": "UNKNOWN",
            "confidence": 10,
            "details": f"VirusTotal API error: {str(e)[:300]}",
            "description": "Could not verify with VirusTotal due to API error or rate limit (4 req/min, 500/day free)."
        }

# ---------- URLSCAN.IO ----------
async def check_urlscan(url: str, domain: str, client: httpx.AsyncClient) -> Dict[str, Any]:
    api_key = get_api_key("URLSCAN_API_KEY", "URLScan_io", "URLSCAN_IO_API_KEY", "URLSCAN_IO_KEY")
    # URLScan search works even without key (public), but with key more results
    headers = {}
    if api_key:
        headers["API-Key"] = api_key
    try:
        # Search by domain or url
        search_q = f'page.domain:"{domain}"' if domain else f'page.url:"{url}"'
        # Use api/v1/search/?q=
        resp = await client.get(f"https://urlscan.io/api/v1/search/?q={search_q}",
                            headers=headers, timeout=15)
        # If fails try url search
        if resp.status_code != 200 and not domain:
            search_q = f'page.url:"{url}"'
            resp = await client.get(f"https://urlscan.io/api/v1/search/?q={search_q}",
                                 headers=headers, timeout=15)
        resp.raise_for_status()
        data = resp.json()
        total = data.get("total", 0)
        results = data.get("results", [])

        if total == 0 or not results:
            # Not found historically -> we could submit a new scan if key exists
            if api_key:
                try:
                    scan_payload = {"url": url, "visibility": "public"}
                    post = await client.post("https://urlscan.io/api/v1/scan/",
                                             headers={**headers, "Content-Type": "application/json"},
                                             json=scan_payload, timeout=15)
                    if post.status_code == 200:
                        scan_data = post.json()
                        return {
                            "source": "URLScan.io",
                            "risk_score": 30,
                            "weight": 7,
                            "verdict": "UNKNOWN",
                            "confidence": 50,
                            "details": f"No historical scans for {domain} (0 results). Submitted new scan: {scan_data.get('api','')} - check urlscan.io result page. UUID: {scan_data.get('uuid','')}",
                            "description": "No prior URLScan records. Fresh scan initiated for forensic analysis.",
                            "raw": scan_data
                        }
                except Exception as sub_e:
                    pass
            return {
                "source": "URLScan.io",
                "risk_score": 20,
                "weight": 7,
                "verdict": "UNKNOWN",
                "confidence": 45,
                "details": f"No historical URLScan.io results for domain {domain} (searched {search_q}) - likely not previously scanned or low traffic.",
                "description": "No historical data in URLScan.io - not necessarily safe, but unlisted."
            }

        # Analyze first result
        latest = results[0] if results else {}
        page = latest.get("page", {})
        verdicts = latest.get("verdicts", {})
        overall = verdicts.get("overall", {})
        malicious_bool = overall.get("malicious", False)
        score = overall.get("score", 0)
        # tags
        tags = latest.get("tags", []) or []
        brand = page.get("brand", "") or ""
        # IPs etc
        country = page.get("country", "")
        # risk
        if malicious_bool is True:
            risk = 95
            verdict = "MALICIOUS"
            desc = f"URLScan flagged as malicious with score {score}. Tags: {', '.join(tags[:5])}. Brand impersonation maybe: {brand}"
        elif score and isinstance(score, (int,float)) and score > 0:
            # urlscan score can be 0-100? check
            risk = min(90, max(20, int(score)))
            verdict = "SUSPICIOUS" if risk >= 50 else "LOW_RISK"
            desc = f"URLScan score {score} - indicates suspicious behavior. Tags: {', '.join(tags[:5])}"
        else:
            # Check if tags contain phishing, suspicious etc
            suspicious_tags = [t for t in tags if any(k in t.lower() for k in ("phish","malicious","suspicious","fraud"))]
            if suspicious_tags:
                risk = 60
                verdict = "SUSPICIOUS"
                desc = f"URLScan tags suspicious: {suspicious_tags} - overall not marked malicious but caution."
            else:
                risk = 10
                verdict = "SAFE"
                desc = f"URLScan: {total} historical scans, latest appears benign. Country: {country}, server: {page.get('server','')}"

        details = f"Total scans: {total}. Latest: URL {page.get('url','')} Status: {page.get('status','')} Country: {country} Brand detection: {brand} Tags: {tags} Verdict malicious: {malicious_bool} Score: {score}"
        return {
            "source": "URLScan.io",
            "risk_score": risk,
            "weight": 7,
            "verdict": verdict,
            "confidence": 80 if total>0 else 40,
            "details": details,
            "description": desc,
            "raw": {"total": total, "latest": latest}
        }
    except Exception as e:
        return {
            "source": "URLScan.io",
            "risk_score": 50,
            "weight": 7,
            "verdict": "UNKNOWN",
            "confidence": 10,
            "details": f"URLScan.io API error: {str(e)[:300]}",
            "description": "Could not verify via URLScan.io forensic engine."
        }

# ---------- URLHAUS ----------
async def check_urlhaus(url: str, client: httpx.AsyncClient) -> Dict[str, Any]:
    api_key = get_api_key("URLHAUS_API_KEY", "urlhaus_abuse", "ABUSE_CH_API_KEY", "ABUSECH_API_KEY", "URLHAUS_AUTH_KEY")
    if not api_key:
        return {
            "source": "URLhaus (abuse.ch)",
            "risk_score": 50,
            "weight": 9,
            "verdict": "UNKNOWN",
            "confidence": 0,
            "details": "URLhaus API key (Auth-Key from abuse.ch) not configured. Since 2025 abuse.ch requires auth.",
            "description": "URLhaus check skipped - Auth-Key missing. URLhaus detects malware distribution URLs."
        }
    try:
        headers = {"Auth-Key": api_key}
        data = {"url": url}
        resp = await client.post("https://urlhaus-api.abuse.ch/v1/url/", headers=headers, data=data, timeout=15)
        resp.raise_for_status()
        j = resp.json()
        query_status = j.get("query_status", "")
        # no_results => not listed
        if query_status == "no_results":
            return {
                "source": "URLhaus (abuse.ch)",
                "risk_score": 5,
                "weight": 9,
                "verdict": "SAFE",
                "confidence": 90,
                "details": f"URL not found in URLhaus malware database (query_status: no_results).",
                "description": "Clean according to URLhaus malware URL database.",
                "raw": j
            }
        elif query_status == "ok":
            threat = j.get("threat", "malware_download")
            tags = j.get("tags", [])
            url_status = j.get("url_status", "")
            return {
                "source": "URLhaus (abuse.ch)",
                "risk_score": 100,
                "weight": 9,
                "verdict": "MALICIOUS",
                "confidence": 98,
                "details": f"FOUND in URLhaus! Threat: {threat} Tags: {tags} Status: {url_status} Reporter: {j.get('reporter','')} Date added: {j.get('date_added','')}",
                "description": f"⚠️ MALWARE DISTRIBUTION URL detected by URLhaus: {threat}",
                "raw": j
            }
        else:
            return {
                "source": "URLhaus (abuse.ch)",
                "risk_score": 30,
                "weight": 9,
                "verdict": "UNKNOWN",
                "confidence": 50,
                "details": f"URLhaus response query_status={query_status} - {j}",
                "description": f"URLhaus returned status {query_status} - unconfirmed.",
                "raw": j
            }
    except Exception as e:
        return {
            "source": "URLhaus (abuse.ch)",
            "risk_score": 50,
            "weight": 9,
            "verdict": "UNKNOWN",
            "confidence": 10,
            "details": f"URLhaus API error: {str(e)[:300]}",
            "description": "Could not query URLhaus malware database."
        }

# ---------- ALIEN VAULT OTX ----------
async def check_otx(domain: str, ip: Optional[str], client: httpx.AsyncClient) -> Optional[Dict[str, Any]]:
    api_key = get_api_key("OTX_API_KEY", "otx_key", "OTX_KEY", "ALIENVAULT_OTX_API_KEY", "ALIENVAULT_API_KEY")
    if not api_key:
        return {
            "source": "AlienVault OTX",
            "risk_score": 50,
            "weight": 6,
            "verdict": "UNKNOWN",
            "confidence": 0,
            "details": "OTX API key not configured.",
            "description": "OTX threat intel check skipped - key missing. OTX aggregates community pulses for phishing/malware."
        }
    headers = {"X-OTX-API-KEY": api_key}
    if not domain and not ip:
        return None
    try:
        # Try domain general
        url = f"https://otx.alienvault.com/api/v1/indicators/domain/{domain}/general"
        resp = await client.get(url, headers=headers, timeout=15)
        if resp.status_code == 404:
            # try IP if provided
            if ip:
                url_ip = f"https://otx.alienvault.com/api/v1/indicators/IPv4/{ip}/general"
                resp_ip = await client.get(url_ip, headers=headers, timeout=15)
                if resp_ip.status_code == 200:
                    data = resp_ip.json()
                    pulse_count = data.get("pulse_info", {}).get("count", 0)
                    pulses = data.get("pulse_info", {}).get("pulses", [])[:3]
                    # risk based on count
                    if pulse_count >= 10:
                        risk, verdict = 90, "MALICIOUS"
                    elif pulse_count >= 5:
                        risk, verdict = 80, "MALICIOUS"
                    elif pulse_count >= 1:
                        risk, verdict = 70, "SUSPICIOUS"
                    else:
                        risk, verdict = 10, "SAFE"
                    desc = f"OTX found {pulse_count} threat pulses for IP {ip}. {'High risk IP.' if pulse_count>0 else 'No pulses.'}"
                    details = f"Pulses: {pulse_count}. Details: {pulses}. Whois: {data.get('whois','')[:200]} Alexa: {data.get('alexa','')}"
                    return {
                        "source": "AlienVault OTX",
                        "risk_score": risk,
                        "weight": 6,
                        "verdict": verdict,
                        "confidence": 85 if pulse_count>0 else 70,
                        "details": details,
                        "description": desc,
                        "raw": {"pulse_count": pulse_count}
                    }
            # not found as domain nor ip
            return {
                "source": "AlienVault OTX",
                "risk_score": 10,
                "weight": 6,
                "verdict": "SAFE",
                "confidence": 75,
                "details": f"Domain {domain} not found in OTX pulses (no threat intel).",
                "description": "No OTX community threat pulses found - clean in OTX.",
                "raw": {}
            }

        resp.raise_for_status()
        data = resp.json()
        pulse_info = data.get("pulse_info", {})
        pulse_count = pulse_info.get("count", 0)
        pulses = pulse_info.get("pulses", [])
        # Extract tags and malware families
        tags = set()
        for p in pulses[:5]:
            for t in p.get("tags", [])[:5]:
                tags.add(t)
        tags_str = ", ".join(list(tags)[:8])

        if pulse_count >= 10:
            risk, verdict = 92, "MALICIOUS"
        elif pulse_count >= 5:
            risk, verdict = 82, "MALICIOUS"
        elif pulse_count >= 2:
            risk, verdict = 70, "SUSPICIOUS"
        elif pulse_count == 1:
            risk, verdict = 55, "SUSPICIOUS"
        else:
            risk, verdict = 8, "SAFE"

        desc = f"OTX pulses: {pulse_count}. {'High threat intel presence.' if pulse_count>=3 else 'No major threat pulses.' if pulse_count==0 else 'Some suspicious community reports.'} Tags: {tags_str}" if tags_str else f"OTX pulses: {pulse_count}"
        details = f"Domain: {domain} Pulse count: {pulse_count}. Pulses sample: {[p.get('name','') for p in pulses[:3]]} Alexa rank: {data.get('alexa','')} Whois excerpt: {str(data.get('whois',''))[:200]}"
        return {
            "source": "AlienVault OTX",
            "risk_score": risk,
            "weight": 6,
            "verdict": verdict,
            "confidence": 88 if pulse_count>0 else 75,
            "details": details,
            "description": desc,
            "raw": {"pulse_count": pulse_count, "tags": tags_str}
        }

    except Exception as e:
        return {
            "source": "AlienVault OTX",
            "risk_score": 50,
            "weight": 6,
            "verdict": "UNKNOWN",
            "confidence": 10,
            "details": f"OTX API error: {str(e)[:300]}",
            "description": "Could not query OTX threat intel."
        }

# ---------- PULSEDIVE ----------
async def check_pulsedive(domain: str, url: str, ip: Optional[str], client: httpx.AsyncClient) -> Optional[Dict[str, Any]]:
    api_key = get_api_key("PULSEDIVE_API_KEY", "pulsdive", "PULSEDIVE_KEY")
    if not api_key:
        return {
            "source": "Pulsedive",
            "risk_score": 50,
            "weight": 5,
            "verdict": "UNKNOWN",
            "confidence": 0,
            "details": "Pulsedive API key not configured.",
            "description": "Pulsedive enrichment skipped - key missing."
        }
    if not (domain or url or ip):
        return None
    try:
        # Try info.php endpoint with indicator
        indicator = domain or url or ip
        # pulsive expects key param, indicator param
        # docs: https://pulsedive.com/api/?q=info.php+indicator
        resp = await client.get("https://pulsedive.com/api/info.php",
                            params={"indicator": indicator, "key": api_key, "pretty": 1},
                            timeout=15)
        if resp.status_code == 200:
            try:
                data = resp.json()
                # data may contain results array
                if isinstance(data, dict) and data.get("results"):
                    results = data["results"]
                    # results is list
                    if results:
                        first = results[0] if isinstance(results, list) else results
                        risk_level = first.get("risk", "unknown")
                        # risk mapping low, medium, high, critical
                        risk_map = {
                            "none": 5,
                            "low": 20,
                            "medium": 55,
                            "high": 85,
                            "critical": 100,
                            "unknown": 50
                        }
                        mapped_risk = risk_map.get(risk_level.lower(), 50) if isinstance(risk_level, str) else 50
                        verdict = "MALICIOUS" if mapped_risk >= 80 else ("SUSPICIOUS" if mapped_risk>=50 else "SAFE" if mapped_risk<20 else "LOW_RISK")
                        details = f"Indicator {indicator} Risk: {risk_level} Threats: {first.get('threats',[])} Feeds: {[f.get('name','') for f in first.get('feed',[])][:3]}"
                        return {
                            "source": "Pulsedive",
                            "risk_score": mapped_risk,
                            "weight": 5,
                            "verdict": verdict,
                            "confidence": 80,
                            "details": details,
                            "description": f"Pulsedive risk level {risk_level} for {indicator}",
                            "raw": first
                        }
                # if indicator not found, data may have error or empty
                # try explore.php as fallback
            except Exception:
                pass

        # Fallback explore
        resp2 = await client.get("https://pulsedive.com/api/explore.php",
                             params={"q": f"indicator={indicator}", "key": api_key, "limit": 10},
                             timeout=15)
        if resp2.status_code == 200:
            try:
                data2 = resp2.json()
                results = data2.get("results", [])
                if not results:
                    return {
                        "source": "Pulsedive",
                        "risk_score": 10,
                        "weight": 5,
                        "verdict": "SAFE",
                        "confidence": 70,
                        "details": f"No Pulsedive results for indicator {indicator}.",
                        "description": "Clean - no risk indicators in Pulsedive.",
                        "raw": data2
                    }
                # analyze first
                first = results[0]
                risk_level = first.get("risk", "unknown")
                risk_map = {"none":5, "low":20, "medium":55, "high":85, "critical":100, "unknown":50}
                mapped_risk = risk_map.get(str(risk_level).lower(), 50)
                verdict = "MALICIOUS" if mapped_risk>=80 else ("SUSPICIOUS" if mapped_risk>=50 else "SAFE")
                return {
                    "source": "Pulsedive",
                    "risk_score": mapped_risk,
                    "weight": 5,
                    "verdict": verdict,
                    "confidence": 75,
                    "details": f"Explore results {len(results)} items. First risk {risk_level} Indicator {indicator}",
                    "description": f"Pulsedive reports risk {risk_level} for {indicator}",
                    "raw": first
                }
            except Exception as e:
                pass

        return {
            "source": "Pulsedive",
            "risk_score": 15,
            "weight": 5,
            "verdict": "SAFE",
            "confidence": 60,
            "details": f"No Pulsedive threat data found for {indicator}",
            "description": "No Pulsedive threat intel found - considered clean.",
            "raw": {}
        }

    except Exception as e:
        return {
            "source": "Pulsedive",
            "risk_score": 50,
            "weight": 5,
            "verdict": "UNKNOWN",
            "confidence": 10,
            "details": f"Pulsedive API error: {str(e)[:300]}",
            "description": "Could not query Pulsedive."
        }

# ---------- ABUSEIPDB ----------
async def check_abuseipdb(ip: Optional[str], client: httpx.AsyncClient) -> Optional[Dict[str, Any]]:
    if not ip:
        return {
            "source": "AbuseIPDB",
            "risk_score": 50,
            "weight": 7,
            "verdict": "UNKNOWN",
            "confidence": 0,
            "details": "No IP resolved for AbuseIPDB check.",
            "description": "AbuseIPDB skipped - could not resolve domain IP."
        }
    api_key = get_api_key("ABUSEIPDB_API_KEY", "abuseipdb", "ABUSEIPDB_KEY")
    if not api_key:
        return {
            "source": "AbuseIPDB",
            "risk_score": 50,
            "weight": 7,
            "verdict": "UNKNOWN",
            "confidence": 0,
            "details": "AbuseIPDB API key not configured.",
            "description": "AbuseIPDB check skipped - key missing. Provides abuse confidence score 0-100."
        }
    try:
        headers = {"Key": api_key, "Accept": "application/json"}
        params = {"ipAddress": ip, "maxAgeInDays": 90, "verbose": ""}
        resp = await client.get("https://api.abuseipdb.com/api/v2/check", headers=headers, params=params, timeout=15)
        resp.raise_for_status()
        data = resp.json()
        inner = data.get("data", {})
        score = inner.get("abuseConfidenceScore", 0)  # 0-100
        total_reports = inner.get("totalReports", 0)
        last_reported = inner.get("lastReportedAt", "N/A")
        # abuseConfidenceScore directly usable as risk
        risk = int(score)
        if risk >= 75:
            verdict = "MALICIOUS"
        elif risk >= 40:
            verdict = "SUSPICIOUS"
        elif risk >= 1:
            verdict = "LOW_RISK"
        else:
            verdict = "SAFE"
        details = f"IP {ip} Abuse confidence {score}/100, Total reports {total_reports}, Last reported {last_reported}, ISP {inner.get('isp','')} Country {inner.get('countryCode','')}"
        description = f"AbuseIPDB reports {score}% abuse confidence for IP {ip} ({total_reports} reports)."
        return {
            "source": "AbuseIPDB",
            "risk_score": risk,
            "weight": 7,
            "verdict": verdict,
            "confidence": 90,
            "details": details,
            "description": description,
            "raw": inner
        }
    except Exception as e:
        return {
            "source": "AbuseIPDB",
            "risk_score": 50,
            "weight": 7,
            "verdict": "UNKNOWN",
            "confidence": 10,
            "details": f"AbuseIPDB API error: {str(e)[:300]}",
            "description": "Could not query AbuseIPDB."
        }

# ---------- SPAMHAUS ----------
async def check_spamhaus(domain: str, ip: Optional[str]) -> Optional[Dict[str, Any]]:
    api_key = get_api_key("SPAMHAUS_API_KEY", "spamhaus", "SPAMHAUS_DQS_KEY", "SPAMHAUS_KEY")
    # Spamhaus works via DNSBL even without key for low volume; if key exists use DQS zone
    # We'll implement DNSBL zen.spamhaus.org for IP and dbl.spamhaus.org for domain
    try:
        # Resolve IP if not provided
        if not ip:
            ip = _get_ip(domain)
        if not (ip or domain):
            return None
        results = []

        # IP check: zen.spamhaus.org
        if ip:
            reversed_ip = '.'.join(reversed(ip.split('.')))
            zen_query = f"{reversed_ip}.zen.spamhaus.org"
            try:
                await asyncio.to_thread(dns.resolver.resolve, zen_query, 'A', lifetime=5)
                results.append(f"IP {ip} listed in zen.spamhaus.org")
            except dns.resolver.NXDOMAIN:
                pass
            except Exception as e:
                # maybe timeout
                pass

        # Domain check: dbl.spamhaus.org or via public if allowed
        # Actually dbl: query domain.dbl.spamhaus.org
        domain_query = f"{domain}.dbl.spamhaus.org"
        try:
            await asyncio.to_thread(dns.resolver.resolve, domain_query, 'A', lifetime=5)
            results.append(f"Domain {domain} listed in dbl.spamhaus.org")
        except dns.resolver.NXDOMAIN:
            pass
        except Exception:
            pass

        if results:
            return {
                "source": "Spamhaus",
                "risk_score": 85,
                "weight": 6,
                "verdict": "MALICIOUS",
                "confidence": 90,
                "details": f"Spamhaus blocklist hit: {'; '.join(results)}",
                "description": f"Domain/IP flagged by Spamhaus anti-spam/phishing blocklists."
            }
        else:
            return {
                "source": "Spamhaus",
                "risk_score": 5,
                "weight": 6,
                "verdict": "SAFE",
                "confidence": 80,
                "details": f"No Spamhaus listings for domain {domain} IP {ip or 'N/A'}. Checked zen and dbl.",
                "description": "Not blacklisted by Spamhaus DNSBLs."
            }
    except Exception as e:
        return {
            "source": "Spamhaus",
            "risk_score": 50,
            "weight": 6,
            "verdict": "UNKNOWN",
            "confidence": 10,
            "details": f"Spamhaus DNSBL check error: {str(e)[:300]}",
            "description": "Could not perform Spamhaus DNSBL check."
        }

# ---------- OPENPHISH ----------
async def check_openphish(url: str, domain: str, client: httpx.AsyncClient) -> Dict[str, Any]:
    try:
        resp = await client.get("https://openphish.com/feed.txt", timeout=8)
        resp.raise_for_status()
        text = resp.text
        feed_urls = [line.strip() for line in text.splitlines() if line.strip()]
        feed_domains = {_clean_domain(feed_url) for feed_url in feed_urls}
        exact_url_match = url.rstrip("/") in {feed_url.rstrip("/") for feed_url in feed_urls}
        domain_match = domain in feed_domains
        if exact_url_match or domain_match:
            return {
                "source": "OpenPhish",
                "risk_score": 100,
                "weight": 7,
                "verdict": "MALICIOUS",
                "confidence": 95,
                "details": f"{'URL' if exact_url_match else 'Domain'} found in OpenPhish community feed (verified phishing).",
                "description": "Listed as phishing in OpenPhish feed (free 12h updates)."
            }
        else:
            return {
                "source": "OpenPhish",
                "risk_score": 5,
                "weight": 7,
                "verdict": "SAFE",
                "confidence": 75,
                "details": f"Domain {domain} not in OpenPhish feed ({len(feed_urls)} URLs checked). OpenPhish does not require an API key for this feed.",
                "description": "Not listed in OpenPhish phishing database."
            }
    except Exception as e:
        return {
            "source": "OpenPhish",
            "risk_score": 50,
            "weight": 7,
            "verdict": "UNKNOWN",
            "confidence": 10,
            "details": f"OpenPhish public feed check failed: {str(e)[:200]}",
            "description": "Could not check the public OpenPhish feed; this source does not use a backend API key."
        }

# ---------- CRT.SH ----------
async def check_crtsh(domain: str, client: httpx.AsyncClient) -> Dict[str, Any]:
    try:
        query_domain = quote(domain, safe="")
        resp = await client.get(f"https://crt.sh/?q={query_domain}&output=json", timeout=12)
        if resp.status_code != 200:
            return {
                "source": "crt.sh (CT Logs)",
                "risk_score": 50,
                "weight": 3,
                "verdict": "UNKNOWN",
                "confidence": 20,
                "details": f"crt.sh returned status {resp.status_code}",
                "description": "Could not fetch Certificate Transparency logs."
            }
        data = resp.json()
        # data may be large list
        if not isinstance(data, list):
            return {
                "source": "crt.sh (CT Logs)",
                "risk_score": 50,
                "weight": 3,
                "verdict": "UNKNOWN",
                "confidence": 20,
                "details": "crt.sh response not list",
                "description": "Unexpected CT log response."
            }
        count = len(data)
        # Analyze issuance frequency: many certs in short time may indicate lookalikes? Or just CDN.
        # For phishing detection, brand new domain with 1 cert <30 days maybe suspicious
        # Count distinct issuers
        issuers = set()
        for entry in data[:100]:
            issuers.add(entry.get("issuer_name",""))
        details = f"Certificate Transparency: {count} certs found for {domain}. Recent issuers: {list(issuers)[:5]}"
        if count == 0:
            risk = 40  # no cert history could be new
            verdict = "SUSPICIOUS"
            desc = f"No CT logs for {domain} - newly observed or no TLS ever."
        elif count <= 2:
            risk = 25
            verdict = "LOW_RISK"
            desc = f"Only {count} certificates in CT logs - relatively new domain TLS history."
        else:
            risk = 10
            verdict = "SAFE"
            desc = f"{count} certs in CT logs - established TLS history."

        return {
            "source": "crt.sh (CT Logs)",
            "risk_score": risk,
            "weight": 3,
            "verdict": verdict,
            "confidence": 65,
            "details": details,
            "description": desc,
            "raw": {"count": count}
        }
    except Exception as e:
        return {
            "source": "crt.sh (CT Logs)",
            "risk_score": 50,
            "weight": 3,
            "verdict": "UNKNOWN",
            "confidence": 10,
            "details": f"crt.sh error: {str(e)[:250]}",
            "description": "Could not check CT logs."
        }

# ---------- AGGREGATOR ----------
async def run_all_reputation_checks(url: str) -> dict:
    """
    Runs all reputation checks and returns dict with:
      checks: list[dict]
      ip: str
      domain: str
    """
    domain = _clean_domain(url) if url else ""
    ip = await asyncio.to_thread(_get_ip, domain) if domain else None

    async with httpx.AsyncClient(follow_redirects=True) as client:
        tasks: List[Coroutine] = [
            check_google_safe_browsing(url, client),
            check_virustotal(url, client),
            check_urlhaus(url, client),
            check_openphish(url, domain, client),
            check_abuseipdb(ip, client),
            check_spamhaus(domain, ip),
            check_otx(domain, ip, client),
            check_pulsedive(domain, url, ip, client),
            check_urlscan(url, domain, client),
            check_crtsh(domain, client),
        ]

        results = await asyncio.gather(*tasks, return_exceptions=True)

    # Filter out exceptions and None results
    checks = [res for res in results if res and not isinstance(res, Exception)]

    return {"checks": checks, "ip": ip, "domain": domain}
