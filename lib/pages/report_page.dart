import 'dart:async';
import 'package:beewhere/controller/report_api.dart';
import 'package:beewhere/widgets/drawer.dart';
import 'package:beewhere/widgets/bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:beewhere/services/connectivity_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final int _currentIndex = 2; // Report tab index

  // Form state
  String _reportType = 'attendance'; // Default: attendance
  String _duration = 'month'; // Default: monthly
  DateTime? _startDate;
  DateTime? _endDate;
  bool _showStatus = false; // For activity reports
  bool _genReport = false; // Whether to show report data

  // Navigation counters
  int _prevCount = 0;
  int _nextCount = 0;

  // Report data
  bool _isLoading = false;
  List<dynamic> _reportData = [];
  String? _errorMessage;

  // Connectivity state
  bool _isOnline = true;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    // Initialize with current month
    _calculateDateRange();
    _initConnectivityListener();
  }

  void _initConnectivityListener() {
    _isOnline = ConnectivityService.isOnline;
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      ConnectivityResult result,
    ) {
      if (mounted) {
        setState(() {
          _isOnline = result != ConnectivityResult.none;
        });
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  /// Calculate date range based on duration selection
  void _calculateDateRange() {
    final now = DateTime.now();

    switch (_duration) {
      case 'week':
        // ISO week: Monday to Sunday
        final weekday = now.weekday;
        _startDate = now.subtract(Duration(days: weekday - 1));
        _endDate = _startDate!.add(const Duration(days: 6));
        break;
      case 'month':
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 0); // Last day of month
        break;
      case 'year':
        _startDate = DateTime(now.year, 1, 1);
        _endDate = DateTime(now.year, 12, 31);
        break;
      case 'custom':
        // Will be set by date pickers
        break;
    }

    // Set time to start/end of day
    if (_startDate != null && _duration != 'custom') {
      _startDate = DateTime(
        _startDate!.year,
        _startDate!.month,
        _startDate!.day,
        0,
        0,
        0,
      );
    }
    if (_endDate != null && _duration != 'custom') {
      _endDate = DateTime(
        _endDate!.year,
        _endDate!.month,
        _endDate!.day,
        23,
        59,
        59,
      );
    }
  }

  /// Navigate to previous period
  void _navigatePrev() {
    if (_duration == 'custom') return;

    setState(() {
      _prevCount++;
      _nextCount = _nextCount > 0 ? _nextCount - 1 : 0;

      final now = DateTime.now();
      switch (_duration) {
        case 'week':
          final weekStart = now.subtract(
            Duration(days: now.weekday - 1 + (_prevCount * 7)),
          );
          _startDate = weekStart;
          _endDate = weekStart.add(const Duration(days: 6));
          break;
        case 'month':
          _startDate = DateTime(now.year, now.month - _prevCount, 1);
          _endDate = DateTime(now.year, now.month - _prevCount + 1, 0);
          break;
        case 'year':
          _startDate = DateTime(now.year - _prevCount, 1, 1);
          _endDate = DateTime(now.year - _prevCount, 12, 31);
          break;
      }
    });

    // Automatically fetch data for new period
    _fetchReportData();
  }

  /// Navigate to next period
  void _navigateNext() {
    if (_duration == 'custom' || _prevCount == 0) return;

    setState(() {
      _prevCount--;
      _nextCount++;

      final now = DateTime.now();
      switch (_duration) {
        case 'week':
          final weekStart = now.subtract(
            Duration(days: now.weekday - 1 + (_prevCount * 7)),
          );
          _startDate = weekStart;
          _endDate = weekStart.add(const Duration(days: 6));
          break;
        case 'month':
          _startDate = DateTime(now.year, now.month - _prevCount, 1);
          _endDate = DateTime(now.year, now.month - _prevCount + 1, 0);
          break;
        case 'year':
          _startDate = DateTime(now.year - _prevCount, 1, 1);
          _endDate = DateTime(now.year - _prevCount, 12, 31);
          break;
      }
    });

    // Automatically fetch data for new period
    _fetchReportData();
  }

  /// Show report based on current filters
  Future<void> _showReport() async {
    // Reset navigation counters
    _prevCount = 0;
    _nextCount = 0;

    // Validate custom dates
    if (_duration == 'custom') {
      if (_startDate == null || _endDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select start and end dates')),
        );
        return;
      }

      if (_startDate!.isAfter(_endDate!)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Start date must be before end date')),
        );
        return;
      }
    } else {
      _calculateDateRange();
    }

    setState(() {
      _genReport = true;
    });

    await _fetchReportData();
  }

  /// Fetch report data (called by Show button and navigation)
  Future<void> _fetchReportData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Convert to Unix timestamps (seconds)
    final startTimestamp = _startDate!.millisecondsSinceEpoch ~/ 1000;
    final endTimestamp = _endDate!.millisecondsSinceEpoch ~/ 1000;

    final result = await ReportApi.getReport(
      context,
      _reportType,
      startTimestamp,
      endTimestamp,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;

        if (result['success']) {
          _reportData = result['data'] as List;

          // Process dates for attendance reports
          if (_reportType == 'attendance') {
            for (var item in _reportData) {
              if (item['inTime'] != null) {
                // API returns format: "2025/12/01 02:16" - convert slashes to dashes
                item['inTime'] = DateTime.parse(
                  item['inTime'].toString().replaceAll('/', '-'),
                );
              }
              if (item['outTime'] != null) {
                // API returns format: "2025/12/01 02:16" - convert slashes to dashes
                item['outTime'] = DateTime.parse(
                  item['outTime'].toString().replaceAll('/', '-'),
                );
              }
            }
          }
        } else {
          _errorMessage = result['message'];
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/background_login.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: AppBar(
            title: const Text('Report'),
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _isOnline
                      ? Colors.green.withOpacity(0.2)
                      : Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isOnline ? Colors.green : Colors.red,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isOnline ? Icons.wifi : Icons.wifi_off,
                      color: _isOnline ? Colors.green : Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _isOnline ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
      drawer: const AppDrawer(),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacementNamed(context, '/home');
          } else if (index == 1) {
            Navigator.pushReplacementNamed(context, '/history');
          } else if (index == 3) {
            Navigator.pushReplacementNamed(context, '/profile');
          }
        },
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Report Type Dropdown
            _buildDropdown(
              label: 'Report Type',
              value: _reportType,
              items: [
                {'value': 'attendance', 'label': 'Attendance'},
                {'value': 'activity', 'label': 'Activity'},
              ],
              onChanged: (value) {
                setState(() {
                  _reportType = value!;
                  _genReport = false;
                });
              },
            ),
            const SizedBox(height: 16),

            // Show Status Checkbox (only for activity reports)
            if (_reportType == 'activity')
              CheckboxListTile(
                title: const Text('Show Status'),
                value: _showStatus,
                onChanged: (value) {
                  setState(() {
                    _showStatus = value ?? false;
                  });
                },
                contentPadding: EdgeInsets.zero,
              ),

            // Duration Dropdown
            _buildDropdown(
              label: 'Duration',
              value: _duration,
              items: [
                {'value': 'week', 'label': 'Weekly'},
                {'value': 'month', 'label': 'Monthly'},
                {'value': 'year', 'label': 'Yearly'},
                {'value': 'custom', 'label': 'Custom'},
              ],
              onChanged: (value) {
                setState(() {
                  _duration = value!;
                  _genReport = false;

                  if (_duration != 'custom') {
                    _calculateDateRange();
                  }
                });
              },
            ),
            const SizedBox(height: 16),

            // Custom Date Pickers
            if (_duration == 'custom') ...[
              _buildDatePicker(
                label: 'Start Date',
                date: _startDate,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _startDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() {
                      _startDate = picked;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              _buildDatePicker(
                label: 'End Date',
                date: _endDate,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _endDate ?? DateTime.now(),
                    firstDate: _startDate ?? DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() {
                      _endDate = picked;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
            ],

            // Show Button
            ElevatedButton(
              onPressed: _showReport,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1), // Purple-blue theme
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Show Report'),
            ),
            const SizedBox(height: 24),

            // Navigation buttons and report display
            if (_genReport) ...[
              // Prev/Next Navigation (hidden for custom)
              if (_duration != 'custom')
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _navigatePrev,
                    ),
                    Text(
                      _getDurationLabel(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _prevCount > 0 ? _navigateNext : null,
                    ),
                  ],
                ),

              const SizedBox(height: 16),

              // Loading / Error / Data display
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (_errorMessage != null)
                Center(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              else if (_reportData.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text('No records found'),
                  ),
                )
              else if (_reportType == 'attendance')
                _buildAttendanceTable()
              else
                _buildActivityTable(),
            ],
          ],
        ),
      ),
    );
  }

  /// Build dropdown widget
  Widget _buildDropdown({
    required String label,
    required String value,
    required List<Map<String, String>> items,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item['value'],
              child: Text(item['label']!),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  /// Build date picker widget
  Widget _buildDatePicker({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          child: InputDecorator(
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.calendar_today),
            ),
            child: Text(
              date != null
                  ? DateFormat('yyyy-MM-dd').format(date)
                  : 'Select date',
            ),
          ),
        ),
      ],
    );
  }

  /// Get duration label for display
  String _getDurationLabel() {
    if (_startDate == null || _endDate == null) return '';

    switch (_duration) {
      case 'week':
        return '${DateFormat('d MMM').format(_startDate!)} - ${DateFormat('d MMM yyyy').format(_endDate!)}';
      case 'month':
        return DateFormat('MMMM yyyy').format(_startDate!);
      case 'year':
        return DateFormat('yyyy').format(_startDate!);
      default:
        return '${DateFormat('d MMM yyyy').format(_startDate!)} - ${DateFormat('d MMM yyyy').format(_endDate!)}';
    }
  }

  /// Build attendance report table
  Widget _buildAttendanceTable() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // Header Row
            Container(
              decoration: BoxDecoration(
                color: const Color(
                  0xFF6366F1,
                ).withOpacity(0.1), // Purple-blue theme light
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Text(
                        'Date',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Text(
                        'In Time',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Text(
                        'Out Time',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Text(
                        'Duration (hrs)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Data Rows
            ..._reportData.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isLast = index == _reportData.length - 1;

              return Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: isLast
                        ? BorderSide.none
                        : BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    // Date
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Text(
                          item['date'] ?? '-N/A-',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),

                    // In Time
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: item['inTime'] != null
                                ? Colors.green.shade50
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item['inTime'] != null
                                ? DateFormat('hh:mm a').format(item['inTime'])
                                : '-N/A-',
                            style: TextStyle(
                              fontSize: 13,
                              color: item['inTime'] != null
                                  ? Colors.green.shade900
                                  : Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Out Time
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: item['outTime'] != null
                                ? Colors.orange.shade50
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item['outTime'] != null
                                ? DateFormat('hh:mm a').format(item['outTime'])
                                : '-N/A-',
                            style: TextStyle(
                              fontSize: 13,
                              color: item['outTime'] != null
                                  ? Colors.orange.shade900
                                  : Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Duration
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Builder(
                          builder: (context) {
                            // Parse duration to check if it meets 9 hours
                            final durationStr =
                                item['duration']?.toString() ?? '0';
                            double durationValue = 0;
                            try {
                              durationValue = double.parse(durationStr);
                            } catch (e) {
                              durationValue = 0;
                            }

                            // Red if less than 9 hours, purple-blue if 9+ hours
                            final isUndertime = durationValue < 9.0;
                            final bgColor = isUndertime
                                ? Colors.red.shade50
                                : const Color(0xFF6366F1).withOpacity(0.1);
                            final textColor = isUndertime
                                ? Colors.red.shade700
                                : const Color(0xFF6366F1);

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                durationStr == '0' ? '-N/A-' : durationStr,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  /// Build activity report table
  Widget _buildActivityTable() {
    return Column(
      children: _reportData.map((item) {
        final date = item['date'];
        final activityList = item['activityList'] as List? ?? [];

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date header
                Text(
                  date != null
                      ? '${DateFormat('d MMM yyyy').format(DateTime.parse(date))} (${DateFormat('EEE').format(DateTime.parse(date))})'
                      : 'Unknown Date',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Divider(),

                // Activity list
                if (activityList.isEmpty)
                  const Text('No activities')
                else
                  ...activityList[0].map<Widget>((activity) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Expanded(child: Text(activity['name'] ?? '')),
                          if (_showStatus)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: activity['statusFlag'] == true
                                    ? Colors.green.shade100
                                    : Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                activity['statusFlag'] == true
                                    ? 'Done'
                                    : 'Pending',
                                style: TextStyle(
                                  color: activity['statusFlag'] == true
                                      ? Colors.green.shade800
                                      : Colors.orange.shade800,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
