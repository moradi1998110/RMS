import 'package:flutter/material.dart';

import '../../shared/floating_dock.dart';
import '../../shared/role_shell.dart';
import 'meals_tab.dart';
import 'program_tab.dart';
import 'reports_tab.dart';
import 'today_tab.dart';

class ManagerShell extends StatelessWidget {
  const ManagerShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleShell(
      pages: [
        ShellPage(item: DockItem('اليوم', Icons.qr_code_scanner), child: TodayTab()),
        ShellPage(item: DockItem('البرنامج', Icons.calendar_month), child: ProgramTab()),
        ShellPage(item: DockItem('الوجبات', Icons.restaurant), child: MealsTab()),
        ShellPage(item: DockItem('التقارير', Icons.bar_chart), child: ReportsTab()),
      ],
    );
  }
}
