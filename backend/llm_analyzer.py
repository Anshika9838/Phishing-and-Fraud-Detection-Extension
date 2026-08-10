import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional
from urllib.parse import urlparse

import requests

SAFE_BROWSING_NON_HITS = {"SAFE", "UNKNOWN", "API_ERROR", "MISSING_API_KEY", "INVALID_URL"}
RISK_KEYWORDS = [
    "password", "login", "verify", "verification", "urgent", "limited time",
    "suspended", "locked", "refund", "invoice", "bank", "wallet", "crypto",
    "otp", "one time password", "gift card", "prize", "winner", "claim",
    "account", "payment", "card", "ssn", "social security", "kyc",
]
CREDENTIAL_FIELD_TERMS = [
    "password", "pass", "otp", "pin", "card", "cvv", "ssn", "token",
    "secret", "wallet", "bank", "login", "email", "user",
]
DEFAULT_MODEL = "gemini-2.0-flash"

SYSTEM_PROMPT = """
You are Theft Alert, a careful phishing and fraud detection analyst for a browser extension.
Assess the page from browser telemetry only. Be concise, evidence-led, and conservative.
Do not claim a site is malicious unless the evidence supports it. Return strict JSON only.
Risk score scale: 0 is safe, 100 is severe phishing, fraud, malware, or credential theft risk.
""".strip()

RESPONSE_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "risk_score": {"type": "INTEGER"},
        "threat_type": {
            "type": "STRING",
            "enum": ["SAFE", "LOW_RISK", "SUSPICIOUS", "PHISHING", "FRAUD", "MALWARE", "UNKNOWN"],
        },
        "brief_reason": {"type": "STRING"},
        "description": {"type": "STRING"},
        "recommendation": {"type": "STRING"},
        "evidence": {"type": "ARRAY", "items": {"type": "STRING"}},
    },
    "required": ["risk_score", "threat_type", "brief_reason", "description", "recommendation", "evidence"],
}


def latest_scan_report_from_log(path: Path) -> Optional[Dict[str, Any]]:
    """Return the last JSON object stored in scan_reports.log."""
    if not path.exists():
        return None

    text = path.read_text(encoding="utf-8", errors="replace")
    if not text.strip():
        return None

    decoder = json.JSONDecoder()
    latest: Optional[Dict[str, Any]] = None
    index = 0

    while index < len(text):
        start = text.find("{", index)
        if start == -1:
            break
        try:
            value, end = decoder.raw_decode(text[start:])
        except json.JSONDecodeError:
            index = start + 1
            continue

        if isinstance(value, dict):
            latest = value
        index = start + max(end, 1)

    return latest


def analyze_scan_report(
    scan_report: Dict[str, Any],
    safe_browsing_result: Optional[Dict[str, Any]] = None,
    use_gemini: bool = True,
) -> Dict[str, Any]:
    scan_report = scan_report or {}
    safe_browsing_result = safe_browsing_result or {
        "score": 0.5,
        "threat_type": "UNKNOWN",
        "description": "Google Safe Browsing result was not available.",
    }

    if use_gemini and os.getenv("GEMINI_API_KEY"):
        try:
            raw_result = _call_gemini(scan_report, safe_browsing_result)
            return _normalize_result(raw_result, scan_report, safe_browsing_result, "gemini")
        except Exception as exc:
            fallback = _heuristic_result(scan_report, safe_browsing_result, "heuristic_fallback")
            fallback["evidence"] = [f"Gemini unavailable: {_compact_text(str(exc), 140)}"] + fallback["evidence"]
            fallback["description"] = (
                fallback["description"]
                + " Gemini could not complete the LLM review, so this score uses local browser signals and Safe Browsing."
            )
            return fallback

    source = "heuristic_no_gemini_key" if use_gemini else "heuristic"
    return _heuristic_result(scan_report, safe_browsing_result, source)


