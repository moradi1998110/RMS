
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import '../../shared/error_box.dart';
import '../../shared/meal_image.dart';
import '../../shared/notice.dart';
import 'manager_models.dart';
import 'manager_providers.dart';
import 'manager_repository.dart';

class MealsTab extends ConsumerWidget {
  const MealsTab({super.key});

  Future<void> _open(BuildContext context, [ManagerMeal? meal]) async {
    final saved = await showAppSheet<bool>(context, builder: (_) => MealSheet(meal: meal));
    if (saved != true || !context.mounted) return;
    await showNotice(context, kind: NoticeKind.done, title: meal == null ? 'أُضيفت الوجبة' : 'حُفظت الوجبة', text: meal == null ? 'أضفها إلى البرنامج لتظهر للموظفين.' : null);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meals = ref.watch(mealsProvider);
    final value = meals.valueOrNull;
    final scheduled = {for (final row in ref.watch(schedulesProvider).valueOrNull ?? const <ScheduleRow>[]) row.mealId};
    final schedulesLoaded = ref.watch(schedulesProvider).hasValue;
    if (value == null) {
      return LoadingOrError(error: meals.error, onRetry: () => ref.invalidate(mealsProvider));
    }
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(mealsProvider);
        await ref.read(mealsProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Text('الوجبات', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 28)),
          const SizedBox(height: 12),
          FilledButton(key: const Key('add-meal'), onPressed: () => _open(context), child: const Text('إضافة وجبة جديدة')),
          const SizedBox(height: 12),
          if (value.isEmpty) const Text('لا توجد وجبات بعد. ابدأ بإضافة أول وجبة.', style: TextStyle(fontSize: 18)),
          for (final meal in value) ...[
            _MealCard(meal: meal, unscheduled: schedulesLoaded && meal.isActive && !scheduled.contains(meal.id), imageUrl: meal.imagePath == null ? null : ref.read(managerRepositoryProvider).imageUrl(meal.imagePath!), onEdit: () => _open(context, meal)),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, required this.unscheduled, required this.imageUrl, required this.onEdit});

  final ManagerMeal meal;
  final String? imageUrl;
  final bool unscheduled;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (imageUrl != null)
            SizedBox(
              height: 110,
              child: MealImage(url: imageUrl!),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(meal.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
                    const SizedBox(width: 12),
                    Text(points(meal.price), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ],
                ),
                Text(meal.extras.isEmpty ? 'بدون إضافات' : 'معها: ${meal.extras.join('، ')}', style: const TextStyle(fontSize: 17, color: AppColors.inkMuted)),
                if (unscheduled)
                  const Text('غير مجدولة: لا تظهر للموظفين حتى تضيفها إلى البرنامج', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.onWarningSoft)),
                if (!meal.isActive)
                  const Text('موقوفة: لا تُعرض للموظفين', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.onDangerSoft)),
                const SizedBox(height: 8),
                OutlinedButton(key: Key('edit-meal-${meal.id}'), onPressed: onEdit, child: const Text('تعديل')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MealSheet extends ConsumerStatefulWidget {
  const MealSheet({super.key, this.meal});

  final ManagerMeal? meal;

  @override
  ConsumerState<MealSheet> createState() => _MealSheetState();
}

class _MealSheetState extends ConsumerState<MealSheet> {
  late final _name = TextEditingController(text: widget.meal?.name);
  late final _description = TextEditingController(text: widget.meal?.description);
  late final _price = TextEditingController(text: widget.meal == null ? '' : '${widget.meal!.price}');
  late bool _salad = widget.meal?.hasSalad ?? false;
  late bool _softDrink = widget.meal?.hasSoftDrink ?? false;
  late bool _juice = widget.meal?.hasJuice ?? false;
  late bool _vegetables = widget.meal?.hasVegetables ?? false;
  late bool _active = widget.meal?.isActive ?? true;
  Uint8List? _image;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pick(bool fromCamera) async {
    final bytes = await ref.read(photoPickerProvider)(fromCamera);
    if (bytes == null || !mounted) return;
    setState(() {
      _image = bytes.length > maxImageBytes ? null : bytes;
      _error = bytes.length > maxImageBytes ? 'هذه الصورة كبيرة. اختر صورة أخرى.' : null;
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    final problem = mealProblem(_name.text, _price.text);
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
      await ref.read(managerRepositoryProvider).saveMeal(MealDraft(
            id: widget.meal?.id,
            name: _name.text,
            description: _description.text,
            price: int.parse(_price.text),
            hasSalad: _salad,
            hasSoftDrink: _softDrink,
            hasJuice: _juice,
            hasVegetables: _vegetables,
            isActive: _active,
            imagePath: widget.meal?.imagePath,
            newImage: _image,
          ));
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
    final meal = widget.meal;
    final savedImage = meal?.imagePath == null ? null : ref.read(managerRepositoryProvider).imageUrl(meal!.imagePath!);
    return PopScope(
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(meal == null ? 'وجبة جديدة' : 'تعديل الوجبة', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          if (_image != null || savedImage != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 120,
                child: _image != null
                    ? Image.memory(_image!, key: const Key('meal-photo'), fit: BoxFit.cover)
                    : MealImage(url: savedImage!),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(child: OutlinedButton(key: const Key('photo-camera'), onPressed: _busy ? null : () => _pick(true), child: const Text('التقط صورة'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(key: const Key('photo-gallery'), onPressed: _busy ? null : () => _pick(false), child: const Text('من المعرض'))),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('meal-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'اسم الوجبة'),
            style: const TextStyle(fontSize: 19),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('meal-description'),
            controller: _description,
            decoration: const InputDecoration(labelText: 'التفاصيل'),
            style: const TextStyle(fontSize: 18),
            maxLines: 2,
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('meal-price'),
            controller: _price,
            decoration: const InputDecoration(labelText: 'قيمة الوجبة بالنقاط'),
            style: const TextStyle(fontSize: 19),
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
          ),
          const SizedBox(height: 14),
          const Text('معها', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: ChoiceBox(key: const Key('extra-salad'), label: 'سلطة', center: true, selected: _salad, onTap: () => setState(() => _salad = !_salad))),
              const SizedBox(width: 8),
              Expanded(child: ChoiceBox(key: const Key('extra-drink'), label: 'مشروب غازي', center: true, selected: _softDrink, onTap: () => setState(() => _softDrink = !_softDrink))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: ChoiceBox(key: const Key('extra-juice'), label: 'عصير', center: true, selected: _juice, onTap: () => setState(() => _juice = !_juice))),
              const SizedBox(width: 8),
              Expanded(child: ChoiceBox(key: const Key('extra-vegetables'), label: 'خضراوات', center: true, selected: _vegetables, onTap: () => setState(() => _vegetables = !_vegetables))),
            ],
          ),
          if (meal != null) ...[
            const SizedBox(height: 12),
            OptionSwitch(
              key: const Key('meal-active'),
              label: 'تُعرض للموظفين. عند الإيقاف تختفي من البرنامج، وتبقى الحجوزات القائمة.',
              value: _active,
              onChanged: (value) => setState(() => _active = value),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBox(_error!),
          ],
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('meal-save'),
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'جارٍ الحفظ...' : 'حفظ الوجبة'),
          ),
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
