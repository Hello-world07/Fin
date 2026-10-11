import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/app_theme.dart';
import '../../core/providers.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../domain/emi_math.dart';
import '../../domain/emi_payment_rules.dart';
import '../../domain/enums.dart';
import '../../domain/reminder_schedule.dart';
import '../reminders/section_reminders_sheet.dart';
import '../../shared/async_view.dart';
import '../../shared/calculator_sheet.dart';
import '../../shared/empty_state.dart';
import '../../shared/forms.dart';
import '../../shared/finance_form_widgets.dart';
import '../../shared/finance_display_widgets.dart';
import '../../shared/emi_visual_data.dart';
import '../../shared/notched_navigation_bar.dart';
import '../../shared/screen_header.dart';
import 'emi_payoff_simulation.dart';

class EmisScreen extends ConsumerStatefulWidget {
  const EmisScreen({super.key});

  @override
  ConsumerState<EmisScreen> createState() => _EmisScreenState();
}

class _EmisScreenState extends ConsumerState<EmisScreen> {
  bool _showCompleted = false;
  bool _hintVisible = false;
  bool _hintChecked = false;
  bool _celebrating = false;
  bool _fabExpanded = true;
  final _pageController = PageController(initialPage: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showHintOnce());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _showHintOnce() async {
    if (_hintChecked || !_pageController.hasClients) return;
    _hintChecked = true;
    const key = 'emi.completed_swipe_left_hint_seen';
    final db = ref.read(databaseProvider);
    final seen = await (db.select(
      db.settings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    if (!mounted || seen != null || !_pageController.hasClients) return;
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: 'true'),
        );
    if (!mounted || !_pageController.hasClients) return;
    setState(() => _hintVisible = true);
    await _pageController.animateTo(
      _pageController.offset + 24,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
    if (!mounted || !_pageController.hasClients) return;
    await _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _hintVisible = false);
  }

