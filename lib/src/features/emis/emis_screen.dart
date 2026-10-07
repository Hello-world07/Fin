import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../domain/due_status.dart';
import '../../domain/emi_math.dart';
import '../../domain/emi_payment_rules.dart';
import '../../domain/enums.dart';
import '../../shared/async_view.dart';
import '../../shared/calculator_sheet.dart';
import '../../shared/empty_state.dart';
import '../../shared/forms.dart';
import '../../shared/finance_form_widgets.dart';
import '../../shared/finance_display_widgets.dart';

class EmisScreen extends ConsumerWidget {
  const EmisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EMIs & Loans'),
        actions: [
          if (ref.watch(emiStatusFilterProvider) != null)
            TextButton(
              onPressed: () =>
                  ref.read(emiStatusFilterProvider.notifier).state = null,
              child: const Text('All'),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openFinanceSheet(context, const EmiFormSheet()),
        icon: const Icon(Icons.add),
        label: const Text('Add EMI'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: AsyncView(
        value: ref.watch(emiDetailsProvider),
        builder: (items) {
          final filter = ref.watch(emiStatusFilterProvider);
          final visible = filter == null
              ? items
              : items.where((item) => item.emi.status == filter).toList();
          if (visible.isEmpty) {
            return const EmptyState(
              icon: Icons.account_balance_outlined,
              title: 'No EMIs yet',
              message:
                  'Add loans or installment commitments to track progress and due dates.',
            );
          }
          final active = visible
              .where(
                (item) =>
                    item.emi.status != EmiStatus.completed &&
                    item.nextUnpaidInstallment != null,
              )
              .toList();
          final completed = visible
              .where(
                (item) =>
                    item.emi.status == EmiStatus.completed ||
                    item.nextUnpaidInstallment == null,
              )
              .toList();
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, _emiListBottomPadding),
            children: [
              _EmiListSummary(items: active),
              if (active.isNotEmpty) ...[
                _EmiSectionLabel('ACTIVE', '${active.length}'),
                for (final item in active) ...[
                  _EmiRow(detail: item),
                  const Divider(height: 1),
                ],
              ],
              if (completed.isNotEmpty) ...[
                _EmiSectionLabel('COMPLETED', '${completed.length}'),
                for (final item in completed) ...[
                  _EmiRow(detail: item),
                  const Divider(height: 1),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _EmiSectionLabel extends StatelessWidget {
  const _EmiSectionLabel(this.title, this.count);
  final String title;
  final String count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Text(count, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

class _EmiListSummary extends StatelessWidget {
  const _EmiListSummary({required this.items});

  final List<EmiDetail> items;

  @override
  Widget build(BuildContext context) {
    final active = items
        .where(
          (item) =>
              item.nextUnpaidInstallment != null &&
              item.emi.status != EmiStatus.completed &&
              item.emi.status != EmiStatus.paused,
        )
        .toList();
    final remaining = active.fold<int>(
      0,
      (sum, item) => sum + item.remainingBalancePaise,
    );
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${active.length} active ${active.length == 1 ? 'EMI' : 'EMIs'}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Remaining across active EMIs',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            AmountText(
              remaining,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

const double _emiListBottomPadding = 88;

class _EmiRow extends StatelessWidget {
  const _EmiRow({required this.detail});

  final EmiDetail detail;

  @override
  Widget build(BuildContext context) {
    final emi = detail.emi;
    final nextInstallment = detail.nextUnpaidInstallment;
    final nextDueDate = nextInstallment?.dueDate;
    final isCompleted =
        emi.status == EmiStatus.completed || nextInstallment == null;
    final dueText = isCompleted
        ? 'Completed'
        : relativeDueText(nextDueDate!, DateTime.now());
    final canPay =
        !isCompleted &&
        emi.status != EmiStatus.paused &&
        isWithinEmiPaymentWindow(nextDueDate!, DateTime.now());
    final colors = Theme.of(context).colorScheme;
    final dueColor = dueText.startsWith('Overdue')
        ? colors.error
        : dueText == 'Due today'
        ? colors.primary
        : colors.secondary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
      leading: SizedBox.square(
        dimension: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: detail.progress.clamp(0.0, 1.0),
              strokeWidth: 4,
              backgroundColor: colors.surfaceContainerHighest,
            ),
            Text(
              '${detail.paidInstallments}/${emi.tenureMonths}',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              displayName(emi.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            '${formatMoney(nextInstallment == null ? detail.scheduledInstallmentPaise : detail.amountForInstallment(nextInstallment.number))} / ${emi.frequency.label.toLowerCase()}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isCompleted
                        ? 'Completed'
                        : 'Due ${formatDate(nextDueDate!)}',
                  ),
                ),
                Text(
                  dueText,
                  style: TextStyle(
                    color: dueColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isCompleted
                  ? 'Completed · ${detail.paidInstallments}/${emi.tenureMonths} paid'
                  : '${detail.remainingInstallments} left · ${formatMoney(detail.remainingBalancePaise)} remaining · ${emi.status.label}',
            ),
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canPay)
            _PayEmiButton(detail: detail, installment: nextInstallment),
          Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
        ],
      ),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => EmiDetailScreen(emi.id))),
      onLongPress: () => openFinanceSheet(context, EmiFormSheet(emi: emi)),
    );
  }
}

class _PayEmiButton extends ConsumerWidget {
  const _PayEmiButton({required this.detail, required this.installment});

  final EmiDetail detail;
  final EmiInstallment installment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emi = detail.emi;
    final paying = ref.watch(payingEmisProvider).contains(emi.id);
    final disabled = paying || emi.status == EmiStatus.completed;
    return IconButton(
      tooltip: paying
          ? 'Recording...'
          : emi.status == EmiStatus.completed
          ? 'Paid'
          : 'Mark paid',
      icon: paying
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              emi.status == EmiStatus.completed
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
            ),
      onPressed: disabled
          ? null
          : () async {
              final payingState = ref.read(payingEmisProvider.notifier);
              if (payingState.state.contains(emi.id)) return;
              payingState.update((state) => {...state, emi.id});
              try {
                final recorded = await ref
                    .read(financeRepositoryProvider)
                    .markEmiPaid(
                      emi.id,
                      expectedDueDate: installment.dueDate,
                      expectedInstallmentNumber: installment.number,
                    );
                if (!recorded && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Installment already recorded'),
                    ),
                  );
                }
              } finally {
                payingState.update((state) {
                  final next = {...state}..remove(emi.id);
                  return next;
                });
              }
            },
    );
  }
}

class EmiDetailScreen extends ConsumerStatefulWidget {
  const EmiDetailScreen(this.id, {super.key});

  final int id;

  @override
  ConsumerState<EmiDetailScreen> createState() => _EmiDetailScreenState();
}

class _EmiDetailScreenState extends ConsumerState<EmiDetailScreen> {
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(financeRepositoryProvider);
    return FutureBuilder(
      key: ValueKey(_reload),
      future: repo.emiDetail(widget.id),
      builder: (context, snapshot) {
        final detail = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(displayName(detail?.emi.name ?? 'EMI')),
            actions: [
              if (detail != null)
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () =>
                      openFinanceSheet(context, EmiFormSheet(emi: detail.emi)),
                ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: detail == null
                    ? null
                    : () async {
                        final current = detail;
                        final unpaid = current.remainingInstallments;
                        final amount = formatMoney(
                          current.scheduledInstallmentPaise,
                        );
                        final remaining = unpaid == 0
                            ? ''
                            : '\n\n$unpaid unpaid installment${unpaid == 1 ? '' : 's'} '
                                  'of $amount will no longer be tracked.';
                        final delete = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text('Delete "${current.emi.name}"?'),
                            content: Text(
                              'This will remove the EMI from your active list. Its recorded payment history will be kept.$remaining',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.error,
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.onError,
                                ),
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete EMI'),
                              ),
                            ],
                          ),
                        );
                        if (delete != true) return;
                        await repo.deleteEmi(widget.id);
                        if (context.mounted) Navigator.pop(context);
                      },
              ),
            ],
          ),
          body: detail == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _EmiOverview(detail: detail),
                    if (detail.nextUnpaidInstallment != null &&
                        detail.emi.status != EmiStatus.completed &&
                        detail.emi.status != EmiStatus.paused) ...[
                      const SizedBox(height: 16),
                      _EarlyPaymentAction(
                        detail: detail,
                        onPaid: () => setState(() => _reload++),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Payment history',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    _InstallmentTimeline(detail: detail),
                  ],
                ),
        );
      },
    );
  }
}

