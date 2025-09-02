import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:airport_auhtority_linkage_app/config/config.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart'; // For opening PDF download

class AnalysisTestPage extends StatefulWidget {
  const AnalysisTestPage({super.key});

  @override
  State<AnalysisTestPage> createState() => _AnalysisTestPageState();
}

class _AnalysisTestPageState extends State<AnalysisTestPage> {
  String? status;
  bool loading = false;
  Map<String, dynamic>? result;
  String? docId; // Store doc_id from response
  final Logger _logger = Logger();

  Future<void> uploadTestFile() async {
    setState(() {
      loading = true;
      status = null;
      result = null;
      docId = null;
    });

    try {
      final file = await FilePicker.platform.pickFiles(
        allowedExtensions: ['xlsx', 'xlsb'],
        type: FileType.custom,
      );

      if (file == null || (file.files.first.bytes == null && file.files.first.path == null)) {
        setState(() {
          status = "⚠️ No file selected.";
          loading = false;
        });
        return;
      }

      final filename = file.files.first.name;
      final url = Uri.parse(AppConfig.analyzeURL);

      final request = http.MultipartRequest('POST', url);
      if (kIsWeb || file.files.first.bytes != null) {
        final fileBytes = file.files.first.bytes!;
        request.files.add(
          http.MultipartFile.fromBytes('base_file', fileBytes, filename: filename),
        );
      } else {
        final filePath = file.files.first.path!;
        request.files.add(
          await http.MultipartFile.fromPath('base_file', filePath, filename: filename),
        );
      }

      final streamedResponse = await request.send().timeout(const Duration(seconds: 300));
      final response = await http.Response.fromStream(streamedResponse);
      final body = json.decode(response.body);

      if (!mounted) return;

      if (body['success'] == true) {
        setState(() {
          result = body['sheets'];
          docId = body['doc_id']; // Capture doc_id
          status = "✅ Analysis complete. Click below to download PDF.";
        });
      } else {
        setState(() {
          status = "❌ Error: ${body['error'] ?? 'Unknown error'}";
        });
      }
    } catch (e, stackTrace) {
      if (mounted) {
        _logger.e('Error: $e\nStackTrace: $stackTrace');
        setState(() {
          status = "❌ Exception: $e";
        });
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> downloadPdf() async {
    if (docId == null) {
      setState(() => status = "⚠️ No document ID available. Please analyze a file first.");
      return;
    }
    final pdfUrl = Uri.parse('${AppConfig.baseURL}/download_dashboard/$docId');
    if (await canLaunchUrl(pdfUrl)) {
      await launchUrl(pdfUrl, mode: LaunchMode.externalApplication);
    } else {
      setState(() => status = "❌ Failed to launch PDF download.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Excel Analysis')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: loading ? null : uploadTestFile,
              icon: const Icon(Icons.upload_file),
              label: const Text("Pick and Analyze Excel"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            if (docId != null)
              ElevatedButton.icon(
                onPressed: loading ? null : downloadPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text("Download PDF"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            const SizedBox(height: 20),
            if (loading) const CircularProgressIndicator(),
            if (status != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: status!.startsWith("✅") ? Colors.green[100] : Colors.red[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status!,
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            if (result != null)
              Expanded(
                child: ListView(
                  children: result!.entries.map((entry) {
                    final sheetName = entry.key;
                    final sheetData = entry.value as Map<String, dynamic>;
                    final columns = List<String>.from(sheetData['columns'] ?? []);
                    final formalSummary = sheetData['formal_summary'] ?? 'No summary available';
                    Uint8List? chartBarImage;
                    Uint8List? chartPieImage;

                    if (sheetData['chart_bar'] != null && (sheetData['chart_bar'] as String).isNotEmpty) {
                      try {
                        chartBarImage = base64Decode(sheetData['chart_bar']);
                      } catch (e) {
                        _logger.e('Error decoding bar chart for $sheetName: $e');
                      }
                    }
                    if (sheetData['chart_pie'] != null && (sheetData['chart_pie'] as String).isNotEmpty) {
                      try {
                        chartPieImage = base64Decode(sheetData['chart_pie']);
                      } catch (e) {
                        _logger.e('Error decoding pie chart for $sheetName: $e');
                      }
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ExpansionTile(
                        title: Text("📄 Sheet: $sheetName", style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Columns: ${columns.length}"),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Formal Summary:', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text(formalSummary, style: const TextStyle(fontSize: 14)),
                                const SizedBox(height: 10),
                                if (chartBarImage != null)
                                  Container(
                                    margin: const EdgeInsets.symmetric(vertical: 10),
                                    height: 200,
                                    width: double.infinity,
                                    child: Image.memory(chartBarImage, fit: BoxFit.contain),
                                  ),
                                if (chartPieImage != null)
                                  Container(
                                    margin: const EdgeInsets.symmetric(vertical: 10),
                                    height: 200,
                                    width: double.infinity,
                                    child: Image.memory(chartPieImage, fit: BoxFit.contain),
                                  ),
                                const Text('Sample Data:', style: TextStyle(fontWeight: FontWeight.bold)),
                                ...List<Map<String, dynamic>>.from(sheetData['rows'] ?? []).take(5).map((row) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Text(row.toString(), style: const TextStyle(fontSize: 12)),
                                  );
                                }),
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