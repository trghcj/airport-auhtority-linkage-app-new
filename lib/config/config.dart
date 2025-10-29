import 'package:flutter/foundation.dart';

class AppConfig {
  // Environment-specific configuration
  static bool _isDevelopment = kDebugMode; // Default to debug mode, can be overridden
  static const String _devBackendIP = "localhost"; // Local development IP
  static const String _prodBackendIP = "your-production-server.com"; // Replace with production IP or domain
  static const int _port = 5003;

  // Method to override environment (e.g., via command-line or config file)
  static void setEnvironment({bool isDev = kDebugMode}) {
    _isDevelopment = isDev;
  }

  // Base URL based on environment, with optional HTTPS support
  static String get baseURL => _isDevelopment
      ? "http://$_devBackendIP:$_port"
      : "https://$_prodBackendIP:$_port"; // Use HTTPS in production

  // Specific endpoints (aligned with Flask backend routes)
  static String get uploadURL => "$baseURL/upload";
  static String get analyzeURL => "$baseURL/analyze";
  static String get generatePdfURL => "$baseURL/download_dashboard_pdf"; // Corrected to match Flask route
  static String get searchURL => "$baseURL/search"; // Added for SearchPage
  static String get statsURL => "$baseURL/stats"; // Added for StatsPage

  // Firestore collection
  static const String firestoreFlightsCollection = "analysis_results";

  // API configuration
  static String get apiVersion => ""; // Removed version prefix since Flask routes don't use it
  static String? _apiKey; // Placeholder for API key, set via setApiKey
  static String? _authToken; // Placeholder for authentication token

  // Methods to set API credentials
  static void setApiKey(String key) {
    if (key.isEmpty) {
      throw ArgumentError("API key cannot be empty");
    }
    _apiKey = key;
  }

  static void setAuthToken(String token) {
    if (token.isEmpty) {
      throw ArgumentError("Authentication token cannot be empty");
    }
    _authToken = token;
  }

  // Method to get headers with authentication
  static Map<String, String> get headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_apiKey != null) {
      headers['X-API-Key'] = _apiKey!;
    }
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }
}