class _EmiOverview extends StatelessWidget {
  const _EmiOverview({required this.detail});

  final EmiDetail detail;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final totalPaise = detail.totalRepaymentPaise;
    final remainingPaise = detail.remainingBalancePaise;
    final percent = (detail.progress * 100).clamp(0, 100).round();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 116,
            child: Center(
              child: MiniProgressRing(
                progress: detail.progress,
                size: 104,
                strokeWidth: 10,
                backgroundColor: colors.outlineVariant.withValues(alpha: 0.35),
                child: Text(
                  '$percent%',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EMI overview',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                _OverviewMetric(
                  label: 'Paid',
                  value: formatMoney(detail.paidPaise),
                ),
                _OverviewMetric(
                  label: 'Remaining',
                  value: formatMoney(remainingPaise),
                ),
                _OverviewMetric(
                  label: 'Total payable',
                  value: formatMoney(totalPaise),
                ),
                _OverviewMetric(
                  label: 'Installments',
                  value:
                      '${detail.paidInstallments} paid • ${detail.remainingInstallments} left',
                ),
                _OverviewMetric(
                  label: 'Tenure',
                  value: '${detail.emi.tenureMonths} installments',
                ),
                if (detail.emi.interestRate != null)
                  _OverviewMetric(
                    label: 'Interest rate',
                    value: '${detail.emi.interestRate}% p.a.',
                  ),
                if (detail.installments.isNotEmpty)
                  _OverviewMetric(
                    label: 'Final installment',
                    value: formatDate(detail.installments.last.dueDate),
                  ),
                if (detail.installments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      detail.nextUnpaidInstallment == null
                          ? 'This EMI is complete.'
                          : 'You\'ll finish this EMI on ${formatDate(detail.installments.last.dueDate)}.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _EarlyPaymentAction extends ConsumerWidget {
  const _EarlyPaymentAction({required this.detail, required this.onPaid});

  final EmiDetail detail;
  final VoidCallback onPaid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emi = detail.emi;
    final installment = detail.nextUnpaidInstallment;
    if (installment == null) return const SizedBox.shrink();
    final amount = formatMoney(detail.amountForInstallment(installment.number));
    final isNormalWindow = isWithinEmiPaymentWindow(
      installment.dueDate,
      DateTime.now(),
    );
    return OutlinedButton.icon(
      icon: const Icon(Icons.fast_forward_outlined),
      label: Text(
        isNormalWindow
            ? 'Record ${_monthLabel(installment.dueDate)} EMI • $amount'
            : 'Mark ${_monthLabel(installment.dueDate)} EMI paid early • $amount',
      ),
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              isNormalWindow
                  ? 'Record ${_monthLabel(installment.dueDate)} EMI?'
                  : 'Mark ${_monthLabel(installment.dueDate)} EMI paid early?',
            ),
            content: Text(
              '$amount\n'
              '${isNormalWindow ? 'Due' : 'Originally due'}: '
              '${formatDate(installment.dueDate)}\n'
              'FinKeep records this payment in your tracker; it does not transfer money.\n'
              'Installment ${installment.number}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Mark as paid • $amount'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        final recorded = await ref
            .read(financeRepositoryProvider)
            .markEmiPaid(
              emi.id,
              expectedDueDate: installment.dueDate,
              expectedInstallmentNumber: installment.number,
              paidEarly: !isNormalWindow,
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                recorded
                    ? 'EMI payment recorded'
                    : 'Installment already recorded',
              ),
            ),
          );
        }
        if (recorded) onPaid();
      },
    );
  }
}

