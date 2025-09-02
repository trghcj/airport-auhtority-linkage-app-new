import 'package:airport_auhtority_linkage_app/services/analysis_service.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:file_picker/file_picker.dart';
import 'package:airport_auhtority_linkage_app/models/analysis_data.dart' as model;
import 'package:airport_auhtority_linkage_app/config/config.dart';

class SearchProvider with ChangeNotifier {
  final Logger logger = Logger();
  final AnalysisService analysisService = AnalysisService();
  final Map<String, Map<String, dynamic>> _flightData = {}; // Stores flight data by Reg No
  bool _isLoading = false;
  String? _status;

  Map<String, Map<String, dynamic>> get flightData => Map.unmodifiable(_flightData); // Immutable getter
  bool get isLoading => _isLoading;
  String? get status => _status;

  Future<void> fetchRegistrations(List<PlatformFile> files) async {
    // Validate input
    if (files.isEmpty) {
      _status = '❌ No files selected for upload.';
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _status = 'Starting data processing...';
    notifyListeners();

    try {
      // Validate file sizes (50MB limit per file)
      for (final file in files) {
        if (file.size > 50 * 1024 * 1024) {
          throw Exception('File ${file.name} exceeds 50MB limit.');
        }
      }

      // Upload files to get doc_id
      _status = 'Uploading files...';
      notifyListeners();
      final uploadResponse = await analysisService.uploadFiles(files).timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw Exception('Upload timed out after 60 seconds.'),
          );
      final docId = uploadResponse['docId'] as String?;

      if (docId == null || docId.isEmpty) {
        _status = '⚠️ Upload failed: Invalid or missing Doc ID. Check file format (e.g., missing Operator_Name).';
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Fetch detailed analysis data using the doc_id
      _status = 'Fetching registration data...';
      notifyListeners();
      final rawData = await analysisService.fetchAnalysisData(docId).timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw Exception('Fetch timed out after 60 seconds.'),
          );

      // Process raw data into flightData with detailed fields
      _flightData.clear();
      for (var entry in rawData.entries) {
        final sheetData = entry.value as model.AnalysisData;
        final rows = sheetData.rows;

        for (var row in rows) {
          final regNo = (row['Reg_No']?.toString().trim().toLowerCase() ?? 'unknown').isEmpty ? 'unknown' : row['Reg_No']?.toString().trim().toLowerCase() ?? 'unknown';
          if (regNo == 'unknown') continue; // Skip invalid or empty Reg Nos

          _flightData[regNo] = _flightData[regNo] ?? {
            'Reg_No': regNo,
            'Operator_Name': row['Operator_Name']?.toString() ?? 'Unknown',
            'Aircraft_Type': row['Aircraft_Type']?.toString() ?? 'Unknown',
            'Arr_Date': row['Arr_Local'] != null
                ? DateTime.parse(row['Arr_Local'].toString()).toLocal().toString().split(' ')[0]
                : 'Unknown',
            'Dep_Date': row['Dep_Local'] != null
                ? DateTime.parse(row['Dep_Local'].toString()).toLocal().toString().split(' ')[0]
                : 'Unknown',
            'Arr_Bill_Status': row['Arr_Bill_Status']?.toString() ?? 'unbilled',
            'Dep_Bill_Status': row['Dep_Bill_Status']?.toString() ?? 'unbilled',
            'UDF_Bill_Status': row['UDF_Bill_Status']?.toString() ?? 'unbilled',
            'Linkage_Status': row['Linkage_Status']?.toString() ?? 'Unknown',
            'Airtime_Hours': row['Airtime_Hours']?.toString() ?? '0.0',
            'Count': 0, // Initialize count
          };

          // Update count if multiple entries for the same Reg No
          _flightData[regNo]!['Count'] = (_flightData[regNo]!['Count'] as int) + 1;
        }
      }

      _status = '✅ Registration data loaded for ${_flightData.length} aircraft.';
      logger.d('Loaded registrations for ${_flightData.length} aircraft at ${DateTime(2025, 8, 3, 2, 44, 0).toIso8601String()}');
    } catch (e) {
      _status = e.toString().contains('Upload failed')
          ? '❌ Upload failed: ${e.toString().replaceAll('Exception: Upload failed: ', '')}'
          : e.toString().contains('Failed to fetch analysis data')
              ? '❌ Fetch failed: ${e.toString().replaceAll('Exception: Failed to fetch analysis data: ', '')}'
              : e.toString().contains('exceeds 50MB limit')
                  ? '❌ ${e.toString()}'
                  : e.toString().contains('timed out')
                      ? '❌ ${e.toString()}'
                      : '❌ Unexpected error: ${e.toString()}';
      logger.e('Error fetching registrations: $e at ${DateTime(2025, 8, 3, 2, 44, 0).toIso8601String()}');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clears the current registrations and status.
  void clearData() {
    _flightData.clear();
    _status = null;
    notifyListeners();
  }
}