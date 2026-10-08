import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/app_theme.dart';
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

class EmisScreen extends ConsumerStatefulWidget {
  const EmisScreen({super.key});

  @override
  ConsumerState<EmisScreen> createState() => _EmisScreenState();
}

class _EmisScreenState extends ConsumerState<EmisScreen> {
  bool _showCompleted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EMIs & Loans')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openFinanceSheet(context, const EmiFormSheet()),
        icon: const Icon(Icons.add),
        label: const Text('Add EMI'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: AsyncView(
        value: ref.watch(emiDetailsProvider),
        builder: (items) {
          final active =
              items
                  .where(
                    (item) =>
                        item.emi.status != EmiStatus.completed &&
                        item.nextUnpaidInstallment != null,
                  )
                  .toList()
                ..sort(
                  (a, b) => a.nextUnpaidInstallment!.dueDate.compareTo(
                    b.nextUnpaidInstallment!.dueDate,
                  ),
                );
          final completed = items
              .where(
                (item) =>
                    item.emi.status == EmiStatus.completed ||
                    item.nextUnpaidInstallment == null,
              )
              .toList();
          final visible = _showCompleted ? completed : active;
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, _emiListBottomPadding),
            children: [
              _EmiHero(items: active),
              const SizedBox(height: 24),
              _EmiTabs(
                activeCount: active.length,
                completedCount: completed.length,
                showCompleted: _showCompleted,
                onChanged: (value) => setState(() => _showCompleted = value),
              ),
              const SizedBox(height: 14),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: EmptyState(
                    icon: _showCompleted
                        ? Icons.check_circle_outline
                        : Icons.account_balance_outlined,
                    title: _showCompleted
                        ? 'No completed EMIs yet'
                        : 'No active EMIs',
                    message: _showCompleted
                        ? 'Paid-off loans will appear here.'
                        : 'Add an EMI to see its installments and progress.',
                    actionLabel: _showCompleted ? null : 'Add EMI',
                    onAction: _showCompleted
                        ? null
                        : () => openFinanceSheet(context, const EmiFormSheet()),
                  ),
                )
              else
                for (final item in visible) ...[
                  _EmiRow(detail: item, completed: _showCompleted),
                  const Divider(height: 1),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _EmiTabs extends StatelessWidget {
  const _EmiTabs({
    required this.activeCount,
    required this.completedCount,
    required this.showCompleted,
    required this.onChanged,
  });
  final int activeCount;
  final int completedCount;
  final bool showCompleted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<bool>(
    segments: [
      ButtonSegment(value: false, label: Text('Active ($activeCount)')),
      ButtonSegment(value: true, label: Text('Completed ($completedCount)')),
    ],
    selected: {showCompleted},
    showSelectedIcon: false,
    onSelectionChanged: (value) => onChanged(value.first),
    style: SegmentedButton.styleFrom(
      selectedBackgroundColor: AppTheme.selectedFill,
      selectedForegroundColor: AppTheme.seed,
      shape: const StadiumBorder(),
    ),
  );
}

class _EmiHero extends StatelessWidget {
  const _EmiHero({required this.items});

  final List<EmiDetail> items;

  @override
  Widget build(BuildContext context) {
    final remaining = items.fold<int>(
      0,
      (sum, item) => sum + item.remainingBalancePaise,
    );
    final monthly = items.fold<int>(
      0,
      (sum, item) => sum + item.scheduledInstallmentPaise,
    );
    final total = items.fold<int>(
      0,
      (sum, item) => sum + item.totalRepaymentPaise,
    );
    final paid = items.fold<int>(0, (sum, item) => sum + item.paidPaise);
    final finalDue = items.isEmpty
        ? null
        : items
              .map((item) => item.installments.last.dueDate)
              .reduce((a, b) => a.isAfter(b) ? a : b);
    final now = dateOnly(DateTime.now());
    final months = finalDue == null
        ? 0
        : (finalDue.year - now.year) * 12 +
              finalDue.month -
              now.month -
              (finalDue.day < now.day ? 1 : 0);
    final countdown = finalDue == null
        ? 'No active debt'
        : months > 0
        ? 'Debt-free in $months ${months == 1 ? 'month' : 'months'}'
        : finalDue.isBefore(now)
        ? 'Final date passed'
        : 'Debt-free this month';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL REMAINING',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppTheme.mutedText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          AmountText(
            remaining,
            style: Theme.of(
              context,
            ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeroFigure(
                  label: 'Monthly commitment',
                  value: formatMoney(monthly),
                ),
              ),
              Expanded(
                child: _HeroFigure(
                  label: 'Debt-free date',
                  value: finalDue == null ? '—' : formatDate(finalDue),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            countdown,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.mutedText),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: total == 0 ? 0 : (paid / total).clamp(0, 1),
            minHeight: 5,
            borderRadius: BorderRadius.circular(3),
            backgroundColor: Theme.of(context).colorScheme.outlineVariant,
          ),
        ],
      ),
    );
  }
}

class _HeroFigure extends StatelessWidget {
  const _HeroFigure({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: AppTheme.mutedText),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    ],
  );
}

