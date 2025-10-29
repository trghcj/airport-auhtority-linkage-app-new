import 'dart:convert';
import 'dart:io' show File, Platform;
import 'package:airport_auhtority_linkage_app/services/analysis_service.dart';
import 'package:airport_auhtority_linkage_app/config/config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:airport_auhtority_linkage_app/models/analysis_data.dart' as model;
import 'package:universal_html/html.dart' as html; // Import universal_html for web support

class AnalysisPage extends StatefulWidget {
  final Map<String, model.AnalysisData>? initialAnalysisResult; // Receive pre-analyzed data

  const AnalysisPage({super.key, this.initialAnalysisResult});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  final Logger _logger = Logger();
  final AnalysisService _analysisService = AnalysisService();
  bool _isLoading = false;
  String? _status;
  Map<String, model.AnalysisData>? _analysisResult;
  String? _selectedSheet;
  String? _docId; // Store docId from initialAnalysisResult

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  void _initializeData() {
    if (widget.initialAnalysisResult != null && widget.initialAnalysisResult!.isNotEmpty) {
      setState(() {
        _analysisResult = widget.initialAnalysisResult;
        _selectedSheet = _analysisResult!.keys.firstWhere((k) => _analysisResult![k] != null, orElse: () => _analysisResult!.keys.first);
        // ignore: unnecessary_null_comparison
        _docId = _analysisResult!.values.firstWhere((v) => v.docId != null, orElse: () => model.AnalysisData.empty()).docId;
        _status = _docId != null
            ? '✅ Analysis data received with Doc ID: $_docId'
            : '✅ Analysis data received from previous upload (no Doc ID).';
        _logger.d(
            'Initialized with analysis result: $_analysisResult, docId: $_docId at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
      });
    }
  }

  @override
  void didUpdateWidget(covariant AnalysisPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialAnalysisResult != oldWidget.initialAnalysisResult) {
      _initializeData();
    }
  }

  Future<void> _uploadAndAnalyzeFile() async {
    setState(() {
      _isLoading = true;
      _status = 'Starting analysis...';
      _analysisResult = null;
      _selectedSheet = null;
      _docId = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: kIsWeb,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _status = '⚠️ Please select a base data file.';
          _isLoading = false;
        });
        _showSnackBar('No file selected. Please try again.');
        return;
      }

      final file = result.files.first;
      if (file.size > 50 * 1024 * 1024) {
        setState(() {
          _status = '❌ File size exceeds 50MB limit.';
          _isLoading = false;
        });
        _showSnackBar('File size exceeds 50MB limit.');
        return;
      }

