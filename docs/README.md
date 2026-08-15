# Phishing & Fraud Detection Competitive Analysis

**Subject:** Theft Alert / Phishing-and-Fraud-Detection-Extension  
**Research cutoff:** 15 August 2026  
**Repository snapshot:** `4cd8fc4e755c244de0c6a41c0dfe3ea094c13ac5`

## Start here

1. [Project architecture and code review](01-project-architecture-and-code-review.md)
2. [Competitive landscape and capability matrix](02-competitive-landscape-and-matrix.md)
3. [Methodology and official reference register](03-methodology-and-reference-register.md)

## Individual competitor documents

| Document | Competitive class |
|---|---|
| [Airtel AI Spam, Malicious-Link and OTP Fraud Protection vs Theft Alert](competitors/airtel.md) | Adjacent but strategically important Indian network-level competitor |
| [Vodafone Idea Vi Protect vs Theft Alert](competitors/vi-protect.md) | Adjacent Indian network-level competitor |
| [Google Safe Browsing / Chrome Enhanced Protection vs Theft Alert](competitors/google.md) | Direct platform competitor and upstream dependency |
| [Microsoft Defender SmartScreen vs Theft Alert](competitors/microsoft.md) | Direct browser/OS platform competitor |
| [Guardio vs Theft Alert](competitors/guardio.md) | Direct consumer browser-security competitor |
| [Netcraft Extension vs Theft Alert](competitors/netcraft.md) | Direct anti-phishing browser-extension competitor |
| [Malwarebytes Browser Guard vs Theft Alert](competitors/malwarebytes.md) | Direct consumer browser-extension competitor |
| [Bitdefender TrafficLight and Scamio vs Theft Alert](competitors/bitdefender.md) | Direct browser competitor plus adjacent conversational scam analyzer |
| [Norton Safe Web vs Theft Alert](competitors/norton.md) | Direct web reputation/browser competitor |
| [McAfee WebAdvisor and Scam Detector vs Theft Alert](competitors/mcafee.md) | Direct browser protection plus adjacent AI scam suite |
| [Truecaller Scam/Spam Protection vs Theft Alert](competitors/truecaller.md) | Adjacent communications-security competitor |
| [Cloudflare Browser Isolation / Zero Trust vs Theft Alert](competitors/cloudflare.md) | Enterprise prevention competitor/architectural alternative |
| [JioSecurity (powered by Norton) vs Theft Alert](competitors/jio.md) | Adjacent Indian mobile/device security competitor |

## Executive conclusion

The repository demonstrates a broad and thoughtful **prototype**: it combines ten reputation/intelligence sources, domain infrastructure, rendered page/form context, deterministic heuristics and optional Gemini explanation. Its strongest prospective differentiation is transparent technical evidence plus semantic page analysis.

It is not yet equivalent to established products. Airtel and Vi act at network scale; Chrome and SmartScreen intervene natively before/during navigation and cover downloads; Netcraft and Malwarebytes block browser behaviors/content; Scamio and McAfee cover multimodal communications; Truecaller owns caller/SMS graph signals; Cloudflare contains untrusted code and data entry. The project’s most urgent needs are secure production architecture, pre-navigation action, calibrated evaluation, privacy governance, one consistent fusion engine and a real report/appeal/update loop.

## Files and use

All reports are Markdown for easy version control and conversion to DOCX/PDF. Links are clickable in a browser or Markdown viewer. A ZIP archive is provided alongside this folder.
