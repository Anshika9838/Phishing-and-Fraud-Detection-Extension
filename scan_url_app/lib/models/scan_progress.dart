class ScanProgressData {
  final String step;
  final int percent;
  final String? source;
  const ScanProgressData({required this.step, required this.percent, this.source});
}

/// The visual step sequence shown while a scan is in flight. The real
/// backend performs all of this work server-side in a single request, so
/// this timeline is a cosmetic simulation that runs concurrently with the
/// actual `POST /api/scan_url` call — preserving the original app's
/// "scanning across databases" animation/experience while still only
/// hitting the one real endpoint. If the real response arrives first, the
/// UI jumps straight to 100% and shows the result.
const List<Map<String, Object>> kScanSteps = [
  {'source': 'Google Safe Browsing', 'label': 'Checking Google Safe Browsing', 'duration': 650},
  {'source': 'VirusTotal', 'label': 'Querying VirusTotal', 'duration': 600},
  {'source': 'URLhaus', 'label': 'Scanning URLhaus malware feed', 'duration': 550},
  {'source': 'OpenPhish', 'label': 'Cross-referencing OpenPhish', 'duration': 500},
  {'source': 'WHOIS Lookup', 'label': 'Fetching WHOIS registration data', 'duration': 700},
  {'source': 'AbuseIPDB & OTX', 'label': 'Aggregating community reputation', 'duration': 600},
  {'source': 'SSL & Cert Analysis', 'label': 'Validating TLS certificate chain', 'duration': 450},
  {'source': 'AI Contextual Analysis', 'label': 'Running AI-powered judgement', 'duration': 700},
];
