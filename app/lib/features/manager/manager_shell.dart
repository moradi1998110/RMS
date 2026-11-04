import 'package:flutter/material.dart';

import '../../shared/floating_dock.dart';
import '../../shared/role_shell.dart';

class ManagerShell extends StatelessWidget {
  const ManagerShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleShell(
      pages: [
        ShellPage(item: DockItem('اليوم', Icons.qr_code_scanner), child: PlannedPage('وجبات اليوم')),
        ShellPage(item: DockItem('البرنامج', Icons.calendar_month), child: PlannedPage('البرنامج الأسبوعي')),
        ShellPage(item: DockItem('الوجبات', Icons.restaurant), child: PlannedPage('الوجبات')),
        ShellPage(item: DockItem('التقارير', Icons.bar_chart), child: PlannedPage('التقارير')),
      ],
    );
  }
}