class _InstallmentTimeline extends StatelessWidget {
  const _InstallmentTimeline({required this.detail});

  final EmiDetail detail;

  @override
  Widget build(BuildContext context) {
    final paymentsByInstallment = {
      for (final payment in detail.payments) payment.installmentNumber: payment,
    };
    final children = <Widget>[];
    final now = DateTime.now();
    for (final installment in detail.installments) {
      final payment = paymentsByInstallment[installment.number];
      final state =
          payment == null &&
              installment.number <= detail.emi.initialPaidInstallments
          ? _InstallmentState.paidBeforeTracking
          : _installmentState(installment.dueDate, now, payment);
      children.add(
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _stateColor(context, state).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _stateColor(context, state).withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_stateIcon(state), color: _stateColor(context, state)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _monthLabel(installment.dueDate),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        StatusPill(
                          label: _stateLabel(state),
                          color: _stateColor(context, state),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatMoney(
                        payment?.amountPaise ??
                            detail.amountForInstallment(installment.number),
                      ),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${payment?.paidEarly == true ? 'Scheduled' : 'Due'}: '
                      '${formatDate(installment.dueDate)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (payment != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${payment.paidEarly ? 'Paid early' : 'Paid'}: '
                        '${formatDateTime(payment.paidOn)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (state == _InstallmentState.paidBeforeTracking) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Paid before tracking began',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      'Installment ${installment.number}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: children);
  }

  _InstallmentState _installmentState(
    DateTime due,
    DateTime now,
    EmiPayment? payment,
  ) {
    if (payment != null) {
      return payment.paidEarly
          ? _InstallmentState.paidEarly
          : _InstallmentState.paid;
    }
    final today = dateOnly(now);
    final dueDay = dateOnly(due);
    if (today.isAfter(dueDay)) return _InstallmentState.overdue;
    if (today == dueDay) return _InstallmentState.dueToday;
    if (isDueSoon(dueDay, today)) return _InstallmentState.dueSoon;
    return _InstallmentState.upcoming;
  }

  Color _stateColor(BuildContext context, _InstallmentState state) {
    final colors = Theme.of(context).colorScheme;
    return switch (state) {
      _InstallmentState.paid => colors.primary,
      _InstallmentState.paidBeforeTracking => colors.primary,
      _InstallmentState.paidEarly => colors.secondary,
      _InstallmentState.overdue => colors.error,
      _InstallmentState.dueToday => colors.tertiary,
      _InstallmentState.dueSoon => colors.primary,
      _InstallmentState.upcoming => colors.outline,
    };
  }
}

enum _InstallmentState {
  paid,
  paidEarly,
  paidBeforeTracking,
  upcoming,
  dueSoon,
  dueToday,
  overdue,
}

IconData _stateIcon(_InstallmentState state) {
  return switch (state) {
    _InstallmentState.paid => Icons.check_circle,
    _InstallmentState.paidBeforeTracking => Icons.check_circle_outline,
    _InstallmentState.paidEarly => Icons.offline_bolt_outlined,
    _InstallmentState.overdue => Icons.error_outline,
    _InstallmentState.dueToday => Icons.today_outlined,
    _InstallmentState.dueSoon => Icons.schedule_outlined,
    _InstallmentState.upcoming => Icons.radio_button_unchecked,
  };
}

String _stateLabel(_InstallmentState state) {
  return switch (state) {
    _InstallmentState.paid => 'Paid',
    _InstallmentState.paidBeforeTracking => 'Already paid',
    _InstallmentState.paidEarly => 'Paid early',
    _InstallmentState.upcoming => 'Upcoming',
    _InstallmentState.dueSoon => 'Due soon',
    _InstallmentState.dueToday => 'Due today',
    _InstallmentState.overdue => 'Overdue',
  };
}

String _monthLabel(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

class EmiFormSheet extends ConsumerStatefulWidget {
  const EmiFormSheet({super.key, this.emi, this.initialEmiAmount});

  final Emi? emi;
  final String? initialEmiAmount;

  @override
  ConsumerState<EmiFormSheet> createState() => _EmiFormSheetState();
}

class _EmiFormSheetState extends ConsumerState<EmiFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.emi?.name ?? '');
  late final _provider = TextEditingController(
    text: widget.emi?.provider ?? '',
  );
  late final _principal = TextEditingController(
    text: widget.emi == null ? '' : rupeesText(widget.emi!.principalPaise),
  );
  late final _amount = TextEditingController(
    text:
        widget.initialEmiAmount ??
        (widget.emi == null ? '' : rupeesText(widget.emi!.emiAmountPaise)),
  );
  late final _tenure = TextEditingController(
    text: widget.emi?.tenureMonths.toString() ?? '12',
  );
  late final _notes = TextEditingController(text: widget.emi?.notes ?? '');
  late final _interest = TextEditingController(
    text: widget.emi?.interestRate?.toString() ?? '',
  );
  String? _scheduleError;
  late int? _paymentMethodId = widget.emi?.paymentMethodId;
  late DateTime _due =
      widget.emi?.nextDueDate ??
      DateTime(
        DateTime.now().year,
        DateTime.now().month + 1,
        DateTime.now().day,
      );
  late PaymentFrequency _frequency =
      widget.emi?.frequency ?? PaymentFrequency.monthly;
  late String _type = widget.emi?.type ?? 'Loan';
  late String _providerChoice = _providerChipFor(widget.emi?.provider);
  String? _selectedPaymentTile;
  late String _tenureChoice =
      const [
        '6',
        '12',
        '24',
        '36',
      ].contains(widget.emi?.tenureMonths.toString())
      ? widget.emi!.tenureMonths.toString()
      : widget.emi == null
      ? '12'
      : 'Custom';
  DateTime? _loadedNextDue;
  Animation<double>? _routeAnimation;
  bool _scheduleLoadStarted = false;
  late final Listenable _summaryInputs = Listenable.merge([
    _principal,
    _amount,
    _tenure,
    _paid,
  ]);

  @override
  void initState() {
    super.initState();
    _selectedPaymentTile = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.emi == null || _scheduleLoadStarted) return;
    final animation = ModalRoute.of(context)?.animation;
    if (_routeAnimation != animation) {
      _routeAnimation?.removeStatusListener(_onSheetAnimationStatus);
      _routeAnimation = animation;
      animation?.addStatusListener(_onSheetAnimationStatus);
    }
    if (animation == null || animation.status == AnimationStatus.completed) {
      _startScheduleLoad();
    }
  }

  void _onSheetAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _startScheduleLoad();
  }

