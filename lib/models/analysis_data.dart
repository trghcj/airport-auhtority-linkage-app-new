import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:airport_auhtority_linkage_app/config/config.dart';

// Custom exception for analysis-related errors
class AnalysisException implements Exception {
  final String message;
  AnalysisException(this.message);

  @override
  String toString() => 'AnalysisException: $message';
}

class AnalysisData {
  /// The name of the sheet from which the data is derived.
  final String sheetName;

  /// List of column headers for the data table.
  final List<String> columns;

  /// List of rows, where each row is a map of column names to dynamic values.
  final List<Map<String, dynamic>> rows;

  /// Statistical data associated with the sheet (e.g., totals, averages).
  final Map<String, dynamic> stats;

  /// Base64-encoded string representing a bar chart image (to be decoded and rendered in UI).
  String chartBar;

  /// Base64-encoded string representing a pie chart image (to be decoded and rendered in UI).
  String chartPie;

  /// Formal textual summary of the analysis results.
  final String formalSummary;

  /// Unique document ID generated during upload or analysis.
  final String docId;

  /// Dynamic current date and time (updated to 01:29 AM IST, August 18, 2025)
  static final DateTime _currentDate = DateTime(2025, 8, 18, 1, 29, 0, 0, 19800);

  /// Creates an AnalysisData object with required fields and optional defaults.
  AnalysisData({
    required this.sheetName,
    required this.columns,
    required this.rows,
    required this.stats,
    this.chartBar = '',
    this.chartPie = '',
    this.formalSummary = '',
    required this.docId,
  }) {
    if (docId.isEmpty) {
      throw AnalysisException('docId is required and cannot be empty in sheet: $sheetName at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
    }
    // Validate columns and rows consistency
    if (columns.isEmpty) {
      logger.w('Empty columns list detected for sheet: $sheetName at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}, using default column');
      columns.add('DefaultColumn');
    }
    if (rows.any((row) => row.keys.any((key) => !columns.contains(key)))) {
      logger.w('Row keys do not match columns for sheet: $sheetName at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}, adjusting rows');
      for (var row in rows) {
        row.removeWhere((key, value) => !columns.contains(key));
      }
    }
    // Validate chart fields with optimized Base64 check
    if (chartBar.isNotEmpty && !_isValidBase64(chartBar)) {
      logger.w('Invalid Base64 string for chartBar in sheet: $sheetName at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}, resetting to empty');
      chartBar = '';
    }
    if (chartPie.isNotEmpty && !_isValidBase64(chartPie)) {
      logger.w('Invalid Base64 string for chartPie in sheet: $sheetName at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}, resetting to empty');
      chartPie = '';
    }
  }

  /// Converts the AnalysisData object to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    try {
      return {
        'sheetName': sheetName,
        'columns': List<String>.from(columns), // Ensure immutable copy
        'rows': rows.map((row) => Map<String, dynamic>.from(row)).toList(), // Deep copy
        'stats': Map<String, dynamic>.from(stats), // Deep copy
        'chartBar': chartBar,
        'chartPie': chartPie,
        'formalSummary': formalSummary,
        'docId': docId,
      };
    } catch (e, stackTrace) {
      logger.e('Failed to convert AnalysisData to JSON: $e\nStackTrace: $stackTrace at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      throw AnalysisException('Failed to serialize analysis data for sheet: $sheetName, error: ${e.toString()}');
    }
  }

