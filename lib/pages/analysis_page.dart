import 'dart:convert';
import 'dart:io' show File, Platform;
import 'package:airport_auhtority_linkage_app/services/analysis_service.dart';
import 'package:airport_auhtority_linkage_app/config/config.dart';
import 'package:airport_auhtority_linkage_app/models/analysis_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;

class AnalysisPage extends StatefulWidget {
  final Map<String, AnalysisData>? initialAnalysisResult;

  const AnalysisPage({super.key, this.initialAnalysisResult});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  final Logger _logger = Logger();
  final AnalysisService _analysisService = AnalysisService();
  bool _isLoading = false;
  String? _status;
  Map<String, AnalysisData>? _analysisResult;
  String? _selectedSheet;
  String? _docId;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  void _initializeData() {
    if (widget.initialAnalysisResult != null && widget.initialAnalysisResult!.isNotEmpty) {
      setState(() {
        _analysisResult = Map.from(widget.initialAnalysisResult!);
        _selectedSheet = _analysisResult!.keys.first;
        _docId = _analysisResult!.values.first.docId;
        _status = _docId != null && _docId!.isNotEmpty
            ? '✅ Analysis loaded (Doc ID: $_docId)'
            : '✅ Loaded previous analysis data.';
      });
      _logger.i("Initialized with docId: $_docId and ${_analysisResult!.length} sheets.");
    }
  }

  Future<void> _uploadAndAnalyzeFile() async {
    setState(() {
      _isLoading = true;
      _status = 'Uploading and analyzing...';
    });

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: kIsWeb,
      );

      if (picked == null || picked.files.isEmpty) {
        _setStatus('⚠️ No file selected.');
        return;
      }

      final file = picked.files.first;
      if (file.size > 50 * 1024 * 1024) {
        _setStatus('❌ File too large (>50MB).');
        return;
      }

      final result = await _analysisService.analyzeData(file);
      if (!mounted) return;

      final analysisData =
          (result['analysisResult'] as Map<String, dynamic>).cast<String, AnalysisData>();
      final docId = result['docId'] as String? ?? '';

      setState(() {
        _isLoading = false;
        _analysisResult = analysisData;
        _docId = docId;
        _selectedSheet = _analysisResult!.keys.first;
        _status =
            '✅ Analysis complete (${_analysisResult!.length} sheets). ${_docId!.isNotEmpty ? "Doc ID: $_docId" : ""}';
      });
      _showSnackBar('Analysis complete!');
    } catch (e, stack) {
      _logger.e("Error analyzing: $e\n$stack");
      _setStatus('❌ Analysis failed: ${e.toString().split(":").last}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadPDF(String sheetName) async {
    if (_docId == null || _docId!.isEmpty) {
      _setStatus('⚠️ No document ID. Please upload first.');
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Downloading PDF...';
    });

    try {
      final pdfData = await _analysisService.downloadPDF(_docId!);
      if (pdfData.isEmpty) throw Exception("No PDF data received.");

      final fileName = 'analysis_${sheetName.replaceAll(' ', '_')}_${_docId!}.pdf';

      if (kIsWeb) {
        final blob = html.Blob([pdfData]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(pdfData, flush: true);

        if (Platform.isAndroid || Platform.isIOS) {
          final result = await OpenFile.open(file.path);
          if (result.type != ResultType.done) {
            _showSnackBar('⚠️ Could not open file.');
          }
        }
      }

      _setStatus('✅ PDF downloaded for $sheetName');
    } catch (e, stack) {
      _logger.e('PDF download error: $e\n$stack');
      _setStatus('❌ PDF download failed: ${e.toString().split(":").last}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // -------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------
  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
    ));
  }

  void _setStatus(String msg) {
    if (!mounted) return;
    setState(() {
      _status = msg;
      _isLoading = false;
    });
    _showSnackBar(msg);
  }

  Color? _getStatusColor() {
    if (_status == null) return null;
    if (_status!.startsWith('✅')) return Colors.green[100];
    if (_status!.startsWith('❌')) return Colors.red[100];
    if (_status!.startsWith('⚠️')) return Colors.orange[100];
    return null;
  }

  Widget _buildSheetDashboard(String sheetName) {
    final sheet = _analysisResult?[sheetName];
    if (sheet == null) {
      return const Center(child: Text('No data available.'));
    }

    final summary = sheet.formalSummary;
    final stats = sheet.stats;
    final chartBar = sheet.chartBar;
    final chartPie = sheet.chartPie;
    final rows = sheet.rows.take(10).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("📝 Summary:\n$summary",
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          if (chartBar.isNotEmpty)
            Image.memory(base64Decode(chartBar), height: 180, fit: BoxFit.contain),
          if (chartPie.isNotEmpty)
            Image.memory(base64Decode(chartPie), height: 180, fit: BoxFit.contain),
          const SizedBox(height: 10),
          const Text("📊 Key Statistics:",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ...stats.entries
              .map((e) => Text("${e.key.replaceAll('_', ' ').toUpperCase()}: ${e.value}")),
          const Divider(),
          const Text("📋 Sample Rows:",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ...rows.map((r) => Text(r.toString())),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: !_isLoading ? () => _downloadPDF(sheetName) : null,
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            label: const Text("Download PDF"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sheetKeys = _analysisResult?.keys.toList() ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analyze Base Data'),
        actions: [
          if (_docId != null && _docId!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
              tooltip: "Download PDF",
              onPressed: _selectedSheet != null ? () => _downloadPDF(_selectedSheet!) : null,
            )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: _uploadAndAnalyzeFile,
                    icon: const Icon(Icons.upload_file),
                    label: const Text("Upload & Analyze Base File"),
                  ),
                  if (_status != null)
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _getStatusColor(),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_status!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, height: 1.4)),
                    ),
                  if (_analysisResult != null && _analysisResult!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButton<String>(
                      value: _selectedSheet,
                      hint: const Text("Select Sheet"),
                      isExpanded: true,
                      items: sheetKeys
                          .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedSheet = val),
                    ),
                    const SizedBox(height: 10),
                    if (_selectedSheet != null)
                      Expanded(child: _buildSheetDashboard(_selectedSheet!)),
                  ],
                ],
              ),
      ),
    );
  }
}

extension StringExtension on String {
  String get titleCase => split(' ')
      .map((word) => word.isNotEmpty
          ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
          : word)
      .join(' ');
}
