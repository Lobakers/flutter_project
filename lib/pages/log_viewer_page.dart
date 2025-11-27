import 'package:beewhere/services/logger_service.dart';
import 'package:beewhere/theme/color_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String _filterLevel = 'ALL'; // ALL, DEBUG, INFO, WARNING, ERROR

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    try {
      final logs = await LoggerService.getLogs();
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading logs: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Logs'),
        content: const Text('Are you sure you want to delete all logs?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await LoggerService.clearLogs();
      _loadLogs();
    }
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case 'DEBUG':
        return Colors.grey;
      case 'INFO':
        return Colors.blue;
      case 'WARNING':
        return Colors.orange;
      case 'ERROR':
        return Colors.red;
      default:
        return Colors.black;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredLogs = _filterLevel == 'ALL'
        ? _logs
        : _logs.where((log) => log['level'] == _filterLevel).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Logs'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadLogs),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: Row(
              children: ['ALL', 'DEBUG', 'INFO', 'WARNING', 'ERROR'].map((
                level,
              ) {
                final isSelected = _filterLevel == level;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(level),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() => _filterLevel = level);
                    },
                    backgroundColor: Colors.grey.shade200,
                    selectedColor: BeeColor.buttonColor.withOpacity(0.2),
                    labelStyle: TextStyle(
                      color: isSelected ? BeeColor.buttonColor : Colors.black,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Logs List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredLogs.isEmpty
                ? const Center(child: Text('No logs found'))
                : ListView.separated(
                    itemCount: filteredLogs.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final log = filteredLogs[index];
                      final timestamp = DateTime.parse(log['timestamp']);
                      final formattedTime = DateFormat(
                        'HH:mm:ss',
                      ).format(timestamp);

                      return ExpansionTile(
                        leading: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getLevelColor(
                              log['level'],
                            ).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _getLevelColor(log['level']),
                            ),
                          ),
                          child: Text(
                            log['level'],
                            style: TextStyle(
                              color: _getLevelColor(log['level']),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          log['message'],
                          style: const TextStyle(fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '$formattedTime • ${log['tag']}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText('Message: ${log['message']}'),
                                const SizedBox(height: 8),
                                if (log['error'] != null) ...[
                                  Text(
                                    'Error:',
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SelectableText(
                                    log['error'],
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                if (log['stack_trace'] != null) ...[
                                  const Text(
                                    'Stack Trace:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    color: Colors.grey.shade100,
                                    child: SelectableText(
                                      log['stack_trace'],
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
