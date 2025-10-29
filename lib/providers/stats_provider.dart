import 'package:airport_auhtority_linkage_app/services/analysis_service.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:file_picker/file_picker.dart';
import 'package:airport_auhtority_linkage_app/models/analysis_data.dart' as model;
import 'package:airport_auhtority_linkage_app/config/config.dart';

class StatsProvider with ChangeNotifier {
  final Logger logger = Logger();
  final AnalysisService analysisService = AnalysisService();
  final Map<String, Map<String, dynamic>> _statsData = {}; // Stores stats by group (e.g., operator or region)
  bool _isLoading = false;
  String? _status;
  Map<String, dynamic>? _uploadData; // Stores raw response for potential use

  Map<String, Map<String, dynamic>> get statsData => Map.unmodifiable(_statsData); // Immutable getter
  bool get isLoading => _isLoading;
  String? get status => _status;
  Map<String, dynamic>? get uploadData => _uploadData; // Expose for debugging or UI

  Future<void> fetchStats(List<PlatformFile> files, {String groupBy = 'operator'}) async {
    // Validate input
    if (files.isEmpty) {
      _status = '❌ No files selected for upload.';
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _status = 'Starting statistics processing...';
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
      _status = 'Fetching statistics data...';
      notifyListeners();
      final rawData = await analysisService.fetchAnalysisData(docId).timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw Exception('Fetch timed out after 60 seconds.'),
          );

      // Process raw data into statsData with detailed metrics
      _statsData.clear();
      _uploadData = rawData; // Store raw response for potential use
      for (var entry in rawData.entries) {
        final sheetData = entry.value as model.AnalysisData;
        final rows = sheetData.rows;

        for (var row in rows) {
          final groupKey = groupBy == 'operator' ? row['Operator_Name']?.toString() ?? 'Unknown' : row['Dep_Location']?.toString() ?? 'Unknown';
          if (!_statsData.containsKey(groupKey)) {
            _statsData[groupKey] = {
              'Group': groupKey,
              'Customer_Name': row['Customer_Name']?.toString() ?? 'N/A',
              'Flight_Count': 0,
              'Avg_Airtime_Hours': 0.0,
              'Same_Linkage_Count': 0,
              'Different_Linkage_Count': 0,
              'Arr_Billed_Count': 0,
              'Arr_Unbilled_Count': 0,
              'Dep_Billed_Count': 0,
              'Dep_Unbilled_Count': 0,
              'UDF_Billed_Count': 0,
              'UDF_Unbilled_Count': 0,
              'Total_Landing_Charges': 0.0,
              'Total_UDF_Charges': 0.0,
            };
          }

          final stats = _statsData[groupKey]!;
          stats['Flight_Count'] = (stats['Flight_Count'] as int) + 1;
          stats['Avg_Airtime_Hours'] = (stats['Avg_Airtime_Hours'] as double) +
              (double.tryParse(row['Airtime_Hours']?.toString() ?? '0.0') ?? 0.0);
          if (stats['Flight_Count'] > 1) {
            stats['Avg_Airtime_Hours'] = stats['Avg_Airtime_Hours'] / stats['Flight_Count'];
          }
          if (row['Linkage_Status']?.toString() == 'Same') stats['Same_Linkage_Count'] = (stats['Same_Linkage_Count'] as int) + 1;
          if (row['Linkage_Status']?.toString() == 'Different') stats['Different_Linkage_Count'] = (stats['Different_Linkage_Count'] as int) + 1;
          if (row['Arr_Bill_Status']?.toString() == 'billed') stats['Arr_Billed_Count'] = (stats['Arr_Billed_Count'] as int) + 1;
          if (row['Arr_Bill_Status']?.toString() == 'unbilled') stats['Arr_Unbilled_Count'] = (stats['Arr_Unbilled_Count'] as int) + 1;
          if (row['Dep_Bill_Status']?.toString() == 'billed') stats['Dep_Billed_Count'] = (stats['Dep_Billed_Count'] as int) + 1;
          if (row['Dep_Bill_Status']?.toString() == 'unbilled') stats['Dep_Unbilled_Count'] = (stats['Dep_Unbilled_Count'] as int) + 1;
          if (row['UDF_Bill_Status']?.toString() == 'billed') stats['UDF_Billed_Count'] = (stats['UDF_Billed_Count'] as int) + 1;
          if (row['UDF_Bill_Status']?.toString() == 'unbilled') stats['UDF_Unbilled_Count'] = (stats['UDF_Unbilled_Count'] as int) + 1;
          stats['Total_Landing_Charges'] = (stats['Total_Landing_Charges'] as double) +
              (double.tryParse(row['Landing']?.toString() ?? '0.0') ?? 0.0);
          stats['Total_UDF_Charges'] = (stats['Total_UDF_Charges'] as double) +
              (double.tryParse(row['UDF_Charge']?.toString() ?? '0.0') ?? 0.0);
        }
      }

      // Finalize averages
      _statsData.forEach((key, value) {
        if (value['Flight_Count'] > 0) {
          value['Avg_Airtime_Hours'] = (value['Avg_Airtime_Hours'] as double) / value['Flight_Count'];
        }
      });

      _status = '✅ Statistics loaded for ${_statsData.length} groups.';
      logger.d('Stats loaded for ${_statsData.length} groups at ${DateTime(2025, 8, 3, 2, 49, 0).toIso8601String()}');
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
      logger.e('Error fetching stats: $e at ${DateTime(2025, 8, 3, 2, 49, 0).toIso8601String()}');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clears the current stats and status.
  void clearData() {
    _statsData.clear();
    _uploadData = null;
    _status = null;
    notifyListeners();
  }
}