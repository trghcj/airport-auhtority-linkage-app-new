import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:airport_auhtority_linkage_app/config/config.dart';
import 'package:airport_auhtority_linkage_app/services/analysis_service.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';

extension StringCapitalization on String {
  String capitalize() => isEmpty ? this : this[0].toUpperCase() + substring(1);
}

class StatsPage extends StatefulWidget {
  final String? docId;

  const StatsPage({super.key, this.docId});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final Logger _logger = Logger();
  final AnalysisService _analysisService = AnalysisService();
  List<Map<String, dynamic>> _stats = [];
  bool _isLoading = false;
  String? _error;
  String _groupBy = 'operator';
  DateTime? _lastRefresh;

  @override
  void initState() {
    super.initState();
    _logger.i(
      'StatsPage initialized with docId: ${widget.docId} at '
      '${DateFormat("yyyy-MM-dd HH:mm:ss 'IST'").format(DateTime.now())}',
    );

    if (widget.docId == null || widget.docId!.isEmpty) {
      setState(() {
        _error = '⚠️ No document ID available. Please upload or analyze data first.';
      });
    } else {
      _fetchStats();
    }
  }

  /// Fetch statistics data from backend
  Future<void> _fetchStats() async {
    if (widget.docId == null || widget.docId!.isEmpty) {
      _setError('⚠️ No document ID available. Please upload or analyze data first.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final statsData = await _analysisService.fetchStatsData(widget.docId!, _groupBy);
      if (!mounted) return;

      if (statsData.isEmpty) {
        _setError('No statistics available. Try re-uploading or analyzing your file.');
        return;
      }

      final processed = statsData.map((stat) {
        final groupKey = _groupBy == 'operator' ? 'Group_Name' : 'Region';
        final groupValue = stat[groupKey] ?? 'N/A';

        // Parse financial values safely
        double landingCharges = double.tryParse(
              (stat['Total_Landing_Charges']?.toString() ?? '0')
                  .replaceAll('₹', '')
                  .replaceAll(',', ''),
            ) ??
            0.0;

        double udfCharges = double.tryParse(
              (stat['Total_UDF_Charges']?.toString() ?? '0')
                  .replaceAll('₹', '')
                  .replaceAll(',', ''),
            ) ??
            0.0;

        // Determine bill statuses
        final arrBilled = (stat['Arr_Billed_Count'] ?? 0) > 0;
        final depBilled = (stat['Dep_Billed_Count'] ?? 0) > 0;
        final udfBilled = (stat['UDF_Billed_Count'] ?? 0) > 0;

        // Determine airtime color
        Color airtimeColor = Colors.grey;
        final avgAirtime = stat['Avg_Airtime_Hours']?.toString() ?? 'N/A';
        if (avgAirtime != 'N/A') {
          try {
            final hours = double.parse(avgAirtime.split(' ').first);
            if (hours < 10) {
              airtimeColor = Colors.red;
            } else if (hours < 14) {
              airtimeColor = Colors.orange;
            } else {
              airtimeColor = Colors.green;
            }
          } catch (e) {
            _logger.w('Error parsing Avg_Airtime_Hours: $e');
          }
        }

        return {
          ...stat,
          'GroupValue': groupValue,
          'Total_Landing_Charges': '₹${landingCharges.toStringAsFixed(2)}',
          'Total_UDF_Charges': '₹${udfCharges.toStringAsFixed(2)}',
          'ArrBillStatus': arrBilled ? 'Yes' : 'No',
          'DepBillStatus': depBilled ? 'Yes' : 'No',
          'UDFBillStatus': udfBilled ? 'Yes' : 'No',
          'Airtime_Color': airtimeColor.value.toRadixString(16),
        };
      }).toList();

      setState(() {
        _stats = processed;
        _isLoading = false;
        _lastRefresh = DateTime.now();
      });

      _logger.i('Fetched ${_stats.length} stats grouped by $_groupBy');
      _showSnackBar('✅ Stats refreshed successfully');
    } catch (e, stack) {
      _logger.e('Error fetching stats: $e\n$stack');
      _setError(
        e.toString().contains('Network')
            ? 'Network issue. Please check your internet connection.'
            : 'Error fetching statistics: $e',
      );
    }
  }

  void _setError(String message) {
    setState(() {
      _error = message;
      _isLoading = false;
      _stats = [];
    });
    _showSnackBar(message);
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
  }

  Color _getBillStatusColor(String status) =>
      status.toLowerCase() == 'yes' ? Colors.green : Colors.red;

  Widget _buildStatRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
          Text(value, style: TextStyle(color: color ?? Colors.black, fontSize: 14)),
        ],
      ),
    );
  }

  // ------------------------------ UI ------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flight Statistics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchStats,
          ),
          if (_lastRefresh != null)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Center(
                child: Text(
                  'Last: ${DateFormat('HH:mm:ss').format(_lastRefresh!)}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                    ),
                  )
                : _stats.isEmpty
                    ? const Center(
                        child: Text(
                          'No statistics available.\nPlease analyze data first.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButton<String>(
                            value: _groupBy,
                            items: ['operator', 'region']
                                .map((v) => DropdownMenuItem(value: v, child: Text(v.capitalize())))
                                .toList(),
                            onChanged: (v) {
                              if (v != null && v != _groupBy) {
                                setState(() {
                                  _groupBy = v;
                                  _stats = [];
                                });
                                _fetchStats();
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _stats.length,
                              itemBuilder: (context, index) {
                                final item = _stats[index];
                                final airtimeColor = Color(
                                  int.tryParse('0xff${item['Airtime_Color']}', radix: 16) ??
                                      0xff808080,
                                );
                                return Card(
                                  elevation: 3,
                                  margin: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['GroupValue'] ?? 'N/A',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        _buildStatRow(
                                            'Flights', item['Flight_Count']?.toString() ?? '0'),
                                        _buildStatRow('Avg Airtime',
                                            item['Avg_Airtime_Hours'] ?? 'N/A',
                                            color: airtimeColor),
                                        _buildStatRow(
                                            'Total Airtime', item['Total_Hours'] ?? 'N/A',
                                            color: airtimeColor),
                                        _buildStatRow('Same Linkage',
                                            item['Same_Linkage_Count']?.toString() ?? '0'),
                                        _buildStatRow('Different Linkage',
                                            item['Different_Linkage_Count']?.toString() ?? '0'),
                                        _buildStatRow('Total Landing',
                                            item['Total_Landing_Charges'] ?? '₹0.00'),
                                        _buildStatRow('Total UDF',
                                            item['Total_UDF_Charges'] ?? '₹0.00'),
                                        _buildStatRow('Arr Bill Status',
                                            item['ArrBillStatus'] ?? 'N/A',
                                            color: _getBillStatusColor(
                                                item['ArrBillStatus'] ?? 'N/A')),
                                        _buildStatRow('Dep Bill Status',
                                            item['DepBillStatus'] ?? 'N/A',
                                            color: _getBillStatusColor(
                                                item['DepBillStatus'] ?? 'N/A')),
                                        _buildStatRow('UDF Bill Status',
                                            item['UDFBillStatus'] ?? 'N/A',
                                            color: _getBillStatusColor(
                                                item['UDFBillStatus'] ?? 'N/A')),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }
}
