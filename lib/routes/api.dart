class Api {
  static const String system = 'https://devauth.beesuite.app/api';
  static const String devamscore = 'https://devamscore.beesuite.app/api';

  static const String login = system + '/auth/login';
  static const String user_info = devamscore + '/user-info';
  static const String coordinate =
      devamscore + "/map/search?type=latlng&input=";
  static const String project = devamscore + "/project";
  static const String contract = devamscore + "/contract";
  static const String client_detail = devamscore + "/client/detail";
  static const String attendance_profile =
      devamscore + "/admin/attendance/user";
  static const String clock = devamscore + "/clock/transaction";
  static const String clock_beewhere = devamscore + "/clock/beewhere/latest";
  static const String report = devamscore + "/clock/history-list";
}
