import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import '../../shared/error_box.dart';
import 'employee_models.dart';
import 'employee_providers.dart';
import 'employee_repository.dart';

/// Returns true once the rating is saved.
Future<bool?> showRateSheet(BuildContext context, RatableMeal meal, {int stars = 0}) {
  return showAppSheet<bool>(context, builder: (_) => RateSheet(meal: meal, stars: stars));
}

/// Five large stars, so the choice needs no reading.
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.stars, required this.onPick, this.size = 48, this.keyPrefix = 'star'});

  final int stars;
  final ValueChanged<int> onPick;
  final double size;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      // One star on the right reads as the lowest, as people expect in Arabic.
      textDirection: TextDirection.rtl,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var value = 1; value <= 5; value++)
            Semantics(
              button: true,
              label: '$value من 5',
              child: InkResponse(
                key: Key('$keyPrefix-$value'),
                onTap: () => onPick(value),
                radius: size * 0.6,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    value <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: size,
                    color: value <= stars ? AppColors.star : AppColors.unselected,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RateSheet extends ConsumerStatefulWidget {
  const RateSheet({super.key, required this.meal, this.stars = 0});

  final RatableMeal meal;
  final int stars;

  @override
  ConsumerState<RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends ConsumerState<RateSheet> {
  late int _stars = widget.stars;
  final _tags = <RatingTag>{};
  final _comment = TextEditingController();
  bool _busy = false;
  String? _error;

  // Kept across retries of the same rating; any change starts a new one.
  String _key = const Uuid().v4();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _changed(VoidCallback change) => setState(() {
        change();
        _error = null;
        _key = const Uuid().v4();
      });

  Future<void> _send() async {
    if (_busy) return;
    if (_stars == 0) {
      setState(() => _error = 'اختر عدد النجوم أولاً.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      await ref.read(employeeRepositoryProvider).rateMeal(
            bookingId: widget.meal.bookingId,
            stars: _stars,
            tags: _tags,
            comment: _comment.text,
            key: _key,
          );
      ref.invalidate(ratableMealsProvider);
      navigator.pop(true);
    } on EmployeeFailure catch (failure) {
      ref.invalidate(ratableMealsProvider);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failure.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final meal = widget.meal;
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('قيّم وجبتك', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(meal.mealName, style: textTheme.titleMedium),
          Text('${meal.period.label} ${longDate(meal.serviceDate)}', style: const TextStyle(fontSize: 17, color: AppColors.inkMuted)),
          const SizedBox(height: 12),
          StarRow(stars: _stars, onPick: _busy ? (_) {} : (value) => _changed(() => _stars = value)),
          const SizedBox(height: 4),
          Text(
            _stars == 0 ? 'اختر عدد النجوم' : starsWord(_stars),
            key: const Key('stars-word'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: _stars == 0 ? AppColors.inkMuted : AppColors.ink),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in RatingTag.values)
                FilterChip(
                  key: Key('tag-${tag.code}'),
                  label: Text(tag.label, style: const TextStyle(fontSize: 17)),
                  selected: _tags.contains(tag),
                  showCheckmark: true,
                  selectedColor: AppColors.primarySoft,
                  side: BorderSide(color: _tags.contains(tag) ? AppColors.primary : AppColors.unselected, width: 1.5),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: _busy ? null : (on) => _changed(() => on ? _tags.add(tag) : _tags.remove(tag)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('rate-comment'),
            controller: _comment,
            enabled: !_busy,
            maxLines: 3,
            maxLength: 500,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(hintText: 'اكتب ملاحظتك للمطعم (اختياري)'),
            onChanged: (_) => _changed(() {}),
          ),
          const Text(
            'يرى مدير المطعم اسمك مع التقييم، ولا يمكن تعديله بعد الإرسال.',
            style: TextStyle(fontSize: 15, color: AppColors.inkMuted),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBox(_error!),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('rate-send'),
            onPressed: _busy ? null : _send,
            child: Text(_busy ? 'جارٍ الإرسال...' : 'أرسل التقييم'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56), foregroundColor: AppColors.ink),
            child: const Text('ليس الآن'),
          ),
        ],
      ),
    );
  }
}
