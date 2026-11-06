import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const primary = Color(0xFF0F5C54);
  static const primarySoft = Color(0xFFDDF0EC);
  static const onPrimarySoft = Color(0xFF0A423C);
  static const ink = Color(0xFF12302C);
  static const inkMuted = Color(0xFF46605B);
  static const ground = Color(0xFFF3F6F5);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFD5DFDC);
  static const fieldBorder = Color(0xFF8AA19C);
  static const danger = Color(0xFFB42318);
  static const dangerSoft = Color(0xFFFDECEA);
  static const onDangerSoft = Color(0xFF8F1C13);
  static const warningSoft = Color(0xFFFFF3E3);
  static const onWarningSoft = Color(0xFF8A4B00);
  static const refundSoft = Color(0xFFE6E1F5);
  static const onRefundSoft = Color(0xFF3F2A8C);
  static const scrim = Color(0x4712302C);
  static const breakfast = Color(0xFFC77700);
  static const lunch = Color(0xFF0E8A7D);
  static const dinner = Color(0xFF3F2A8C);
  static const emptyLine = Color(0xFFE1E8E6);
  static const closed = Color(0xFFECEFEE);
  static const imagePlaceholder = Color(0xFFDCE7E4);
  static const todayCell = Color(0xFFEAF4F1);
  static const dayCell = Color(0xFFF7F9F8);
  static const pastDay = Color(0xFF5C736E);
  static const unselected = Color(0xFFB7C6C2);
  static const star = Color(0xFFD98A00);
}

/// Large text and tall controls throughout: most users are older staff.
ThemeData appTheme({String? fontFamily}) {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: AppColors.ground,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      onPrimary: AppColors.surface,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.danger,
    ),
  );

  OutlineInputBorder border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: 2),
      );

  return base.copyWith(
    textTheme: base.textTheme
        .copyWith(
          headlineMedium: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.25),
          titleLarge: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          titleMedium: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          bodyLarge: const TextStyle(fontSize: 18, height: 1.5),
          bodyMedium: const TextStyle(fontSize: 17, height: 1.5),
          labelLarge: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        )
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink, fontFamily: fontFamily),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, fontFamily: fontFamily),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFamily: fontFamily),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: AppColors.ink,
        textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFamily: fontFamily),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      labelStyle: const TextStyle(fontSize: 18, color: AppColors.inkMuted),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      enabledBorder: border(AppColors.fieldBorder),
      focusedBorder: border(AppColors.primary),
      errorBorder: border(AppColors.danger),
      focusedErrorBorder: border(AppColors.danger),
    ),
  );
}
