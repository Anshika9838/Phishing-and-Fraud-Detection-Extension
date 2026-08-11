"""
Infrastructure analyzer: SSL details, WHOIS, domain age/expiry/registrar, and heuristic content analysis
"""
import socket
import asyncio
import ssl
from datetime import datetime, timezone
import re
import os
from urllib.parse import urlparse
from typing import Dict, Any, Optional, List, Coroutine
import whois
import httpx

SUSPICIOUS_TLDS = {".tk", ".ml", ".ga", ".cf", ".gq", ".xyz", ".top", ".buzz", ".work", ".click", ".country", ".stream", ".download", ".xin", ".gdn", ".mom", ".party", ".loan"}
BRAND_KEYWORDS = ["paypal", "google", "microsoft", "apple", "amazon", "netflix", "bank", "facebook", "instagram", "whatsapp", "binance", "coinbase", "metamask", "office365", "outlook", "linkedin", "adobe"]

def _get_domain(url: str) -> str:
    try:
        parsed = urlparse(url if "://" in url else f"https://{url}")
        return (parsed.hostname or "").lower()
    except:
        return ""

async def get_ssl_details(hostname: str) -> Dict[str, Any]:
    """
    Direct TLS cert fetch
    """
    if not hostname:
        return {
            "source": "SSL/TLS Certificate",
            "risk_score": 50,
            "weight": 6,
            "verdict": "UNKNOWN",
            "confidence": 0,
            "details": "No hostname for SSL check",
            "description": "Could not perform SSL check - no hostname.",
            "extra": {}
        }
    try:
        context = ssl.create_default_context()
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(hostname, 443, ssl=context, server_hostname=hostname),
            timeout=7
        )
        ssock = writer.get_extra_info('ssl_object')
        cert = ssock.getpeercert()
        cipher = ssock.cipher()
        writer.close()
        await writer.wait_closed()

        not_before_str = cert.get("notBefore", "")
        not_after_str = cert.get("notAfter", "")

        def parse_ssl_date(s):
            try:
                return datetime.strptime(s, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)
            except:
                return None

        not_before = parse_ssl_date(not_before_str)
        not_after = parse_ssl_date(not_after_str)
        now = datetime.now(timezone.utc)
        days_until_expiry = (not_after - now).days if not_after else None
        cert_age_days = (now - not_before).days if not_before else None

        subject = cert.get("subject", ())
        issuer = cert.get("issuer", ())

        def flatten_name(tup):
            return {k: v for items in tup for k, v in items}

        subject_dict = flatten_name(subject)
        issuer_dict = flatten_name(issuer)
        sans = [tup[1] for tup in cert.get("subjectAltName", []) if len(tup) == 2]
        is_self_signed = cert.get("issuer") == cert.get("subject")

        if not_after and not_after < now:
            risk, verdict, desc = 100, "MALICIOUS", f"SSL certificate EXPIRED on {not_after_str}."
        elif is_self_signed:
            risk, verdict, desc = 90, "MALICIOUS", "Self-signed SSL certificate - not trusted."
        elif days_until_expiry is not None and days_until_expiry < 3:
            risk, verdict, desc = 75, "SUSPICIOUS", f"SSL expires in {days_until_expiry} days."
        elif days_until_expiry is not None and days_until_expiry < 30:
            risk, verdict, desc = 40, "LOW_RISK", f"SSL expires soon in {days_until_expiry} days."
        else:
            risk, verdict, desc = 5, "SAFE", f"SSL certificate valid, expires in {days_until_expiry} days."

        cn = subject_dict.get("commonName", "")
        if hostname not in sans and hostname != cn and not any(hostname.endswith(f".{s.lstrip('*.')}") for s in sans if s.startswith('*.')):
            risk = max(risk, 60)
            verdict = "SUSPICIOUS" if risk < 90 else verdict
            desc += f" Certificate CN/SAN mismatch: CN={cn} SANs={sans[:3]}"

        details = f"Issuer: {issuer_dict.get('organizationName', 'N/A')}, Expires in: {days_until_expiry} days, Self-signed: {is_self_signed}"

        return {
            "source": "SSL/TLS Certificate",
            "risk_score": risk,
            "weight": 6,
            "verdict": verdict,
            "confidence": 95 if not is_self_signed else 90,
            "details": details,
            "description": desc,
            "extra": {
                "issuer": issuer_dict, "subject": subject_dict, "not_after": not_after_str,
                "days_until_expiry": days_until_expiry, "cert_age_days": cert_age_days,
                "sans": sans, "is_self_signed": is_self_signed, "cipher": cipher
            }
        }
    except (asyncio.TimeoutError, ssl.SSLError, ConnectionRefusedError, socket.gaierror, OSError) as e:
        return {
            "source": "SSL/TLS Certificate",
            "risk_score": 85,
            "weight": 6,
            "verdict": "SUSPICIOUS",
            "confidence": 80,
            "details": f"SSL error connecting to {hostname}:443 - {str(e)[:400]}. Could be invalid cert, self-signed, or non-SSL.",
            "description": f"SSL handshake failed for {hostname} - possible self-signed or fake certificate.",
            "extra": {"error": str(e)[:500]}
        }

