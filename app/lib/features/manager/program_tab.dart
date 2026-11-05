import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import '../../shared/error_box.dart';
import '../../shared/notice.dart';
import '../employee/employee_models.dart';
import 'manager_models.dart';
import 'manager_providers.dart';
import 'manager_repository.dart';

class ProgramTab extends ConsumerStatefulWidget {
  const ProgramTab({super.key});

  @override
  ConsumerState<ProgramTab> createState() => _ProgramTabState();
}

class _ProgramTabState extends ConsumerState<ProgramTab> {
  bool _ramadan = false;
  bool _copying = false;

  Future<void> _add(int dayOfWeek, MealPeriod period) async {
    final saved = await showAppSheet<bool>(
      context,
      builder: (_) => _ScheduleSheet(dayOfWeek: dayOfWeek, period: period, isRamadan: _ramadan),
    );
    if (saved != true || !mounted) return;
    await showNotice(context, kind: NoticeKind.done, title: 'حُفظت الجدولة', text: 'ظهرت الوجبة للموظفين.');
  }

  Future<void> _remove(ScheduleRow schedule, int dayOfWeek) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('إزالة ${schedule.mealName}؟'),
        content: Text(
          'تختفي من يوم ${weekdayNameOf(dayOfWeek)}. الوجبات التي حجزها موظفون تبقى كما هي.',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('لا')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('نعم، أزلها')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(managerRepositoryProvider).removeDay(schedule, dayOfWeek);
      refreshManagerData(ref);
    } on ManagerFailure catch (failure) {
      if (mounted) await showNotice(context, kind: NoticeKind.warning, title: 'لم تتم الإزالة', text: failure.message);
    }
  }

  Future<void> _copy() async {
    if (_copying) return;
    setState(() => _copying = true);
    try {
      final copied = await ref.read(managerRepositoryProvider).copyLastWeek();
      refreshManagerData(ref);
      if (!mounted) return;
      await showNotice(
        context,
        kind: NoticeKind.done,
        title: copied == 0 ? 'لا يوجد ما يُنسخ' : 'نُسخ برنامج الأسبوع الماضي',
        text: copied == 0 ? 'الوجبات المكررة كل أسبوع تبقى تلقائياً.' : mealCount(copied),
      );
    } on ManagerFailure catch (failure) {
      if (mounted) await showNotice(context, kind: NoticeKind.warning, title: 'لم يتم النسخ', text: failure.message);
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final schedules = ref.watch(schedulesProvider);
    final rules = ref.watch(timeRulesProvider);
    final schedulesValue = schedules.valueOrNull;
    final rulesValue = rules.valueOrNull;
    if (schedulesValue == null || rulesValue == null) {
      return LoadingOrError(error: schedules.error ?? rules.error, onRetry: () => refreshManagerData(ref));
    }
    final today = dayOf(DateTime.now());
    final periods = _ramadan ? ramadanPeriods : usualPeriods;
    final textTheme = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () async {
        refreshManagerData(ref);
        await ref.read(schedulesProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Text('البرنامج الأسبوعي', style: textTheme.headlineMedium?.copyWith(fontSize: 28)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: ChoiceBox(key: const Key('season-normal'), label: 'البرنامج العادي', center: true, selected: !_ramadan, onTap: () => setState(() => _ramadan = false))),
              const SizedBox(width: 8),
              Expanded(child: ChoiceBox(key: const Key('season-ramadan'), label: 'برنامج رمضان', center: true, selected: _ramadan, onTap: () => setState(() => _ramadan = true))),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton(key: const Key('copy-week'), onPressed: _copying ? null : _copy, child: const Text('انسخ من الأسبوع الماضي')),
          const SizedBox(height: 12),
          for (final dayOfWeek in weekOrder) ...[
            _DayCard(
              dayOfWeek: dayOfWeek,
              periods: periods,
              schedules: schedulesValue.where((row) => row.isRamadan == _ramadan && row.serves(dayOfWeek, today)).toList(),
              onAdd: (period) => _add(dayOfWeek, period),
              onRemove: (row) => _remove(row, dayOfWeek),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 6),
          Text('أوقات الوجبات', style: textTheme.titleMedium?.copyWith(fontSize: 22)),
          const SizedBox(height: 4),
          Text('تُطبَّق تلقائياً على كل وجبة تجدولها.', style: textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted)),
          const SizedBox(height: 10),
          for (final period in periods)
            for (final rule in rulesValue.where((rule) => rule.period == period)) ...[
              _RuleCard(rule: rule),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.dayOfWeek, required this.periods, required this.schedules, required this.onAdd, required this.onRemove});

  final int dayOfWeek;
  final List<MealPeriod> periods;
  final List<ScheduleRow> schedules;
  final ValueChanged<MealPeriod> onAdd;
  final ValueChanged<ScheduleRow> onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(weekdayNameOf(dayOfWeek), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          for (final period in periods) ...[
            const Divider(height: 16, color: AppColors.line),
            Row(
              children: [
                Expanded(child: Text(period.label, style: const TextStyle(fontSize: 16, color: AppColors.inkMuted))),
                Semantics(
                  button: true,
                  label: 'إضافة ${period.label} يوم ${weekdayNameOf(dayOfWeek)}',
                  excludeSemantics: true,
                  child: TextButton(
                    key: Key('add-$dayOfWeek-${period.name}'),
                    onPressed: () => onAdd(period),
                    style: TextButton.styleFrom(backgroundColor: AppColors.primarySoft, foregroundColor: AppColors.onPrimarySoft, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('إضافة'),
                  ),
                ),
              ],
            ),
            if (!schedules.any((row) => row.period == period))
              const Text('لا توجد وجبة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
            for (final row in schedules.where((row) => row.period == period))
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.weeklyRepeat ? row.mealName : '${row.mealName} (هذا الأسبوع)',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                  ),
                  TextButton(
                    key: Key('remove-${row.id}-$dayOfWeek'),
                    onPressed: () => onRemove(row),
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    child: const Text('إزالة'),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _ScheduleSheet extends ConsumerStatefulWidget {
  const _ScheduleSheet({required this.dayOfWeek, required this.period, required this.isRamadan});

  final int dayOfWeek;
  final MealPeriod period;
  final bool isRamadan;

  @override
  ConsumerState<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends ConsumerState<_ScheduleSheet> {
  String? _mealId;
  late final _days = {widget.dayOfWeek};
  bool _weekly = true;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_busy) return;
    final mealId = _mealId;
    if (mealId == null || _days.isEmpty) {
      setState(() => _error = 'اختر الوجبة ويوماً واحداً على الأقل.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      await ref.read(managerRepositoryProvider).addSchedule(
            mealId: mealId,
            period: widget.period,
            isRamadan: widget.isRamadan,
            weekdays: _days.toList()..sort(),
            weekly: _weekly,
          );
      refreshManagerData(ref);
      navigator.pop(true);
    } on ManagerFailure catch (failure) {
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
    final meals = (ref.watch(mealsProvider).valueOrNull ?? const <ManagerMeal>[]).where((meal) => meal.isActive).toList();
    final rule = (ref.watch(timeRulesProvider).valueOrNull ?? const <TimeRule>[]).where((rule) => rule.period == widget.period).firstOrNull;
    return PopScope(
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('جدولة ${widget.period.label}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          const Text('اختر الوجبة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (meals.isEmpty) const Text('لا توجد وجبات. أضف وجبة من تبويب الوجبات أولاً.', style: TextStyle(fontSize: 17, color: AppColors.inkMuted)),
          for (final meal in meals)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ChoiceBox(key: Key('pick-${meal.id}'), label: meal.name, selected: _mealId == meal.id, onTap: () => setState(() => _mealId = meal.id)),
            ),
          const SizedBox(height: 8),
          const Text('أي الأيام؟', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final dayOfWeek in weekOrder)
                SizedBox(
                  width: 112,
                  child: ChoiceBox(
                    key: Key('day-$dayOfWeek'),
                    label: weekdayNameOf(dayOfWeek),
                    center: true,
                    selected: _days.contains(dayOfWeek),
                    onTap: () => setState(() {
                      if (!_days.remove(dayOfWeek)) _days.add(dayOfWeek);
                    }),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: ChoiceBox(key: const Key('repeat-weekly'), label: 'كل أسبوع', center: true, selected: _weekly, onTap: () => setState(() => _weekly = true))),
              const SizedBox(width: 8),
              Expanded(child: ChoiceBox(key: const Key('repeat-once'), label: 'هذا الأسبوع فقط', center: true, selected: !_weekly, onTap: () => setState(() => _weekly = false))),
            ],
          ),
          if (rule != null) ...[
            const SizedBox(height: 12),
            FactBox(lines: [('الأوقات تلقائية: آخر إلغاء', ruleText(rule.cancelDay, rule.cancel))]),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBox(_error!),
          ],
          const SizedBox(height: 12),
          FilledButton(key: const Key('schedule-save'), onPressed: _busy ? null : _save, child: Text(_busy ? 'جارٍ النشر...' : 'حفظ ونشر')),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('رجوع'),
          ),
        ],
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.rule});

  final TimeRule rule;

  Future<void> _edit(BuildContext context) async {
    final result = await showAppSheet<(int, int)>(context, builder: (_) => _RuleSheet(rule: rule));
    if (result == null || !context.mounted) return;
    final (updated, kept) = result;
    await showNotice(
      context,
      kind: NoticeKind.done,
      title: 'حُفظت أوقات ${rule.period.label}',
      text: kept > 0 ? 'تغيّرت $updated وجبة، وبقيت $kept محجوزة على موعدها.' : 'تغيّرت $updated وجبة.',
    );
  }

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(rule.period.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('آخر حجز: ${ruleText(rule.bookDay, rule.book)}', style: const TextStyle(fontSize: 17)),
          Text('آخر إلغاء: ${ruleText(rule.cancelDay, rule.cancel)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text('بدء الاستلام: ${ruleText(rule.fromDay, rule.from)}', style: const TextStyle(fontSize: 17)),
          Text('آخر استلام: ${ruleText(rule.untilDay, rule.until)}', style: const TextStyle(fontSize: 17)),
          const SizedBox(height: 8),
          OutlinedButton(key: Key('edit-times-${rule.period.name}'), onPressed: () => _edit(context), child: const Text('تعديل الأوقات')),
        ],
      ),
    );
  }
}

class _RuleSheet extends ConsumerStatefulWidget {
  const _RuleSheet({required this.rule});

  final TimeRule rule;

  @override
  ConsumerState<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends ConsumerState<_RuleSheet> {
  late var _bookDay = widget.rule.bookDay;
  late var _book = widget.rule.book;
  late var _cancelDay = widget.rule.cancelDay;
  late var _cancel = widget.rule.cancel;
  late var _fromDay = widget.rule.fromDay;
  late var _from = widget.rule.from;
  late var _untilDay = widget.rule.untilDay;
  late var _until = widget.rule.until;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_busy) return;
    final rule = TimeRule(
      period: widget.rule.period,
      bookDay: _bookDay,
      book: _book,
      cancelDay: _cancelDay,
      cancel: _cancel,
      fromDay: _fromDay,
      from: _from,
      untilDay: _untilDay,
      until: _until,
    );
    final problem = rule.problem;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      final result = await ref.read(managerRepositoryProvider).saveTimeRule(rule);
      refreshManagerData(ref);
      navigator.pop(result);
    } on ManagerFailure catch (failure) {
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
    return PopScope(
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('أوقات ${widget.rule.period.label}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          _TimeField(keyName: 'book', label: 'آخر حجز', day: _bookDay, time: _book, onDay: (day) => setState(() => _bookDay = day), onTime: (time) => setState(() => _book = time)),
          _TimeField(keyName: 'cancel', label: 'آخر إلغاء', day: _cancelDay, time: _cancel, onDay: (day) => setState(() => _cancelDay = day), onTime: (time) => setState(() => _cancel = time)),
          _TimeField(keyName: 'from', label: 'بدء الاستلام', day: _fromDay, time: _from, onDay: (day) => setState(() => _fromDay = day), onTime: (time) => setState(() => _from = time)),
          _TimeField(keyName: 'until', label: 'آخر استلام', day: _untilDay, time: _until, onDay: (day) => setState(() => _untilDay = day), onTime: (time) => setState(() => _until = time)),
          const Text(
            'تتغير فوراً الوجبات التي لا حجوزات عليها. أما المحجوزة فتبقى على موعدها الذي وافق عليه أصحابها.',
            style: TextStyle(fontSize: 17, color: AppColors.inkMuted),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBox(_error!),
          ],
          const SizedBox(height: 12),
          FilledButton(key: const Key('times-save'), onPressed: _busy ? null : _save, child: Text(_busy ? 'جارٍ الحفظ...' : 'حفظ')),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('رجوع'),
          ),
        ],
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.keyName, required this.label, required this.day, required this.time, required this.onDay, required this.onTime});

  final String keyName;
  final String label;
  final int day;
  final TimeOfDay time;
  final ValueChanged<int> onDay;
  final ValueChanged<TimeOfDay> onTime;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: ChoiceBox(key: Key('$keyName-previous'), label: 'اليوم السابق', center: true, selected: day == -1, onTap: () => onDay(-1))),
              const SizedBox(width: 6),
              Expanded(child: ChoiceBox(key: Key('$keyName-same'), label: 'يوم الوجبة', center: true, selected: day == 0, onTap: () => onDay(0))),
            ],
          ),
          const SizedBox(height: 6),
          OutlinedButton(
            key: Key('$keyName-time'),
            onPressed: () async {
              final picked = await showTimePicker(context: context, initialTime: time);
              if (picked != null) onTime(picked);
            },
            child: Text(clock(DateTime(2000, 1, 1, time.hour, time.minute))),
          ),
        ],
      ),
    );
  }
}
