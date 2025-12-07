import 'package:beewhere/controller/history_api.dart';
import 'package:beewhere/theme/color_theme.dart';
import 'package:beewhere/widgets/bottom_nav.dart';
import 'package:beewhere/widgets/drawer.dart';
import 'package:beewhere/widgets/edit_activity_dialog.dart';
import 'package:beewhere/widgets/edit_time_request_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<dynamic> _records = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;
  double _totalHours = 0.0;

  // Pagination - CUMULATIVE LOADING STRATEGY
  final ScrollController _scrollController = ScrollController();

  // ✅ Changed: Use dynamic limit instead of page number
  int _currentLimit = 5;
  final int _incrementStep = 5; // How many more to fetch each time
  int _previousRecordCount = 0; // To track if we got new data

  bool _hasMore = true;

  // Date range filter
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    // Set default date range (last 30 days)
    _endDate = DateTime.now();
    _startDate = _endDate!.subtract(const Duration(days: 30));

    _scrollController.addListener(_onScroll);
    _loadHistory();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreHistory();
    }
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;

      // ✅ Reset cumulative counters
      _currentLimit = 5;
      _previousRecordCount = 0;

      _records = [];
      _hasMore = true;
    });

    await _fetchHistoryData();
  }

  Future<void> _loadMoreHistory() async {
    if (!mounted) return;
    setState(() {
      _isLoadingMore = true;
      // ✅ Increase limit to fetch more data from the start
      _currentLimit += _incrementStep;
    });

    await _fetchHistoryData(isLoadMore: true);
  }

  Future<void> _fetchHistoryData({bool isLoadMore = false}) async {
    try {
      final startDateStr = _startDate != null
          ? DateFormat('yyyy-MM-dd').format(_startDate!)
          : null;
      final endDateStr = _endDate != null
          ? DateFormat('yyyy-MM-dd').format(_endDate!)
          : null;

      final result = await HistoryApi.getAttendanceHistory(
        context,
        startDate: startDateStr,
        endDate: endDateStr,
        limit: _currentLimit, // ✅ Request larger batch
        offset: 0, // ✅ Always start from 0
      );

      if (mounted) {
        if (result['success']) {
          final newRecords = result['data'] as List<dynamic>;

          setState(() {
            // ✅ REPLACE records instead of appending
            // (because newRecords contains the old ones + new ones)
            _records = newRecords;

            // ✅ Check if we actually got more records than last time
            // If the count didn't increase, we've reached the end.
            if (isLoadMore && newRecords.length <= _previousRecordCount) {
              _hasMore = false;
            }

            // Update previous count for next check
            _previousRecordCount = newRecords.length;

            _totalHours = HistoryApi.calculateTotalHours(_records);
            _isLoading = false;
            _isLoadingMore = false;
          });
        } else {
          setState(() {
            if (!isLoadMore) {
              _errorMessage = result['message'] ?? 'Failed to load history';
            } else {
              // Revert limit if failed
              _currentLimit -= _incrementStep;
            }
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (!isLoadMore) {
            _errorMessage = 'Error loading history: $e';
          } else {
            // Revert limit if failed
            _currentLimit -= _incrementStep;
          }
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  // ... (Rest of the file remains the same: _showEditActivityDialog, build, etc.) ...

  Future<void> _showEditActivityDialog(Map<String, dynamic> record) async {
    final clockGuid = record['CLOCK_LOG_GUID'] ?? record['clockLogGuid'];
    if (clockGuid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot edit: missing clock ID')),
        );
      }
      return;
    }

    // Extract activities to pass to dialog
    final activities = record['ACTIVITY'] as List<dynamic>?;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditActivityDialog(
        clockGuid: clockGuid,
        initialActivities: activities,
      ),
    );

    if (result == true) {
      _loadHistory(); // Refresh to show updates
    }
  }

  Future<void> _showEditTimeDialog(Map<String, dynamic> record) async {
    final clockGuid = record['CLOCK_LOG_GUID'] ?? record['clockLogGuid'];
    if (clockGuid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot edit: missing clock ID')),
        );
      }
      return;
    }

    // Extract times to pass to dialog
    final clockInTime =
        record['CLOCK_IN_TIME'] ?? record['clockInTime'] as String?;
    final clockOutTime =
        record['CLOCK_OUT_TIME'] ?? record['clockOutTime'] as String?;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditTimeRequestDialog(
        clockGuid: clockGuid,
        initialClockInTime: clockInTime,
        initialClockOutTime: clockOutTime,
      ),
    );

    if (result == true) {
      if (mounted) {
        // Optionally refresh or show message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your request has been submitted')),
        );
      }
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
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            title: const Text('Attendance History'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadHistory,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
      ),
      drawer: const AppDrawer(),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 1, // History is index 1
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacementNamed(context, '/home');
          } else if (index == 2) {
            Navigator.pushReplacementNamed(context, '/report');
          } else if (index == 3) {
            Navigator.pushReplacementNamed(context, '/profile');
          }
          // If index == 1 (History), do nothing as we're already here
        },
      ),
      body: Column(
        children: [
          _buildSummaryCard(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? _buildErrorView()
                : _records.isEmpty
                ? _buildEmptyView()
                : _buildHistoryList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      margin: const EdgeInsets.all(15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: BeeColor.gradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem(
            'Total Records',
            '${_records.length}',
            Icons.list_alt,
          ),
          Container(height: 40, width: 1, color: Colors.white.withOpacity(0.3)),
          _buildSummaryItem(
            'Total Hours',
            _totalHours.toStringAsFixed(1),
            Icons.access_time,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 30),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildHistoryList() {
    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(15),
        itemCount: _records.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _records.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(10.0),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final record = _records[index];
          return _buildHistoryCard(record);
        },
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> record) {
    final clockInTime = record['CLOCK_IN_TIME'] ?? '';
    final clockOutTime = record['CLOCK_OUT_TIME'] ?? '';
    final jobType = record['JOB_TYPE'] ?? 'Unknown';
    final address =
        record['ADDRESS_IN'] ?? record['ADDRESS_OUT'] ?? 'No address';
    final clientName = record['CLIENT_NAME'] ?? '';

    // Extract activity names from ACTIVITY array
    final activities = record['ACTIVITY'] as List<dynamic>?;
    final activityNames = <String>[];
    if (activities != null && activities.isNotEmpty) {
      for (var activity in activities) {
        if (activity is Map<String, dynamic>) {
          final name = activity['name'] as String?;
          if (name != null && name.isNotEmpty) {
            activityNames.add(name);
          }
        }
      }
    }

    // Calculate duration
    String duration = 'In Progress';
    if (clockInTime.isNotEmpty && clockOutTime.isNotEmpty) {
      try {
        final clockIn = DateTime.parse(clockInTime);
        final clockOut = DateTime.parse(clockOutTime);
        final diff = clockOut.difference(clockIn);
        final hours = diff.inHours;
        final minutes = diff.inMinutes % 60;
        duration = '${hours}h ${minutes}m';
      } catch (e) {
        duration = 'N/A';
      }
    }

    // Format times
    String formattedClockIn = 'N/A';
    String formattedClockOut = 'N/A';
    String dateStr = '';

    try {
      if (clockInTime.isNotEmpty) {
        final dt = DateTime.parse(clockInTime);
        formattedClockIn = DateFormat('hh:mm a').format(dt);
        dateStr = DateFormat('EEE, MMM dd, yyyy').format(dt);
      }
      if (clockOutTime.isNotEmpty) {
        final dt = DateTime.parse(clockOutTime);
        formattedClockOut = DateFormat('hh:mm a').format(dt);
      }
    } catch (e) {
      debugPrint('Error formatting time: $e');
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date and Job Type
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getJobTypeColor(jobType),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    jobType.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Clock In/Out Times
            Row(
              children: [
                Expanded(
                  child: _buildTimeInfo(
                    'Clock In',
                    formattedClockIn,
                    Icons.login,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildTimeInfo(
                    'Clock Out',
                    formattedClockOut,
                    Icons.logout,
                    Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Duration
            Row(
              children: [
                const Icon(Icons.timer, size: 16, color: Colors.grey),
                const SizedBox(width: 5),
                Text(
                  'Duration: $duration',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            // Client Name (if available)
            if (clientName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.business, size: 16, color: Colors.grey),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      clientName,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            // Address
            // const SizedBox(height: 8),
            // Row(
            //   crossAxisAlignment: CrossAxisAlignment.start,
            //   children: [
            //     const Icon(Icons.location_on, size: 16, color: Colors.grey),
            //     const SizedBox(width: 5),
            //     Expanded(
            //       child: Text(
            //         address,
            //         style: const TextStyle(fontSize: 12, color: Colors.grey),
            //         maxLines: 2,
            //         overflow: TextOverflow.ellipsis,
            //       ),
            //     ),
            //   ],
            // ),

            // Activities (if available)
            if (activityNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.task_alt, size: 16, color: Colors.grey),
                  const SizedBox(width: 5),
                  Text(
                    'Activity: ${activityNames.join(', ')}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],

            // Action Buttons
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showEditActivityDialog(record),
                    icon: const Icon(Icons.playlist_add_check, size: 16),
                    label: const Text(
                      'Edit Activity',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showEditTimeDialog(record),
                    icon: const Icon(Icons.edit_calendar, size: 16),
                    label: const Text(
                      'Edit Time',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeInfo(String label, String time, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getJobTypeColor(String jobType) {
    switch (jobType.toLowerCase()) {
      case 'office':
        return Colors.blue;
      case 'site':
        return Colors.orange;
      case 'home':
        return Colors.green;
      case 'others':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 20),
          Text(
            'No attendance records found',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          Text(
            'Try adjusting the date range',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 80, color: Colors.red.shade300),
          const SizedBox(height: 20),
          Text(
            'Error Loading History',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _errorMessage ?? 'Unknown error',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
