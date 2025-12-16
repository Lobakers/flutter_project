import 'dart:async';
import 'package:beewhere/controller/client_detail_api.dart';
import 'package:beewhere/controller/project_api.dart';
import 'package:beewhere/controller/contract_api.dart';

import 'package:beewhere/controller/attendance_profile_api.dart';
import 'package:beewhere/controller/clock_api.dart';
import 'package:beewhere/controller/geofence_helper.dart';
import 'package:beewhere/controller/auto_clockout_service.dart';
import 'package:beewhere/services/offline_database.dart';
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
import 'package:beewhere/widgets/location_map_widget.dart';
import 'package:beewhere/config/geofence_config.dart';
import 'package:beewhere/services/connectivity_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _locationAutoRefreshTimer; // Timer for auto location refresh
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

  // Connectivity state
  bool _isOnline = true;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

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
      checkInterval: GeofenceConfig.autoClockOutCheckInterval,
      radiusInMeters: GeofenceConfig.autoClockOutRadius,
      // radiusInMeters: 10.0, //testing purpose
      onLeaveGeofence: _onUserLeftGeofence,
    );

    // ✨ Listen to auto clock-out status stream
    _autoClockOutService?.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _currentUserLat = status['userLat'];
          _currentUserLng = status['userLng'];
          _lastDistance = status['distance'];
          _lastViolationCount = status['violationCount'];
        });
      }
    });

    _initializeData();
    _startTimers();
    _startLocationAutoRefresh();
    _initConnectivityListener();
  }

  // ✨ Initialize connectivity listener
  void _initConnectivityListener() {
    // Set initial state
    _isOnline = ConnectivityService.isOnline;

    // Listen to connectivity changes
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
    _activityController.dispose();
    _autoClockOutService?.dispose(); // ✨ FIX: Safe null check
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  // start auto location refresh
  void _startLocationAutoRefresh() {
    _locationAutoRefreshTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      if (mounted && !_isLoading) {
        _getCurrentPosition(); // ✨ Just call your existing method
      }
    });
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

  // ✨ LOAD CACHED DATA FOR INSTANT UI
  Future<void> _loadCachedData() async {
    // 1. Load Clock Status
    try {
      final cachedClock = await OfflineDatabase.getClockStatus();
      if (cachedClock != null && mounted) {
        debugPrint('📱 Loaded clock status from cache');
        setState(() {
          _isClockedIn = cachedClock['isClockedIn'] == true;
          if (_isClockedIn) {
            _clockRefGuid = cachedClock['clockLogGuid'];
            _clockInTime = cachedClock['clockTime'];
            _clockStatus = _formatClockTime(_clockInTime);
            _selectedJobType = _capitalizeFirst(cachedClock['jobType'] ?? '');
            _selectedClient = cachedClock['clientId'];
            _selectedProject = cachedClock['projectId'];
            _selectedContract = cachedClock['contractId'];
            _activityName = cachedClock['activityName'] ?? '';
            _activityController.text = _activityName;

            // Trigger UI updates
            _updateFieldVisibility(_selectedJobType);
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading cached clock status: $e');
    }

    // 2. Load Dropdowns
    try {
      final cachedClients = await OfflineDatabase.getClients();
      final cachedProjects = await OfflineDatabase.getProjects();
      final cachedContracts = await OfflineDatabase.getContracts();

      if (mounted) {
        setState(() {
          if (cachedClients.isNotEmpty) _clients = cachedClients;
          if (cachedProjects.isNotEmpty) _projects = cachedProjects;
          if (cachedContracts.isNotEmpty) _contracts = cachedContracts;
        });
        debugPrint(
          '📱 Loaded dropdowns from cache: ${_clients.length} clients',
        );
      }
    } catch (e) {
      debugPrint('Error loading cached dropdowns: $e');
    }
  }

  Future<void> _initializeData() async {
    // ✨ Load cache FIRST for instant feedback
    await _loadCachedData();

    await DeviceInfoHelper.init();
    await _loadAttendanceProfile();
    await _loadDropdownData();
    // ✅ FIX: Get location FIRST before checking clock status
    // This ensures _latitude and _longitude are available for geofence monitoring
    await _getCurrentPosition();
    await _checkExistingClock();
  }

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

        // ✨ Update live duration if clocked in
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
    if (!mounted) return;

    if (result['success'] && result['isClockedIn'] == true) {
      setState(() {
        _isClockedIn = true;
        _clockRefGuid = result['clockLogGuid'];
        _clockStatus = _formatClockTime(result['clockTime']); // ✨ Format time
        _clockInTime =
            result['clockTime']; // Store clock-in time for clock-out dialog
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
    } else if (result['success'] && result['isClockedIn'] == false) {
      // ✨ FIX: If cache said we were clocked in, but server says we are NOT, reset UI
      if (_isClockedIn) {
        debugPrint(
          '⚠️ Cache mismatch: Server says NOT clocked in. Resetting UI.',
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
        _autoClockOutService?.stopMonitoring();
      }
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
      debugPrint(
        '(test from homepage) YOUR REAL LOCATION at ${DateTime.now().toIso8601String()}:',
      );
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
  // List<dynamic> _getNearbyClients() {
  //   if (_latitude == null || _longitude == null) {
  //     debugPrint(
  //       '⚠️ No location available, showing all ${_clients.length} clients',
  //     );
  //     return _clients; // Return all if no location
  //   }

  //   final nearbyClients = _clients.where((client) {
  //     final locationData = client['LOCATION_DATA'] as List<dynamic>?;
  //     if (locationData == null || locationData.isEmpty) {
  //       return false; // Exclude clients without location
  //     }

  //     final location = locationData[0];
  //     final clientLat = (location['LATITUDE'] as num?)?.toDouble();
  //     final clientLng = (location['LONGITUDE'] as num?)?.toDouble();

  //     if (clientLat == null || clientLng == null) {
  //       return false; // Exclude clients with invalid coordinates
  //     }

  //     // Calculate distance
  //     final distance = GeofenceHelper.calculateDistance(
  //       _latitude!,
  //       _longitude!,
  //       clientLat,
  //       clientLng,
  //     );

  //     final isNearby = distance <= 1000.0;
  //     if (isNearby) {
  //       // debugPrint(
  //       //   '✅ Client "${client['NAME']}" is ${distance.toStringAsFixed(1)}m away',
  //       // );
  //     }

  //     return isNearby; // Only include clients within 250m
  //   }).toList();

  //   // debugPrint(
  //   //   '📍 Found ${nearbyClients.length} clients within 250m (out of ${_clients.length} total)',
  //   // );

  //   // Deduplicate by CLIENT_GUID to prevent dropdown errors
  //   final seenGuids = <String>{};
  //   final uniqueClients = nearbyClients.where((client) {
  //     final guid = client['CLIENT_GUID'] as String?;
  //     if (guid == null || seenGuids.contains(guid)) {
  //       return false;
  //     }
  //     seenGuids.add(guid);
  //     return true;
  //   }).toList();

  //   if (uniqueClients.length < nearbyClients.length) {
  //     debugPrint(
  //       '⚠️ Removed ${nearbyClients.length - uniqueClients.length} duplicate clients',
  //     );
  //   }

  //   return uniqueClients;
  // }

  /// Filter clients based on geofence_filter setting for the selected job type
  List<dynamic> _getNearbyClients() {
    // ✨ NEW: Check if geofence filtering is enabled for current job type
    final attendance = Provider.of<AttendanceProvider>(context, listen: false);
    final jobTypeConfig = attendance.getFieldsForJobType(_selectedJobType);
    final shouldFilterByGeofence = jobTypeConfig['geofence_filter'] ?? false;

    // If geofence filtering is disabled, return all clients
    if (!shouldFilterByGeofence) {
      // debugPrint(
      //   '📍 Geofence filter disabled for $_selectedJobType, showing all ${_clients.length} clients',
      // );
      return _clients;
    }

    // If no location available, return all clients with a warning
    if (_latitude == null || _longitude == null) {
      // debugPrint(
      //   '⚠️ No location available, showing all ${_clients.length} clients',
      // );
      return _clients;
    }

    // ✨ Get configured radius for job type
    final configRadius =
        attendance.getRadiusForJobType(_selectedJobType) ??
        GeofenceConfig.clientFilterRadius;

    // Filter clients within configured radius
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

      return distance <=
          configRadius; // Only include clients within configured radius
    }).toList();

    // debugPrint(
    //   '📍 Found ${nearbyClients.length} clients within 1000m (out of ${_clients.length} total)',
    // );

    // Deduplicate by CLIENT_GUID to prevent dropdown errors
    final seenGuids = <String>{};
    final uniqueClients = nearbyClients.where((client) {
      final guid = client['CLIENT_GUID'] as String?;
      if (guid == null || seenGuids.contains(guid)) {
        return false;
      }
      seenGuids.add(guid);
      return true;
    }).toList();

    if (uniqueClients.length < nearbyClients.length) {
      debugPrint(
        '⚠️ Removed ${nearbyClients.length - uniqueClients.length} duplicate clients',
      );
    }

    return uniqueClients;
  }

  /// Prepare client markers for map display
  /// Uses the same filtering logic as dropdown
  List<ClientMarkerData> _getClientMarkersForMap() {
    if (_latitude == null || _longitude == null) {
      return []; // No markers if no location
    }

    // ✨ Get filtered clients based on current job type's geofence setting
    final filteredClients = _getNearbyClients();

    // Convert to marker data
    final markers = <ClientMarkerData>[];

    for (var client in filteredClients) {
      final locationData = client['LOCATION_DATA'] as List<dynamic>?;
      if (locationData == null || locationData.isEmpty) continue;

      final location = locationData[0];
      final clientLat = (location['LATITUDE'] as num?)?.toDouble();
      final clientLng = (location['LONGITUDE'] as num?)?.toDouble();

      if (clientLat == null || clientLng == null) continue;

      // Calculate distance from user
      final distance = GeofenceHelper.calculateDistance(
        _latitude!,
        _longitude!,
        clientLat,
        clientLng,
      );

      markers.add(
        ClientMarkerData(
          clientGuid: client['CLIENT_GUID'] as String,
          name: client['NAME'] as String? ?? 'Unknown',
          abbreviation: client['ABBR'] as String? ?? 'N/A',
          latitude: clientLat,
          longitude: clientLng,
          distance: distance,
        ),
      );
    }

    // debugPrint('📍 Prepared ${markers.length} client markers for map');
    return markers;
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

    // ✨ Get configured radius for current job type
    final attendance = Provider.of<AttendanceProvider>(context, listen: false);
    final configRadius =
        attendance.getRadiusForJobType(_selectedJobType) ??
        GeofenceConfig.autoClockOutRadius;

    debugPrint('🎯 Starting geofence monitoring');
    debugPrint('   Target: $targetLat, $targetLng');
    debugPrint('   Radius: ${configRadius}m');
    debugPrint('   Check interval: 15s');
    debugPrint('   Required violations: 2');

    _autoClockOutService?.startMonitoring(
      targetLat: targetLat,
      targetLng: targetLng,
      targetAddress: targetAddress,
      radiusInMeters: configRadius, // ✨ Use dynamic radius
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
      // This ensures consistency between foreground and background monitoring
      double? targetLat = _latitude;
      double? targetLng = _longitude;
      String? targetAddress = _currentAddress;

      if (targetLat == null || targetLng == null || _clockRefGuid == null) {
        debugPrint(
          '⚠️ Cannot start background tracking: missing location or clockRefGuid',
        );
        return;
      }

      // ✨ Get configured radius for current job type
      final attendance = Provider.of<AttendanceProvider>(
        context,
        listen: false,
      );
      final configRadius =
          attendance.getRadiusForJobType(_selectedJobType) ??
          GeofenceConfig.autoClockOutRadius;

      // Start background tracking
      await BackgroundGeofenceService.startTracking(
        targetLat: targetLat,
        targetLng: targetLng,
        targetAddress: targetAddress ?? 'Work Location',
        radiusInMeters: configRadius, // ✨ Use dynamic radius
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
        'Action Required',
        'Please select a job type (Office/Site/Home/Others)',
      );
      return;
    }

    // Validation 2: Client required (only for clock in)
    if (!_isClockedIn &&
        _fieldVisibility['client'] == true &&
        _selectedClient == null) {
      _showDialog('Action Required', 'Please select a client');
      return;
    }

    // Validation 3: Location required
    if (_latitude == null || _longitude == null) {
      _showDialog('Action Required', 'Please get your current location first');
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
        _clockStatus = _formatClockTime(result['clockTime']); // ✨ Format time
      });

      // ✨ START GEOFENCE MONITORING AFTER CLOCK IN
      _startGeofenceMonitoringForClient(_selectedClient);

      // ✨ REQUEST NOTIFICATION PERMISSION AND START BACKGROUND TRACKING
      await _startBackgroundTracking();

      _showSuccessDialog(
        'Clock In Successful',
        'Time: ${_formatClockTime(result['clockTime'])}',
      );
    } else {
      // ✨ Check for multi-device conflict
      if (result['multiDeviceConflict'] == true) {
        _showMultiDeviceConflictDialog(
          'Already Clocked In',
          result['message'] ?? 'You have already clocked in on another device.',
        );
      } else {
        _showDialog('Error', result['message'] ?? 'Clock in failed');
      }
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
          'In: ${_formatClockTime(_clockInTime)}\nOut: ${_formatClockTime(result['clockTime'])}',
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
      // ✨ Check for multi-device conflict
      if (result['multiDeviceConflict'] == true) {
        _showMultiDeviceConflictDialog(
          'Already Clocked Out',
          result['message'] ??
              'You have already clocked out on another device.',
        );
      } else {
        _showDialog('Error', result['message'] ?? 'Clock out failed');
      }
    }
  }

  // ===================== UI HELPERS =====================

  void _onJobTypeSelected(String jobType) {
    setState(() {
      _selectedJobType = jobType;

      // ✨ FIX: Clear selected client if it's not in the new filtered list
      // This prevents dropdown errors when switching between job types with different geofence filters
      if (_selectedClient != null) {
        final filteredClients = _getNearbyClients();
        final clientExists = filteredClients.any(
          (client) => client['CLIENT_GUID'] == _selectedClient,
        );

        if (!clientExists) {
          debugPrint(
            '⚠️ Selected client not in filtered list for $jobType, clearing selection',
          );
          _selectedClient = null;
          _selectedProject = null;
          _selectedContract = null;
        }
      }
    });
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

  void _showSuccessDialog(String title, String message) {
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

  /// ✨ Show dialog for multi-device conflicts with refresh option
  void _showMultiDeviceConflictDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.orange,
        title: Row(
          children: [
            const Icon(Icons.devices, color: Colors.white, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Please refresh the page to sync the latest status.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              // Refresh the page data
              await _initializeData();
            },
            icon: const Icon(Icons.refresh, size: 20),
            label: const Text('Refresh Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.orange,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _capitalizeFirst(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Parse clock time string to DateTime object
  DateTime? _parseClockInTime(String? timeString) {
    if (timeString == null || timeString.isEmpty) return null;

    try {
      // CASE 1: ISO 8601 with 'Z' (e.g., "2025-12-04T11:40:04.000Z")
      // The API sends Local Time but marks it as UTC 'Z'.
      if (timeString.contains('T') && timeString.endsWith('Z')) {
        final localString = timeString.substring(0, timeString.length - 1);
        return DateTime.parse(localString);
      }
      // CASE 2: Space separated (e.g., "2025-12-04 03:40:27")
      // The API sends UTC time but without timezone info.
      else if (timeString.contains(' ') && !timeString.contains('T')) {
        final isoString = timeString.replaceAll(' ', 'T') + 'Z';
        return DateTime.parse(isoString).toLocal();
      }
      // CASE 3: Standard ISO
      else {
        return DateTime.parse(timeString);
      }
    } catch (e) {
      debugPrint('Error parsing time: $e');
      return null;
    }
  }

  /// Format clock time to Malaysia timezone (GMT+8)
  String _formatClockTime(String? timeString) {
    final dateTime = _parseClockInTime(timeString);
    if (dateTime == null) return 'N/A';

    // Format to readable Malaysia time: "04 Dec 2025, 11:40 AM"
    return DateFormat('dd MMM yyyy, hh:mm a').format(dateTime);
  }

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
          166,
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
                  // Online/Offline status label
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
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
              // User info section (previously the banner)
              Container(
                height: 110,
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
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
            Navigator.pushNamed(context, '/history');
          } else if (index == 2) {
            // Navigate to report page
            Navigator.pushNamed(context, '/report');
          } else if (index == 3) {
            // Navigate to profile page
            Navigator.pushNamed(context, '/profile');
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
              // const SizedBox(height: 10),
              _buildJobTypeButtons(attendance),
              if (_selectedJobType.isNotEmpty) _buildForm(),
              _buildLocationDisplay(),
              const SizedBox(height: 20),
              _buildClockButton(),
              // if (_isClockedIn) _buildGeofenceStatus(),
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
                    Text(
                      'Auto clock-out if you move >${_autoClockOutService?.radiusInMeters.toStringAsFixed(0) ?? 'N/A'}m away',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
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
          Text(
            _isClockedIn ? 'Clocked In' : 'Clock In',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _isClockedIn ? Colors.red : const Color(0xFF2DD36F),
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

  // Widget _buildLocationDisplay() {
  //   return Padding(
  //     padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
  //     child: Row(
  //       children: [
  //         Expanded(
  //           child: Container(
  //             height: 50,
  //             padding: const EdgeInsets.symmetric(horizontal: 12),
  //             decoration: BoxDecoration(
  //               color: Colors.grey.shade100,
  //               borderRadius: BorderRadius.circular(8),
  //               border: Border.all(color: Colors.grey.shade300),
  //             ),
  //             child: Center(
  //               child: _isLoading
  //                   ? const CircularProgressIndicator(strokeWidth: 2)
  //                   : Text(
  //                       _currentAddress,
  //                       style: const TextStyle(fontSize: 14),
  //                       overflow: TextOverflow.ellipsis,
  //                     ),
  //             ),
  //           ),
  //         ),
  //         const SizedBox(width: 10),
  //         Container(
  //           decoration: BoxDecoration(
  //             color: BeeColor.fillIcon,
  //             borderRadius: BorderRadius.circular(30),
  //             border: Border.all(color: Colors.black, width: 2),
  //           ),
  //           child: IconButton(
  //             icon: const Icon(Icons.my_location),
  //             onPressed: _isLoading ? null : _getCurrentPosition,
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildLocationDisplay() {
    // ✨ Determine radius based on job type's geofence_filter setting
    double? displayRadius;
    if (_selectedJobType.isNotEmpty) {
      final attendance = Provider.of<AttendanceProvider>(
        context,
        listen: false,
      );
      final jobTypeConfig = attendance.getFieldsForJobType(_selectedJobType);
      final shouldShowRadius = jobTypeConfig['geofence_filter'] ?? false;

      if (shouldShowRadius) {
        // ✨ Get dynamic radius (fallback to default)
        final configRadius =
            attendance.getRadiusForJobType(_selectedJobType) ??
            GeofenceConfig.mapDisplayRadius;
        displayRadius = configRadius;
      }
    }

    return Column(
      children: [
        // 🗺️ Map display with refresh button inside
        if (_latitude != null && _longitude != null)
          LocationMapWidget(
            latitude: _latitude!,
            longitude: _longitude!,
            height: 250,
            showRefreshButton: true,
            onRefresh: _isLoading ? null : _getCurrentPosition,
            clientMarkers: _getClientMarkersForMap(),
            radiusInMeters: displayRadius, // ✨ NEW: Pass radius
          )
        else
          // Show placeholder when no location
          Container(
            height: 250,
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300, width: 2),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.location_off,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No Location Available',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _getCurrentPosition,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    label: Text(
                      _isLoading ? 'Getting Location...' : 'Get Location',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
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

    // Show helpful message when no clients are nearby
    if (label == 'Client' && items.isEmpty) {
      // ✨ Get configured radius for message
      final attendance = Provider.of<AttendanceProvider>(
        context,
        listen: false,
      );
      final radius =
          attendance.getRadiusForJobType(_selectedJobType) ??
          GeofenceConfig.clientFilterRadius;

      return Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.location_off, color: Colors.orange.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No Clients Nearby',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    GeofenceConfig.getNoClientsFoundMessage(radius),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ✨ FIX: Validate that value exists in items list
    // If the value is not in the list, set it to null to prevent dropdown errors
    String? validatedValue = value;
    if (value != null) {
      final valueExists = items.any((item) => item[valueKey] == value);
      if (!valueExists) {
        debugPrint(
          '⚠️ Dropdown value $value not found in items, setting to null',
        );
        validatedValue = null;
      }
    }

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
        value: validatedValue,
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