async def get_whois_detailed(domain: str) -> Dict[str, Any]:
    """
    WHOIS with domain age, expiry, registrar, privacy detection
    """
    if not domain:
        return {
            "source": "WHOIS / Domain Registration",
            "risk_score": 50,
            "weight": 8,
            "verdict": "UNKNOWN",
            "confidence": 0,
            "details": "No domain for WHOIS",
            "description": "WHOIS check skipped.",
            "extra": {}
        }
    try:
        w = await asyncio.to_thread(whois.whois, domain)
        # creation_date can be list or datetime
        def normalize_date(d):
            if not d:
                return None
            if isinstance(d, list):
                # pick earliest
                # filter None
                valid = [x for x in d if x]
                if not valid:
                    return None
                # if list of datetimes, min
                try:
                    return min(valid)
                except:
                    return valid[0]
            return d

        creation = normalize_date(getattr(w, "creation_date", None))
        expiration = normalize_date(getattr(w, "expiration_date", None) or getattr(w, "expiry_date", None))
        updated = normalize_date(getattr(w, "updated_date", None))

        registrar = getattr(w, "registrar", None) or "Unknown"
        name_servers = getattr(w, "name_servers", []) or []
        status = getattr(w, "status", []) or []
        emails = getattr(w, "emails", []) or []

        # Ensure dates are aware? compare naive vs aware handling
        now = datetime.now()
        # If creation tzaware, convert now to aware etc - simplify naive
        def to_naive(dt):
            if dt is None:
                return None
            if getattr(dt, "tzinfo", None):
                return dt.replace(tzinfo=None)
            return dt

        creation_n = to_naive(creation)
        expiration_n = to_naive(expiration)
        now_n = now

        age_days = (now_n - creation_n).days if creation_n else None
        expiry_days = (expiration_n - now_n).days if expiration_n else None
        lifetime_days = (expiration_n - creation_n).days if creation_n and expiration_n else None

        # Privacy detection
        privacy_keywords = ["privacy", "proxy", "redacted", "withheld", "whoisguard", "anonym", "protected", "private", "domains by proxy"]
        text_blob = f"{str(registrar)} {str(w)}".lower()
        is_privacy = any(k in text_blob for k in privacy_keywords)

        # Registrar reputation? Not perfect, but free cheap registrars often used in phishing
        cheap_registrars = ["namecheap", "namesilo", "porkbun", "dynadot", "godaddy", "tucows", "name.com", "enom"]
        registrar_lower = str(registrar).lower()
        is_cheap_registrar = any(c in registrar_lower for c in cheap_registrars)

        # Risk calculation based on age
        if age_days is None:
            risk = 50
            verdict = "UNKNOWN"
            desc = f"Could not determine domain age for {domain}. WHOIS data incomplete."
        elif age_days < 7:
            risk = 90
            verdict = "MALICIOUS"
            desc = f"Domain {domain} is extremely new: only {age_days} days old (created {creation}). High risk for cloned/fake phishing."
        elif age_days < 30:
            risk = 80
            verdict = "SUSPICIOUS"
            desc = f"Domain {domain} is very new: {age_days} days old. Common in fraud clones."
        elif age_days < 90:
            risk = 55
            verdict = "SUSPICIOUS"
            desc = f"Domain {domain} age {age_days} days - relatively young."
        elif age_days < 180:
            risk = 30
            verdict = "LOW_RISK"
            desc = f"Domain {domain} age {age_days} days - moderately established."
        elif age_days < 365:
            risk = 15
            verdict = "SAFE"
            desc = f"Domain {domain} age {age_days} days - established less than a year."
        else:
            risk = 5
            verdict = "SAFE"
            desc = f"Domain {domain} is well-established: {age_days} days old ({age_days//365} years)."

        # Adjust risk for privacy + young
        if is_privacy and age_days is not None and age_days < 90:
            risk = min(100, risk + 15)
            desc += " WHOIS privacy protection enabled combined with young age increases impersonation risk."
        elif is_privacy and age_days and age_days > 365:
            # privacy on old domain normal, reduce impact
            desc += " WHOIS privacy enabled (common)."

        if lifetime_days is not None and lifetime_days < 365:
            # registered for only 1 year, throwaway pattern
            risk = min(100, risk + 10)
            desc += f" Short registration period ({lifetime_days} days total) suggests throwaway domain."

        if expiry_days is not None and expiry_days < 0:
            risk = 100
            verdict = "MALICIOUS"
            desc += f" Domain EXPIRED {abs(expiry_days)} days ago!"

        details = (f"Registrar: {registrar} Age: {age_days} days Created: {creation} Expires: {expiration} Updated: {updated} "
                   f"Expiry in: {expiry_days} days Lifetime: {lifetime_days} days Privacy: {is_privacy} NS: {name_servers[:3]} Status: {status[:4]} Emails: {str(emails)[:200]}")

        return {
            "source": "WHOIS / Domain Registration",
            "risk_score": risk,
            "weight": 8,
            "verdict": verdict,
            "confidence": 85 if age_days is not None else 40,
            "details": details,
            "description": desc,
            "extra": {
                "creation_date": str(creation),
                "expiration_date": str(expiration),
                "updated_date": str(updated),
                "age_days": age_days,
                "expiry_days": expiry_days,
                "lifetime_days": lifetime_days,
                "registrar": str(registrar),
                "name_servers": name_servers[:5],
                "privacy": is_privacy,
                "status": status[:10]
            }
        }
    except Exception as e:
        return {
            "source": "WHOIS / Domain Registration",
            "risk_score": 50,
            "weight": 8,
            "verdict": "UNKNOWN",
            "confidence": 15,
            "details": f"WHOIS lookup failed for {domain}: {str(e)[:400]}. Some TLDs block WHOIS.",
            "description": "Could not retrieve WHOIS registration details.",
            "extra": {"error": str(e)[:500]}
        }

