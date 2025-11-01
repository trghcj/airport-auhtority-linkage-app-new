import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:airport_auhtority_linkage_app/config/config.dart';
import 'package:airport_auhtority_linkage_app/services/analysis_service.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';

extension StringCapitalization on String {
  String capitalize() {
    return isEmpty ? this : this[0].toUpperCase() + substring(1);
  }
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
    _logger.d('Initializing StatsPage with docId: ${widget.docId} at ${DateTime.now().toIso8601String()}');
    if (widget.docId == null) {
      setState(() {
        _error = 'No document ID available. Please upload or analyze a file first.';
      });
    } else {
      _fetchStats();
    }
  }

  Future<void> _fetchStats() async {
    if (widget.docId == null) {
      setState(() {
        _error = 'No document ID available. Please upload or analyze a file first.';
        _isLoading = false;
      });
      _showSnackBar('No document ID available. Please upload or analyze a file first.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final statsData = await _analysisService.fetchStatsData(widget.docId!, _groupBy);
      if (!mounted) return;

      setState(() {
        _stats = statsData.map((stat) {
          // Debug logging to check raw data
          _logger.d('Raw stat data: $stat');

          // Determine group key dynamically
          final groupKey = _groupBy == 'operator' ? 'Group_Name' : 'Region';
          String groupValue = stat[groupKey] ?? stat['operator'] ?? stat['region'] ?? 'N/A';
          if (groupValue == 'N/A') {
            _logger.w('Missing $groupKey, falling back to alternative keys or N/A for stat: ${jsonEncode(stat)}');
          }

          // Parse financial values
          final landingCharges = double.tryParse((stat['Total_Landing_Charges']?.toString() ?? '0.0').replaceAll('₹', '').replaceAll(',', '')) ?? 0.0;
          final udfCharges = double.tryParse((stat['Total_UDF_Charges']?.toString() ?? '0.0').replaceAll('₹', '').replaceAll(',', '')) ?? 0.0;

          // Determine bill statuses based on counts
          final arrBilledCount = (stat['Arr_Billed_Count'] ?? 0) as int;
          final depBilledCount = (stat['Dep_Billed_Count'] ?? 0) as int;
          final udfBilledCount = (stat['UDF_Billed_Count'] ?? 0) as int;
          final arrBillStatus = arrBilledCount > 0 ? 'Yes' : 'No';
          final depBillStatus = depBilledCount > 0 ? 'Yes' : 'No';
          final udfBillStatus = udfBilledCount > 0 ? 'Yes' : 'No';

          // Calculate airtime color dynamically
          Color airtimeColor = Colors.grey;
          final avgAirtime = stat['Avg_Airtime_Hours'] ?? 'N/A';
          if (avgAirtime != 'N/A') {
            try {
              final hours = double.parse(avgAirtime.toString().split(' ').first);
              airtimeColor = hours < 10 ? Colors.red : (hours < 14 ? Colors.yellow : Colors.green);
            } catch (e) {
              _logger.w('Error parsing avg airtime for stat: $e, using grey');
            }
          }

          return {
            ...stat,
            groupKey: groupValue, // Ensure the correct group key is set
            'Total_Landing_Charges': '₹${landingCharges.toStringAsFixed(2)}',
            'Total_UDF_Charges': '₹${udfCharges.toStringAsFixed(2)}',
            'ArrBillStatus': arrBillStatus,
            'DepBillStatus': depBillStatus,
            'UDFBillStatus': udfBillStatus,
            'Airtime_Color': airtimeColor.value.toRadixString(16), // Store color as hex
          };
        }).toList();
        _isLoading = false;
        _lastRefresh = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)); // 01:53 AM IST
      });
      _logger.d('Fetched ${_stats.length} stats records at ${DateTime.now().toIso8601String()}');
      _showSnackBar('Stats refreshed successfully.');
    } catch (e, stackTrace) {
      if (mounted) {
        _logger.e('Stats error at ${DateTime.now().toIso8601String()}: $e\nStackTrace: $stackTrace');
        setState(() {
          _error = 'Error fetching stats: ${e.toString().contains("Network error") ? "Check your internet connection and try again." : e.toString()}';
          _isLoading = false;
        });
        _showSnackBar('Error fetching stats: ${e.toString().contains("Network error") ? "Check your internet connection." : e.toString()}');
      }
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Color _getBillStatusColor(String status) {
    return status.toLowerCase() == 'yes' ? Colors.green : Colors.red;
  }

  Widget _buildStatRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 14,
              color: color ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Flight Statistics',
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
            onPressed: _isLoading ? null : _fetchStats,
            tooltip: 'Refresh Stats',
          ),
          if (_lastRefresh != null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Text(
                'Last: ${_lastRefresh!.toString().split('.').first} IST',
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButton<String>(
                value: _groupBy,
                items: ['operator', 'region'].map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(
                        s.capitalize(),
                        style: const TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 14,
                        ),
                      ),
                    )).toList(),
                onChanged: (value) {
                  if (value != null && value != _groupBy) {
                    setState(() {
                      _groupBy = value;
                      _stats = [];
                    });
                    _fetchStats();
                  }
                },
                dropdownColor: Theme.of(context).cardColor,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(child: CircularProgressIndicator()),
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
                )
              else if (_stats.isEmpty && !_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text(
                    'No statistics available. Upload or analyze data to view stats.',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (_stats.isNotEmpty)
                Container(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: _stats.length,
                    itemBuilder: (context, index) {
                      final item = _stats[index];
                      final groupKey = _groupBy == 'operator' ? 'Group_Name' : 'Region';
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 8.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16.0),
                          title: Text(
                            item[groupKey] ?? 'N/A',
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStatRow('Operator', item['Group_Name'] ?? 'Unknown'),
                              _buildStatRow('Flights', item['Flight_Count']?.toString() ?? '0'),
                              _buildStatRow('Avg Airtime', item['Avg_Airtime_Hours'] ?? 'N/A',
                                  color: item['Airtime_Color'] != null
                                      ? Color(int.tryParse('0xff${item['Airtime_Color']}', radix: 16) ?? 0xff808080)
                                      : Colors.grey),
                              _buildStatRow('Total Airtime', item['Total_Hours'] ?? 'N/A',
                                  color: item['Airtime_Color'] != null
                                      ? Color(int.tryParse('0xff${item['Airtime_Color']}', radix: 16) ?? 0xff808080)
                                      : Colors.grey),
                              _buildStatRow('Same Linkage', item['Same_Linkage_Count']?.toString() ?? '0'),
                              _buildStatRow('Different Linkage', item['Different_Linkage_Count']?.toString() ?? '0'),
                              _buildStatRow('Arr Billed', item['Arr_Billed_Count']?.toString() ?? '0'),
                              _buildStatRow('Arr UnBilled', item['Arr_UnBilled_Count']?.toString() ?? '0'),
                              _buildStatRow('Dep Billed', item['Dep_Billed_Count']?.toString() ?? '0'),
                              _buildStatRow('Dep UnBilled', item['Dep_UnBilled_Count']?.toString() ?? '0'),
                              _buildStatRow('UDF Billed', item['UDF_Billed_Count']?.toString() ?? '0'),
                              _buildStatRow('UDF UnBilled', item['UDF_UnBilled_Count']?.toString() ?? '0'),
                              _buildStatRow('Total Landing', item['Total_Landing_Charges'] ?? '₹0.00'),
                              _buildStatRow('Total UDF', item['Total_UDF_Charges'] ?? '₹0.00'),
                              _buildStatRow('Arr Bill Status', item['ArrBillStatus'] ?? 'N/A',
                                  color: _getBillStatusColor(item['ArrBillStatus'] ?? 'N/A')),
                              _buildStatRow('Dep Bill Status', item['DepBillStatus'] ?? 'N/A',
                                  color: _getBillStatusColor(item['DepBillStatus'] ?? 'N/A')),
                              _buildStatRow('UDF Bill Status', item['UDFBillStatus'] ?? 'N/A',
                                  color: _getBillStatusColor(item['UDFBillStatus'] ?? 'N/A')),
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
      ),
    );
  }
}