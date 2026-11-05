import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import '../../shared/week_charts.dart';
import '../auth/auth_models.dart';
import 'admin_providers.dart';
import 'user_sheets.dart';

class SummaryPage extends ConsumerWidget {
  const SummaryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);
    final places = ref.watch(placesProvider);
    final week = ref.watch(weekSummaryProvider);
    final usersValue = users.valueOrNull;
    final placesValue = places.valueOrNull;
    final weekValue = week.valueOrNull;
    if (usersValue == null || placesValue == null || weekValue == null) {
      return LoadingOrError(error: users.error ?? places.error ?? week.error, onRetry: () => refreshAdminData(ref));
    }

    final employees = usersValue.where((user) => user.role == UserRole.employee).toList();
    final managers = usersValue.where((user) => user.role == UserRole.manager).length;
    final balances = employees.fold<int>(0, (sum, user) => sum + user.available);
    final served = weekValue.days.fold<int>(0, (sum, day) => sum + day.total);

    return RefreshIndicator(
      onRefresh: () async {
        refreshAdminData(ref);
        await ref.read(usersProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Text('الملخص', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 28)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _StatTile(label: 'الموظفون', value: '${employees.length}')),
              const SizedBox(width: 10),
              Expanded(child: _StatTile(label: 'المطاعم', value: '${placesValue.length}')),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _StatTile(label: 'مدراء المطاعم', value: '$managers')),
              const SizedBox(width: 10),
              Expanded(child: _StatTile(label: 'مجموع الأرصدة', value: money(balances))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => addUser(context),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  child: const Text('إضافة مستخدم'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => ref.read(adminTabProvider.notifier).state = 3,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(60)),
                  child: const Text('شحن رصيد'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          WeekChart(summary: weekValue),
          if (served + weekValue.cancelled > 0) ...[
            const SizedBox(height: 12),
            BarsCard(
              title: 'نتيجة حجوزات هذا الأسبوع',
              rows: [
                ('مستلمة', weekValue.collected),
                ('لم تُستلم', weekValue.notCollected),
                ('بانتظار الاستلام', weekValue.waiting),
                ('ملغاة', weekValue.cancelled),
              ],
            ),
          ],
          if (served > 0) ...[
            const SizedBox(height: 12),
            BarsCard(
              title: 'وجبات هذا الأسبوع حسب المطعم',
              rows: [
                for (final place in placesValue)
                  if (weekValue.byRestaurant.containsKey(place.id)) (place.name, weekValue.byRestaurant[place.id]!),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 17, color: AppColors.inkMuted)),
          Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

