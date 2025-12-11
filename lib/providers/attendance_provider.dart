import 'package:flutter/material.dart';

/// Stores attendance profile configuration
/// Controls which buttons and fields are visible
class AttendanceProvider with ChangeNotifier {
  // Button visibility
  bool officeVisible = false;
  bool siteVisible = false;
  bool homeVisible = false;
  bool othersVisible = false;

  // Office field visibility
  bool officeClientList = false;
  bool officeProjectList = false;
  bool officeContractList = false;
  bool officeActivityList = false;
  bool officeGeofenceFilter = false;

  // Site field visibility
  bool siteClientList = false;
  bool siteProjectList = false;
  bool siteContractList = false;
  bool siteActivityList = false;
  bool siteGeofenceFilter = false;

  // Home field visibility
  bool homeClientList = false;
  bool homeProjectList = false;
  bool homeContractList = false;
  bool homeActivityList = false;
  bool homeGeofenceFilter = false;

  // Others field visibility
  bool othersClientList = false;
  bool othersProjectList = false;
  bool othersContractList = false;
  bool othersActivityList = false;
  bool othersGeofenceFilter = false;

  // ✨ Auto clock-out ranges (in meters)
  double? officeAutoClockOutRange;
  double? siteAutoClockOutRange;
  double? homeAutoClockOutRange;
  double? othersAutoClockOutRange;
  void setFromApiResponse(Map<String, dynamic> data) {
    final property = data['property'];

    // Button visibility
    officeVisible = property['office']['value'] ?? false;
    siteVisible = property['site']['value'] ?? false;
    homeVisible = property['home']['value'] ?? false;
    othersVisible = property['others']['value'] ?? false;

    // ✨ Parsing Auto Clock-out Ranges
    _parseAutoClockoutRanges(property);

    // Office fields
    officeClientList = property['office']['client_list'] ?? false;
    officeProjectList = property['office']['project_selection'] ?? false;
    officeContractList = property['office']['contract_selection'] ?? false;
    officeActivityList = property['office']['activity_list'] ?? false;
    officeGeofenceFilter = property['office']['geofence_filter'] ?? false;

    // Site fields
    siteClientList = property['site']['client_list'] ?? false;
    siteProjectList = property['site']['project_selection'] ?? false;
    siteContractList = property['site']['contract_selection'] ?? false;
    siteActivityList = property['site']['activity_list'] ?? false;
    siteGeofenceFilter = property['site']['geofence_filter'] ?? false;

    // Home fields
    homeClientList = property['home']['client_list'] ?? false;
    homeProjectList = property['home']['project_selection'] ?? false;
    homeContractList = property['home']['contract_selection'] ?? false;
    homeActivityList = property['home']['activity_list'] ?? false;
    homeGeofenceFilter = property['home']['geofence_filter'] ?? false;

    // Others fields
    othersClientList = property['others']['client_list'] ?? false;
    othersProjectList = property['others']['project_selection'] ?? false;
    othersContractList = property['others']['contract_selection'] ?? false;
    othersActivityList = property['others']['activity_list'] ?? false;
    othersGeofenceFilter = property['others']['geofence_filter'] ?? false;

    notifyListeners();
  }

  /// Get field visibility for a specific job type
  Map<String, bool> getFieldsForJobType(String jobType) {
    switch (jobType.toLowerCase()) {
      case 'office':
        return <String, bool>{
          'client': officeClientList,
          'project': officeProjectList,
          'contract': officeContractList,
          'activity': officeActivityList,
          'geofence_filter': officeGeofenceFilter,
        };
      case 'site':
        return <String, bool>{
          'client': siteClientList,
          'project': siteProjectList,
          'contract': siteContractList,
          'activity': siteActivityList,
          'geofence_filter': siteGeofenceFilter,
        };
      case 'home':
        return <String, bool>{
          'client': homeClientList,
          'project': homeProjectList,
          'contract': homeContractList,
          'activity': homeActivityList,
          'geofence_filter': homeGeofenceFilter,
        };
      case 'others':
        return <String, bool>{
          'client': othersClientList,
          'project': othersProjectList,
          'contract': othersContractList,
          'activity': othersActivityList,
          'geofence_filter': othersGeofenceFilter,
        };
      default:
        return <String, bool>{
          'client': false,
          'project': false,
          'contract': false,
          'activity': false,
          'geofence_filter': false,
        };
    }
  }

  /// Get list of visible job type buttons
  List<String> getVisibleJobTypes() {
    List<String> visible = [];
    if (officeVisible) visible.add('Office');
    if (siteVisible) visible.add('Site');
    if (homeVisible) visible.add('Home');
    if (othersVisible) visible.add('Others');
    return visible;
  }

  void clear() {
    officeVisible = false;
    siteVisible = false;
    homeVisible = false;
    othersVisible = false;

    officeClientList = false;
    officeProjectList = false;
    officeContractList = false;
    officeActivityList = false;
    officeGeofenceFilter = false;

    siteClientList = false;
    siteProjectList = false;
    siteContractList = false;
    siteActivityList = false;
    siteGeofenceFilter = false;

    homeClientList = false;
    homeProjectList = false;
    homeContractList = false;
    homeActivityList = false;
    homeGeofenceFilter = false;

    othersClientList = false;
    othersProjectList = false;
    othersContractList = false;
    othersActivityList = false;
    othersGeofenceFilter = false;

    // Reset ranges
    officeAutoClockOutRange = null;
    siteAutoClockOutRange = null;
    homeAutoClockOutRange = null;
    othersAutoClockOutRange = null;

    notifyListeners();
  }

  /// NEW: Parse auto clock-out ranges from property
  void _parseAutoClockoutRanges(Map<String, dynamic> property) {
    if (property['office'] != null &&
        property['office']['autoclockout_filter'] != null &&
        property['office']['autoclockout_filter']['value'] == true) {
      officeAutoClockOutRange =
          (property['office']['autoclockout_filter']['range'] as num?)
              ?.toDouble();
    }

    if (property['site'] != null &&
        property['site']['autoclockout_filter'] != null &&
        property['site']['autoclockout_filter']['value'] == true) {
      siteAutoClockOutRange =
          (property['site']['autoclockout_filter']['range'] as num?)
              ?.toDouble();
    }

    if (property['home'] != null &&
        property['home']['autoclockout_filter'] != null &&
        property['home']['autoclockout_filter']['value'] == true) {
      homeAutoClockOutRange =
          (property['home']['autoclockout_filter']['range'] as num?)
              ?.toDouble();
    }

    if (property['others'] != null &&
        property['others']['autoclockout_filter'] != null &&
        property['others']['autoclockout_filter']['value'] == true) {
      othersAutoClockOutRange =
          (property['others']['autoclockout_filter']['range'] as num?)
              ?.toDouble();
    }
  }

  /// NEW: Get configured radius for job type
  double? getRadiusForJobType(String jobType) {
    switch (jobType.toLowerCase()) {
      case 'office':
        return officeAutoClockOutRange;
      case 'site':
        return siteAutoClockOutRange;
      case 'home':
        return homeAutoClockOutRange;
      case 'others':
        return othersAutoClockOutRange;
      default:
        return null;
    }
  }
}
