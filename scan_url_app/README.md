# Theft Alert — Flutter App

A pixel-for-pixel Flutter port of the original React Native/Expo app ("ShieldURL"),
wired to your **Theft Alert** FastAPI backend instead of the mock scanner, with the
login screen removed.

## What's the same

Every screen, color, spacing value, radius, font size, and animation was ported
directly from the original `src/` (React Native) source:

- **Splash** — animated shield logo + fade/slide title (2s, auto-advances)
- **Onboarding** — 3-slide swiper with dots, Skip, Next/Get Started
- **Terms & Conditions** — scroll-to-accept flow, button disabled until scrolled to the end
- **Home (Scan)** — URL input, paste/clear button, animated multi-source scan
  progress, animated circular score gauge, markdown-style report, checks list
- **History** — stats pills, list of past scans, swipe-to-clear, empty state
- **Settings** — preferences, clear-history, about
- **Detail screen** — full report view reached by tapping a history row
- Same soft "smoky lavender" color palette in `lib/theme/colors.dart`, same
  light/dark variants that automatically follow the system theme

## What changed (per your requirements)

1. **Real backend, URL-only endpoint.** `lib/services/api_service.dart` calls
   **`POST /api/scan_url`** on your Theft Alert backend — never `/api/report`
   (which expects a full browser-extension payload). The backend URL is
   configurable from the **Settings** tab (new "Backend server" card) and
   defaults to `http://10.0.2.2:8000` (the Android-emulator alias for your
   host machine's `localhost`) — change it to your real server address.
2. **Login screen removed.** There is no `LoginScreen`, no session/auth
   state, and no Sign Out button. The flow is now:
   `Splash → Onboarding → Terms → Main tabs` (previously Splash → Onboarding →
   Terms → **Login** → Main tabs).
3. **Terms & Conditions rewritten** to describe what this app *actually*
   does per your backend docs (§5, Data Management & Privacy): it sends only
   the URL you type to your configured backend, no page content or personal
   data is collected by the app itself, history stays on-device, and the
   backend shares the minimum data necessary with the threat-intel providers
   listed in your docs (Google Safe Browsing, VirusTotal, URLhaus, OpenPhish,
   AbuseIPDB, AlienVault OTX, Spamhaus, Pulsedive, URLScan.io).

## ⚠️ Please verify the response field mapping

Your backend documentation describes the shape of `POST /api/scan_url`'s
response at a high level:

```json
{
  "url": "...", "domain": "...", "ip": "...",
  "overall": {
    "risk_score": 95.0,
    "threat_type": "PHISHING",
    "brief_reason": "...",
    "recommendation": "..."
  },
  "reputation_checks": [...],
  "infrastructure_checks": [...]
}
```

...but it doesn't specify the exact key names *inside* each entry of
`reputation_checks` / `infrastructure_checks` (e.g. whether a single check
uses `source` or `name`, `status` or `verdict`, `detail` or `message`, etc).
Since I only had your documentation and not the backend source code, I
parse defensively in **`lib/models/scan_report.dart`**
(`ScanCheck.fromDynamic`) — it tries several likely key names and falls
back gracefully if a field is missing, so the app won't crash on an
unexpected shape, but the labels may not be perfectly accurate until you
confirm the real field names.

**To finish wiring this up correctly:** call `/api/scan_url` on your running
backend with a test URL, compare the raw JSON to the assumptions above, and
adjust the `pick([...])` key lists in `ScanCheck.fromDynamic` and
`ScanReport.fromApiJson` if your backend uses different names. That's the
only place backend-shape assumptions live.

### Score direction

Your backend's `overall.risk_score` is **higher = more dangerous** (e.g. 95
for a confirmed phishing site). The UI's circular gauge shows a **safety**
score where higher = safer, so the app computes `safetyScore = 100 -
risk_score`. Risk-level thresholds (safe/caution/danger) are set at
`risk_score` ≤ 30 / ≤ 65 / above — tune `_riskLevelForScore` in
`scan_report.dart` if you'd like different cutoffs.

### Scan progress animation

The backend does all its work server-side in one request, so the
"Scanning across databases…" step-by-step animation (`lib/widgets/
scan_progress_view.dart`, source list in `lib/models/scan_progress.dart`) is
a cosmetic timeline that runs *concurrently* with the real
`POST /api/scan_url` call — it's purely to preserve the original
scanning animation/experience. If the real response arrives before the
animation finishes, the UI jumps straight to the result.

## Project structure

```
lib/
  main.dart                     Entry point
  app.dart                      MaterialApp + theming (system light/dark)
  theme/
    colors.dart                 Exact colour tokens (light/dark)
    typography.dart             Text styles, spacing, radius tokens
    theme_scope.dart            useAppTheme(context) helper
  models/
    scan_report.dart            ScanReport/ScanCheck + backend JSON parsing
    scan_progress.dart          Cosmetic scan-step timeline data
  services/
    api_service.dart            Calls POST /api/scan_url
    storage_service.dart        Local history/onboarding/terms/backend-url
  widgets/                      ShieldLogo, ScoreGauge, AppButton, AppInput,
                                 AppHeader, MarkdownView, HistoryRow,
                                 ScanProgressView — all ported 1:1
  screens/
    splash_screen.dart
    onboarding_screen.dart
    terms_screen.dart           Updated Terms & Conditions content
    main_tabs_screen.dart       Bottom nav (Scan / History / Settings)
    home_screen.dart            Wired to ApiService.scanUrl()
    history_screen.dart
    settings_screen.dart        No login UI; has Backend Server config
    detail_screen.dart
    root_navigator.dart         Splash → Onboarding → Terms → Main (no auth)
```

## Setup

This project was written directly as source files — it wasn't possible to
run `flutter pub get` / `flutter build` in the sandbox this was generated
in (no network access to pub.dev), so please do a normal first run and fix
anything your specific Flutter SDK version flags:

```bash
flutter pub get
flutter run
```

Dependencies used (see `pubspec.yaml`): `http` for the API call,
`shared_preferences` for local storage — both first-party/widely-used
packages, kept to a minimum on purpose.

Then, on first launch: go through Splash → Onboarding → Terms, then open
the **Settings** tab and set your backend's address (e.g.
`http://192.168.1.23:8000` for a phone on the same Wi-Fi as your server, or
`http://10.0.2.2:8000` for the Android emulator talking to your host
machine), tap **Save & Test Connection**, then head to the **Scan** tab.

### Android cleartext HTTP

If your backend runs over plain `http://` (not `https://`), Android 9+
blocks cleartext traffic by default. Either serve your backend over HTTPS,
or add a `network_security_config.xml` allowing your backend's host and
reference it from `android/app/src/main/AndroidManifest.xml`
(`android:networkSecurityConfig`) — this project doesn't include one by
default.
