import 'package:flutter/material.dart';

import '../core/theme.dart';

/// A bottom sheet that closes only through its own buttons or the back key, so a stray
/// touch cannot dismiss a confirmation.
Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder, Color background = AppColors.surface}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    isDismissible: false,
    backgroundColor: background,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
        child: builder(context),
      ),
    ),
  );
}

/// A whole-row on/off choice, with the switch as a visible cue.
class OptionSwitch extends StatelessWidget {
  const OptionSwitch({super.key, required this.label, required this.value, required this.onChanged, this.color = AppColors.primary, this.soft = AppColors.primarySoft});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color color;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value ? soft : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: value ? color : AppColors.unselected, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500))),
                const SizedBox(width: 10),
                Switch(value: value, onChanged: onChanged, activeTrackColor: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A short block of facts inside a sheet, one label and bold value per line.
class FactBox extends StatelessWidget {
  const FactBox({super.key, required this.lines});

  final List<(String, String)> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppColors.ground, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value) in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '$label '),
                  TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
                style: const TextStyle(fontSize: 18, color: AppColors.ink),
              ),
            ),
        ],
      ),
    );
  }
}

/// Placeholder and failure views shared by the data pages.
class LoadingOrError extends StatelessWidget {
  const LoadingOrError({super.key, this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (error == null) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'تعذّر عرض البيانات. تأكد من الإنترنت ثم حاول مرة أخرى.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('حاول مرة أخرى')),
          ],
        ),
      ),
    );
  }
}