def _call_gemini(scan_report: Dict[str, Any], safe_browsing_result: Dict[str, Any]) -> Dict[str, Any]:
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY is not configured")

    model = os.getenv("GEMINI_MODEL", DEFAULT_MODEL).strip() or DEFAULT_MODEL
    api_url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
    prompt = _build_gemini_prompt(scan_report, safe_browsing_result)
    payload = {
        "systemInstruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": 0.1,
            "maxOutputTokens": 700,
            "responseMimeType": "application/json",
            "responseSchema": RESPONSE_SCHEMA,
        },
    }

    response = requests.post(api_url, json=payload, timeout=30)
    if not response.ok:
        raise RuntimeError(f"Gemini API returned HTTP {response.status_code}: {_safe_error_message(response)}")

    data = response.json()
    text = _extract_candidate_text(data)
    return _parse_json_object(text)


def _build_gemini_prompt(scan_report: Dict[str, Any], safe_browsing_result: Dict[str, Any]) -> str:
    summary = _build_scan_summary(scan_report)
    return (
        "Analyze this Chromium extension scan report for phishing and fraud risk. "
        "Use the Google Safe Browsing result and reputation checks as evidence, but also inspect forms, text, links, iframes, "
        "resource domains, and network activity. Return only JSON with risk_score, threat_type, brief_reason, "
        "description, recommendation, and evidence. brief_reason must be one short sentence under 160 characters.\n\n"
        f"Google Safe Browsing result:\n{json.dumps(safe_browsing_result, ensure_ascii=False)}\n\n"
        f"Scan report summary:\n{json.dumps(summary, ensure_ascii=False)}"
    )


def _build_scan_summary(scan_report: Dict[str, Any]) -> Dict[str, Any]:
    url = str(scan_report.get("url") or "")
    domain = str(scan_report.get("domain") or _hostname(url) or "")
    links = _unique_strings(scan_report.get("links"))
    iframes = _unique_strings(scan_report.get("iframes"))
    resources = scan_report.get("resources") if isinstance(scan_report.get("resources"), dict) else {}
    forms = scan_report.get("forms") if isinstance(scan_report.get("forms"), list) else []
    reputation_checks = scan_report.get("reputation_checks") if isinstance(scan_report.get("reputation_checks"), list) else []
    text = _compact_text(scan_report.get("cleanText", ""), 1800)

    image_sources = _unique_strings(resources.get("images"))
    script_sources = _unique_strings(resources.get("scripts"))
    style_sources = _unique_strings(resources.get("styles"))
    resource_urls = image_sources + script_sources + style_sources
    external_link_hosts = _external_hosts(links, domain)
    external_resource_hosts = _external_hosts(resource_urls, domain)
    external_iframe_hosts = _external_hosts(iframes, domain)

    form_summaries: List[Dict[str, Any]] = []
    password_input_count = 0
    credential_fields: List[str] = []
    external_form_count = 0

    for form in forms[:8]:
        if not isinstance(form, dict):
            continue
        inputs = form.get("inputs") if isinstance(form.get("inputs"), list) else []
        input_types = []
        field_names = []
        for field in inputs[:16]:
            if not isinstance(field, dict):
                continue
            field_type = str(field.get("type") or "").lower()
            field_name = " ".join(
                str(field.get(key) or "") for key in ("name", "id", "placeholder")
            ).strip()
            input_types.append(field_type or "text")
            if field_name:
                field_names.append(_compact_text(field_name, 80))
            if field_type == "password":
                password_input_count += 1
            lowered = f"{field_type} {field_name}".lower()
            if any(term in lowered for term in CREDENTIAL_FIELD_TERMS):
                credential_fields.append(_compact_text(field_name or field_type, 80))

        action = str(form.get("action") or "")
        action_host = _hostname(action)
        is_external = bool(form.get("isExternalAction")) or bool(action_host and action_host != domain)
        if is_external:
            external_form_count += 1

        form_summaries.append(
            {
                "action_host": action_host,
                "is_external_action": is_external,
                "method": str(form.get("method") or "").upper(),
                "input_types": input_types[:10],
                "credential_like_fields": field_names[:8],
            }
        )

    searchable = f"{url} {domain} {text}".lower()
    suspicious_terms = sorted({term for term in RISK_KEYWORDS if term in searchable})
    reputation_summary: List[Dict[str, Any]] = []
    for result in reputation_checks[:8]:
        if not isinstance(result, dict):
            continue
        reputation_summary.append(
            {
                "source": _compact_text(result.get("source", "Unknown"), 80),
                "score": result.get("score"),
                "threat_type": result.get("threat_type"),
                "details": _compact_text(result.get("details", ""), 220),
            }
        )

    return {
        "report_type": scan_report.get("reportType", "full_page_scan"),
        "scan_trigger": scan_report.get("scanTrigger"),
        "url": url,
        "domain": domain,
        "title": _compact_text(scan_report.get("title", ""), 160),
        "is_top_frame": scan_report.get("isTopFrame"),
        "text_sample": text,
        "suspicious_terms": suspicious_terms[:12],
        "counts": {
            "links": len(links),
            "external_link_hosts": len(external_link_hosts),
            "forms": len(forms),
            "external_forms": external_form_count,
            "password_inputs": password_input_count,
            "credential_like_fields": len(set(credential_fields)),
            "iframes": len(iframes),
            "external_iframe_hosts": len(external_iframe_hosts),
            "images": len(image_sources),
            "scripts": len(script_sources),
            "styles": len(style_sources),
        },
        "external_link_hosts_sample": external_link_hosts[:12],
        "external_resource_hosts_sample": external_resource_hosts[:12],
        "external_iframe_hosts_sample": external_iframe_hosts[:8],
        "forms_sample": form_summaries,
        "reputation_checks": reputation_summary,
        "network_request": _network_summary(scan_report),
        "url_signals": {
            "uses_http": url.lower().startswith("http://"),
            "has_punycode_domain": "xn--" in domain.lower(),
            "subdomain_depth": max(len([part for part in domain.split(".") if part]) - 2, 0),
        },
    }


