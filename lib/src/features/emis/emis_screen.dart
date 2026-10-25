import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/gestures.dart' show VelocityTracker;
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
import '../../domain/emi_affordability.dart';
import '../../domain/emi_payment_rules.dart';
import '../../domain/enums.dart';
import '../../domain/reminder_schedule.dart';
import '../reminders/section_reminders_sheet.dart';
import '../../shared/async_view.dart';
import '../../shared/calculator_sheet.dart';
import '../../shared/empty_state.dart';
import '../../shared/forms.dart';
import '../../shared/finance_form_widgets.dart';
import '../../shared/finance_bottom_sheet.dart';
import '../../shared/finance_display_widgets.dart';
import '../../shared/emi_visual_data.dart';
import '../../shared/notched_navigation_bar.dart';
import '../../shared/timed_snackbar.dart';
import 'emi_payoff_simulation.dart';
import 'emi_overview_screen.dart';

enum _EmiSort { dueDate, amount, remaining, closingSoon, name }

String _emiSortLabel(_EmiSort value) => switch (value) {
  _EmiSort.dueDate => 'Due date',
  _EmiSort.amount => 'Amount high to low',
  _EmiSort.remaining => 'Most left to pay',
  _EmiSort.closingSoon => 'Closing soon first',
  _EmiSort.name => 'Name A-Z',
};

class EmisScreen extends ConsumerStatefulWidget {
  const EmisScreen({super.key});

  @override
  ConsumerState<EmisScreen> createState() => _EmisScreenState();
}

class _EmisScreenState extends ConsumerState<EmisScreen> {
  bool _showCompleted = false;
  bool _celebrating = false;
  bool _searchOpen = false;
  String _query = '';
  _EmiSort _sort = _EmiSort.dueDate;
  final _pageController = PageController(initialPage: 0);
  final _activeScrollController = ScrollController();
  final _completedScrollController = ScrollController();
  final ValueNotifier<bool> _heroCollapsed = ValueNotifier(false);
  final ValueNotifier<bool> _barScrolled = ValueNotifier(false);
  final ValueNotifier<bool> _listScrolling = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _activeScrollController.addListener(() => _updatePageScroll(false));
    _completedScrollController.addListener(() => _updatePageScroll(true));
  }

  void _updatePageScroll(bool completed) {
    final controller = completed
        ? _completedScrollController
        : _activeScrollController;
    if (!controller.hasClients || completed != _showCompleted) return;
    final position = controller.position;
    final offset = position.pixels.clamp(0.0, position.maxScrollExtent);
    final scrolled = offset > 0;
    if (_barScrolled.value != scrolled) _barScrolled.value = scrolled;
    final collapsed =
        !completed && offset > MediaQuery.textScalerOf(context).scale(64);
    if (_heroCollapsed.value != collapsed) _heroCollapsed.value = collapsed;
  }

  void _onPageChanged(int index) {
    setState(() => _showCompleted = index == 1);
    _heroCollapsed.value = false;
    final controller = index == 1
        ? _completedScrollController
        : _activeScrollController;
    _barScrolled.value = controller.hasClients && controller.offset > 0;
  }

  @override
  void dispose() {
    _activeScrollController.dispose();
    _completedScrollController.dispose();
    _heroCollapsed.dispose();
    _barScrolled.dispose();
    _listScrolling.dispose();
    _pageController.dispose();
    super.dispose();
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
                  AmountText(
                    _wholeRupees(
                      detail.amountForInstallment(installment.number),
                    ),
                  ),
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
      showTimedSnackBar(
        ScaffoldMessenger.of(context),
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
      showTimedSnackBar(
        ScaffoldMessenger.of(context),
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
    final tokens = AppTheme.colorsOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: tokens.surface,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.colorsOf(context).background,
        body: Column(
          children: [
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
                  final remaining = active.fold<int>(
                    0,
                    (sum, item) => sum + item.remainingBalancePaise,
                  );
                  final topInset = MediaQuery.viewPaddingOf(context).top;
                  return Column(
                    children: [
                      SizedBox(
                        height: topInset + 56,
                        child: ColoredBox(
                          color: tokens.surface,
                          child: Padding(
                            padding: EdgeInsets.only(top: topInset),
                            child: Stack(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final narrow = constraints.maxWidth < 370;
                                      return Row(
                                        children: [
                                          Expanded(
                                            child: ValueListenableBuilder<bool>(
                                              valueListenable: _heroCollapsed,
                                              builder: (context, collapsed, _) => FittedBox(
                                                alignment: Alignment.centerLeft,
                                                fit: BoxFit.scaleDown,
                                                child: AnimatedSwitcher(
                                                  duration: const Duration(
                                                    milliseconds: 150,
                                                  ),
                                                  child: collapsed
                                                      ? Row(
                                                          key: const ValueKey(
                                                            'remaining',
                                                          ),
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            AmountText(
                                                              _wholeRupees(
                                                                remaining,
                                                              ),
                                                              style: Theme.of(context)
                                                                  .textTheme
                                                                  .titleSmall
                                                                  ?.copyWith(
                                                                    fontSize:
                                                                        17,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color: tokens
                                                                        .text,
                                                                  ),
                                                            ),
                                                            Text(
                                                              ' left',
                                                              style: Theme.of(context)
                                                                  .textTheme
                                                                  .titleSmall
                                                                  ?.copyWith(
                                                                    fontSize:
                                                                        17,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color: tokens
                                                                        .text,
                                                                  ),
                                                            ),
                                                          ],
                                                        )
                                                      : Text(
                                                          'EMIs & Loans',
                                                          key: const ValueKey(
                                                            'title',
                                                          ),
                                                          style: Theme.of(context)
                                                              .textTheme
                                                              .titleSmall
                                                              ?.copyWith(
                                                                fontSize: 17,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color:
                                                                    tokens.text,
                                                              ),
                                                        ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          SizedBox(
                                            width: narrow ? 154 : 188,
                                            child: _EmiTabs(
                                              controller: _pageController,
                                              activeCount: active.length,
                                              completedCount: completed.length,
                                              showCompleted: _showCompleted,
                                            ),
                                          ),
                                          SizedBox(
                                            width: 48,
                                            height: 48,
                                            child: IconButtonTheme(
                                              data: IconButtonThemeData(
                                                style: ButtonStyle(
                                                  foregroundColor:
                                                      WidgetStatePropertyAll(
                                                        tokens.text,
                                                      ),
                                                ),
                                              ),
                                              child: SectionReminderButton(
                                                type: FinanceReminderType.emi,
                                                dotColor: tokens.emi,
                                                dotBorderColor: tokens.surface,
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: ValueListenableBuilder<bool>(
                                    valueListenable: _barScrolled,
                                    builder: (context, scrolled, _) => SizedBox(
                                      height: 1,
                                      child: ColoredBox(
                                        color: scrolled
                                            ? tokens.outline
                                            : Colors.transparent,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            ScrollConfiguration(
                              behavior: const _EmiClampedScrollBehavior(),
                              child: PageView(
                                controller: _pageController,
                                onPageChanged: _onPageChanged,
                                children: [
                                  _buildPage(context, active, completed, false),
                                  _buildPage(context, active, completed, true),
                                ],
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
      ),
    );
  }

  Widget _buildPage(
    BuildContext context,
    List<EmiDetail> active,
    List<EmiDetail> completed,
    bool showCompleted,
  ) {
    final sort = active.length >= 6 ? _sort : _EmiSort.dueDate;
    final query = active.length >= 6 ? _query.trim().toLowerCase() : '';
    final filtered = active.where((item) {
      return query.isEmpty ||
          item.emi.name.toLowerCase().contains(query) ||
          (item.emi.provider ?? '').toLowerCase().contains(query);
    }).toList();
    if (!showCompleted) {
      filtered.sort(
        (a, b) => switch (sort) {
          _EmiSort.dueDate => a.nextUnpaidInstallment!.dueDate.compareTo(
            b.nextUnpaidInstallment!.dueDate,
          ),
          _EmiSort.amount =>
            b
                .amountForInstallment(b.nextUnpaidInstallment!.number)
                .compareTo(
                  a.amountForInstallment(a.nextUnpaidInstallment!.number),
                ),
          _EmiSort.remaining => b.remainingBalancePaise.compareTo(
            a.remainingBalancePaise,
          ),
          _EmiSort.closingSoon => a.remainingInstallments.compareTo(
            b.remainingInstallments,
          ),
          _EmiSort.name => a.emi.name.toLowerCase().compareTo(
            b.emi.name.toLowerCase(),
          ),
        },
      );
    }
    final visible = showCompleted ? completed : filtered;
    final initialsById = _emiInitialsById(active);
    final arcColors = _emiAgendaColors([...active, ...completed]);
    final sections = <(DateTime?, List<EmiDetail>)>[];
    if (showCompleted) {
      final grouped = <DateTime, List<EmiDetail>>{};
      for (final item in visible) {
        final completedOn = item.payments.isEmpty
            ? item.emi.updatedAt
            : item.payments
                  .map((payment) => payment.paidOn)
                  .reduce((a, b) => a.isAfter(b) ? a : b);
        grouped.putIfAbsent(dateOnly(completedOn), () => []).add(item);
      }
      for (final entry in grouped.entries) {
        sections.add((entry.key, entry.value));
      }
    } else if (sort == _EmiSort.dueDate) {
      final grouped = <DateTime, List<EmiDetail>>{};
      for (final item in visible) {
        final day = dateOnly(item.nextUnpaidInstallment!.dueDate);
        grouped.putIfAbsent(day, () => []).add(item);
      }
      for (final entry in grouped.entries) {
        sections.add((entry.key, entry.value));
      }
    } else {
      for (var offset = 0; offset < visible.length; offset += 8) {
        sections.add((null, visible.skip(offset).take(8).toList()));
      }
    }
    final entries = <(DateTime?, List<EmiDetail>?, EmiDetail?, int)>[];
    for (final (day, group) in sections) {
      if (day != null) entries.add((day, group, null, 0));
      for (var rowIndex = 0; rowIndex < group.length; rowIndex++) {
        entries.add((null, null, group[rowIndex], rowIndex));
      }
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          _listScrolling.value = true;
        } else if (notification is ScrollEndNotification) {
          _listScrolling.value = false;
        }
        return false;
      },
      child: CustomScrollView(
        key: PageStorageKey(showCompleted ? 'emi-completed' : 'emi-active'),
        controller: showCompleted
            ? _completedScrollController
            : _activeScrollController,
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: showCompleted
                ? _EmiCompletedHero(items: completed)
                : _EmiHero(
                    items: active,
                    colors: arcColors,
                    onAdd: () =>
                        openFinanceSheet(context, const EmiFormSheet()),
                  ),
          ),
          if (!showCompleted && active.length >= 6)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    Row(
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.sort, size: 16),
                          label: Text('Sort: ${_emiSortLabel(_sort)}'),
                          onPressed: () => showFinanceBottomSheet<void>(
                            context,
                            builder: (sheet) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final option in _EmiSort.values)
                                    ListTile(
                                      title: Text(_emiSortLabel(option)),
                                      trailing: _sort == option
                                          ? const Icon(Icons.check)
                                          : null,
                                      onTap: () {
                                        Navigator.pop(sheet);
                                        setState(() => _sort = option);
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: _searchOpen ? 'Close search' : 'Search EMIs',
                          onPressed: () => setState(() {
                            _searchOpen = !_searchOpen;
                            if (!_searchOpen) _query = '';
                          }),
                          icon: Icon(_searchOpen ? Icons.close : Icons.search),
                        ),
                      ],
                    ),
                    if (_searchOpen)
                      TextField(
                        autofocus: false,
                        decoration: InputDecoration(
                          hintText: 'Search name or lender',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: AppTheme.colorsOf(
                            context,
                          ).surfaceContainer,
                          border: InputBorder.none,
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                  ],
                ),
              ),
            ),
          if (visible.isEmpty && !showCompleted)
            SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: EmptyState(
                  icon: showCompleted
                      ? Icons.check_circle_outline
                      : Icons.account_balance_outlined,
                  title: showCompleted
                      ? 'No completed EMIs yet'
                      : query.isNotEmpty
                      ? 'No matching EMIs'
                      : 'No active EMIs',
                  message: showCompleted
                      ? 'Swipe left to go back'
                      : 'Add an EMI to see its installments and progress.',
                  actionLabel: showCompleted || query.isNotEmpty
                      ? null
                      : 'Add EMI',
                  onAction: showCompleted || query.isNotEmpty
                      ? null
                      : () => openFinanceSheet(context, const EmiFormSheet()),
                ),
              ),
            ),
          if (entries.isNotEmpty)
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          if (entries.isNotEmpty)
            SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final (day, group, detail, rowIndex) = entries[index];
                if (day != null) {
                  return Padding(
                    key: ValueKey('emi-day-${day.millisecondsSinceEpoch}'),
                    padding: const EdgeInsets.only(top: 16),
                    child: _EmiGroupHeader(
                      day: day,
                      items: group!,
                      completed: showCompleted,
                      onMarkAll: () => _markAllPaid(group),
                    ),
                  );
                }
                final item = detail!;
                final initials = initialsById[item.emi.id];
                final row = _EmiRow(
                  key: ValueKey(item.emi.id),
                  detail: item,
                  completed: showCompleted,
                  scrolling: _listScrolling,
                  onLongPress: () =>
                      _showTileActions(item, completed: showCompleted),
                  arcColor: arcColors[item.emi.id],
                  avatarInitials: initials,
                );
                final tile =
                    showCompleted || item.emi.status == EmiStatus.paused
                    ? row
                    : _SwipePayTile(
                        key: ValueKey('swipe-${item.emi.id}'),
                        detail: item,
                        onPaid: () => _markPaid(item, fromSwipe: true),
                        scrolling: _listScrolling,
                        child: row,
                      );
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      if (rowIndex > 0)
                        Container(
                          height: 1,
                          margin: const EdgeInsets.only(left: 48),
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppTheme.colorsOf(context).outline
                              : AppTheme.homeCardOutline,
                        ),
                      tile,
                    ],
                  ),
                );
              },
            ),
          if (!showCompleted && active.isNotEmpty)
            SliverToBoxAdapter(
              child: _EmiActiveFooter(
                showTips: active.length < 8,
                onAdd: () => openFinanceSheet(context, const EmiFormSheet()),
              ),
            ),
          if (showCompleted && completed.isNotEmpty)
            const SliverToBoxAdapter(child: _EmiCompletedFooter()),
          if (entries.isNotEmpty || !showCompleted)
            SliverToBoxAdapter(
              child: SizedBox(
                height:
                    NotchedNavigationMetrics.contentPadding(context) -
                    NotchedNavigationMetrics.contentGap +
                    16,
              ),
            ),
        ],
      ),
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
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final tokens = AppTheme.colorsOf(context);
          final page = controller.hasClients
              ? (controller.page ?? (showCompleted ? 1.0 : 0.0))
              : (showCompleted ? 1.0 : 0.0);
          final half = constraints.maxWidth / 2;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.surfaceContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 3 + page.clamp(0.0, 1.0) * (half - 3),
                  top: 3,
                  width: half - 3,
                  bottom: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.selectedFill,
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final index in [0, 1])
                      Expanded(
                        child: InkWell(
                          onTap: () => controller.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          ),
                          borderRadius: BorderRadius.circular(22),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  index == 0
                                      ? 'Active $activeCount'
                                      : completedCount > 0
                                      ? 'Completed $completedCount'
                                      : 'Completed',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color:
                                            (index == 0
                                                ? page < .5
                                                : page >= .5)
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : tokens.secondaryText,
                                        fontWeight:
                                            (index == 0
                                                ? page < .5
                                                : page >= .5)
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _showEmiInsightSheet(
  BuildContext context,
  String title,
  Widget child,
) => showFinanceBottomSheet<void>(
  context,
  builder: (sheet) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(sheet).height * .92,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(title, style: Theme.of(sheet).textTheme.titleLarge),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(sheet),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: child,
          ),
        ),
      ],
    ),
  ),
);

Future<void> openPersonalEmiIncomeInsight(
  BuildContext context,
  WidgetRef ref,
  List<EmiDetail> items,
) async {
  await _showIncomePanel<void>(context, (_) => _EmiIncomeCard(items: items));
}

Future<T?> _showIncomePanel<T>(
  BuildContext context,
  WidgetBuilder content,
) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close income insight',
  barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: .28),
  transitionDuration: const Duration(milliseconds: 220),
  transitionBuilder: (context, animation, _, child) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -.35),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ),
  pageBuilder: (panel, _, _) {
    final palette = AppTheme.homePaletteOf(panel);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            MediaQuery.viewInsetsOf(panel).bottom,
          ),
          child: Material(
            color: palette.surface,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 440,
                maxHeight:
                    (MediaQuery.sizeOf(panel).height -
                        MediaQuery.viewInsetsOf(panel).bottom) *
                    .8,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Income & EMIs',
                            style: Theme.of(panel).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(panel),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    content(panel),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  },
);

class _EmiInsights extends ConsumerStatefulWidget {
  const _EmiInsights({required this.items, required this.colors});
  final List<EmiDetail> items;
  final Map<int, Color> colors;

  @override
  ConsumerState<_EmiInsights> createState() => _EmiInsightsState();
}

class _EmiInsightsState extends ConsumerState<_EmiInsights> {
  Future<void> _openIncome() async {
    final income = await ref.read(personalEmiIncomeProvider.future);
    if (!mounted) return;
    if (income == null) {
      final value = await _showIncomePanel<int>(
        context,
        (_) => const _IncomeAmountSheet(initialIncome: null),
      );
      if (!mounted || value == null) return;
      final db = ref.read(databaseProvider);
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: 'emi.monthlyIncomePaise',
              value: value.toString(),
            ),
          );
    } else {
      await _showIncomePanel<void>(
        context,
        (_) => _EmiIncomeCard(items: widget.items),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final income = ref.watch(personalEmiIncomeProvider).valueOrNull;
    final tokens = AppTheme.colorsOf(context);
    final accent = Theme.of(context).colorScheme.primary;
    final data = ref.watch(_emiLoadProvider(_emiLoadKey(widget.items)));
    final current = data.months.isEmpty ? 0 : data.months.first.amountPaise;
    final next = data.months.length > 1 ? data.months[1].amountPaise : 0;
    final change = next - current;
    final share = personalEmiIncomePercent(current, income);
    final zone = personalEmiIncomeZone(share);
    final plan = data.plan;
    return Row(
      children: [
        Expanded(
          child: _EmiHeroStat(
            title: 'Next month',
            value: change == 0
                ? const Text('No change')
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(change < 0 ? '-' : '+'),
                      AmountText(
                        _netWholeRupees(change.abs()),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: change < 0 ? accent : tokens.pay,
                            ),
                      ),
                    ],
                  ),
            color: change < 0
                ? accent
                : change > 0
                ? tokens.pay
                : tokens.text,
            caption: 'vs ${DateFormat('MMM').format(DateTime.now())}',
            onTap: () =>
                _showEmiAllMonths(context, widget.items, widget.colors),
          ),
        ),
        _EmiStatDivider(),
        Expanded(
          child: _EmiHeroStat(
            title: 'EMI vs income',
            value: Text(
              share == null
                  ? '+ Add'
                  : privacyAmountsHidden
                  ? hiddenAmount
                  : '$share%',
            ),
            caption: zone,
            onTap: _openIncome,
          ),
        ),
        _EmiStatDivider(),
        Expanded(
          child: _EmiHeroStat(
            title: 'Pay faster',
            value: Text(plan == null ? '—' : '${plan.monthsSooner} mo'),
            caption: plan == null ? '1 EMI only' : 'sooner',
            onTap: plan == null
                ? null
                : () => _showEmiInsightSheet(
                    context,
                    'Pay off faster',
                    _EmiPayoffPlanner(items: widget.items),
                  ),
          ),
        ),
      ],
    );
  }
}