def heuristic_url_analysis(url: str, domain: str, page_data: dict = None) -> Dict[str, Any]:
    """
    Deep heuristic + content analysis
    """
    try:
        parsed = urlparse(url if "://" in url else f"https://{url}")
        hostname = (parsed.hostname or domain or "").lower()
        path = parsed.path or ""
        query = parsed.query or ""
        full = url.lower()

        risks = []
        score = 0

        # URL based heuristics
        if parsed.scheme == "http":
            risks.append("Uses HTTP not HTTPS")
            score += 15
        if "@" in url:
            risks.append("Contains @ symbol (possible credential phishing trick)")
            score += 30
        if hostname and hostname.replace(".", "").isdigit() or re.match(r"^\d+\.\d+\.\d+\.\d+$", hostname):
            risks.append("Uses IP address instead of domain - high phishing indicator")
            score += 40
        if "xn--" in hostname:
            risks.append("Punycode domain (IDN homograph attack possible)")
            score += 35
        if len(hostname) > 30:
            risks.append(f"Unusually long domain ({len(hostname)} chars)")
            score += 10
        if full.count("-") >= 4:
            risks.append(f"Many hyphens in URL ({full.count('-')}) - typosquat technique")
            score += 15
        if full.count(".") >= 4:
            risks.append(f"Deep subdomain structure ({full.count('.')} dots)")
            score += 10
        # suspicious tld
        for tld in SUSPICIOUS_TLDS:
            if hostname.endswith(tld):
                risks.append(f"Suspicious TLD {tld} commonly abused in phishing")
                score += 20
        # digits
        digits = sum(c.isdigit() for c in hostname)
        if digits >= 5:
            risks.append(f"Many digits in domain ({digits}) - random generation")
            score += 15
        # hex-like
        if re.search(r"[a-f0-9]{8,}", hostname):
            risks.append("Looks like random hash in domain")
            score += 10

        # Brand impersonation detection: brand + unrelated domain?
        # e.g., paypal-something.tk trying to impersonate paypal but domain != paypal.com
        for brand in BRAND_KEYWORDS:
            if brand in full:
                # check if legitimate domain? e.g., paypal.com should have paypal in eTLD+1
                # If brand in url but domain not official brand domains -> suspicious typo-squatting
                legitimate_suffixes = [f"{brand}.com", f"{brand}.co", f"{brand}.net", f"{brand}.org", f"{brand}.in", f"{brand}.co.in"]
                if brand in hostname and not any(hostname == s or hostname.endswith(f".{s}") or hostname == brand or hostname.endswith(brand) and ".com" in hostname for s in legitimate_suffixes):
                    # more precise: if hostname contains brand but not exactly brand's official
                    # Example: paypal-login.com, secure-paypal.com, paypal.com.evil.com
                    if hostname != f"{brand}.com" and not hostname.endswith(f".{brand}.com"):
                        risks.append(f"Possible brand impersonation: '{brand}' in URL but domain is {hostname}")
                        score += 25

        # Content analysis if page_data provided
        page_text = ""
        forms = []
        resources = {}
        links = []
        iframes = []
        if page_data:
            page_text = str(page_data.get("cleanText","") or page_data.get("text","") or "")[:5000].lower()
            forms = page_data.get("forms", []) if isinstance(page_data.get("forms"), list) else []
            resources = page_data.get("resources", {}) if isinstance(page_data.get("resources"), dict) else {}
            links = page_data.get("links", []) if isinstance(page_data.get("links"), list) else []
            iframes = page_data.get("iframes", []) if isinstance(page_data.get("iframes"), list) else []

            # forms external
            external_forms = 0
            password_fields = 0
            credential_fields = 0
            for f in forms:
                if not isinstance(f, dict):
                    continue
                if f.get("isExternalAction"):
                    external_forms += 1
                inputs = f.get("inputs", []) if isinstance(f.get("inputs"), list) else []
                for inp in inputs:
                    if not isinstance(inp, dict):
                        continue
                    t = str(inp.get("type","")).lower()
                    name = f"{inp.get('name','')} {inp.get('id','')} {inp.get('placeholder','')}".lower()
                    if t == "password":
                        password_fields += 1
                    if any(k in name for k in ("password","pass","login","user","email","card","cvv","ssn","otp","pin","bank")):
                        credential_fields += 1

            if external_forms>0:
                risks.append(f"{external_forms} form(s) submit data to external domain (data exfiltration)")
                score += 35
            if password_fields>0:
                risks.append(f"Contains {password_fields} password input field(s) - credential harvesting risk")
                score += 25
            if credential_fields >= 3:
                risks.append(f"Many credential-like fields ({credential_fields}) - possible fake login")
                score += 20

            # iframes external
            external_iframes = 0
            if iframes:
                for iframe in iframes:
                    try:
                        h = urlparse(iframe).hostname or ""
                        if h and h != hostname:
                            external_iframes += 1
                    except:
                        pass
            if external_iframes>0:
                risks.append(f"{external_iframes} external iframe(s) embed")
                score += 15

            # resource domains
            all_resources = []
            for key in ("images","scripts","styles"):
                vals = resources.get(key, [])
                if isinstance(vals, list):
                    all_resources.extend(vals)
            external_resources = 0
            for r in all_resources:
                try:
                    h = urlparse(r).hostname or ""
                    if h and h != hostname:
                        external_resources += 1
                except:
                    pass
            if external_resources >= 5 and len(all_resources)>0 and external_resources / max(1,len(all_resources)) > 0.6:
                risks.append(f"High external resource ratio ({external_resources}/{len(all_resources)}) - possible cloned site hotlinking victim")
                score += 10

            # urgency / social engineering keywords in text
            urgency_words = ["urgent","immediately","suspended","locked","verify","action required","limited time","act now","security alert","unusual activity","confirm identity"]
            found_urgency = [w for w in urgency_words if w in page_text]
            if found_urgency:
                risks.append(f"Urgency/social engineering phrases: {', '.join(found_urgency[:4])}")
                score += len(found_urgency)*4

            # Check credential harvesting vs domain mismatch: title containing brand but domain not brand
            title = str(page_data.get("title","")).lower()
            for brand in BRAND_KEYWORDS:
                if brand in title and brand not in hostname:
                    risks.append(f"Title mentions '{brand}' but domain is {hostname} - potential spoofed/cloned login")
                    score += 30
                    break

        # final risk cap
        risk_score = min(100, score)

        if risk_score >= 80:
            verdict = "MALICIOUS"
            desc = f"High-risk URL/content heuristics: {'; '.join(risks[:4])}"
        elif risk_score >= 50:
            verdict = "SUSPICIOUS"
            desc = f"Suspicious patterns: {'; '.join(risks[:4])}"
        elif risk_score >= 25:
            verdict = "LOW_RISK"
            desc = f"Some caution signals: {'; '.join(risks[:3])}."
        else:
            verdict = "SAFE"
            desc = "No strong heuristic phishing signals in URL structure and content."

        details = f"URL: {url} Domain: {hostname} Path length: {len(path)} Query length: {len(query)} Risks: {risks} Score raw {score}"

        return {
            "source": "Heuristic & Content Analysis",
            "risk_score": risk_score,
            "weight": 5,
            "verdict": verdict,
            "confidence": 80,
            "details": details,
            "description": desc,
            "extra": {"risks": risks, "password_fields": password_fields if 'password_fields' in locals() else 0, "external_forms": external_forms if 'external_forms' in locals() else 0}
        }
    except Exception as e:
        return {
            "source": "Heuristic & Content Analysis",
            "risk_score": 50,
            "weight": 5,
            "verdict": "UNKNOWN",
            "confidence": 10,
            "details": f"Heuristic analysis error: {str(e)[:300]}",
            "description": "Could not perform heuristic analysis."
        }

