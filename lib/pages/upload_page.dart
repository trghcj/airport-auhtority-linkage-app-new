import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:airport_auhtority_linkage_app/config/config.dart';
import 'package:airport_auhtority_linkage_app/services/analysis_service.dart';
import 'package:logger/logger.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' show File, Platform;
import 'package:intl/intl.dart'; // Added for consistent date formatting

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final Logger _logger = Logger();
  final AnalysisService _analysisService = AnalysisService();
  String? _docId;
  String _status = 'Waiting for file upload...';
  bool _isUploading = false;
  String? _error;
  List<PlatformFile>? _selectedFiles;
  bool _hasDepartureFile = false;
  bool _hasBaseFile = false;

  Future<void> _pickFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedFiles = result.files;
          _hasDepartureFile = _selectedFiles!.any((f) => f.name.toLowerCase().contains('departure'));
          _hasBaseFile = _selectedFiles!.any((f) => f.name.toLowerCase().contains('base'));
          _status = 'Files selected: ${_selectedFiles!.map((f) => f.name).join(', ')}';
          _error = null;
        });
        _logger.d(
            'Files picked: ${_selectedFiles!.map((f) => f.name).join(', ')} at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
      } else {
        setState(() {
          _status = 'No files selected.';
        });
        _logger.w('No files selected at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
      }
    } catch (e) {
      if (mounted) {
        _logger.e(
            'File pick error: $e at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
        setState(() {
          _error = 'Error selecting files: ${e.toString()}';
          _status = 'Failed to select files.';
        });
      }
    }
  }

  Future<void> _handleUpload() async {
    if (_selectedFiles == null || !_hasDepartureFile) {
      setState(() {
        _error = 'Please select at least one departure file (e.g., containing "departure" in name).';
        _status = 'No departure file selected for upload.';
      });
      _logger.w('No departure file selected at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
      return;
    }

    setState(() {
      _isUploading = true;
      _status = 'Uploading departure file...';
      _error = null;
    });

    try {
      // Ensure the base URL in config.dart is set to http://localhost:5003
      final result = await _analysisService.uploadFiles(_selectedFiles!);
      if (!mounted) return;

      if (result.containsKey('success') && result['success'] == true && result.containsKey('doc_id')) {
        setState(() {
          _docId = result['doc_id'] as String;
          _isUploading = false;
          _status = '✅ Departure file uploaded successfully. Doc ID: $_docId';
          _navigateAfterUpload();
        });
      } else {
        setState(() {
          _isUploading = false;
          _status = 'Upload completed, but no valid Doc ID received.';
          _error = 'Upload may have failed. Check file format (e.g., missing Operator_Name) or server response.';
        });
      }
      _logger.d(
          'Upload result: docId: $_docId, Response: $result at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
    } catch (e, stackTrace) {
      if (mounted) {
        _logger.e(
            'Upload error: $e\nStackTrace: $stackTrace at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
        setState(() {
          _isUploading = false;
          _error = _parseUploadError(e.toString());
          _status = 'Upload failed. Please try again or check the file format/server connection.';
        });
      }
    }
  }

  Future<void> _handleAnalyze() async {
    if (_selectedFiles == null || !_hasBaseFile) {
      setState(() {
        _error = 'Please select at least one base file (e.g., containing "base" in name).';
        _status = 'No base file selected for analysis.';
      });
      _logger.w('No base file selected at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
      return;
    }

    setState(() {
      _isUploading = true;
      _status = 'Analyzing base file...';
      _error = null;
    });

    try {
      final baseFile = _selectedFiles!.firstWhere((f) => f.name.toLowerCase().contains('base'));
      final analysisResponse = await _analysisService.analyzeData(baseFile);
      if (!mounted) return;

      if (analysisResponse.containsKey('success') && analysisResponse['success'] == true && analysisResponse.containsKey('doc_id')) {
        setState(() {
          _isUploading = false;
          _status = '✅ Base file analyzed successfully.';
          Navigator.pushNamed(context, '/dashboard', arguments: {
            'docId': analysisResponse['doc_id'],
            'analysisResult': analysisResponse['sheets'],
          });
        });
      } else {
        setState(() {
          _isUploading = false;
          _status = 'Analysis completed, but no valid Doc ID received.';
          _error = 'Analysis may have failed. Check file format (e.g., missing Customer_Name) or server response.';
        });
      }
      _logger.d(
          'Analysis completed: docId: ${analysisResponse['doc_id']}, Response: $analysisResponse at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
    } catch (e, stackTrace) {
      if (mounted) {
        _logger.e(
            'Analysis error: $e\nStackTrace: $stackTrace at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
        setState(() {
          _isUploading = false;
          _error = e.toString().contains("Network error")
              ? 'Analysis failed: Check your internet connection and try again.'
              : e.toString().contains("Upload failed")
                  ? _parseUploadError(e.toString())
                  : 'Analysis failed: ${e.toString()}';
          _status = 'Analysis failed. Please try again or check the file format/server connection.';
        });
      }
    }
  }

  Future<void> _downloadPDF() async {
    if (_docId == null) {
      setState(() {
        _status = '⚠️ No document ID available. Upload a departure file first.';
      });
      _logger.w('No docId for PDF download at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
      return;
    }

    setState(() {
      _isUploading = true;
      _status = 'Downloading PDF...';
    });

    try {
      final pdfData = await _analysisService.downloadPDF(_docId!);
      if (pdfData.isEmpty) {
        throw Exception('Empty PDF data received');
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/departure_analysis_${_docId!}.pdf');
      await file.writeAsBytes(pdfData, flush: true);

      if (!mounted) return;

      setState(() {
        _isUploading = false;
        _status = '✅ PDF downloaded to ${file.path}';
      });
      _logger.d(
          'PDF downloaded: ${file.path} at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');

      if (Platform.isAndroid || Platform.isIOS) {
        await OpenFile.open(file.path);
      }
    } catch (e, stackTrace) {
      if (mounted) {
        _logger.e(
            'Error downloading PDF: $e\nStackTrace: $stackTrace at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
        setState(() {
          _isUploading = false;
          _status = '❌ PDF download failed: ${e.toString().contains('Empty PDF data') ? 'No data available for this document.' : e.toString().contains("Network error") ? "Check your internet connection and try again." : e.toString()}';
        });
      }
    }
  }

  String _parseUploadError(String errorMessage) {
    try {
      final errorJson = jsonDecode(errorMessage) as Map<String, dynamic>?;
      if (errorJson != null && errorJson.containsKey('error')) {
        return 'Upload failed: ${errorJson['error']}\n${errorJson.containsKey('details') ? errorJson['details'] : ''}\nCheck file headers (e.g., Operator_Name for departure, Customer_Name for base) and try again.';
      }
      return 'Upload failed: $errorMessage';
    } catch (e) {
      return 'Upload failed: $errorMessage';
    }
  }

  void _navigateAfterUpload() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload Successful'),
        content: const Text('Where would you like to go next?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (_docId != null) {
                Navigator.pushNamed(context, '/search', arguments: {'docId': _docId});
              }
            },
            child: const Text('Search Flights'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (_docId != null) {
                Navigator.pushNamed(context, '/stats', arguments: {'docId': _docId});
              }
            },
            child: const Text('View Statistics'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/dashboard');
            },
            child: const Text('Back to Dashboard'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Files'),
        elevation: 4,
        shadowColor: Colors.grey.withOpacity(0.3),
        actions: [
          if (_docId != null && !_isUploading)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
              onPressed: _downloadPDF,
              tooltip: 'Download PDF',
            ),
        ],
      ),
      body: Builder(
        builder: (context) => Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _isUploading ? null : _pickFiles,
                    child: const Text('Select Files'),
                  ),
                  ElevatedButton(
                    onPressed: _isUploading || _selectedFiles == null || !_hasDepartureFile
                        ? null
                        : _handleUpload,
                    child: const Text('Upload Departure'),
                  ),
                  ElevatedButton(
                    onPressed: _isUploading || _selectedFiles == null || !_hasBaseFile
                        ? null
                        : _handleAnalyze,
                    child: const Text('Analyze Base'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_isUploading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 16.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: _status.contains('✅')
                      ? Colors.green
                      : _status.contains('❌') || _status.contains('⚠️')
                          ? Colors.red
                          : null,
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (_selectedFiles != null && _selectedFiles!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Wrap(
                    spacing: 8.0,
                    children: _selectedFiles!.map((file) => Chip(label: Text(file.name))).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}