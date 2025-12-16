import 'package:beewhere/controller/history_api.dart';
import 'package:flutter/material.dart';

class EditActivityDialog extends StatefulWidget {
  final String clockGuid;
  final List<dynamic>? initialActivities;

  const EditActivityDialog({
    super.key,
    required this.clockGuid,
    this.initialActivities,
  });

  @override
  State<EditActivityDialog> createState() => _EditActivityDialogState();
}

class _EditActivityDialogState extends State<EditActivityDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  String? _clockLogGuid;
  List<TextEditingController> _activityControllers = [];

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    // If we have initial activities, use them directly (Offline support)
    if (widget.initialActivities != null) {
      setState(() {
        _clockLogGuid = widget.clockGuid;
        // Populate controllers
        _activityControllers = (widget.initialActivities!)
            .map(
              (e) => TextEditingController(
                text: (e is Map ? e['name'] : e).toString(),
              ),
            )
            .toList();

        if (_activityControllers.isEmpty) {
          _activityControllers.add(TextEditingController());
        }
        _isLoading = false;
      });
      return;
    }

    // Otherwise fetch from API (Online behavior)
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await HistoryApi.getClockDetail(context, widget.clockGuid);

    if (mounted) {
      if (result['success']) {
        final data = result['data'];
        final recordData = data is List ? data[0] : data;

        setState(() {
          _clockLogGuid =
              recordData['CLOCK_LOG_GUID'] ?? recordData['clockLogGuid'];
          final activityData =
              recordData['ACTIVITY'] ?? recordData['activity'] ?? [];

          _activityControllers = (activityData as List)
              .map(
                (e) => TextEditingController(text: e['name']?.toString() ?? ''),
              )
              .toList();

          if (_activityControllers.isEmpty) {
            _activityControllers.add(TextEditingController());
          }

          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Failed to load activities';
          _isLoading = false;
        });
      }
    }
  }

  void _addActivityField() {
    setState(() {
      _activityControllers.add(TextEditingController());
    });
  }

  void _removeActivityField(int index) {
    setState(() {
      _activityControllers[index].dispose();
      _activityControllers.removeAt(index);
    });
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 8,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF667eea), // Purple-blue
                Color(0xFF764ba2), // Deep purple
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF667eea).withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon section
              Container(
                margin: const EdgeInsets.only(top: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Message
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF667eea),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveActivities() async {
    if (_clockLogGuid == null) {
      _showErrorDialog('Error', 'Missing clock ID');
      return;
    }

    // Build activity list from text fields (non-empty only)
    final activities = _activityControllers
        .where((controller) => controller.text.trim().isNotEmpty)
        .map(
          (controller) => {
            'name': controller.text.trim(),
            'statusFlag': true, // All activities marked as completed
          },
        )
        .toList();

    // Validate that at least one activity is entered
    if (activities.isEmpty) {
      _showErrorDialog(
        'Action Required',
        'Please enter at least one activity before saving',
      );
      return;
    }

    final result = await HistoryApi.updateActivity(
      context,
      _clockLogGuid!,
      activities,
    );

    if (mounted) {
      if (result['success']) {
        // Show styled success dialog first
        await showDialog(
          context: context,
          builder: (_) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 8,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF2DD36F), // Green
                    Color(0xFF10B981), // Emerald green
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2DD36F).withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon section
                  Container(
                    margin: const EdgeInsets.only(top: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Title
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Activity Updated',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Message
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Your activity has been updated successfully',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF2DD36F),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'OK',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        // Then close the edit dialog and return to history page
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed to update activity'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    for (var controller in _activityControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Activity'),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? Text(_errorMessage!, style: const TextStyle(color: Colors.red))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _activityControllers.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _activityControllers[index],
                                  decoration: InputDecoration(
                                    hintText: 'Activity ${index + 1}',
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              if (_activityControllers.length > 1)
                                IconButton(
                                  icon: const Icon(
                                    Icons.remove_circle,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _removeActivityField(index),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  // COMMENTED OUT: Add Activity button (not needed for single activity)
                  // OutlinedButton.icon(
                  //   onPressed: _addActivityField,
                  //   icon: const Icon(Icons.add),
                  //   label: const Text('Add Activity'),
                  // ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading || _errorMessage != null
              ? null
              : _saveActivities,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
