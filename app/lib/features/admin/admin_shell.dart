import 'package:flutter/material.dart';

import '../../shared/floating_dock.dart';
import '../../shared/role_shell.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleShell(
      pages: [
        ShellPage(item: DockItem('الملخص', Icons.bar_chart), child: PlannedPage('الملخص')),
        ShellPage(item: DockItem('المستخدمون', Icons.group), child: PlannedPage('المستخدمون')),
        ShellPage(item: DockItem('المطاعم', Icons.place), child: PlannedPage('المواقع والمطاعم')),
        ShellPage(item: DockItem('المالية', Icons.account_balance_wallet), child: PlannedPage('المالية')),
      ],
    );
  }
}