  void _startScheduleLoad() {
    if (_scheduleLoadStarted) return;
    _scheduleLoadStarted = true;
    _routeAnimation?.removeStatusListener(_onSheetAnimationStatus);
    unawaited(_loadExistingSchedule());
  }

  Future<void> _loadExistingSchedule() async {
    try {
      final detail = await ref
          .read(financeRepositoryProvider)
          .emiDetail(widget.emi!.id);
      if (!mounted) return;
      setState(() {
        _tenure.text = detail.emi.tenureMonths.toString();
        _due = detail.nextUnpaidInstallment?.dueDate ?? detail.emi.nextDueDate;
        _loadedNextDue = _due;
        _paid.text = detail.paidInstallments.toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _scheduleError = 'Could not load the current EMI schedule.',
      );
    }
  }

  late final _paid = TextEditingController(
    text: widget.emi?.initialPaidInstallments.toString() ?? '0',
  );

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onSheetAnimationStatus);
    _name.dispose();
    _provider.dispose();
    _principal.dispose();
    _amount.dispose();
    _tenure.dispose();
    _notes.dispose();
    _interest.dispose();
    _paid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final methods = ref.watch(paymentMethodsProvider).valueOrNull ?? const [];
    final selectedPaymentTile =
        _selectedPaymentTile ??
        _tileForPaymentMethod(_paymentMethodId, methods);
    final frequencySegments = <ButtonSegment<PaymentFrequency>>[
      const ButtonSegment(
        value: PaymentFrequency.monthly,
        label: Text('Monthly'),
      ),
      const ButtonSegment(
        value: PaymentFrequency.quarterly,
        label: Text('Quarterly'),
      ),
      const ButtonSegment(
        value: PaymentFrequency.weekly,
        label: Text('Weekly'),
      ),
      if (_frequency == PaymentFrequency.yearly)
        const ButtonSegment(
          value: PaymentFrequency.yearly,
          label: Text('Yearly'),
        ),
    ];
    final availableHeight =
        (MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom) *
        0.92;
    return SafeArea(
      child: SizedBox(
        height: availableHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.emi == null ? 'New EMI' : 'Edit EMI',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 18),
                    children: [
                      _SelectorGroup(
                        label: 'TYPE',
                        child: SegmentedToggle<String>(
                          segments: const [
                            ButtonSegment(value: 'Loan', label: Text('Loan')),
                            ButtonSegment(
                              value: 'Phone/Product',
                              label: Text('Phone / Product'),
                            ),
                            ButtonSegment(
                              value: 'Credit Card',
                              label: Text('Credit Card'),
                            ),
                          ],
                          selected: {_type},
                          onSelectionChanged: (value) =>
                              setState(() => _type = value.first),
                        ),
                      ),
                      const SizedBox(height: 24),
                      HeroAmountInput(
                        controller: _amount,
                        label: 'MONTHLY EMI',
                        validator: amountText,
                        calculator: () =>
                            _openAmountCalculator(_amount, 'Monthly EMI'),
                      ),
                      const SizedBox(height: 20),
                      _FieldLabel('NAME'),
                      const SizedBox(height: 7),
                      TextFormField(
                        controller: _name,
                        decoration: _filledDecoration(
                          context,
                          hint: 'Loan name',
                          icon: Icons.account_balance_outlined,
                        ),
                        validator: requiredText,
                      ),
                      const SizedBox(height: 20),
                      _FieldLabel('LENDER'),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final provider in _knownProviders)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(provider),
                                  selected: _providerChoice == provider,
                                  onSelected: (_) => setState(
                                    () => _providerChoice = provider,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: const Text('Other'),
                                selected: _providerChoice == 'Other',
                                onSelected: (_) =>
                                    setState(() => _providerChoice = 'Other'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_providerChoice == 'Other') ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _provider,
                          decoration: _filledDecoration(
                            context,
                            hint: 'Lender name',
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _LabeledInput(
                              label: 'PRINCIPAL',
                              controller: _principal,
                              hint: 'Amount',
                              prefix: '₹ ',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator: amountText,
                              calculator: () => _openAmountCalculator(
                                _principal,
                                'Principal',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _LabeledInput(
                              label: 'INTEREST RATE (OPTIONAL)',
                              controller: _interest,
                              hint: '0',
                              suffix: '%',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator: _interestValidator,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _FieldLabel('TENURE'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final months in const ['6', '12', '24', '36'])
                            ChoiceChip(
                              label: Text(months),
                              selected: _tenureChoice == months,
                              onSelected: (_) => setState(() {
                                _tenureChoice = months;
                                _tenure.text = months;
                              }),
                            ),
                          ChoiceChip(
                            label: const Text('Custom'),
                            selected: _tenureChoice == 'Custom',
                            onSelected: (_) =>
                                setState(() => _tenureChoice = 'Custom'),
                          ),
                        ],
                      ),
                      if (_tenureChoice == 'Custom') ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _tenure,
                          keyboardType: TextInputType.number,
                          decoration: _filledDecoration(
                            context,
                            hint: 'Number of payments',
                          ),
                          validator: _positiveIntegerValidator,
                        ),
                      ],
                      const SizedBox(height: 20),
                      _SelectorGroup(
                        label: 'FREQUENCY',
                        child: SegmentedToggle<PaymentFrequency>(
                          segments: frequencySegments,
                          selected: {_frequency},
                          onSelectionChanged: (value) =>
                              setState(() => _frequency = value.first),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _DateSelector(
                                  value: _due,
                                  onChanged: (value) =>
                                      setState(() => _due = value),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _LabeledInput(
                              label: 'EMIS ALREADY PAID',
                              controller: _paid,
                              hint: '0',
                              keyboardType: TextInputType.number,
                              validator: _paidValidator,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const _FieldLabel('PAYMENT METHOD'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final option in _methodTiles)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: option == _methodTiles.last ? 0 : 8,
                                ),
                                child: _PaymentTile(
                                  label: option.$1,
                                  icon: option.$2,
                                  selected: selectedPaymentTile == option.$1,
                                  onTap: () => setState(() {
                                    _selectedPaymentTile = option.$1;
                                    _paymentMethodId = _methodIdForTile(
                                      option.$1,
                                      methods,
                                    );
                                  }),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const _FieldLabel('NOTES'),
                      const SizedBox(height: 7),
                      TextFormField(
                        controller: _notes,
                        maxLines: 3,
                        decoration: _filledDecoration(
                          context,
                          hint: 'Optional notes',
                        ),
                      ),
                      ListenableBuilder(
                        listenable: _summaryInputs,
                        builder: (context, _) {
                          final summary = _liveSummary();
                          if (summary == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: _EmiSummaryCard(summary: summary),
                          );
                        },
                      ),
                      if (_scheduleError != null) ...[
                        const SizedBox(height: 16),
                        _ValidationMessage(_scheduleError!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving...' : 'Save EMI'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _saving = false;

  Future<void> _openAmountCalculator(
    TextEditingController controller,
    String label,
  ) async {
    final value = await openCalculator(
      context,
      initial: controller.text,
      amountLabel: label,
    );
    if (value != null && mounted) controller.text = value;
  }

  _EmiFormSummary? _liveSummary() {
    final principal = _tryPaise(_principal.text);
    final installment = _tryPaise(_amount.text);
    final tenure = int.tryParse(_tenure.text);
    final paid = int.tryParse(_paid.text);
    if (principal == null ||
        installment == null ||
        tenure == null ||
        paid == null ||
        principal <= 0 ||
        installment <= 0 ||
        tenure <= 0 ||
        paid < 0 ||
        paid > tenure) {
      return null;
    }
    final remaining = tenure - paid;
    final endDate = remaining == 0
        ? _due
        : emiInstallmentDueDate(_due, remaining, _frequency);
    final total = installment * tenure;
    return _EmiFormSummary(
      endDate: endDate,
      remaining: remaining,
      totalPaise: total,
      interestPaise: total - principal,
    );
  }

  Future<void> _save() async {
    setState(() => _scheduleError = null);
    if (!_formKey.currentState!.validate()) return;
    late final int principalPaise;
    late final int emiAmountPaise;
    late final int tenure;
    final interest = double.tryParse(_interest.text.trim());
    try {
      principalPaise = parseRupeesToPaise(_principal.text);
      emiAmountPaise = parseRupeesToPaise(_amount.text);
      tenure = int.parse(_tenure.text.trim());
    } on FormatException catch (error) {
      setState(() => _scheduleError = error.message);
      return;
    }
    final paidCount = int.parse(_paid.text.trim());
    if (paidCount > tenure) {
      setState(
        () => _scheduleError = 'Already-paid EMIs cannot exceed tenure.',
      );
      return;
    }
    final schedule = calculateEmiSchedule(
      principalPaise: principalPaise,
      installmentPaise: emiAmountPaise,
      tenure: tenure,
      annualInterestRate: interest,
    );
    if (!schedule.isConsistent) {
      setState(() => _scheduleError = schedule.validationMessage);
      return;
    }
    setState(() => _saving = true);
    EmiDetail? detail;
    try {
      detail = widget.emi == null
          ? null
          : await ref.read(financeRepositoryProvider).emiDetail(widget.emi!.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _scheduleError = 'Could not load the current EMI schedule.';
      });
      return;
    }
    final recordedPaid = detail?.payments.length ?? 0;
    final baselinePaid = paidCount - recordedPaid;
    if (baselinePaid < 0) {
      setState(() {
        _saving = false;
        _scheduleError = 'Paid count cannot be less than recorded payments.';
      });
      return;
    }
    final startDate =
        widget.emi != null &&
            dateOnly(_due) ==
                dateOnly(_loadedNextDue ?? widget.emi!.nextDueDate)
        ? widget.emi!.startDate
        : _due;
    final item = EmisCompanion(
      id: widget.emi == null ? const Value.absent() : Value(widget.emi!.id),
      name: Value(_name.text.trim()),
      provider: Value(
        _providerChoice == 'Other'
            ? _provider.text.trim()
            : _providerValue(_providerChoice),
      ),
      principalPaise: Value(principalPaise),
      emiAmountPaise: Value(emiAmountPaise),
      interestRate: Value(interest),
      tenureMonths: Value(tenure),
      startDate: Value(startDate),
      nextDueDate: Value(_due),
      frequency: Value(_frequency),
      type: Value(_type),
      initialPaidInstallments: Value(baselinePaid),
      paymentMethodId: Value(_paymentMethodId),
      status: Value(
        paidCount >= tenure
            ? EmiStatus.completed
            : (widget.emi?.status ?? EmiStatus.active),
      ),
      notes: Value(_notes.text.trim().isEmpty ? null : _notes.text.trim()),
      updatedAt: Value(DateTime.now()),
    );
    if (!mounted) return;
    final repo = ref.read(financeRepositoryProvider);
    closeFinanceSheetAndSave(context, () async {
      await repo.saveEmi(item);
    }, errorMessage: 'Could not save this EMI.');
  }

  String? _interestValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null) return 'Enter a valid percentage';
    if (parsed < 0) return 'Interest rate cannot be negative';
    return null;
  }

  String? _paidValidator(String? value) {
    final count = int.tryParse(value?.trim() ?? '');
    if (count == null || count < 0) return 'Enter 0 or more';
    return null;
  }

  String? _positiveIntegerValidator(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed <= 0) {
      return 'Enter a number greater than zero';
    }
    return null;
  }
}

const _knownProviders = ['Axis', 'HDFC', 'SBI', 'ICICI', 'Bajaj'];
const _methodTiles = [
  ('AUTO-DEBIT', Icons.account_balance_outlined),
  ('UPI', Icons.qr_code_2),
  ('CARD', Icons.credit_card_outlined),
  ('CASH', Icons.payments_outlined),
];

String _providerChipFor(String? provider) {
  if (provider == null) return 'Axis';
  final value = provider.toLowerCase();
  if (value.contains('axis')) return 'Axis';
  if (value.contains('hdfc')) return 'HDFC';
  if (value == 'sbi' || value.contains('state bank')) return 'SBI';
  if (value.contains('icici')) return 'ICICI';
  if (value.contains('bajaj')) return 'Bajaj';
  return 'Other';
}

String _providerValue(String chip) => switch (chip) {
  'Axis' => 'Axis Bank',
  'HDFC' => 'HDFC Bank',
  'SBI' => 'SBI',
  'ICICI' => 'ICICI Bank',
  'Bajaj' => 'Bajaj Finance',
  _ => chip,
};

String? _tileForPaymentMethod(int? id, List<PaymentMethod> methods) {
  if (id == null) return null;
  final method = methods.where((item) => item.id == id).firstOrNull;
  if (method == null) return null;
  final label = '${method.label} ${method.kind}'.toLowerCase();
  if (label.contains('upi')) return 'UPI';
  if (label.contains('cash')) return 'CASH';
  if (label.contains('card')) return 'CARD';
  if (label.contains('bank') || label.contains('auto')) return 'AUTO-DEBIT';
  return null;
}

int? _methodIdForTile(String tile, List<PaymentMethod> methods) {
  final matches = methods.where((method) {
    final label = '${method.label} ${method.kind}'.toLowerCase();
    return switch (tile) {
      'AUTO-DEBIT' => label.contains('bank') || label.contains('auto'),
      'UPI' => label.contains('upi'),
      'CARD' => label.contains('card'),
      'CASH' => label.contains('cash'),
      _ => false,
    };
  });
  return matches.firstOrNull?.id;
}

int? _tryPaise(String value) {
  try {
    return parseRupeesToPaise(value);
  } on FormatException {
    return null;
  }
}

InputDecoration _filledDecoration(
  BuildContext context, {
  required String hint,
  IconData? icon,
}) {
  return financeFieldDecoration(context, hint: hint, icon: icon);
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => FinanceFieldLabel(text);
}

class _SelectorGroup extends StatelessWidget {
  const _SelectorGroup({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [_FieldLabel(label), const SizedBox(height: 8), child],
  );
}

class _LabeledInput extends StatelessWidget {
  const _LabeledInput({
    required this.label,
    required this.controller,
    required this.hint,
    required this.keyboardType,
    this.prefix,
    this.suffix,
    this.validator,
    this.calculator,
  });
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;
  final String? prefix;
  final String? suffix;
  final String? Function(String?)? validator;
  final VoidCallback? calculator;

  @override
  Widget build(BuildContext context) => FilledField(
    label: label,
    child: TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: financeFieldDecoration(context, hint: hint).copyWith(
        prefixText: prefix,
        suffixText: suffix,
        suffixIcon: calculator == null
            ? null
            : IconButton(
                tooltip: 'Calculator',
                icon: const Icon(Icons.calculate_outlined),
                onPressed: calculator,
              ),
      ),
      validator: validator,
    ),
  );
}

class _DateSelector extends StatelessWidget {
  const _DateSelector({required this.value, required this.onChanged});
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => DateTile(
    label: 'NEXT DUE DATE',
    value: value,
    onChanged: (date) {
      if (date != null) onChanged(date);
    },
  );
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      OptionTile(label: label, icon: icon, selected: selected, onTap: onTap);
}

class _EmiFormSummary {
  const _EmiFormSummary({
    required this.endDate,
    required this.remaining,
    required this.totalPaise,
    required this.interestPaise,
  });
  final DateTime endDate;
  final int remaining;
  final int totalPaise;
  final int interestPaise;
}

class _EmiSummaryCard extends StatelessWidget {
  const _EmiSummaryCard({required this.summary});
  final _EmiFormSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _SummaryLine('End date', formatDate(summary.endDate)),
          _SummaryLine('EMIs remaining', '${summary.remaining}'),
          _SummaryLine('Total payable', formatMoney(summary.totalPaise)),
          _SummaryLine('Total interest', formatMoney(summary.interestPaise)),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _ValidationMessage extends StatelessWidget {
  const _ValidationMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colors.onErrorContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