async def get_qualys_ssl_grade(domain: str, client: httpx.AsyncClient) -> Dict[str, Any]:
    """
    Optional: Qualys SSL Labs cached grade
    """
    try:
        resp = await client.get("https://api.ssllabs.com/api/v3/analyze", params={"host": domain, "fromCache": "on", "maxAge": 24}, timeout=12)
        if resp.status_code != 200:
            return {
                "source": "Qualys SSL Labs",
                "risk_score": 50,
                "weight": 2,
                "verdict": "UNKNOWN",
                "confidence": 15,
                "details": f"Qualys returned status {resp.status_code}",
                "description": "Qualys SSL Labs grade unavailable."
            }
        data = resp.json()
        status = data.get("status")
        if status == "READY" and data.get("endpoints"):
            grade = data["endpoints"][0].get("grade","")
            # grade A+ -> low risk, B -> medium, C/D/E/F -> high
            grade_risk_map = {"A+":5, "A":10, "A-":15, "B":30, "C":55, "D":70, "E":85, "F":95, "T":90, "M":90}
            risk = grade_risk_map.get(grade, 50)
            verdict = "SAFE" if risk<25 else ("LOW_RISK" if risk<45 else "SUSPICIOUS" if risk<75 else "MALICIOUS")
            return {
                "source": "Qualys SSL Labs",
                "risk_score": risk,
                "weight": 2,
                "verdict": verdict,
                "confidence": 85,
                "details": f"Qualys grade {grade} for {domain} status {status}",
                "description": f"SSL Labs grade {grade} - {'excellent' if risk<15 else 'good' if risk<35 else 'weak' if risk<70 else 'poor/failing'} TLS configuration.",
                "extra": {"grade": grade}
            }
        else:
            return {
                "source": "Qualys SSL Labs",
                "risk_score": 30,
                "weight": 2,
                "verdict": "UNKNOWN",
                "confidence": 30,
                "details": f"Qualys status {status} - no cached grade",
                "description": f"Qualys scan {status} - no recent cached report."
            }
    except Exception as e:
        return {
            "source": "Qualys SSL Labs",
            "risk_score": 50,
            "weight": 2,
            "verdict": "UNKNOWN",
            "confidence": 10,
            "details": f"Qualys error: {str(e)[:250]}",
            "description": "Could not fetch Qualys SSL grade."
        }

async def run_infra_checks(url: str, page_data: dict = None) -> dict:
    domain = _get_domain(url)
    # Heuristic analysis is CPU-bound and fast, can run synchronously.
    heuristic_check = heuristic_url_analysis(url, domain, page_data)

    async with httpx.AsyncClient() as client:
        tasks: List[Coroutine] = [
            get_ssl_details(domain),
            get_whois_detailed(domain),
            get_qualys_ssl_grade(domain, client),
        ]
        results = await asyncio.gather(*tasks, return_exceptions=True)

    all_checks = [res for res in results if res and not isinstance(res, Exception)]
    all_checks.append(heuristic_check)

    return {"checks": all_checks, "domain": domain}
