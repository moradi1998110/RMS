import 'package:flutter/material.dart';

import '../core/theme.dart';

class DockItem {
  const DockItem(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Floating navigation with a sliding pill. Every icon keeps its label, because icons
/// alone confuse many of our users.
class FloatingDock extends StatelessWidget {
  const FloatingDock({super.key, required this.items, required this.selected, required this.onSelected});

  final List<DockItem> items;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 260);
    // The bar has a fixed height, so very large system text is capped here only.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Container(
        height: 76,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFDDE5E3)),
          boxShadow: const [BoxShadow(color: Color(0x3312302C), blurRadius: 32, offset: Offset(0, 12))],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth / items.length;
            return Stack(
              children: [
                AnimatedPositionedDirectional(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  start: selected * width,
                  top: 0,
                  bottom: 0,
                  width: width,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(22)),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: _DockButton(item: items[i], active: i == selected, onTap: () => onSelected(i)),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({required this.item, required this.active, required this.onTap});

  final DockItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.surface : AppColors.inkMuted;
    return Semantics(
      selected: active,
      button: true,
      excludeSemantics: true,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, size: 26, color: color),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(item.label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
            ),
          ],
        ),
      ),
    );
  }
}
