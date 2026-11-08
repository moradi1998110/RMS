import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import '../../shared/error_box.dart';
import 'app_updater.dart';
import 'update_models.dart';

/// The newer version this phone can install, if any. Kept for the whole session; a
/// failed check is simply no offer, so a weak connection never blocks the app.
final availableUpdateProvider = FutureProvider<AvailableUpdate?>((ref) async {
  try {
    final updater = ref.watch(appUpdaterProvider);
    if (updater.currentBuild <= 0) return null;
    return updateFor(await updater.latest(), currentBuild: updater.currentBuild, abi: updater.abi);
  } catch (_) {
    return null;
  }
});

Future<void> showUpdateSheet(BuildContext context, AvailableUpdate update) {
  return showAppSheet<void>(context, builder: (_) => UpdatePanel(update: update, closable: true));
}

/// A strip at the top of every screen while a newer version waits.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(availableUpdateProvider).valueOrNull;
    if (update == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Material(
        key: const Key('update-banner'),
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.system_update_rounded, color: AppColors.onWarningSoft),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('يوجد تحديث جديد لتطبيق ZAD', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.onWarningSoft)),
              ),
              FilledButton(
                key: const Key('update-open'),
                onPressed: () => showUpdateSheet(context, update),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 14)),
                child: const Text('حدّث الآن'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// This copy's version, and a way to look for an update now rather than wait.
class AppVersionRow extends ConsumerStatefulWidget {
  const AppVersionRow({super.key});

  @override
  ConsumerState<AppVersionRow> createState() => _AppVersionRowState();
}

class _AppVersionRowState extends ConsumerState<AppVersionRow> {
  bool _checking = false;
  String? _result;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    ref.invalidate(availableUpdateProvider);
    final update = await ref.read(availableUpdateProvider.future);
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (update == null) _result = 'لديك أحدث إصدار.';
    });
    if (update != null) await showUpdateSheet(context, update);
  }

  @override
  Widget build(BuildContext context) {
    final updater = ref.watch(appUpdaterProvider.select((updater) => (updater.currentVersion, updater.currentBuild)));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الإصدار ${updater.$1} (${updater.$2})', key: const Key('app-version'), style: Theme.of(context).textTheme.titleMedium),
                if (_result != null) Text(_result!, key: const Key('update-none'), style: const TextStyle(fontSize: 16, color: AppColors.inkMuted)),
              ],
            ),
          ),
          TextButton(
            key: const Key('update-check'),
            onPressed: _checking ? null : _check,
            child: Text(_checking ? 'جارٍ البحث...' : 'ابحث عن تحديث'),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of the app when this build is older than a mandatory release.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.update});

  final AvailableUpdate update;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('update-required'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.system_update_rounded, size: 72, color: AppColors.primary),
              const SizedBox(height: 12),
              Text('يجب تحديث التطبيق', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              const Text(
                'هذه النسخة لم تعد تعمل. حدّثها لتكمل الحجز والاستلام.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 20),
              UpdatePanel(update: update, closable: false),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Stage { ready, downloading, installing, opened }

/// What is new, then download with progress, then Android's install screen.
class UpdatePanel extends ConsumerStatefulWidget {
  const UpdatePanel({super.key, required this.update, required this.closable});

  final AvailableUpdate update;
  final bool closable;

  @override
  ConsumerState<UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends ConsumerState<UpdatePanel> {
  _Stage _stage = _Stage.ready;
  double _progress = 0;
  String? _error;

  // Kept after a download, so allowing the install in settings needs no second download.
  String? _downloaded;

  Future<void> _start() async {
    final updater = ref.read(appUpdaterProvider);
    setState(() {
      _error = null;
      _stage = _downloaded == null ? _Stage.downloading : _Stage.installing;
      _progress = 0;
    });
    try {
      final path = _downloaded ??
          await updater.download(widget.update.file, (progress) {
            if (mounted) setState(() => _progress = progress);
          });
      _downloaded = path;
      if (mounted) setState(() => _stage = _Stage.installing);
      await updater.install(path);
      if (mounted) setState(() => _stage = _Stage.opened);
    } on UpdateException catch (failure) {
      if (failure.failure != UpdateFailure.installBlocked) _downloaded = null;
      if (mounted) {
        setState(() {
          _stage = _Stage.ready;
          _error = failure.failure.message;
        });
      }
    } catch (_) {
      _downloaded = null;
      if (mounted) {
        setState(() {
          _stage = _Stage.ready;
          _error = UpdateFailure.network.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.update.release;
    final textTheme = Theme.of(context).textTheme;
    final busy = _stage == _Stage.downloading || _stage == _Stage.installing;
    return PopScope(
      canPop: !busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('ZAD ${release.version} (${release.build})', style: textTheme.titleLarge),
          Text('حجم التحديث ${widget.update.file.megabytes} ميغابايت', style: const TextStyle(fontSize: 17, color: AppColors.inkMuted)),
          if (release.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('update-notes'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.ground, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ما الجديد', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(release.notes, style: const TextStyle(fontSize: 18, height: 1.4)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'في أول تحديث قد يطلب الهاتف إذناً: اضغط «الإعدادات»، ثم فعّل «السماح من هذا المصدر»، ثم ارجع واضغط «ثبّت».',
            style: TextStyle(fontSize: 16, color: AppColors.inkMuted, height: 1.4),
          ),
          if (_stage == _Stage.downloading) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(key: const Key('update-progress'), value: _progress, minHeight: 10, borderRadius: BorderRadius.circular(5)),
            const SizedBox(height: 6),
            Text('جارٍ التنزيل ${(_progress * 100).round()}٪', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
          ],
          if (_stage == _Stage.opened) ...[
            const SizedBox(height: 14),
            Container(
              key: const Key('update-opened'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
              child: const Text(
                'اضغط «تثبيت» في الشاشة التي ظهرت. بعد التثبيت افتح ZAD من جديد.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onPrimarySoft),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBox(_error!),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('update-start'),
            onPressed: busy ? null : _start,
            icon: const Icon(Icons.download_rounded),
            label: Text(switch (_stage) {
              _Stage.downloading => 'جارٍ التنزيل...',
              _Stage.installing => 'جارٍ فتح التثبيت...',
              _Stage.opened => 'افتح شاشة التثبيت مرة أخرى',
              _Stage.ready => _downloaded != null ? 'ثبّت' : (_error != null ? 'حاول مرة أخرى' : 'نزّل وثبّت'),
            }),
          ),
          if (widget.closable) ...[
            const SizedBox(height: 8),
            TextButton(
              key: const Key('update-later'),
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56), foregroundColor: AppColors.ink),
              child: const Text('لاحقاً'),
            ),
          ],
        ],
      ),
    );
  }
}
