import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';

import 'package:airport_auhtority_linkage_app/config/config.dart';
import 'package:airport_auhtority_linkage_app/models/analysis_data.dart' as model;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';

class AnalysisService {
  final Logger logger = Logger();

  // ---------------------------------------------------------------------------
  // Date parser helper (removed — unused in current codebase)
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Retry logic for all requests
  // ---------------------------------------------------------------------------
  Future<T> _retryRequest<T>(Future<T> Function() request, int maxAttempts) async {
    const delay = Duration(seconds: 2);
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await request();
      } catch (e) {
        if (attempt == maxAttempts) rethrow;
        logger.w('Attempt $attempt failed: $e — retrying...');
        await Future.delayed(delay * attempt);
      }
    }
    throw Exception('Max retry attempts reached');
  }

  // ---------------------------------------------------------------------------
  // 1️⃣ Upload departure files to backend (/upload)
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> uploadFiles(List<PlatformFile> files) async {
    if (files.isEmpty) throw Exception('Please select at least one departure file.');

    final uri = Uri.parse('${AppConfig.uploadURL}');
    return await _retryRequest(() async {
      final request = http.MultipartRequest('POST', uri);

      for (final file in files) {
        if (file.bytes != null) {
          request.files.add(http.MultipartFile.fromBytes(
            'departure_files[]',
            file.bytes!,
            filename: file.name,
          ));
        } else if (file.path != null) {
          request.files.add(await http.MultipartFile.fromPath(
            'departure_files[]',
            file.path!,
            filename: file.name,
          ));
        }
      }

      final response = await request.send().timeout(const Duration(seconds: 120));
      final body = await response.stream.bytesToString();
      final data = jsonDecode(body) as Map<String, dynamic>? ?? {};

      if (response.statusCode != 200 || !(data['success'] ?? false)) {
        throw Exception('Upload failed: ${data['error'] ?? 'Unknown error'}');
      }

      final docId = data['doc_id'] as String?;
      if (docId == null) throw Exception('No doc_id returned from backend.');
      logger.i('✅ Upload successful – Doc ID: $docId');

      return {'docId': docId, 'sheets': data['sheets'] ?? {}};
    }, 3);
  }

  // ---------------------------------------------------------------------------
  // 2️⃣ Analyze base file (/analyze)
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> analyzeData(PlatformFile baseFile) async {
    if (baseFile.bytes == null && baseFile.path == null) {
      throw Exception('Invalid base file format.');
    }

    final uri = Uri.parse('${AppConfig.analyzeURL}');
    return await _retryRequest(() async {
      final request = http.MultipartRequest('POST', uri);
      if (baseFile.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes('base_file', baseFile.bytes!, filename: baseFile.name));
      } else {
        request.files.add(await http.MultipartFile.fromPath('base_file', baseFile.path!, filename: baseFile.name));
      }

      final response = await request.send().timeout(const Duration(seconds: 90));
      final body = await response.stream.bytesToString();
      final data = jsonDecode(body) as Map<String, dynamic>? ?? {};

      if (response.statusCode != 200 || !(data['success'] ?? false)) {
        throw Exception('Analysis failed: ${data['error'] ?? 'Unknown error'}');
      }

      final docId = data['doc_id'] ?? 'temp_${DateTime.now().millisecondsSinceEpoch}';
      logger.i('✅ Analysis complete – Doc ID: $docId');

      final sheets = data['sheets'] as Map<String, dynamic>? ?? {};
      final parsedSheets = <String, model.AnalysisData>{};
      for (var entry in sheets.entries) {
        parsedSheets[entry.key] = model.AnalysisData.fromJson(entry.value);
      }

      return {'docId': docId, 'analysisResult': parsedSheets};
    }, 3);
  }

  // ---------------------------------------------------------------------------
  // 3️⃣ Download PDF (/download_dashboard_pdf)
  // ---------------------------------------------------------------------------
  Future<Uint8List> downloadPDF(String docId) async {
    if (docId.isEmpty) throw Exception('Invalid doc_id.');
    final uri = Uri.parse('${AppConfig.generatePdfURL}?doc_id=$docId');

    return await _retryRequest(() async {
      final response = await http.get(uri).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        throw Exception('Failed to download PDF (${response.statusCode}): ${response.body}');
      }
      if (response.bodyBytes.isEmpty) {
        throw Exception('Received empty PDF data.');
      }

      logger.i('✅ PDF downloaded successfully for $docId');
      return response.bodyBytes;
    }, 3);
  }

  // ---------------------------------------------------------------------------
  // 4️⃣ Fetch analysis summary (/search)
  // ---------------------------------------------------------------------------
  Future<Map<String, Map<String, int>>> fetchAnalysisData(String docId) async {
    if (docId.isEmpty) throw Exception('Invalid doc_id.');
    final uri = Uri.parse('${AppConfig.searchURL}?doc_id=$docId');

    final response = await _retryRequest(() => http.get(uri).timeout(const Duration(seconds: 60)), 3);
    if (response.statusCode != 200) throw Exception('Fetch failed: ${response.body}');

    final List<dynamic> data = jsonDecode(response.body);
    final result = <String, Map<String, int>>{};
    for (var entry in data) {
      final regNo = entry['Reg_No'] ?? 'N/A';
      final date = entry['Arr_Date'] ?? 'N/A';
      final count = entry['Count'] ?? 0;
      result.putIfAbsent(regNo, () => {})[date] = count;
    }

    logger.i('✅ Analysis data fetched for ${result.length} aircrafts');
    return result;
  }

  // ---------------------------------------------------------------------------
  // 5️⃣ Fetch aggregated stats (/stats)
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> fetchStatsData(String docId, String groupBy) async {
    if (docId.isEmpty) throw Exception('Invalid doc_id.');

    final uri = Uri.parse('${AppConfig.statsURL}?doc_id=$docId&group_by=$groupBy');
    final response = await _retryRequest(() => http.get(uri).timeout(const Duration(seconds: 60)), 3);
    if (response.statusCode != 200) throw Exception('Failed to fetch stats: ${response.body}');

    final List<dynamic> data = jsonDecode(response.body);
    final stats = data.map((e) => {
          'Group_Name': e['Operator_Name'] ?? e['Region'] ?? 'N/A',
          'Flight_Count': e['Flight_Count'] ?? 0,
          'Avg_Airtime_Hours': e['Avg_Airtime_Hours'] ?? '0.0',
          'Region': e['Region'] ?? 'N/A',
        }).toList();

    logger.i('✅ Stats fetched for ${stats.length} entries');
    return stats;
  }

  // ---------------------------------------------------------------------------
  // 6️⃣ Search flights with filters (/search)
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> searchFlights(String docId, Map<String, String> queryParams) async {
    if (docId.isEmpty) throw Exception('Invalid doc_id.');

    final uri = Uri.parse(AppConfig.searchURL).replace(queryParameters: {'doc_id': docId, ...queryParams});
    final response = await _retryRequest(() => http.get(uri).timeout(const Duration(seconds: 60)), 3);

    if (response.statusCode != 200) throw Exception('Search failed: ${response.body}');
    final List<dynamic> data = jsonDecode(response.body);

    logger.i('✅ Search returned ${data.length} results');
    return List<Map<String, dynamic>>.from(data);
  }
}
