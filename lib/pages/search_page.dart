import 'dart:async';
import 'package:airport_auhtority_linkage_app/services/analysis_service.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';
import 'package:airport_auhtority_linkage_app/config/config.dart';

class SearchPage extends StatefulWidget {
  final String filterBy;
  final String? docId; // Receive doc_id from UploadPage or DashboardPage

  const SearchPage({super.key, required this.filterBy, this.docId});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final Logger _logger = Logger();
  final AnalysisService _analysisService = AnalysisService();

  final _regNoController = TextEditingController();
  final _uniqueIdController = TextEditingController();
  final _aircraftTypeController = TextEditingController();

  String? _linkageStatus;
  String? _arrBillStatus;
  String? _depBillStatus;
  String? _udfBillStatus;

  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  String? _error;
  Timer? _debounceTimer;
  int _page = 0;
  static const int _limit = 100; // Fetch up to 100 entries per page

  @override
  void initState() {
    super.initState();
    _regNoController.text = widget.filterBy.trim();
    _logger.i(
      'SearchPage initialized with docId: ${widget.docId}, filterBy: "${widget.filterBy}" '
      'at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now())}',
    );
    if (widget.docId != null) _fetchResults();
  }

  @override
  void dispose() {
    _regNoController.dispose();
    _uniqueIdController.dispose();
    _aircraftTypeController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchResults() async {
    if (widget.docId == null || widget.docId!.isEmpty) {
      _setError('⚠️ No document ID available. Please upload or analyze a file first.');
      return;
    }

    final query = [
      _regNoController.text.trim(),
      _uniqueIdController.text.trim(),
      _aircraftTypeController.text.trim(),
      _linkageStatus,
      _arrBillStatus,
      _depBillStatus,
      _udfBillStatus,
    ].where((s) => s?.isNotEmpty ?? false).join(' ');

    _logger.d('Fetching search results | docId=${widget.docId}, query="$query", page=$_page, limit=$_limit');

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await _analysisService.searchFlights(widget.docId!, {
        'query': query,
        'page': _page.toString(),
        'limit': _limit.toString(),
      });

      if (!mounted) return;

      if (results.isEmpty) {
        _setError('No matching flights found for your search.');
        return;
      }

      setState(() {
        _results = results.map((r) {
          return {
            'Reg No': r['Reg No'] ?? 'Unknown',
            'Date': r['Date'] ?? 'Unknown',
            'Unique Id': r['Unique Id'] ?? 'Unknown',
            'Operator Name': r['Operator Name'] ?? 'Unknown Operator',
            'Aircraft Type': r['Aircraft Type'] ?? 'Unknown',
            'Airtime Hours': r['Airtime Hours'] ?? '0.00',
            'Linkage Status': r['Linkage Status'] ?? 'Unknown',
            'Arr Bill Status': r['Arr Bill Status'] ?? 'unbilled',
            'Dep Bill Status': r['Dep Bill Status'] ?? 'unbilled',
            'UDF Bill Status': r['UDF Bill Status'] ?? 'unbilled',
            'Landing': r['Landing'] ?? '₹0.00',
            'UDF Charge': r['UDF Charge'] ?? '₹0.00',
          };
        }).toList();
        _isLoading = false;
      });

      _logger.i('Fetched ${_results.length} results for "$query" at page $_page');
    } catch (e, stack) {
      _logger.e('Search error: $e\n$stack');
      _setError(
        e.toString().contains("Network")
            ? 'Network issue. Please check your internet connection.'
            : 'Unexpected error: $e',
      );
    }
  }

  void _debounceSearch() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _fetchResults();
    });
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _isLoading = false;
      _results = [];
    });
    _showSnackBar(message);
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
    }
  }

  Color _getAirtimeColor(String airtimeHoursStr) {
    final airtimeHours = double.tryParse(airtimeHoursStr) ?? 0.0;
    if (airtimeHours >= 14) return Colors.green;
    if (airtimeHours >= 10) return Colors.orange;
    return Colors.red;
  }

  void _resetFilters() {
    _regNoController.clear();
    _uniqueIdController.clear();
    _aircraftTypeController.clear();
    _linkageStatus = null;
    _arrBillStatus = null;
    _depBillStatus = null;
    _udfBillStatus = null;
    _page = 0;
    _debounceSearch();
  }

  // ------------------------------ UI ------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Flights'),
        actions: [
          IconButton(onPressed: _resetFilters, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTextField(_regNoController, 'Registration No.'),
              _buildTextField(_uniqueIdController, 'Unique ID'),
              _buildTextField(_aircraftTypeController, 'Aircraft Type'),
              const SizedBox(height: 8),
              _buildDropdown(
                label: 'Linkage Status',
                value: _linkageStatus,
                items: ['Same', 'Different'],
                onChanged: (v) => setState(() => _linkageStatus = v),
              ),
              _buildDropdown(
                label: 'Arrival Bill Status',
                value: _arrBillStatus,
                items: ['Billed', 'Unbilled'],
                onChanged: (v) => setState(() => _arrBillStatus = v),
              ),
              _buildDropdown(
                label: 'Departure Bill Status',
                value: _depBillStatus,
                items: ['Billed', 'Unbilled'],
                onChanged: (v) => setState(() => _depBillStatus = v),
              ),
              _buildDropdown(
                label: 'UDF Bill Status',
                value: _udfBillStatus,
                items: ['Billed', 'Unbilled'],
                onChanged: (v) => setState(() => _udfBillStatus = v),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.search),
                onPressed: _isLoading ? null : _debounceSearch,
                label: const Text("Search Flights"),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              ),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 16)),
                ),
              if (_results.isNotEmpty) _buildResultsList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              controller.clear();
              _debounceSearch();
            },
          ),
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => _debounceSearch(),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (v) {
          onChanged(v);
          _debounceSearch();
        },
      ),
    );
  }

  Widget _buildResultsList() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final item = _results[index];
          final airtimeColor = _getAirtimeColor(item['Airtime Hours']);
          return Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${item['Reg No']} (${item['Unique Id']})",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  _buildDetail("Operator", item['Operator Name']),
                  _buildDetail("Aircraft", item['Aircraft Type']),
                  _buildDetail("Date", item['Date']),
                  _buildDetail("Airtime", item['Airtime Hours'], color: airtimeColor),
                  _buildDetail("Linkage", item['Linkage Status']),
                  _buildDetail("Arr Bill", item['Arr Bill Status']),
                  _buildDetail("Dep Bill", item['Dep Bill Status']),
                  _buildDetail("UDF Bill", item['UDF Bill Status']),
                  _buildDetail("Landing", item['Landing']),
                  _buildDetail("UDF Charge", item['UDF Charge']),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetail(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500)),
        Text(value, style: TextStyle(color: color ?? Colors.black)),
      ],
    );
  }
}
