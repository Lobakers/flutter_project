import 'dart:async';
import 'package:beewhere/controller/client_detail_api.dart';
import 'package:beewhere/controller/project_api.dart';
import 'package:beewhere/controller/contract_api.dart';
import 'package:beewhere/controller/coordinate_api.dart';
import 'package:beewhere/controller/attendance_profile_api.dart';
import 'package:beewhere/controller/clock_api.dart';
import 'package:beewhere/providers/auth_provider.dart';
import 'package:beewhere/providers/attendance_provider.dart';
import 'package:beewhere/theme/color_theme.dart';
import 'package:beewhere/widgets/device_info_helper.dart';
import 'package:beewhere/widgets/drawer.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Location state
  String _currentAddress = "Tap to get location";
  bool _isLoading = false;
  double? _latitude;
  double? _longitude;

  // Time display
  String _currentTime = '';
  String _currentDate = '';
  String _currentDay = '';
  Timer? _timer;

  // Clock state
  bool _isClockedIn = false;
  String _clockStatus = "You Haven't Clocked In Yet";
  String? _clockRefGuid; // Needed for clock out
  String? _clockInTime;

  // Form state
  String _selectedJobType = '';
  String? _selectedClient;
  String? _selectedProject;
  String? _selectedContract;
  String _activityName = '';
  final _activityController = TextEditingController();

  // Dropdown data
  List<dynamic> _clients = [];
  List<dynamic> _projects = [];
  List<dynamic> _contracts = [];
  bool _loadingDropdowns = false;

  // Field visibility (from attendance profile)
  Map<String, bool> _fieldVisibility = {};

  @override
  void initState() {
    super.initState();
    _initializeData();
    _startTimers();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _activityController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    await DeviceInfoHelper.init();
    await _loadAttendanceProfile();
    await _loadDropdownData();
    await _checkExistingClock();
    await _getCurrentPosition();
  }

  void _startTimers() {
    _updateDateTime();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateDateTime(),
    );
  }

  void _updateDateTime() {
    final now = DateTime.now();
    if (mounted) {
      setState(() {
        _currentTime = DateFormat('HH:mm a').format(now);
        _currentDate = DateFormat('dd MMMM, yyyy').format(now);
        _currentDay = DateFormat('EEEE').format(now);
      });
    }
  }

  // ===================== API CALLS =====================

  Future<void> _loadAttendanceProfile() async {
    final result = await AttendanceProfileApi.getAttendanceProfile(context);
    if (result['success']) {
      final provider = Provider.of<AttendanceProvider>(context, listen: false);
      provider.setFromApiResponse(result['data']);
    }
  }

  Future<void> _loadDropdownData() async {
    setState(() => _loadingDropdowns = true);
    try {
      _clients = await ClientDetailApi.getClients(context);
      _projects = await ProjectApi.getProjects(context);
      _contracts = await ContractApi.getContracts(context);
    } catch (e) {
      debugPrint('Error loading dropdowns: $e');
    }
    setState(() => _loadingDropdowns = false);
  }

  Future<void> _checkExistingClock() async {
    final result = await ClockApi.getLatestClock(context);
    if (result['success'] && result['isClockedIn'] == true) {
      setState(() {
        _isClockedIn = true;
        _clockRefGuid = result['clockLogGuid'];
        _clockStatus = result['clockTime'] ?? '';
        _selectedJobType = _capitalizeFirst(result['jobType'] ?? '');
        _selectedClient = result['clientId'];
        _selectedProject = result['projectId'];
        _selectedContract = result['contractId'];
        _activityName = result['activityName'] ?? '';
        _activityController.text = _activityName;
      });
      _updateFieldVisibility(_selectedJobType);
    }
  }

  // ===================== LOCATION =====================

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('Location services disabled. Please enable them.');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar('Location permissions denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnackBar('Location permissions permanently denied');
      return false;
    }
    return true;
  }

  Future<void> _getCurrentPosition() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    setState(() => _isLoading = true);

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _latitude = position.latitude;
      _longitude = position.longitude;

      // Use your backend API to get address
      final address = await CoordinateApi.getAddressFromCoordinates(
        context,
        _latitude!,
        _longitude!,
      );
      setState(() => _currentAddress = address);
    } catch (e) {
      debugPrint('Location error: $e');
      setState(() => _currentAddress = "Failed to get location");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ===================== CLOCK IN/OUT =====================

  Future<void> _handleClockAction() async {
    if (_selectedJobType.isEmpty) {
      _showDialog(
        'Error',
        'Please select a job type (Office/Site/Home/Others)',
      );
      return;
    }

    if (_isClockedIn) {
      await _performClockOut();
    } else {
      await _performClockIn();
    }
  }

  Future<void> _performClockIn() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final userGuid = auth.userInfo?['userId'] ?? '';

    final result = await ClockApi.clockIn(
      context: context,
      userGuid: userGuid,
      jobType: _selectedJobType.toLowerCase(),
      latitude: _latitude,
      longitude: _longitude,
      address: _currentAddress,
      clientId: _selectedClient,
      projectId: _selectedProject,
      contractId: _selectedContract,
      activityName: _activityName,
      deviceDescription: DeviceInfoHelper.deviceDescription,
      deviceIp: DeviceInfoHelper.deviceIp,
      deviceId: DeviceInfoHelper.deviceId,
    );

    if (result['success']) {
      setState(() {
        _isClockedIn = true;
        _clockRefGuid = result['clockLogGuid'];
        _clockInTime = result['clockTime'];
        _clockStatus = result['clockTime'];
      });
      _showSuccessDialog('Clock In Successful', 'Time: ${result['clockTime']}');
    } else {
      _showDialog('Error', result['message']);
    }
  }

  Future<void> _performClockOut() async {
    if (_clockRefGuid == null) {
      _showDialog('Error', 'No clock in record found');
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final userGuid = auth.userInfo?['userId'] ?? '';

    final result = await ClockApi.clockOut(
      context: context,
      userGuid: userGuid,
      jobType: _selectedJobType.toLowerCase(),
      latitude: _latitude,
      longitude: _longitude,
      address: _currentAddress,
      clockRefGuid: _clockRefGuid!,
      clientId: _selectedClient,
      projectId: _selectedProject,
      contractId: _selectedContract,
      activityName: _activityName,
      deviceDescription: DeviceInfoHelper.deviceDescription,
      deviceIp: DeviceInfoHelper.deviceIp,
      deviceId: DeviceInfoHelper.deviceId,
    );

    if (result['success']) {
      _showSuccessDialog(
        'Clock Out Successful',
        'In: $_clockInTime\nOut: ${result['clockTime']}',
      );
      setState(() {
        _isClockedIn = false;
        _clockRefGuid = null;
        _clockStatus = "You Haven't Clocked In Yet";
        _selectedJobType = '';
        _selectedClient = null;
        _selectedProject = null;
        _selectedContract = null;
        _activityController.clear();
        _fieldVisibility = {};
      });
    } else {
      _showDialog('Error', result['message']);
    }
  }

  // ===================== UI HELPERS =====================

  void _onJobTypeSelected(String jobType) {
    setState(() => _selectedJobType = jobType);
    _updateFieldVisibility(jobType);
  }

  void _updateFieldVisibility(String jobType) {
    final provider = Provider.of<AttendanceProvider>(context, listen: false);
    setState(() {
      _fieldVisibility = provider.getFieldsForJobType(jobType);
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2DD36F),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _capitalizeFirst(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ===================== BUILD =====================

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final attendance = Provider.of<AttendanceProvider>(context);
    final email = auth.userInfo?['email'] ?? 'No email';
    final companyName = auth.userInfo?['companyName'] ?? 'No company';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('beeWhere')),
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: _initializeData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildBanner(email, companyName),
              _buildTimeCard(),
              const SizedBox(height: 10),
              _buildJobTypeButtons(attendance),
              _buildLocationDisplay(),
              if (_selectedJobType.isNotEmpty) _buildForm(),
              const SizedBox(height: 20),
              _buildClockButton(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBanner(String email, String companyName) {
    return Container(
      height: 120,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/background_login.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_circle, size: 80, color: Colors.white),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Good Day!',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
              Text(
                email,
                style: const TextStyle(fontSize: 14, color: Colors.white),
              ),
              Text(
                companyName,
                style: const TextStyle(fontSize: 14, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeCard() {
    return Container(
      margin: const EdgeInsets.all(15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Clock In',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2DD36F),
            ),
          ),
          Text(
            _clockStatus,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _currentTime,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_currentDate, style: const TextStyle(fontSize: 14)),
                  Text(_currentDay, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJobTypeButtons(AttendanceProvider attendance) {
    final visibleTypes = attendance.getVisibleJobTypes();
    if (visibleTypes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('Loading job types...'),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: visibleTypes.map((type) => _buildJobButton(type)).toList(),
      ),
    );
  }

  Widget _buildJobButton(String title) {
    final isSelected = _selectedJobType == title;
    return Expanded(
      child: GestureDetector(
        onTap: _isClockedIn ? null : () => _onJobTypeSelected(title),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.blue,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationDisplay() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Center(
                child: _isLoading
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : Text(
                        _currentAddress,
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(
              color: BeeColor.fillIcon,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: _isLoading ? null : _getCurrentPosition,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          if (_fieldVisibility['client'] == true)
            _buildDropdown(
              'Client',
              _clients,
              _selectedClient,
              'CLIENT_GUID',
              'NAME',
              (v) => setState(() => _selectedClient = v),
            ),
          if (_fieldVisibility['project'] == true)
            _buildDropdown(
              'Project',
              _projects,
              _selectedProject,
              'PROJECT_GUID',
              'NAME',
              (v) => setState(() => _selectedProject = v),
            ),
          if (_fieldVisibility['contract'] == true)
            _buildDropdown(
              'Contract',
              _contracts,
              _selectedContract,
              'CONTRACT_GUID',
              'NAME',
              (v) => setState(() => _selectedContract = v),
            ),
          if (_fieldVisibility['activity'] == true) _buildActivityField(),
        ],
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    List<dynamic> items,
    String? value,
    String valueKey,
    String labelKey,
    Function(String?) onChanged,
  ) {
    if (_loadingDropdowns)
      return const Padding(
        padding: EdgeInsets.all(10),
        child: CircularProgressIndicator(),
      );

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey),
      ),
      child: DropdownButton<String>(
        isExpanded: true,
        underline: const SizedBox(),
        hint: Text('Select $label'),
        value: value,
        items: items
            .map(
              (item) => DropdownMenuItem<String>(
                value: item[valueKey],
                child: Text(item[labelKey] ?? ''),
              ),
            )
            .toList(),
        onChanged: _isClockedIn ? null : onChanged,
      ),
    );
  }

  Widget _buildActivityField() {
    return TextField(
      controller: _activityController,
      enabled: !_isClockedIn,
      maxLines: 3,
      onChanged: (v) => _activityName = v,
      decoration: const InputDecoration(
        labelText: 'Activity List',
        hintText: 'Add task here',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildClockButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: _handleClockAction,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isClockedIn
                ? Colors.red
                : const Color(0xFF2DD36F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            _isClockedIn ? 'Clock Out' : 'Clock In',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
