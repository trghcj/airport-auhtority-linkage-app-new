import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:airport_auhtority_linkage_app/config/config.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';

class AnalysisTestPage extends StatefulWidget {
  const AnalysisTestPage({super.key});

  @override
  State<AnalysisTestPage> createState() => _AnalysisTestPageState();
}

class _AnalysisTestPageState extends State<AnalysisTestPage> {
  String? status;
  bool loading = false;
  Map<String, dynamic>? result;
  String? docId;
  final Logger _logger = Logger();

  // ---------------------------------------------------------------------------
  // Upload & Analyze File
  // ---------------------------------------------------------------------------
  Future<void> uploadTestFile() async {
    setState(() {
      loading = true;
      status = null;
      result = null;
      docId = null;
    });

    try {
      final picked = await FilePicker.platform.pickFiles(
        allowedExtensions: ['xlsx', 'xls'],
        type: FileType.custom,
      );

      if (picked == null || (picked.files.first.bytes == null && picked.files.first.path == null)) {
        setState(() {
          status = "⚠️ No file selected.";
          loading = false;
        });
        return;
      }

      final file = picked.files.first;
      final filename = file.name;
      final request = http.MultipartRequest('POST', Uri.parse(AppConfig.analyzeURL));

      if (kIsWeb || file.bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes('base_file', file.bytes!, filename: filename),
        );
      } else {
        request.files.add(await http.MultipartFile.fromPath('base_file', file.path!, filename: filename));
      }

      final streamedResponse = await request.send().timeout(const Duration(seconds: 300));
      final response = await http.Response.fromStream(streamedResponse);
      final body = jsonDecode(response.body);

      if (!mounted) return;

      if (body['success'] == true) {
        setState(() {
          result = body['sheets'];
          docId = body['doc_id'];
          status = "✅ Analysis complete. You can download the PDF below.";
        });
        _logger.i("Analysis completed successfully — docId: $docId");
      } else {
        setState(() {
          status = "❌ Error: ${body['error'] ?? 'Unknown error'}";
        });
        _logger.e("Analysis error: ${body['error']}");
      }
    } catch (e, stackTrace) {
      _logger.e('Error: $e\nStackTrace: $stackTrace');
      if (mounted) {
        setState(() => status = "❌ Exception: $e");
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Download generated PDF dashboard
  // ---------------------------------------------------------------------------
  Future<void> downloadPdf() async {
    if (docId == null || docId!.isEmpty) {
      setState(() => status = "⚠️ No document ID available. Please analyze a file first.");
      return;
    }

    final pdfUrl = Uri.parse('${AppConfig.generatePdfURL}?doc_id=$docId');
    _logger.i("Attempting to open PDF URL: $pdfUrl");

    if (await canLaunchUrl(pdfUrl)) {
      await launchUrl(pdfUrl, mode: LaunchMode.externalApplication);
      setState(() => status = "📄 PDF download initiated.");
    } else {
      setState(() => status = "❌ Failed to launch PDF link.");
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📊 Test Excel Analysis')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: loading ? null : uploadTestFile,
              icon: const Icon(Icons.upload_file),
              label: const Text("Pick & Analyze Excel"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
            if (docId != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ElevatedButton.icon(
                  onPressed: loading ? null : downloadPdf,
                  icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                  label: const Text("Download PDF Dashboard"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            if (loading) const CircularProgressIndicator(),
            if (status != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: status!.startsWith("✅")
                      ? Colors.green[100]
                      : status!.startsWith("⚠️")
                          ? Colors.amber[100]
                          : Colors.red[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status!,
                  style: const TextStyle(fontSize: 15),
                  textAlign: TextAlign.center,
                ),
              ),
            if (result != null)
              Expanded(
                child: ListView(
                  children: result!.entries.map((entry) {
                    final sheetName = entry.key;
                    final sheetData = entry.value as Map<String, dynamic>;
                    final summary = sheetData['formal_summary'] ?? 'No summary available';
                    Uint8List? chartBar, chartPie;

                    if (sheetData['chart_bar'] != null && (sheetData['chart_bar'] as String).isNotEmpty) {
                      try {
                        chartBar = base64Decode(sheetData['chart_bar']);
                      } catch (e) {
                        _logger.e('Error decoding bar chart for $sheetName: $e');
                      }
                    }

                    if (sheetData['chart_pie'] != null && (sheetData['chart_pie'] as String).isNotEmpty) {
                      try {
                        chartPie = base64Decode(sheetData['chart_pie']);
                      } catch (e) {
                        _logger.e('Error decoding pie chart for $sheetName: $e');
                      }
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ExpansionTile(
                        title: Text("📄 $sheetName", style: const TextStyle(fontWeight: FontWeight.bold)),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Summary:', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text(summary),
                                const SizedBox(height: 10),
                                if (chartBar != null)
                                  Image.memory(chartBar, height: 180, fit: BoxFit.contain),
                                if (chartPie != null)
                                  Image.memory(chartPie, height: 180, fit: BoxFit.contain),
                                const SizedBox(height: 10),
                                const Text('Sample Data (first 5 rows):',
                                    style: TextStyle(fontWeight: FontWeight.bold)),
                                ...List<Map<String, dynamic>>.from(sheetData['rows'] ?? [])
                                    .take(5)
                                    .map((row) => Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 2),
                                          child: Text(row.toString(),
                                              style: const TextStyle(fontSize: 12)),
                                        )),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
