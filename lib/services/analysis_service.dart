import 'dart:convert';
import 'package:airport_auhtority_linkage_app/config/config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:logger/logger.dart';
import 'package:airport_auhtority_linkage_app/models/analysis_data.dart' as model;
import 'package:intl/intl.dart'; // For IST formatting
import 'dart:async'; // For retry logic

class AnalysisService {
  final Logger logger = Logger();
  static final DateTime _currentDate = DateTime(2025, 8, 24, 4, 35, 0, 0, 19800); // 04:35 AM IST, August 24, 2025

  // Date parsing aligned with Flask backend's parse_excel_serial_date
  DateTime? _parseExcelSerialDate(dynamic serialNum, String? hhmmStr, String fieldName) {
    if (serialNum == null || serialNum is! num || serialNum < 0 || serialNum > 1e6) {
      logger.w('Invalid serial number for $fieldName: $serialNum at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      return null;
    }
    try {
      final baseDate = DateTime(1899, 12, 30);
      final date = baseDate.add(Duration(days: serialNum.toInt()));
      if (hhmmStr != null && hhmmStr.isNotEmpty) {
        final hhmmNormalized = hhmmStr.replaceAll(':', '').replaceAll(RegExp(r'[^0-9]'), '');
        if (hhmmNormalized.length == 4 && int.tryParse(hhmmNormalized) != null) {
          final hours = int.parse(hhmmNormalized.substring(0, 2));
          final minutes = int.parse(hhmmNormalized.substring(2, 4));
          if (hours >= 0 && hours <= 23 && minutes >= 0 && minutes <= 59) {
            return date.add(Duration(hours: hours, minutes: minutes)).toUtc();
          } else {
            logger.w('Invalid HHMM for $fieldName: $hhmmStr, using 00:00 at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
            return date.toUtc();
          }
        } else {
          logger.w('Non-numeric or invalid HHMM for $fieldName: $hhmmStr, using 00:00 at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
          return date.toUtc();
        }
      }
      return date.toUtc();
    } catch (e) {
      logger.w('Error parsing serial date for $fieldName: $serialNum with HHMM $hhmmStr, error: $e at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      return null;
    }
  }

  // Retry logic for network requests with fresh request creation
  Future<T> _retryRequest<T>(Future<T> Function() request, int maxAttempts) async {
    const retryDelay = Duration(seconds: 2);
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await request();
      } catch (e) {
        if (attempt == maxAttempts) rethrow;
        logger.w('Retry attempt $attempt failed: $e at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}, retrying in ${retryDelay * attempt}');
        await Future.delayed(retryDelay * attempt);
      }
    }
    throw Exception('Max retry attempts reached');
  }

  /// Uploads departure files to generate a doc_id.
  Future<Map<String, dynamic>> uploadFiles(List<PlatformFile> files) async {
    if (files.isEmpty) {
      logger.e('No files selected for upload at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      throw Exception('Please select at least one departure file.');
    }

    final departureFile = files[0];
    if (files.length > 1) {
      logger.w('Only the first file will be uploaded as departure_file; additional files ignored at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}.');
    }

    if (departureFile.size > 50 * 1024 * 1024) {
      logger.e('File size exceeds 50MB limit for ${departureFile.name} at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      throw Exception('Departure file size exceeds 50MB limit.');
    }

    logger.d('Uploading file: ${departureFile.name} at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');

    final uri = Uri.parse('${AppConfig.baseURL}/upload');
    return await _retryRequest(() async {
      final request = http.MultipartRequest('POST', uri);

      if (departureFile.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'departure_file',
          departureFile.bytes!,
          filename: departureFile.name,
        ));
      } else if (departureFile.path != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'departure_file',
          departureFile.path!,
          filename: departureFile.name,
        ));
      } else {
        logger.e('Invalid departure file format or data for ${departureFile.name} at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
        throw Exception('Invalid departure file format or data.');
      }

      final response = await request.send().timeout(const Duration(seconds: 60));
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody) as Map<String, dynamic>? ?? {};

      if (response.statusCode != 200 || !(responseData['success'] as bool? ?? false)) {
        logger.e('Upload failed: ${responseData['error'] ?? 'Unknown error'}, Status: ${response.statusCode}, Response: $responseBody at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
        throw Exception('Upload failed: ${responseData['error'] ?? 'Unknown error (Check Operator_Name in row 1)'}');
      }

      final docId = responseData['doc_id'] as String?;
      final sheets = responseData['sheets'] as Map<String, dynamic>? ?? {};
      if (docId == null) {
        logger.e('No doc_id returned from server for ${departureFile.name} at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
        throw Exception('No doc_id returned from server');
      }

      logger.d('Upload completed with doc_id: $docId at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      return {'docId': docId, 'sheets': sheets};
    }, 3);
  }

  /// Analyzes a base file and returns analysis data with doc_id.
  Future<Map<String, dynamic>> analyzeData(PlatformFile baseFile) async {
    if (baseFile.size > 50 * 1024 * 1024) {
      logger.e('File size exceeds 50MB limit for ${baseFile.name} at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      throw Exception('Base file size exceeds 50MB limit.');
    }

    logger.d('Analyzing file: ${baseFile.name} at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');

    final uri = Uri.parse('${AppConfig.baseURL}/analyze');
    return await _retryRequest(() async {
      final request = http.MultipartRequest('POST', uri);

      if (baseFile.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'base_file',
          baseFile.bytes!,
          filename: baseFile.name,
        ));
      } else if (baseFile.path != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'base_file',
          baseFile.path!,
          filename: baseFile.name,
        ));
      } else {
        logger.e('Invalid base file format or data for ${baseFile.name} at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
        throw Exception('Invalid base file format or data.');
      }

      final response = await request.send().timeout(const Duration(seconds: 60));
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody) as Map<String, dynamic>? ?? {};

      if (response.statusCode != 200 || !(responseData['success'] as bool? ?? false)) {
        logger.e('Analysis failed: ${responseData['error'] ?? 'Unknown error'}, Status: ${response.statusCode}, Response: $responseBody at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
        throw Exception('Analysis failed: ${responseData['error'] ?? 'Unknown error (Check Customer_Name in row 1)'}');
      }

      var docId = responseData['doc_id'] as String?;
      final sheets = responseData['sheets'] as Map<String, dynamic>? ?? {};
      final analysisResult = <String, model.AnalysisData>{};
      for (var entry in sheets.entries) {
        try {
          analysisResult[entry.key] = model.AnalysisData.fromJson(entry.value as Map<String, dynamic>);
        } catch (e) {
          logger.w('Failed to parse sheet ${entry.key}: $e at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}, using empty data');
          analysisResult[entry.key] = model.AnalysisData.empty();
        }
      }

      for (var sheet in analysisResult.values) {
        for (var row in sheet.rows) {
          final arrDate = row['Arr_Date'] as dynamic;
          final depDate = row['Dep_Date'] as dynamic;
          final arrGmt = _parseExcelSerialDate(arrDate, row['Arr_GMT'] as String?, 'Arr_GMT');
          final depGmt = _parseExcelSerialDate(depDate, row['Dep_GMT'] as String?, 'Dep_GMT');
          if (arrGmt != null && depGmt != null) {
            final difference = depGmt.difference(arrGmt).abs();
            row['Airtime_Hours'] = '${(difference.inMinutes / 60.0).toStringAsFixed(2)} hours';
          } else {
            row['Airtime_Hours'] = 'N/A';
          }

          row['Arr_Bill_Status'] = (row['Arr_Bill_Status']?.toString().toLowerCase() ?? '').contains('billed') ? 'Yes' : 'No';
          row['Dep_Bill_Status'] = (row['Dep_Bill_Status']?.toString().toLowerCase() ?? '').contains('billed') ? 'Yes' : 'No';
          row['UDF_Bill_Status'] = (row['UDF_Bill_Status']?.toString().toLowerCase() ?? '').contains('billed') ? 'Yes' : 'No';

          row['Landing'] = '₹${(double.tryParse(row['Landing']?.toString() ?? '0.0') ?? 0.0).toStringAsFixed(2)}';
          row['UDF_Charge'] = '₹${(double.tryParse(row['UDF_Charge']?.toString() ?? '0.0') ?? 0.0).toStringAsFixed(2)}';
        }
      }

      if (docId == null) {
        logger.w('No doc_id returned from analyzeData, generating temporary ID for ${baseFile.name} at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
        docId = 'temp_${_currentDate.millisecondsSinceEpoch}';
      }

      logger.d('Analysis completed with doc_id: $docId for ${analysisResult.length} sheets at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      return {'docId': docId, 'analysisResult': analysisResult};
    }, 3);
  }

  /// Downloads a PDF dashboard for the given doc_id with improved error handling.
  Future<Uint8List> downloadPDF(String docId) async {
    if (docId.isEmpty) {
      logger.e('No doc_id provided for PDF download at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      throw Exception('No document ID available for PDF download.');
    }

    try {
      final uri = Uri.parse('${AppConfig.baseURL}/download_dashboard_pdf?doc_id=$docId');
      final response = await _retryRequest(() => http.get(uri).timeout(const Duration(seconds: 60)), 3);

      if (response.statusCode != 200) {
        logger.e('PDF download failed: Status ${response.statusCode}, Body: ${response.body} at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
        final errorDetails = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
        if (response.statusCode == 500 && errorDetails['details']?.contains('pdflatex') == true) {
          const logPath = 'C:\\Users\\suremdra singh\\AppData\\Local\\MiKTeX\\miktex\\log\\pdflatex.log';
          logger.e('PDF generation failed: Server-side LaTeX error. Check log at $logPath on the server or contact support.');
          throw Exception('PDF generation failed: Server-side LaTeX error. Check log at $logPath or contact support.');
        }
        throw Exception('PDF download failed: Status ${response.statusCode}, ${errorDetails['error'] ?? response.body}');
      }

      if (response.bodyBytes.isEmpty) {
        logger.e('Empty PDF data received for docId: $docId at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
        throw Exception('No PDF data available for this document.');
      }

      logger.d('PDF downloaded successfully for docId: $docId at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      return response.bodyBytes;
    } catch (e, stackTrace) {
      logger.e('Error downloading PDF: $e, StackTrace: $stackTrace at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      throw Exception('PDF download failed: ${e.toString()}');
    }
  }

  /// Fetches pre-analyzed registration data per day for a given doc_id.
  Future<Map<String, Map<String, int>>> fetchAnalysisData(String docId) async {
    if (docId.isEmpty) {
      logger.e('No doc_id provided for fetching analysis data at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      throw Exception('No document ID available. Please upload a file first.');
    }

    logger.d('Fetching analysis data for docId: $docId at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');

    final uri = Uri.parse('${AppConfig.baseURL}/search?doc_id=$docId');
    final response = await _retryRequest(() => http.get(uri).timeout(const Duration(seconds: 60)), 3);

    try {
      if (response.statusCode != 200) {
        logger.e('Fetch failed: Status ${response.statusCode}, Body: ${response.body} at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
        throw Exception('Failed to fetch analysis data: Status ${response.statusCode}, ${response.body}');
      }

      final responseData = jsonDecode(response.body) as List<dynamic>? ?? [];
      final registrationsPerDay = <String, Map<String, int>>{};
      for (var item in responseData) {
        final regNo = item['Reg_No'] as String? ?? 'N/A';
        final date = item['Arr_Date'] as String? ?? 'N/A';
        final count = item['Count'] as int? ?? 0;
        registrationsPerDay.putIfAbsent(regNo, () => {})[date] = count;
      }

      logger.d('Fetched registration data for ${registrationsPerDay.length} aircraft at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      return registrationsPerDay;
    } catch (e, stackTrace) {
      logger.e('Error fetching analysis data: $e, StackTrace: $stackTrace at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      throw Exception('Failed to fetch analysis data: ${e.toString()}');
    }
  }

  /// Fetches aggregated statistics for a given doc_id, grouped by operator or region.
  Future<List<Map<String, dynamic>>> fetchStatsData(String docId, String groupBy) async {
    if (docId.isEmpty) {
      logger.e('No doc_id provided for fetching stats data at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      throw Exception('No document ID available. Please upload a file first.');
    }

    logger.d('Fetching stats data for docId: $docId, groupBy: $groupBy at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');

    final uri = Uri.parse('${AppConfig.baseURL}/stats')
        .replace(queryParameters: {'doc_id': docId, 'group_by': groupBy});
    final response = await _retryRequest(() => http.get(uri).timeout(const Duration(seconds: 60)), 3);

    try {
      if (response.statusCode != 200) {
        logger.e('Stats fetch failed: Status ${response.statusCode}, Body: ${response.body} at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
        throw Exception('Failed to fetch stats: Status ${response.statusCode}, ${response.body}');
      }

      final responseData = jsonDecode(response.body) as List<dynamic>? ?? [];
      final stats = responseData.map((item) {
        final groupName = item['Operator_Name'] ?? (groupBy == 'region' ? item['Region'] : 'N/A');
        return {
          'Group_Name': groupName,
          'Customer_Name': item['Customer_Name'] ?? 'N/A',
          'Flight_Count': int.tryParse(item['Flight_Count']?.toString() ?? '0') ?? 0,
          'Avg_Airtime_Hours': double.tryParse(item['Avg_Airtime_Hours']?.toString() ?? '0.0')?.toStringAsFixed(2) ?? '0.0',
          'Same_Linkage_Count': int.tryParse(item['Same_Linkage_Count']?.toString() ?? '0') ?? 0,
          'Different_Linkage_Count': int.tryParse(item['Different_Linkage_Count']?.toString() ?? '0') ?? 0,
          'Arr_Billed_Count': int.tryParse(item['Arr_Billed_Count']?.toString() ?? '0') ?? 0,
          'Arr_UnBilled_Count': int.tryParse(item['Arr_UnBilled_Count']?.toString() ?? '0') ?? 0,
          'Dep_Billed_Count': int.tryParse(item['Dep_Billed_Count']?.toString() ?? '0') ?? 0,
          'Dep_UnBilled_Count': int.tryParse(item['Dep_UnBilled_Count']?.toString() ?? '0') ?? 0,
          'UDF_Billed_Count': int.tryParse(item['UDF_Billed_Count']?.toString() ?? '0') ?? 0,
          'UDF_UnBilled_Count': int.tryParse(item['UDF_UnBilled_Count']?.toString() ?? '0') ?? 0,
          'Total_Landing_Charges': '₹${(double.tryParse(item['Total_Landing_Charges']?.toString() ?? '0.0') ?? 0.0).toStringAsFixed(2)}',
          'Total_UDF_Charges': '₹${(double.tryParse(item['Total_UDF_Charges']?.toString() ?? '0.0') ?? 0.0).toStringAsFixed(2)}',
          'Region': item['Region'] ?? 'N/A',
        };
      }).toList();

      logger.d('Fetched stats data for ${stats.length} entries at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      return stats;
    } catch (e, stackTrace) {
      logger.e('Error fetching stats data: $e, StackTrace: $stackTrace at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      throw Exception('Failed to fetch stats data: ${e.toString()}');
    }
  }

  /// Searches flights with filters for a given doc_id with pagination.
  Future<List<Map<String, dynamic>>> searchFlights(String docId, Map<String, String> queryParams) async {
    if (docId.isEmpty) {
      logger.e('No doc_id provided for search at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      throw Exception('No document ID available. Please upload a file first.');
    }

    final page = int.tryParse(queryParams['page'] ?? '0') ?? 0;
    final limit = int.tryParse(queryParams['limit'] ?? '100') ?? 100;
    logger.d('Searching flights for docId: $docId, page: $page, limit: $limit, params: ${queryParams['query']} at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');

    final uri = Uri.parse('${AppConfig.baseURL}/search')
        .replace(queryParameters: {'doc_id': docId, 'page': page.toString(), 'limit': limit.toString(), ...queryParams});
    final response = await _retryRequest(() => http.get(uri).timeout(const Duration(seconds: 60)), 3);

    try {
      if (response.statusCode != 200) {
        logger.e('Search failed: Status ${response.statusCode}, Body: ${response.body} at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
        throw Exception('Failed to search flights: Status ${response.statusCode}, ${response.body}');
      }

      final responseData = jsonDecode(response.body) as List<dynamic>? ?? [];
      final results = responseData.map((item) {
        final regNo = item['Reg_No'] as String? ?? 'N/A';
        final arrDate = item['Arr_Date'] as String? ?? 'N/A';
        final count = item['Count']?.toString() ?? '1';
        return {
          'Reg No': regNo,
          'Date': arrDate,
          'Count': count,
          'Unique Id': item['Unique_Id'] as String? ?? 'N/A',
          'Operator Name': item['Operator_Name'] as String? ?? 'N/A',
          'Aircraft Type': item['Aircraft_Type'] as String? ?? 'N/A',
          'Airtime Hours': item['Airtime_Hours'] as String? ?? 'N/A',
          'Linkage Status': item['Linkage_Status'] as String? ?? 'N/A',
          'Arr Bill Status': item['Arr_Bill_Status'] as String? ?? 'N/A',
          'Dep Bill Status': item['Dep_Bill_Status'] as String? ?? 'N/A',
          'UDF Bill Status': item['UDF_Bill_Status'] as String? ?? 'N/A',
          'Landing': item['Landing'] != null ? '₹${(double.tryParse(item['Landing'].toString()) ?? 0.0).toStringAsFixed(2)}' : '₹0.00',
          'UDF Charge': item['UDF_Charge'] != null ? '₹${(double.tryParse(item['UDF_Charge'].toString()) ?? 0.0).toStringAsFixed(2)}' : '₹0.00',
        };
      }).toList();

      logger.d('Fetched ${results.length} search results at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      return results;
    } catch (e, stackTrace) {
      logger.e('Error searching flights: $e, StackTrace: $stackTrace at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      throw Exception('Failed to search flights: ${e.toString()}');
    }
  }
}