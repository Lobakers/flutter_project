import 'package:beewhere/controller/history_api.dart';
import 'package:beewhere/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class EditTimeRequestDialog extends StatefulWidget {
  final String clockGuid;
  final String? initialClockInTime;
  final String? initialClockOutTime;

  const EditTimeRequestDialog({
    super.key,
    required this.clockGuid,
    this.initialClockInTime,
    this.initialClockOutTime,
  });

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
    // If initial times provided, use them directly (Offline support)
    if (widget.initialClockInTime != null ||
        widget.initialClockOutTime != null) {
      try {
        if (widget.initialClockInTime != null) {
          _startTime = DateTime.parse(widget.initialClockInTime!);
        }
        if (widget.initialClockOutTime != null) {
          _endTime = DateTime.parse(widget.initialClockOutTime!);
        }
        setState(() {
          _isLoading = false;
        });
      } catch (e) {
        // Fallback to API if parsing fails
        debugPrint('Error parsing initial times: $e');
      }

      if (_startTime != null || _endTime != null) {
        return; // Successfully loaded from initial data
      }
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

        try {
          final clockInStr =
              recordData['CLOCK_IN_TIME'] ?? recordData['clockInTime'];
          final clockOutStr =
              recordData['CLOCK_OUT_TIME'] ?? recordData['clockOutTime'];

          if (clockInStr != null) {
            _startTime = DateTime.parse(clockInStr);
          }
          if (clockOutStr != null) {
            _endTime = DateTime.parse(clockOutStr);
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

  Future<void> _submitRequest() async {
    if (_startTime == null || _endTime == null) {
      _showErrorDialog('Action Required', 'Please select start and end times');
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      _showErrorDialog('Action Required', 'Please enter a description');
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
                      'Request Submitted',
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
                      'Your time change request has been submitted successfully',
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
