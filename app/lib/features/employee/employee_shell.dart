import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/floating_dock.dart';
import '../../shared/role_shell.dart';
import 'account_page.dart';
import 'bookings_page.dart';
import 'employee_providers.dart';
import 'meals_page.dart';

class EmployeeShell extends ConsumerStatefulWidget {
  const EmployeeShell({super.key});

  @override
  ConsumerState<EmployeeShell> createState() => _EmployeeShellState();
}

class _EmployeeShellState extends ConsumerState<EmployeeShell> {
  // The phone may sit for hours with the app open: a top-up or a closed booking window
  // should show as soon as the user comes back.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => refreshEmployeeData(ref));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      selected: ref.watch(employeeTabProvider),
      onSelected: (index) => ref.read(employeeTabProvider.notifier).state = index,
      pages: const [
        ShellPage(item: DockItem('الوجبات', Icons.restaurant), child: MealsPage()),
        ShellPage(item: DockItem('حجوزاتي', Icons.calendar_month), child: BookingsPage()),
        ShellPage(item: DockItem('حسابي', Icons.person), child: AccountPage()),
      ],
    );
  }
}
