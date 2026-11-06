import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import '../../shared/week_charts.dart';
import 'manager_models.dart';
import 'manager_providers.dart';

class ReportsTab extends ConsumerWidget {
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(managerWeekProvider);
    final value = week.valueOrNull;
    if (value == null) {
      return LoadingOrError(error: week.error, onRetry: () => ref.invalidate(managerWeekProvider));
    }
    final summary = value.summary;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(managerRatingsProvider);
        ref.invalidate(managerWeekProvider);
        await ref.read(managerWeekProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Text('تقارير المطعم', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 28)),
          const SizedBox(height: 12),
          WeekChart(summary: summary),
          if (value.topMeals.isNotEmpty || summary.cancelled > 0) ...[
            const SizedBox(height: 12),
            BarsCard(
              title: 'نتيجة حجوزات هذا الأسبوع',
              rows: [
                ('مستلمة', summary.collected),
                ('لم تُستلم', summary.notCollected),
                ('بانتظار الاستلام', summary.waiting),
                ('ملغاة', summary.cancelled),
              ],
            ),
          ],
          if (value.topMeals.isNotEmpty) ...[
            const SizedBox(height: 12),
            BarsCard(title: 'أكثر الوجبات طلباً هذا الأسبوع', rows: value.topMeals),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Expanded(child: Text('المستحق للمطعم هذا الأسبوع', style: TextStyle(fontSize: 18))),
                const SizedBox(width: 8),
                Text(dinars(value.due), key: const Key('week-due'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _RatingsSection(),
        ],
      ),
    );
  }
}

/// This week's ratings: the averages first, then what employees wrote.
class _RatingsSection extends ConsumerWidget {
  const _RatingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratings = ref.watch(managerRatingsProvider);
    final value = ratings.valueOrNull;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('تقييمات الموظفين هذا الأسبوع', style: textTheme.titleLarge),
        const SizedBox(height: 10),
        if (value == null)
          ratings.hasError
              ? OutlinedButton(onPressed: () => ref.invalidate(managerRatingsProvider), child: const Text('تعذّر عرض التقييمات. حاول مرة أخرى'))
              : const Center(child: CircularProgressIndicator())
        else if (value.count == 0)
          const Text('لا توجد تقييمات هذا الأسبوع بعد.', key: Key('ratings-empty'), style: TextStyle(fontSize: 18, color: AppColors.inkMuted))
        else ...[
          Row(
            children: [
              Expanded(child: _Tile(label: 'متوسط التقييم', value: '${averageText(value.average)} من 5', valueKey: 'ratings-average')),
              const SizedBox(width: 10),
              Expanded(child: _Tile(label: 'عدد التقييمات', value: '${value.count}', valueKey: 'ratings-count')),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('حسب الوجبة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                for (final meal in value.meals)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(meal.name, style: TextStyle(fontSize: 18, color: meal.average < 3 ? AppColors.danger : AppColors.ink)),
                        ),
                        const Icon(Icons.star_rounded, color: AppColors.star, size: 22),
                        Text(
                          ' ${averageText(meal.average)} · ${meal.count} تقييم',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: meal.average < 3 ? AppColors.danger : AppColors.ink),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (value.latest.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('آراء الموظفين', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final rating in value.latest) ...[
              _RatingCard(rating: rating),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.valueKey});

  final String label;
  final String value;
  final String valueKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.ground, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 16, color: AppColors.inkMuted)),
          Text(value, key: Key(valueKey), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _RatingCard extends StatelessWidget {
  const _RatingCard({required this.rating});

  final MealRating rating;

  @override
  Widget build(BuildContext context) {
    final low = rating.isLow;
    final ink = low ? AppColors.onDangerSoft : AppColors.ink;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: low ? AppColors.dangerSoft : AppColors.surface,
        border: Border.all(color: low ? AppColors.danger : AppColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${rating.stars} من 5 · ${rating.employeeName}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: ink)),
          if ((rating.comment ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('"${rating.comment}"', style: TextStyle(fontSize: 17, color: ink)),
          ],
          if (rating.tags.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(rating.tags.map((tag) => tag.label).join('، '), style: TextStyle(fontSize: 16, color: ink)),
          ],
          const SizedBox(height: 4),
          Text(
            '${rating.mealName} · ${rating.period.label} ${weekdayName(rating.serviceDate)}',
            style: TextStyle(fontSize: 15, color: low ? AppColors.onDangerSoft : AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}
