import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// 🚀 Backend base URL — your Flask API deployed on Railway
const String baseUrl = 'https://web-production-9b0d5.up.railway.app';

class NetworkService {
  /// 🔹 Upload multiple Excel files
  static Future<Map<String, dynamic>> uploadDepartureFiles(List<File> files) async {
    final url = Uri.parse('$baseUrl/upload');
    final request = http.MultipartRequest('POST', url);

    try {
      for (var file in files) {
        request.files.add(await http.MultipartFile.fromPath(
          'departure_files[]',
          file.path,
          contentType: MediaType('application', 'vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
        ));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Upload failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error during upload: $e');
      rethrow;
    }
  }

  /// 🔹 Analyze a base Excel file
  static Future<Map<String, dynamic>> analyzeFile(File file) async {
    final url = Uri.parse('$baseUrl/analyze');
    final request = http.MultipartRequest('POST', url);

    try {
      request.files.add(await http.MultipartFile.fromPath(
        'base_file',
        file.path,
        contentType: MediaType('application', 'vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Analyze failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error during analyze: $e');
      rethrow;
    }
  }

  /// 🔹 Search data by doc_id and query
  static Future<List<dynamic>> searchRecords(String docId, String query) async {
    final url = Uri.parse('$baseUrl/search?doc_id=$docId&query=$query');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Search failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error during search: $e');
      rethrow;
    }
  }

  /// 🔹 Fetch statistics (grouped by operator/region/airport)
  static Future<List<dynamic>> fetchStats(String docId, {String groupBy = 'operator'}) async {
    final url = Uri.parse('$baseUrl/stats?doc_id=$docId&group_by=$groupBy');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Stats fetch failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error fetching stats: $e');
      rethrow;
    }
  }

  /// 🔹 Download dashboard PDF
  static Future<http.Response> downloadDashboardPdf(String docId) async {
    final url = Uri.parse('$baseUrl/download_dashboard_pdf?doc_id=$docId');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return response;
      } else {
        throw Exception('PDF download failed: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error downloading PDF: $e');
      rethrow;
    }
  }
}
