import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import '../../shared/week_charts.dart';
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
        ],
      ),
    );
  }
}
