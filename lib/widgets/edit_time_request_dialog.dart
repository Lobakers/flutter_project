import 'package:beewhere/controller/history_api.dart';
import 'package:beewhere/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class EditTimeRequestDialog extends StatefulWidget {
  final String clockGuid;

  const EditTimeRequestDialog({super.key, required this.clockGuid});

  @override
  State<EditTimeRequestDialog> createState() => _EditTimeRequestDialogState();
}

class _EditTimeRequestDialogState extends State<EditTimeRequestDialog> {
  bool _isLoading = true;
  String? _errorMessage;

  DateTime? _startTime;
  DateTime? _endTime;
  final TextEditingController _descriptionController = TextEditingController();
  String? _supportingDocName;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadClockDetails();
  }

  Future<void> _loadClockDetails() async {
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

        try {
          // Parse times and add 8 hours as per requirement
          final clockInStr =
              recordData['CLOCK_IN_TIME'] ?? recordData['clockInTime'];
          final clockOutStr =
              recordData['CLOCK_OUT_TIME'] ?? recordData['clockOutTime'];

          if (clockInStr != null) {
            _startTime = DateTime.parse(
              clockInStr,
            ).add(const Duration(hours: 8));
          }
          if (clockOutStr != null) {
            _endTime = DateTime.parse(
              clockOutStr,
            ).add(const Duration(hours: 8));
          }

          setState(() {
            _isLoading = false;
          });
        } catch (e) {
          setState(() {
            _errorMessage = 'Failed to parse times: $e';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Failed to load clock details';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _supportingDocName = pickedFile.name;
      });

      // TODO: Upload to Azure and get URL
      // For now, just use the filename
    }
  }

  Future<void> _selectStartTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startTime ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_startTime ?? DateTime.now()),
      );

      if (time != null) {
        setState(() {
          _startTime = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _selectEndTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endTime ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_endTime ?? DateTime.now()),
      );

      if (time != null) {
        setState(() {
          _endTime = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _submitRequest() async {
    if (_startTime == null || _endTime == null) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Validation Error'),
          content: const Text('Please select start and end times'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Validation Error'),
          content: const Text('Please enter a description'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Try multiple possible field names for user GUID
    final userGuid =
        authProvider.userInfo?['userId'] ??
        authProvider.userInfo?['USER_GUID'] ??
        authProvider.userInfo?['userGuid'] ??
        authProvider.userInfo?['GUID'] ??
        authProvider.userInfo?['guid'] ??
        '';
    final userEmail = authProvider.userInfo?['email'] ?? '';

    debugPrint('🔍 User Info for Time Request:');
    debugPrint('   userGuid: $userGuid');
    debugPrint('   userEmail: $userEmail');
    debugPrint('   Full userInfo: ${authProvider.userInfo}');

    // Convert to Unix timestamp (seconds)
    final startTimeUnix = _startTime!.millisecondsSinceEpoch ~/ 1000;
    final endTimeUnix = _endTime!.millisecondsSinceEpoch ~/ 1000;

    final result = await HistoryApi.submitTimeRequest(
      context,
      userGuid: userGuid,
      userEmail: userEmail,
      startTime: startTimeUnix,
      endTime: endTimeUnix,
      description: _descriptionController.text.trim(),
      supportingDoc: _supportingDocName,
    );

    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });

      if (result['success']) {
        // Show styled success dialog first
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF2DD36F),
            title: const Text(
              'Request Submitted',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Your time change request has been submitted successfully',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        // Then close the edit dialog and return to history page
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed to submit request'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request Time Change'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
              ? Text(_errorMessage!, style: const TextStyle(color: Colors.red))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Start Time',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _selectStartTime,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          _startTime != null
                              ? DateFormat(
                                  'yyyy-MM-dd HH:mm',
                                ).format(_startTime!)
                              : 'Select start time',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'End Time',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _selectEndTime,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          _endTime != null
                              ? DateFormat('yyyy-MM-dd HH:mm').format(_endTime!)
                              : 'Select end time',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Description',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        hintText: 'Explain why you need to change the time',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Upload Proof'),
                        ),
                        const SizedBox(width: 8),
                        if (_supportingDocName != null)
                          Expanded(
                            child: Text(
                              _supportingDocName!,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading || _errorMessage != null || _isSubmitting
              ? null
              : _submitRequest,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit'),
        ),
      ],
    );
  }
}
