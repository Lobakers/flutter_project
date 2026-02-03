import 'dart:async';
import 'package:flutter/material.dart';
import 'package:beewhere/controller/clock_api.dart';
import 'package:beewhere/controller/auto_clockout_service.dart';
import 'package:beewhere/config/geofence_config.dart';
import 'package:beewhere/services/offline_database.dart';
import 'package:beewhere/services/background_geofence_service.dart';
import 'package:beewhere/services/logger_service.dart';
import 'package:beewhere/controller/client_detail_api.dart';
import 'package:beewhere/controller/project_api.dart';
import 'package:beewhere/controller/contract_api.dart';

class ClockProvider with ChangeNotifier {
  bool _isClockedIn = false;
  String _clockStatus = "You Haven't Clocked In Yet";
  String? _clockRefGuid;
  String? _clockInTime;

  // Form selections
  String _selectedJobType = '';
  String? _selectedClient;
  String? _selectedProject;
  String? _selectedContract;
  String _activityName = '';

  // Data lists for dropdowns
  List<dynamic> _clients = [];
  List<dynamic> _projects = [];
  List<dynamic> _contracts = [];
  bool _loadingDropdowns = false;

  bool _isAutoClockingOut = false;
  bool _isInitializing = true;

  AutoClockOutService? _autoClockOutService;

  // Getters
  bool get isClockedIn => _isClockedIn;
  String get clockStatus => _clockStatus;
  String? get clockRefGuid => _clockRefGuid;
  String? get clockInTime => _clockInTime;
  String get selectedJobType => _selectedJobType;
  String? get selectedClient => _selectedClient;
  String? get selectedProject => _selectedProject;
  String? get selectedContract => _selectedContract;
  String get activityName => _activityName;
  bool get isAutoClockingOut => _isAutoClockingOut;
  bool get isInitializing => _isInitializing;
  AutoClockOutService? get autoClockOutService => _autoClockOutService;

  List<dynamic> get clients => _clients;
  List<dynamic> get projects => _projects;
  List<dynamic> get contracts => _contracts;
  bool get loadingDropdowns => _loadingDropdowns;

  // Setters
  set isClockedIn(bool value) {
    _isClockedIn = value;
    notifyListeners();
  }

  set clients(List<dynamic> value) {
    _clients = value;
    notifyListeners();
  }

  set projects(List<dynamic> value) {
    _projects = value;
    notifyListeners();
  }

  set contracts(List<dynamic> value) {
    _contracts = value;
    notifyListeners();
  }

  set clockStatus(String value) {
    _clockStatus = value;
    notifyListeners();
  }

  set clockRefGuid(String? value) {
    _clockRefGuid = value;
    notifyListeners();
  }

  set clockInTime(String? value) {
    _clockInTime = value;
    notifyListeners();
  }

  set selectedJobType(String value) {
    _selectedJobType = value;
    notifyListeners();
  }

  set selectedClient(String? value) {
    _selectedClient = value;
    notifyListeners();
  }

  set selectedProject(String? value) {
    _selectedProject = value;
    notifyListeners();
  }

  set selectedContract(String? value) {
    _selectedContract = value;
    notifyListeners();
  }

  set activityName(String value) {
    _activityName = value;
    notifyListeners();
  }

  // Stream for auto clock-out events (to show dialogs in UI)
  final StreamController<double> _autoClockOutEventController =
      StreamController<double>.broadcast();
  Stream<double> get autoClockOutEvents => _autoClockOutEventController.stream;

  ClockProvider() {
    _autoClockOutService = AutoClockOutService(
      checkInterval: GeofenceConfig.autoClockOutCheckInterval,
      radiusInMeters: GeofenceConfig.autoClockOutRadius,
      onLeaveGeofence: _handleAutoClockOut,
    );
  }

