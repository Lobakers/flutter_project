import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'package:beewhere/config/geofence_config.dart';
import 'package:beewhere/controller/attendance_profile_api.dart';
import 'package:beewhere/controller/clock_api.dart';
import 'package:beewhere/controller/geofence_helper.dart';
import 'package:beewhere/providers/attendance_provider.dart';
import 'package:beewhere/providers/auth_provider.dart';
import 'package:beewhere/providers/clock_provider.dart';
import 'package:beewhere/services/background_geofence_service.dart';
import 'package:beewhere/services/connectivity_service.dart';
import 'package:beewhere/services/location_permission_service.dart';
import 'package:beewhere/services/notification_service.dart';
import 'package:beewhere/services/offline_database.dart';
import 'package:beewhere/services/storage_service.dart';
import 'package:beewhere/pages/history_page.dart';
import 'package:beewhere/pages/main_shell.dart';
import 'package:beewhere/widgets/device_info_helper.dart';
import 'package:beewhere/widgets/drawer.dart';
import 'package:beewhere/widgets/location_map_widget.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:slide_to_act/slide_to_act.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
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

  // ✨ Restored local state for form input management
  final TextEditingController _activityController = TextEditingController();
  Map<String, bool> _fieldVisibility = {};

  ClockProvider get clockProvider =>
      Provider.of<ClockProvider>(context, listen: false);

  double? _currentUserLat;
  double? _currentUserLng;
  double? _lastDistance;
  int? _lastViolationCount;

  @override
  void initState() {
    super.initState();

    // ✨ Initialize notification service
    NotificationService.init();

    _initializeData();
    _startTimers();
    _startLocationAutoRefresh();

    // ✨ Initialize ClockProvider and background monitoring
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final clockProvider = Provider.of<ClockProvider>(context, listen: false);
      clockProvider.initialize(context);

      // Listen for auto clock-out events
      clockProvider.autoClockOutEvents.listen((distance) {
        if (mounted) {
          _onUserLeftGeofence(distance);
        }
      });

      _initLocationAndClock();
    });

    // ✨ Add app lifecycle observer to refresh status when app resumes
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      debugPrint('📱 App resumed, refreshing clock status');

      // ✨ Tell background service that app is in foreground
      try {
        await FlutterForegroundTask.saveData(
          key: 'appInForeground',
          value: true,
        );
      } catch (e) {
        debugPrint('⚠️ Error updating foreground flag: $e');
      }

      // Refresh clock status from server when app resumes
      _checkExistingClock();

      // ✨ Check if an auto clock-out happened in background
      _checkPendingAutoClockOut();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      debugPrint('📱 App paused/inactive, background service will take over');

      // ✨ Tell background service that app is NOT in foreground
      try {
        await FlutterForegroundTask.saveData(
          key: 'appInForeground',
          value: false,
        );
      } catch (e) {
        debugPrint('⚠️ Error updating foreground flag: $e');
      }
    }
  }

  // ✨ Initialize connectivity listener

  @override
  void dispose() {
    _timer?.cancel();
    _locationAutoRefreshTimer?.cancel();
    _activityController.dispose();
    WidgetsBinding.instance.removeObserver(this); // ✨ Remove lifecycle observer
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

  // ✨ Flag to prevent multiple simultaneous auto clock-out calls
  bool _isAutoClockingOut = false;

  // ✨ CALLBACK: When user leaves geofence area or location is disabled
  Future<void> _onUserLeftGeofence(double distance) async {
    debugPrint(
      '🔔 _onUserLeftGeofence called with distance: $distance, isClockedIn: ${clockProvider.isClockedIn}, isAutoClockingOut: $_isAutoClockingOut',
    );

    // Check if we're still clocked in (prevent duplicate clock-out)
    if (!clockProvider.isClockedIn) {
      debugPrint('⚠️ Already clocked out, ignoring auto clock-out trigger');
      return;
    }

    // Check if already processing an auto clock-out
    if (_isAutoClockingOut) {
      debugPrint(
        '⚠️ Auto clock-out already in progress, ignoring duplicate trigger',
      );
      return;
    }

    // Set flag to prevent duplicate calls
    _isAutoClockingOut = true;

    try {
      // ✨ CRITICAL: Stop background service IMMEDIATELY to prevent duplicate triggers
      debugPrint(
        '🛑 Stopping background service to prevent duplicate auto clock-out',
      );
      await BackgroundGeofenceService.stopTracking();

      // Special case: distance = -1 means location service was disabled
      if (distance < 0) {
        debugPrint(
          '🚨 FOREGROUND AUTO CLOCK OUT TRIGGERED! Location service DISABLED',
        );

        if (mounted) {
          _showLocationDisabledDialog();
        }

        await _performClockOut(
          isAutomatic: true,
          distance: 0,
          reason: 'location_disabled',
        );
      } else {
        debugPrint(
          '🚨 FOREGROUND AUTO CLOCK OUT TRIGGERED! Distance: ${distance.toStringAsFixed(2)}m',
        );

        if (mounted) {
          _showAutoClockOutDialog(distance);
        }

        await _performClockOut(isAutomatic: true, distance: distance);
      }
    } finally {
      // Reset flag after clock-out completes
      _isAutoClockingOut = false;
    }
  }

  Future<void> _checkPendingAutoClockOut() async {
    final pending = await StorageService.getAutoClockOutPending();
    if (pending != null && mounted) {
      final distance = pending['distance'] as double? ?? 0.0;
      final reason = pending['reason'] as String?;

      // Clear the flag so it doesn't show again
      await StorageService.clearAutoClockOutPending();

      // Show the dialog
      if (reason == 'location_disabled') {
        _showLocationDisabledDialog();
      } else {
        _showAutoClockOutDialog(distance);
      }
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

  void _showLocationDisabledDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.red,
        title: const Text(
          'Auto Clock Out',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_disabled, size: 50, color: Colors.white),
            const SizedBox(height: 10),
            const Text(
              'Location service has been disabled.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
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
          clockProvider.isClockedIn = cachedClock['isClockedIn'] == true;
          if (clockProvider.isClockedIn) {
            clockProvider.clockRefGuid = cachedClock['clockLogGuid'];
            clockProvider.clockInTime = cachedClock['clockTime'];
            clockProvider.clockStatus = _formatClockTime(
              clockProvider.clockInTime,
            );
            clockProvider.selectedJobType = _capitalizeFirst(
              cachedClock['jobType'] ?? '',
            );
            clockProvider.selectedClient = cachedClock['clientId'];
            clockProvider.selectedProject = cachedClock['projectId'];
            clockProvider.selectedContract = cachedClock['contractId'];
            clockProvider.activityName = cachedClock['activityName'] ?? '';
            _activityController.text = clockProvider.activityName;

            // Trigger UI updates
            _updateFieldVisibility(clockProvider.selectedJobType);
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
          if (cachedClients.isNotEmpty) clockProvider.clients = cachedClients;
          if (cachedProjects.isNotEmpty)
            clockProvider.projects = cachedProjects;
          if (cachedContracts.isNotEmpty)
            clockProvider.contracts = cachedContracts;
        });
        debugPrint(
          '📱 Loaded dropdowns from cache: ${clockProvider.clients.length} clients',
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
    // Load dropdown data via provider
    await clockProvider.loadDropdownData(context);
    // Logic moved to _initLocationAndClock to allow UI to build first
  }

  // ✨ NEW: Handle permissions, location, and clock status after frame build
  Future<void> _initLocationAndClock() async {
    if (!mounted) return;

    // 1. Show Prominent Disclosure & Request Permissions
    // This will show the "Purple" dialog if background permission is missing
    final granted = await LocationPermissionService.requestLocationPermissions(
      context,
    );

    // ✨ FIX: If user declines on startup, show the warning immediately
    if (!granted && mounted) {
      _showOpenSettingsDialog();
    }

    // 2. Get Location
    // This handles foreground permission if not already granted
    await _getCurrentPosition();

    // 3. Check Clock Status
    // This uses location for geofence monitoring
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
        if (clockProvider.isClockedIn && clockProvider.clockInTime != null) {
          final clockInDate = _parseClockInTime(clockProvider.clockInTime);
          if (clockInDate != null) {
            final difference = now.difference(clockInDate);
            final hours = difference.inHours;
            final minutes = difference.inMinutes % 60;
            clockProvider.clockStatus = '$hours hours $minutes minute';
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

  Future<void> _checkExistingClock() async {
    final result = await ClockApi.getLatestClock(context);
    if (!mounted) return;

    if (result['success'] && result['isClockedIn'] == true) {
      setState(() {
        clockProvider.isClockedIn = true;
        clockProvider.clockRefGuid = result['clockLogGuid'];
        clockProvider.clockStatus = _formatClockTime(
          result['clockTime'],
        ); // ✨ Format time
        clockProvider.clockInTime =
            result['clockTime']; // Store clock-in time for clock-out dialog
        clockProvider.selectedJobType = _capitalizeFirst(
          result['jobType'] ?? '',
        );
        clockProvider.selectedClient = result['clientId'];
        clockProvider.selectedProject = result['projectId'];
        clockProvider.selectedContract = result['contractId'];
        clockProvider.activityName = result['activityName'] ?? '';
        _activityController.text = clockProvider.activityName;
      });
      _updateFieldVisibility(clockProvider.selectedJobType);

      // ✨ If already clocked in, restart geofence monitoring
      await _startGeofenceMonitoringForClient(clockProvider.selectedClient);
    } else if (result['success'] && result['isClockedIn'] == false) {
      // ✨ FIX: If cache said we were clocked in, but server says we are NOT, reset UI
      if (clockProvider.isClockedIn) {
        debugPrint(
          '⚠️ Cache mismatch: Server says NOT clocked in. Resetting UI.',
        );
        setState(() {
          clockProvider.isClockedIn = false;
          clockProvider.clockRefGuid = null;
          clockProvider.clockStatus = "You Haven't Clocked In Yet";
          clockProvider.selectedJobType = '';
          clockProvider.selectedClient = null;
          clockProvider.selectedProject = null;
          clockProvider.selectedContract = null;
          _activityController.clear();
          _fieldVisibility = {};
        });
        clockProvider.autoClockOutService?.stopMonitoring();
      }
    }
  }

  // ===================== LOCATION =====================

  // ✨ UPDATED: Only check foreground location permission
  // Background location is checked separately before clock-in
  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('Location services disabled. Please enable them.');
      return false;
    }

    // ✨ Use the standardized permission service which includes prominent disclosure
    final granted = await LocationPermissionService.requestLocationPermissions(
      context,
    );

    if (!granted) {
      // If not granted, we might want to show a specific message or dialog
      // but requestLocationPermissions already handles the flow.
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

  /// Filter clients based on geofence_filter setting for the selected job type
  List<dynamic> _getNearbyClients() {
    // ✨ NEW: Check if geofence filtering is enabled for current job type
    final attendance = Provider.of<AttendanceProvider>(context, listen: false);
    final jobTypeConfig = attendance.getFieldsForJobType(
      clockProvider.selectedJobType,
    );
    final shouldFilterByGeofence = jobTypeConfig['geofence_filter'] ?? false;

    // If geofence filtering is disabled, return all clients
    if (!shouldFilterByGeofence) {
      // debugPrint(
      //   '📍 Geofence filter disabled for $clockProvider.selectedJobType, showing all ${clockProvider.clients.length} clients',
      // );
      return clockProvider.clients;
    }

    // If no location available, return all clients with a warning
    if (_latitude == null || _longitude == null) {
      // debugPrint(
      //   '⚠️ No location available, showing all ${clockProvider.clients.length} clients',
      // );
      return clockProvider.clients;
    }

    // ✨ Get configured radius for job type
    final configRadius =
        attendance.getRadiusForJobType(clockProvider.selectedJobType) ??
        GeofenceConfig.clientFilterRadius;

    // Filter clients within configured radius
    final nearbyClients = clockProvider.clients.where((client) {
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
    //   '📍 Found ${nearbyClients.length} clients within 1000m (out of ${clockProvider.clients.length} total)',
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

  Future<void> _startGeofenceMonitoringForClient(String? clientGuid) async {
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
        attendance.getRadiusForJobType(clockProvider.selectedJobType) ??
        GeofenceConfig.autoClockOutRadius;

    debugPrint('🎯 Starting geofence monitoring');
    debugPrint('   Target: $targetLat, $targetLng');
    debugPrint('   Radius: ${configRadius}m');
    debugPrint('   Check interval: 15s');
    debugPrint('   Required violations: 2');

    await clockProvider.autoClockOutService?.startMonitoring(
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

      if (targetLat == null ||
          targetLng == null ||
          clockProvider.clockRefGuid == null) {
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
          attendance.getRadiusForJobType(clockProvider.selectedJobType) ??
          GeofenceConfig.autoClockOutRadius;

      // Start background tracking
      await BackgroundGeofenceService.startTracking(
        targetLat: targetLat,
        targetLng: targetLng,
        targetAddress: targetAddress ?? 'Work Location',
        radiusInMeters: configRadius, // ✨ Use dynamic radius
        clockRefGuid: clockProvider.clockRefGuid!,
      );

      debugPrint('✅ Background tracking started');
    } catch (e) {
      debugPrint('❌ Error starting background tracking: $e');
    }
  }

  // ===================== CLOCK IN/OUT =====================

  Future<void> _handleClockAction() async {
    // Validation 1: Job type required
    if (clockProvider.selectedJobType.isEmpty) {
      _showDialog(
        'Action Required',
        'Please select a job type (Office/Site/Home/Others)',
      );
      return;
    }

    // Validation 2: Client required (only for clock in)
    if (!clockProvider.isClockedIn &&
        _fieldVisibility['client'] == true &&
        clockProvider.selectedClient == null) {
      _showDialog('Action Required', 'Please select a client');
      return;
    }

    // Validation 3: Location required
    if (_latitude == null || _longitude == null) {
      _showDialog('Action Required', 'Please get your current location first');
      return;
    }

    // Validation 4: Background location permission required (only for clock in)
    if (!clockProvider.isClockedIn) {
      final hasPermission =
          await LocationPermissionService.hasBackgroundPermission();
      if (!hasPermission) {
        // ✨ Simplified: Go directly to disclosure request instead of showing Red dialog first
        final granted =
            await LocationPermissionService.requestLocationPermissions(context);
        if (!granted) {
          if (mounted) _showOpenSettingsDialog();
          return;
        }
      }
    }

    if (clockProvider.isClockedIn) {
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
      jobType: clockProvider.selectedJobType.toLowerCase(),
      latitude: _latitude,
      longitude: _longitude,
      address: _currentAddress,
      clientId: clockProvider.selectedClient,
      projectId: clockProvider.selectedProject,
      contractId: clockProvider.selectedContract,
      activityName: clockProvider.activityName,
      deviceDescription: DeviceInfoHelper.deviceDescription,
      deviceIp: DeviceInfoHelper.deviceIp,
      deviceId: DeviceInfoHelper.deviceId,
    );

    if (result['success'] && mounted) {
      setState(() {
        clockProvider.isClockedIn = true;
        clockProvider.clockRefGuid = result['clockLogGuid'];
        clockProvider.clockInTime = result['clockTime'];
        clockProvider.clockStatus = _formatClockTime(
          result['clockTime'],
        ); // ✨ Format time
      });

      // ✨ START GEOFENCE MONITORING AFTER CLOCK IN
      await _startGeofenceMonitoringForClient(clockProvider.selectedClient);

      // ✨ REQUEST NOTIFICATION PERMISSION AND START BACKGROUND TRACKING
      await _startBackgroundTracking();

      // ✨ Set initial foreground flag (app is currently open)
      try {
        await FlutterForegroundTask.saveData(
          key: 'appInForeground',
          value: true,
        );
      } catch (e) {
        debugPrint('⚠️ Error setting initial foreground flag: $e');
      }

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
    String? reason,
  }) async {
    if (clockProvider.clockRefGuid == null) {
      _showDialog('Error', 'No clock in record found');
      return;
    }

    // ✨ STOP FOREGROUND AND BACKGROUND MONITORING
    clockProvider.autoClockOutService?.stopMonitoring();
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
      jobType: clockProvider.selectedJobType.toLowerCase(),
      latitude: _latitude,
      longitude: _longitude,
      address: _currentAddress,
      clockRefGuid: clockProvider.clockRefGuid!,
      clientId: clockProvider.selectedClient,
      projectId: clockProvider.selectedProject,
      contractId: clockProvider.selectedContract,
      activityName: clockProvider.activityName,
      deviceDescription: DeviceInfoHelper.deviceDescription,
      deviceIp: DeviceInfoHelper.deviceIp,
      deviceId: DeviceInfoHelper.deviceId,
    );

    if (result['success'] && mounted) {
      if (!isAutomatic) {
        _showSuccessDialog(
          'Clock Out Successful',
          'In: ${_formatClockTime(clockProvider.clockInTime)}\nOut: ${_formatClockTime(result['clockTime'])}',
        );
      } else {
        // Show persistent notification for auto clock-out
        await NotificationService.showAutoClockOutNotification(
          distance: distance ?? 0.0,
          location: _currentAddress ?? 'Work Location',
          reason: reason,
        );
      }

      setState(() {
        clockProvider.isClockedIn = false;
        clockProvider.clockRefGuid = null;
        clockProvider.clockStatus = "You Haven't Clocked In Yet";
        clockProvider.selectedJobType = '';
        clockProvider.selectedClient = null;
        clockProvider.selectedProject = null;
        clockProvider.selectedContract = null;
        _activityController.clear();
        _fieldVisibility = {};
      });
    } else {
      // ✨ Check for multi-device conflict
      if (result['multiDeviceConflict'] == true) {
        // If it's automatic clock-out, just update UI silently (already clocked out)
        if (isAutomatic) {
          debugPrint(
            '⚠️ Auto clock-out: Already clocked out on another device, updating UI',
          );
          setState(() {
            clockProvider.isClockedIn = false;
            clockProvider.clockRefGuid = null;
            clockProvider.clockStatus = "You Haven't Clocked In Yet";
            clockProvider.selectedJobType = '';
            clockProvider.selectedClient = null;
            clockProvider.selectedProject = null;
            clockProvider.selectedContract = null;
            _activityController.clear();
            _fieldVisibility = {};
          });
        } else {
          // Manual clock-out: show dialog
          _showMultiDeviceConflictDialog(
            'Already Clocked Out',
            result['message'] ??
                'You have already clocked out on another device.',
          );
        }
      } else {
        _showDialog('Error', result['message'] ?? 'Clock out failed');
      }
    }
  }

  // ===================== UI HELPERS =====================

  void _onJobTypeSelected(String jobType) {
    setState(() {
      clockProvider.selectedJobType = jobType;

      // ✨ FIX: Clear selected client if it's not in the new filtered list
      // This prevents dropdown errors when switching between job types with different geofence filters
      if (clockProvider.selectedClient != null) {
        final filteredClients = _getNearbyClients();
        final clientExists = filteredClients.any(
          (client) => client['CLIENT_GUID'] == clockProvider.selectedClient,
        );

        if (!clientExists) {
          debugPrint(
            '⚠️ Selected client not in filtered list for $jobType, clearing selection',
          );
          clockProvider.selectedClient = null;
          clockProvider.selectedProject = null;
          clockProvider.selectedContract = null;
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

  // ✨ NEW: Show dialog to open app settings
  void _showOpenSettingsDialog() {
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
                Color(0xFFF59E0B), // Orange
                Color(0xFFEA580C), // Dark orange
              ],
            ),
            borderRadius: BorderRadius.circular(20),
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
                  Icons.settings,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              // Title
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Permission Denied',
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
                  'You need to manually grant background location permission in app settings.\n\nGo to Settings → Permissions → Location → Allow all the time',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white, width: 2),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await LocationPermissionService.openAppSettings();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFFF59E0B),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Open Settings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
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
      // The API sends UTC time with 'Z' marker
      if (timeString.contains('T') && timeString.endsWith('Z')) {
        final utcTime = DateTime.parse(timeString);
        final localTime = utcTime.toLocal();
        return localTime;
      }
      // CASE 2: Space separated (e.g., "2025-12-04 03:40:27" or "2025-12-04 15:40:27")
      // The API returns UTC time in space-separated format
      // BUT we need to detect if it's already been converted to local
      else if (timeString.contains(' ') && !timeString.contains('T')) {
        final isoString = timeString.replaceAll(' ', 'T');

        // Parse as UTC first
        final utcTime = DateTime.parse(isoString + 'Z');
        final localTime = utcTime.toLocal();

        // Check if the converted time is reasonable (within 1 hour of now)
        // If the UTC->Local conversion gives us a time very close to now, it's correct
        // If it gives us a time 8 hours in the future, the original was already local
        final now = DateTime.now();
        final differenceInMinutes = localTime.difference(now).inMinutes.abs();

        if (differenceInMinutes < 60) {
          // Converted time is within 1 hour of now - correct UTC conversion
          return localTime;
        } else {
          // Converted time is far from now - original was already local time
          final originalAsLocal = DateTime.parse(isoString);
          return originalAsLocal;
        }
      }
      // CASE 3: ISO format without Z (e.g., "2025-12-04T11:40:04" or "2025-12-04T11:40:04.123456")
      // Need to detect if it's UTC or already local time
      else if (timeString.contains('T')) {
        // Try UTC conversion first
        final utcTime = DateTime.parse(timeString + 'Z');
        final localTime = utcTime.toLocal();

        // Check if the converted time is reasonable (within 1 hour of now)
        final now = DateTime.now();
        final differenceInMinutes = localTime.difference(now).inMinutes.abs();

        if (differenceInMinutes < 60) {
          // Converted time is within 1 hour of now - correct UTC conversion
          return localTime;
        } else {
          // Converted time is far from now - original was already local time
          final originalAsLocal = DateTime.parse(timeString);
          return originalAsLocal;
        }
      }
      // CASE 4: Fallback
      else {
        final time = DateTime.parse(timeString);
        return time;
      }
    } catch (e) {
      debugPrint('❌ Error parsing clock time "$timeString": $e');
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
    final clockProvider = Provider.of<ClockProvider>(context);
    final connectivity = Provider.of<ConnectivityService>(context);

    final email = auth.userInfo?['email'] ?? 'No email';
    final companyName = auth.userInfo?['companyName'] ?? 'No company';

    final isOnline = connectivity.online;
    // ✨ FIX: Safe check for monitoring status
    final isMonitoring =
        clockProvider.autoClockOutService?.isMonitoring ?? false;

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
                      color: isOnline
                          ? Colors.green.withOpacity(0.2)
                          : Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isOnline ? Colors.green : Colors.red,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isOnline ? Icons.wifi : Icons.wifi_off,
                          color: isOnline ? Colors.green : Colors.red,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isOnline ? Colors.green : Colors.red,
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
      body: RefreshIndicator(
        onRefresh: _initializeData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildTimeCard(),
              // const SizedBox(height: 10),
              _buildJobTypeButtons(attendance),
              if (clockProvider.selectedJobType.isNotEmpty) _buildForm(),
              _buildLocationDisplay(),
              const SizedBox(height: 20),
              _buildClockButton(),
              if (clockProvider.isClockedIn && email == 'irfan@zen.com.my')
                _buildGeofenceStatus(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGeofenceStatus() {
    // Geofence status is now handled via clockProvider.autoClockOutService
    if (!clockProvider.isClockedIn) return const SizedBox();

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
                      'Monitoring: ${clockProvider.autoClockOutService?.targetAddress ?? 'Work Location'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Auto clock-out if you move >${clockProvider.autoClockOutService?.radiusInMeters.toStringAsFixed(0) ?? 'N/A'}m away',
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
            'Target: ${clockProvider.autoClockOutService?.targetLat?.toStringAsFixed(6) ?? 'N/A'}, ${clockProvider.autoClockOutService?.targetLng?.toStringAsFixed(6) ?? 'N/A'}',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'Distance: ${_lastDistance?.toStringAsFixed(2) ?? 'N/A'}m (Radius: ${clockProvider.autoClockOutService?.radiusInMeters.toStringAsFixed(1) ?? 'N/A'}m)',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color:
                  (_lastDistance ?? 0) >
                      (clockProvider.autoClockOutService?.radiusInMeters ?? 0)
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
            clockProvider.isClockedIn ? 'Clocked In' : 'Clock In',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: clockProvider.isClockedIn
                  ? Colors.red
                  : const Color(0xFF2DD36F),
            ),
          ),
          Text(
            clockProvider.clockStatus,
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
    final isSelected = clockProvider.selectedJobType == title;
    const purpleBlue = Color(
      0xFF6366F1,
    ); // Purple-blue/indigo to match background theme
    return Expanded(
      child: GestureDetector(
        onTap: clockProvider.isClockedIn
            ? null
            : () => _onJobTypeSelected(title),
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
    if (clockProvider.selectedJobType.isNotEmpty) {
      final attendance = Provider.of<AttendanceProvider>(
        context,
        listen: false,
      );
      final jobTypeConfig = attendance.getFieldsForJobType(
        clockProvider.selectedJobType,
      );
      final shouldShowRadius = jobTypeConfig['geofence_filter'] ?? false;

      if (shouldShowRadius) {
        // ✨ Get dynamic radius (fallback to default)
        final configRadius =
            attendance.getRadiusForJobType(clockProvider.selectedJobType) ??
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
              clockProvider.selectedClient,
              'CLIENT_GUID',
              'NAME',
              (v) => setState(() => clockProvider.selectedClient = v),
            ),
          if (_fieldVisibility['project'] == true)
            _buildDropdown(
              'Project',
              clockProvider.projects,
              clockProvider.selectedProject,
              'PROJECT_GUID',
              'NAME',
              (v) => setState(() => clockProvider.selectedProject = v),
            ),
          if (_fieldVisibility['contract'] == true)
            _buildDropdown(
              'Contract',
              clockProvider.contracts,
              clockProvider.selectedContract,
              'CONTRACT_GUID',
              'NAME',
              (v) => setState(() => clockProvider.selectedContract = v),
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
    if (clockProvider.loadingDropdowns)
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
          attendance.getRadiusForJobType(clockProvider.selectedJobType) ??
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
        onChanged: clockProvider.isClockedIn ? null : onChanged,
      ),
    );
  }

  Widget _buildActivityField() {
    return TextField(
      controller: _activityController,
      enabled: !clockProvider.isClockedIn,
      maxLines: 3,
      onChanged: (v) => clockProvider.activityName = v,
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
        outerColor: clockProvider.isClockedIn
            ? Colors.red
            : const Color(0xFF2DD36F),
        sliderButtonIcon: Icon(
          clockProvider.isClockedIn ? Icons.logout : Icons.login,
          color: clockProvider.isClockedIn
              ? Colors.red
              : const Color(0xFF2DD36F),
        ),
        text: clockProvider.isClockedIn
            ? 'Slide to Clock Out'
            : 'Slide to Clock In',
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
