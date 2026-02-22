import 'dart:async';
import 'package:beewhere/controller/client_detail_api.dart';
import 'package:beewhere/controller/project_api.dart';
import 'package:beewhere/controller/contract_api.dart';

import 'package:beewhere/controller/attendance_profile_api.dart';
import 'package:beewhere/controller/clock_api.dart';
import 'package:beewhere/controller/geofence_helper.dart';
import 'package:beewhere/controller/auto_clockout_service.dart';
import 'package:beewhere/services/offline_database.dart';
import 'package:beewhere/services/storage_service.dart'; // ✅ Import for watchdog
import 'package:beewhere/services/background_geofence_service.dart';
import 'package:beewhere/services/notification_service.dart';
import 'package:beewhere/services/logger_service.dart'; // ✨ For on-device debug logs
import 'package:beewhere/services/location_permission_service.dart';
import 'package:beewhere/services/pending_sync_service.dart'; // ✨ NEW
import 'package:beewhere/providers/auth_provider.dart';
import 'package:beewhere/providers/attendance_provider.dart';
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
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:beewhere/widgets/searchable_selection_sheet.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
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
  Timer? _serviceWatchdog; // ✅ FIX BUG #7: Watchdog to detect service death

  // Clock state
  bool _isClockedIn = false;
  String _clockStatus = "You Haven't Clocked In Yet";
  String? _clockRefGuid;
  String? _clockInTime;
  bool _isProcessingClockAction =
      false; // ✅ FIX BUG #14: Lock form during API call

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
  int _pendingSyncCount = 0; // ✨ NEW: Track pending actions for UI badge
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
    _startLocationStream(); // ✨ Start real-time stream
    _initConnectivityListener();

    // ✨ Request background location permission on startup
    // Use addPostFrameCallback to ensure context is valid for showing dialogs
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocationAndClock();
    });

    // ✨ Add app lifecycle observer to refresh status when app resumes
    WidgetsBinding.instance.addObserver(this);

    // ✅ FIX BUG #7: Start service watchdog to detect if OS kills the service
    _startServiceWatchdog();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      debugPrint('📱 App resumed, refreshing clock status');

      // Re-check connectivity status on app resume
      // This fixes the issue where indicator stays "offline" after phone sleep
      try {
        final isOnline = await ConnectivityService.checkConnectivity();
        if (mounted) {
          setState(() {
            _isOnline = isOnline;
          });
        }
        debugPrint('📡 Connectivity refreshed on resume: $_isOnline');
      } catch (e) {
        debugPrint('⚠️ Error checking connectivity on resume: $e');
      }

      // ✨ Resume stream if needed
      if (_positionStreamSubscription == null ||
          _positionStreamSubscription!.isPaused) {
        _startLocationStream();
      }

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

      // ✅ FIX BUG #6: Refresh pending sync count on app resume
      // This ensures badge updates after background sync completes
      try {
        final count = await PendingSyncService.getPendingCount();
        if (mounted) {
          setState(() {
            _pendingSyncCount = count;
          });
        }
        debugPrint('📊 Pending sync count refreshed: $count');
      } catch (e) {
        debugPrint('⚠️ Error refreshing pending count: $e');
      }
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
  void _initConnectivityListener() {
    // Set initial state
    _isOnline = ConnectivityService.isOnline;

    // Listen to connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      ConnectivityResult result,
    ) {
      final wasOnline = _isOnline;
      final isNowOnline = result != ConnectivityResult.none;

      if (mounted) {
        setState(() {
          _isOnline = isNowOnline;
        });
      }

      // FIX: Only re-sync with server when connection is RESTORED (offline -> online).
      // When going offline, we preserve the current in-memory clock state as-is.
      // This prevents the UI from resetting to "not clocked in" on connectivity loss.
      if (!wasOnline && isNowOnline) {
        debugPrint('📡 Connection restored — syncing clock status with server...');
        _checkExistingClock();
      }
    });
  }

  // ✅ FIX BUG #7: Service watchdog to detect and restart dead service
  void _startServiceWatchdog() {
    // Check every 5 minutes if service is still running
    _serviceWatchdog = Timer.periodic(const Duration(minutes: 5), (
      timer,
    ) async {
      try {
        // Only check if user is clocked in
        if (!_isClockedIn) return;

        final isRunning = await FlutterForegroundTask.isRunningService;
        if (!isRunning) {
          debugPrint(
            '⚠️ WATCHDOG: Background service died! Attempting restart...',
          );

          // Get saved tracking parameters from storage
          final state = await StorageService.getClockInState();
          if (state != null && state['isClockedIn'] == true) {
            final targetLat = state['targetLat'] as double?;
            final targetLng = state['targetLng'] as double?;
            final targetAddress = state['targetAddress'] as String?;
            final radiusInMeters = state['radiusInMeters'] as double?;
            final clockRefGuid = state['clockRefGuid'] as String?;

            if (targetLat != null &&
                targetLng != null &&
                clockRefGuid != null) {
              debugPrint(
                '🔄 WATCHDOG: Restarting service with saved parameters',
              );
              await BackgroundGeofenceService.startTracking(
                targetLat: targetLat,
                targetLng: targetLng,
                targetAddress: targetAddress ?? 'work location',
                radiusInMeters:
                    radiusInMeters ?? GeofenceConfig.autoClockOutRadius,
                clockRefGuid: clockRefGuid,
              );
              debugPrint('✅ WATCHDOG: Service restarted successfully');
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ WATCHDOG: Error checking service: $e');
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _serviceWatchdog?.cancel(); // ✅ Stop watchdog
    _positionStreamSubscription?.cancel(); // ✨ Cancel stream
    _activityController.dispose();
    _autoClockOutService?.dispose(); // ✨ FIX: Safe null check
    _connectivitySubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this); // ✨ Remove lifecycle observer

    super.dispose();
  }

  StreamSubscription<Position>?
  _positionStreamSubscription; // ✨ Stream for real-time location

  // start auto location refresh
  void _startLocationStream() {
    // Cancel existing stream if any
    _positionStreamSubscription?.cancel();

    // ✨ Subscribe to location updates
    // detailed configuration for "Waze-like" updates
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high, // Good accuracy
      distanceFilter: 5, // Update every 5 meters moved
    );

    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _latitude = position.latitude;
                _longitude = position.longitude;
                // Update address string
                _currentAddress =
                    '${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}';
              });

              // 🧪 DEBUG: Print your real lat/long
              // debugPrint(
              //   '📍 Stream Location: ${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}',
              // );
            }
          },
          onError: (e) {
            debugPrint('Location stream error: $e');
          },
        );
  }

  // ✨ Flag to prevent multiple simultaneous auto clock-out calls
  bool _isAutoClockingOut = false;

  // ✨ CALLBACK: When user leaves geofence area or location is disabled
  Future<void> _onUserLeftGeofence(double distance) async {
    LoggerService.logNotification(
      '_onUserLeftGeofence called with distance: $distance, isClockedIn: $_isClockedIn, isAutoClockingOut: $_isAutoClockingOut',
    );

    // Check if we're still clocked in (prevent duplicate clock-out)
    if (!_isClockedIn) {
      LoggerService.logWithEmoji(
        '!',
        'Already clocked out, ignoring auto clock-out trigger',
      );
      return;
    }

    // ✨ NEW: Check if already processing via the service's global lock
    // This handles cases where multiple HomePage instances might exist
    // if (!AutoClockOutService.isGloballyProcessing) { ... } -- Service already blocked the call,
    // but we add it here as a safety log.
    LoggerService.logWithEmoji(
      'ℹ️',
      '_onUserLeftGeofence processing start. Global lock should be active.',
    );

    // Check if already processing an auto clock-out
    if (_isAutoClockingOut) {
      LoggerService.logFailure(
        'Auto clock-out already in progress, ignoring duplicate trigger',
      );
      return;
    }

    // Set flag to prevent duplicate calls
    _isAutoClockingOut = true;

    try {
      // ✨ CRITICAL: Stop background service IMMEDIATELY to prevent duplicate triggers
      LoggerService.logGeofenceStop(
        'Stopping background service to prevent duplicate auto clock-out',
      );
      try {
        await BackgroundGeofenceService.stopTracking();
      } catch (e) {
        LoggerService.logFailure('Error stopping background service: $e');
      }

      // Special case: distance = -1 means location service was disabled
      if (distance < 0) {
        LoggerService.logAutoClockOut(
          'FOREGROUND AUTO CLOCK OUT TRIGGERED! Location service DISABLED',
        );

        // ✨ NEW: Immediately update local and database state so background isolate sees us as clocked out
        setState(() => _isClockedIn = false);
        await OfflineDatabase.saveClockStatus({
          'isClockedIn': false,
          'clockLogGuid': null,
          'clockTime': null,
          'jobType': null,
          'address': null,
          'clientId': null,
          'projectId': null,
          'contractId': null,
          'activityName': null,
        });

        if (mounted) {
          _showLocationDisabledDialog();
        }
        await _performClockOut(
          isAutomatic: true,
          distance: 0,
          reason: 'location_disabled',
        );
      } else if (distance == -2.0) {
        LoggerService.logAutoClockOut(
          'FOREGROUND AUTO CLOCK OUT TRIGGERED! Location permission REVOKED',
        );

        // ✨ Immediately update state
        setState(() => _isClockedIn = false);
        await OfflineDatabase.saveClockStatus({
          'isClockedIn': false,
          'clockLogGuid': null,
          'clockTime': null,
          'jobType': null,
          'address': null,
          'clientId': null,
          'projectId': null,
          'contractId': null,
          'activityName': null,
        });

        if (mounted) {
          _showPermissionRevokedDialog();
        }

        await _performClockOut(
          isAutomatic: true,
          distance: 0,
          reason: 'permission_revoked',
        );
      } else {
        LoggerService.logAutoClockOut(
          'FOREGROUND AUTO CLOCK OUT TRIGGERED! Distance: ${distance.toStringAsFixed(2)}m',
        );

        // ✨ NEW: Immediately update local and database state so background isolate sees us as clocked out
        setState(() => _isClockedIn = false);
        await OfflineDatabase.saveClockStatus({
          'isClockedIn': false,
          'clockLogGuid': null,
          'clockTime': null,
          'jobType': null,
          'address': null,
          'clientId': null,
          'projectId': null,
          'contractId': null,
          'activityName': null,
        });

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

  // ✨ LOAD CACHED DATA FOR INSTANT UI
  Future<void> _loadCachedData() async {
    // 1. Load Clock Status (only if not already loaded from server)
    try {
      // ✅ FIX: Don't overwrite server data with stale cache
      if (_clockRefGuid != null) {
        debugPrint('⏭️ Skipping cache load - server data already loaded');
        return;
      }

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
    // ✅ CRITICAL FIX: Load attendance profile FIRST
    // This must happen before _checkExistingClock() which calls _startGeofenceMonitoringForClient()
    // Otherwise getRadiusForJobType() returns NULL, using default 250m instead of configured range
    await _loadAttendanceProfile();

    // ✅ FIX: Check server state to avoid showing stale cache
    // This prevents showing "31 hours clocked in" from old cache
    await _checkExistingClock();

    // ✨ Load cache FIRST for instant feedback (if server check failed)
    await _loadCachedData();

    await DeviceInfoHelper.init();
    await _loadDropdownData();
    // Logic moved to _initLocationAndClock to allow UI to build first

    // ✨ Update pending sync count
    try {
      final count = await PendingSyncService.getPendingCount();
      if (mounted) {
        setState(() => _pendingSyncCount = count);
      }
    } catch (e) {
      debugPrint('⚠️ Error updating pending count: $e');
    }
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

    // Note: _checkExistingClock() now called in _initializeData()
    // to prevent showing stale cache before server verification
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
    debugPrint('📊 AttendanceProfileApi result: $result');
    if (result['success'] && mounted) {
      final provider = Provider.of<AttendanceProvider>(context, listen: false);
      provider.setFromApiResponse(result['data']);
      debugPrint('✅ AttendanceProvider initialized successfully');
    } else {
      debugPrint(
        '❌ Failed to load attendance profile: ${result['message'] ?? 'Unknown error'}',
      );
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
      await _startGeofenceMonitoringForClient(_selectedClient);

      // ✅ FIX BUG #13: Restart background service if not running
      // CRITICAL: After clear app data, UI syncs but service doesn't restart
      try {
        final isServiceRunning = await FlutterForegroundTask.isRunningService;
        if (!isServiceRunning) {
          debugPrint(
            '⚠️ User clocked in but background service not running! Restarting...',
          );

          // Get saved tracking parameters from storage
          final state = await StorageService.getClockInState();
          if (state != null && state['isClockedIn'] == true) {
            final targetLat = state['targetLat'] as double?;
            final targetLng = state['targetLng'] as double?;
            final targetAddress = state['targetAddress'] as String?;
            final radiusInMeters = state['radiusInMeters'] as double?;
            final clockRefGuid = state['clockRefGuid'] as String?;

            if (targetLat != null &&
                targetLng != null &&
                clockRefGuid != null) {
              debugPrint(
                '🔄 Restarting background service with saved parameters',
              );

              // Get configured radius for current job type
              final attendance = Provider.of<AttendanceProvider>(
                context,
                listen: false,
              );
              final configRadius =
                  attendance.getRadiusForJobType(_selectedJobType) ??
                  radiusInMeters ??
                  GeofenceConfig.autoClockOutRadius;

              await BackgroundGeofenceService.startTracking(
                targetLat: targetLat,
                targetLng: targetLng,
                targetAddress: targetAddress ?? 'work location',
                radiusInMeters: configRadius,
                clockRefGuid: clockRefGuid,
              );
              debugPrint('✅ Background service restarted successfully');
            } else {
              debugPrint('⚠️ Missing required parameters to restart service');
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error checking/restarting background service: $e');
      }
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
    } else if (!result['success']) {
      // ✅ FIX: API call failed (e.g. network error during connectivity transition).
      // Do NOT reset the UI — preserve whatever clock state is already in memory.
      // When the user is clocked in and loses connection, this keeps the UI correctly
      // showing "Clocked In" instead of resetting to "not clocked in".
      debugPrint(
        '⚠️ getLatestClock failed (${result['message'] ?? 'unknown error'}). '
        'Preserving in-memory clock state (_isClockedIn: $_isClockedIn).',
      );
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

      // ✅ FIX BUG #10: Detect mock location during clock-in
      // CRITICAL SECURITY: Prevent fraudulent clock-ins
      if (position.isMocked) {
        debugPrint('🚨 MOCK LOCATION DETECTED during clock-in attempt!');
        if (mounted) {
          setState(() {
            _currentAddress = "Mock location detected";
            _isLoading = false;
          });
          _showDialog(
            'Invalid Location',
            'Mock location detected. Please disable any GPS spoofing apps and try again.\n\nThis is a security measure to prevent fraudulent clock-ins.',
          );
        }
        return;
      }

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
      return _clients;
    }

    // If no location available, return all clients with a warning
    if (_latitude == null || _longitude == null) {
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

      // ✨ NEW: Check ALL locations, not just the first one
      bool isAnyLocationNearby = false;

      for (var location in locationData) {
        final clientLat = (location['LATITUDE'] as num?)?.toDouble();
        final clientLng = (location['LONGITUDE'] as num?)?.toDouble();

        if (clientLat == null || clientLng == null) continue;

        // Calculate distance
        final distance = GeofenceHelper.calculateDistance(
          _latitude!,
          _longitude!,
          clientLat,
          clientLng,
        );

        if (distance <= configRadius) {
          isAnyLocationNearby = true;
          break; // Found one nearby location, so this client is valid
        }
      }

      return isAnyLocationNearby;
    }).toList();

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

    // ✅ Check if geofence filtering is enabled for this job type
    final attendance = Provider.of<AttendanceProvider>(context, listen: false);
    final jobTypeConfig = attendance.getFieldsForJobType(_selectedJobType);
    final shouldFilterByGeofence = jobTypeConfig['geofence_filter'] ?? false;

    // ✨ Get the configured radius for filtering (only used if filtering is enabled)
    final configRadius =
        attendance.getRadiusForJobType(_selectedJobType) ??
        GeofenceConfig.clientFilterRadius;

    // debugPrint(
    //   '📍 [_getClientMarkersForMap] JobType: $_selectedJobType, geofence_filter: $shouldFilterByGeofence, configRadius: $configRadius, filteredClients: ${filteredClients.length}',
    // );

    // Convert to marker data
    final markers = <ClientMarkerData>[];

    for (var client in filteredClients) {
      final locationData = client['LOCATION_DATA'] as List<dynamic>?;
      if (locationData == null || locationData.isEmpty) continue;

      // ✨ NEW: Create a marker for EVERY valid location
      for (var location in locationData) {
        final locationGuid = location['LOCATION_GUID'] as String?;
        final clientLat = (location['LATITUDE'] as num?)?.toDouble();
        final clientLng = (location['LONGITUDE'] as num?)?.toDouble();
        final address = location['ADDRESS'] as String?;

        if (clientLat == null || clientLng == null) continue;

        // Calculate distance from user
        final distance = GeofenceHelper.calculateDistance(
          _latitude!,
          _longitude!,
          clientLat,
          clientLng,
        );

        // ✅ FIX: Only apply distance filter if geofence filtering is enabled
        // If geofence filtering is disabled, show all markers (matching dropdown behavior)
        // If geofence filtering is enabled, only show markers within configured radius
        if (!shouldFilterByGeofence || distance <= configRadius) {
          markers.add(
            ClientMarkerData(
              clientGuid: client['CLIENT_GUID'] as String,
              locationGuid: locationGuid, // ✨ NEW
              name: client['NAME'] as String? ?? 'Unknown',
              abbreviation: client['ABBR'] as String? ?? 'N/A',
              latitude: clientLat,
              longitude: clientLng,
              address: address, // ✨ NEW
              distance: distance,
            ),
          );
        }
      }
    }

    // debugPrint(
    //   '📍 [_getClientMarkersForMap] Created ${markers.length} markers for map display',
    // );
    return markers;
  }

  Future<void> _startGeofenceMonitoringForClient(String? clientGuid) async {
    // ✨ NEW: Check if auto clock-out is enabled for this job type
    final attendance = Provider.of<AttendanceProvider>(context, listen: false);
    final isAutoClockOutEnabled = attendance.isAutoClockOutEnabledForJobType(
      _selectedJobType,
    );

    if (!isAutoClockOutEnabled) {
      LoggerService.logGeofenceStop(
        '[_startGeofenceMonitoringForClient] Auto clock-out DISABLED for $_selectedJobType (geofence monitoring not started)',
      );
      return; // Skip geofence monitoring if auto clock-out is disabled
    }

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

    // ✅ DEBUG: Log what we're about to look up
    LoggerService.logGeofenceStart(
      '[_startGeofenceMonitoringForClient] _selectedJobType: "$_selectedJobType"',
    );

    final configRadius =
        attendance.getRadiusForJobType(_selectedJobType) ??
        GeofenceConfig.autoClockOutRadius;

    // ✅ DEBUG: Log the result
    LoggerService.logGeofenceStart(
      '[_startGeofenceMonitoringForClient] getRadiusForJobType returned: ${attendance.getRadiusForJobType(_selectedJobType)}',
    );

    LoggerService.logGeofenceStart('Starting geofence monitoring');
    LoggerService.logWithEmoji('   🎯', 'Target: $targetLat, $targetLng');
    LoggerService.logDistance('Current radius in service: ${configRadius}m');
    LoggerService.logWithEmoji('   ⏱️', 'Check interval: 15s');
    LoggerService.logWithEmoji('   ✓', 'Required violations: 2');

    await _autoClockOutService?.startMonitoring(
      targetLat: targetLat,
      targetLng: targetLng,
      targetAddress: targetAddress,
      radiusInMeters: configRadius, // ✨ Use dynamic radius
    );
  }

  /// Start background tracking for auto clock-out when app is closed
  Future<void> _startBackgroundTracking() async {
    try {
      // ✨ NEW: Check if auto clock-out is enabled for this job type
      final attendance = Provider.of<AttendanceProvider>(
        context,
        listen: false,
      );
      final isAutoClockOutEnabled = attendance.isAutoClockOutEnabledForJobType(
        _selectedJobType,
      );

      if (!isAutoClockOutEnabled) {
        LoggerService.warning(
          'Auto clock-out DISABLED for $_selectedJobType (background tracking not started)',
          tag: 'BackgroundTracking',
        );
        return; // Skip background tracking if auto clock-out is disabled
      }

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
    // ✅ FIX BUG #14: Prevent concurrent actions
    if (_isProcessingClockAction) {
      debugPrint('⚠️ Clock action already in progress, ignoring');
      return;
    }

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

    // Validation 4: Background location permission required (only for clock in)
    if (!_isClockedIn) {
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

    // ✅ FIX BUG #14: Lock form during processing
    setState(() => _isProcessingClockAction = true);

    try {
      if (_isClockedIn) {
        await _performClockOut();
      } else {
        await _performClockIn();
      }
    } finally {
      // ✅ Always unlock form after processing
      if (mounted) {
        setState(() => _isProcessingClockAction = false);
      }
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
      await AutoClockOutService.resetGlobalLock();
      await _startGeofenceMonitoringForClient(_selectedClient);

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

      // ✨ NEW: Check for battery optimization (Android specific)
      if (Platform.isAndroid) {
        try {
          final isOptimized =
              await Permission.ignoreBatteryOptimizations.isDenied;
          if (isOptimized && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(
                      Icons.battery_alert_rounded,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Disable "Battery Optimization" for accurate tracking.',
                        style: TextStyle(fontSize: 13, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                backgroundColor: const Color(
                  0xFF333333,
                ), // Professional dark grey
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                duration: const Duration(seconds: 8),
                action: SnackBarAction(
                  label: 'FIX',
                  textColor: Colors.orange,
                  onPressed: () {
                    openAppSettings();
                  },
                ),
              ),
            );
          }
        } catch (e) {
          debugPrint('⚠️ Error checking battery optimization: $e');
        }
      }

      // ✨ Update pending sync count after action
      try {
        final count = await PendingSyncService.getPendingCount();
        if (mounted) setState(() => _pendingSyncCount = count);
      } catch (e) {
        debugPrint('⚠️ Error updating pending count: $e');
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

    // ✨ NEW: Always reset the global lock after a clock-out attempt
    await AutoClockOutService.resetGlobalLock();

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
          reason: reason,
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

      // ✨ Update pending sync count after action
      try {
        final count = await PendingSyncService.getPendingCount();
        if (mounted) setState(() => _pendingSyncCount = count);
      } catch (e) {
        debugPrint('⚠️ Error updating pending count: $e');
      }
    } else {
      // ✨ Check for multi-device conflict
      if (result['multiDeviceConflict'] == true) {
        // If it's automatic clock-out, just update UI silently (already clocked out)
        if (isAutomatic) {
          debugPrint(
            '⚠️ Auto clock-out: Already clocked out on another device, updating UI',
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

  void _showLocationDisabledDialog() {
    _showSafetyDialog(
      title: 'Location Service Disabled',
      message:
          'Location services have been turned off. For accurate attendance tracking, we have automatically clocked you out.',
      icon: Icons.location_off,
      color: Colors.orange,
    );
  }

  void _showAutoClockOutDialog(double distance) {
    _showSafetyDialog(
      title: 'Auto Clock Out',
      message:
          'You have moved ${distance.toStringAsFixed(0)}m away from your work location. For your safety and attendance integrity, we have automatically clocked you out.',
      icon: Icons.location_on,
      color: Colors.orange,
    );
  }

  void _showPermissionRevokedDialog() {
    _showSafetyDialog(
      title: 'Location Permission Revoked',
      message:
          'Location permissions have been removed. For your safety and attendance integrity, we have automatically clocked you out.',
      icon: Icons.security,
      color: Colors.red,
    );
  }

  void _showSafetyDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
  }) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
          ],
        ),
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
    final email = auth.userInfo?['email'] ?? 'No email';
    final companyName = auth.userInfo?['companyName'] ?? 'No company';

    // ✨ FIX: Safe check for monitoring status
    final isMonitoring = _autoClockOutService?.isMonitoring ?? false;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(
          140,
        ), // Reduced height to match tighter content (was 166)
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
                  const SizedBox(width: 8),

                  // ✨ NEW: Pending sync badge
                  if (_pendingSyncCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange, width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.sync,
                            color: Colors.orange,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Pending: $_pendingSyncCount',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 16),
                ],
              ),
              // User info section (previously the banner)
              Expanded(
                child: Container(
                  width: double.infinity,
                  // Reduced top padding to pull text closer to AppBar title
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
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
              const SizedBox(height: 5),
              _buildClockButton(),
              // if (_isClockedIn) _buildGeofenceStatus(),
              const SizedBox(height: 15),
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
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 5),
      padding: const EdgeInsets.fromLTRB(15, 5, 15, 5),
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
      padding: const EdgeInsets.symmetric(horizontal: 5),
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
          margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 15),
          padding: const EdgeInsets.symmetric(vertical: 10),
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
            margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
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
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
          // Activity field hidden as per user request (editable in history later)
          // if (_fieldVisibility['activity'] == true) _buildActivityField(),
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
    if (_loadingDropdowns) {
      return const Padding(
        padding: EdgeInsets.all(10),
        child: CircularProgressIndicator(),
      );
    }

    // Show helpful message when no clients are nearby
    if (label == 'Client' && items.isEmpty) {
      // ✨ NEW: Check if geofence filtering is enabled for current job type
      final attendance = Provider.of<AttendanceProvider>(
        context,
        listen: false,
      );
      final jobTypeConfig = attendance.getFieldsForJobType(_selectedJobType);
      final shouldFilterByGeofence = jobTypeConfig['geofence_filter'] ?? false;

      // ✨ FIX: Don't show "No Clients Nearby" message if geofence filtering is disabled
      // For Home/Others (geofence_filter=false), we should return all clients when they load
      // So if items are empty, it's just a loading state - return empty container
      if (!shouldFilterByGeofence) {
        return const SizedBox.shrink(); // Return empty space while clients load
      }

      // ✨ Get configured radius for message (only if filtering is enabled)
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

    // Find selected item label
    String displayValue = 'Select $label';
    if (value != null) {
      final selectedItem = items.firstWhere(
        (item) => item[valueKey] == value,
        orElse: () => null,
      );
      if (selectedItem != null) {
        displayValue = selectedItem[labelKey] ?? '';
      }
    }

    return GestureDetector(
      onTap: _isClockedIn
          ? null
          : () => _showSelectionSheet(
              label,
              items,
              value,
              valueKey,
              labelKey,
              onChanged,
            ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey),
          color: _isClockedIn ? Colors.grey.shade200 : Colors.white,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                displayValue,
                style: TextStyle(
                  fontSize: 16,
                  color: value == null ? Colors.grey.shade600 : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  // ✨ NEW: Searchable Bottom Sheet
  void _showSelectionSheet(
    String label,
    List<dynamic> items,
    String? currentValue,
    String valueKey,
    String labelKey,
    Function(String?) onChanged,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SearchableSelectionSheet(
          label: label,
          items: items,
          selectedValue: currentValue,
          valueKey: valueKey,
          labelKey: labelKey,
          onSelected: (value) {
            onChanged(value);
            Navigator.pop(context); // Close the sheet
          },
        );
      },
    );
  }

  // Widget _buildActivityField() {
  //   return TextField(
  //     controller: _activityController,
  //     enabled: !_isClockedIn,
  //     maxLines: 3,
  //     onChanged: (v) => _activityName = v,
  //     decoration: const InputDecoration(
  //       labelText: 'Activity List',
  //       hintText: 'Add task here',
  //       border: OutlineInputBorder(),
  //     ),
  //   );
  // }

  Widget _buildClockButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