const double _emiListBottomPadding = 88;

class _EmiRow extends StatelessWidget {
  const _EmiRow({required this.detail, required this.completed});

  final EmiDetail detail;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final emi = detail.emi;
    final nextInstallment = detail.nextUnpaidInstallment;
    final due = nextInstallment?.dueDate;
    final days = due == null
        ? 0
        : dateOnly(due).difference(dateOnly(DateTime.now())).inDays;
    final urgency = days < 0
        ? AppTheme.pay
        : days <= 7
        ? AppTheme.emi
        : AppTheme.receive;
    final lastPayment = detail.payments.isEmpty
        ? null
        : detail.payments
              .map((payment) => payment.paidOn)
              .reduce((a, b) => a.isAfter(b) ? a : b);
    final completedOn = lastPayment ?? emi.updatedAt;
    return InkWell(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => EmiDetailScreen(emi.id))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: completed
                  ? AppTheme.fieldFill
                  : AppTheme.selectedFill,
              child: completed
                  ? const Icon(Icons.check, color: AppTheme.seed)
                  : Text(
                      displayName(
                        emi.provider?.isNotEmpty == true
                            ? emi.provider!
                            : emi.name,
                      ).characters.first.toUpperCase(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppTheme.seed,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName(emi.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: completed ? AppTheme.mutedText : null,
                              ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AmountText(
                        completed
                            ? detail.paidPaise
                            : detail.amountForInstallment(
                                nextInstallment!.number,
                              ),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    completed
                        ? '${emi.tenureMonths} installments · Total paid'
                        : '${emi.provider?.isNotEmpty == true ? emi.provider : emi.type} · per ${emi.frequency.label.toLowerCase()}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppTheme.mutedText),
                  ),
                  if (completed) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Completed on ${formatDate(completedOn)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.mutedText,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    if (emi.tenureMonths <= 24)
                      SegmentedProgressStrip(
                        installments: emi.tenureMonths,
                        paidInstallments: detail.paidInstallments,
                      )
                    else
                      LinearProgressIndicator(
                        value: detail.paidInstallments / emi.tenureMonths,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Due ${formatDate(due!)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        StatusPill(
                          label: relativeDueText(due, DateTime.now()),
                          color: urgency,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${detail.remainingInstallments} left · ${formatMoney(detail.remainingBalancePaise)} remaining',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.mutedText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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
  bool _saving = false;
  bool _celebrating = false;

  Future<void> _record(EmiDetail detail, {required bool early}) async {
    final installment = detail.nextUnpaidInstallment;
    if (installment == null || _saving) return;
    setState(() => _saving = true);
    try {
      final recorded = await ref
          .read(financeRepositoryProvider)
          .markEmiPaid(
            widget.id,
            expectedDueDate: installment.dueDate,
            expectedInstallmentNumber: installment.number,
            paidEarly: early,
          );
      if (!mounted) return;
      if (!recorded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Installment already recorded')),
        );
        return;
      }
      final updated = await ref
          .read(financeRepositoryProvider)
          .emiDetail(widget.id);
      if (!mounted) return;
      final payment = updated.payments
          .where((item) => item.installmentNumber == installment.number)
          .firstOrNull;
      if (updated.remainingInstallments == 0) {
        setState(() => _celebrating = true);
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _celebrating = false);
        });
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            updated.remainingInstallments == 0
                ? 'EMI completed. Marked paid.'
                : 'Marked paid.',
          ),
          action: payment == null
              ? null
              : SnackBarAction(
                  label: 'Undo',
                  onPressed: () => _revert(payment.id),
                ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not record payment: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _revert(int paymentId) async {
    try {
      final reverted = await ref
          .read(financeRepositoryProvider)
          .revertEmiPayment(widget.id, paymentId);
      if (mounted && !reverted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment was already reverted')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not undo payment: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(emiDetailsProvider);
    final detail = details.valueOrNull
        ?.where((item) => item.emi.id == widget.id)
        .firstOrNull;
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
                    await ref
                        .read(financeRepositoryProvider)
                        .deleteEmi(widget.id);
                    if (context.mounted) Navigator.pop(context);
                  },
          ),
        ],
      ),
      body: detail == null
          ? Center(
              child: details.hasError || details.hasValue
                  ? const Text('EMI not found')
                  : const CircularProgressIndicator(),
            )
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                  children: [
                    _EmiOverview(detail: detail),
                    const SizedBox(height: 28),
                    Text(
                      'Installments',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _InstallmentTimeline(detail: detail, onRevert: _revert),
                    if (detail.emi.interestRate != null &&
                        detail.nextUnpaidInstallment != null) ...[
                      const SizedBox(height: 28),
                      _EmiWhatIf(detail: detail),
                    ],
                  ],
                ),
                if (_celebrating)
                  const Positioned.fill(
                    child: IgnorePointer(child: _EmiCelebration()),
                  ),
              ],
            ),
      bottomNavigationBar:
          detail == null ||
              detail.nextUnpaidInstallment == null ||
              detail.emi.status == EmiStatus.paused
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _HoldToPayButton(
                      label:
                          'Mark ${_monthLabel(detail.nextUnpaidInstallment!.dueDate)} paid',
                      busy: _saving,
                      enabled: isWithinEmiPaymentWindow(
                        detail.nextUnpaidInstallment!.dueDate,
                        DateTime.now(),
                      ),
                      onConfirmed: () => _record(detail, early: false),
                    ),
                    if (!isWithinEmiPaymentWindow(
                      detail.nextUnpaidInstallment!.dueDate,
                      DateTime.now(),
                    ))
                      TextButton.icon(
                        onPressed: _saving ? null : () => _confirmEarly(detail),
                        icon: const Icon(Icons.bolt_outlined),
                        label: const Text('Pay early'),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _confirmEarly(EmiDetail detail) async {
    final installment = detail.nextUnpaidInstallment!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark paid early?'),
        content: Text(
          '${formatMoney(detail.amountForInstallment(installment.number))} due ${formatDate(installment.dueDate)}. This records a payment in FinKeep; it does not transfer money.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mark paid'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _record(detail, early: true);
  }
}

class _EmiOverview extends StatelessWidget {
  const _EmiOverview({required this.detail});

  final EmiDetail detail;

  @override
  Widget build(BuildContext context) {
    final percent = (detail.progress * 100).clamp(0, 100).round();
    return Column(
      children: [
        MiniProgressRing(
          progress: detail.progress,
          size: 140,
          strokeWidth: 11,
          backgroundColor: Theme.of(context).colorScheme.outlineVariant,
          child: Text(
            '$percent%',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          displayName(detail.emi.name),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          '${detail.paidInstallments} paid · ${detail.remainingInstallments} left',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.mutedText),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _OverviewMetric(
                label: 'Paid',
                value: formatMoney(detail.paidPaise),
              ),
            ),
            Expanded(
              child: _OverviewMetric(
                label: 'Remaining',
                value: formatMoney(detail.remainingBalancePaise),
              ),
            ),
            Expanded(
              child: _OverviewMetric(
                label: 'Total payable',
                value: formatMoney(detail.totalRepaymentPaise),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: AppTheme.mutedText),
      ),
      const SizedBox(height: 5),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );
}

class _HoldToPayButton extends StatefulWidget {
  const _HoldToPayButton({
    required this.label,
    required this.busy,
    required this.enabled,
    required this.onConfirmed,
  });
  final String label;
  final bool busy;
  final bool enabled;
  final VoidCallback onConfirmed;

  @override
  State<_HoldToPayButton> createState() => _HoldToPayButtonState();
}

class _HoldToPayButtonState extends State<_HoldToPayButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 850),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed &&
            !widget.busy &&
            widget.enabled) {
          widget.onConfirmed();
          _controller.reset();
        }
      });

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Hold to ${widget.label.toLowerCase()}',
    child: GestureDetector(
      onTapDown: widget.busy || !widget.enabled
          ? null
          : (_) => _controller.forward(from: 0),
      onTapUp: (_) => _controller.reset(),
      onTapCancel: () => _controller.reset(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Stack(
          children: [
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: null,
                style: FilledButton.styleFrom(
                  disabledBackgroundColor: widget.enabled
                      ? AppTheme.seed
                      : Theme.of(context).colorScheme.outlineVariant,
                  disabledForegroundColor: AppTheme.onHero,
                  shape: const StadiumBorder(),
                ),
                icon: widget.busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.touch_app_outlined),
                label: Text(widget.busy ? 'Recording...' : widget.label),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: FractionallySizedBox(
                    widthFactor: _controller.value,
                    child: Container(height: 4, color: AppTheme.accent),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InstallmentTimeline extends StatelessWidget {
  const _InstallmentTimeline({required this.detail, required this.onRevert});

  final EmiDetail detail;
  final ValueChanged<int> onRevert;

  @override
  Widget build(BuildContext context) {
    final paymentsByInstallment = {
      for (final payment in detail.payments) payment.installmentNumber: payment,
    };
    final children = <Widget>[];
    final now = DateTime.now();
    final installments = detail.installments;
    for (var index = 0; index < installments.length; index++) {
      final installment = installments[index];
      final payment = paymentsByInstallment[installment.number];
      final state =
          payment == null &&
              installment.number <= detail.emi.initialPaidInstallments
          ? _InstallmentState.paidBeforeTracking
          : _installmentState(installment.dueDate, now, payment);
      children.add(
        Stack(
          children: [
            if (index < installments.length - 1)
              Positioned(
                left: 14,
                top: 22,
                bottom: 0,
                child: Container(
                  width: 2,
                  color: installment.isPaid && installments[index + 1].isPaid
                      ? AppTheme.receive
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 30,
                  child: Icon(
                    _stateIcon(state),
                    size: 22,
                    color: _stateColor(context, state),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _monthLabel(installment.dueDate),
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            StatusPill(
                              label:
                                  !installment.isPaid &&
                                      installment.number ==
                                          detail
                                              .nextUnpaidInstallment
                                              ?.number &&
                                      state != _InstallmentState.overdue
                                  ? 'Due next'
                                  : _stateLabel(state),
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
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${payment?.paidEarly == true ? 'Scheduled' : 'Due'}: '
                          '${formatDate(installment.dueDate)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (payment != null) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Paid ${formatDateTime(payment.paidOn)}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppTheme.mutedText),
                                ),
                              ),
                              IconButton(
                                tooltip:
                                    'Revert installment ${installment.number}',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => onRevert(payment.id),
                                icon: const Icon(Icons.undo, size: 18),
                              ),
                            ],
                          ),
                        ],
                        if (state == _InstallmentState.paidBeforeTracking) ...[
                          const SizedBox(height: 3),
                          Text(
                            'Paid before tracking began',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
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

class _EmiWhatIf extends StatefulWidget {
  const _EmiWhatIf({required this.detail});
  final EmiDetail detail;

  @override
  State<_EmiWhatIf> createState() => _EmiWhatIfState();
}

class _EmiWhatIfState extends State<_EmiWhatIf> {
  double _fraction = 0;

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final rate =
        (detail.emi.interestRate ?? 0) /
        100 /
        switch (detail.emi.frequency) {
          PaymentFrequency.weekly => 52,
          PaymentFrequency.quarterly => 4,
          PaymentFrequency.yearly => 1,
          _ => 12,
        };
    final unpaid = detail.installments.where((item) => !item.isPaid).toList();
    final planned = unpaid
        .map((item) => detail.amountForInstallment(item.number))
        .toList();
    var principal = 0.0;
    for (var index = planned.length - 1; index >= 0; index--) {
      principal = (principal + planned[index]) / (1 + rate);
    }
    final extra = (principal * _fraction).round();
    var balance = math.max(0.0, principal - extra);
    var projectedPayments = 0;
    var projectedTotal = extra;
    for (final amount in planned) {
      if (balance <= 0.5) break;
      balance *= 1 + rate;
      final paid = math.min(balance, amount.toDouble());
      projectedTotal += paid.round();
      balance -= paid;
      projectedPayments++;
    }
    final saved = math.max(0, detail.remainingBalancePaise - projectedTotal);
    final periodsSooner = planned.length - projectedPayments;
    final monthsSooner = switch (detail.emi.frequency) {
      PaymentFrequency.weekly => (periodsSooner * 7 / 30).round(),
      PaymentFrequency.quarterly => periodsSooner * 3,
      PaymentFrequency.yearly => periodsSooner * 12,
      _ => periodsSooner,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What if',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          'Pay extra ${formatMoney(extra)} now',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Slider(
          value: _fraction,
          onChanged: (value) => setState(() => _fraction = value),
        ),
        Text(
          '$monthsSooner ${monthsSooner == 1 ? 'month' : 'months'} sooner · Estimated ${formatMoney(saved)} interest saved',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppTheme.mutedText),
        ),
      ],
    );
  }
}

class _EmiCelebration extends StatelessWidget {
  const _EmiCelebration();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1300),
      builder: (context, progress, child) => Stack(
        children: [
          for (var index = 0; index < 18; index++)
            Positioned(
              left:
                  constraints.maxWidth / 2 +
                  math.cos(index * math.pi * 2 / 18) *
                      progress *
                      constraints.maxWidth *
                      0.45,
              top:
                  constraints.maxHeight * 0.28 +
                  math.sin(index * math.pi * 2 / 18) *
                      progress *
                      constraints.maxHeight *
                      0.3 +
                  progress * progress * 100,
              child: Opacity(
                opacity: 1 - progress,
                child: Transform.rotate(
                  angle: progress * math.pi * 3,
                  child: Container(
                    width: 8,
                    height: 16,
                    color: [
                      AppTheme.accent,
                      AppTheme.receive,
                      AppTheme.emi,
                      AppTheme.subscriptions,
                    ][index % 4],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
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
  const EmiFormSheet({
    super.key,
    this.emi,
    this.initialEmiAmount,
    this.initialPrincipal,
    this.initialInterestRate,
    this.initialName,
    this.initialTenureMonths,
    this.initialFrequency,
    this.initialDueDate,
  });

  final Emi? emi;
  final String? initialEmiAmount;
  final String? initialPrincipal;
  final String? initialInterestRate;
  final String? initialName;
  final int? initialTenureMonths;
  final PaymentFrequency? initialFrequency;
  final DateTime? initialDueDate;

  @override
  ConsumerState<EmiFormSheet> createState() => _EmiFormSheetState();
}

class _EmiFormSheetState extends ConsumerState<EmiFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.emi?.name ?? widget.initialName ?? '',
  );
  late final _provider = TextEditingController(
    text: widget.emi?.provider ?? '',
  );
  late final _principal = TextEditingController(
    text: widget.emi == null
        ? widget.initialPrincipal ?? ''
        : rupeesText(widget.emi!.principalPaise),
  );
  late final _amount = TextEditingController(
    text:
        widget.initialEmiAmount ??
        (widget.emi == null ? '' : rupeesText(widget.emi!.emiAmountPaise)),
  );
  late final _tenure = TextEditingController(
    text:
        widget.emi?.tenureMonths.toString() ??
        widget.initialTenureMonths?.toString() ??
        '12',
  );
  late final _notes = TextEditingController(text: widget.emi?.notes ?? '');
  late final _interest = TextEditingController(
    text:
        widget.emi?.interestRate?.toString() ??
        widget.initialInterestRate ??
        '',
  );
  String? _scheduleError;
  late int? _paymentMethodId = widget.emi?.paymentMethodId;
  late DateTime _due =
      widget.emi?.nextDueDate ??
      widget.initialDueDate ??
      DateTime(
        DateTime.now().year,
        DateTime.now().month + 1,
        DateTime.now().day,
      );
  late PaymentFrequency _frequency =
      widget.emi?.frequency ??
      widget.initialFrequency ??
      PaymentFrequency.monthly;
  late String _type = widget.emi?.type ?? 'Loan';
  late String _providerChoice = _providerChipFor(widget.emi?.provider);
  String? _selectedPaymentTile;
  late String _tenureChoice =
      const ['6', '12', '24', '36'].contains(
        (widget.emi?.tenureMonths ?? widget.initialTenureMonths)?.toString(),
      )
      ? (widget.emi?.tenureMonths ?? widget.initialTenureMonths).toString()
      : widget.emi == null
      ? widget.initialTenureMonths == null
            ? '12'
            : 'Custom'
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