  /// Creates an AnalysisData object from a JSON map, handling various key formats and missing data.
  factory AnalysisData.fromJson(Map<String, dynamic> json) {
    try {
      // Handle sheetName with multiple possible keys
      final sheetName = _getStringValue(json, ['sheet_name', 'sheetName']) ?? 'Unknown Sheet';

      // Handle columns, ensuring a non-empty list with fallback
      final columnsJson = json['columns'] as List<dynamic>? ?? [];
      final columns = columnsJson
          .map((e) => _getStringValue({'value': e}, ['value']) ?? 'Unknown')
          .where((e) => e.isNotEmpty)
          .toList();
      if (columns.isEmpty) {
        logger.w('No valid columns found, using default column at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
        columns.add('DefaultColumn');
      }

      // Handle rows, processing nested data with stricter type checking and Airtime_Hours calculation
      final rowData = json['rows'] as List<dynamic>? ?? [];
      final rows = rowData
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final row = Map<String, dynamic>.fromEntries(item.entries.where((e) => e.value != null));
            // Handle Airtime_Hours with support for both serial dates and ISO strings
            final arrDate = _parseDate(row['Arr_Date'], row['Arr_GMT'] as String?);
            final depDate = _parseDate(row['Dep_Date'], row['Dep_GMT'] as String?);
            row['Airtime_Hours'] = (arrDate != null && depDate != null)
                ? '${(depDate.difference(arrDate).abs().inMinutes / 60.0).toStringAsFixed(2)} hours'
                : row['Airtime_Hours'] ?? 'N/A';
            // Format charges
            row['Landing'] = '₹${(double.tryParse(row['Landing']?.toString() ?? '0.0') ?? 0.0).toStringAsFixed(2)}';
            row['UDF_Charge'] = '₹${(double.tryParse(row['UDF_Charge']?.toString() ?? '0.0') ?? 0.0).toStringAsFixed(2)}';
            // Standardize bill statuses
            row['Arr_Bill_Status'] = (row['Arr_Bill_Status']?.toString().toLowerCase() ?? '').contains('billed') ? 'Yes' : 'No';
            row['Dep_Bill_Status'] = (row['Dep_Bill_Status']?.toString().toLowerCase() ?? '').contains('billed') ? 'Yes' : 'No';
            row['UDF_Bill_Status'] = (row['UDF_Bill_Status']?.toString().toLowerCase() ?? '').contains('billed') ? 'Yes' : 'No';
            return row;
          })
          .where((row) => row.isNotEmpty)
          .toList();
      if (rows.isEmpty) {
        logger.w('No valid rows found, using default row at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
        rows.add({'DefaultColumn': 'N/A'});
      }

      // Handle stats, preserving numeric and string types with validation
      final statsJson = json['stats'] as Map<dynamic, dynamic>? ?? {};
      final stats = <String, dynamic>{};
      statsJson.forEach((key, value) {
        final keyStr = key.toString();
        if (value is num) {
          stats[keyStr] = value;
        } else if (value is String) {
          stats[keyStr] = value;
        } else if (value != null) {
          stats[keyStr] = value.toString();
          logger.w('Converted non-numeric/string value to string for key: $keyStr, value: $value at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
        }
      });
      if (stats.isEmpty) {
        logger.w('No valid stats found, using default at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
        stats['total_records'] = 0;
      }

      // Handle chart and summary fields with fallbacks and validation
      var chartBar = _getStringValue(json, ['chart_bar', 'chartBar']) ?? '';
      if (chartBar.isNotEmpty && !_isValidBase64(chartBar)) {
        logger.w('Invalid Base64 string for chartBar in sheet: $sheetName at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}, resetting to empty');
        chartBar = '';
      }
      var chartPie = _getStringValue(json, ['chart_pie', 'chartPie']) ?? '';
      if (chartPie.isNotEmpty && !_isValidBase64(chartPie)) {
        logger.w('Invalid Base64 string for chartPie in sheet: $sheetName at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}, resetting to empty');
        chartPie = '';
      }
      final formalSummary = _getStringValue(json, ['formal_summary', 'formalSummary']) ?? '';
      final docId = _getStringValue(json, ['doc_id', 'docId']) ?? '';

      if (docId.isEmpty) {
        throw AnalysisException('docId is required and cannot be empty in sheet: $sheetName at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      }

      return AnalysisData(
        sheetName: sheetName,
        columns: columns,
        rows: rows,
        stats: stats,
        chartBar: chartBar,
        chartPie: chartPie,
        formalSummary: formalSummary,
        docId: docId,
      );
    } catch (e, stackTrace) {
      logger.e('Failed to parse AnalysisData from JSON: $e\nStackTrace: $stackTrace at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      throw AnalysisException('Failed to parse analysis data for sheet: ${json['sheetName'] ?? 'Unknown'}, error: ${e.toString()}');
    }
  }

  /// Helper method to safely get a string value from a map with multiple possible keys.
  static String? _getStringValue(Map<String, dynamic> map, List<String> keys) {
    for (var key in keys) {
      final value = map[key];
      if (value is String) return value;
    }
    return null;
  }

  /// Helper method to check if a string is a valid Base64-encoded string.
  static bool _isValidBase64(String str) {
    try {
      base64Decode(str);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Helper method to parse date from either Excel serial or ISO string format.
  static DateTime? _parseDate(dynamic dateValue, String? hhmmStr) {
    if (dateValue == null) return null;
    if (dateValue is num) {
      return _parseExcelSerialDate(dateValue, hhmmStr);
    } else if (dateValue is String) {
      try {
        return DateTime.parse(dateValue).toUtc();
      } catch (e) {
        logger.w('Failed to parse ISO date $dateValue: $e at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
        return null;
      }
    }
    return null;
  }

  /// Helper method to parse Excel serial date with HHMM support, aligned with Flask backend
  static DateTime? _parseExcelSerialDate(dynamic serialNum, String? hhmmStr) {
    if (serialNum == null || serialNum is! num || serialNum < 0 || serialNum > 1e6) {
      logger.w('Invalid serial number: $serialNum at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      return null;
    }
    try {
      final baseDate = DateTime(1899, 12, 30);
      final date = baseDate.add(Duration(days: serialNum.toInt()));
      if (hhmmStr != null && hhmmStr.isNotEmpty) {
        final hhmmNormalized = hhmmStr.replaceAll(':', '');
        if (RegExp(r'^\d{4}$').hasMatch(hhmmNormalized)) {
          final hours = int.parse(hhmmNormalized.substring(0, 2));
          final minutes = int.parse(hhmmNormalized.substring(2, 4));
          if (hours >= 0 && hours <= 23 && minutes >= 0 && minutes <= 59) {
            return date.add(Duration(hours: hours, minutes: minutes)).toUtc();
          } else {
            logger.w('Invalid HHMM $hhmmStr, using 00:00 at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
            return date.toUtc();
          }
        } else {
          logger.w('Non-numeric or invalid HHMM $hhmmStr, using 00:00 at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
          return date.toUtc();
        }
      }
      return date.toUtc();
    } catch (e) {
      logger.w('Error parsing serial date $serialNum with HHMM $hhmmStr: $e at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      return null;
    }
  }

  /// Creates an empty AnalysisData object with default values.
  static AnalysisData empty() {
    return AnalysisData(
      sheetName: 'Empty Sheet',
      columns: ['DefaultColumn'],
      rows: [{'DefaultColumn': 'N/A'}],
      stats: {'total_records': 0},
      chartBar: '',
      chartPie: '',
      formalSummary: 'No data processed',
      docId: 'empty_doc_id_${_currentDate.millisecondsSinceEpoch}',
    );
  }

  // Static Logger instance for logging warnings and errors
  static final Logger logger = Logger();
}