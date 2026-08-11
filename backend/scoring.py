"""
Scoring engine: combines all threat intel + infra checks + LLM into final risk score
"""
from typing import List, Dict, Any
import datetime

def calculate_overall_score(all_checks: List[Dict[str, Any]], llm_results: List[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    all_checks: list of check dicts each with risk_score, weight, verdict, etc
    llm_results: optional list of LLM analysis dicts containing risk_score etc
    Returns aggregated final result
    """
    llm_results = llm_results or []
    # combine
    combined = list(all_checks) + list(llm_results)

    total_weight = 0
    weighted_sum = 0
    high_conf_malicious = []
    safe_signals = []

    for c in combined:
        try:
            weight = float(c.get("weight", 1))
            risk = float(c.get("risk_score", 50))
            # adjust weight by confidence? if confidence < 20, halve weight
            conf = float(c.get("confidence", 70))
            if conf < 20:
                weight *= 0.5
            elif conf < 40:
                weight *= 0.75
            # cap
            weight = max(0.1, weight)
            total_weight += weight
            weighted_sum += risk * weight

            if risk >= 85 and c.get("verdict") == "MALICIOUS" and weight >= 6:
                high_conf_malicious.append(c)
            if risk <= 15 and c.get("verdict") == "SAFE":
                safe_signals.append(c)
        except Exception:
            continue

    if total_weight == 0:
        final_score = 50
    else:
        final_score = weighted_sum / total_weight

    # Boosting logic: if any high confidence malicious from critical sources, enforce minimum floor
    # Critical sources: Google Safe Browsing, VirusTotal, URLhaus, OpenPhish, Spamhaus
    critical_sources = {"Google Safe Browsing", "VirusTotal", "URLhaus (abuse.ch)", "OpenPhish", "Spamhaus"}
    critical_hits = [c for c in high_conf_malicious if c.get("source") in critical_sources]

    if critical_hits:
        # at least one critical source says malicious => floor 85
        # if 2 critical sources => floor 95
        if len(critical_hits) >= 2:
            final_score = max(final_score, 95)
        else:
            final_score = max(final_score, 85)
    elif high_conf_malicious:
        # non-critical but high confidence malicious (e.g. AbuseIPDB 100 + OTX)
        if len(high_conf_malicious) >= 2:
            final_score = max(final_score, 80)
        else:
            final_score = max(final_score, 65)

    # Cap between 0-100
    final_score = max(0, min(100, round(final_score, 1)))

    # Determine threat_type
    if final_score >= 85:
        if any(c.get("source") == "URLhaus (abuse.ch)" and c.get("risk_score",0)>=90 for c in combined):
            threat_type = "MALWARE"
        elif any("phish" in str(c.get("details","")).lower() or c.get("source") in ("Google Safe Browsing","OpenPhish") for c in critical_hits):
            threat_type = "PHISHING"
        else:
            threat_type = "FRAUD" if final_score >= 90 else "PHISHING"
    elif final_score >= 65:
        threat_type = "SUSPICIOUS"
    elif final_score >= 35:
        threat_type = "LOW_RISK"
    elif final_score >= 15:
        threat_type = "SAFE"
    else:
        threat_type = "SAFE"

    # For UI compatibility also provide SAFE vs PHISHING etc
    # Provide brief reasoning
    # Collect top risk reasons
    sorted_by_risk = sorted([c for c in combined if c.get("risk_score",0) >= 50], key=lambda x: x.get("risk_score",0), reverse=True)[:5]
    top_reasons = [c.get("description","") for c in sorted_by_risk if c.get("description")]

    if not top_reasons:
        # if safe, show safe reasons
        safe_sorted = sorted([c for c in combined if c.get("risk_score",0) < 25], key=lambda x: x.get("risk_score",0))
        top_reasons = [c.get("description","") for c in safe_sorted[:3]]

    brief_reason = top_reasons[0] if top_reasons else ("No strong threat indicators found." if final_score<30 else "Multiple risk signals detected.")

    # Recommendation
    if final_score >= 85:
        recommendation = "⛔ DO NOT ENTER ANY CREDENTIALS. Leave this site immediately. It is flagged as malicious/fraudulent by multiple threat intel sources. Report and block."
    elif final_score >= 65:
        recommendation = "⚠️ High caution: suspected phishing/fake clone. Do not enter passwords, card, OTP, or personal data. Verify domain independently via official source."
    elif final_score >= 35:
        recommendation = "⚠️ Moderate risk: some suspicious signals. Avoid submitting sensitive data until you verify legitimacy. Check SSL and WHOIS details."
    else:
        recommendation = "✅ Low risk: No strong phishing/fraud indicators. Still stay alert before entering sensitive information."

    # Evidence list for UI (max 6)
    evidence = []
    for c in sorted(combined, key=lambda x: x.get("risk_score",0), reverse=True)[:10]:
        if c.get("risk_score",0) >= 30 or final_score < 30:
            evidence.append(f"{c.get('source')}: {c.get('description','')} (Score {c.get('risk_score')})")
        if len(evidence) >= 6:
            break

    if not evidence:
        evidence = ["No strong phishing or fraud indicators in captured signals."]

    # Build per-source score breakdown for frontend
    breakdown = []
    for c in combined:
        breakdown.append({
            "source": c.get("source"),
            "risk_score": c.get("risk_score"),
            "verdict": c.get("verdict"),
            "weight": c.get("weight"),
            "confidence": c.get("confidence"),
            "details": c.get("details","")[:500],
            "description": c.get("description","")[:300]
        })

    return {
        "risk_score": final_score,
        "score": round(final_score/100, 2),  # for backward compat 0-1
        "threat_type": threat_type,
        "brief_reason": brief_reason[:200],
        "description": f"Overall risk {final_score}/100 - {threat_type}. " + " ".join(top_reasons[:3])[:600],
        "recommendation": recommendation,
        "evidence": evidence[:6],
        "breakdown": breakdown,
        "critical_hits": len(critical_hits),
        "malicious_sources": [c.get("source") for c in high_conf_malicious],
        "checked_at": datetime.datetime.utcnow().isoformat() + "Z",
        "total_weight": total_weight,
        "sources_checked": len(combined)
    }

def risk_to_label(score: float) -> str:
    if score >= 85:
        return "Critical - Malicious/Fraud"
    if score >= 65:
        return "High - Suspicious Phishing"
    if score >= 35:
        return "Medium - Low Risk / Caution"
    if score >= 15:
        return "Low - Likely Safe"
    return "Safe"