  Future<void> _markPaid(
    EmiDetail detail, {
    bool fromSwipe = false,
    bool forceEarly = false,
  }) async {
    final installment = detail.nextUnpaidInstallment;
    if (installment == null || detail.emi.status == EmiStatus.paused) return;
    final days = dateOnly(
      installment.dueDate,
    ).difference(dateOnly(DateTime.now())).inDays;
    final confirmed = fromSwipe && days <= 10
        ? true
        : await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(
                forceEarly || days > 10
                    ? 'Pay early?'
                    : 'Mark ${_emiName(detail.emi.name)} paid?',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AmountText(detail.amountForInstallment(installment.number)),
                  Text(
                    'Due ${formatDate(installment.dueDate)}. This records a payment in FinKeep; it does not transfer money.',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Mark paid'),
                ),
              ],
            ),
          );
    if (confirmed != true || !mounted) return;
    try {
      final repository = ref.read(financeRepositoryProvider);
      final recorded = await repository.markEmiPaid(
        detail.emi.id,
        expectedDueDate: installment.dueDate,
        expectedInstallmentNumber: installment.number,
        paidEarly:
            forceEarly ||
            !isWithinEmiPaymentWindow(installment.dueDate, DateTime.now()),
      );
      if (!mounted) return;
      if (!recorded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Installment already recorded or unavailable'),
          ),
        );
        return;
      }
      final updated = await repository.emiDetail(detail.emi.id);
      if (!mounted) return;
      if (updated.remainingInstallments == 0) {
        setState(() => _celebrating = true);
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _celebrating = false);
        });
      }
      final payment = updated.payments
          .where((p) => p.installmentNumber == installment.number)
          .firstOrNull;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: const Text('Marked paid.'),
          action: payment == null
              ? null
              : SnackBarAction(
                  label: 'Undo',
                  onPressed: () async {
                    try {
                      await repository.revertEmiPayment(
                        detail.emi.id,
                        payment.id,
                      );
                    } catch (_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not undo payment'),
                          ),
                        );
                      }
                    }
                  },
                ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not record payment')),
        );
      }
    }
  }

  Future<void> _showTileActions(
    EmiDetail detail, {
    required bool completed,
  }) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!completed && detail.emi.status != EmiStatus.paused) ...[
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Mark paid'),
                onTap: () => Navigator.pop(sheetContext, 'paid'),
              ),
              ListTile(
                leading: const Icon(Icons.bolt_outlined),
                title: const Text('Pay early'),
                onTap: () => Navigator.pop(sheetContext, 'early'),
              ),
            ],
            if (!completed)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () => Navigator.pop(sheetContext, 'edit'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(completed ? 'View' : 'Open details'),
              onTap: () => Navigator.pop(sheetContext, 'view'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'paid':
        await _markPaid(detail);
      case 'early':
        await _markPaid(detail, forceEarly: true);
      case 'edit':
        openFinanceSheet(context, EmiFormSheet(emi: detail.emi));
      case 'view':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EmiDetailScreen(detail.emi.id)),
        );
      case 'delete':
        await _deleteFromList(detail);
      default:
        break;
    }
  }

  Future<void> _deleteFromList(EmiDetail detail) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${_emiName(detail.emi.name)}?'),
        content: const Text(
          'This EMI will move to Deleted and can be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final repository = ref.read(financeRepositoryProvider);
      await repository.deleteEmi(detail.emi.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: const Text('Moved to Deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await repository.restoreEmi(detail.emi.id);
            },
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not delete EMI')));
      }
    }
  }

  Future<void> _markAllPaid(List<EmiDetail> items) async {
    final selected = items
        .where((item) => item.emi.status != EmiStatus.paused)
        .map((item) => item.emi.id)
        .toSet();
    final chosen = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Mark all paid',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .55,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final item in items)
                        CheckboxListTile(
                          value: selected.contains(item.emi.id),
                          onChanged: item.emi.status == EmiStatus.paused
                              ? null
                              : (value) => update(() {
                                  if (value == true) {
                                    selected.add(item.emi.id);
                                  } else {
                                    selected.remove(item.emi.id);
                                  }
                                }),
                          title: Text(_emiName(item.emi.name)),
                          subtitle: Text(
                            'Due ${formatDate(item.nextUnpaidInstallment!.dueDate)}',
                          ),
                          secondary: AmountText(
                            item.amountForInstallment(
                              item.nextUnpaidInstallment!.number,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(
                            sheetContext,
                            Set<int>.of(selected),
                          ),
                    child: const Text('Confirm payments'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || chosen == null || chosen.isEmpty) return;
    final repository = ref.read(financeRepositoryProvider);
    final recorded = <(int, int)>[];
    var completedAny = false;
    for (final item in items.where((item) => chosen.contains(item.emi.id))) {
      final installment = item.nextUnpaidInstallment!;
      try {
        final saved = await repository.markEmiPaid(
          item.emi.id,
          expectedDueDate: installment.dueDate,
          expectedInstallmentNumber: installment.number,
          paidEarly: !isWithinEmiPaymentWindow(
            installment.dueDate,
            DateTime.now(),
          ),
        );
        if (!saved) continue;
        final updated = await repository.emiDetail(item.emi.id);
        final payment = updated.payments
            .where((p) => p.installmentNumber == installment.number)
            .firstOrNull;
        if (payment != null) recorded.add((item.emi.id, payment.id));
        completedAny |= updated.remainingInstallments == 0;
      } catch (_) {
        /* Continue with the remaining confirmed items. */
      }
    }
    if (!mounted) return;
    if (completedAny) {
      setState(() => _celebrating = true);
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _celebrating = false);
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(
          '${recorded.length} ${recorded.length == 1 ? 'EMI' : 'EMIs'} marked paid.',
        ),
        action: recorded.isEmpty
            ? null
            : SnackBarAction(
                label: 'Undo',
                onPressed: () async {
                  for (final (emiId, paymentId) in recorded) {
                    try {
                      await repository.revertEmiPayment(emiId, paymentId);
                    } catch (_) {
                      /* An already reverted payment should not block the rest. */
                    }
                  }
                },
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : Padding(
              padding: EdgeInsets.only(
                bottom: NotchedNavigationMetrics.fabBottomPadding,
              ),
              child: FloatingActionButton.extended(
                isExtended: _fabExpanded,
                onPressed: () =>
                    openFinanceSheet(context, const EmiFormSheet()),
                icon: const Icon(Icons.add),
                label: const Text('Add EMI'),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(
        children: [
          const ScreenHeader(
            title: Text('EMIs & Loans'),
            actions: [
              Tooltip(
                message: 'Reminders',
                child: TooltipVisibility(
                  visible: false,
                  child: SectionReminderButton(type: FinanceReminderType.emi),
                ),
              ),
            ],
          ),
          Expanded(
            child: AsyncView(
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
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _showHintOnce();
                });
                return Column(
                  children: [
                    _EmiTabs(
                      controller: _pageController,
                      activeCount: active.length,
                      completedCount: completed.length,
                      showCompleted: _showCompleted,
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification.metrics.axis != Axis.vertical) {
                                return false;
                              }
                              final expand = notification.metrics.pixels <= 8;
                              if (_fabExpanded != expand) {
                                setState(() => _fabExpanded = expand);
                              }
                              return false;
                            },
                            child: PageView(
                              controller: _pageController,
                              onPageChanged: (index) =>
                                  setState(() => _showCompleted = index == 1),
                              children: [
                                _buildPage(context, active, completed, false),
                                _buildPage(context, active, completed, true),
                              ],
                            ),
                          ),
                          if (_hintVisible)
                            Positioned(
                              top: 12,
                              right: 20,
                              child: IgnorePointer(
                                child: Chip(
                                  label: const Text(
                                    'Swipe left for completed EMIs',
                                  ),
                                  side: BorderSide.none,
                                  backgroundColor: AppTheme.colorsOf(
                                    context,
                                  ).selectedFill,
                                ),
                              ),
                            ),
                          if (_celebrating)
                            const Positioned.fill(
                              child: IgnorePointer(child: _EmiCelebration()),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(
    BuildContext context,
    List<EmiDetail> active,
    List<EmiDetail> completed,
    bool showCompleted,
  ) {
    final visible = showCompleted ? completed : active;
    final arcColors = <int, Color>{
      for (var i = 0; i < active.length; i++)
        active[i].emi.id: _emiArcColor(context, i),
      for (var i = 0; i < completed.length; i++)
        completed[i].emi.id: _emiArcColor(context, i),
    };
    final rows = <(DateTime?, EmiDetail?)>[];
    if (showCompleted) {
      for (final item in completed) {
        rows.add((null, item));
      }
    } else {
      final grouped = <DateTime, List<EmiDetail>>{};
      for (final item in active) {
        final day = dateOnly(item.nextUnpaidInstallment!.dueDate);
        grouped.putIfAbsent(day, () => []).add(item);
      }
      for (final entry in grouped.entries) {
        rows.add((entry.key, null));
        for (final item in entry.value) {
          rows.add((null, item));
        }
      }
    }
    return CustomScrollView(
      key: PageStorageKey(showCompleted ? 'emi-completed' : 'emi-active'),
      slivers: [
        if (!showCompleted)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(children: [_EmiHero(items: active)]),
            ),
          ),
        if (visible.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: EmptyState(
                icon: showCompleted
                    ? Icons.check_circle_outline
                    : Icons.account_balance_outlined,
                title: showCompleted
                    ? 'No completed EMIs yet'
                    : 'No active EMIs',
                message: showCompleted
                    ? 'Swipe left to go back'
                    : 'Add an EMI to see its installments and progress.',
                actionLabel: showCompleted ? null : 'Add EMI',
                onAction: showCompleted
                    ? null
                    : () => openFinanceSheet(context, const EmiFormSheet()),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              if (row.$1 != null) {
                final day = row.$1!;
                final group = active
                    .where(
                      (item) =>
                          dateOnly(item.nextUnpaidInstallment!.dueDate) == day,
                    )
                    .toList();
                return _DueDayHeader(
                  day: day,
                  items: group,
                  onMarkAll: () => _markAllPaid(group),
                );
              }
              final detail = row.$2!;
              return Padding(
                key: ValueKey(detail.emi.id),
                padding: const EdgeInsets.only(bottom: 10),
                child: showCompleted || detail.emi.status == EmiStatus.paused
                    ? _EmiRow(
                        detail: detail,
                        completed: showCompleted,
                        onMarkPaid: null,
                        onLongPress: () =>
                            _showTileActions(detail, completed: showCompleted),
                        arcColor: arcColors[detail.emi.id],
                      )
                    : _SwipePayTile(
                        detail: detail,
                        onPaid: () => _markPaid(detail, fromSwipe: true),
                        child: _EmiRow(
                          detail: detail,
                          completed: false,
                          arcColor: arcColors[detail.emi.id],
                          onMarkPaid: () => _markPaid(detail),
                          onLongPress: () =>
                              _showTileActions(detail, completed: false),
                        ),
                      ),
              );
            },
          ),
        ),
        if (!showCompleted && active.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(child: _EmiMonthSection(items: active)),
          ),
        if (!showCompleted && active.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(child: _EmiIncomeCard(items: active)),
          ),
        if (!showCompleted && active.length >= 2)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(child: _EmiPayoffPlanner(items: active)),
          ),
        SliverToBoxAdapter(
          child: SizedBox(
            height:
                NotchedNavigationMetrics.contentPadding(context) -
                NotchedNavigationMetrics.contentGap +
                88,
          ),
        ),
      ],
    );
  }
}

class _EmiTabs extends StatelessWidget {
  const _EmiTabs({
    required this.controller,
    required this.activeCount,
    required this.completedCount,
    required this.showCompleted,
  });
  final PageController controller;
  final int activeCount;
  final int completedCount;
  final bool showCompleted;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: SizedBox(
      height: 48,
      child: LayoutBuilder(
        builder: (context, constraints) => AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final page = controller.hasClients
                ? (controller.page ?? (showCompleted ? 1.0 : 0.0))
                : (showCompleted ? 1.0 : 0.0);
            final half = constraints.maxWidth / 2;
            final primary = Theme.of(context).colorScheme.primary;
            final secondary = AppTheme.colorsOf(context).secondaryText;
            return Stack(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => controller.animateToPage(
                          0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        ),
                        child: Center(
                          child: Text(
                            'Active ($activeCount)',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: page < .5 ? primary : secondary,
                                  fontWeight: page < .5
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => controller.animateToPage(
                          1,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        ),
                        child: Center(
                          child: Text(
                            'Completed ($completedCount)',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: page >= .5 ? primary : secondary,
                                  fontWeight: page >= .5
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: page.clamp(0.0, 1.0) * half + 20,
                  bottom: 0,
                  width: half - 40,
                  height: 2,
                  child: ColoredBox(color: primary),
                ),
              ],
            );
          },
        ),
      ),
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
    final finalDue = items.isEmpty
        ? null
        : items
              .map(
                (item) => item.installments
                    .where((part) => !part.isPaid)
                    .last
                    .dueDate,
              )
              .reduce((a, b) => a.isAfter(b) ? a : b);
    final now = dateOnly(DateTime.now());
    final months = finalDue == null
        ? 0
        : math.max(
            0,
            (finalDue.year - now.year) * 12 +
                finalDue.month -
                now.month -
                (finalDue.day < now.day ? 1 : 0),
          );
    final visual = buildEmiVisualData(items, now);
    final current = visual.months.isEmpty ? 0 : visual.months.first.amountPaise;
    final next = visual.months.length < 2 ? 0 : visual.months[1].amountPaise;
    final colors = AppTheme.colorsOf(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.homeCardOutline),
      ),
      child: items.isEmpty
          ? Text(
              'No active EMIs',
              style: Theme.of(context).textTheme.titleMedium,
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _EmiDebtRing(items: items, months: months),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: AmountText(
                          remaining,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      Text(
                        'left',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Free by ${formatDate(finalDue!)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 3,
                        runSpacing: 1,
                        children: [
                          Text(
                            'This month',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          AmountText(
                            current,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          Text(
                            '− Next month',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          AmountText(
                            next,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

String _emiName(String name) => displayName(name);

Color _emiArcColor(BuildContext context, int index) {
  final base = HSLColor.fromColor(AppTheme.colorsOf(context).emi);
  return base
      .withHue((base.hue - 12 + (index % 6) * 5).clamp(0.0, 360.0))
      .withLightness((.38 + (index % 3) * .08).clamp(0.0, 1.0))
      .toColor();
}

class _EmiDebtRing extends StatefulWidget {
  const _EmiDebtRing({required this.items, required this.months});
  final List<EmiDetail> items;
  final int months;
  @override
  State<_EmiDebtRing> createState() => _EmiDebtRingState();
}

class _EmiDebtRingState extends State<_EmiDebtRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  )..forward();
  int? _selected;
  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final values = [
      for (final item in widget.items) item.remainingBalancePaise,
    ];
    final colors = [
      for (var i = 0; i < widget.items.length; i++) _emiArcColor(context, i),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapDown: (details) {
            final delta = details.localPosition - const Offset(56, 56);
            if (delta.distance < 39 || delta.distance > 56) return;
            final angle =
                (math.atan2(delta.dy, delta.dx) + math.pi / 2 + 2 * math.pi) %
                (2 * math.pi);
            final total = values.fold<int>(0, (n, v) => n + v);
            var cursor = 0.0;
            for (var i = 0; i < values.length; i++) {
              cursor +=
                  2 *
                  math.pi *
                  (total == 0 ? 1 / values.length : values[i] / total);
              if (angle <= cursor) {
                setState(() => _selected = i);
                break;
              }
            }
          },
          child: Tooltip(
            message: 'Tap an arc for its EMI and remaining amount',
            child: SizedBox.square(
              dimension: 112,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _grow,
                      builder: (context, _) => CustomPaint(
                        size: const Size.square(112),
                        painter: _EmiDebtPainter(
                          values,
                          colors,
                          AppTheme.colorsOf(context).outline,
                          AppTheme.colorsOf(context).surface,
                          MediaQuery.disableAnimationsOf(context)
                              ? 1
                              : _grow.value,
                        ),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${widget.months} mo',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'to go',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_selected != null && _selected! < widget.items.length)
          SizedBox(
            width: 112,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 3,
              children: [
                Text(
                  _emiName(widget.items[_selected!].emi.name),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                AmountText(
                  widget.items[_selected!].remainingBalancePaise,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EmiDebtPainter extends CustomPainter {
  const _EmiDebtPainter(
    this.values,
    this.colors,
    this.track,
    this.gapColor,
    this.grow,
  );
  final List<int> values;
  final List<Color> colors;
  final Color track, gapColor;
  final double grow;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(7);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    final total = values.fold<int>(0, (n, v) => n + v);
    if (total <= 0) return;
    final gap = 2 / (rect.width / 2);
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = 2 * math.pi * values[i] / total;
      final visible = math.max(0.0, sweep - gap);
      if (visible > 0) {
        canvas.drawArc(
          rect,
          start + gap / 2,
          visible * grow,
          false,
          paint..color = colors[i],
        );
      }
      canvas.drawArc(
        rect,
        start - gap / 2,
        gap,
        false,
        paint..color = gapColor,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _EmiDebtPainter old) =>
      old.grow != grow ||
      old.track != track ||
      old.gapColor != gapColor ||
      old.values.toString() != values.toString() ||
      old.colors.toString() != colors.toString();
}

class _DueDayHeader extends StatelessWidget {
  const _DueDayHeader({
    required this.day,
    required this.items,
    required this.onMarkAll,
  });
  final DateTime day;
  final List<EmiDetail> items;
  final VoidCallback onMarkAll;
  @override
  Widget build(BuildContext context) {
    final days = day.difference(dateOnly(DateTime.now())).inDays;
    final tokens = AppTheme.colorsOf(context);
    final urgency = days < 0
        ? tokens.pay
        : days <= 7
        ? tokens.emi
        : tokens.text;
    final total = items.fold<int>(
      0,
      (sum, item) =>
          sum + item.amountForInstallment(item.nextUnpaidInstallment!.number),
    );
    final lenders = <String, int>{};
    for (final item in items) {
      final name = _emiName(
        item.emi.provider?.isNotEmpty == true ? item.emi.provider! : 'Other',
      );
      lenders.update(
        name,
        (amount) =>
            amount +
            item.amountForInstallment(item.nextUnpaidInstallment!.number),
        ifAbsent: () =>
            item.amountForInstallment(item.nextUnpaidInstallment!.number),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 3,
                  runSpacing: 2,
                  children: [
                    Text(
                      '${DateFormat('EEE dd MMM').format(day)} · ${items.length} ${items.length == 1 ? 'EMI' : 'EMIs'} · ${days < 0
                          ? '${-days} days overdue'
                          : days == 0
                          ? 'today'
                          : 'in $days days'} ·',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: urgency,
                      ),
                    ),
                    AmountText(
                      total,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: urgency,
                      ),
                    ),
                  ],
                ),
              ),
              if (days <= 7 &&
                  items.any((e) => e.emi.status != EmiStatus.paused))
                TextButton(
                  onPressed: onMarkAll,
                  child: const Text('Mark all paid'),
                ),
            ],
          ),
          if (lenders.length >= 2) ...[
            const SizedBox(height: 3),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final entry in lenders.entries)
                  Tooltip(
                    message: '${entry.key} installments due ${formatDate(day)}',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: urgency.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Wrap(
                        spacing: 3,
                        children: [
                          Text(
                            entry.key,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          AmountText(
                            entry.value,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EmiMonthSection extends StatefulWidget {
  const _EmiMonthSection({required this.items});
  final List<EmiDetail> items;
  @override
  State<_EmiMonthSection> createState() => _EmiMonthSectionState();
}

class _EmiMonthSectionState extends State<_EmiMonthSection> {
  bool _debtLeft = false;

  @override
  Widget build(BuildContext context) {
    final visual = buildEmiVisualData(widget.items, dateOnly(DateTime.now()));
    final months = visual.months;
    final max = months.fold<int>(0, (n, item) => math.max(n, item.amountPaise));
    final tokens = AppTheme.colorsOf(context);
    final reliefs = visual.reliefs;
    final groupedRelief = <DateTime, List<EmiRelief>>{};
    for (final relief in reliefs) {
      final from = DateTime(relief.month.year, relief.month.month + 1);
      groupedRelief.putIfAbsent(from, () => []).add(relief);
    }
    final biggest = groupedRelief.entries.isEmpty
        ? null
        : groupedRelief.entries.reduce(
            (a, b) =>
                a.value.fold<int>(0, (n, r) => n + r.amountPaise) >=
                    b.value.fold<int>(0, (n, r) => n + r.amountPaise)
                ? a
                : b,
          );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: AppTheme.homeCardOutline),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your EMI load',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          SegmentedToggle<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Monthly load')),
              ButtonSegment(value: true, label: Text('Debt left')),
            ],
            selected: {_debtLeft},
            onSelectionChanged: (value) =>
                setState(() => _debtLeft = value.first),
            filled: true,
            selectedBackground: tokens.selectedFill,
            selectedForeground: tokens.text,
          ),
          const SizedBox(height: 12),
          if (_debtLeft)
            _EmiDebtChart(items: widget.items)
          else ...[
            RepaintBoundary(
              child: LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < months.length; i++)
                      Builder(
                        builder: (context) {
                          final month = months[i];
                          final step = max == 0
                              ? 0
                              : (month.amountPaise * 4 / max).ceil().clamp(
                                  0,
                                  4,
                                );
                          final detail = month.parts.isEmpty
                              ? 'No EMI due'
                              : month.parts
                                    .map(
                                      (part) =>
                                          '${_emiName(part.$1)} ${formatMoney(part.$2)}',
                                    )
                                    .join(' + ');
                          return SizedBox(
                            width: (constraints.maxWidth - 24) / 4,
                            child: Tooltip(
                              triggerMode: TooltipTriggerMode.tap,
                              message:
                                  '${_monthLabel(month.month).substring(0, 3)}: $detail',
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 82,
                                ),
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: tokens.emi.withValues(
                                    alpha: .07 + step * .06,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_monthLabel(month.month).substring(0, 3)}${i == 0 || month.month.month == 1 ? ' ${month.month.year}' : ''}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(fontSize: 12),
                                    ),
                                    const SizedBox(height: 4),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: AmountText(
                                        month.amountPaise,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                    if (month.dropped)
                                      Icon(
                                        Icons.south,
                                        size: 15,
                                        color: tokens.emi,
                                        semanticLabel: 'Load drops',
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.south, size: 15, color: tokens.emi),
                const SizedBox(width: 4),
                Text(
                  'Load drops',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            for (final group in groupedRelief.entries)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 3,
                  children: [
                    Text(
                      'From ${_monthLabel(group.key).substring(0, 3)} ${group.key.year}:',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    AmountText(
                      group.value.fold<int>(0, (n, r) => n + r.amountPaise),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'less (${group.value.map((r) => _emiName(r.name)).join(' + ')} end${group.value.length == 1 ? 's' : ''})',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            if (biggest != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 3,
                children: [
                  Text(
                    'Biggest relief: ${biggest.value.map((r) => _emiName(r.name)).join(' + ')} frees',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  AmountText(
                    biggest.value.fold<int>(0, (n, r) => n + r.amountPaise),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'from ${_monthLabel(biggest.key).substring(0, 3)}${biggest.key.year == DateTime.now().year ? '' : ' ${biggest.key.year}'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DebtPoint {
  const _DebtPoint(this.month, this.balancePaise, this.closed);
  final DateTime month;
  final int balancePaise;
  final List<String> closed;
}

class _EmiDebtChart extends StatefulWidget {
  const _EmiDebtChart({required this.items});
  final List<EmiDetail> items;

  @override
  State<_EmiDebtChart> createState() => _EmiDebtChartState();
}

class _EmiDebtChartState extends State<_EmiDebtChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  )..forward();

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  List<_DebtPoint> _points() {
    final today = dateOnly(DateTime.now());
    final start = DateTime(today.year, today.month);
    final due = <DateTime, int>{};
    final closing = <DateTime, List<String>>{};
    var total = 0;
    DateTime? last;
    for (final detail in widget.items) {
      total += detail.remainingBalancePaise;
      final unpaid = detail.installments.where((e) => !e.isPaid).toList();
      for (final installment in unpaid) {
        final month = DateTime(
          installment.dueDate.year,
          installment.dueDate.month,
        );
        due[month] =
            (due[month] ?? 0) + detail.amountForInstallment(installment.number);
      }
      if (unpaid.isNotEmpty) {
        final end = unpaid.last.dueDate;
        final month = DateTime(end.year, end.month);
        closing.putIfAbsent(month, () => []).add(_emiName(detail.emi.name));
        if (last == null || end.isAfter(last)) last = end;
      }
    }
    if (last == null) return [_DebtPoint(start, 0, const [])];
    final count = ((last.year - start.year) * 12 + last.month - start.month)
        .clamp(0, 240);
    final points = <_DebtPoint>[
      _DebtPoint(DateTime(start.year, start.month - 1), total, const []),
    ];
    var remaining = total;
    for (var i = 0; i <= count; i++) {
      final month = DateTime(start.year, start.month + i);
      remaining = math.max(0, remaining - (due[month] ?? 0));
      points.add(_DebtPoint(month, remaining, closing[month] ?? const []));
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    final points = _points();
    final tokens = AppTheme.colorsOf(context);
    final end = points.last.month;
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 192,
            child: LayoutBuilder(
              builder: (context, size) => GestureDetector(
                onTapUp: (event) {
                  final index =
                      ((event.localPosition.dx / size.maxWidth) *
                              (points.length - 1))
                          .round()
                          .clamp(0, points.length - 1);
                  final point = points[index];
                  final names = point.closed.isEmpty
                      ? 'Debt left'
                      : '${point.closed.join(' + ')} closes';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '$names ${DateFormat('MMM yyyy').format(point.month)} - ${formatMoney(point.balancePaise)}',
                      ),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
                child: AnimatedBuilder(
                  animation: _draw,
                  builder: (context, _) => CustomPaint(
                    size: Size(size.maxWidth, 192),
                    painter: _DebtAreaPainter(
                      values: points.map((e) => e.balancePaise).toList(),
                      closures: [
                        for (var i = 0; i < points.length; i++)
                          if (points[i].closed.isNotEmpty) i,
                      ],
                      color: tokens.emi,
                      track: tokens.outline,
                      progress: _draw.value,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AmountText(points.first.balancePaise, compact: true),
              const Text('Tap curve for month details'),
              AmountText(0, compact: true),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final index in [1, points.length ~/ 2, points.length - 1])
                Text(
                  DateFormat('MMM yy').format(points[index].month),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Debt-free ${DateFormat('MMM yyyy').format(end)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _DebtAreaPainter extends CustomPainter {
  const _DebtAreaPainter({
    required this.values,
    required this.closures,
    required this.color,
    required this.track,
    required this.progress,
  });
  final List<int> values;
  final List<int> closures;
  final Color color;
  final Color track;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    const top = 12.0;
    final bottom = size.height - 12;
    final maxValue = values.reduce(math.max).toDouble();
    final dx = size.width / (values.length - 1);
    Offset point(int i) => Offset(
      i * dx,
      bottom - (maxValue == 0 ? 0 : values[i] / maxValue) * (bottom - top),
    );
    final count = ((values.length - 1) * progress).ceil().clamp(
      1,
      values.length - 1,
    );
    final line = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i <= count; i++) {
      final prev = point(i - 1);
      final next = point(i);
      line.cubicTo(
        (prev.dx + next.dx) / 2,
        prev.dy,
        (prev.dx + next.dx) / 2,
        next.dy,
        next.dx,
        next.dy,
      );
    }
    final area = Path.from(line)
      ..lineTo(point(count).dx, bottom)
      ..lineTo(0, bottom)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: .16));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
    canvas.drawLine(
      Offset(0, bottom),
      Offset(size.width, bottom),
      Paint()..color = track,
    );
    for (final i in closures) {
      if (i > count) continue;
      canvas.drawCircle(point(i), 5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _DebtAreaPainter old) =>
      progress != old.progress ||
      color != old.color ||
      track != old.track ||
      !listEquals(values, old.values) ||
      !listEquals(closures, old.closures);
}

class _EmiIncomeCard extends ConsumerStatefulWidget {
  const _EmiIncomeCard({required this.items});
  final List<EmiDetail> items;

  @override
  ConsumerState<_EmiIncomeCard> createState() => _EmiIncomeCardState();
}

class _EmiIncomeCardState extends ConsumerState<_EmiIncomeCard> {
  static const _key = 'emi.monthlyIncomePaise';
  int? _income;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final row = await (db.select(
      db.settings,
    )..where((table) => table.key.equals(_key))).getSingleOrNull();
    if (mounted) setState(() => _income = int.tryParse(row?.value ?? ''));
  }

  Future<void> _edit() async {
    Future<void>? sheetClosed;
    final value = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        sheetClosed ??= ModalRoute.of(sheetContext)?.completed;
        return _IncomeAmountSheet(initialIncome: _income);
      },
    );
    if (!mounted || value == null) return;
    if (sheetClosed != null) await sheetClosed;
    if (!mounted) return;
    final db = ref.read(databaseProvider);
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: _key, value: value.toString()),
        );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _income = value);
    });
  }

  Future<void> _remove() async {
    final db = ref.read(databaseProvider);
    await (db.delete(
      db.settings,
    )..where((table) => table.key.equals(_key))).go();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _income = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.colorsOf(context);
    final months = buildEmiVisualData(
      widget.items,
      dateOnly(DateTime.now()),
    ).months;
    final month = months.first;
    final share = _income == null || _income == 0
        ? 0.0
        : month.amountPaise / _income!;
    final nextShare = _income == null || _income == 0
        ? 0.0
        : months[1].amountPaise / _income!;
    final shareLabel = privacyAmountsHidden
        ? hiddenAmount
        : '${(share * 100).round()}%';
    final nextShareLabel = privacyAmountsHidden
        ? hiddenAmount
        : '${(nextShare * 100).round()}%';
    final level = share < .3
        ? 'Comfortable'
        : share < .4
        ? 'Watchful'
        : share <= .5
        ? 'High'
        : 'Very high';
    final color = share < .3
        ? tokens.receive
        : share < .4
        ? tokens.emi
        : share <= .5
        ? Color.lerp(tokens.emi, tokens.pay, .45)!
        : tokens.pay;
    final zones = <(String, Color, bool)>[
      ('Comfortable <30%', tokens.receive, share < .3),
      ('Watchful 30-40%', tokens.emi, share >= .3 && share < .4),
      (
        'High 40-50%',
        Color.lerp(tokens.emi, tokens.pay, .45)!,
        share >= .4 && share <= .5,
      ),
      ('Very high >50%', tokens.pay, share > .5),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.outline),
        borderRadius: BorderRadius.circular(24),
      ),
      child: _income == null
          ? Column(
              key: const ValueKey('income-empty'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Income & EMIs',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'See how much of your income goes to EMIs - stays on this phone',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: _edit, child: const Text('Add income')),
              ],
            )
          : Column(
              key: const ValueKey('income-gauge'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Income & EMIs',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Center(
                  child: RepaintBoundary(
                    child: SizedBox(
                      width: 180,
                      height: 106,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          CustomPaint(
                            size: const Size(180, 100),
                            painter: _IncomeGaugePainter(
                              fraction: share.clamp(0, 1),
                              color: color,
                              track: tokens.surfaceContainer,
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                shareLabel,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              Text(
                                privacyAmountsHidden ? 'Private' : level,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final zone in zones)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: zone.$3
                              ? zone.$2.withValues(alpha: .16)
                              : tokens.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 8, color: zone.$2),
                            const SizedBox(width: 4),
                            Text(
                              zone.$1,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: zone.$3
                                        ? tokens.text
                                        : tokens.secondaryText,
                                    fontWeight: zone.$3
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Your EMIs use $shareLabel of your income. Lenders often prefer under roughly 40-50%.',
                ),
                const SizedBox(height: 4),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('This month: '),
                    AmountText(month.amountPaise),
                    const Text(' of '),
                    AmountText(_income!),
                  ],
                ),
                Text('Next month: $nextShareLabel'),
                Row(
                  children: [
                    OutlinedButton(onPressed: _edit, child: const Text('Edit')),
                    const SizedBox(width: 16),
                    OutlinedButton(
                      onPressed: _remove,
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _IncomeAmountSheet extends StatefulWidget {
  const _IncomeAmountSheet({required this.initialIncome});

  final int? initialIncome;

  @override
  State<_IncomeAmountSheet> createState() => _IncomeAmountSheetState();
}

class _IncomeAmountSheetState extends State<_IncomeAmountSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialIncome == null ? '' : rupeesText(widget.initialIncome!),
  );
  final FocusNode _focusNode = FocusNode();
  String? _error;

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    int amount;
    try {
      amount = parseRupeesToPaise(_controller.text);
    } on FormatException {
      setState(() => _error = 'Enter an amount above zero');
      return;
    }
    _focusNode.unfocus();
    Navigator.pop(context, amount);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      24,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Monthly income', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Saved on this phone. Not included in reports.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        HeroAmountInput(
          controller: _controller,
          focusNode: _focusNode,
          label: 'MONTHLY INCOME',
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submit,
            child: const Text('Save income'),
          ),
        ),
      ],
    ),
  );
}

class _IncomeGaugePainter extends CustomPainter {
  const _IncomeGaugePainter({
    required this.fraction,
    required this.color,
    required this.track,
  });
  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(8, 8, size.width - 16, (size.width - 16));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, paint..color = track);
    canvas.drawArc(
      rect,
      math.pi,
      math.pi * fraction,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _IncomeGaugePainter old) =>
      fraction != old.fraction || color != old.color || track != old.track;
}

class _EmiPayoffPlanner extends StatefulWidget {
  const _EmiPayoffPlanner({required this.items});
  final List<EmiDetail> items;

  @override
  State<_EmiPayoffPlanner> createState() => _EmiPayoffPlannerState();
}

class _EmiPayoffPlannerState extends State<_EmiPayoffPlanner> {
  int _extraPaise = 0;
  bool _reuseFreed = true;

  Future<void> _customExtra() async {
    final controller = TextEditingController();
    final form = GlobalKey<FormState>();
    Future<void>? sheetClosed;
    final amount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        sheetClosed ??= ModalRoute.of(sheetContext)?.completed;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            24,
            20,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                HeroAmountInput(
                  controller: controller,
                  label: 'EXTRA PER MONTH',
                  validator: (value) {
                    try {
                      if (parseRupeesToPaise(value ?? '') > 0) return null;
                    } catch (_) {}
                    return 'Enter an amount above zero';
                  },
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    if (form.currentState!.validate()) {
                      Navigator.pop(
                        sheetContext,
                        parseRupeesToPaise(controller.text),
                      );
                    }
                  },
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (sheetClosed != null) await sheetClosed;
    controller.dispose();
    if (mounted && amount != null) setState(() => _extraPaise = amount);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.colorsOf(context);
    final now = dateOnly(DateTime.now());
    final plan = simulateEmiPayoff(
      items: widget.items,
      today: now,
      extraPerMonthPaise: _extraPaise,
      reuseFreedPayments: _reuseFreed,
    );
    final hasRates = plan.hasRates;
    final sorted = plan.ordered;
    final thisMonthPaise = buildEmiVisualData(
      widget.items,
      now,
    ).months.first.amountPaise;
    final skipped = plan.targetId == null
        ? null
        : sorted.takeWhile((item) => item.emi.id != plan.targetId).where((
            item,
          ) {
            final dueThisMonth = item.installments
                .where(
                  (i) =>
                      !i.isPaid &&
                      i.dueDate.year == now.year &&
                      i.dueDate.month == now.month,
                )
                .fold<int>(
                  0,
                  (sum, i) => sum + item.amountForInstallment(i.number),
                );
            return dueThisMonth >= item.remainingBalancePaise;
          }).firstOrNull;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.outline),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pay off faster',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'You pay '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: AmountText(
                    thisMonthPaise,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const TextSpan(
                  text:
                      ' this month. Keep paying that, plus any extra, and put money freed up by finished EMIs on the next loan to become debt-free sooner.',
                ),
              ],
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            hasRates
                ? 'Order: highest known interest first. Unknown rates follow by smallest balance.'
                : 'Order: smallest remaining balance first because no rates are recorded.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < sorted.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(width: 26, child: Text('${i + 1}.')),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_emiName(sorted[i].emi.name)),
                        if (sorted[i].emi.id == plan.targetId)
                          Chip(
                            label: const Text('Extra goes here first'),
                            side: BorderSide.none,
                            backgroundColor: tokens.selectedFill,
                          ),
                        if (sorted[i].emi.id == plan.targetId &&
                            skipped != null)
                          Text(
                            '${_emiName(skipped.emi.name)} is already paid by this month\'s installment, so extra goes to ${_emiName(sorted[i].emi.name)}.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  AmountText(sorted[i].remainingBalancePaise),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Extra per month',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final rupees in [500, 1000, 2000, 5000])
                ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [AmountText(rupees * 100)],
                  ),
                  selected: _extraPaise == rupees * 100,
                  onSelected: (_) => setState(() => _extraPaise = rupees * 100),
                ),
              ActionChip(label: const Text('Custom'), onPressed: _customExtra),
              if (_extraPaise > 0)
                ActionChip(
                  label: const Text('Clear extra'),
                  onPressed: () => setState(() => _extraPaise = 0),
                ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reuse freed-up EMI money'),
            value: _reuseFreed,
            onChanged: (value) => setState(() => _reuseFreed = value),
          ),
          const SizedBox(height: 8),
          Text(
            'As scheduled: Debt-free ${DateFormat('MMM yyyy').format(plan.originalEnd)}',
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _reuseFreed ? 'Keep paying ' : 'With extra only: ',
                ),
                if (_reuseFreed)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: AmountText(
                      thisMonthPaise,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                TextSpan(
                  text: _reuseFreed
                      ? ' every month: ${DateFormat('MMM yyyy').format(plan.plannedEnd)}'
                      : DateFormat('MMM yyyy').format(plan.plannedEnd),
                ),
              ],
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (plan.monthsSooner > 0)
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: plan.monthsSooner),
              duration: const Duration(milliseconds: 400),
              builder: (context, months, _) => Chip(
                label: Text(
                  '$months ${months == 1 ? 'month' : 'months'} sooner',
                ),
                side: BorderSide.none,
                backgroundColor: tokens.selectedFill,
              ),
            )
          else
            Text(
              "Extra money on a short EMI doesn't move your last date. Try reusing freed-up money or a bigger amount.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if ((plan.peakExtraMonth?.extraPaise ?? 0) > 0)
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'That averages '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: AmountText(
                      plan.averageExtraPaise,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const TextSpan(
                    text: ' more than scheduled per month, up to ',
                  ),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: AmountText(
                      plan.peakExtraMonth!.extraPaise,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextSpan(
                    text:
                        ' in ${DateFormat('MMM yyyy').format(plan.peakExtraMonth!.month)}.',
                  ),
                ],
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('You pay '),
              AmountText(plan.totalPaidPaise),
              const Text(' in total'),
            ],
          ),
          if (hasRates)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Estimated interest saved '),
                  AmountText(plan.interestSavedPaise),
                ],
              ),
            )
          else
            const Text(
              "Without interest, finishing sooner doesn't save money, it frees up your cash earlier. Add interest rates to see interest saved.",
            ),
          const SizedBox(height: 8),
          Text(
            'Some lenders charge prepayment fees. Check before paying extra.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SwipePayTile extends StatefulWidget {
  const _SwipePayTile({
    required this.detail,
    required this.onPaid,
    required this.child,
  });
  final EmiDetail detail;
  final Future<void> Function() onPaid;
  final Widget child;
  @override
  State<_SwipePayTile> createState() => _SwipePayTileState();
}

class _SwipePayTileState extends State<_SwipePayTile> {
  Offset? _start;
  int? _pointer;
  double _drag = 0;
  bool _ticked = false;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final threshold = constraints.maxWidth * .55;
      final installment = widget.detail.nextUnpaidInstallment!;
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Listener(
          onPointerDown: (event) {
            if (_pointer != null) return;
            _pointer = event.pointer;
            _start = event.localPosition;
            _ticked = false;
          },
          onPointerMove: (event) {
            if (event.pointer != _pointer || _start == null) return;
            final dx = event.localPosition.dx - _start!.dx;
            final dy = event.localPosition.dy - _start!.dy;
            if (dx <= 0 || dx.abs() <= dy.abs()) return;
            final next = dx.clamp(0.0, constraints.maxWidth * .75);
            if (!_ticked && next >= threshold) {
              _ticked = true;
              HapticFeedback.selectionClick();
            }
            setState(() => _drag = next);
          },
          onPointerUp: (event) {
            if (event.pointer != _pointer) return;
            final confirmed = _drag >= threshold;
            setState(() => _drag = 0);
            _pointer = null;
            _start = null;
            if (confirmed) unawaited(widget.onPaid());
          },
          onPointerCancel: (event) {
            if (event.pointer != _pointer) return;
            setState(() => _drag = 0);
            _pointer = null;
            _start = null;
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: AppTheme.colorsOf(context).selectedFill,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: AppTheme.colorsOf(context).receive,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Mark paid',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: AppTheme.colorsOf(context).receive,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          AmountText(
                            widget.detail.amountForInstallment(
                              installment.number,
                            ),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          Text(
                            '${_monthLabel(installment.dueDate)} installment',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(_drag, 0),
                child: widget.child,
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _EmiRow extends StatelessWidget {
  const _EmiRow({
    required this.detail,
    required this.completed,
    required this.onMarkPaid,
    this.onLongPress,
    this.arcColor,
  });

  final EmiDetail detail;
  final bool completed;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onLongPress;
  final Color? arcColor;

  @override
  Widget build(BuildContext context) {
    final emi = detail.emi;
    final nextInstallment = detail.nextUnpaidInstallment;
    final due = nextInstallment?.dueDate;
    final days = due == null
        ? 0
        : dateOnly(due).difference(dateOnly(DateTime.now())).inDays;
    final urgency = days < 0
        ? AppTheme.colorsOf(context).pay
        : days <= 7
        ? AppTheme.colorsOf(context).emi
        : AppTheme.colorsOf(context).secondaryText;
    final lastPayment = detail.payments.isEmpty
        ? null
        : detail.payments
              .map((payment) => payment.paidOn)
              .reduce((a, b) => a.isAfter(b) ? a : b);
    final completedOn = lastPayment ?? emi.updatedAt;
    final tokens = AppTheme.colorsOf(context);
    final avatarColor = arcColor ?? tokens.secondaryText;
    return Material(
      color: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppTheme.homeCardOutline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onLongPress: onLongPress,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => EmiDetailScreen(emi.id))),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: avatarColor.withValues(alpha: .16),
                    child: completed
                        ? Icon(Icons.check, color: avatarColor)
                        : Text(
                            _emiName(emi.name).characters.first.toUpperCase(),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: avatarColor,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _emiName(emi.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: completed
                                    ? tokens.secondaryText
                                    : tokens.text,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          completed
                              ? '${emi.tenureMonths} installments'
                              : '${_emiName(emi.provider?.isNotEmpty == true ? emi.provider! : emi.type)} · ${emi.frequency.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: tokens.secondaryText),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 90,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: AmountText(
                            completed
                                ? detail.paidPaise
                                : detail.amountForInstallment(
                                    nextInstallment!.number,
                                  ),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 2),
                        MiniProgressRing(
                          progress: emi.tenureMonths == 0
                              ? 0
                              : detail.paidInstallments / emi.tenureMonths,
                          size: 34,
                          strokeWidth: 3,
                          child: Center(
                            child: Text(
                              '${detail.remainingInstallments} left',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 3,
                runSpacing: 2,
                children: [
                  Text(
                    '${detail.paidInstallments} of ${emi.tenureMonths} paid',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.secondaryText,
                    ),
                  ),
                  if (!completed) ...[
                    Text('−', style: Theme.of(context).textTheme.bodySmall),
                    AmountText(
                      detail.remainingBalancePaise,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text('left', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (completed)
                    StatusPill(
                      label: 'Completed on ${formatDate(completedOn)}',
                      color: tokens.secondaryText,
                    )
                  else if (days <= 7)
                    StatusPill(
                      label: days < 0
                          ? 'Overdue by ${-days} days'
                          : days == 0
                          ? 'Due today'
                          : days == 1
                          ? 'Due tomorrow'
                          : 'in $days days',
                      color: urgency,
                    ),
                  if (!completed && detail.remainingInstallments <= 2)
                    StatusPill(label: 'Closing soon', color: tokens.emi),
                  if (!completed && days <= 7 && onMarkPaid != null)
                    TextButton(
                      onPressed: onMarkPaid,
                      child: const Text('Mark paid'),
                    ),
                ],
              ),
            ],
          ),
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
                    if (detail.nextUnpaidInstallment != null) ...[
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
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppTheme.colorsOf(context).secondaryText,
          ),
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
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppTheme.colorsOf(context).secondaryText,
        ),
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
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: null,
            style: FilledButton.styleFrom(
              disabledBackgroundColor: widget.enabled
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
              disabledForegroundColor: AppTheme.heroTextOf(context),
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
        builder: (context, child) => Stack(
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: SizedBox(
                    width: 120,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _controller.value,
                      child: Container(height: 4, color: AppTheme.accent),
                    ),
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
                      ? AppTheme.colorsOf(context).receive
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
                                      ?.copyWith(
                                        color: AppTheme.colorsOf(
                                          context,
                                        ).secondaryText,
                                      ),
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
    final extra = (_fraction * 10000 * 100).round();
    final plan = simulateEmiPayoff(
      items: [detail],
      today: DateTime.now(),
      extraPerMonthPaise: extra,
      reuseFreedPayments: false,
    );
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
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Extra per month '),
            AmountText(extra, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
        Slider(
          value: _fraction,
          onChanged: (value) => setState(() => _fraction = value),
        ),
        Text(
          'New end ${DateFormat('MMM yyyy').format(plan.plannedEnd)} · ${plan.monthsSooner} ${plan.monthsSooner == 1 ? 'month' : 'months'} sooner',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (detail.emi.interestRate != null && detail.emi.interestRate! > 0)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Estimated interest saved '),
              AmountText(
                plan.interestSavedPaise,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
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
                      AppTheme.colorsOf(context).receive,
                      AppTheme.colorsOf(context).emi,
                      AppTheme.colorsOf(context).subscriptions,
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
                              prefix: '${activeAmountFormatter.value.symbol} ',
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
    if (!mounted) return;
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
