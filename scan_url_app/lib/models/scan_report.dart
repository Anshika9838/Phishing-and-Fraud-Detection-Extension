import '../theme/colors.dart';

enum CheckStatus { pass, warn, fail }

/// A single evidence item — one entry from the backend's
/// `reputation_checks` or `infrastructure_checks` arrays.
class ScanCheck {
  final String id;
  final String name;
  final String description;
  final CheckStatus status;
  final String detail;

  ScanCheck({
    required this.id,
    required this.name,
    required this.description,
    required this.status,
    required this.detail,
  });

  /// The Theft Alert backend documentation describes each check as "a
  /// standardized dictionary" but doesn't pin exact key names, so this
  /// parses defensively across the most likely shapes
  /// (source/name, status/verdict/result, detail/description/message).
  factory ScanCheck.fromDynamic(dynamic raw, int index) {
    if (raw is! Map) {
      return ScanCheck(
        id: 'check_$index',
        name: 'Check ${index + 1}',
        description: '',
        status: CheckStatus.warn,
        detail: raw?.toString() ?? 'No data returned.',
      );
    }
    final map = Map<String, dynamic>.from(raw);

    String pick(List<String> keys, {String fallback = ''}) {
      for (final k in keys) {
        final v = map[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString();
      }
      return fallback;
    }

    final name = pick(['source', 'name', 'check', 'provider'], fallback: 'Check ${index + 1}');
    final description = pick(['description', 'category'], fallback: '');
    final detail = pick(
      ['detail', 'details', 'message', 'reason', 'summary'],
      fallback: 'No additional detail provided.',
    );

    // Determine status from whatever verdict-shaped field is present.
    CheckStatus status = CheckStatus.warn;
    final verdictRaw = pick(['status', 'verdict', 'risk_level', 'result', 'classification']).toLowerCase();
    final maliciousFlag = map['malicious'] ?? map['is_malicious'] ?? map['flagged'];
    final numericScore = map['risk_score'] ?? map['score'];

    if (verdictRaw.isNotEmpty) {
      if (verdictRaw.contains('malicious') ||
          verdictRaw.contains('phish') ||
          verdictRaw.contains('danger') ||
          verdictRaw.contains('fail') ||
          verdictRaw.contains('high') ||
          verdictRaw.contains('blacklist')) {
        status = CheckStatus.fail;
      } else if (verdictRaw.contains('suspicious') ||
          verdictRaw.contains('warn') ||
          verdictRaw.contains('medium') ||
          verdictRaw.contains('caution') ||
          verdictRaw.contains('unknown')) {
        status = CheckStatus.warn;
      } else if (verdictRaw.contains('clean') ||
          verdictRaw.contains('safe') ||
          verdictRaw.contains('pass') ||
          verdictRaw.contains('low') ||
          verdictRaw.contains('ok') ||
          verdictRaw.contains('none')) {
        status = CheckStatus.pass;
      }
    } else if (maliciousFlag is bool) {
      status = maliciousFlag ? CheckStatus.fail : CheckStatus.pass;
    } else if (numericScore != null) {
      final n = double.tryParse(numericScore.toString()) ?? 0;
      status = n >= 65 ? CheckStatus.fail : (n >= 30 ? CheckStatus.warn : CheckStatus.pass);
    }

    return ScanCheck(
      id: pick(['id'], fallback: '${name}_$index').toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
      name: name,
      description: description,
      status: status,
      detail: detail,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'status': status.name,
        'detail': detail,
      };

  factory ScanCheck.fromJson(Map<String, dynamic> j) => ScanCheck(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String? ?? '',
        status: CheckStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => CheckStatus.warn,
        ),
        detail: j['detail'] as String? ?? '',
      );
}

class ScanReport {
  final String id;
  final String url;
  final String domain;
  final String ip;
  final DateTime scannedAt;

  /// Raw backend risk score, 0-100, HIGHER = more dangerous
  /// (matches `overall.risk_score` from `/api/scan_url`).
  final double riskScore;

  final RiskLevel risk;
  final String threatType;
  final String summary;

  /// Markdown-ish explanation shown via [MarkdownView].
  final String explanation;

  final List<ScanCheck> checks;
  final List<String> categories;

  ScanReport({
    required this.id,
    required this.url,
    required this.domain,
    required this.ip,
    required this.scannedAt,
    required this.riskScore,
    required this.risk,
    required this.threatType,
    required this.summary,
    required this.explanation,
    required this.checks,
    required this.categories,
  });

  /// "Safety score" for the gauge — higher is safer (0-100).
  int get safetyScore => (100 - riskScore).clamp(0, 100).round();

  int get sourcesCount => checks.length;
  int get positives => checks.where((c) => c.status == CheckStatus.pass).length;
  int get neutrals => checks.where((c) => c.status == CheckStatus.warn).length;
  int get negatives => checks.where((c) => c.status == CheckStatus.fail).length;

  static RiskLevel _riskLevelForScore(double riskScore) {
    if (riskScore <= 30) return RiskLevel.safe;
    if (riskScore <= 65) return RiskLevel.caution;
    return RiskLevel.danger;
  }

