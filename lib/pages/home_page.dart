import 'dart:async';
import 'package:beewhere/controller/client_detail_api.dart';
import 'package:beewhere/controller/project_api.dart';
import 'package:beewhere/controller/contract_api.dart';

import 'package:beewhere/controller/attendance_profile_api.dart';
import 'package:beewhere/controller/clock_api.dart';
import 'package:beewhere/controller/geofence_helper.dart';
import 'package:beewhere/controller/auto_clockout_service.dart';
import 'package:beewhere/services/background_geofence_service.dart';
import 'package:beewhere/services/notification_service.dart';
import 'package:beewhere/providers/auth_provider.dart';
import 'package:beewhere/providers/attendance_provider.dart';
import 'package:beewhere/theme/color_theme.dart';
import 'package:beewhere/widgets/bottom_nav.dart';
import 'package:beewhere/widgets/device_info_helper.dart';
import 'package:beewhere/widgets/drawer.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:slide_to_act/slide_to_act.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Location state
  String _currentAddress = "Tap to get location"; // Now stores coordinates
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
  String? _clockRefGuid;
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

  // Field visibility
  Map<String, bool> _fieldVisibility = {};

  // Navigation state
  int _currentIndex = 0;

  AutoClockOutService? _autoClockOutService;

  double? _currentUserLat;
  double? _currentUserLng;
  double? _lastDistance;
  int? _lastViolationCount;

  @override
  void initState() {
    super.initState();

    // ✨ Initialize notification service
    NotificationService.init();

    // ✨ FIX: Initialize here safely
    _autoClockOutService = AutoClockOutService(
      checkInterval: const Duration(seconds: 15),
      radiusInMeters: 250.0,
      // radiusInMeters: 10.0, //testing purpose
      onLeaveGeofence: _onUserLeftGeofence,
    );

    _initializeData();
    _startTimers();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _activityController.dispose();
    _autoClockOutService?.dispose(); // ✨ FIX: Safe null check
    super.dispose();
  }

  // ✨ CALLBACK: When user leaves geofence area
  Future<void> _onUserLeftGeofence(double distance) async {
    debugPrint(
      '🚨 AUTO CLOCK OUT TRIGGERED! Distance: ${distance.toStringAsFixed(2)}m',
    );

    if (mounted) {
      _showAutoClockOutDialog(distance);
    }

    await _performClockOut(isAutomatic: true, distance: distance);
  }

  Future<void> _updateGeofenceStatus() async {
    if (!(_autoClockOutService?.isMonitoring ?? false)) return;

    final status = await _autoClockOutService?.checkNow();
    if (status != null && status['distance'] != null && mounted) {
      setState(() {
        _currentUserLat = status['userLat'];
        _currentUserLng = status['userLng'];
        _lastDistance = status['distance'];
        _lastViolationCount = status['violationCount'];
      });
    }
  }

  void _showAutoClockOutDialog(double distance) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.orange,
        title: const Text(
          'Auto Clock Out',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off, size: 50, color: Colors.white),
            const SizedBox(height: 10),
            Text(
              'You have moved ${distance.toStringAsFixed(0)}m away from your work location.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 10),
            const Text(
              'You have been automatically clocked out.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateDateTime();
      if (_isClockedIn && (_autoClockOutService?.isMonitoring ?? false)) {
        _updateGeofenceStatus();
      }
    });
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
    if (result['success'] && mounted) {
      final provider = Provider.of<AttendanceProvider>(context, listen: false);
      provider.setFromApiResponse(result['data']);
    }
  }

  Future<void> _loadDropdownData() async {
    if (!mounted) return;
    setState(() => _loadingDropdowns = true);
    try {
      _clients = await ClientDetailApi.getClients(context);
      _projects = await ProjectApi.getProjects(context);
      _contracts = await ContractApi.getContracts(context);
    } catch (e) {
      debugPrint('Error loading dropdowns: $e');
    }
    if (mounted) setState(() => _loadingDropdowns = false);
  }

  Future<void> _checkExistingClock() async {
    final result = await ClockApi.getLatestClock(context);
    if (result['success'] && result['isClockedIn'] == true && mounted) {
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

      // ✨ If already clocked in, restart geofence monitoring
      _startGeofenceMonitoringForClient(_selectedClient);
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

    if (mounted) setState(() => _isLoading = true);

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _latitude = position.latitude;
      _longitude = position.longitude;

      // 🧪 DEBUG: Print your real lat/long - COPY THIS TO testMode!
      debugPrint('═══════════════════════════════════════════');
      debugPrint('🧪 YOUR REAL LOCATION:');
      debugPrint('   const double testLat = $_latitude;');
      debugPrint('   const double testLng = $_longitude;');
      debugPrint('═══════════════════════════════════════════');

      // Display coordinates instead of address to save geocoding API costs
      final coordinates =
          '${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}';
      if (mounted) setState(() => _currentAddress = coordinates);
    } catch (e) {
      debugPrint('Location error: $e');
      if (mounted) setState(() => _currentAddress = "Failed to get location");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ===================== GEOFENCE =====================

  /// Filter clients to show only those within 250m of current location
  List<dynamic> _getNearbyClients() {
    if (_latitude == null || _longitude == null) {
      debugPrint(
        '⚠️ No location available, showing all ${_clients.length} clients',
      );
      return _clients; // Return all if no location
    }

    final nearbyClients = _clients.where((client) {
      final locationData = client['LOCATION_DATA'] as List<dynamic>?;
      if (locationData == null || locationData.isEmpty) {
        return false; // Exclude clients without location
      }

      final location = locationData[0];
      final clientLat = (location['LATITUDE'] as num?)?.toDouble();
      final clientLng = (location['LONGITUDE'] as num?)?.toDouble();

      if (clientLat == null || clientLng == null) {
        return false; // Exclude clients with invalid coordinates
      }

      // Calculate distance
      final distance = GeofenceHelper.calculateDistance(
        _latitude!,
        _longitude!,
        clientLat,
        clientLng,
      );

      final isNearby = distance <= 10000.0;
      if (isNearby) {
        debugPrint(
          '✅ Client "${client['NAME']}" is ${distance.toStringAsFixed(1)}m away',
        );
      }

      return isNearby; // Only include clients within 250m
    }).toList();

    debugPrint(
      '📍 Found ${nearbyClients.length} clients within 250m (out of ${_clients.length} total)',
    );
    return nearbyClients;
  }

  void _startGeofenceMonitoringForClient(String? clientGuid) {
    // Use user's current location as geofence center (where they clocked in)
    // This way, auto clock-out triggers when they move 500m from their clock-in position
    final targetLat = _latitude;
    final targetLng = _longitude;
    final targetAddress = _currentAddress;

    if (targetLat == null || targetLng == null) {
      debugPrint('⚠️ No current location available');
      return;
    }

    debugPrint('🎯 Starting geofence monitoring');
    debugPrint('   Target: $targetLat, $targetLng');
    debugPrint('   Radius: 500.0m');
    debugPrint('   Check interval: 15s');
    debugPrint('   Required violations: 2');

    _autoClockOutService?.startMonitoring(
      targetLat: targetLat,
      targetLng: targetLng,
      targetAddress: targetAddress,
    );
  }

  /// Start background tracking for auto clock-out when app is closed
  Future<void> _startBackgroundTracking() async {
    try {
      // Request notification permission
      final notificationGranted =
          await NotificationService.requestPermissions();
      if (!notificationGranted) {
        debugPrint('⚠️ Notification permission denied');
        // Continue anyway, background tracking will still work
      }

      // Get target location (same logic as foreground geofence)
      // Use user's current location as geofence center (where they clocked in)
      double? targetLat = _latitude;
      double? targetLng = _longitude;
      String? targetAddress = _currentAddress;

      // Use test mode if enabled
      const bool testMode = false;
      if (testMode && _latitude != null && _longitude != null) {
        targetLat = _latitude;
        targetLng = _longitude;
        targetAddress = "Test Location - Your Current Position";
      } else if (_selectedClient != null && _selectedClient!.isNotEmpty) {
        // Find client from list
        try {
          final client = _clients.firstWhere(
            (c) => c['CLIENT_GUID'] == _selectedClient,
          );
          final locationData = client['LOCATION_DATA'] as List<dynamic>?;
          if (locationData != null && locationData.isNotEmpty) {
            final location = locationData[0];
            targetLat = (location['LATITUDE'] as num?)?.toDouble();
            targetLng = (location['LONGITUDE'] as num?)?.toDouble();
            targetAddress = location['ADDRESS'] as String?;
          }
        } catch (e) {
          debugPrint('⚠️ Error getting client location: $e');
        }
      }

      if (targetLat == null || targetLng == null || _clockRefGuid == null) {
        debugPrint(
          '⚠️ Cannot start background tracking: missing location or clockRefGuid',
        );
        return;
      }

      // Start background tracking
      await BackgroundGeofenceService.startTracking(
        targetLat: targetLat,
        targetLng: targetLng,
        targetAddress: targetAddress ?? 'Work Location',
        radiusInMeters: 500.0, // Same as foreground
        clockRefGuid: _clockRefGuid!,
      );

      debugPrint('✅ Background tracking started');
    } catch (e) {
      debugPrint('❌ Error starting background tracking: $e');
    }
  }

  // ===================== CLOCK IN/OUT =====================

  Future<void> _handleClockAction() async {
    // Validation 1: Job type required
    if (_selectedJobType.isEmpty) {
      _showDialog(
        'Error',
        'Please select a job type (Office/Site/Home/Others)',
      );
      return;
    }

    // Validation 2: Client required (only for clock in)
    if (!_isClockedIn &&
        _fieldVisibility['client'] == true &&
        _selectedClient == null) {
      _showDialog('Error', 'Please select a client');
      return;
    }

    // Validation 3: Location required
    if (_latitude == null || _longitude == null) {
      _showDialog('Error', 'Please get your current location first');
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

    if (result['success'] && mounted) {
      setState(() {
        _isClockedIn = true;
        _clockRefGuid = result['clockLogGuid'];
        _clockInTime = result['clockTime'];
        _clockStatus = result['clockTime'];
      });

      // ✨ START GEOFENCE MONITORING AFTER CLOCK IN
      _startGeofenceMonitoringForClient(_selectedClient);

      // ✨ REQUEST NOTIFICATION PERMISSION AND START BACKGROUND TRACKING
      await _startBackgroundTracking();

      _showSuccessDialog('Clock In Successful', 'Time: ${result['clockTime']}');
    } else {
      _showDialog('Error', result['message'] ?? 'Clock in failed');
    }
  }

  Future<void> _performClockOut({
    bool isAutomatic = false,
    double? distance,
  }) async {
    if (_clockRefGuid == null) {
      _showDialog('Error', 'No clock in record found');
      return;
    }

    // ✨ STOP FOREGROUND AND BACKGROUND MONITORING
    _autoClockOutService?.stopMonitoring();
    try {
      await BackgroundGeofenceService.stopTracking();
    } catch (e) {
      debugPrint('⚠️ Error stopping background tracking: $e');
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

    if (result['success'] && mounted) {
      if (!isAutomatic) {
        _showSuccessDialog(
          'Clock Out Successful',
          'In: $_clockInTime\nOut: ${result['clockTime']}',
        );
      } else {
        // Show persistent notification for auto clock-out
        await NotificationService.showAutoClockOutNotification(
          distance: distance ?? 0.0,
          location: _currentAddress ?? 'Work Location',
        );
      }

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
      _showDialog('Error', result['message'] ?? 'Clock out failed');
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
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showDialog(String title, String message) {
    if (!mounted) return;
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
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2DD36F),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(message, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
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

    // ✨ FIX: Safe check for monitoring status
    final isMonitoring = _autoClockOutService?.isMonitoring ?? false;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(
          176,
        ), // AppBar height (56) + Banner height (120)
        child: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/background_login.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: Column(
            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                elevation: 0,
                title: const Text('beeWhere'),
                actions: [
                  if (isMonitoring)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Row(
                        children: const [
                          Icon(
                            Icons.location_on,
                            color: Colors.green,
                            size: 20,
                          ),
                          SizedBox(width: 4),
                          Text('Tracking', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              ),
              // User info section (previously the banner)
              Container(
                height: 120,
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Icon(
                      Icons.account_circle,
                      size: 80,
                      color: Colors.white,
                    ),
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
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          companyName,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      drawer: const AppDrawer(),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 1) {
            // Navigate to history page
            Navigator.pushReplacementNamed(context, '/history');
          } else if (index == 2) {
            // Navigate to report page
            Navigator.pushReplacementNamed(context, '/report');
          } else if (index == 3) {
            // Navigate to profile page
            Navigator.pushReplacementNamed(context, '/profile');
          }
          // If index == 0 (Home), do nothing as we're already here
        },
      ),
      body: RefreshIndicator(
        onRefresh: _initializeData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildTimeCard(),
              const SizedBox(height: 10),
              _buildJobTypeButtons(attendance),
              _buildLocationDisplay(),
              if (_selectedJobType.isNotEmpty) _buildForm(),
              const SizedBox(height: 20),
              _buildClockButton(),
              if (_isClockedIn) _buildGeofenceStatus(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGeofenceStatus() {
    final isMonitoring = _autoClockOutService?.isMonitoring ?? false;
    if (!isMonitoring) return const SizedBox();

    return Container(
      margin: const EdgeInsets.all(15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.radar, color: Colors.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Geofence Active',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    Text(
                      'Monitoring: ${_autoClockOutService?.targetAddress ?? 'Work Location'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Text(
                      'Auto clock-out if you move >500m away',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          // Debug info section
          Text(
            'Debug Info:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your Location: ${_currentUserLat?.toStringAsFixed(6) ?? 'N/A'}, ${_currentUserLng?.toStringAsFixed(6) ?? 'N/A'}',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'Target: ${_autoClockOutService?.targetLat?.toStringAsFixed(6) ?? 'N/A'}, ${_autoClockOutService?.targetLng?.toStringAsFixed(6) ?? 'N/A'}',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'Distance: ${_lastDistance?.toStringAsFixed(2) ?? 'N/A'}m (Radius: ${_autoClockOutService?.radiusInMeters.toStringAsFixed(1) ?? 'N/A'}m)',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color:
                  (_lastDistance ?? 0) >
                      (_autoClockOutService?.radiusInMeters ?? 0)
                  ? Colors.red
                  : Colors.green,
            ),
          ),
          Text(
            'Violation Count: ${_lastViolationCount ?? 0}',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
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
    const purpleBlue = Color(
      0xFF6366F1,
    ); // Purple-blue/indigo to match background theme
    return Expanded(
      child: GestureDetector(
        onTap: _isClockedIn ? null : () => _onJobTypeSelected(title),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? purpleBlue : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: purpleBlue),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : purpleBlue,
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
              _getNearbyClients(), // Use filtered list
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
      child: SlideAction(
        height: 60,
        sliderButtonIconSize: 20,
        sliderButtonIconPadding: 14,
        innerColor: Colors.white,
        outerColor: _isClockedIn ? Colors.red : const Color(0xFF2DD36F),
        sliderButtonIcon: Icon(
          _isClockedIn ? Icons.logout : Icons.login,
          color: _isClockedIn ? Colors.red : const Color(0xFF2DD36F),
        ),
        text: _isClockedIn ? 'Slide to Clock Out' : 'Slide to Clock In',
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        onSubmit: () async {
          await _handleClockAction();
          return null; // Return null to reset slider
        },
      ),
    );
  }
}
