import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/auth_models.dart';
import '../features/update/update_ui.dart';
import 'floating_dock.dart';

class ShellPage {
  const ShellPage({required this.item, required this.child});

  final DockItem item;
  final Widget child;
}

/// The frame for each role: name and sign-out on top, floating navigation below.
class RoleShell extends ConsumerStatefulWidget {
  const RoleShell({super.key, required this.pages, this.selected, this.onSelected});

  final List<ShellPage> pages;

  /// Set these when something outside the dock also needs to change the page.
  final int? selected;
  final ValueChanged<int>? onSelected;

  @override
  ConsumerState<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends ConsumerState<RoleShell> {
  int _selected = 0;

  // A page is built, and fetches its data, only once it is first opened; after that
  // it stays alive so switching back is instant.
  final _opened = <int>{};

  // Looks for a new version again when the app comes back, at most every few hours.
  late final AppLifecycleListener _lifecycle;
  DateTime _updateCheckedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () {
      if (DateTime.now().difference(_updateCheckedAt) < const Duration(hours: 3)) return;
      _updateCheckedAt = DateTime.now();
      ref.invalidate(availableUpdateProvider);
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('لا')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('نعم، اخرج')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(authControllerProvider);
    final name = status is SignedIn ? status.profile.fullName : '';
    final selected = widget.selected ?? _selected;
    _opened.add(selected);
    final update = ref.watch(availableUpdateProvider).valueOrNull;
    if (update != null && update.required) return UpdateRequiredScreen(update: update);
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                      ),
                      TextButton(onPressed: _confirmSignOut, child: const Text('خروج')),
                    ],
                  ),
                ),
                const UpdateBanner(),
                Expanded(
                  child: IndexedStack(
                    index: selected,
                    children: [
                      for (final (index, page) in widget.pages.indexed)
                        _opened.contains(index)
                            ? Padding(padding: const EdgeInsets.only(bottom: 96), child: page.child)
                            : const SizedBox.shrink(),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: FloatingDock(
                items: [for (final page in widget.pages) page.item],
                selected: selected,
                onSelected: widget.onSelected ?? (index) => setState(() => _selected = index),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stands in for a screen that has not been built yet.
class PlannedPage extends StatelessWidget {
  const PlannedPage(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'هذه الشاشة قيد البناء.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.inkMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
