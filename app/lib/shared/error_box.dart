import 'package:flutter/material.dart';

import '../core/theme.dart';

class ErrorBox extends StatelessWidget {
  const ErrorBox(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(12)),
        child: Text(
          message,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onDangerSoft),
        ),
      ),
    );
  }
}
