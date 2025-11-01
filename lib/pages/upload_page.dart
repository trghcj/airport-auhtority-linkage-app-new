import 'dart:convert';
import 'dart:io' show File;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:airport_auhtority_linkage_app/services/analysis_service.dart';

// Web only
import 'package:universal_html/html.dart' as html;

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final Logger _log = Logger();
  final AnalysisService _analysisService = AnalysisService();
  final Dio _dio = Dio();
  String? _docId;
  String _status = 'Waiting for file...';
  bool _uploading = false;
  String? _error;
  List<PlatformFile>? _files;
  bool _hasDeparture = false;
  bool _hasBase = false;

  // -----------------------------------------------------------------
  // 1. Pick files
  // -----------------------------------------------------------------
  Future<void> _pick() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: true,
      );
      if (res == null || res.files.isEmpty) {
        setState(() => _status = 'No file selected');
        _showSnackBar('No files selected');
        return;
      }
      setState(() {
        _files = res.files;
        _hasDeparture = _files!.any((f) => f.name.toLowerCase().contains('departure'));
        _hasBase = _files!.any((f) => f.name.toLowerCase().contains('base'));
        _status = 'Picked: ${_files!.map((e) => e.name).join(', ')}';
        _error = null;
      });
      _log.d('Picked files at ${_ist()}');
    } catch (e) {
      setState(() {
        _status = 'Error picking files';
        _error = e.toString();
      });
      _showSnackBar('Error picking files: $e');
      _log.e('Error picking files: $e');
    }
  }

  // -----------------------------------------------------------------
  // 2. Upload departure files
  // -----------------------------------------------------------------
  Future<void> _uploadDeparture() async {
    if (_files == null || !_hasDeparture) {
      setState(() {
        _error = 'Select at least one file containing "departure"';
        _status = 'Missing departure file';
      });
      _showSnackBar(_error!);
      return;
    }

    setState(() {
      _uploading = true;
      _status = 'Uploading...';
      _error = null;
    });

    try {
      final departureFiles = _files!.where((f) => f.name.toLowerCase().contains('departure')).toList();
      if (departureFiles.isEmpty) throw Exception('No valid departure files found');

      final result = await _analysisService.uploadFiles(departureFiles);
      setState(() {
        _uploading = false;
        _docId = result['docId'] as String;
        _status = 'Uploaded – Doc ID: $_docId';
      });
      _showSnackBar('Upload successful! Doc ID: $_docId');
      _showNextSteps();
    } catch (e) {
      setState(() {
        _uploading = false;
        _error = e.toString();
        _status = 'Upload failed';
      });
      _showSnackBar('Upload failed: $e');
      _log.e('Upload failed: $e at ${_ist()}');
    }
  }

  // -----------------------------------------------------------------
  // 3. Analyze base file (optional)
  // -----------------------------------------------------------------
  Future<void> _analyzeBase() async {
    if (_files == null || !_hasBase) {
      setState(() => _error = 'Select a base file');
      _showSnackBar(_error!);
      return;
    }
    final base = _files!.firstWhere((f) => f.name.toLowerCase().contains('base'), orElse: () => throw Exception('No base file found'));
    setState(() => _uploading = true);

    try {
      final form = FormData.fromMap({
        'base_file': kIsWeb
            ? MultipartFile.fromBytes(base.bytes!, filename: base.name)
            : await MultipartFile.fromFile(base.path!, filename: base.name),
      });
      const url = 'https://YOUR_NGROK_URL.ngrok-free.app'; // Placeholder, update with AppConfig.analyzeURL if integrated
      final resp = await _dio.post(
        '$url/analyze',
        data: form,
        options: Options(headers: {'Content-Type': 'multipart/form-data'}),
      );
      final data = resp.data;
      if (data['success'] == true) {
        Navigator.pushNamed(context, '/dashboard', arguments: data);
      } else {
        throw Exception(data['error']);
      }
    } on DioException catch (e) {
      _handleDio(e, 'Analyze');
    } catch (e) {
      setState(() => _error = e.toString());
      _showSnackBar('Analyze failed: $e');
    } finally {
      setState(() => _uploading = false);
    }
  }

  // -----------------------------------------------------------------
  // 4. Download PDF
  // -----------------------------------------------------------------
  Future<void> _downloadPdf() async {
    if (_docId == null) {
      _showSnackBar('No Doc ID available');
      return;
    }
    setState(() => _uploading = true);
    try {
      const url = 'https://766f2f960db6.ngrok-free.app'; // Placeholder, update with AppConfig.generatePdfURL if integrated
      final resp = await _dio.get(
        '$url/download_dashboard_pdf?doc_id=$_docId',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = resp.data as List<int>;

      if (kIsWeb) {
        final blob = html.Blob([bytes]);
        final objUrl = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: objUrl)
          ..setAttribute('download', 'dashboard_$_docId.pdf')
          ..click();
        html.Url.revokeObjectUrl(objUrl);
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/dashboard_$_docId.pdf');
        await file.writeAsBytes(bytes);
        await OpenFile.open(file.path);
      }
      setState(() => _status = 'PDF downloaded');
      _showSnackBar('PDF downloaded successfully');
    } catch (e) {
      setState(() => _error = e.toString());
      _showSnackBar('PDF download failed: $e');
    } finally {
      setState(() => _uploading = false);
    }
  }

  // -----------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------
  String _ist() {
    final utc = DateTime.now().toUtc();
    final ist = utc.add(const Duration(hours: 5, minutes: 30)); // 11:14 PM IST, October 26, 2025
    return DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(ist);
  }

  void _handleDio(DioException e, String op) {
    String msg = e.response?.data?['error'] ?? e.message ?? 'Network error';
    setState(() {
      _uploading = false;
      _error = '$op failed: $msg';
      _status = '$op failed';
    });
    _log.e('$op Dio error: $msg at ${_ist()}');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  void _showNextSteps() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Upload Success'),
        content: const Text('Where to next?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/search', arguments: {'docId': _docId}),
            child: const Text('Search Flights'),
          ),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/stats', arguments: {'docId': _docId}),
            child: const Text('View Stats'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Stay Here'),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------
  // UI
  // -----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Files'),
        actions: [
          if (_docId != null && !_uploading)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
              onPressed: _downloadPdf,
              tooltip: 'Download PDF',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(onPressed: _uploading ? null : _pick, child: const Text('Pick Files')),
                ElevatedButton(
                    onPressed: _uploading || !_hasDeparture ? null : _uploadDeparture,
                    child: const Text('Upload Departure')),
                ElevatedButton(
                    onPressed: _uploading || !_hasBase ? null : _analyzeBase,
                    child: const Text('Analyze Base')),
              ],
            ),
            const SizedBox(height: 16),
            if (_uploading) const CircularProgressIndicator(),
            Text(_status,
                style: TextStyle(
                    color: _status.contains('Uploaded') ? Colors.green : Colors.black)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (_files != null && _files!.isNotEmpty)
              Wrap(
                spacing: 8,
                children: _files!
                    .map((f) => Chip(
                          label: Text(f.name,
                              style: TextStyle(
                                  color: f.name.toLowerCase().contains('departure')
                                      ? Colors.blue
                                      : Colors.green)),
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}