def _heuristic_result(
    scan_report: Dict[str, Any],
    safe_browsing_result: Dict[str, Any],
    source: str,
) -> Dict[str, Any]:
    summary = _build_scan_summary(scan_report)
    counts = summary["counts"]
    url_signals = summary["url_signals"]
    safe_type = str(safe_browsing_result.get("threat_type") or "UNKNOWN").upper()
    safe_hit = safe_type not in SAFE_BROWSING_NON_HITS

    risk = 10
    evidence: List[str] = []
    safe_browsing_note = ""

    if safe_hit:
        risk = max(risk, 90)
        evidence.append(f"Google Safe Browsing reported {safe_type.replace('_', ' ').title()}.")
    elif safe_type in {"UNKNOWN", "API_ERROR", "MISSING_API_KEY"}:
        risk = max(risk, 35)
        safe_browsing_note = "Google Safe Browsing could not give a confirmed verdict."

    if url_signals["uses_http"]:
        risk += 10
        evidence.append("The page uses HTTP instead of HTTPS.")
    if url_signals["has_punycode_domain"]:
        risk += 18
        evidence.append("The domain uses punycode, which can hide lookalike characters.")
    if url_signals["subdomain_depth"] >= 3:
        risk += 8
        evidence.append("The URL has unusually deep subdomains.")
    if counts["password_inputs"]:
        risk += 20
        evidence.append("The page contains password input fields.")
    if counts["external_forms"]:
        risk += 25
        evidence.append("At least one form submits data to another domain.")
    if counts["credential_like_fields"]:
        risk += 12
        evidence.append("Form fields appear to request account, payment, or identity data.")
    if summary["suspicious_terms"]:
        risk += min(20, len(summary["suspicious_terms"]) * 5)
        evidence.append("Page text includes fraud-pressure terms such as " + ", ".join(summary["suspicious_terms"][:4]) + ".")
    if counts["external_link_hosts"] >= 5:
        risk += 8
        evidence.append("The page links to several external domains.")
    if counts["external_iframe_hosts"]:
        risk += 10
        evidence.append("The page embeds iframe content from another domain.")
    if summary["report_type"] == "network_activity" and summary["network_request"].get("is_cross_domain"):
        risk += 12
        evidence.append("A monitored network request went to another domain.")
    if safe_browsing_note:
        evidence.append(safe_browsing_note)

    risk = _clamp_int(risk, 0, 100)
    raw = {
        "risk_score": risk,
        "threat_type": _risk_to_threat_type(risk, safe_type),
        "brief_reason": _brief_reason(risk, evidence),
        "description": _description_for(summary, risk, evidence),
        "recommendation": _recommendation_for(risk),
        "evidence": evidence[:5],
    }
    return _normalize_result(raw, scan_report, safe_browsing_result, source)