      final analysisResponse = await _analysisService.analyzeData(file);
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _analysisResult = (analysisResponse['analysisResult'] as Map<String, dynamic>).cast<String, model.AnalysisData>();
        _selectedSheet = _analysisResult!.keys.firstWhere((k) => _analysisResult![k] != null, orElse: () => _analysisResult!.keys.first);
        _docId = analysisResponse['docId'] as String?;
        _status = _docId != null
            ? '✅ Analysis complete for ${_analysisResult!.keys.length} sheet(s) with Doc ID: $_docId'
            : '✅ Analysis complete for ${_analysisResult!.keys.length} sheet(s) (no Doc ID).';
        _logger.d(
            'Analysis result: $_analysisResult, docId: $_docId at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
      });
      _showSnackBar('Analysis completed successfully.');
    } catch (e, stackTrace) {
      if (mounted) {
        _logger.e(
            'Error analyzing file: $e\nStackTrace: $stackTrace at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
        setState(() {
          _status = '❌ Analysis failed: ${e.toString().contains("Network error") ? "Check your internet connection and try again." : e.toString().contains("Customer_Name") ? "Check base file has 'Customer_Name' column or try again." : e.toString()}';
          _isLoading = false;
        });
        _showSnackBar('Analysis failed: ${e.toString().contains("Network error") ? "Check your internet connection." : e.toString()}');
      }
    }
  }

  Future<void> _downloadPDF(String sheetName) async {
    if (_docId == null || _docId!.isEmpty) {
      setState(() {
        _status = '⚠️ No document ID available. Upload via UploadPage first to generate a PDF.';
        _isLoading = false;
      });
      _showSnackBar('No document ID available for PDF download.');
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Downloading PDF for sheet: $sheetName...';
    });

    try {
      final pdfData = await _analysisService.downloadPDF(_docId!);
      if (pdfData.isEmpty) {
        throw Exception('Empty PDF data received');
      }

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

        if (!mounted) return;

        if (Platform.isAndroid || Platform.isIOS) {
          final result = await OpenFile.open(file.path);
          if (result.type != ResultType.done) {
            _showSnackBar('Failed to open PDF. Check file permissions.');
          }
        }
      }

      setState(() {
        _isLoading = false;
        _status = '✅ PDF downloaded successfully for $sheetName';
      });
      _logger.d(
          'PDF downloaded: $fileName at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
      _showSnackBar('PDF downloaded successfully.');
    } catch (e, stackTrace) {
      if (mounted) {
        _logger.e(
            'Error downloading PDF: $e\nStackTrace: $stackTrace at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
        setState(() {
          _isLoading = false;
          _status = '❌ PDF download failed: ${e.toString().contains('Empty PDF data') ? 'No data available for this document.' : e.toString().contains("Network error") ? "Check your internet connection and try again." : e.toString()}';
        });
        _showSnackBar('PDF download failed: ${e.toString().contains("Network error") ? "Check your internet connection." : e.toString()}');
      }
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Color? _getStatusColor() {
    if (_status == null) return null;
    if (_status!.startsWith('✅')) return Colors.green[100];
    if (_status!.startsWith('❌')) return Colors.red[100];
    if (_status!.startsWith('⚠️')) return Colors.orange[100];
    return null;
  }

  Color _getAirtimeColor(String? hours) {
    if (hours == null || hours == 'N/A') return Colors.grey;
    try {
      final doubleHours = double.parse(hours.split(' ').first);
      if (doubleHours < 10) return Colors.red;
      if (doubleHours < 14) return Colors.yellow;
      return Colors.green;
    } catch (e) {
      return Colors.grey;
    }
  }

  Color _getBillStatusColor(String? status) {
    if (status == null) return Colors.grey;
    return status.toLowerCase() == 'yes' ? Colors.green : Colors.red;
  }

  DateTime? _parseDate(String? dateStr, String? hhmmStr, String fieldName) {
    if (dateStr == null || dateStr.isEmpty || dateStr == 'N/A') {
      _logger.w('Invalid date format for $fieldName: $dateStr at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
      return null;
    }
    try {
      // Try parsing as ISO string first
      DateTime? parsedDate = DateTime.tryParse(dateStr);
      if (parsedDate != null) {
        return _applyHHMM(parsedDate, hhmmStr);
      }
      // Try parsing as Excel serial number
      final serialNum = double.tryParse(dateStr);
      if (serialNum != null && serialNum >= 0 && serialNum <= 1e6) {
        final baseDate = DateTime(1899, 12, 30);
        final date = baseDate.add(Duration(days: serialNum.toInt()));
        return _applyHHMM(date, hhmmStr);
      }
      _logger.w('Invalid date format for $fieldName: $dateStr at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
      return null;
    } catch (e) {
      _logger.w('Error parsing date for $fieldName: $dateStr, error: $e at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
      return null;
    }
  }

  DateTime? _applyHHMM(DateTime date, String? hhmmStr) {
    if (hhmmStr != null && hhmmStr.isNotEmpty) {
      final hhmmNormalized = hhmmStr.replaceAll(':', '').replaceAll(RegExp(r'[^0-9]'), '');
      if (hhmmNormalized.length == 4 && int.tryParse(hhmmNormalized) != null) {
        final hours = int.tryParse(hhmmNormalized.substring(0, 2)) ?? 0;
        final minutes = int.tryParse(hhmmNormalized.substring(2, 4)) ?? 0;
        if (hours >= 0 && hours <= 23 && minutes >= 0 && minutes <= 59) {
          return date.add(Duration(hours: hours, minutes: minutes)).toUtc();
        } else {
          _logger.w('Invalid HHMM $hhmmStr, using 00:00 at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
        }
      } else {
        _logger.w('Non-numeric or invalid HHMM $hhmmStr, using 00:00 at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
      }
    }
    return date.toUtc();
  }

  Widget _buildSheetDashboard(String sheetName) {
    if (_analysisResult == null || !_analysisResult!.containsKey(sheetName)) {
      return const Center(
        child: Text(
          'No data available for this sheet.',
          style: TextStyle(fontFamily: 'Roboto', fontSize: 16),
        ),
      );
    }

    final sheetData = _analysisResult![sheetName]!;
    final columns = sheetData.columns;
    final rows = sheetData.rows;
    final stats = sheetData.stats;
    final formalSummary = sheetData.formalSummary;
    final chartBarBase64 = sheetData.chartBar;
    final chartPieBase64 = sheetData.chartPie;

    final processedRows = rows.map((row) {
      DateTime? arrGmt = _parseDate(row['Arr_Date']?.toString(), row['Arr_GMT'] as String?, 'Arr GMT');
      DateTime? depGmt = _parseDate(row['Dep_Date']?.toString(), row['Dep_GMT'] as String?, 'Dep GMT');
      String airtimeHours = 'N/A';
      if (arrGmt != null && depGmt != null) {
        Duration difference = depGmt.difference(arrGmt).abs();
        double hours = difference.inMinutes / 60.0;
        airtimeHours = '${hours.toStringAsFixed(2)} hours';
      }

      double landing = (double.tryParse((row['Landing']?.toString() ?? '0.0').replaceAll('₹', '').replaceAll(',', '')) ?? 0.0);
      double udfCharge = (double.tryParse((row['UDF_Charge']?.toString() ?? '0.0').replaceAll('₹', '').replaceAll(',', '')) ?? 0.0);

      return {
        ...row,
        'Airtime_Hours': airtimeHours,
        'Landing': '₹${landing.toStringAsFixed(2)}',
        'UDF_Charge': '₹${udfCharge.toStringAsFixed(2)}',
        'Arr_Bill_Status': (row['Arr_Bill_Status']?.toString().toLowerCase() ?? '').contains('billed') ? 'Yes' : 'No',
        'Dep_Bill_Status': (row['Dep_Bill_Status']?.toString().toLowerCase() ?? '').contains('billed') ? 'Yes' : 'No',
        'UDF_Bill_Status': (row['UDF_Bill_Status']?.toString().toLowerCase() ?? '').contains('billed') ? 'Yes' : 'No',
      };
    }).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Analysis Dashboard',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Summary: $formalSummary',
            style: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Statistics',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...stats.entries.map((entry) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${entry.key}:',
                              style: const TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              entry.value.toString(),
                              style: const TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (chartBarBase64.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Image.memory(base64Decode(chartBarBase64), fit: BoxFit.contain),
            ),
          if (chartPieBase64.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Image.memory(base64Decode(chartPieBase64), fit: BoxFit.contain),
            ),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: DataTable(
                    columnSpacing: 16.0,
                    dataRowHeight: 48.0,
                    headingRowHeight: 56.0,
                    columns: columns.map((col) => DataColumn(
                          label: Text(
                            col,
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        )).toList(),
                    rows: processedRows.map((row) {
                      return DataRow(cells: columns.map((col) {
                        final value = row[col] ?? 'N/A';
                        Color? textColor;
                        if (col == 'Airtime_Hours') {
                          textColor = _getAirtimeColor(value.toString());
                        } else if (col.endsWith('Bill_Status')) {
                          textColor = _getBillStatusColor(value.toString());
                        }
                        return DataCell(
                          Text(
                            value.toString(),
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 14,
                              color: textColor,
                              overflow: TextOverflow.ellipsis,
                            ),
                            maxLines: 1,
                          ),
                        );
                      }).toList());
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isLoading || _selectedSheet == null || _docId == null
                ? null
                : () => _downloadPDF(_selectedSheet!),
            child: const Text('Download PDF'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              textStyle: const TextStyle(fontSize: 16, fontFamily: 'Roboto'),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        title: const Text(
          'Analyze Base Data',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 4,
        shadowColor: Colors.grey.withOpacity(0.3),
        actions: [
          if (_docId != null && !_isLoading)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
              onPressed: _selectedSheet == null ? null : () => _downloadPDF(_selectedSheet!),
              tooltip: 'Download PDF',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.analytics),
                        label: const Text(
                          'Upload Base Data File',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 16,
                          ),
                        ),
                        onPressed: _uploadAndAnalyzeFile,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                          textStyle: const TextStyle(fontSize: 16),
                          minimumSize: Size(MediaQuery.of(context).size.width - 32, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _getStatusColor(),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Text(
                        _status!,
                        style: const TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 14,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  if (_analysisResult != null) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: DropdownButton<String>(
                            value: _selectedSheet,
                            hint: const Text(
                              'Select a Sheet',
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 14,
                              ),
                            ),
                            isExpanded: true,
                            items: sheetKeys.map((sheet) {
                              return DropdownMenuItem<String>(
                                value: sheet,
                                child: Text(
                                  sheet,
                                  style: const TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() => _selectedSheet = value);
                              _logger.d(
                                  'Selected sheet: $value at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)))}');
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_selectedSheet != null)
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: SingleChildScrollView(
                          child: _buildSheetDashboard(_selectedSheet!),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}