class _EmiStatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 54,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: AppTheme.colorsOf(context).outline,
  );
}

class _EmiHeroStat extends StatelessWidget {
  const _EmiHeroStat({
    required this.title,
    required this.value,
    required this.caption,
    required this.onTap,
    this.color,
  });
  final String title, caption;
  final Widget value;
  final VoidCallback? onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.colorsOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 62),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 12,
                color: tokens.secondaryText,
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: DefaultTextStyle(
                style: Theme.of(context).textTheme.titleSmall!.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color ?? tokens.text,
                ),
                child: value,
              ),
            ),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 12,
                color: tokens.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<EmiMonthLoad> _allEmiMonths(List<EmiDetail> items, DateTime today) {
  final start = DateTime(today.year, today.month);
  final partsByMonth = <DateTime, List<(String, int)>>{};
  DateTime? last;
  for (final detail in items) {
    for (final installment in detail.installments.where(
      (part) => !part.isPaid,
    )) {
      final month = DateTime(
        installment.dueDate.year,
        installment.dueDate.month,
      );
      partsByMonth.putIfAbsent(month, () => []).add((
        _emiName(detail.emi.name),
        detail.amountForInstallment(installment.number),
      ));
      if (last == null || month.isAfter(last)) last = month;
    }
  }
  if (last == null) return const [];
  final count = ((last.year - start.year) * 12 + last.month - start.month)
      .clamp(0, 240);
  final months = <EmiMonthLoad>[];
  var previous = 0;
  for (var i = 0; i <= count; i++) {
    final month = DateTime(start.year, start.month + i);
    final parts = partsByMonth[month] ?? const <(String, int)>[];
    final amount = parts.fold<int>(0, (sum, part) => sum + part.$2);
    months.add(EmiMonthLoad(month, amount, parts, i > 0 && amount < previous));
    previous = amount;
  }
  return months;
}

typedef _EmiLoadKey = (List<EmiDetail>, int);

class _EmiMonthChange {
  const _EmiMonthChange(this.month, this.netPaise, this.reasons, this.starts);
  final DateTime month;
  final int netPaise;
  final List<(String, int)> reasons;
  final bool starts;
}

class _EmiLoadData {
  const _EmiLoadData(
    this.months,
    this.changes,
    this.plan,
    this.currentPaidPaise,
    this.entries,
    this.debtAfter,
  );
  final List<EmiMonthLoad> months;
  final Map<int, _EmiMonthChange> changes;
  final EmiPayoffPlan? plan;
  final int currentPaidPaise;
  final List<List<_EmiMonthEntry>> entries;
  final List<int> debtAfter;
}

class _EmiMonthEntry {
  const _EmiMonthEntry(this.detail, this.installment, this.amountPaise);
  final EmiDetail detail;
  final EmiInstallment installment;
  final int amountPaise;
}

final _emiLoadProvider = Provider.autoDispose.family<_EmiLoadData, _EmiLoadKey>(
  (ref, key) {
    final items = key.$1;
    final today = DateTime.fromMillisecondsSinceEpoch(key.$2);
    final months = _allEmiMonths(items, today);
    final entries = List.generate(months.length, (_) => <_EmiMonthEntry>[]);
    final debtAfter = <int>[];
    final firstMonth = DateTime(today.year, today.month);
    var outstanding = items.fold<int>(
      0,
      (sum, item) => sum + item.remainingBalancePaise,
    );
    for (final item in items) {
      for (final installment in item.installments) {
        final due = installment.dueDate;
        final index =
            (due.year - firstMonth.year) * 12 + due.month - firstMonth.month;
        if (index < 0 || index >= entries.length) continue;
        entries[index].add(
          _EmiMonthEntry(
            item,
            installment,
            item.amountForInstallment(installment.number),
          ),
        );
      }
    }
    for (var index = 0; index < entries.length; index++) {
      entries[index].sort(
        (a, b) => a.installment.dueDate.compareTo(b.installment.dueDate),
      );
      outstanding = math.max(0, outstanding - months[index].amountPaise);
      debtAfter.add(outstanding);
    }
    final changes = <int, _EmiMonthChange>{};
    for (var i = 1; i < months.length; i++) {
      final previous = months[i - 1];
      final current = months[i];
      final net = current.amountPaise - previous.amountPaise;
      if (net == 0) continue;
      final before = <String, int>{};
      final after = <String, int>{};
      for (final part in previous.parts) {
        before.update(
          part.$1,
          (value) => value + part.$2,
          ifAbsent: () => part.$2,
        );
      }
      for (final part in current.parts) {
        after.update(
          part.$1,
          (value) => value + part.$2,
          ifAbsent: () => part.$2,
        );
      }
      final reasons = <(String, int)>[];
      var starts = false;
      for (final name in {...before.keys, ...after.keys}) {
        final difference = (after[name] ?? 0) - (before[name] ?? 0);
        if (difference == 0) continue;
        if (difference > 0 && (before[name] ?? 0) == 0) starts = true;
        reasons.add((name, difference));
      }
      changes[i] = _EmiMonthChange(current.month, net, reasons, starts);
    }
    return _EmiLoadData(
      months,
      changes,
      items.length < 2
          ? null
          : simulateEmiPayoff(
              items: items,
              today: today,
              extraPerMonthPaise: 0,
              reuseFreedPayments: true,
            ),
      items.fold<int>(
        0,
        (total, item) =>
            total +
            item.installments
                .where(
                  (part) =>
                      part.isPaid &&
                      part.dueDate.year == today.year &&
                      part.dueDate.month == today.month,
                )
                .fold<int>(
                  0,
                  (sum, part) => sum + item.amountForInstallment(part.number),
                ),
      ),
      entries,
      debtAfter,
    );
  },
);

_EmiLoadKey _emiLoadKey(List<EmiDetail> items) {
  final today = dateOnly(DateTime.now());
  return (items, today.millisecondsSinceEpoch);
}

int _netWholeRupees(int paise) => (paise.abs() ~/ 100) * 100;

Future<void> _showEmiAllMonths(
  BuildContext context,
  List<EmiDetail> items,
  Map<int, Color> colors,
) => _showEmiInsightSheet(
  context,
  'Monthly load',
  _EmiLoadContent(
    items: items,
    onMonthTap: (index) => _showEmiMonthSheet(context, items, colors, index),
  ),
);

Future<void> _showEmiMonthSheet(
  BuildContext context,
  List<EmiDetail> items,
  Map<int, Color> colors,
  int index, {
  ValueChanged<int>? onMonthChanged,
}) => showFinanceBottomSheet<void>(
  context,
  builder: (_) => FractionallySizedBox(
    heightFactor: .75,
    child: _EmiMonthSheet(
      items: items,
      colors: colors,
      initialIndex: index,
      onMonthChanged: onMonthChanged,
      onAllMonths: () => _showEmiAllMonths(context, items, colors),
    ),
  ),
);

class _EmiMonthSheet extends ConsumerStatefulWidget {
  const _EmiMonthSheet({
    required this.items,
    required this.colors,
    required this.initialIndex,
    required this.onMonthChanged,
    required this.onAllMonths,
  });

  final List<EmiDetail> items;
  final Map<int, Color> colors;
  final int initialIndex;
  final ValueChanged<int>? onMonthChanged;
  final VoidCallback onAllMonths;

  @override
  ConsumerState<_EmiMonthSheet> createState() => _EmiMonthSheetState();
}

