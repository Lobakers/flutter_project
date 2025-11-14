import 'package:flutter/material.dart';

class BeeColor {
  static const Color primary = Color(0xFF242886);
  static const Color secondary = Color(0xFF905A92);
  static const Color tertiary = Color(0xFFEE8B60);
  static const Color buttonColor = Color(0xFF4B39EF);
  static const Color background = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color fillIcon = Color(0x4C4B39EF);
  static const Color grey = Color.fromARGB(255, 159, 159, 159);
  // static const Color background = Color.fromARGB(245, 245, 245, 245);
  static const Color font = Color(0xFF3B4B68);
  static const Color error = Color(0xFFE21C3D);
  // ignore: deprecated_member_use
  static Color shadow = const Color(0xFF1546A0).withOpacity(0.5);

  static const LinearGradient gradient = LinearGradient(
    // begin: Alignment(0, -1),
    // end: Alignment(0, 0),
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [BeeColor.primary, BeeColor.secondary, BeeColor.tertiary],
  );
}
