import 'package:airport_auhtority_linkage_app/services/analysis_service.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:file_picker/file_picker.dart';
import 'package:airport_auhtority_linkage_app/models/analysis_data.dart' as model;
import 'package:airport_auhtority_linkage_app/config/config.dart';
import 'package:intl/intl.dart'; // For IST formatting

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
        _status = '⚠️ Upload failed: Invalid or missing Doc ID. Check file format (e.g., missing Operator Name or Reg No).';
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

        if (rows.isEmpty) {
          logger.w('No rows found in sheet ${entry.key} for docId $docId at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
          continue;
        }

        for (var row in rows) {
          final regNoRaw = row['Reg No']?.toString().trim(); // Updated to 'Reg No'
          final regNo = (regNoRaw?.isNotEmpty ?? false) ? regNoRaw!.toLowerCase() : 'unknown';
          if (regNo == 'unknown') {
            logger.w('Skipping row with invalid or empty Reg No: $row at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
            continue; // Skip invalid or empty Reg Nos
          }

          // Parse and validate dates
          DateTime? arrDate;
          DateTime? depDate;
          try {
            if (row['Arr Local'] != null && row['Arr Local'].toString().isNotEmpty) { // Updated to 'Arr Local'
              arrDate = DateTime.parse(row['Arr Local'].toString()).toLocal();
            }
            if (row['Dep Local'] != null && row['Dep Local'].toString().isNotEmpty) { // Updated to 'Dep Local'
              depDate = DateTime.parse(row['Dep Local'].toString()).toLocal();
            }
          } catch (e) {
            logger.w('Error parsing date for Reg No $regNo: $e, using "Unknown" at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
          }

          // Initialize or update flight data
          _flightData[regNo] = _flightData[regNo] ?? {
            'Reg No': regNo, // Updated to 'Reg No'
            'Operator Name': row['Operator Name']?.toString() ?? 'Unknown', // Updated to 'Operator Name'
            'Aircraft Type': row['Aircraft Type']?.toString() ?? 'Unknown', // Updated to 'Aircraft Type'
            'Arr Date': arrDate?.toIso8601String().split('T')[0] ?? 'Unknown', // Updated to 'Arr Date'
            'Dep Date': depDate?.toIso8601String().split('T')[0] ?? 'Unknown', // Updated to 'Dep Date'
            'Arr Bill Status': row['Arr Bill Status']?.toString() ?? 'unbilled', // Updated to 'Arr Bill Status'
            'Dep Bill Status': row['Dep Bill Status']?.toString() ?? 'unbilled', // Updated to 'Dep Bill Status'
            'UDF Bill Status': row['UDF Bill Status']?.toString() ?? 'unbilled', // Updated to 'UDF Bill Status'
            'Linkage Status': row['Linkage Status']?.toString() ?? 'Unknown', // Updated to 'Linkage Status'
            'Airtime Hours': row['Airtime Hours']?.toString() ?? '0.0', // Updated to 'Airtime Hours'
            'Count': 0, // Initialize count
            'Landing': row['Landing']?.toString().replaceAll('₹', '') ?? '0.0', // Numeric value without currency symbol
            'UDF Charge': row['UDF Charge']?.toString().replaceAll('₹', '') ?? '0.0', // Numeric value without currency symbol
          };

          // Update count and aggregate numeric fields
          final flightData = _flightData[regNo]!;
          flightData['Count'] = (flightData['Count'] as int) + 1;

          final double prevLanding = double.tryParse(flightData['Landing'] as String) ?? 0.0;
          final double addLanding = double.tryParse(row['Landing']?.toString().replaceAll('₹', '') ?? '0.0') ?? 0.0;
          flightData['Landing'] = (prevLanding + addLanding).toStringAsFixed(2);

          final double prevUdf = double.tryParse(flightData['UDF Charge'] as String) ?? 0.0;
          final double addUdf = double.tryParse(row['UDF Charge']?.toString().replaceAll('₹', '') ?? '0.0') ?? 0.0;
          flightData['UDF Charge'] = (prevUdf + addUdf).toStringAsFixed(2);
        }
      }

      _status = '✅ Registration data loaded for ${_flightData.length} aircraft.';
      logger.d('Loaded registrations for ${_flightData.length} aircraft at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
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
      logger.e('Error fetching registrations: $e at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
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