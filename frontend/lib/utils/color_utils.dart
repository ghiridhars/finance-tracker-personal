import 'package:flutter/material.dart';

Color parseHexColor(String hex, {Color fallback = Colors.grey}) {
  try {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  } catch (e) {
    return fallback;
  }
}
