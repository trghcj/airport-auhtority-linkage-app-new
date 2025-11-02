import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'dart:convert';

/// 🚀 Configuration for API endpoints
/// (You can move this to config/config.dart if you prefer)
class AppConfig {
  static const String baseUrl = 'https://web-production-9b0d5.up.railway.app';
  static const String uploadEndpoint = '/upload';
  static String get uploadURL => baseUrl + uploadEndpoint;
}

class UploadService {
  final Logger _logger = Logger();

  /// Uploads one or more Excel files (.xlsx / .xls) to the Flask backend.
  ///
  /// Returns: { 'docId': '<Firestore Document ID>' } on success,
  /// or throws an [Exception] with a detailed error message on failure.
  Future<Map<String, dynamic>> uploadFiles(List<String> filePaths) async {
    try {
      if (filePaths.isEmpty) {
        throw Exception('No files provided for upload.');
      }

      final uri = Uri.parse(AppConfig.uploadURL);
      final request = http.MultipartRequest('POST', uri);

      bool hasValidFiles = false;

      for (final path in filePaths) {
        final file = File(path);
        if (!await file.exists()) {
          _logger.w('File not found, skipping: $path');
          continue;
        }

        final fileName = file.uri.pathSegments.last.toLowerCase();
        if (!fileName.endsWith('.xlsx') && !fileName.endsWith('.xls')) {
          _logger.w('Skipping invalid file format: $fileName (must be .xlsx/.xls)');
          continue;
        }

        // 🔹 The backend expects multiple files under 'departure_files[]'
        request.files.add(await http.MultipartFile.fromPath(
          'departure_files[]',
          path,
          filename: fileName,
        ));
        hasValidFiles = true;
        _logger.d('Added file: $fileName');
      }

      if (!hasValidFiles) {
        throw Exception('No valid Excel files were added for upload.');
      }

      _logger.i('📤 Uploading files to: ${AppConfig.uploadURL}');
      _logger.d('Files: ${request.files.map((f) => f.filename).join(', ')}');

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();
      final responseStatus = streamedResponse.statusCode;

      _logger.d('📦 Response ($responseStatus): $responseBody');

      if (responseStatus == 200) {
        final data = jsonDecode(responseBody) as Map<String, dynamic>;

        if (data['success'] == true && data['doc_id'] != null) {
          final docId = data['doc_id'];
          _logger.i('✅ Upload successful! Firestore Doc ID: $docId');
          return {'docId': docId};
        } else {
          final errorMsg = data['error'] ?? 'Unknown backend error';
          throw Exception('Upload failed: $errorMsg');
        }
      } else {
        throw Exception('Upload failed with status: $responseStatus\n$responseBody');
      }
    } catch (e, stackTrace) {
      _logger.e('❌ Upload error: $e\nStackTrace:\n$stackTrace');
      rethrow;
    }
  }
}
