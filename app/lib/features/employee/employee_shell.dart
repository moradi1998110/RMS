import 'package:flutter/material.dart';

import '../../shared/floating_dock.dart';
import '../../shared/role_shell.dart';

class EmployeeShell extends StatelessWidget {
  const EmployeeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleShell(
      pages: [
        ShellPage(item: DockItem('الوجبات', Icons.restaurant), child: PlannedPage('الوجبات')),
        ShellPage(item: DockItem('حجوزاتي', Icons.calendar_month), child: PlannedPage('حجوزاتي')),
        ShellPage(item: DockItem('حسابي', Icons.person), child: PlannedPage('حسابي')),
      ],
    );
  }
}
