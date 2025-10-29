import 'dart:async';
import 'dart:convert';
import 'package:airport_auhtority_linkage_app/providers/search_provider.dart';
import 'package:flutter/material.dart';
import 'package:airport_auhtority_linkage_app/services/analysis_service.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart'; // For IST formatting

// Fallback Config if not defined elsewhere
class Config {
  static const String apiBaseUrl = 'http://localhost:5003'; // Adjust as needed
}

// Static current date and time (01:17 AM IST, August 03, 2025)
final DateTime _currentDate = DateTime(2025, 8, 3, 1, 17, 0, 0, 19800);

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
  static const int _limit = 100; // Target at least 100 entries

  @override
  void initState() {
    super.initState();
    _regNoController.text = widget.filterBy.trim(); // Preserve case for display
    _logger.d('Initializing SearchPage with docId: ${widget.docId} at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
    if (widget.docId != null) {
      _fetchResults();
    } else {
      setState(() {
        _error = 'No document ID available. Please upload or analyze a file first.';
      });
    }
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
    if (widget.docId == null) {
      setState(() {
        _error = 'No document ID available. Please upload or analyze a file first.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final query = [
        _regNoController.text.trim(),
        _uniqueIdController.text.trim(),
        _aircraftTypeController.text.trim(),
        _linkageStatus,
        _arrBillStatus,
        _depBillStatus,
        _udfBillStatus,
      ].where((s) => s?.isNotEmpty ?? false).join(' ');

      final results = await _analysisService.searchFlights(widget.docId!, {
        'query': query,
        'page': _page.toString(),
        'limit': _limit.toString(),
      });

      if (!mounted) return;

      setState(() {
        _results = results.map((result) {
          // Map only the fields provided by searchFlights, with fallbacks
          return {
            'Reg No': result['Reg No'] ?? 'N/A',
            'Date': result['Date'] ?? 'N/A',
            'Count': result['Count'] ?? '1',
            'Unique Id': 'N/A', // Not available from searchFlights
            'Operator Name': 'N/A', // Not available from searchFlights
            'Aircraft Type': 'N/A', // Not available from searchFlights
            'Airtime Hours': 'N/A', // Not available from searchFlights
            'Linkage Status': 'N/A', // Not available from searchFlights
            'Arr Bill Status': 'N/A', // Not available from searchFlights
            'Dep Bill Status': 'N/A', // Not available from searchFlights
            'UDF Bill Status': 'N/A', // Not available from searchFlights
            'Landing': '₹0.00', // Not available from searchFlights
            'UDF Charge': '₹0.00', // Not available from searchFlights
          };
        }).toList();
        _isLoading = false;
        _logger.d('Fetched ${_results.length} search results at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}');
      });
    } catch (e, stackTrace) {
      if (mounted) {
        _logger.e('Search error at ${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(_currentDate)}: $e\nStackTrace: $stackTrace');
        setState(() {
          _error = 'Error fetching results: ${e.toString().contains("Network error") ? "Check your internet connection and try again." : e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  void _debounceSearch() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _fetchResults();
    });
  }

  void _clearTextField(TextEditingController controller) {
    controller.clear();
    _debounceSearch();
  }

  void _resetDropdown(void Function(String?) setter) {
    setter(null);
    _debounceSearch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Search Flights',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 4,
        shadowColor: Colors.grey.withOpacity(0.3),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _regNoController.clear();
              _uniqueIdController.clear();
              _aircraftTypeController.clear();
              _linkageStatus = null;
              _arrBillStatus = null;
              _depBillStatus = null;
              _udfBillStatus = null;
              _page = 0;
              _debounceSearch();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTextField(
                controller: _regNoController,
                label: 'Registration No.',
                onClear: () => _clearTextField(_regNoController),
              ),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _uniqueIdController,
                label: 'Unique ID',
                onClear: () => _clearTextField(_uniqueIdController),
              ),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _aircraftTypeController,
                label: 'Aircraft Type',
                onClear: () => _clearTextField(_aircraftTypeController),
              ),
              const SizedBox(height: 8),
              _buildDropdown(
                value: _linkageStatus,
                hint: 'Linkage Status',
                items: ['Same', 'Different'],
                onChanged: (value) {
                  setState(() => _linkageStatus = value);
                  _debounceSearch();
                },
                onReset: () => _resetDropdown((v) => _linkageStatus = v),
              ),
              const SizedBox(height: 8),
              _buildDropdown(
                value: _arrBillStatus,
                hint: 'Arrival Bill Status',
                items: ['Billed', 'Unbilled'],
                onChanged: (value) {
                  setState(() => _arrBillStatus = value);
                  _debounceSearch();
                },
                onReset: () => _resetDropdown((v) => _arrBillStatus = v),
              ),
              const SizedBox(height: 8),
              _buildDropdown(
                value: _depBillStatus,
                hint: 'Departure Bill Status',
                items: ['Billed', 'Unbilled'],
                onChanged: (value) {
                  setState(() => _depBillStatus = value);
                  _debounceSearch();
                },
                onReset: () => _resetDropdown((v) => _depBillStatus = v),
              ),
              const SizedBox(height: 8),
              _buildDropdown(
                value: _udfBillStatus,
                hint: 'UDF Bill Status',
                items: ['Billed', 'Unbilled'],
                onChanged: (value) {
                  setState(() => _udfBillStatus = value);
                  _debounceSearch();
                },
                onReset: () => _resetDropdown((v) => _udfBillStatus = v),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _debounceSearch,
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(MediaQuery.of(context).size.width - 32, 50),
                ),
                child: const Text(
                  'Search',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 16,
                  ),
                ),
              ),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      color: Colors.red,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (_results.isNotEmpty || _isLoading || _error != null)
                Container(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
                  child: SingleChildScrollView(
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final item = _results[index];
                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(vertical: 8.0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16.0),
                            title: Text(
                              '${item['Reg No']} - ${item['Count']} Flights',
                              style: const TextStyle(
                                fontFamily: 'Roboto',
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDetailRow('Reg No', item['Reg No']),
                                _buildDetailRow('Date', item['Date']),
                                _buildDetailRow('Count', item['Count'].toString()),
                                _buildDetailRow('Unique ID', item['Unique Id']),
                                _buildDetailRow('Operator Name', item['Operator Name']),
                                _buildDetailRow('Aircraft Type', item['Aircraft Type']),
                                _buildDetailRow('Airtime', item['Airtime Hours'], color: Colors.grey), // Static color
                                _buildDetailRow('Linkage', item['Linkage Status']),
                                _buildDetailRow('Arr Bill', item['Arr Bill Status']),
                                _buildDetailRow('Dep Bill', item['Dep Bill Status']),
                                _buildDetailRow('UDF Bill', item['UDF Bill Status']),
                                _buildDetailRow('Landing', item['Landing']),
                                _buildDetailRow('UDF Charge', item['UDF Charge']),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required VoidCallback onClear,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 14),
            ),
            onChanged: (_) => _debounceSearch(),
            style: const TextStyle(fontFamily: 'Roboto', fontSize: 14),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: onClear,
        ),
      ],
    );
  }

  Widget _buildDropdown({
    String? value,
    required String hint,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required VoidCallback onReset,
  }) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: value,
            hint: Text(
              hint,
              style: const TextStyle(fontFamily: 'Roboto', fontSize: 14),
            ),
            items: items.map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(
                    s,
                    style: const TextStyle(fontFamily: 'Roboto', fontSize: 14),
                  ),
                )).toList(),
            onChanged: onChanged,
            decoration: const InputDecoration(
              labelStyle: TextStyle(fontFamily: 'Roboto', fontSize: 14),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: onReset,
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: color ?? Colors.black,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}