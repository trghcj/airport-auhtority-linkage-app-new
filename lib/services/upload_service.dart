import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'dart:convert';
import 'package:airport_auhtority_linkage_app/config/config.dart'; // Assuming config.dart contains AppConfig

class UploadService {
  final Logger _logger = Logger();
  static const String _uploadEndpoint = '/upload';

  /// Uploads .xlsx files to the backend and returns the response.
  /// 
  /// [filePaths] is a list of paths to the .xlsx files to upload.
  /// Returns a Map containing the 'docId' on success, or throws an exception on failure.
  Future<Map<String, dynamic>> uploadFiles(List<String> filePaths) async {
    try {
      // Validate file list
      if (filePaths.isEmpty) {
        throw Exception('No files provided for upload');
      }

      // Prepare multipart request
      var request = http.MultipartRequest('POST', Uri.parse(AppConfig.uploadURL + _uploadEndpoint));
      bool hasDepartureFile = false;

      // Process each file
      for (var filePath in filePaths) {
        final file = File(filePath);
        if (!await file.exists()) {
          _logger.w('File not found, skipping: $filePath');
          continue;
        }

        // Validate file extension
        final fileName = file.uri.pathSegments.last.toLowerCase();
        if (!fileName.endsWith('.xlsx') && !fileName.endsWith('.xls')) {
          _logger.w('Skipping invalid file format (must be .xlsx or .xls): $fileName');
          continue;
        }

        // Determine file type based on name
        if (fileName.contains('departure') && !hasDepartureFile) {
          request.files.add(await http.MultipartFile.fromPath('departure_file', filePath));
          _logger.d('Added departure file: $fileName');
          hasDepartureFile = true;
        } else if (fileName.contains('base')) {
          request.files.add(await http.MultipartFile.fromPath('base_file', filePath));
          _logger.d('Added base file: $fileName');
        } else {
          _logger.w('Skipping unrecognized file (must contain "departure" or "base"): $fileName');
        }
      }

      // Ensure at least one departure file is included
      if (!hasDepartureFile) {
        throw Exception('At least one departure file (containing "departure" in name and .xlsx/.xls format) is required.');
      }

      // Send request
      _logger.d('Sending upload request to ${AppConfig.uploadURL + _uploadEndpoint} with files: ${request.files.map((f) => f.filename)}');
      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      _logger.d('Upload response (status: ${response.statusCode}): $responseBody');

      if (response.statusCode == 200) {
        var data = jsonDecode(responseBody) as Map<String, dynamic>;
        if (data['success'] == true && data['doc_id'] != null) {
          final docId = data['doc_id'] as String;
          _logger.i('Upload successful, docId: $docId');
          return {'docId': docId};
        } else {
          final errorMsg = data['sheets']?['error'] ?? data['error'] ?? 'Unknown error';
          throw Exception('Upload failed: $errorMsg');
        }
      } else {
        throw Exception('Upload failed with status: ${response.statusCode}, message: $responseBody');
      }
    } catch (e, stackTrace) {
      _logger.e('Upload error: $e\nStackTrace: $stackTrace');
      rethrow;
    }
  }
}