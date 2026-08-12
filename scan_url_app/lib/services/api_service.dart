import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/scan_report.dart';
import 'storage_service.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Talks to the Theft Alert FastAPI backend. Per product requirement,
/// this client only ever calls `POST /api/scan_url` — the lightweight,
/// URL-only endpoint — rather than `/api/report`, which expects a full
/// page-content payload from a browser extension.
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  Future<ScanReport> scanUrl(String rawUrl) async {
    final base = await StorageService.instance.getBackendUrl();
    if (base.trim().isEmpty) {
      throw ApiException('Set your Theft Alert backend URL in Settings first.');
    }
    final uri = Uri.parse('${base.trim().replaceAll(RegExp(r'/+$'), '')}/api/scan_url');

    http.Response resp;
    try {
      resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'url': rawUrl.trim()}),
          )
          .timeout(const Duration(seconds: 45));
    } catch (e) {
      throw ApiException('Could not reach the backend at $base. Check the URL and your network.');
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException('Backend returned an error (HTTP ${resp.statusCode}).');
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      throw ApiException('Backend returned an unexpected response.');
    }

    return ScanReport.fromApiJson(json, requestedUrl: rawUrl.trim());
  }

  Future<void> healthCheck() async {
    final base = await StorageService.instance.getBackendUrl();
    final uri = Uri.parse('${base.trim().replaceAll(RegExp(r'/+$'), '')}/');
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException('Server responded with HTTP ${resp.statusCode}.');
    }
  }
}
