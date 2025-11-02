import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// 🌐 Global configuration for backend and API routes.
/// Handles automatic environment switching (Development ↔ Production)
/// and provides Firebase-friendly + emulator-safe support.
class AppConfig {
  // --------------------------------------------------------------------------
  // ⚙️ Environment Configuration
  // --------------------------------------------------------------------------

  /// Automatically detect environment:
  /// - Web → Always Production (localhost is not accessible)
  /// - Local Debug (Android/iOS/Emulator) → Use localhost / 10.0.2.2
  static bool _isDevelopment = !kIsWeb && kDebugMode;

  /// 🧩 Local Flask backend configuration
  /// Use "10.0.2.2" for Android emulator, "localhost" for Windows/macOS.
  static const String _devBackendIP = "10.0.2.2"; // ✅ Works on Android emulator
  static const int _devPort = 5003;

  /// 🚀 Production backend (Deployed Flask API on Railway)
  static const String _prodBackendURL =
      "https://web-production-9b0d5.up.railway.app";

  // --------------------------------------------------------------------------
  // ✅ Configuration Validation
  // --------------------------------------------------------------------------

  static void _validateConfig() {
    if (_isDevelopment && !_isValidIP(_devBackendIP)) {
      throw ArgumentError("❌ Invalid development IP: $_devBackendIP");
    }
    if (_devPort <= 0 || _devPort > 65535) {
      throw ArgumentError("❌ Invalid port number: $_devPort");
    }
  }

  /// 🧠 Validate IPv4, localhost, or emulator IP
  static bool _isValidIP(String ip) {
    if (ip == "localhost" || ip == "10.0.2.2") return true;
    const pattern = r'^(\d{1,3}\.){3}\d{1,3}$';
    final match = RegExp(pattern).stringMatch(ip);
    if (match == null) return false;
    return ip.split('.').every((segment) {
      final num = int.tryParse(segment);
      return num != null && num >= 0 && num <= 255;
    });
  }

  /// 🔄 Manually override environment (useful for production tests)
  static void setEnvironment({bool isDev = kDebugMode}) {
    _isDevelopment = isDev && !kIsWeb; // Prevent localhost on Web
    _validateConfig();
  }

  // --------------------------------------------------------------------------
  // 🌍 API ROUTES
  // --------------------------------------------------------------------------

  /// ✅ Dynamically selects correct backend URL
  static String get baseUrl =>
      _isDevelopment ? "http://$_devBackendIP:$_devPort" : _prodBackendURL;

  /// 📤 File Upload Endpoint
  static String get uploadURL => "$baseUrl/upload";

  /// 🧠 Excel File Analysis Endpoint
  static String get analyzeURL => "$baseUrl/analyze";

  /// 🧾 Generate or Download Dashboard PDF Endpoint
  static String get generatePdfURL => "$baseUrl/download_dashboard_pdf";

  /// 🪶 Backward compatibility alias
  static String get downloadPdfUrl => generatePdfURL;

  /// ✈️ Flight Search Endpoint
  static String get searchURL => "$baseUrl/search";

  /// 📈 Statistics Endpoint
  static String get statsURL => "$baseUrl/stats";

  /// 🧮 Health check / test endpoint (optional)
  static String get healthCheckURL => "$baseUrl/";

  // --------------------------------------------------------------------------
  // 🔐 API Keys / Tokens (Optional)
  // --------------------------------------------------------------------------

  static String? _apiKey;
  static String? _authToken;

  static void setApiKey(String key) {
    if (key.isEmpty) throw ArgumentError("API key cannot be empty");
    _apiKey = key;
  }

  static void setAuthToken(String token) {
    if (token.isEmpty) throw ArgumentError("Auth token cannot be empty");
    _authToken = token;
  }

  /// Common headers for all authorized requests
  static Map<String, String> get headers {
    final headers = {'Content-Type': 'application/json'};
    if (_apiKey != null) headers['X-API-Key'] = _apiKey!;
    if (_authToken != null) headers['Authorization'] = 'Bearer $_authToken';
    return headers;
  }

  // --------------------------------------------------------------------------
  // 🕒 Utility Helpers
  // --------------------------------------------------------------------------

  /// Returns current IST timestamp
  static String get currentDateTimeIST =>
      DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(
        DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)),
      );

  /// Returns Firestore-safe collection name
  static String get firestoreFlightsCollection =>
      "analysis_results_${DateFormat('yyyy_MM_dd').format(DateTime.now())}";

  // --------------------------------------------------------------------------
  // 🧾 Debug Utility
  // --------------------------------------------------------------------------

  /// Logs current backend environment and base URL
  static void logActiveConfig() {
    final env = _isDevelopment
        ? "🧩 Development (Localhost / Emulator)"
        : "🚀 Production (Railway)";
    // ignore: avoid_print
    print("""
───────────────────────────────────────────────
🌍 Active Environment: $env
🔗 Base URL: $baseUrl
🕒 Time: $currentDateTimeIST
───────────────────────────────────────────────
""");
  }
}
