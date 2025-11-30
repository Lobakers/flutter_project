import 'package:beewhere/controller/history_api.dart';
import 'package:flutter/material.dart';

class EditActivityDialog extends StatefulWidget {
  final String clockGuid;

  const EditActivityDialog({super.key, required this.clockGuid});

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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await HistoryApi.getClockDetail(context, widget.clockGuid);

    if (mounted) {
      if (result['success']) {
        final data = result['data'];
        // API returns an array, take first element
        final recordData = data is List ? data[0] : data;

        setState(() {
          _clockLogGuid =
              recordData['CLOCK_LOG_GUID'] ?? recordData['clockLogGuid'];
          final activityData =
              recordData['ACTIVITY'] ?? recordData['activity'] ?? [];

          // Create text controllers for each activity
          _activityControllers = (activityData as List)
              .map(
                (e) => TextEditingController(text: e['name']?.toString() ?? ''),
              )
              .toList();

          // If no activities exist, add one empty field
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

  Future<void> _saveActivities() async {
    if (_clockLogGuid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Missing clock ID')));
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

    final result = await HistoryApi.updateActivity(
      context,
      _clockLogGuid!,
      activities,
    );

    if (mounted) {
      if (result['success']) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Activity updated successfully')),
        );
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
                  OutlinedButton.icon(
                    onPressed: _addActivityField,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Activity'),
                  ),
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
