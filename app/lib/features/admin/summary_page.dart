import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import '../auth/auth_models.dart';
import 'admin_models.dart';
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
          _WeekChart(summary: weekValue),
          if (served + weekValue.cancelled > 0) ...[
            const SizedBox(height: 12),
            _BarsCard(
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
            _BarsCard(
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

const _lineColors = [AppColors.breakfast, AppColors.lunch, AppColors.dinner];
const _lineLabels = ['الفطور', 'الغداء', 'العشاء'];

class _WeekChart extends StatefulWidget {
  const _WeekChart({required this.summary});

  final WeekSummary summary;

  @override
  State<_WeekChart> createState() => _WeekChartState();
}

class _WeekChartState extends State<_WeekChart> {
  bool _asTable = false;
  int? _picked;

  @override
  Widget build(BuildContext context) {
    final days = widget.summary.days;
    final highest = days.fold<int>(0, (top, day) => day.total > top ? day.total : top);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('وجبات هذا الأسبوع', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
              if (highest > 0)
                TextButton(
                  key: const Key('chart-toggle'),
                  onPressed: () => setState(() => _asTable = !_asTable),
                  style: TextButton.styleFrom(backgroundColor: AppColors.ground, textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  child: Text(_asTable ? 'عرض كرسم بياني' : 'عرض كجدول'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (highest == 0)
            const Text('لا توجد حجوزات لهذا الأسبوع بعد.', style: TextStyle(fontSize: 17, color: AppColors.inkMuted))
          else ...[
            Wrap(
              spacing: 14,
              children: [
                for (var line = 0; line < 3; line++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 12, height: 12, decoration: BoxDecoration(color: _lineColors[line], borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 6),
                      Text(_lineLabels[line], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_asTable) _table(days) else _chart(days, highest),
          ],
        ],
      ),
    );
  }

  Widget _chart(List<WeekDayCount> days, int highest) {
    const plotHeight = 128.0;
    final picked = _picked == null ? null : days[_picked!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 140,
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.fieldBorder))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < days.length; index++)
                Expanded(
                  child: Semantics(
                    button: true,
                    label: '${weekdayName(days[index].day)}: ${days[index].total} وجبة',
                    excludeSemantics: true,
                    child: GestureDetector(
                      key: Key('chart-day-$index'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _picked = index),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: _picked == index ? AppColors.closed : Colors.transparent,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Evening on top, morning at the base, in the order of the legend read upward.
                            for (var line = 2; line >= 0; line--)
                              if (days[index].lines[line] > 0)
                                Container(
                                  height: days[index].lines[line] / highest * plotHeight,
                                  margin: const EdgeInsets.only(top: 2),
                                  color: _lineColors[line],
                                ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final head in calendarHeads)
              Expanded(
                child: Text(head, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: const TextStyle(fontSize: 14, color: AppColors.inkMuted)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          picked == null
              ? 'اضغط على أي يوم لعرض أرقامه.'
              : '${weekdayName(picked.day)}: ${picked.total} وجبة (فطور ${picked.lines[0]}، غداء ${picked.lines[1]}، عشاء ${picked.lines[2]})',
          key: const Key('chart-caption'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _table(List<WeekDayCount> days) {
    TableRow row(List<String> cells, {bool heading = false}) => TableRow(
          decoration: heading ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
          children: [
            for (var index = 0; index < cells.length; index++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Text(
                  cells[index],
                  textAlign: index == 0 ? TextAlign.start : TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: heading ? FontWeight.w700 : FontWeight.w400),
                ),
              ),
          ],
        );
    return Table(
      columnWidths: const {0: FlexColumnWidth(1.6)},
      children: [
        row(const ['اليوم', 'فطور', 'غداء', 'عشاء'], heading: true),
        for (final day in days) row([weekdayName(day.day), '${day.lines[0]}', '${day.lines[1]}', '${day.lines[2]}']),
      ],
    );
  }
}

class _BarsCard extends StatelessWidget {
  const _BarsCard({required this.title, required this.rows});

  final String title;
  final List<(String, int)> rows;

  @override
  Widget build(BuildContext context) {
    final highest = rows.fold<int>(1, (top, row) => row.$2 > top ? row.$2 : top);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final (label, value) in rows) ...[
            Row(
              children: [
                Expanded(child: Text(label, style: const TextStyle(fontSize: 17))),
                const SizedBox(width: 8),
                Text('$value', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value / highest,
                minHeight: 12,
                backgroundColor: AppColors.closed,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
