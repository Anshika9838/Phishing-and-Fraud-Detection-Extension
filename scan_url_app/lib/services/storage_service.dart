import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scan_report.dart';

/// Local-only persistence layer — the direct port of the original
/// `lib/storage.ts` (which used AsyncStorage). No login/session keys:
/// the login screen has been removed per product requirements, so there
/// is no session to persist.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const _kHistory = 'theft_alert.history';
  static const _kTermsAccepted = 'theft_alert.terms_accepted';
  static const _kOnboardingDone = 'theft_alert.onboarding_done';
  static const _kBackendUrl = 'theft_alert.backend_url';

  Future<List<ScanReport>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kHistory);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => ScanReport.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ScanReport>> addScan(ScanReport report) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await getHistory();
    final filtered = existing.where((r) => r.url != report.url).toList();
    final next = [report, ...filtered].take(100).toList();
    await prefs.setString(_kHistory, jsonEncode(next.map((r) => r.toJson()).toList()));
    return next;
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHistory);
  }

  Future<List<ScanReport>> deleteScan(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await getHistory();
    final next = existing.where((r) => r.id != id).toList();
    await prefs.setString(_kHistory, jsonEncode(next.map((r) => r.toJson()).toList()));
    return next;
  }

  Future<bool> isTermsAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kTermsAccepted) ?? false;
  }

  Future<void> acceptTerms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTermsAccepted, true);
  }

  Future<bool> isOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingDone) ?? false;
  }

  Future<void> setOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingDone, true);
  }

  /// The backend base URL (e.g. `http://192.168.1.10:8000`), configurable
  /// from Settings since it depends on where the Theft Alert FastAPI
  /// server is deployed.
  Future<String> getBackendUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kBackendUrl) ?? 'http://10.0.2.2:8000';
  }

  Future<void> setBackendUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBackendUrl, url.trim());
  }
}
