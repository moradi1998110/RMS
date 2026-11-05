import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/floating_dock.dart';
import '../../shared/role_shell.dart';
import 'admin_providers.dart';
import 'finance_page.dart';
import 'places_page.dart';
import 'summary_page.dart';
import 'users_page.dart';

class AdminShell extends ConsumerWidget {
  const AdminShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RoleShell(
      selected: ref.watch(adminTabProvider),
      onSelected: (index) => ref.read(adminTabProvider.notifier).state = index,
      pages: const [
        ShellPage(item: DockItem('الملخص', Icons.bar_chart), child: SummaryPage()),
        ShellPage(item: DockItem('المستخدمون', Icons.group), child: UsersPage()),
        ShellPage(item: DockItem('المطاعم', Icons.place), child: PlacesPage()),
        ShellPage(item: DockItem('المالية', Icons.account_balance_wallet), child: FinancePage()),
      ],
    );
  }
}