  /// Parses the response of `POST /api/scan_url`:
  /// ```json
  /// {
  ///   "url": "...", "domain": "...", "ip": "...",
  ///   "overall": { "risk_score": 95.0, "threat_type": "PHISHING",
  ///                "brief_reason": "...", "recommendation": "..." },
  ///   "reputation_checks": [...],
  ///   "infrastructure_checks": [...]
  /// }
  /// ```
  factory ScanReport.fromApiJson(Map<String, dynamic> json, {required String requestedUrl}) {
    final overall = (json['overall'] is Map) ? Map<String, dynamic>.from(json['overall']) : <String, dynamic>{};

    final riskScoreRaw = overall['risk_score'] ?? overall['score'] ?? json['risk_score'];
    final riskScore = double.tryParse(riskScoreRaw?.toString() ?? '') ?? 0;

    final threatType = (overall['threat_type'] ?? 'UNKNOWN').toString();
    final briefReason = (overall['brief_reason'] ?? overall['reason'] ?? '').toString();
    final recommendation = (overall['recommendation'] ?? '').toString();

    final url = (json['url'] ?? requestedUrl).toString();
    final domain = (json['domain'] ?? _extractDomain(url)).toString();
    final ip = (json['ip'] ?? json['ip_address'] ?? '—').toString();

    final risk = _riskLevelForScore(riskScore);

    final repChecksRaw = (json['reputation_checks'] is List) ? json['reputation_checks'] as List : const [];
    final infraChecksRaw = (json['infrastructure_checks'] is List) ? json['infrastructure_checks'] as List : const [];

    final checks = <ScanCheck>[
      for (var i = 0; i < repChecksRaw.length; i++) ScanCheck.fromDynamic(repChecksRaw[i], i),
      for (var i = 0; i < infraChecksRaw.length; i++)
        ScanCheck.fromDynamic(infraChecksRaw[i], repChecksRaw.length + i),
    ];

    final summary = briefReason.isNotEmpty
        ? briefReason
        : (risk == RiskLevel.safe
            ? 'No significant threats detected. This URL appears safe to visit.'
            : risk == RiskLevel.caution
                ? 'Some warning signs detected. Proceed with caution and verify the source.'
                : 'Multiple high-risk signals detected. Avoid visiting this URL.');

    final explanationBuf = StringBuffer();
    explanationBuf.writeln('## Summary');
    explanationBuf.writeln('The URL **$domain** was analysed with a threat classification of '
        '**${threatType.isEmpty ? 'UNKNOWN' : threatType}**.');
    explanationBuf.writeln();
    if (briefReason.isNotEmpty) {
      explanationBuf.writeln('### Why');
      explanationBuf.writeln(briefReason);
      explanationBuf.writeln();
    }
    if (recommendation.isNotEmpty) {
      explanationBuf.writeln('### Recommendation');
      explanationBuf.writeln(recommendation);
      explanationBuf.writeln();
    }
    explanationBuf.writeln('### Evidence considered');
    explanationBuf.writeln('- **${checks.length}** signals checked across reputation feeds and '
        'infrastructure analysis');
    explanationBuf.writeln('- **${checks.where((c) => c.status == CheckStatus.pass).length}** clean, '
        '**${checks.where((c) => c.status == CheckStatus.warn).length}** cautionary, '
        '**${checks.where((c) => c.status == CheckStatus.fail).length}** flagged as malicious');

    final categories = <String>[];
    if (threatType.isNotEmpty && !['NONE', 'SAFE', 'UNKNOWN'].contains(threatType.toUpperCase())) {
      categories.add(threatType);
    }
    if (categories.isEmpty) {
      categories.add(risk == RiskLevel.safe ? 'Trusted' : 'Unverified');
    }

    return ScanReport(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      url: url,
      domain: domain,
      ip: ip,
      scannedAt: DateTime.now(),
      riskScore: riskScore,
      risk: risk,
      threatType: threatType,
      summary: summary,
      explanation: explanationBuf.toString().trim(),
      checks: checks,
      categories: categories,
    );
  }

  static String _extractDomain(String input) {
    try {
      var u = input.trim();
      if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(u)) u = 'https://$u';
      final uri = Uri.parse(u);
      var host = uri.host;
      if (host.startsWith('www.')) host = host.substring(4);
      return host.isEmpty ? input : host;
    } catch (_) {
      return input;
    }
  }

  // --- Local persistence (own stable schema, independent of API shape) ---

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'domain': domain,
        'ip': ip,
        'scannedAt': scannedAt.toIso8601String(),
        'riskScore': riskScore,
        'risk': risk.name,
        'threatType': threatType,
        'summary': summary,
        'explanation': explanation,
        'checks': checks.map((c) => c.toJson()).toList(),
        'categories': categories,
      };

  factory ScanReport.fromJson(Map<String, dynamic> j) => ScanReport(
        id: j['id'] as String,
        url: j['url'] as String,
        domain: j['domain'] as String,
        ip: j['ip'] as String? ?? '—',
        scannedAt: DateTime.tryParse(j['scannedAt'] as String? ?? '') ?? DateTime.now(),
        riskScore: (j['riskScore'] as num?)?.toDouble() ?? 0,
        risk: RiskLevel.values.firstWhere((r) => r.name == j['risk'], orElse: () => RiskLevel.caution),
        threatType: j['threatType'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        explanation: j['explanation'] as String? ?? '',
        checks: ((j['checks'] as List?) ?? [])
            .map((c) => ScanCheck.fromJson(Map<String, dynamic>.from(c as Map)))
            .toList(),
        categories: ((j['categories'] as List?) ?? []).map((e) => e.toString()).toList(),
      );
}

/// Basic client-side URL sanity check before hitting the backend.
class UrlValidation {
  final bool ok;
  final String? reason;
  const UrlValidation(this.ok, [this.reason]);
}

UrlValidation validateUrlFormat(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return const UrlValidation(false, 'Please paste a URL to scan.');
  if (trimmed.length < 4) return const UrlValidation(false, 'That URL looks too short.');
  final re = RegExp(r'^https?://|^\w+([.-]\w+)*\.[a-z]{2,}', caseSensitive: false);
  if (!re.hasMatch(trimmed)) {
    return const UrlValidation(false, "That doesn't look like a valid URL.");
  }
  return const UrlValidation(true);
}
