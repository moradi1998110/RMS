import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import 'delegates_sheet.dart';
import 'employee_models.dart';
import 'employee_providers.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);
    final transactions = ref.watch(transactionsProvider);
    final walletValue = wallet.valueOrNull;
    final transactionsValue = transactions.valueOrNull;

    if (walletValue == null || transactionsValue == null) {
      return LoadingOrError(
        error: wallet.error ?? transactions.error,
        onRetry: () => refreshEmployeeData(ref),
      );
    }

    final limit = ref.watch(transactionsLimitProvider);
    final shown = transactionsValue.take(limit).toList();
    final hasMore = transactionsValue.length > limit;
    final textTheme = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () async {
        refreshEmployeeData(ref);
        await ref.read(transactionsProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Text('حسابي', style: textTheme.headlineMedium?.copyWith(fontSize: 28)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _BalanceTile(label: 'متاح', amount: walletValue.available, strong: true)),
              const SizedBox(width: 10),
              Expanded(child: _BalanceTile(label: 'محجوز', amount: walletValue.held, strong: false)),
            ],
          ),
          const SizedBox(height: 14),
          // Also here, since the meals page shows the button only with a meal coming up.
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(child: Text('من يستلم وجباتي', style: textTheme.titleMedium)),
                const DelegatesButton(),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('حركات حسابك', style: textTheme.titleMedium?.copyWith(fontSize: 22)),
          const SizedBox(height: 10),
          if (shown.isEmpty)
            Text('لا توجد حركات بعد.', style: textTheme.bodyLarge?.copyWith(color: AppColors.inkMuted)),
          for (final transaction in shown) ...[
            _TransactionCard(transaction: transaction),
            const SizedBox(height: 10),
          ],
          if (hasMore)
            OutlinedButton(
              key: const Key('tx-more'),
              onPressed: transactions.isLoading ? null : () => ref.read(transactionsLimitProvider.notifier).state = limit + transactionsPage,
              child: Text(transactions.isLoading ? 'جارٍ التحميل...' : 'عرض المزيد'),
            ),
        ],
      ),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({required this.label, required this.amount, required this.strong});

  final String label;
  final int amount;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final foreground = strong ? AppColors.surface : AppColors.ink;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: strong ? AppColors.primary : AppColors.surface,
        border: strong ? null : Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 17, color: foreground)),
          Text(money(amount), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: foreground)),
        ],
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.transaction});

  final WalletTx transaction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(transaction.text, style: const TextStyle(fontSize: 17)),
                Text(shortDate(transaction.createdAt), style: const TextStyle(fontSize: 16, color: AppColors.inkMuted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            transaction.amountText,
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: transaction.isGain ? AppColors.primary : AppColors.ink),
          ),
        ],
      ),
    );
  }
}
