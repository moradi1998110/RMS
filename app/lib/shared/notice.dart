import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

enum NoticeKind { done, refund, person, warning }

const noticeDuration = Duration(seconds: 2);

/// The app's event message: a centred square whose coloured badge springs in and draws
/// its mark, with a vibration as it appears. It closes by itself or when tapped.
Future<void> showNotice(BuildContext context, {required NoticeKind kind, required String title, String? text}) {
  // Every kind vibrates the moment it appears, so the phone confirms it even unseen.
  HapticFeedback.vibrate();
  final animate = !MediaQuery.of(context).disableAnimations;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'إغلاق',
    barrierColor: AppColors.scrim,
    transitionDuration: animate ? const Duration(milliseconds: 220) : Duration.zero,
    pageBuilder: (_, __, ___) => _NoticeSquare(kind: kind, title: title, text: text, animate: animate),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.86, end: 1).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
        child: child,
      ),
    ),
  );
}

/// Strong colours with a white mark, each kind its own: green done, purple money back,
/// amber colleague, red problem.
(Color, IconData?) _look(NoticeKind kind) => switch (kind) {
      NoticeKind.done => (AppColors.primary, null),
      NoticeKind.refund => (AppColors.onRefundSoft, Icons.undo_rounded),
      NoticeKind.person => (AppColors.onWarningSoft, Icons.how_to_reg_rounded),
      NoticeKind.warning => (AppColors.danger, Icons.priority_high_rounded),
    };

class _NoticeSquare extends StatefulWidget {
  const _NoticeSquare({required this.kind, required this.title, this.text, required this.animate});

  final NoticeKind kind;
  final String title;
  final String? text;
  final bool animate;

  @override
  State<_NoticeSquare> createState() => _NoticeSquareState();
}

class _NoticeSquareState extends State<_NoticeSquare> with SingleTickerProviderStateMixin {
  Timer? _timer;

  // One short timeline for the badge: it springs in, its mark appears, a ring fades out.
  late final _motion = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));

  @override
  void initState() {
    super.initState();
    _timer = Timer(noticeDuration, _close);
    if (widget.animate) {
      _motion.forward();
    } else {
      _motion.value = 1;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _motion.dispose();
    super.dispose();
  }

  void _close() {
    _timer?.cancel();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
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
                    _Badge(kind: widget.kind, motion: _motion),
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

class _Badge extends StatelessWidget {
  const _Badge({required this.kind, required this.motion});

  final NoticeKind kind;
  final Animation<double> motion;

  static const _size = 100.0;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _look(kind);
    // Stages of the one timeline, as fractions of it.
    final disc = CurvedAnimation(parent: motion, curve: const Interval(0, 0.55, curve: Curves.elasticOut));
    final mark = CurvedAnimation(parent: motion, curve: const Interval(0.35, 0.8, curve: Curves.easeOutCubic));
    final ring = CurvedAnimation(parent: motion, curve: const Interval(0.2, 1, curve: Curves.easeOut));
    return SizedBox.square(
      key: Key('notice-badge-${kind.name}'),
      dimension: _size,
      child: AnimatedBuilder(
        animation: motion,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            // The ring spreads and fades once, like a ripple.
            if (ring.value < 1)
              Transform.scale(
                scale: 0.8 + 0.5 * ring.value,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.5 * (1 - ring.value)), width: 6),
                  ),
                ),
              ),
            Transform.scale(
              scale: disc.value,
              child: Container(width: 72, height: 72, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            ),
            if (icon == null)
              // The tick is drawn stroke by stroke rather than appearing whole.
              CustomPaint(size: const Size.square(72), painter: _TickPainter(mark.value))
            else
              Opacity(
                opacity: mark.value,
                child: Transform.rotate(
                  angle: kind == NoticeKind.refund ? -math.pi / 2 * (1 - mark.value) : 0,
                  child: Transform.scale(
                    scale: 0.4 + 0.6 * mark.value,
                    child: Transform.translate(
                      // A problem shakes once, so it reads as "stop" rather than "done".
                      offset: Offset(kind == NoticeKind.warning ? math.sin(mark.value * math.pi * 4) * 4 * (1 - mark.value) : 0, 0),
                      child: Icon(icon, size: 42, color: AppColors.surface),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final path = Path()
      ..moveTo(size.width * 0.27, size.height * 0.53)
      ..lineTo(size.width * 0.44, size.height * 0.69)
      ..lineTo(size.width * 0.74, size.height * 0.36);
    final paint = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.progress != progress;
}
