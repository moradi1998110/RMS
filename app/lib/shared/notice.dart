import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

enum NoticeKind { done, refund, person, warning }

const noticeDuration = Duration(milliseconds: 3500);

/// The app's event message: a centred square with an icon and a vibration. It closes
/// by itself or when tapped.
Future<void> showNotice(BuildContext context, {required NoticeKind kind, required String title, String? text}) {
  if (kind == NoticeKind.warning) {
    HapticFeedback.heavyImpact();
  } else {
    HapticFeedback.mediumImpact();
  }
  final animate = !MediaQuery.of(context).disableAnimations;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'إغلاق',
    barrierColor: AppColors.scrim,
    transitionDuration: animate ? const Duration(milliseconds: 220) : Duration.zero,
    pageBuilder: (_, __, ___) => _NoticeSquare(kind: kind, title: title, text: text),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.86, end: 1).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    ),
  );
}

class _NoticeSquare extends StatefulWidget {
  const _NoticeSquare({required this.kind, required this.title, this.text});

  final NoticeKind kind;
  final String title;
  final String? text;

  @override
  State<_NoticeSquare> createState() => _NoticeSquareState();
}

class _NoticeSquareState extends State<_NoticeSquare> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(noticeDuration, _close);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _close() {
    _timer?.cancel();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon) = switch (widget.kind) {
      NoticeKind.done => (AppColors.primarySoft, AppColors.onPrimarySoft, Icons.check_rounded),
      NoticeKind.refund => (AppColors.refundSoft, AppColors.onRefundSoft, Icons.undo_rounded),
      NoticeKind.person => (AppColors.warningSoft, AppColors.onWarningSoft, Icons.how_to_reg_rounded),
      NoticeKind.warning => (AppColors.warningSoft, AppColors.onWarningSoft, Icons.warning_amber_rounded),
    };
    return Center(
      child: Semantics(
        liveRegion: true,
        child: Material(
          color: AppColors.surface,
          elevation: 12,
          borderRadius: BorderRadius.circular(32),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _close,
            // A minimum rather than a fixed height, so enlarged system text still fits.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 272, minWidth: 272, maxWidth: 272),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
                      child: Icon(icon, size: 50, color: foreground),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700, height: 1.25, color: AppColors.ink),
                    ),
                    if (widget.text != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.text!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18, height: 1.35, color: AppColors.ink),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
