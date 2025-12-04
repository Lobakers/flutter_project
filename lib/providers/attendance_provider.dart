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
  bool officeGeofenceFilter = false; // ✨ NEW

  // Site field visibility
  bool siteClientList = false;
  bool siteProjectList = false;
  bool siteContractList = false;
  bool siteActivityList = false;
  bool siteGeofenceFilter = false; // ✨ NEW

  // Home field visibility
  bool homeClientList = false;
  bool homeProjectList = false;
  bool homeContractList = false;
  bool homeActivityList = false;
  bool homeGeofenceFilter = false; // ✨ NEW

  // Others field visibility
  bool othersClientList = false;
  bool othersProjectList = false;
  bool othersContractList = false;
  bool othersActivityList = false;
  bool othersGeofenceFilter = false; // ✨ NEW

  /// Set data from API response
  void setFromApiResponse(Map<String, dynamic> data) {
    final property = data['property'];

    // Button visibility
    officeVisible = property['office']['value'] ?? false;
    siteVisible = property['site']['value'] ?? false;
    homeVisible = property['home']['value'] ?? false;
    othersVisible = property['others']['value'] ?? false;

    // Office fields
    officeClientList = property['office']['client_list'] ?? false;
    officeProjectList = property['office']['project_selection'] ?? false;
    officeContractList = property['office']['contract_selection'] ?? false;
    officeActivityList = property['office']['activity_list'] ?? false;
    officeGeofenceFilter =
        property['office']['geofence_filter'] ?? false; // ✨ NEW

    // Site fields
    siteClientList = property['site']['client_list'] ?? false;
    siteProjectList = property['site']['project_selection'] ?? false;
    siteContractList = property['site']['contract_selection'] ?? false;
    siteActivityList = property['site']['activity_list'] ?? false;
    siteGeofenceFilter = property['site']['geofence_filter'] ?? false; // ✨ NEW

    // Home fields
    homeClientList = property['home']['client_list'] ?? false;
    homeProjectList = property['home']['project_selection'] ?? false;
    homeContractList = property['home']['contract_selection'] ?? false;
    homeActivityList = property['home']['activity_list'] ?? false;
    homeGeofenceFilter = property['home']['geofence_filter'] ?? false; // ✨ NEW

    // Others fields
    othersClientList = property['others']['client_list'] ?? false;
    othersProjectList = property['others']['project_selection'] ?? false;
    othersContractList = property['others']['contract_selection'] ?? false;
    othersActivityList = property['others']['activity_list'] ?? false;
    othersGeofenceFilter =
        property['others']['geofence_filter'] ?? false; // ✨ NEW

    notifyListeners();
  }

  /// Get field visibility for a specific job type
  Map<String, bool> getFieldsForJobType(String jobType) {
    switch (jobType.toLowerCase()) {
      case 'office':
        return {
          'client': officeClientList,
          'project': officeProjectList,
          'contract': officeContractList,
          'activity': officeActivityList,
          'geofence_filter': officeGeofenceFilter, // ✨ NEW
        };
      case 'site':
        return {
          'client': siteClientList,
          'project': siteProjectList,
          'contract': siteContractList,
          'activity': siteActivityList,
          'geofence_filter': siteGeofenceFilter, // ✨ NEW
        };
      case 'home':
        return {
          'client': homeClientList,
          'project': homeProjectList,
          'contract': homeContractList,
          'activity': homeActivityList,
          'geofence_filter': homeGeofenceFilter, // ✨ NEW
        };
      case 'others':
        return {
          'client': othersClientList,
          'project': othersProjectList,
          'contract': othersContractList,
          'activity': othersActivityList,
          'geofence_filter': othersGeofenceFilter, // ✨ NEW
        };
      default:
        return {
          'client': false,
          'project': false,
          'contract': false,
          'activity': false,
          'geofence_filter': false, // ✨ NEW
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
    officeGeofenceFilter = false; // ✨ NEW

    siteClientList = false;
    siteProjectList = false;
    siteContractList = false;
    siteActivityList = false;
    siteGeofenceFilter = false; // ✨ NEW

    homeClientList = false;
    homeProjectList = false;
    homeContractList = false;
    homeActivityList = false;
    homeGeofenceFilter = false; // ✨ NEW

    othersClientList = false;
    othersProjectList = false;
    othersContractList = false;
    othersActivityList = false;
    othersGeofenceFilter = false; // ✨ NEW

    notifyListeners();
  }
}