  /// Initialize clock status from cache and server
  Future<void> initialize(BuildContext context) async {
    _isInitializing = true;
    notifyListeners();

    try {
      // 1. Load from cache first for instant UI
      final cached = await OfflineDatabase.getClockStatus();
      if (cached != null) {
        _updateFromMap(cached);
        if (_isClockedIn) {
          // Restart geofence monitoring if was clocked in
          await _startMonitoring();
        }
      }

      // 2. Sync with server in background
      _syncWithServer(context);
    } catch (e) {
      LoggerService.error('Failed to initialize ClockProvider: $e');
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Silently sync status with server
  Future<void> _syncWithServer(BuildContext context) async {
    final result = await ClockApi.getLatestClock(context);
    if (result['success']) {
      final serverClockedIn = result['isClockedIn'] == true;

      // If server state differs from local, update
      if (serverClockedIn != _isClockedIn ||
          result['clockLogGuid'] != _clockRefGuid) {
        debugPrint('🔄 ClockProvider: Server sync - updating status');
        _updateFromMap(result);

        if (_isClockedIn) {
          await _startMonitoring();
        } else {
          await stopMonitoring();
        }
        notifyListeners();
      }
    }
  }

  /// Load dropdown data from API
  Future<void> loadDropdownData(BuildContext context) async {
    if (_clients.isNotEmpty && _projects.isNotEmpty && _contracts.isNotEmpty) {
      return; // Already loaded
    }

    _loadingDropdowns = true;
    notifyListeners();

    try {
      final clientsData = await ClientDetailApi.getClients(context);
      final projectsData = await ProjectApi.getProjects(context);
      final contractsData = await ContractApi.getContracts(context);

      _clients = clientsData;
      _projects = projectsData;
      _contracts = contractsData;
    } catch (e) {
      LoggerService.error('Error loading dropdown data: $e');
    } finally {
      _loadingDropdowns = false;
      notifyListeners();
    }
  }

  void _updateFromMap(Map<String, dynamic> data) {
    _isClockedIn = data['isClockedIn'] == true;
    _clockRefGuid = data['clockLogGuid'];
    _clockInTime = data['clockTime'];
    _selectedJobType = data['jobType'] ?? '';
    _selectedClient = data['clientId'];
    _selectedProject = data['projectId'];
    _selectedContract = data['contractId'];
    _activityName = data['activityName'] ?? '';

    if (!_isClockedIn) {
      _clockStatus = "You Haven't Clocked In Yet";
    }
  }

  /// Set form selections
  void setSelections({
    String? jobType,
    String? client,
    String? project,
    String? contract,
    String? activity,
  }) {
    if (jobType != null) _selectedJobType = jobType;
    if (client != null) _selectedClient = client;
    if (project != null) _selectedProject = project;
    if (contract != null) _selectedContract = contract;
    if (activity != null) _activityName = activity;
    notifyListeners();
  }

  /// Update clock status after successful action
  void updateStatus({
    required bool isClockedIn,
    String? clockRefGuid,
    String? clockTime,
    String? status,
  }) {
    _isClockedIn = isClockedIn;
    _clockRefGuid = clockRefGuid;
    _clockInTime = clockTime;
    if (status != null) _clockStatus = status;

    if (!isClockedIn) {
      _clockRefGuid = null;
      _clockStatus = "You Haven't Clocked In Yet";
      // Clear selections on clock out
      _selectedJobType = '';
      _selectedClient = null;
      _selectedProject = null;
      _selectedContract = null;
      _activityName = '';
    }

    notifyListeners();
  }

  Future<void> _startMonitoring() async {
    // Note: latitude/longitude are needed for monitoring.
    // In HomePage, they are stored locally. We might need to pass them or
    // let ClockProvider handle its own monitoring startup when location is available.
  }

  Future<void> stopMonitoring() async {
    _autoClockOutService?.stopMonitoring();
    try {
      await BackgroundGeofenceService.stopTracking();
    } catch (e) {
      debugPrint('⚠️ Error stopping background tracking: $e');
    }
  }

  Future<void> _handleAutoClockOut(double distance) async {
    if (!_isClockedIn || _isAutoClockingOut) return;

    _isAutoClockingOut = true;
    notifyListeners();

    try {
      // Notify UI to show dialog
      _autoClockOutEventController.add(distance);

      // The actual clock-out call should still happen,
      // but ClockProvider can handle the status update.
      // HomePage will actually trigger _performClockOut which will update this provider.
    } finally {
      _isAutoClockingOut = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _autoClockOutService?.dispose();
    _autoClockOutEventController.close();
    super.dispose();
  }
}
