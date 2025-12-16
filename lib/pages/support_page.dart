import 'dart:async';
import 'dart:io';

import 'package:beewhere/controller/support_api.dart';
import 'package:beewhere/providers/auth_provider.dart';
import 'package:beewhere/services/offline_database.dart';
import 'package:beewhere/services/connectivity_service.dart';
import 'package:beewhere/theme/color_theme.dart';
import 'package:beewhere/widgets/drawer.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  // Clock Status Logic
  String _currentTime = '';
  String _currentDate = '';
  String _currentDay = '';
  Timer? _timer;
  bool _isClockedIn = false;
  String _clockStatus = "You Haven't Clocked In Yet";
  String? _clockInTime;

  // Segmented Control
  String _selectedSegment = 'request'; // 'request' or 'suggestion'

  // Forms
  final _formKey = GlobalKey<FormState>(); // Unified form key or separate?

  // Suggestion Form Fields
  final _suggestionTitleController = TextEditingController();
  final _suggestionDescController = TextEditingController();

  // Request Form Fields
  String _requestType = 'overtime'; // Default
  final _requestTitleController = TextEditingController();
  final _requestDescController = TextEditingController();
  DateTime? _inTime;
  DateTime? _outTime;

  // File Upload
  File? _selectedFile;
  String _uploadError = '';
  bool _isUploading = false;

  // Connectivity state
  bool _isOnline = true;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _startTimers();
    _loadCachedClockStatus();
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
    _timer?.cancel();
    _suggestionTitleController.dispose();
    _suggestionDescController.dispose();
    _requestTitleController.dispose();
    _requestDescController.dispose();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  // --- Clock Logic ---

  void _startTimers() {
    _updateDateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateDateTime();
    });
  }

  void _updateDateTime() {
    final now = DateTime.now();
    if (mounted) {
      setState(() {
        _currentTime = DateFormat('HH:mm a').format(now);
        _currentDate = DateFormat('dd MMMM, yyyy').format(now);
        _currentDay = DateFormat('EEEE').format(now);

        if (_isClockedIn && _clockInTime != null) {
          final clockInDate = _parseClockInTime(_clockInTime);
          if (clockInDate != null) {
            final difference = now.difference(clockInDate);
            final hours = difference.inHours;
            final minutes = difference.inMinutes % 60;
            _clockStatus = '$hours hours $minutes minute';
          }
        }
      });
    }
  }

  DateTime? _parseClockInTime(dynamic timeData) {
    if (timeData == null) return null;
    try {
      if (timeData is int) {
        return DateTime.fromMillisecondsSinceEpoch(timeData * 1000);
      } else if (timeData is String) {
        return DateTime.parse(timeData);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _loadCachedClockStatus() async {
    try {
      final cachedClock = await OfflineDatabase.getClockStatus();
      if (cachedClock != null && mounted) {
        setState(() {
          _isClockedIn = cachedClock['isClockedIn'] == true;
          if (_isClockedIn) {
            _clockInTime = cachedClock['clockTime'];
            // Status text updated by timer
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading cached clock status: $e');
    }
  }

  // --- Form Logic ---

  void _changeSegment(String value) {
    setState(() {
      _selectedSegment = value;
      // Reset forms?
      _uploadError = '';
      _selectedFile = null;
    });
  }

  Future<void> _pickFile() async {
    final picker = ImagePicker();
    // Allow users to pick image from gallery (or camera if needed, but usually file is from storage)
    // For wider file support (PDF), we'd need file_picker, but user requested 'image/pdf'.
    // ImagePicker only supports images/video.
    // Note: User prompt mentioned "File Input (Image/PDF)".
    // If dependencies don't have file_picker, I'll restrict to ImagePicker for now or check pubspec again.
    // Pubspec has `image_picker`. It does NOT have `file_picker`.
    // I will use ImagePicker and maybe stick to images for now, or use basic file picker if available?
    // Wait, `image_picker` is strict.
    // I will implement ImagePicker for now as it's in pubspec.

    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final file = File(image.path);
      final size = await file.length();
      if (size > 5 * 1024 * 1024) {
        // 5MB
        setState(() => _uploadError = 'File size must be less than 5MB');
        return;
      }
      setState(() {
        _selectedFile = file;
        _uploadError = '';
      });
    }
  }

  Future<void> _submitForm() async {
    if (_selectedSegment == 'suggestion') {
      _submitSuggestion();
    } else {
      _submitRequest();
    }
  }

  Future<void> _submitSuggestion() async {
    if (_suggestionTitleController.text.isEmpty) {
      _showErrorDialog('Title is required');
      return;
    }

    setState(() => _isUploading = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final body = {
      "requestType": "suggestions",
      "subject": _suggestionTitleController.text,
      "starttime": null,
      "endtime": null,
      "supportingDoc": "",
      "description": _suggestionDescController.text,
      "userGuid": auth.userInfo?['userId'] ?? "",
      "userEmail": auth.userInfo?['email'] ?? "",
    };

    final result = await SupportApi.submitSupportRequest(context, body);
    setState(() => _isUploading = false);

    if (result['success']) {
      _showSuccessDialog('Suggestion submitted successfully');
      _suggestionTitleController.clear();
      _suggestionDescController.clear();
    } else {
      _showErrorDialog(result['message'] ?? 'Submission failed');
    }
  }

  Future<void> _submitRequest() async {
    // Validation
    if (_requestTitleController.text.isEmpty) {
      _showErrorDialog('Subject is required');
      return;
    }
    if (_inTime == null) {
      _showErrorDialog('Start time is required');
      return;
    }
    if (_outTime == null) {
      _showErrorDialog('End time is required');
      return;
    }
    if (_inTime!.isAfter(_outTime!)) {
      _showErrorDialog('Start time must be less than End time');
      return;
    }
    if (_selectedFile == null) {
      _showErrorDialog('Supporting document is required');
      return;
    }

    setState(() => _isUploading = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    String filename = '';

    // 1. Try to Upload File (if online)
    if (_isOnline) {
      final uploadResult = await SupportApi.uploadFile(context, _selectedFile!);
      if (!uploadResult['success']) {
        setState(() => _isUploading = false);
        _showErrorDialog(uploadResult['message'] ?? 'File upload failed');
        return;
      }
      filename = uploadResult['filename'];
    } else {
      // OFFLINE: Generate placeholder filename, actual upload happens during sync
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final originalFilename = p.basename(_selectedFile!.path);
      filename = '${timestamp}_$originalFilename';
    }

    // 2. Submit Request
    final startTimeSeconds = _inTime!.millisecondsSinceEpoch ~/ 1000;
    final endTimeSeconds = _outTime!.millisecondsSinceEpoch ~/ 1000;

    final body = {
      "requestType": _requestType,
      "subject": _requestTitleController.text,
      "starttime": startTimeSeconds,
      "endtime": endTimeSeconds,
      "supportingDoc": filename,
      "description": _requestDescController.text,
      "userGuid": auth.userInfo?['userId'] ?? "",
      "userEmail": auth.userInfo?['email'] ?? "",
    };

    final result = await SupportApi.submitSupportRequest(
      context,
      body,
      cachedFile: _isOnline
          ? null
          : _selectedFile, // Pass cached file if offline
    );

    setState(() => _isUploading = false);

    if (result['success']) {
      _showSuccessDialog(result['message'] ?? 'Request submitted successfully');
      _requestTitleController.clear();
      _requestDescController.clear();
      setState(() {
        _selectedFile = null;
        _inTime = null;
        _outTime = null;
      });
    } else {
      _showErrorDialog(result['message'] ?? 'Submission failed');
    }
  }

  void _showErrorDialog(String message) {
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Action Required',
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

  void _showSuccessDialog(String message) {
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
                  'Success',
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
  }

  // --- UI Builders ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support', style: TextStyle(color: Colors.white)),
        backgroundColor: BeeColor.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/background_login.png'),
              fit: BoxFit.cover,
            ),
          ),
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
      drawer: const AppDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildClockStatusCard(),
            const SizedBox(height: 16),
            _buildSegmentControl(),
            const SizedBox(height: 16),
            _selectedSegment == 'request'
                ? _buildRequestForm()
                : _buildSuggestionForm(),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _submitForm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: BeeColor.buttonColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isUploading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Submit',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClockStatusCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFF5F5F5)],
          ),
        ),
        child: Column(
          children: [
            Text(
              _currentTime,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: BeeColor.primary,
              ),
            ),
            Text(
              '$_currentDay, $_currentDate',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (_isClockedIn)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green, width: 1),
                ),
                child: const Text(
                  'Clocked In',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (_isClockedIn) ...[
              const SizedBox(height: 8),
              Text(
                _clockStatus,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.indigo, // Or BeeColor.primary
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentControl() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _buildSegmentButton('Request', 'request'),
          _buildSegmentButton('Suggestion', 'suggestion'),
        ],
      ),
    );
  }

  Widget _buildSegmentButton(String label, String value) {
    final isSelected = _selectedSegment == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _changeSegment(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? BeeColor.buttonColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black54,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTextField(
          'Subject',
          _suggestionTitleController,
          isRequired: true,
        ),
        const SizedBox(height: 16),
        _buildTextField('Description', _suggestionDescController, maxLines: 4),
      ],
    );
  }

  Widget _buildRequestForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Type', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _requestType,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'overtime', child: Text('Overtime')),
                DropdownMenuItem(
                  value: 'clocks',
                  child: Text('Clock Adjustments'),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _requestType = val);
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        _buildTextField('Subject', _requestTitleController, isRequired: true),
        const SizedBox(height: 16),

        _buildDateTimePicker(
          'Start Time',
          _inTime,
          (val) => setState(() => _inTime = val),
        ),
        const SizedBox(height: 8),
        if (_inTime != null && _outTime != null && _inTime!.isAfter(_outTime!))
          const Text(
            '*Start time must be less than End time',
            style: TextStyle(color: Colors.red, fontSize: 12),
          ),

        const SizedBox(height: 16),
        _buildDateTimePicker(
          'End Time',
          _outTime,
          (val) => setState(() => _outTime = val),
        ),

        const SizedBox(height: 16),
        const Text(
          'Supporting Document *',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickFile,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[50],
            ),
            child: Row(
              children: [
                const Icon(Icons.attach_file, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedFile != null
                        ? p.basename(_selectedFile!.path)
                        : 'No file chosen',
                    style: TextStyle(
                      color: _selectedFile != null ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
                Text(
                  'Add File',
                  style: TextStyle(
                    color: BeeColor.buttonColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_uploadError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _uploadError,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),

        const SizedBox(height: 16),
        _buildTextField('Description', _requestDescController, maxLines: 4),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool isRequired = false,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (isRequired)
              const Text(' *', style: TextStyle(color: Colors.red)),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateTimePicker(
    String label,
    DateTime? value,
    Function(DateTime) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Text(' *', style: TextStyle(color: Colors.red)),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (date != null && mounted) {
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
              );
              if (time != null) {
                onChanged(
                  DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  ),
                );
              }
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value != null
                      ? DateFormat('yyyy-MM-dd HH:mm').format(value)
                      : 'Select Date & Time',
                  style: TextStyle(
                    color: value != null ? Colors.black : Colors.black54,
                  ),
                ),
                const Icon(Icons.calendar_today, size: 20, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
