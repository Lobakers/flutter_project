import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class DeviceInfoHelper {
  static String deviceDescription = '';
  static String deviceId = '';
  static String deviceIp = '';

  /// Initialize device info - call this once at app start
  static Future<void> init() async {
    await _getDeviceInfo();
    await _getDeviceIp();
  }

  static Future<void> _getDeviceInfo() async {
    try {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceDescription = androidInfo.model;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceDescription = iosInfo.model;
        deviceId = iosInfo.identifierForVendor ?? '';
      }
    } catch (e) {
      debugPrint('Error getting device info: $e');
      deviceDescription = 'Unknown Device';
      deviceId = 'unknown';
    }
  }

  static Future<void> _getDeviceIp() async {
    try {
      final interfaces = await NetworkInterface.list();

      for (var interface in interfaces) {
        // Look for WiFi interface
        if (interface.name == 'wlan0' || interface.name == 'en0') {
          for (var address in interface.addresses) {
            if (address.type == InternetAddressType.IPv4) {
              deviceIp = address.address;
              return;
            }
          }
        }
      }

      // Fallback: get any IPv4 address
      for (var interface in interfaces) {
        for (var address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4 && !address.isLoopback) {
            deviceIp = address.address;
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting IP: $e');
      deviceIp = '0.0.0.0';
    }
  }
}
