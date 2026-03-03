import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:beewhere/services/clock_audit_logger.dart';
import 'package:beewhere/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

/// Audit Logs Viewer - For debugging production issues
/// Shows complete history of clock transactions and system events
/// RESTRICTED: Only accessible by admin user (irfan@zen.com.my)
class AuditLogsPage extends StatefulWidget {
  const AuditLogsPage({super.key});

  @override
  State<AuditLogsPage> createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends State<AuditLogsPage> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String _filterType = 'ALL';
  StreamSubscription<Map<String, dynamic>>? _logStreamSubscription;
  final ScrollController _scrollController = ScrollController();

  final List<String> _filterOptions = [
    'ALL',
    'CLOCK_IN',
    'CLOCK_OUT',
    'AUTO_CLOCK_OUT',
    'SERVICE_START',
    'SERVICE_STOP',
    'SERVICE_RESTART',
    'STORAGE_UPDATE',
    'ERROR',
  ];

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _subscribeToLogStream();
  }

  @override
  void dispose() {
    _logStreamSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Subscribe to real-time log stream
  void _subscribeToLogStream() {
    _logStreamSubscription = ClockAuditLogger.logStream.listen((newLog) {
      if (mounted) {
        setState(() {
          // Add to top for latest-first display
          _logs.insert(0, newLog);
          // Keep list reasonable size in memory
          if (_logs.length > 2000) {
            _logs.removeLast();
          }
        });
        // Auto-scroll to show new log
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);

    try {
      List<Map<String, dynamic>> logs;

      if (_filterType == 'ALL') {
        logs = await ClockAuditLogger.getRecentLogs(limit: 500);
      } else {
        logs = await ClockAuditLogger.getLogsByType(
          eventType: _filterType,
          limit: 200,
        );
      }

      setState(() {
        _logs = logs;
        _isLoading = false;
      });

      // Auto-scroll to top after loading
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading logs: $e')));
      }
    }
  }

  Future<void> _exportLogs() async {
    try {
      final logText = await ClockAuditLogger.exportLogsAsText(limit: 500);

      // Copy to clipboard
      await Clipboard.setData(ClipboardData(text: logText));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✅ Logs copied to clipboard!\n💾 Tip: Export regularly to preserve diagnostic data (max 2000 entries)',
            ),
            duration: Duration(seconds: 4),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error exporting logs: $e')));
      }
    }
  }

  Future<void> _clearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Logs?'),
        content: const Text(
          'This will delete all audit log entries. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ClockAuditLogger.clearLogs();
      _loadLogs();
    }
  }

  // Soft pastel background colors for circles
  Color _getEventBackgroundColor(String eventType) {
    switch (eventType) {
      case 'CLOCK_IN':
        return const Color(0xFFE8F5E9); // Soft green
      case 'CLOCK_OUT':
        return const Color(0xFFE3F2FD); // Soft blue
      case 'AUTO_CLOCK_OUT':
        return const Color(0xFFFFF3E0); // Soft orange
      case 'SERVICE_START':
        return const Color(0xFFE0F2F1); // Soft teal
      case 'SERVICE_STOP':
        return const Color(0xFFF5F5F5); // Soft grey
      case 'SERVICE_RESTART':
        return const Color(0xFFFFF9C4); // Soft amber
      case 'STORAGE_UPDATE':
        return const Color(0xFFF3E5F5); // Soft purple
      case 'ERROR':
        return const Color(0xFFFFEBEE); // Soft red
      default:
        return const Color(0xFFECEFF1); // Soft blue grey
    }
  }

  // Darker shade for icons
  Color _getEventIconColor(String eventType) {
    switch (eventType) {
      case 'CLOCK_IN':
        return const Color(0xFF2E7D32); // Dark green
      case 'CLOCK_OUT':
        return const Color(0xFF1565C0); // Dark blue
      case 'AUTO_CLOCK_OUT':
        return const Color(0xFFE65100); // Dark orange
      case 'SERVICE_START':
        return const Color(0xFF00695C); // Dark teal
      case 'SERVICE_STOP':
        return const Color(0xFF616161); // Dark grey
      case 'SERVICE_RESTART':
        return const Color(0xFFF57F17); // Dark amber
      case 'STORAGE_UPDATE':
        return const Color(0xFF6A1B9A); // Dark purple
      case 'ERROR':
        return const Color(0xFFC62828); // Dark red
      default:
        return const Color(0xFF455A64); // Dark blue grey
    }
  }

  IconData _getEventIcon(String eventType) {
    switch (eventType) {
      case 'CLOCK_IN':
        return Icons.login;
      case 'CLOCK_OUT':
        return Icons.logout;
      case 'AUTO_CLOCK_OUT':
        return Icons.my_location;
      case 'SERVICE_START':
        return Icons.play_arrow;
      case 'SERVICE_STOP':
        return Icons.stop;
      case 'SERVICE_RESTART':
        return Icons.refresh;
      case 'STORAGE_UPDATE':
        return Icons.save;
      case 'ERROR':
        return Icons.error;
      default:
        return Icons.info;
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      return DateFormat('MMM dd, HH:mm:ss').format(dt);
    } catch (e) {
      return timestamp;
    }
  }

  String _formatEventType(String eventType) {
    // Convert ALL_CAPS to Title Case
    return eventType
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final email = auth.userInfo?['email'] ?? '';

    // Access control: Only allow irfan@zen.com.my
    if (email != 'irfan@zen.com.my') {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Access Denied'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Access Denied',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This feature is only available for administrators.',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Audit Logs',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Showing ${_logs.length} entries • Filter: ${_formatEventType(_filterType)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'LIVE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export to Clipboard',
            onPressed: _exportLogs,
            color: Colors.black87,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear Logs',
            onPressed: _clearLogs,
            color: Colors.black87,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadLogs,
            color: Colors.black87,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips - Subtle and Modern
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!, width: 1),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filterOptions.map((filter) {
                  final isSelected = _filterType == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () {
                        setState(() => _filterType = filter);
                        _loadLogs();
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF5E72E4)
                              : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _formatEventType(filter),
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Logs List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No logs found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Perform clock in/out to see audit logs',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    controller: _scrollController,
                    itemCount: _logs.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.grey[200],
                      indent: 72,
                    ),
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      return _buildLogItem(log);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    final eventType = log['event_type'] ?? 'UNKNOWN';
    final description = log['description'] ?? '';
    final timestamp = log['timestamp'] ?? '';
    final clockRefGuid = log['clock_ref_guid'];
    final userId = log['user_id'];
    final storageLayer = log['storage_layer'];
    final metadata = log['metadata'];
    final isOnline = log['is_online'] == 1;

    return ExpansibleTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _getEventBackgroundColor(eventType),
          shape: BoxShape.circle,
        ),
        child: Icon(
          _getEventIcon(eventType),
          color: _getEventIconColor(eventType),
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _formatEventType(eventType),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            _formatTimestamp(timestamp),
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!isOnline)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Offline',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber[900],
                ),
              ),
            ),
        ],
      ),
      details: Container(
        padding: const EdgeInsets.fromLTRB(72, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (clockRefGuid != null)
              _buildDetailRow('Clock GUID', clockRefGuid),
            if (userId != null) _buildDetailRow('User ID', userId),
            if (storageLayer != null)
              _buildDetailRow('Storage Layer', storageLayer),
            if (metadata != null) _buildDetailRow('Details', metadata),
            const SizedBox(height: 8),
            Text(
              'Full Timestamp: $timestamp',
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

/// Simple expandable tile widget
class ExpansibleTile extends StatefulWidget {
  final Widget leading;
  final Widget title;
  final Widget subtitle;
  final Widget details;

  const ExpansibleTile({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.details,
  });

  @override
  State<ExpansibleTile> createState() => _ExpansibleTileState();
}

class _ExpansibleTileState extends State<ExpansibleTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                widget.leading,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      widget.title,
                      const SizedBox(height: 4),
                      widget.subtitle,
                    ],
                  ),
                ),
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey[400],
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded) widget.details,
      ],
    );
  }
}