def _normalize_result(
    raw_result: Dict[str, Any],
    scan_report: Dict[str, Any],
    safe_browsing_result: Dict[str, Any],
    source: str,
) -> Dict[str, Any]:
    raw_result = raw_result or {}
    safe_type = str(safe_browsing_result.get("threat_type") or "UNKNOWN").upper()
    safe_hit = safe_type not in SAFE_BROWSING_NON_HITS
    risk_score = _coerce_score(raw_result.get("risk_score", raw_result.get("score")), default=50)

    if safe_hit:
        risk_score = max(risk_score, 90)

    threat_type = str(raw_result.get("threat_type") or _risk_to_threat_type(risk_score, safe_type)).upper()
    threat_type = re.sub(r"[^A-Z0-9_]+", "_", threat_type).strip("_") or "UNKNOWN"
    if safe_hit:
        threat_type = _safe_browsing_threat_type(safe_type)
    elif risk_score < 25:
        threat_type = "SAFE"
    elif threat_type == "UNKNOWN":
        threat_type = _risk_to_threat_type(risk_score, safe_type)

    evidence = _coerce_evidence(raw_result.get("evidence"))
    if safe_hit and not any("Safe Browsing" in item for item in evidence):
        evidence.insert(0, f"Google Safe Browsing reported {safe_type.replace('_', ' ').title()}.")
    if not evidence:
        evidence = ["No strong phishing or fraud indicators were found in the captured scan data."]

    brief = _compact_text(raw_result.get("brief_reason") or _brief_reason(risk_score, evidence), 180)
    description = _compact_text(raw_result.get("description") or _description_for(_build_scan_summary(scan_report), risk_score, evidence), 900)
    recommendation = _compact_text(raw_result.get("recommendation") or _recommendation_for(risk_score), 260)
    url = str(scan_report.get("url") or "")
    domain = str(scan_report.get("domain") or _hostname(url) or "")

    return {
        "score": round(risk_score / 100, 2),
        "risk_score": risk_score,
        "threat_type": threat_type,
        "brief_reason": brief,
        "description": description,
        "recommendation": recommendation,
        "evidence": evidence[:5],
        "analysis_source": source,
        "url": url,
        "domain": domain,
        "checked_at": datetime.now(timezone.utc).isoformat(),
        "safe_browsing": safe_browsing_result,
    }


def _extract_candidate_text(data: Dict[str, Any]) -> str:
    candidates = data.get("candidates") or []
    for candidate in candidates:
        content = candidate.get("content") or {}
        parts = content.get("parts") or []
        text = "".join(str(part.get("text") or "") for part in parts if isinstance(part, dict))
        if text.strip():
            return text.strip()
    raise RuntimeError("Gemini returned no text candidate")


