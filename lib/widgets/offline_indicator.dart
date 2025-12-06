import 'package:beewhere/services/connectivity_service.dart';
import 'package:flutter/material.dart';

/// Reusable widget to show offline/sync status
class OfflineIndicator extends StatelessWidget {
  final bool isOnline;
  final int pendingCount;
  final bool isSyncing;

  const OfflineIndicator({
    super.key,
    required this.isOnline,
    this.pendingCount = 0,
    this.isSyncing = false,
  });

  @override
  Widget build(BuildContext context) {
    // Don't show anything if online and no pending items
    if (isOnline && pendingCount == 0 && !isSyncing) {
      return const SizedBox.shrink();
    }

    Color backgroundColor;
    IconData icon;
    String message;

    if (isSyncing) {
      backgroundColor = Colors.orange;
      icon = Icons.sync;
      message = 'Syncing $pendingCount item${pendingCount != 1 ? 's' : ''}...';
    } else if (!isOnline) {
      backgroundColor = Colors.red;
      icon = Icons.cloud_off;
      message = pendingCount > 0
          ? 'Offline - $pendingCount pending'
          : 'Offline Mode';
    } else if (pendingCount > 0) {
      backgroundColor = Colors.orange;
      icon = Icons.cloud_upload;
      message =
          '$pendingCount item${pendingCount != 1 ? 's' : ''} pending sync';
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: backgroundColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stateful version that listens to connectivity changes
class LiveOfflineIndicator extends StatefulWidget {
  final int pendingCount;
  final bool isSyncing;

  const LiveOfflineIndicator({
    super.key,
    this.pendingCount = 0,
    this.isSyncing = false,
  });

  @override
  State<LiveOfflineIndicator> createState() => _LiveOfflineIndicatorState();
}

class _LiveOfflineIndicatorState extends State<LiveOfflineIndicator> {
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final isOnline = await ConnectivityService.checkConnectivity();
    if (mounted) {
      setState(() => _isOnline = isOnline);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OfflineIndicator(
      isOnline: _isOnline,
      pendingCount: widget.pendingCount,
      isSyncing: widget.isSyncing,
    );
  }
}
