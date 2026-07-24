import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens lifted from the OjaAI prototype.
abstract final class OjaColors {
  static const cream = Color(0xFFF7F1E3);
  static const paper = Color(0xFFEDE7D6);
  static const navy = Color(0xFF1C2B4A);
  static const gold = Color(0xFFD9A441);
  static const green = Color(0xFF2F7D5E);
  static const red = Color(0xFFB5442E);
  static const ink = Color(0xFF3A3A3A);

  static const greenTint = Color(0x1F2F7D5E);
  static const redTint = Color(0x1FB5442E);
  static const navyFaint = Color(0x1F1C2B4A);
  static const marginRule = Color(0x8CB5442E);
}

abstract final class OjaText {
  /// Handwritten logo.
  static TextStyle logo({double size = 30, Color color = OjaColors.navy}) =>
      GoogleFonts.caveat(
          fontSize: size, fontWeight: FontWeight.w600, color: color);

  /// Big money numbers and headings.
  static TextStyle number({
    double size = 30,
    Color color = OjaColors.navy,
    FontWeight weight = FontWeight.w800,
  }) =>
      GoogleFonts.manrope(fontSize: size, fontWeight: weight, color: color);

  /// Body copy.
  static TextStyle body({
    double size = 18,
    Color color = OjaColors.ink,
    FontWeight weight = FontWeight.w400,
  }) =>
      GoogleFonts.karla(fontSize: size, fontWeight: weight, color: color);
}

ThemeData buildOjaTheme() {
  final base = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: OjaColors.cream,
    colorScheme: ColorScheme.fromSeed(
      seedColor: OjaColors.navy,
      primary: OjaColors.navy,
      secondary: OjaColors.gold,
      error: OjaColors.red,
      surface: OjaColors.cream,
    ),
  );
  return base.copyWith(
    textTheme: GoogleFonts.karlaTextTheme(base.textTheme),
  );
}

String formatNaira(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${amount < 0 ? '-' : ''}₦$buffer';
}