class _EmiMonthSheetState extends ConsumerState<_EmiMonthSheet> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  final ScrollController _chips = ScrollController();
  final Map<int, GlobalKey> _chipKeys = {};
  late final Map<int, String> _initials = _emiInitialsById(widget.items);
  late int _selected = widget.initialIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerChip(_selected));
  }

  void _centerChip(int index) {
    final chip = _chipKeys[index]?.currentContext;
    if (chip == null) return;
    Scrollable.ensureVisible(
      chip,
      alignment: .5,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _pages.dispose();
    _chips.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_emiLoadProvider(_emiLoadKey(widget.items)));
    final months = data.months;
    if (months.isEmpty) return const Center(child: Text('No EMIs due'));
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(months[_selected].month),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => widget.onAllMonths(),
                    );
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: AppTheme.colorsOf(context).selectedFill,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('All months'),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 42,
            child: SingleChildScrollView(
              controller: _chips,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (var index = 0; index < months.length; index++) ...[
                    if (index > 0) const SizedBox(width: 8),
                    Semantics(
                      selected: index == _selected,
                      button: true,
                      child: InkWell(
                        key: _chipKeys.putIfAbsent(index, GlobalKey.new),
                        onTap: () => _pages.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          height: 40,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: index == _selected
                                ? const Color(0xFF0F6B5C)
                                : AppTheme.colorsOf(context).surfaceContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            months[index].month.month == 1 ||
                                    (index == 0 &&
                                        months[index].month.year !=
                                            DateTime.now().year)
                                ? DateFormat(
                                    'MMM yy',
                                  ).format(months[index].month)
                                : DateFormat('MMM').format(months[index].month),
                            softWrap: false,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: index == _selected
                                      ? Colors.white
                                      : AppTheme.colorsOf(context).text,
                                  fontWeight: index == _selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: months.length,
              onPageChanged: (index) {
                setState(() => _selected = index);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _centerChip(index);
                });
                widget.onMonthChanged?.call(index);
              },
              itemBuilder: (context, index) => AnimatedOpacity(
                opacity: index == _selected ? 1 : .5,
                duration: const Duration(milliseconds: 120),
                child: _EmiMonthPage(
                  month: months[index],
                  previous: index == 0 ? null : months[index - 1],
                  change: data.changes[index],
                  entries: data.entries[index],
                  colors: widget.colors,
                  initials: _initials,
                  debtAfterPaise: data.debtAfter[index],
                  currentPaidPaise: index == 0 ? data.currentPaidPaise : 0,
                  incomePaise: ref.watch(personalEmiIncomeProvider).valueOrNull,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmiMonthPage extends StatelessWidget {
  const _EmiMonthPage({
    required this.month,
    required this.previous,
    required this.change,
    required this.entries,
    required this.colors,
    required this.initials,
    required this.debtAfterPaise,
    required this.currentPaidPaise,
    required this.incomePaise,
  });

  final EmiMonthLoad month;
  final EmiMonthLoad? previous;
  final _EmiMonthChange? change;
  final List<_EmiMonthEntry> entries;
  final Map<int, Color> colors;
  final Map<int, String> initials;
  final int debtAfterPaise;
  final int currentPaidPaise;
  final int? incomePaise;

  String _reason(List<(String, int)> parts, String verb) {
    final names = parts
        .take(2)
        .map((part) => part.$1.split(' ').first)
        .join(', ');
    final more = parts.length > 2 ? ' +${parts.length - 2} more' : '';
    final amount = parts.fold<int>(0, (sum, part) => sum + part.$2.abs());
    final action = verb == 'ends' && parts.length > 1 ? 'end' : verb;
    return '$names$more $action\u00a0${verb == 'ends' ? '−' : '+'}${formatMoney(_wholeRupees(amount))}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.colorsOf(context);
    final styles = Theme.of(context).textTheme;
    final difference = previous == null
        ? 0
        : month.amountPaise - previous!.amountPaise;
    final beforeNames =
        previous?.parts.map((part) => part.$1).toSet() ?? <String>{};
    final afterNames = month.parts.map((part) => part.$1).toSet();
    final ended =
        change?.reasons
            .where((part) => part.$2 < 0 && !afterNames.contains(part.$1))
            .toList() ??
        [];
    final started =
        change?.reasons
            .where((part) => part.$2 > 0 && !beforeNames.contains(part.$1))
            .toList() ??
        [];
    final adjusted =
        change?.reasons
            .where(
              (part) =>
                  beforeNames.contains(part.$1) && afterNames.contains(part.$1),
            )
            .toList() ??
        [];
    final reasons = [
      if (ended.isNotEmpty) _reason(ended, 'ends'),
      if (started.isNotEmpty) _reason(started, 'start'),
      for (final part in adjusted.take(2))
        '${part.$1.split(' ').first} ${part.$2 < 0 ? 'drops' : 'rises'}\u00a0${part.$2 < 0 ? '−' : '+'}${formatMoney(_wholeRupees(part.$2.abs()))}',
      if (adjusted.length > 2) '+${adjusted.length - 2} more changes',
    ].join(' · ');
    final dueCount = entries.where((entry) => !entry.installment.isPaid).length;
    final shares = <int, int>{};
    final names = <int, String>{};
    for (final entry in entries.where((entry) => !entry.installment.isPaid)) {
      final id = entry.detail.emi.id;
      shares.update(
        id,
        (amount) => amount + entry.amountPaise,
        ifAbsent: () => entry.amountPaise,
      );
      names[id] = _emiName(entry.detail.emi.name);
    }
    return Semantics(
      label:
          '${DateFormat('MMMM yyyy').format(month.month)}, total ${formatMoney(_wholeRupees(month.amountPaise))}${previous == null
              ? ''
              : difference == 0
              ? ', no change'
              : ', ${difference < 0 ? 'down' : 'up'} ${formatMoney(_wholeRupees(difference.abs()))}'}',
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: [
          AmountText(
            _wholeRupees(month.amountPaise),
            style: styles.headlineMedium?.copyWith(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: tokens.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          if (previous == null)
            Text(
              'Paid ${formatMoney(_wholeRupees(currentPaidPaise))} · Due ${formatMoney(_wholeRupees(month.amountPaise))}',
              style: styles.bodyMedium?.copyWith(color: tokens.secondaryText),
            )
          else
            Text(
              difference == 0
                  ? 'No change vs ${DateFormat('MMMM').format(previous!.month)}'
                  : '${difference < 0 ? '↓' : '↑'} ${formatMoney(_wholeRupees(difference.abs()))} vs ${DateFormat('MMMM').format(previous!.month)}',
              style: styles.bodyMedium?.copyWith(
                color: difference < 0
                    ? tokens.receive
                    : difference > 0
                    ? tokens.pay
                    : tokens.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (previous != null && reasons.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              reasons,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: styles.bodySmall?.copyWith(
                fontSize: 13,
                color: tokens.secondaryText,
              ),
            ),
          ],
          if (month.amountPaise > 0 && shares.isNotEmpty) ...[
            const SizedBox(height: 24),
            RepaintBoundary(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(
                  width: double.infinity,
                  height: 10,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final id in shares.keys) ...[
                        if (id != shares.keys.first) const SizedBox(width: 2),
                        Expanded(
                          flex: math.max(1, shares[id]!),
                          child: ColoredBox(color: colors[id] ?? tokens.emi),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final id in shares.keys.take(4))
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: colors[id] ?? tokens.emi,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${names[id]} ${formatMoney(_wholeRupees(shares[id]!))}',
                        style: styles.labelSmall?.copyWith(
                          color: tokens.secondaryText,
                        ),
                      ),
                    ],
                  ),
                if (shares.length > 4)
                  Text(
                    '+${shares.length - 4}',
                    style: styles.labelSmall?.copyWith(
                      color: tokens.secondaryText,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          if (entries.isEmpty)
            Text(
              'No EMIs due',
              style: styles.bodyMedium?.copyWith(color: tokens.secondaryText),
            )
          else if (previous == null && dueCount == 0)
            Text(
              'All paid for ${DateFormat('MMMM').format(month.month)}',
              style: styles.bodyMedium?.copyWith(color: tokens.receive),
            ),
          for (final entry in entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _EmiAvatar(
                color: colors[entry.detail.emi.id] ?? tokens.emi,
                initials:
                    initials[entry.detail.emi.id] ??
                    _emiName(
                      entry.detail.emi.name,
                    ).characters.first.toUpperCase(),
              ),
              title: Text(
                _emiName(entry.detail.emi.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_emiLenderName(entry.detail.emi.provider ?? entry.detail.emi.type)} · ${DateFormat('d MMM').format(entry.installment.dueDate)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry.installment.isPaid ||
                      entry.installment.number == 1 ||
                      entry.installment.number == entry.detail.emi.tenureMonths)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (entry.installment.isPaid)
                          Icon(
                            Icons.check,
                            size: 13,
                            color: tokens.secondaryText,
                          ),
                        Text(
                          entry.installment.isPaid
                              ? 'Paid'
                              : entry.installment.number == 1
                              ? 'Starts'
                              : 'Last EMI',
                          style: styles.labelSmall?.copyWith(
                            color: entry.installment.isPaid
                                ? tokens.secondaryText
                                : entry.installment.number == 1
                                ? Theme.of(context).colorScheme.tertiary
                                : tokens.receive,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              trailing: AmountText(
                _wholeRupees(entry.amountPaise),
                style: styles.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EmiDetailScreen(entry.detail.emi.id),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tokens.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Debt left after this month',
                  style: styles.bodySmall?.copyWith(
                    color: tokens.secondaryText,
                  ),
                ),
                AmountText(
                  _wholeRupees(debtAfterPaise),
                  style: styles.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (incomePaise != null && incomePaise! > 0)
                  Text(
                    privacyAmountsHidden
                        ? '$hiddenAmount of your income'
                        : '${(month.amountPaise * 100 / incomePaise!).round()}% of your income',
                    style: styles.bodySmall?.copyWith(
                      color: tokens.secondaryText,
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

class _EmiLoadContent extends ConsumerStatefulWidget {
  const _EmiLoadContent({required this.items, required this.onMonthTap});
  final List<EmiDetail> items;
  final ValueChanged<int> onMonthTap;

  @override
  ConsumerState<_EmiLoadContent> createState() => _EmiLoadContentState();
}

class _EmiLoadContentState extends ConsumerState<_EmiLoadContent> {
  int _mode = 0;
  int _visibleMonths = 12;

  String _changeLabel(_EmiMonthChange change) =>
      '${change.netPaise < 0 ? 'down' : 'up'} ${formatMoney(_netWholeRupees(change.netPaise))}';

  String _monthTooltip(EmiMonthLoad month, _EmiMonthChange? change) {
    final reasons =
        change?.reasons
            .map(
              (part) =>
                  '${part.$1} ${part.$2 > 0 ? 'starts' : 'ends'} ${formatMoney(_wholeRupees(part.$2.abs()))}',
            )
            .join(' · ') ??
        'No change';
    return '${DateFormat('MMM yyyy').format(month.month)}: $reasons · Total ${formatMoney(_wholeRupees(month.amountPaise))}';
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_emiLoadProvider(_emiLoadKey(widget.items)));
    final months = data.months;
    final tokens = AppTheme.colorsOf(context);
    final changes = data.changes;
    final drops = changes.values.where((item) => item.netPaise < 0).length;
    final maxAmount = months.isEmpty
        ? 0
        : months.map((month) => month.amountPaise).reduce(math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var index = 0; index < 3; index++) ...[
              if (index > 0) const SizedBox(width: 4),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _mode = index),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _mode == index
                          ? const Color(0xFF0F6B5C)
                          : tokens.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: _mode == index
                          ? null
                          : Border.all(color: tokens.outline),
                    ),
                    child: Text(
                      const ['Months', 'Steps', 'Total debt'][index],
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: _mode == index ? Colors.white : tokens.text,
                        fontWeight: _mode == index
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        if (_mode == 2)
          _EmiDebtChart(items: widget.items)
        else if (months.isNotEmpty && _mode == 0) ...[
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: math.min(_visibleMonths, months.length),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 72,
            ),
            itemBuilder: (context, index) {
              final month = months[index];
              final change = changes[index];
              final level = maxAmount == 0
                  ? 0
                  : (month.amountPaise * 4 / maxAmount).round().clamp(0, 4);
              final tint = [.12, .24, .36, .50, .65][level];
              const green = Color(0xFF0F6B5C);
              final tileText = tint > .45 ? Colors.white : tokens.text;
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return Tooltip(
                triggerMode: TooltipTriggerMode.longPress,
                message: _monthTooltip(month, change),
                child: InkWell(
                  onTap: () {
                    final openMonth = widget.onMonthTap;
                    Navigator.pop(context);
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => openMonth(index),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: tint),
                      borderRadius: BorderRadius.circular(12),
                      border: index == 0
                          ? Border.all(color: green, width: 2)
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${DateFormat('MMM').format(month.month)}${index == 0 || month.month.month == 1 ? ' ${month.month.year}' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(fontSize: 12, color: tileText),
                              ),
                            ),
                            if (index == 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: green,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  'Now',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        fontSize: 9,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimary,
                                      ),
                                ),
                              ),
                          ],
                        ),
                        const Spacer(),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: AmountText(
                            _wholeRupees(month.amountPaise),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: tileText,
                                ),
                          ),
                        ),
                        if (change != null) ...[
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _changeLabel(change),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: tint > .45
                                        ? Colors.white
                                        : change.netPaise < 0
                                        ? isDark
                                              ? tokens.receive
                                              : const Color(0xFF047857)
                                        : tokens.pay,
                                    fontSize: 10,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'less',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 12,
                  color: tokens.secondaryText,
                ),
              ),
              const SizedBox(width: 6),
              for (final alpha in const [.12, .24, .36, .50, .65])
                Container(
                  width: 14,
                  height: 8,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F6B5C).withValues(alpha: alpha),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              const SizedBox(width: 4),
              Text(
                'more',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 12,
                  color: tokens.secondaryText,
                ),
              ),
            ],
          ),
          if (_visibleMonths < months.length)
            TextButton(
              onPressed: () => setState(() => _visibleMonths += 12),
              child: const Text('Show more'),
            ),
          ExpansionTile(
            title: Text('What changes (${changes.length})'),
            children: [
              for (final change in changes.values)
                ListTile(
                  title: Text(
                    '${DateFormat('MMM yyyy').format(change.month)}: ${_changeLabel(change)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: change.netPaise < 0 ? tokens.receive : tokens.pay,
                    ),
                  ),
                  subtitle: Text(
                    change.reasons
                        .map(
                          (part) =>
                              '${part.$1} ${part.$2 > 0 ? 'starts' : 'ends'} ${formatMoney(_wholeRupees(part.$2.abs()))}',
                        )
                        .join(' · '),
                  ),
                ),
            ],
          ),
        ] else if (months.isNotEmpty) ...[
          _EmiStaircaseChart(
            months: months,
            changes: changes,
            tooltip: _monthTooltip,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final index in [0, months.length ~/ 2, months.length - 1])
                Text(
                  DateFormat('MMM yy').format(months[index].month),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Your payment drops $drops ${drops == 1 ? 'time' : 'times'}, from ${formatMoney(_wholeRupees(months.first.amountPaise))} to ${formatMoney(_wholeRupees(months.last.amountPaise))}.',
          ),
        ],
      ],
    );
  }
}

class _EmiStaircaseChart extends StatefulWidget {
  const _EmiStaircaseChart({
    required this.months,
    required this.changes,
    required this.tooltip,
  });
  final List<EmiMonthLoad> months;
  final Map<int, _EmiMonthChange> changes;
  final String Function(EmiMonthLoad, _EmiMonthChange?) tooltip;

  @override
  State<_EmiStaircaseChart> createState() => _EmiStaircaseChartState();
}

class _EmiStaircaseChartState extends State<_EmiStaircaseChart>
    with SingleTickerProviderStateMixin {
  static bool _shown = false;
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  final _tooltip = GlobalKey<TooltipState>();
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    if (_shown) {
      _draw.value = 1;
    } else {
      _shown = true;
      _draw.forward();
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.colorsOf(context);
    final selected =
        widget.months[_selected.clamp(0, widget.months.length - 1)];
    final maxValue = widget.months
        .map((month) => month.amountPaise)
        .reduce(math.max);
    return RepaintBoundary(
      child: SizedBox(
        height: 260,
        child: LayoutBuilder(
          builder: (context, size) => Tooltip(
            key: _tooltip,
            triggerMode: TooltipTriggerMode.manual,
            message: widget.tooltip(selected, widget.changes[_selected]),
            child: GestureDetector(
              onTapUp: (event) {
                setState(
                  () => _selected =
                      ((event.localPosition.dx / size.maxWidth) *
                              widget.months.length)
                          .floor()
                          .clamp(0, widget.months.length - 1),
                );
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _tooltip.currentState?.ensureTooltipVisible(),
                );
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _draw,
                      builder: (context, _) => CustomPaint(
                        painter: _EmiStaircasePainter(
                          values: widget.months
                              .map((month) => month.amountPaise)
                              .toList(),
                          color: tokens.emi,
                          progress: _draw.value,
                        ),
                      ),
                    ),
                  ),
                  for (final entry in widget.changes.entries)
                    Positioned(
                      left: (entry.key * size.maxWidth / widget.months.length)
                          .clamp(0.0, math.max(0, size.maxWidth - 90)),
                      top:
                          ((maxValue == 0
                                      ? 200.0
                                      : 240 -
                                            widget
                                                    .months[entry.key]
                                                    .amountPaise /
                                                maxValue *
                                                240) +
                                  (entry.key % 3) * 26 -
                                  18)
                              .clamp(0.0, 218.0),
                      width: 90,
                      child: Text(
                        '${DateFormat('MMM').format(entry.value.month)} ${entry.value.netPaise < 0 ? '-' : '+'}${formatMoney(_netWholeRupees(entry.value.netPaise))}',
                        maxLines: 2,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: entry.value.netPaise < 0
                              ? tokens.receive
                              : tokens.pay,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmiStaircasePainter extends CustomPainter {
  const _EmiStaircasePainter({
    required this.values,
    required this.color,
    required this.progress,
  });
  final List<int> values;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = values.reduce(math.max);
    final width = size.width / values.length;
    final count = (values.length * progress).ceil().clamp(1, values.length);
    double y(int index) => maxValue == 0
        ? size.height - 8
        : size.height - 8 - values[index] / maxValue * (size.height - 20);
    final line = Path()..moveTo(0, y(0));
    for (var i = 0; i < count; i++) {
      line.lineTo((i + 1) * width, y(i));
      if (i + 1 < count) line.lineTo((i + 1) * width, y(i + 1));
    }
    final area = Path.from(line)
      ..lineTo(count * width, size.height - 8)
      ..lineTo(0, size.height - 8)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: .16));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _EmiStaircasePainter old) =>
      color != old.color ||
      progress != old.progress ||
      !listEquals(values, old.values);
}

class _EmiClampedScrollBehavior extends ScrollBehavior {
  const _EmiClampedScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}

class _EmiCompletedHero extends StatelessWidget {
  const _EmiCompletedHero({required this.items});
  final List<EmiDetail> items;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.colorsOf(context);
    final accent = Theme.of(context).colorScheme.primary;
    final paid = items.fold<int>(0, (sum, item) => sum + item.paidPaise);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.outline)),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: items.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nothing completed yet',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'EMIs you finish will show up here',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: tokens.secondaryText),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paid off',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    color: tokens.secondaryText,
                  ),
                ),
                AmountText(
                  _wholeRupees(paid),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: tokens.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.selectedFill,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    child: Text(
                      '${items.length} ${items.length == 1 ? 'EMI' : 'EMIs'} cleared',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _EmiHero extends ConsumerStatefulWidget {
  const _EmiHero({
    required this.items,
    required this.colors,
    required this.onAdd,
  });
  final List<EmiDetail> items;
  final Map<int, Color> colors;
  final VoidCallback onAdd;
  @override
  ConsumerState<_EmiHero> createState() => _EmiHeroState();
}

class _EmiHeroState extends ConsumerState<_EmiHero>
    with SingleTickerProviderStateMixin {
  static bool _counted = false;
  int? _selectedMonth;
  Timer? _selectionTimer;
  late final AnimationController _count = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  @override
  void initState() {
    super.initState();
    if (_counted || widget.items.isEmpty) {
      _count.value = 1;
    } else {
      _counted = true;
      _count.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _EmiHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_counted && oldWidget.items.isEmpty && widget.items.isNotEmpty) {
      _counted = true;
      _count.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _selectionTimer?.cancel();
    _count.dispose();
    super.dispose();
  }

  Future<void> _openMonth(int index) async {
    _selectionTimer?.cancel();
    setState(() => _selectedMonth = index);
    await _showEmiMonthSheet(
      context,
      widget.items,
      widget.colors,
      index,
      onMonthChanged: (value) {
        if (mounted) setState(() => _selectedMonth = value);
      },
    );
    if (!mounted) return;
    _selectionTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _selectedMonth = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
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
    final monthsToGo = finalDue == null
        ? 0
        : math.max(
            0,
            (finalDue.year - now.year) * 12 +
                finalDue.month -
                now.month -
                (finalDue.day < now.day ? 1 : 0),
          );
    final loadData = ref.watch(_emiLoadProvider(_emiLoadKey(items)));
    final load = loadData.months.take(12).toList();
    final maxLoad = load.fold<int>(
      0,
      (max, month) => month.amountPaise > max ? month.amountPaise : max,
    );
    final tokens = AppTheme.colorsOf(context);
    final accent = Theme.of(context).colorScheme.primary;
    final muted = tokens.secondaryText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.outline)),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (items.isEmpty) ...[
            Text(
              'No active EMIs',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: tokens.text),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: widget.onAdd,
              style: TextButton.styleFrom(
                backgroundColor: tokens.selectedFill,
                foregroundColor: accent,
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add EMI'),
            ),
          ] else ...[
            Text(
              'Total left',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 13, color: muted),
            ),
            AnimatedBuilder(
              animation: _count,
              builder: (context, _) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AmountText(
                  _wholeRupees(
                    (remaining *
                            (MediaQuery.disableAnimationsOf(context)
                                ? 1
                                : _count.value))
                        .round(),
                  ),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: tokens.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: tokens.selectedFill,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Debt-free ${DateFormat('MMM yyyy').format(finalDue!)} · $monthsToGo months',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
            if (load.length >= 2) ...[
              const SizedBox(height: 10),
              Column(
                children: [
                  Row(
                    children: [
                      AmountText(
                        _wholeRupees(load.first.amountPaise),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: tokens.text,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () =>
                            _showEmiAllMonths(context, items, widget.colors),
                        child: Text(
                          'All months ›',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: accent,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 48,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var index = 0; index < load.length; index++) ...[
                          if (index > 0) const SizedBox(width: 6),
                          Expanded(
                            child: InkWell(
                              onTap: () => _openMonth(index),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Container(
                                    height: maxLoad == 0
                                        ? 6
                                        : 6 +
                                              30 *
                                                  load[index].amountPaise /
                                                  maxLoad,
                                    decoration: BoxDecoration(
                                      color: index == 0
                                          ? accent
                                          : tokens.outline,
                                      borderRadius: BorderRadius.circular(4),
                                      border: _selectedMonth == index
                                          ? Border.all(color: accent, width: 2)
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      for (var index = 0; index < load.length; index++) ...[
                        if (index > 0) const SizedBox(width: 6),
                        Expanded(
                          child: InkWell(
                            onTap: () => _openMonth(index),
                            child: Text(
                              load[index].month.month == 1
                                  ? DateFormat(
                                      'MMM yy',
                                    ).format(load[index].month)
                                  : DateFormat('MMM').format(load[index].month),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(fontSize: 10, color: muted),
                            ),
                          ),
                        ),
                      ],
                      if (loadData.months.length > 12)
                        Text(
                          '+${loadData.months.length - 12} mo',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(fontSize: 10, color: muted),
                        ),
                    ],
                  ),
                ],
              ),
            ],
            if (loadData.currentPaidPaise > 0 && load.isNotEmpty) ...[
              const SizedBox(height: 5),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${DateFormat('MMM').format(load.first.month)}: ',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: muted),
                  ),
                  AmountText(
                    _wholeRupees(loadData.currentPaidPaise),
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: tokens.text),
                  ),
                  Text(
                    ' paid · ',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: muted),
                  ),
                  AmountText(
                    _wholeRupees(load.first.amountPaise),
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: tokens.text),
                  ),
                  Text(
                    ' due',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Container(height: 1, color: tokens.outline),
            const SizedBox(height: 10),
            _EmiInsights(items: items, colors: widget.colors),
          ],
        ],
      ),
    );
  }
}

String _emiName(String name) => displayName(name);

String _emiAvatarInitials(String name, bool collides) {
  final words = name.trim().split(RegExp(r'\s+'));
  if (words.isEmpty || words.first.isEmpty) return '?';
  final first = words.first.characters.first.toUpperCase();
  if (!collides) return first;
  final firstWordCharacters = words.first.characters.toList();
  final second = words.length > 1
      ? words[1].characters.first.toUpperCase()
      : firstWordCharacters.length > 1
      ? firstWordCharacters[1].toUpperCase()
      : '';
  return '$first$second';
}

Map<int, String> _emiInitialsById(List<EmiDetail> items) {
  final counts = <String, int>{};
  for (final item in items) {
    final initial = _emiName(item.emi.name).characters.first.toUpperCase();
    counts.update(initial, (value) => value + 1, ifAbsent: () => 1);
  }
  return {
    for (final item in items)
      item.emi.id: _emiAvatarInitials(
        item.emi.name,
        (counts[_emiName(item.emi.name).characters.first.toUpperCase()] ?? 0) >
            1,
      ),
  };
}

class _EmiAvatar extends StatelessWidget {
  const _EmiAvatar({
    required this.color,
    required this.initials,
    this.completed = false,
  });

  final Color color;
  final String initials;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.colorsOf(context);
    return SizedBox.square(
      dimension: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: SizedBox.square(
              dimension: 40,
              child: Center(
                child: Text(
                  initials,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          if (completed)
            Positioned(
              right: -2,
              bottom: -2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.receive,
                  shape: BoxShape.circle,
                  border: Border.all(color: tokens.surface, width: 2),
                ),
                child: Icon(
                  Icons.check,
                  size: 13,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _emiLenderName(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .map((word) {
      const acronyms = {'hdfc', 'sbi', 'icici', 'idfc'};
      return acronyms.contains(word.toLowerCase())
          ? word.toUpperCase()
          : displayName(word);
    })
    .join(' ');
int _wholeRupees(int paise) => (paise / 100).round() * 100;

const _emiAgendaPalette = <Color>[
  Color(0xFF0F766E),
  Color(0xFF1D4ED8),
  Color(0xFF6D28D9),
  Color(0xFF0E7490),
  Color(0xFFBE185D),
  Color(0xFF4338CA),
];

Map<int, Color> _emiAgendaColors(List<EmiDetail> items) {
  final ordered = [...items]
    ..sort((a, b) {
      final byDate = a.emi.createdAt.compareTo(b.emi.createdAt);
      return byDate == 0 ? a.emi.id.compareTo(b.emi.id) : byDate;
    });
  return {
    for (var index = 0; index < ordered.length; index++)
      ordered[index].emi.id:
          _emiAgendaPalette[index % _emiAgendaPalette.length],
  };
}

class _EmiGroupHeader extends StatelessWidget {
  const _EmiGroupHeader({
    required this.day,
    required this.items,
    required this.completed,
    required this.onMarkAll,
  });

  final DateTime day;
  final List<EmiDetail> items;
  final bool completed;
  final VoidCallback onMarkAll;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.colorsOf(context);
    final days = day.difference(dateOnly(DateTime.now())).inDays;
    final urgency = days < 0
        ? (Theme.of(context).brightness == Brightness.dark
              ? tokens.pay
              : const Color(0xFFB91C1C))
        : days <= 7
        ? (Theme.of(context).brightness == Brightness.dark
              ? tokens.emi
              : const Color(0xFFB45309))
        : Theme.of(context).brightness == Brightness.dark
        ? tokens.secondaryText
        : const Color(0xFF475569);
    final count = '${items.length} ${items.length == 1 ? 'EMI' : 'EMIs'}';
    final when = days < 0
        ? 'overdue by ${-days} days'
        : days == 0
        ? 'due today'
        : days == 1
        ? 'due tomorrow'
        : 'in $days days';
    final total = items.fold<int>(
      0,
      (sum, item) =>
          sum +
          (completed
              ? item.paidPaise
              : item.amountForInstallment(item.nextUnpaidInstallment!.number)),
    );
    final canMarkAll =
        !completed &&
        days <= 7 &&
        items.any((item) => item.emi.status != EmiStatus.paused);
    return SizedBox(
      height: 52,
      child: ColoredBox(
        color: tokens.background,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEE d MMM').format(day),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: tokens.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: count,
                            style: TextStyle(color: tokens.secondaryText),
                          ),
                          if (!completed)
                            TextSpan(
                              text: ' · $when',
                              style: TextStyle(color: urgency),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (canMarkAll)
                IconButton(
                  tooltip: 'Mark all paid',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  onPressed: onMarkAll,
                  icon: const Icon(Icons.done_all, size: 18),
                ),
              const SizedBox(width: 4),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AmountText(
                    _wholeRupees(total),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: tokens.text,
                    ),
                  ),
                  Text(
                    completed ? 'paid total' : 'due total',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      color: tokens.secondaryText,
                    ),
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

class _EmiActiveFooter extends StatelessWidget {
  const _EmiActiveFooter({required this.showTips, required this.onAdd});
  final bool showTips;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          Material(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_circle_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Add another EMI',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: tokens.text,
                              ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: tokens.secondaryText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (showTips)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.swipe_right_alt,
                    size: 18,
                    color: tokens.secondaryText,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Swipe right to mark paid · Long-press for more',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: tokens.secondaryText,
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

class _EmiCompletedFooter extends StatelessWidget {
  const _EmiCompletedFooter();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: Text(
      'Finished EMIs stay here for your records.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: AppTheme.colorsOf(context).secondaryText,
      ),
    ),
  );
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
  static bool _shown = false;
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  @override
  void initState() {
    super.initState();
    if (_shown) {
      _draw.value = 1;
    } else {
      _shown = true;
      _draw.forward();
    }
  }

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
                        '$names ${DateFormat('MMM yyyy').format(point.month)} - ${formatMoney(_wholeRupees(point.balancePaise))}',
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
              AmountText(
                _wholeRupees(points.first.balancePaise),
                compact: true,
              ),
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
  final _controller = TextEditingController();
  bool _editing = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    int value;
    try {
      value = parseRupeesToPaise(_controller.text);
      if (value <= 0) throw const FormatException();
    } on FormatException {
      setState(() => _error = 'Enter an amount above zero');
      return;
    }
    FocusScope.of(context).unfocus();
    final db = ref.read(databaseProvider);
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: _key, value: value.toString()),
        );
    if (mounted) {
      setState(() {
        _editing = false;
        _error = null;
      });
    }
  }

  Future<void> _remove() async {
    final db = ref.read(databaseProvider);
    await (db.delete(
      db.settings,
    )..where((table) => table.key.equals(_key))).go();
    if (mounted) setState(() => _editing = false);
  }

  Widget _compactContent(BuildContext context) {
    final tokens = AppTheme.colorsOf(context);
    final income = ref.watch(personalEmiIncomeProvider).valueOrNull;
    final now = DateTime.now();
    final thisMonth = scheduledPersonalEmiAmountInMonth(widget.items, now);
    final nextMonth = scheduledPersonalEmiAmountInMonth(
      widget.items,
      DateTime(now.year, now.month + 1),
    );
    final share = personalEmiIncomePercent(thisMonth, income);
    final nextShare = personalEmiIncomePercent(nextMonth, income);
    final riskShare = math.max(share ?? 0, nextShare ?? 0);
    final label = personalEmiIncomeZone(riskShare);
    final shareText = privacyAmountsHidden ? hiddenAmount : '${share ?? 0}%';
    final nextText = privacyAmountsHidden ? hiddenAmount : '${nextShare ?? 0}%';
    final palette = AppTheme.homePaletteOf(context);
    Widget monthFigure(String month, String percent, int payment) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          month,
          style: TextStyle(color: tokens.secondaryText, fontSize: 13),
        ),
        Text(
          percent,
          style: TextStyle(
            color: tokens.text,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          '${formatMoney(payment)} of ${formatMoney(income!)} income',
          style: TextStyle(color: tokens.secondaryText, fontSize: 12),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Monthly income',
                  style: TextStyle(
                    color: tokens.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: tokens.text),
                onPressed: () {
                  _controller.text = income == null
                      ? ''
                      : NumberFormat.decimalPattern(
                          'en_IN',
                        ).format(income / 100);
                  setState(() {
                    _editing = !_editing;
                    _error = null;
                  });
                },
                icon: Icon(
                  _editing ? Icons.close : Icons.edit_outlined,
                  size: 18,
                ),
                label: Text(
                  _editing
                      ? 'Cancel'
                      : income == null
                      ? 'Add'
                      : 'Edit',
                ),
              ),
            ],
          ),
          if (_editing) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                prefixText: '₹ ',
                labelText: 'Take-home income per month',
                hintText: 'e.g. 60,000',
                filled: true,
                fillColor: palette.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.text,
                  foregroundColor: palette.surface,
                ),
                icon: const Icon(Icons.check),
                label: const Text('Save monthly income'),
              ),
            ),
            if (income != null)
              TextButton.icon(
                onPressed: _remove,
                style: TextButton.styleFrom(
                  foregroundColor: tokens.secondaryText,
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove saved income'),
              ),
          ] else if (income == null)
            const Text('Add monthly income to see your EMI share.')
          else ...[
            Center(
              child: Column(
                children: [
                  _IncomeRiskGauge(percent: riskShare),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: _incomeRiskColor(context, riskShare),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: monthFigure('This month', shareText, thisMonth),
                ),
                const SizedBox(width: 12),
                Expanded(child: monthFigure('Next month', nextText, nextMonth)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Risk level uses the higher of the two months.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.secondaryText),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Most lenders prefer under 40–50%.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.secondaryText),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _compactContent(context);
}

Color _incomeRiskColor(BuildContext context, int percent) {
  final palette = AppTheme.homePaletteOf(context);
  if (percent < 30) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppTheme.darkColors.receive
        : AppTheme.heroEnd;
  }
  if (percent < 40) return palette.emiTone.text;
  return palette.out.text;
}

class _IncomeRiskGauge extends StatelessWidget {
  const _IncomeRiskGauge({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.colorsOf(context);
    final zones = [
      tokens.receive,
      tokens.emi,
      Color.lerp(tokens.emi, tokens.pay, .5)!,
      tokens.pay,
    ];
    return Semantics(
      label: privacyAmountsHidden
          ? 'EMI income risk hidden'
          : 'EMI income risk, ${personalEmiIncomeZone(percent)}, $percent percent',
      child: SizedBox(
        width: 150,
        height: 94,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                size: const Size(150, 94),
                painter: _IncomeRiskPainter(
                  percent: privacyAmountsHidden ? null : percent,
                  zones: zones,
                  marker: tokens.text,
                  surface: tokens.surfaceContainer,
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              child: Text(
                privacyAmountsHidden ? hiddenAmount : '$percent%',
                style: TextStyle(
                  color: tokens.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomeRiskPainter extends CustomPainter {
  const _IncomeRiskPainter({
    required this.percent,
    required this.zones,
    required this.marker,
    required this.surface,
  });
  final int? percent;
  final List<Color> zones;
  final Color marker, surface;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 5);
    final radius = math.min(size.width / 2 - 9, size.height - 13);
    final rect = Rect.fromCircle(center: center, radius: radius);
    const stops = [0.0, .3, .4, .5, 1.0];
    for (var i = 0; i < zones.length; i++) {
      final start = math.pi * (1 + stops[i]) + .025;
      final sweep = math.pi * (stops[i + 1] - stops[i]) - .05;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = zones[i]
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 10,
      );
    }
    if (percent == null) return;
    final angle = math.pi * (1 + percent!.clamp(0, 100) / 100);
    final point = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
    canvas.drawCircle(point, 7, Paint()..color = surface);
    canvas.drawCircle(point, 4, Paint()..color = marker);
  }

  @override
  bool shouldRepaint(covariant _IncomeRiskPainter old) =>
      percent != old.percent ||
      marker != old.marker ||
      surface != old.surface ||
      !listEquals(zones, old.zones);
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
    padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
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
          obscureAmount: privacyAmountsHidden,
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

class _EmiPayoffPlanner extends StatefulWidget {
  const _EmiPayoffPlanner({required this.items});
  final List<EmiDetail> items;

  @override
  State<_EmiPayoffPlanner> createState() => _EmiPayoffPlannerState();
}

class _EmiPayoffPlannerState extends State<_EmiPayoffPlanner> {
  int _extraPaise = 0;
  int _requestedExtraPaise = 0;
  Timer? _extraDebounce;
  final bool _reuseFreed = true;

  @override
  void dispose() {
    _extraDebounce?.cancel();
    super.dispose();
  }

  void _stepExtra(int direction) {
    setState(
      () => _requestedExtraPaise = (_requestedExtraPaise + direction * 50000)
          .clamp(0, 2000000),
    );
    _extraDebounce?.cancel();
    _extraDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _extraPaise = _requestedExtraPaise);
    });
  }

  int _wholePaise(int amount) => (amount / 100).round() * 100;

  Widget _compactPlan(
    BuildContext context,
    EmiPayoffPlan plan,
    int thisMonthPaise,
    EmiDetail? skipped,
  ) {
    final tokens = AppTheme.colorsOf(context);
    final target = plan.ordered
        .where((item) => item.emi.id == plan.targetId)
        .firstOrNull;
    final remaining = widget.items.fold<int>(
      0,
      (sum, item) => sum + item.remainingBalancePaise,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${plan.monthsSooner} ${plan.monthsSooner == 1 ? 'month' : 'months'} sooner',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Debt-free ${DateFormat('MMM yyyy').format(plan.plannedEnd)} instead of ${DateFormat('MMM yyyy').format(plan.originalEnd)}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        Text(
          _extraPaise == 0
              ? 'If you keep paying ${formatMoney(_wholePaise(thisMonthPaise))} every month, even after some EMIs end.'
              : 'If you pay ${formatMoney(_wholePaise(thisMonthPaise))} + ${formatMoney(_wholePaise(_extraPaise))} every month, even after some EMIs end.',
        ),
        const SizedBox(height: 22),
        Text(
          'Add extra per month',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton.outlined(
              tooltip: 'Decrease extra by 500',
              onPressed: _requestedExtraPaise == 0
                  ? null
                  : () => _stepExtra(-1),
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Center(
                child: AmountText(
                  _wholePaise(_requestedExtraPaise),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            IconButton.outlined(
              tooltip: 'Increase extra by 500',
              onPressed: _requestedExtraPaise >= 2000000
                  ? null
                  : () => _stepExtra(1),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (target != null) ...[
          const SizedBox(height: 20),
          Text(
            'Start with: ${_emiName(target.emi.name)} (${formatMoney(_wholePaise(target.remainingBalancePaise))} left)',
          ),
        ],
        const SizedBox(height: 14),
        if (!plan.hasRates)
          Text(
            'No interest recorded, so your total stays ${formatMoney(_wholePaise(remaining))}. You just finish sooner.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.secondaryText),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('How this works'),
          children: [
            Text(
              plan.hasRates
                  ? 'Highest known interest first; unknown rates follow by smallest balance.'
                  : 'Smallest remaining balance first because no rates are recorded.',
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < plan.ordered.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('${i + 1}. ${_emiName(plan.ordered[i].emi.name)}'),
                trailing: AmountText(
                  _wholePaise(plan.ordered[i].remainingBalancePaise),
                ),
              ),
            if (skipped != null && target != null)
              Text(
                '${_emiName(skipped.emi.name)} is already paid by this month\'s installment, so extra goes to ${_emiName(target.emi.name)}.',
              ),
            if (plan.hasRates)
              Wrap(
                spacing: 4,
                children: [
                  const Text('Estimated interest saved:'),
                  AmountText(_wholePaise(plan.interestSavedPaise)),
                ],
              ),
            const SizedBox(height: 8),
            const Text(
              'Some lenders charge prepayment fees. Check before paying extra.',
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = dateOnly(DateTime.now());
    final plan = simulateEmiPayoff(
      items: widget.items,
      today: now,
      extraPerMonthPaise: _extraPaise,
      reuseFreedPayments: _reuseFreed,
    );
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
    return _compactPlan(context, plan, thisMonthPaise, skipped);
  }
}

class _SwipePayTile extends StatefulWidget {
  const _SwipePayTile({
    super.key,
    required this.detail,
    required this.onPaid,
    required this.scrolling,
    required this.child,
  });
  final EmiDetail detail;
  final Future<void> Function() onPaid;
  final ValueListenable<bool> scrolling;
  final Widget child;
  @override
  State<_SwipePayTile> createState() => _SwipePayTileState();
}

class _SwipePayTileState extends State<_SwipePayTile>
    with SingleTickerProviderStateMixin {
  Offset? _start;
  int? _pointer;
  VelocityTracker? _velocity;
  late final AnimationController _slide = AnimationController.unbounded(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  bool _ticked = false;
  bool _claimed = false;
  bool _rejected = false;
  bool _committing = false;

  void _clearPointer() {
    _pointer = null;
    _start = null;
    _velocity = null;
    _claimed = false;
    _rejected = false;
    if (_slide.value != 0) {
      unawaited(_slide.animateTo(0, curve: Curves.easeOutCubic));
    }
  }

  @override
  void initState() {
    super.initState();
    widget.scrolling.addListener(_onScroll);
  }

  void _onScroll() {
    if (widget.scrolling.value) _clearPointer();
  }

  @override
  void dispose() {
    widget.scrolling.removeListener(_onScroll);
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final threshold = constraints.maxWidth * .45;
      final installment = widget.detail.nextUnpaidInstallment!;
      return ClipRRect(
        borderRadius: BorderRadius.zero,
        child: Listener(
          onPointerDown: (event) {
            if (_pointer != null || widget.scrolling.value || _committing) {
              return;
            }
            _pointer = event.pointer;
            _start = event.position;
            _velocity = VelocityTracker.withKind(event.kind)
              ..addPosition(event.timeStamp, event.position);
            _ticked = false;
            _claimed = false;
            _rejected = false;
          },
          onPointerMove: (event) {
            if (event.pointer != _pointer || _start == null || _rejected) {
              return;
            }
            _velocity?.addPosition(event.timeStamp, event.position);
            final delta = event.position - _start!;
            if (!_claimed) {
              if (delta.distance < 24) return;
              if (delta.dx <= 0 || delta.dx < 2.5 * delta.dy.abs()) {
                _rejected = true;
                return;
              }
              _claimed = true;
            }
            final next = ((delta.dx - 12) * .8).clamp(
              0.0,
              constraints.maxWidth * .8,
            );
            if (!_ticked && next >= threshold) {
              _ticked = true;
              HapticFeedback.selectionClick();
            }
            _slide.stop();
            _slide.value = next;
          },
          onPointerUp: (event) {
            if (event.pointer != _pointer) return;
            _velocity?.addPosition(event.timeStamp, event.position);
            final speed = _velocity?.getVelocity().pixelsPerSecond.dx ?? 0;
            final confirmed =
                _claimed && (_slide.value >= threshold || speed > 700);
            _clearPointer();
            if (confirmed) {
              _committing = true;
              unawaited(
                widget.onPaid().whenComplete(() {
                  _committing = false;
                }),
              );
            }
          },
          onPointerCancel: (event) {
            if (event.pointer != _pointer) return;
            _clearPointer();
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
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
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
                              _wholeRupees(
                                widget.detail.amountForInstallment(
                                  installment.number,
                                ),
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
              ),
              AnimatedBuilder(
                animation: _slide,
                child: widget.child,
                builder: (context, child) => Transform.translate(
                  offset: Offset(_slide.value, 0),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _EmiTileBadge extends StatelessWidget {
  const _EmiTileBadge({required this.label, required this.urgent});

  final String label;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.colorsOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = urgent
        ? (dark ? tokens.pay : const Color(0xFFB91C1C))
        : dark
        ? tokens.emi
        : const Color(0xFFB45309);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: foreground, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: foreground,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EmiRow extends StatelessWidget {
  const _EmiRow({
    super.key,
    required this.detail,
    required this.completed,
    required this.scrolling,
    this.onLongPress,
    this.arcColor,
    this.avatarInitials,
  });

  final EmiDetail detail;
  final bool completed;
  final ValueListenable<bool> scrolling;
  final VoidCallback? onLongPress;
  final Color? arcColor;
  final String? avatarInitials;

  @override
  Widget build(BuildContext context) {
    final emi = detail.emi;
    final tokens = AppTheme.colorsOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = arcColor ?? tokens.emi;
    final nameColor = Color.lerp(color, tokens.text, dark ? .58 : 0)!;
    final outstandingColor = AppTheme.homePaletteOf(context).emiTone.text;
    final next = detail.nextUnpaidInstallment;
    final amount = completed
        ? detail.paidPaise
        : detail.amountForInstallment(next!.number);
    final due = next?.dueDate;
    final days = due == null
        ? null
        : dateOnly(due).difference(dateOnly(DateTime.now())).inDays;
    final status = completed
        ? null
        : days != null && days < 0
        ? 'Overdue ${-days} days'
        : detail.remainingInstallments == 1
        ? null
        : detail.remainingInstallments == 2
        ? 'Closing soon'
        : days == 0
        ? 'Due today'
        : days != null && days <= 7
        ? days == 1
              ? 'Due tomorrow'
              : 'in $days days'
        : null;
    final badgeUrgent = days != null && days < 0;
    final subtitle = _emiLenderName(
      emi.provider?.isNotEmpty == true ? emi.provider! : emi.type,
    );
    final secondary = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 13,
      color: dark ? tokens.secondaryText : const Color(0xFF475569),
    );
    final statusTextStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: dark ? tokens.text : const Color(0xFF0F172A),
    );
    final greenTextStyle = statusTextStyle?.copyWith(
      fontWeight: FontWeight.w600,
      color: dark ? Theme.of(context).colorScheme.primary : AppTheme.heroEnd,
    );
    final avatar = _EmiAvatar(
      color: color,
      initials:
          avatarInitials ?? _emiName(emi.name).characters.first.toUpperCase(),
      completed: completed,
    );
    final amountStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: completed ? tokens.secondaryText : tokens.text,
    );
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 84),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            avatar,
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _emiName(emi.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: completed
                                    ? tokens.secondaryText
                                    : nameColor,
                              ),
                        ),
                      ),
                      ...[
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 92),
                          child: Tooltip(
                            message: completed
                                ? 'Total paid'
                                : 'Next installment amount',
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: AmountText(
                                _wholeRupees(amount),
                                style: amountStyle,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: secondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 92),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AmountText(
                                _wholeRupees(
                                  completed
                                      ? amount
                                      : detail.remainingBalancePaise,
                                ),
                                style: completed
                                    ? secondary
                                    : secondary?.copyWith(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: outstandingColor,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                              ),
                              Text(
                                completed ? ' paid' : ' outstanding',
                                style: secondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          completed
                              ? 'All ${emi.tenureMonths} paid'
                              : detail.remainingInstallments == 1
                              ? 'Last EMI'
                              : '${detail.remainingInstallments} EMIs left${detail.paidInstallments > 0 ? ' · ${detail.paidInstallments} paid' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: completed || detail.remainingInstallments == 1
                              ? greenTextStyle
                              : statusTextStyle,
                        ),
                      ),
                      if (status != null) ...[
                        const SizedBox(width: 4),
                        _EmiTileBadge(label: status, urgent: badgeUrgent),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      label:
          '${_emiName(emi.name)}, ${detail.remainingInstallments} EMIs left of ${emi.tenureMonths}, ${formatMoney(_wholeRupees(emi.emiAmountPaise))} per month${completed ? '' : ', ${formatMoney(_wholeRupees(detail.remainingBalancePaise))} outstanding'}',
      child: _EmiRowGesture(
        scrolling: scrolling,
        onLongPress: onLongPress,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => EmiDetailScreen(emi.id))),
        child: content,
      ),
    );
  }
}

class _EmiRowGesture extends StatefulWidget {
  const _EmiRowGesture({
    required this.child,
    required this.scrolling,
    required this.onTap,
    this.onLongPress,
  });
  final Widget child;
  final ValueListenable<bool> scrolling;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<_EmiRowGesture> createState() => _EmiRowGestureState();
}

class _EmiRowGestureState extends State<_EmiRowGesture> {
  int? _pointer;
  Offset? _start;
  double _travel = 0;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (widget.scrolling.value || _pointer != null) return;
      _pointer = event.pointer;
      _start = event.position;
      _travel = 0;
    },
    onPointerMove: (event) {
      if (event.pointer != _pointer || _start == null) return;
      _travel = math.max(_travel, (event.position - _start!).distance);
    },
    onPointerUp: (event) {
      if (event.pointer != _pointer) return;
      _pointer = null;
      _start = null;
    },
    onPointerCancel: (event) {
      if (event.pointer != _pointer) return;
      _pointer = null;
      _start = null;
    },
    child: Material(
      color: AppTheme.colorsOf(context).background,
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                if (_pointer != null &&
                    _travel < 8 &&
                    !widget.scrolling.value) {
                  widget.onLongPress!();
                }
              },
        child: widget.child,
      ),
    ),
  );
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
    final details = ref.watch(allEmiDetailsProvider);
    final detail = details.valueOrNull
        ?.where((item) => item.emi.id == widget.id)
        .firstOrNull;
    if (detail?.category == EmiCategory.givenToFriends) {
      return EmiAgreementDetailScreen(widget.id);
    }
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
                    if (detail.emi.productPricePaise != null ||
                        detail.emi.feesPaise > 0 ||
                        detail.emi.interestRate != null) ...[
                      const SizedBox(height: 24),
                      _EmiFinancingTerms(emi: detail.emi),
                    ],
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
                label:
                    detail.emi.productPricePaise != null ||
                        detail.emi.feesPaise > 0
                    ? 'EMI total'
                    : 'Total payable',
                value: formatMoney(detail.totalRepaymentPaise),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmiFinancingTerms extends StatelessWidget {
  const _EmiFinancingTerms({required this.emi});

  final Emi emi;

  @override
  Widget build(BuildContext context) {
    final rate = emi.interestRate;
    final displayedRate = rate == null
        ? null
        : emi.interestPeriod == EmiRatePeriod.monthly
        ? rate / 12
        : rate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Financing terms',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (emi.productPricePaise case final price?)
          _SummaryLine('Product price', formatMoney(price)),
        if (emi.downPaymentPaise case final downPayment?)
          _SummaryLine('Down payment', formatMoney(downPayment)),
        _SummaryLine('Principal', formatMoney(emi.principalPaise)),
        if (displayedRate != null)
          _SummaryLine(
            '${emi.interestMethod == EmiInterestMethod.flat ? 'Flat' : 'Reducing'} interest · '
                '${emi.interestPeriod == EmiRatePeriod.monthly ? 'monthly' : 'annual'}',
            '${NumberFormat('0.####').format(displayedRate)}%',
          ),
        if (emi.feesPaise > 0)
          _SummaryLine('Separate fees', formatMoney(emi.feesPaise)),
        if (emi.contractualEmi)
          Text(
            'Entered EMI differs from the calculated amount; the contract amount is kept.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.colorsOf(context).secondaryText,
            ),
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
    this.category = EmiCategory.personal,
    this.initialEmiAmount,
    this.initialPrincipal,
    this.initialInterestRate,
    this.initialName,
    this.initialTenureMonths,
    this.initialFrequency,
    this.initialDueDate,
  });

  final Emi? emi;
  final EmiCategory category;
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
  int _formStep = 0;
  final _formScrollController = ScrollController();

  void _goToStep(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _formStep = step;
      _scheduleError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _formScrollController.hasClients) {
        _formScrollController.jumpTo(0);
      }
    });
  }

  String? _stepError(int step) {
    if (step == 0) {
      if (requiredText(_name.text) != null) return 'Enter an EMI name.';
      final phone = _friendPhone.text.replaceAll(RegExp(r'\D'), '');
      if (_isFriend && phone.isNotEmpty && phone.length < 10) {
        return 'Enter a valid phone number.';
      }
      if (_isProduct) {
        if (amountText(_productPrice.text) != null) {
          return 'Enter the product price.';
        }
        if (_downPayment.text.trim().isNotEmpty &&
            amountText(_downPayment.text) != null) {
          return 'Enter a valid down payment.';
        }
      }
    } else if (step == 1) {
      if (amountText(_amount.text) != null) {
        return 'Enter a valid installment amount.';
      }
      if (_positiveIntegerValidator(_tenure.text) != null) {
        return 'Enter a valid number of installments.';
      }
      final paidError = _paidValidator(_paid.text);
      if (paidError != null) return paidError;
    } else if (step == 2) {
      final rateError = _interestValidator(_interest.text);
      if (rateError != null) return rateError;
      if (_fees.text.trim().isNotEmpty && amountText(_fees.text) != null) {
        return 'Enter a valid fee amount.';
      }
      if (_principal.text.trim().isNotEmpty &&
          amountText(_principal.text) != null) {
        return 'Enter a valid principal amount.';
      }
    }
    return null;
  }

  void _continueForm() {
    final error = _stepError(_formStep);
    if (error != null) {
      setState(() => _scheduleError = error);
      return;
    }
    _goToStep(_formStep + 1);
  }

  bool get _isFriend =>
      widget.category == EmiCategory.givenToFriends ||
      isFriendRepaymentType(widget.emi?.type);
  bool get _isProduct => _type == 'Phone/Product';

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
  late final _productPrice = TextEditingController(
    text: widget.emi?.productPricePaise == null
        ? ''
        : rupeesText(widget.emi!.productPricePaise!),
  );
  late final _downPayment = TextEditingController(
    text: widget.emi?.downPaymentPaise == null
        ? ''
        : rupeesText(widget.emi!.downPaymentPaise!),
  );
  late final _fees = TextEditingController(
    text: widget.emi == null || widget.emi!.feesPaise == 0
        ? ''
        : rupeesText(widget.emi!.feesPaise),
  );
  late final _tenure = TextEditingController(
    text:
        widget.emi?.tenureMonths.toString() ??
        widget.initialTenureMonths?.toString() ??
        '12',
  );
  late final _notes = TextEditingController(text: widget.emi?.notes ?? '');
  final _friendPhone = TextEditingController();
  late DateTime _agreementDate = widget.emi?.createdAt ?? DateTime.now();
  bool _friendTermsLocked = false;
  late final _interest = TextEditingController(
    text:
        (widget.emi?.interestRate == null
            ? null
            : widget.emi!.interestPeriod == EmiRatePeriod.monthly
            ? (widget.emi!.interestRate! / 12).toString()
            : widget.emi!.interestRate!.toString()) ??
        widget.initialInterestRate ??
        '',
  );
  late EmiRatePeriod _ratePeriod =
      widget.emi?.interestPeriod ?? EmiRatePeriod.annual;
  late EmiInterestMethod _interestMethod =
      widget.emi?.interestMethod ?? EmiInterestMethod.reducing;
  late bool _keepEnteredEmi = widget.emi?.contractualEmi ?? false;
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
  late String _type = _isFriend
      ? friendRepaymentSubtype(widget.emi?.type)
      : widget.emi?.type ?? 'Loan';
  late String _providerChoice = _isFriend && widget.emi?.provider == null
      ? 'Other'
      : _providerChipFor(widget.emi?.provider);
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
    _interest,
    _productPrice,
    _downPayment,
    _fees,
    _paid,
  ]);

  @override
  void initState() {
    super.initState();
    for (final input in [
      _principal,
      _tenure,
      _interest,
      _productPrice,
      _downPayment,
    ]) {
      input.addListener(_syncCalculatedEmi);
    }
    _selectedPaymentTile = null;
    if (_isFriend && widget.emi != null) {
      ref
          .read(financeRepositoryProvider)
          .friendEmiPhone(widget.emi!.id, widget.emi!.name)
          .then((phone) {
            if (mounted && phone != null) _friendPhone.text = phone;
          });
    }
  }

  void _syncCalculatedEmi() {
    if (_keepEnteredEmi || _friendTermsLocked) return;
    final principal = _principal.text.trim().isNotEmpty
        ? _tryPaise(_principal.text)
        : _isProduct
        ? _estimatedPrincipal()
        : null;
    final tenure = int.tryParse(_tenure.text.trim());
    final rate = _annualRate();
    if (principal == null ||
        principal <= 0 ||
        tenure == null ||
        tenure <= 0 ||
        (_interest.text.trim().isNotEmpty && rate == null)) {
      return;
    }
    final calculated = expectedEmiInstallmentPaise(
      principalPaise: principal,
      tenure: tenure,
      annualInterestRate: rate ?? 0,
      interestMethod: _interestMethod,
    );
    if (calculated > 0 && _tryPaise(_amount.text) != calculated) {
      _amount.text = rupeesText(calculated);
    }
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
        _friendTermsLocked =
            _isFriend &&
            (detail.payments.isNotEmpty ||
                detail.emi.initialPaidInstallments > 0);
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
    _formScrollController.dispose();
    _name.dispose();
    _provider.dispose();
    _principal.dispose();
    _amount.dispose();
    _tenure.dispose();
    _notes.dispose();
    _interest.dispose();
    _productPrice.dispose();
    _downPayment.dispose();
    _fees.dispose();
    _paid.dispose();
    _friendPhone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.homePaletteOf(context);
    final formColors = AppTheme.colorsOf(context);
    final accent = AppTheme.emiIdentityInkOf(context);
    final onAccent = formColors.background;
    final previousNames = <String>[];
    if (widget.emi == null) {
      final previous = [...?ref.watch(allEmiDetailsProvider).valueOrNull]
        ..sort((a, b) => b.emi.createdAt.compareTo(a.emi.createdAt));
      final seen = <String>{};
      for (final detail in previous) {
        final name = detail.emi.name.trim();
        if (detail.category != widget.category ||
            name.isEmpty ||
            !seen.add(name.toLowerCase())) {
          continue;
        }
        previousNames.add(name);
        if (previousNames.length == 6) break;
      }
    }
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
      if (_isFriend)
        const ButtonSegment(value: PaymentFrequency.once, label: Text('Once')),
      if (_isFriend || _frequency == PaymentFrequency.yearly)
        const ButtonSegment(
          value: PaymentFrequency.yearly,
          label: Text('Yearly'),
        ),
    ];
    final availableHeight =
        (MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom) *
        0.92;
    return Theme(
      data: Theme.of(context).copyWith(
        visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
        colorScheme: Theme.of(context).colorScheme.copyWith(
          primary: accent,
          onPrimary: onAccent,
          primaryContainer: accent.withValues(alpha: .12),
          onPrimaryContainer: accent,
          onSurface: formColors.text,
          onSurfaceVariant: formColors.secondaryText,
          surface: formColors.surface,
          surfaceContainer: formColors.surfaceContainer,
        ),
        chipTheme: Theme.of(context).chipTheme.copyWith(
          selectedColor: accent.withValues(alpha: .12),
          side: BorderSide(color: palette.line),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: onAccent,
          ),
        ),
      ),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: availableHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                  Row(
                    children: [
                      for (final (index, label) in const [
                        'Agreement',
                        'Schedule',
                        'Financing',
                        'Review',
                      ].indexed)
                        Expanded(
                          child: InkWell(
                            onTap: () => _goToStep(index),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                children: [
                                  Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: _formStep == index
                                          ? palette.text
                                          : palette.text2,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _formStep == index
                                          ? palette.text
                                          : palette.text2,
                                      fontSize: 11,
                                      fontWeight: _formStep == index
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_scheduleError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ValidationMessage(_scheduleError!),
                    ),
                  Flexible(
                    fit: FlexFit.loose,
                    child: ListView(
                      controller: _formScrollController,
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 8),
                      children: [
                        Offstage(
                          offstage: _formStep != 0,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SelectorGroup(
                                label: 'TYPE',
                                child: SegmentedToggle<String>(
                                  segments: const [
                                    ButtonSegment(
                                      value: 'Loan',
                                      label: Text('Loan'),
                                    ),
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
                                  selectedBackground: accent.withValues(
                                    alpha: .12,
                                  ),
                                  selectedForeground: accent,
                                  filled: true,
                                  onSelectionChanged: _friendTermsLocked
                                      ? null
                                      : (value) =>
                                            setState(() => _type = value.first),
                                ),
                              ),
                              if (_type == 'Credit Card') ...[
                                const SizedBox(height: 8),
                                Text(
                                  'This form tracks a fixed card EMI. Card statements, minimum dues and purchase conversions are not included in this repayment schedule.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: palette.text2),
                                ),
                              ],
                              const SizedBox(height: 14),
                              _FieldLabel('NAME'),
                              const SizedBox(height: 7),
                              TextFormField(
                                controller: _name,
                                decoration: _filledDecoration(
                                  context,
                                  hint: _isFriend
                                      ? 'Person or agreement name'
                                      : 'Loan name',
                                  icon: _isFriend
                                      ? Icons.person_outline
                                      : Icons.account_balance_outlined,
                                ),
                                validator: requiredText,
                              ),
                              if (previousNames.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  'Recently used names',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: palette.text2),
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  height: 38,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: previousNames.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(width: 8),
                                    itemBuilder: (context, index) => ActionChip(
                                      label: Text(previousNames[index]),
                                      onPressed: () =>
                                          _name.text = previousNames[index],
                                    ),
                                  ),
                                ),
                              ],
                              if (_isFriend) ...[
                                const SizedBox(height: 14),
                                const _FieldLabel('PHONE NUMBER (OPTIONAL)'),
                                const SizedBox(height: 7),
                                TextFormField(
                                  controller: _friendPhone,
                                  keyboardType: TextInputType.phone,
                                  decoration: _filledDecoration(
                                    context,
                                    hint: 'Phone number',
                                    icon: Icons.phone_outlined,
                                  ),
                                  validator: (value) {
                                    final digits = (value ?? '').replaceAll(
                                      RegExp(r'\D'),
                                      '',
                                    );
                                    return digits.isEmpty || digits.length >= 10
                                        ? null
                                        : 'Enter a valid phone number';
                                  },
                                ),
                              ],
                              const SizedBox(height: 14),
                              _FieldLabel('LENDER'),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (final provider in _knownProviders)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: ChoiceChip(
                                          label: Text(provider),
                                          selected: _providerChoice == provider,
                                          onSelected: _friendTermsLocked
                                              ? null
                                              : (_) => setState(
                                                  () => _providerChoice =
                                                      provider,
                                                ),
                                        ),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: const Text('Other'),
                                        selected: _providerChoice == 'Other',
                                        onSelected: _friendTermsLocked
                                            ? null
                                            : (_) => setState(
                                                () => _providerChoice = 'Other',
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_providerChoice == 'Other') ...[
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _provider,
                                  enabled: !_friendTermsLocked,
                                  decoration: _filledDecoration(
                                    context,
                                    hint: 'Lender name',
                                  ),
                                ),
                              ],
                              if (_isProduct) ...[
                                const SizedBox(height: 14),
                                _LabeledInput(
                                  label: 'PRODUCT PRICE',
                                  controller: _productPrice,
                                  enabled: !_friendTermsLocked,
                                  hint: 'Full purchase price',
                                  prefix:
                                      '${activeAmountFormatter.value.symbol} ',
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  validator: amountText,
                                ),
                                const SizedBox(height: 14),
                                _LabeledInput(
                                  label: 'DOWN PAYMENT (OPTIONAL)',
                                  controller: _downPayment,
                                  enabled: !_friendTermsLocked,
                                  hint: 'Paid upfront',
                                  prefix:
                                      '${activeAmountFormatter.value.symbol} ',
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  validator: (value) =>
                                      value?.trim().isEmpty == true
                                      ? null
                                      : amountText(value),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Offstage(
                          offstage: _formStep != 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 14),
                              IgnorePointer(
                                ignoring: _friendTermsLocked,
                                child: HeroAmountInput(
                                  controller: _amount,
                                  obscureAmount: privacyAmountsHidden,
                                  label: _isFriend
                                      ? 'INSTALLMENT TO RECEIVE'
                                      : 'MONTHLY EMI',
                                  validator: amountText,
                                  calculator: () => _openAmountCalculator(
                                    _amount,
                                    'Monthly EMI',
                                  ),
                                ),
                              ),
                              if (_type != 'Credit Card')
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Keep entered EMI'),
                                  subtitle: const Text(
                                    'Use the contract amount instead of recalculating it',
                                  ),
                                  value: _keepEnteredEmi,
                                  onChanged: _friendTermsLocked
                                      ? null
                                      : (value) {
                                          setState(
                                            () => _keepEnteredEmi = value,
                                          );
                                          if (!value) _syncCalculatedEmi();
                                        },
                                ),
                              ListenableBuilder(
                                listenable: _summaryInputs,
                                builder: (context, _) {
                                  final summary = _liveSummary();
                                  final tenure = int.tryParse(_tenure.text);
                                  if (summary == null || tenure == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      '$tenure payments · ${formatMoney(summary.totalPaise)} total to ${_isFriend ? 'receive' : 'pay'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: palette.text,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 14),
                              _FieldLabel('TENURE'),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final months in const [
                                    '6',
                                    '12',
                                    '24',
                                    '36',
                                  ])
                                    ChoiceChip(
                                      label: Text(months),
                                      selected: _tenureChoice == months,
                                      onSelected: _friendTermsLocked
                                          ? null
                                          : (_) => setState(() {
                                              _tenureChoice = months;
                                              _tenure.text = months;
                                            }),
                                    ),
                                  ChoiceChip(
                                    label: const Text('Custom'),
                                    selected: _tenureChoice == 'Custom',
                                    onSelected: _friendTermsLocked
                                        ? null
                                        : (_) => setState(
                                            () => _tenureChoice = 'Custom',
                                          ),
                                  ),
                                ],
                              ),
                              if (_tenureChoice == 'Custom') ...[
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _tenure,
                                  enabled: !_friendTermsLocked,
                                  keyboardType: TextInputType.number,
                                  decoration: _filledDecoration(
                                    context,
                                    hint: 'Number of payments',
                                  ),
                                  validator: _positiveIntegerValidator,
                                ),
                              ],
                            ],
                          ),
                        ),
                        Offstage(
                          offstage: _formStep != 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 14),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Text(
                                  'Interest & fees',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: palette.text,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                              ...[
                                _LabeledInput(
                                  label: 'INTEREST RATE (OPTIONAL)',
                                  controller: _interest,
                                  enabled: !_friendTermsLocked,
                                  hint: '0',
                                  suffix: '%',
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  validator: _interestValidator,
                                ),
                                if (_type != 'Credit Card') ...[
                                  const SizedBox(height: 8),
                                  SegmentedToggle<EmiRatePeriod>(
                                    segments: const [
                                      ButtonSegment(
                                        value: EmiRatePeriod.annual,
                                        label: Text('Per year'),
                                      ),
                                      ButtonSegment(
                                        value: EmiRatePeriod.monthly,
                                        label: Text('Per month'),
                                      ),
                                    ],
                                    selected: {_ratePeriod},
                                    selectedBackground: accent.withValues(
                                      alpha: .12,
                                    ),
                                    selectedForeground: accent,
                                    filled: true,
                                    onSelectionChanged: _friendTermsLocked
                                        ? null
                                        : (value) {
                                            setState(
                                              () => _ratePeriod = value.first,
                                            );
                                            _syncCalculatedEmi();
                                          },
                                  ),
                                  const SizedBox(height: 12),
                                  _SelectorGroup(
                                    label: 'INTEREST METHOD',
                                    child: SegmentedToggle<EmiInterestMethod>(
                                      segments: const [
                                        ButtonSegment(
                                          value: EmiInterestMethod.reducing,
                                          label: Text('Reducing balance'),
                                        ),
                                        ButtonSegment(
                                          value: EmiInterestMethod.flat,
                                          label: Text('Flat rate'),
                                        ),
                                      ],
                                      selected: {_interestMethod},
                                      selectedBackground: accent.withValues(
                                        alpha: .12,
                                      ),
                                      selectedForeground: accent,
                                      filled: true,
                                      onSelectionChanged: _friendTermsLocked
                                          ? null
                                          : (value) {
                                              setState(
                                                () => _interestMethod =
                                                    value.first,
                                              );
                                              _syncCalculatedEmi();
                                            },
                                    ),
                                  ),
                                ],
                                if (_type != 'Credit Card') ...[
                                  const SizedBox(height: 14),
                                  _LabeledInput(
                                    label: 'FEES (OPTIONAL)',
                                    controller: _fees,
                                    enabled: !_friendTermsLocked,
                                    hint: 'Separate from EMI and principal',
                                    prefix:
                                        '${activeAmountFormatter.value.symbol} ',
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    validator: (value) =>
                                        value?.trim().isEmpty == true
                                        ? null
                                        : amountText(value),
                                  ),
                                ],
                              ],
                              const SizedBox(height: 14),
                              _LabeledInput(
                                label: 'PRINCIPAL (OPTIONAL)',
                                controller: _principal,
                                enabled: !_friendTermsLocked,
                                obscureAmount: privacyAmountsHidden,
                                hint: 'Calculated if left blank',
                                prefix:
                                    '${activeAmountFormatter.value.symbol} ',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                validator: (value) =>
                                    value?.trim().isEmpty == true
                                    ? null
                                    : amountText(value),
                                calculator: () => _openAmountCalculator(
                                  _principal,
                                  'Principal',
                                ),
                              ),
                              ListenableBuilder(
                                listenable: _summaryInputs,
                                builder: (context, _) {
                                  if (_principal.text.trim().isNotEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  final estimate = _estimatedPrincipal();
                                  if (estimate == null || estimate <= 0) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      '${_isProduct ? 'Price minus down payment' : 'Calculated principal'}: ${formatMoney(estimate)}${!_isProduct && _interest.text.trim().isEmpty ? ' · assumes 0% interest' : ''}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: palette.text2),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        Offstage(
                          offstage: _formStep != 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 14),
                              _SelectorGroup(
                                label: 'FREQUENCY',
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SegmentedToggle<PaymentFrequency>(
                                    segments: frequencySegments,
                                    selected: {_frequency},
                                    selectedBackground: accent.withValues(
                                      alpha: .12,
                                    ),
                                    selectedForeground: accent,
                                    filled: true,
                                    onSelectionChanged: _friendTermsLocked
                                        ? null
                                        : (value) => setState(
                                            () => _frequency = value.first,
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              if (_isFriend) ...[
                                IgnorePointer(
                                  ignoring: _friendTermsLocked,
                                  child: DateTile(
                                    label: 'AGREEMENT DATE',
                                    value: _agreementDate,
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() => _agreementDate = value);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _DateSelector(
                                          value: _due,
                                          onChanged: (value) {
                                            if (!_friendTermsLocked) {
                                              setState(() => _due = value);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ListenableBuilder(
                                      listenable: _tenure,
                                      builder: (context, _) {
                                        final tenure = int.tryParse(
                                          _tenure.text,
                                        );
                                        return _LabeledInput(
                                          label: 'EMIS ALREADY PAID',
                                          controller: _paid,
                                          enabled: !_friendTermsLocked,
                                          hint: '0',
                                          helperText:
                                              tenure == null || tenure <= 0
                                              ? 'Number of installments already paid'
                                              : 'Number of installments already paid (0–$tenure)',
                                          keyboardType:
                                              const TextInputType.numberWithOptions(),
                                          autovalidateMode:
                                              AutovalidateMode.always,
                                          validator: _paidValidator,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Offstage(
                          offstage: _formStep != 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 14),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Text(
                                  'Payment method & notes',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: palette.text,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                              ...[
                                const _FieldLabel('PAYMENT METHOD'),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    for (final option in _methodTiles)
                                      Expanded(
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                            right: option == _methodTiles.last
                                                ? 0
                                                : 8,
                                          ),
                                          child: _PaymentTile(
                                            label: option.$1,
                                            icon: option.$2,
                                            selected:
                                                selectedPaymentTile ==
                                                option.$1,
                                            selectedFill: accent.withValues(
                                              alpha: .12,
                                            ),
                                            onTap: () => setState(() {
                                              _selectedPaymentTile = option.$1;
                                              _paymentMethodId =
                                                  _methodIdForTile(
                                                    option.$1,
                                                    methods,
                                                  );
                                            }),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),
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
                              ],
                              ListenableBuilder(
                                listenable: _summaryInputs,
                                builder: (context, _) {
                                  final summary = _liveSummary();
                                  if (summary == null) {
                                    return const SizedBox.shrink();
                                  }
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (_formStep > 0) ...[
                        TextButton(
                          onPressed: () => _goToStep(_formStep - 1),
                          child: const Text('Back'),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            shape: const StadiumBorder(),
                          ),
                          onPressed: _saving
                              ? null
                              : _formStep == 3
                              ? _save
                              : _continueForm,
                          icon: Icon(
                            _formStep == 3
                                ? Icons.save_outlined
                                : Icons.arrow_forward,
                          ),
                          label: Text(
                            _saving
                                ? 'Saving...'
                                : _formStep == 3
                                ? 'Save EMI'
                                : 'Continue',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
    final principal = _principal.text.trim().isEmpty
        ? _estimatedPrincipal()
        : _tryPaise(_principal.text);
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
    final rate = _annualRate();
    if (_interest.text.trim().isNotEmpty && rate == null) return null;
    final expected = expectedEmiInstallmentPaise(
      principalPaise: principal,
      tenure: tenure,
      annualInterestRate: rate ?? 0,
      interestMethod: _interestMethod,
    );
    final mismatch = (installment - expected).abs() > 50;
    final schedule = calculateEmiSchedule(
      principalPaise: principal,
      installmentPaise: installment,
      tenure: tenure,
      annualInterestRate: rate,
      interestMethod: _interestMethod,
      contractualEmi: _keepEnteredEmi || mismatch,
    );
    return _EmiFormSummary(
      endDate: endDate,
      remaining: remaining,
      totalPaise: schedule.totalRepaymentPaise,
      interestPaise: (schedule.totalRepaymentPaise - principal).clamp(
        0,
        schedule.totalRepaymentPaise,
      ),
      feesPaise: _type == 'Credit Card' ? 0 : (_tryPaise(_fees.text) ?? 0),
      downPaymentPaise: _isProduct ? (_tryPaise(_downPayment.text) ?? 0) : 0,
      expectedEmiPaise: expected,
      enteredEmiPaise: installment,
      hasContractualDifference: mismatch,
      keepEnteredEmi: _keepEnteredEmi,
    );
  }

  double? _annualRate() {
    final text = _interest.text.trim();
    if (text.isEmpty) return null;
    final entered = double.tryParse(text);
    if (entered == null || !entered.isFinite) return null;
    return annualizedEmiRate(entered, _ratePeriod);
  }

  int? _estimatedPrincipal() {
    if (_isProduct) {
      final price = _tryPaise(_productPrice.text);
      final downPayment = _downPayment.text.trim().isEmpty
          ? 0
          : _tryPaise(_downPayment.text);
      if (price != null && downPayment != null && price > downPayment) {
        return price - downPayment;
      }
    }
    final installment = _tryPaise(_amount.text);
    final tenure = int.tryParse(_tenure.text.trim());
    final rateText = _interest.text.trim();
    final rate = _annualRate();
    if (installment == null ||
        installment <= 0 ||
        tenure == null ||
        tenure <= 0 ||
        (rateText.isNotEmpty && rate == null)) {
      return null;
    }
    final estimate = estimatedPrincipalPaise(
      installmentPaise: installment,
      tenure: tenure,
      annualInterestRate: rate,
      interestMethod: _interestMethod,
    );
    return estimate > 0 ? estimate : null;
  }

  Future<void> _save() async {
    setState(() => _scheduleError = null);
    for (var step = 0; step < 3; step++) {
      final error = _stepError(step);
      if (error != null) {
        _goToStep(step);
        setState(() => _scheduleError = error);
        return;
      }
    }
    final interestError = _interestValidator(_interest.text);
    if (interestError != null) {
      setState(() {
        _scheduleError = interestError;
      });
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    late final int principalPaise;
    late final int emiAmountPaise;
    late final int tenure;
    late final int feesPaise;
    int? productPricePaise;
    int? downPaymentPaise;
    final interest = _annualRate();
    try {
      emiAmountPaise = parseRupeesToPaise(_amount.text);
      tenure = int.parse(_tenure.text.trim());
      feesPaise = _type != 'Credit Card' && _fees.text.trim().isNotEmpty
          ? parseRupeesToPaise(_fees.text)
          : 0;
      productPricePaise = _isProduct
          ? parseRupeesToPaise(_productPrice.text)
          : null;
      downPaymentPaise = _isProduct && _downPayment.text.trim().isNotEmpty
          ? parseRupeesToPaise(_downPayment.text)
          : null;
      principalPaise = _principal.text.trim().isEmpty
          ? _estimatedPrincipal() ?? 0
          : parseRupeesToPaise(_principal.text);
    } on FormatException catch (error) {
      setState(() => _scheduleError = error.message);
      return;
    }
    if (_isProduct &&
        (productPricePaise == null ||
            productPricePaise <= 0 ||
            (downPaymentPaise ?? 0) >= productPricePaise)) {
      setState(
        () => _scheduleError =
            'Down payment must be less than the product price.',
      );
      return;
    }
    final paidCount = int.parse(_paid.text.trim());
    if (_isFriend && _agreementDate.isAfter(DateTime.now())) {
      setState(
        () => _scheduleError = 'The agreement date cannot be in the future.',
      );
      return;
    }
    if (_isFriend && dateOnly(_due).isBefore(dateOnly(_agreementDate))) {
      setState(
        () => _scheduleError =
            'The first repayment cannot precede the agreement date.',
      );
      return;
    }
    if (_frequency == PaymentFrequency.once && tenure != 1) {
      setState(
        () => _scheduleError = 'A one-time repayment has one installment.',
      );
      return;
    }
    final schedule = calculateEmiSchedule(
      principalPaise: principalPaise,
      installmentPaise: emiAmountPaise,
      tenure: tenure,
      annualInterestRate: interest,
      interestMethod: _interestMethod,
      contractualEmi: _keepEnteredEmi,
    );
    if (principalPaise <= 0) {
      setState(() => _scheduleError = 'Principal must be greater than zero.');
      return;
    }
    final productPrincipalMismatch =
        _isProduct &&
        principalPaise != productPricePaise! - (downPaymentPaise ?? 0);
    if ((!schedule.isConsistent && !_keepEnteredEmi) ||
        productPrincipalMismatch) {
      final differences = <String>[
        if (productPrincipalMismatch)
          'Price minus down payment is '
              '${formatMoney(productPricePaise - (downPaymentPaise ?? 0))}, '
              'but Principal is ${formatMoney(principalPaise)}.',
        if (!schedule.isConsistent)
          'You entered ${formatMoney(emiAmountPaise)} per payment. '
              'The principal, rate and tenure imply about '
              '${formatMoney(schedule.expectedInstallmentPaise)}.',
      ];
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Check the financing amounts'),
          content: Text(
            '${differences.join('\n\n')}\n\nKeep your entered amounts without changing Principal?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Review'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Keep entered amounts'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
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
    final recordedPaid =
        detail?.installments
            .where(
              (installment) =>
                  installment.isPaid &&
                  installment.number > detail!.emi.initialPaidInstallments,
            )
            .length ??
        0;
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
      interestMethod: Value(_interestMethod),
      interestPeriod: Value(_ratePeriod),
      productPricePaise: Value(productPricePaise),
      downPaymentPaise: Value(downPaymentPaise),
      feesPaise: Value(feesPaise),
      contractualEmi: Value(_keepEnteredEmi || !schedule.isConsistent),
      tenureMonths: Value(tenure),
      startDate: Value(startDate),
      nextDueDate: Value(_due),
      frequency: Value(_frequency),
      type: Value(_isFriend ? '$friendRepaymentType:$_type' : _type),
      createdAt: _isFriend ? Value(_agreementDate) : const Value.absent(),
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
      final id = await repo.saveEmi(item);
      if (_isFriend) {
        try {
          await repo.saveFriendEmiPhone(id, _friendPhone.text);
        } catch (error, stack) {
          debugPrint('Could not save optional friend contact: $error\n$stack');
        }
      }
    }, errorMessage: 'Could not save this EMI.');
  }

  String? _interestValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null || !parsed.isFinite) {
      return 'Enter a valid percentage';
    }
    if (parsed < 0) return 'Interest rate cannot be negative';
    return null;
  }

  String? _paidValidator(String? value) {
    final text = value?.trim() ?? '';
    final tenure = int.tryParse(_tenure.text.trim());
    if (text.isEmpty) return 'Enter how many installments are paid';
    if (!RegExp(r'^\d+$').hasMatch(text)) {
      return 'Enter a whole-number count, not an amount';
    }
    final count = int.tryParse(text);
    if (count == null) return 'Enter a valid installment count';
    if (tenure != null && tenure > 0 && count > tenure) {
      return 'Cannot exceed $tenure installments';
    }
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
  final formColors = AppTheme.colorsOf(context);
  return financeFieldDecoration(context, hint: hint, icon: icon).copyWith(
    fillColor: formColors.fieldFill,
    hintStyle: TextStyle(color: formColors.secondaryText),
    prefixIconColor: formColors.secondaryText,
    prefixStyle: TextStyle(color: formColors.text),
    suffixStyle: TextStyle(color: formColors.secondaryText),
  );
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
    this.helperText,
    this.autovalidateMode,
    this.prefix,
    this.suffix,
    this.validator,
    this.calculator,
    this.obscureAmount = false,
    this.enabled = true,
  });
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;
  final String? helperText;
  final AutovalidateMode? autovalidateMode;
  final String? prefix;
  final String? suffix;
  final String? Function(String?)? validator;
  final VoidCallback? calculator;
  final bool obscureAmount;
  final bool enabled;

  @override
  Widget build(BuildContext context) => FilledField(
    label: label,
    child: TextFormField(
      controller: controller,
      style: TextStyle(color: AppTheme.homePaletteOf(context).text),
      enabled: enabled,
      obscureText: obscureAmount,
      keyboardType: keyboardType,
      autovalidateMode: autovalidateMode,
      decoration: _filledDecoration(context, hint: hint).copyWith(
        helperText: helperText,
        helperMaxLines: helperText == null ? null : 3,
        errorMaxLines: helperText == null ? null : 3,
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
    required this.selectedFill,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final Color selectedFill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OptionTile(
    label: label,
    icon: icon,
    selected: selected,
    selectedFill: selectedFill,
    onTap: onTap,
  );
}

class _EmiFormSummary {
  const _EmiFormSummary({
    required this.endDate,
    required this.remaining,
    required this.totalPaise,
    required this.interestPaise,
    required this.feesPaise,
    required this.downPaymentPaise,
    required this.expectedEmiPaise,
    required this.enteredEmiPaise,
    required this.hasContractualDifference,
    required this.keepEnteredEmi,
  });
  final DateTime endDate;
  final int remaining;
  final int totalPaise;
  final int interestPaise;
  final int feesPaise;
  final int downPaymentPaise;
  final int expectedEmiPaise;
  final int enteredEmiPaise;
  final bool hasContractualDifference;
  final bool keepEnteredEmi;
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
          _SummaryLine('Calculated EMI', formatMoney(summary.expectedEmiPaise)),
          _SummaryLine('End date', formatDate(summary.endDate)),
          _SummaryLine('EMIs remaining', '${summary.remaining}'),
          _SummaryLine('Installments total', formatMoney(summary.totalPaise)),
          _SummaryLine(
            summary.hasContractualDifference
                ? 'Interest implied by entered payments'
                : 'Estimated interest',
            formatMoney(summary.interestPaise),
          ),
          if (summary.hasContractualDifference)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Entered EMI ${formatMoney(summary.enteredEmiPaise)} differs from '
                'calculated EMI ${formatMoney(summary.expectedEmiPaise)}. '
                '${summary.keepEnteredEmi ? 'Your contract amount will be kept.' : 'Review the EMI or keep the entered contract amount.'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (summary.feesPaise > 0)
            _SummaryLine('Separate fees', formatMoney(summary.feesPaise)),
          if (summary.feesPaise > 0 || summary.downPaymentPaise > 0)
            _SummaryLine(
              'Overall cost',
              formatMoney(
                summary.totalPaise +
                    summary.feesPaise +
                    summary.downPaymentPaise,
              ),
            ),
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