def _parse_json_object(text: str) -> Dict[str, Any]:
    cleaned = text.strip()
    cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s*```$", "", cleaned)
    try:
        parsed = json.loads(cleaned)
    except json.JSONDecodeError:
        start = cleaned.find("{")
        end = cleaned.rfind("}")
        if start == -1 or end == -1 or end <= start:
            raise RuntimeError("Gemini response was not valid JSON")
        parsed = json.loads(cleaned[start : end + 1])

    if not isinstance(parsed, dict):
        raise RuntimeError("Gemini response JSON was not an object")
    return parsed


def _safe_error_message(response: requests.Response) -> str:
    try:
        data = response.json()
        message = data.get("error", {}).get("message") or response.text
    except ValueError:
        message = response.text
    return _compact_text(message, 220)


def _coerce_score(value: Any, default: int = 50) -> int:
    if value is None:
        return default
    if isinstance(value, str):
        match = re.search(r"\d+(?:\.\d+)?", value)
        if not match:
            return default
        number = float(match.group(0))
    else:
        try:
            number = float(value)
        except (TypeError, ValueError):
            return default
    if 0 <= number <= 1:
        number *= 100
    return _clamp_int(round(number), 0, 100)


def _coerce_evidence(value: Any) -> List[str]:
    if isinstance(value, list):
        return [_compact_text(item, 220) for item in value if str(item).strip()]
    if isinstance(value, str) and value.strip():
        return [_compact_text(value, 220)]
    return []


def _risk_to_threat_type(risk: int, safe_type: str) -> str:
    if safe_type not in SAFE_BROWSING_NON_HITS:
        return _safe_browsing_threat_type(safe_type)
    if risk >= 75:
        return "PHISHING"
    if risk >= 50:
        return "SUSPICIOUS"
    if risk >= 25:
        return "LOW_RISK"
    return "SAFE"


def _safe_browsing_threat_type(safe_type: str) -> str:
    mapping = {
        "SOCIAL_ENGINEERING": "PHISHING",
        "MALWARE": "MALWARE",
        "UNWANTED_SOFTWARE": "MALWARE",
        "POTENTIALLY_HARMFUL_APPLICATION": "MALWARE",
    }
    return mapping.get(safe_type, "SUSPICIOUS")


def _brief_reason(risk: int, evidence: List[str]) -> str:
    if evidence:
        return _compact_text(evidence[0], 160)
    if risk >= 75:
        return "High-risk phishing or fraud indicators were found."
    if risk >= 50:
        return "Suspicious page signals need caution."
    if risk >= 25:
        return "Some weak risk signals were found."
    return "No strong phishing or fraud indicators were found."


def _description_for(summary: Dict[str, Any], risk: int, evidence: List[str]) -> str:
    domain = summary.get("domain") or "this page"
    if risk >= 75:
        opening = f"{domain} shows high-risk behavior associated with phishing or fraud."
    elif risk >= 50:
        opening = f"{domain} has suspicious signals that should be reviewed before entering sensitive data."
    elif risk >= 25:
        opening = f"{domain} has a few caution signals, but no confirmed malicious verdict was found."
    else:
        opening = f"{domain} does not show strong phishing or fraud signals in the captured scan."

    if evidence:
        return opening + " Key signals: " + " ".join(evidence[:3])
    return opening + " The scan looked at URL structure, forms, visible text, links, resources, and iframes."


def _recommendation_for(risk: int) -> str:
    if risk >= 75:
        return "Leave the page and do not enter passwords, payment details, OTPs, or identity information."
    if risk >= 50:
        return "Avoid submitting sensitive information until you verify the domain and site owner independently."
    if risk >= 25:
        return "Proceed carefully and double-check the domain before sharing any personal information."
    return "No immediate action is required, but stay alert before entering sensitive information."


def _network_summary(scan_report: Dict[str, Any]) -> Dict[str, Any]:
    if scan_report.get("reportType") != "network_activity":
        return {}
    url = str(scan_report.get("url") or "")
    source_domain = str(scan_report.get("sourcePageDomain") or "")
    request_host = _hostname(url)
    return {
        "url": url,
        "host": request_host,
        "method": scan_report.get("method"),
        "request_type": scan_report.get("requestType"),
        "source_page_url": scan_report.get("sourcePageUrl"),
        "source_page_domain": source_domain,
        "is_cross_domain": bool(request_host and source_domain and request_host != source_domain),
    }


def _hostname(value: str) -> str:
    try:
        parsed = urlparse(value if "://" in value else f"https://{value}")
    except ValueError:
        return ""
    return (parsed.hostname or "").lower()


def _external_hosts(urls: Iterable[str], domain: str) -> List[str]:
    hosts = sorted({host for host in (_hostname(url) for url in urls) if host and host != domain})
    return hosts


def _unique_strings(value: Any) -> List[str]:
    if not isinstance(value, list):
        return []
    seen = set()
    output = []
    for item in value:
        text = str(item or "").strip()
        if text and text not in seen:
            output.append(text)
            seen.add(text)
    return output


def _compact_text(value: Any, limit: int = 500) -> str:
    text = re.sub(r"\s+", " ", str(value or "")).strip()
    if len(text) <= limit:
        return text
    return text[: max(limit - 3, 0)].rstrip() + "..."


def _clamp_int(value: int, minimum: int, maximum: int) -> int:
    return max(minimum, min(maximum, int(value)))