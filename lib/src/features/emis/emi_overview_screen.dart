import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../data/repositories.dart';
import '../../domain/emi_payment_rules.dart';
import '../../domain/emi_affordability.dart';
import '../../domain/enums.dart';
import '../../domain/reminder_schedule.dart';
import '../reminders/section_reminders_sheet.dart';
import '../dashboard/home_overview.dart';
import '../../shared/finance_display_widgets.dart';
import '../../shared/forms.dart';
import '../../shared/notched_navigation_bar.dart';
import '../../shared/timed_snackbar.dart';
import 'emi_entry_flow.dart';
import 'emis_screen.dart';

enum _OverviewTab { all, personal, friends, completed }

enum _EmiCardAction { history, remind, pay, edit, delete }

Color _incomeInk(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppTheme.darkColors.receive
    : AppTheme.heroEnd;

Color _expenseInk(BuildContext context) =>
    AppTheme.homePaletteOf(context).out.text;

Color _accentInk(BuildContext context) =>
    AppTheme.homePaletteOf(context).owe.text;

String _signedAmount(int amount, {required bool incoming}) =>
    '${incoming ? '+' : '−'}${formatMoney(amount)}';

String _chartAmount(int amount) => privacyAmountsHidden
    ? hiddenAmount
    : NumberFormat.compactCurrency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 1,
      ).format(amount / 100);

BoxDecoration _emiCard(BuildContext context) {
  final colors = AppTheme.homePaletteOf(context);
  return BoxDecoration(
    color: colors.surfaceAlt,
    borderRadius: BorderRadius.circular(24),
  );
}

String friendEmiReminderMessage(EmiDetail detail) {
  final next = detail.nextUnpaidInstallment;
  if (detail.category != EmiCategory.givenToFriends || next == null) {
    throw ArgumentError('An unpaid repayment agreement is required');
  }
  return 'Hi ${detail.emi.name}, a gentle reminder about '
      '${formatMoneyUnmasked(detail.unpaidAmountForInstallment(next.number))} '
      'for installment ${next.number}, due ${DateFormat('d MMM yyyy').format(next.dueDate)}. '
      'Thank you!';
}

class EmiOverviewScreen extends ConsumerStatefulWidget {
  const EmiOverviewScreen({super.key});

  @override
  ConsumerState<EmiOverviewScreen> createState() => _EmiOverviewScreenState();
}

class _EmiOverviewScreenState extends ConsumerState<EmiOverviewScreen> {
  double _tabSwipeDistance = 0;
  final _scrollController = ScrollController();
  final _agendaSearchController = TextEditingController();
  String? _selectedAgendaGroup;
  bool _agendaSearchOpen = false;
  bool _summaryScrolled = false;
  bool _completedTab = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final scrolled = _scrollController.offset > 80;
      if (scrolled != _summaryScrolled && mounted) {
        setState(() => _summaryScrolled = scrolled);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _agendaSearchController.dispose();
    super.dispose();
  }

  void _selectTab(_OverviewTab value) {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    setState(() {
      _summaryScrolled = false;
      _completedTab = value == _OverviewTab.completed;
      _selectedAgendaGroup = null;
      _agendaSearchOpen = false;
      _agendaSearchController.clear();
    });
    ref.read(emiOverviewCategoryProvider.notifier).state = switch (value) {
      _OverviewTab.all => null,
      _OverviewTab.personal => EmiCategory.personal,
      _OverviewTab.friends => EmiCategory.givenToFriends,
      _OverviewTab.completed => null,
    };
  }

  Future<void> _showCardActions(
    EmiDetail detail, {
    bool longPress = false,
  }) async {
    final friend = detail.category == EmiCategory.givenToFriends;
    final action = await showModalBottomSheet<_EmiCardAction>(
      context: context,
      showDragHandle: true,
      builder: (sheet) {
        final palette = AppTheme.homePaletteOf(sheet);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.emi.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(sheet).textTheme.titleLarge?.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  longPress ? 'Agreement and payment history' : 'Quick actions',
                  style: TextStyle(color: palette.text2),
                ),
                const SizedBox(height: 12),
                if (longPress)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history_rounded),
                    title: const Text('View history'),
                    subtitle: const Text('Installments and payments'),
                    onTap: () => Navigator.pop(sheet, _EmiCardAction.history),
                  ),
                if (longPress && friend && detail.nextUnpaidInstallment != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text('Send reminder'),
                    onTap: () => Navigator.pop(sheet, _EmiCardAction.remind),
                  ),
                if (detail.nextUnpaidInstallment != null &&
                    detail.emi.status != EmiStatus.paused)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_outlined),
                    title: Text(friend ? 'Record repayment' : 'Mark paid'),
                    onTap: () => Navigator.pop(sheet, _EmiCardAction.pay),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () => Navigator.pop(sheet, _EmiCardAction.edit),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Move to Deleted'),
                  onTap: () => Navigator.pop(sheet, _EmiCardAction.delete),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _EmiCardAction.history:
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => EmiAgreementDetailScreen(detail.emi.id),
          ),
        );
      case _EmiCardAction.remind:
        await _remindFriendEmi(
          context,
          ref.read(financeRepositoryProvider),
          detail,
        );
      case _EmiCardAction.pay:
        await _confirmSwipePayment(detail);
      case _EmiCardAction.edit:
        openFinanceSheet(
          context,
          EmiFormSheet(emi: detail.emi, category: detail.category),
        );
      case _EmiCardAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Move to Deleted?'),
            content: Text(
              '${detail.emi.name} and its payment history can be restored.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Keep'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        final repository = ref.read(financeRepositoryProvider);
        await repository.deleteEmi(detail.emi.id);
        if (!mounted) return;
        showTimedSnackBar(
          ScaffoldMessenger.of(context),
          SnackBar(
            content: const Text('Moved to Deleted'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => repository.restoreEmi(detail.emi.id),
            ),
          ),
        );
    }
  }

  Future<bool> _confirmSwipePayment(EmiDetail detail) async {
    final next = detail.nextUnpaidInstallment;
    if (next == null || detail.emi.status == EmiStatus.paused) return false;
    final friend = detail.category == EmiCategory.givenToFriends;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(friend ? 'Record repayment?' : 'Mark installment paid?'),
        content: Text(
          '${detail.emi.name} · ${DateFormat('d MMM yyyy').format(next.dueDate)} · '
          '${formatMoney(detail.unpaidAmountForInstallment(next.number))}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    final repository = ref.read(financeRepositoryProvider);
    final previousIds = detail.payments.map((payment) => payment.id).toSet();
    final saved = await repository.recordEmiPayment(
      detail.emi.id,
      expectedDueDate: next.dueDate,
      amountPaise: detail.unpaidAmountForInstallment(next.number),
      requestKey:
          'overview-menu-${detail.emi.id}-${next.number}-'
          '${DateTime.now().microsecondsSinceEpoch}',
    );
    if (!mounted) return false;
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This installment changed. Review it and try again.'),
        ),
      );
      return false;
    }
    final updated = await repository.emiDetail(detail.emi.id);
    if (!mounted) return false;
    final payment = updated.payments
        .where((item) => !previousIds.contains(item.id))
        .firstOrNull;
    showTimedSnackBar(
      ScaffoldMessenger.of(context),
      SnackBar(
        content: Text(
          friend ? 'Repayment recorded' : 'Installment marked paid',
        ),
        duration: const Duration(seconds: 5),
        action: payment == null
            ? null
            : SnackBarAction(
                label: 'Undo',
                onPressed: () =>
                    repository.revertEmiPayment(detail.emi.id, payment.id),
              ),
      ),
    );
    // The repository stream replaces the row with its next installment.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.homePaletteOf(context);
    final category = ref.watch(emiOverviewCategoryProvider);
    final tab = _completedTab && category == null
        ? _OverviewTab.completed
        : switch (category) {
            null => _OverviewTab.all,
            EmiCategory.personal => _OverviewTab.personal,
            EmiCategory.givenToFriends => _OverviewTab.friends,
          };
    final details = ref.watch(allEmiDetailsProvider);
    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        bottom: false,
        child: details.when(
          loading: () =>
              Center(child: CircularProgressIndicator(color: colors.text)),
          error: (_, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load your EMIs'),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: colors.text),
                  onPressed: () => ref.invalidate(allEmiDetailsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (all) {
            final current = switch (tab) {
              _OverviewTab.all =>
                all
                    .where((item) => item.nextUnpaidInstallment != null)
                    .toList(),
              _OverviewTab.personal =>
                all
                    .where(
                      (item) =>
                          item.category == EmiCategory.personal &&
                          item.nextUnpaidInstallment != null,
                    )
                    .toList(),
              _OverviewTab.friends =>
                all
                    .where(
                      (item) =>
                          item.category == EmiCategory.givenToFriends &&
                          item.nextUnpaidInstallment != null,
                    )
                    .toList(),
              _OverviewTab.completed =>
                all
                    .where((item) => item.nextUnpaidInstallment == null)
                    .toList(),
            };
            final active =
                current
                    .where((item) => item.nextUnpaidInstallment != null)
                    .toList()
                  ..sort(
                    (a, b) => a.nextUnpaidInstallment!.dueDate.compareTo(
                      b.nextUnpaidInstallment!.dueDate,
                    ),
                  );
            final completed = current
                .where((item) => item.nextUnpaidInstallment == null)
                .toList();
            final payable = active
                .where((item) => item.emi.status != EmiStatus.paused)
                .toList();
            final personal = active
                .where((item) => item.category == EmiCategory.personal)
                .toList();
            final friends = active
                .where((item) => item.category == EmiCategory.givenToFriends)
                .toList();
            final now = dateOnly(DateTime.now());
            final overdue = payable
                .where(
                  (item) => dateOnly(
                    item.nextUnpaidInstallment!.dueDate,
                  ).isBefore(now),
                )
                .toList();
            final groups = <String, List<EmiDetail>>{
              'Overdue': [],
              'This week': [],
              'This month': [],
              'Later': [],
            };
            for (final item in active) {
              final due = dateOnly(item.nextUnpaidInstallment!.dueDate);
              final days = due.difference(now).inDays;
              final group = item.emi.status == EmiStatus.paused
                  ? 'Later'
                  : days < 0
                  ? 'Overdue'
                  : days <= 7
                  ? 'This week'
                  : due.year == now.year && due.month == now.month
                  ? 'This month'
                  : 'Later';
              groups[group]!.add(item);
            }
            final quickNav = tab == _OverviewTab.all && active.length >= 8;
            final query = quickNav
                ? _agendaSearchController.text.trim().toLowerCase()
                : '';
            final agenda = <({String? header, EmiDetail? detail, int count})>[
              for (final entry in groups.entries)
                if (!quickNav ||
                    _selectedAgendaGroup == null ||
                    _selectedAgendaGroup == entry.key) ...[
                  for (final matches in [
                    entry.value
                        .where(
                          (item) =>
                              query.isEmpty ||
                              item.emi.name.toLowerCase().contains(query) ||
                              (item.emi.provider?.toLowerCase().contains(
                                    query,
                                  ) ??
                                  false),
                        )
                        .toList(),
                  ])
                    if (matches.isNotEmpty) ...[
                      (header: entry.key, detail: null, count: matches.length),
                      for (final item in matches)
                        (header: null, detail: item, count: 0),
                    ],
                ],
            ];
            final personalLeft = personal.fold<int>(
              0,
              (sum, item) => sum + item.remainingBalancePaise,
            );
            final friendLeft = friends.fold<int>(
              0,
              (sum, item) => sum + item.remainingBalancePaise,
            );
            final collapsedTitle = switch (tab) {
              _OverviewTab.personal => _signedAmount(
                personalLeft,
                incoming: false,
              ),
              _OverviewTab.friends => _signedAmount(friendLeft, incoming: true),
              _OverviewTab.completed => 'Completed',
              _OverviewTab.all =>
                '${_signedAmount(personalLeft, incoming: false)}  ${_signedAmount(friendLeft, incoming: true)}',
            };
            return Column(
              children: [
                Material(
                  color: colors.bg,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 150),
                                layoutBuilder:
                                    (currentChild, previousChildren) => Stack(
                                      alignment: Alignment.centerLeft,
                                      children: [
                                        ...previousChildren,
                                        ?currentChild,
                                      ],
                                    ),
                                child:
                                    _summaryScrolled && tab == _OverviewTab.all
                                    ? Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: _signedAmount(
                                                personalLeft,
                                                incoming: false,
                                              ),
                                              style: TextStyle(
                                                color: _expenseInk(context),
                                              ),
                                            ),
                                            const TextSpan(text: '  '),
                                            TextSpan(
                                              text: _signedAmount(
                                                friendLeft,
                                                incoming: true,
                                              ),
                                              style: TextStyle(
                                                color: _incomeInk(context),
                                              ),
                                            ),
                                          ],
                                        ),
                                        key: const ValueKey('emi-totals'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              color: colors.text,
                                              fontWeight: FontWeight.w800,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                      )
                                    : Text(
                                        _summaryScrolled
                                            ? collapsedTitle
                                            : 'EMIs',
                                        key: ValueKey(
                                          'emi-title-${tab.name}-$_summaryScrolled',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              color: _summaryScrolled
                                                  ? tab == _OverviewTab.personal
                                                        ? _expenseInk(context)
                                                        : tab ==
                                                              _OverviewTab
                                                                  .friends
                                                        ? _incomeInk(context)
                                                        : colors.text
                                                  : colors.text,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                              ),
                            ),
                            SectionReminderButton(
                              type: FinanceReminderType.emi,
                              dotColor: _accentInk(context),
                            ),
                          ],
                        ),
                        _CategoryTabs(value: tab, onChanged: _selectTab),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onHorizontalDragStart: (_) => _tabSwipeDistance = 0,
                    onHorizontalDragUpdate: (gesture) =>
                        _tabSwipeDistance += gesture.delta.dx,
                    onHorizontalDragCancel: () => _tabSwipeDistance = 0,
                    onHorizontalDragEnd: (gesture) {
                      final velocity = gesture.primaryVelocity ?? 0;
                      final distance = _tabSwipeDistance;
                      _tabSwipeDistance = 0;
                      if (distance.abs() < 80 && velocity.abs() < 250) return;
                      final toNext = distance.abs() >= 80
                          ? distance < 0
                          : velocity < 0;
                      final nextIndex = (tab.index + (toNext ? 1 : -1)).clamp(
                        0,
                        _OverviewTab.values.length - 1,
                      );
                      _selectTab(_OverviewTab.values[nextIndex]);
                    },
                    child: CustomScrollView(
                      key: PageStorageKey(tab),
                      controller: _scrollController,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (active.isNotEmpty &&
                                    tab != _OverviewTab.completed) ...[
                                  _OverviewSummary(
                                    personal: personal,
                                    friends: friends,
                                    overdue: overdue,
                                    tab: tab,
                                  ),
                                  const SizedBox(height: 8),
                                  _EmiMonthlySchedule(details: current),
                                  const SizedBox(height: 12),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (tab == _OverviewTab.completed && completed.isEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('Completed EMIs will appear here.'),
                            ),
                          )
                        else if (tab == _OverviewTab.completed)
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            sliver: SliverList.builder(
                              itemCount: completed.length,
                              itemBuilder: (context, index) {
                                final detail = completed[index];
                                final received =
                                    detail.category ==
                                    EmiCategory.givenToFriends;
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 5,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: _accentInk(
                                      context,
                                    ).withValues(alpha: .1),
                                    child: Icon(
                                      Icons.check_rounded,
                                      color: _accentInk(context),
                                    ),
                                  ),
                                  title: Text(
                                    detail.emi.name,
                                    style: TextStyle(
                                      color: received
                                          ? _incomeInk(context)
                                          : _accentInk(context),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${received ? 'Received in full' : 'Paid in full'}'
                                    '${detail.emi.provider == null || detail.emi.provider!.isEmpty ? '' : ' · ${detail.emi.provider}'}',
                                    style: TextStyle(color: colors.text2),
                                  ),
                                  trailing: AmountText(
                                    detail.paidPaise,
                                    style: TextStyle(
                                      color: received
                                          ? _incomeInk(context)
                                          : _expenseInk(context),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => EmiAgreementDetailScreen(
                                        detail.emi.id,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                        else if (current.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: _EmptyCategory(
                                tab: tab,
                                onAdd: () => openEmiEntryFlow(context),
                              ),
                            ),
                          )
                        else if (active.isEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              child: Text('All agreements here are complete.'),
                            ),
                          )
                        else ...[
                          if (quickNav)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  4,
                                  20,
                                  0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${active.length} active EMIs',
                                            style: TextStyle(
                                              color: colors.text,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: _agendaSearchOpen
                                              ? 'Close EMI search'
                                              : 'Search EMIs',
                                          onPressed: () => setState(() {
                                            _agendaSearchOpen =
                                                !_agendaSearchOpen;
                                            if (!_agendaSearchOpen) {
                                              _agendaSearchController.clear();
                                            }
                                          }),
                                          icon: Icon(
                                            _agendaSearchOpen
                                                ? Icons.close
                                                : Icons.search,
                                            color: colors.text,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_agendaSearchOpen)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: TextField(
                                          controller: _agendaSearchController,
                                          onChanged: (_) => setState(() {}),
                                          decoration: InputDecoration(
                                            hintText: 'Search name or lender',
                                            prefixIcon: const Icon(
                                              Icons.search,
                                            ),
                                            filled: true,
                                            fillColor: colors.surfaceAlt,
                                            border: const OutlineInputBorder(
                                              borderSide: BorderSide.none,
                                            ),
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          for (final group in <String?>[
                                            null,
                                            ...groups.keys.where(
                                              (key) => groups[key]!.isNotEmpty,
                                            ),
                                          ]) ...[
                                            ChoiceChip(
                                              label: Text(
                                                group == null
                                                    ? 'All ${active.length}'
                                                    : '$group ${groups[group]!.length}',
                                              ),
                                              selected:
                                                  _selectedAgendaGroup == group,
                                              showCheckmark: false,
                                              selectedColor: colors.text,
                                              backgroundColor:
                                                  colors.surfaceAlt,
                                              side: BorderSide.none,
                                              labelStyle: TextStyle(
                                                color:
                                                    _selectedAgendaGroup ==
                                                        group
                                                    ? colors.bg
                                                    : colors.text,
                                              ),
                                              onSelected: (_) => setState(
                                                () => _selectedAgendaGroup =
                                                    group,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (agenda.isEmpty)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Text('No EMIs match this search.'),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              sliver: SliverList.builder(
                                itemCount: agenda.length,
                                itemBuilder: (context, index) {
                                  final item = agenda[index];
                                  if (item.header != null) {
                                    return Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        0,
                                        12,
                                        0,
                                        8,
                                      ),
                                      child: Text(
                                        tab == _OverviewTab.all
                                            ? '${item.header!} · ${item.count}'
                                            : item.header!,
                                        style: TextStyle(
                                          color: item.header == 'Overdue'
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.error
                                              : colors.text,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    );
                                  }
                                  final detail = item.detail!;
                                  return _AgreementCard(
                                    key: ValueKey(detail.emi.id),
                                    detail: detail,
                                    onActions: () => _showCardActions(detail),
                                    onLongPress: () => _showCardActions(
                                      detail,
                                      longPress: true,
                                    ),
                                    onRemind:
                                        detail.category ==
                                            EmiCategory.givenToFriends
                                        ? (buttonContext) => _remindFriendEmi(
                                            buttonContext,
                                            ref.read(financeRepositoryProvider),
                                            detail,
                                          )
                                        : null,
                                  );
                                },
                              ),
                            ),
                        ],
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: NotchedNavigationMetrics.tabContentPadding(
                              context,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({required this.value, required this.onChanged});
  final _OverviewTab value;
  final ValueChanged<_OverviewTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.homePaletteOf(context);
    const labels = ['All', 'Personal', 'Given to others', 'Completed'];
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (index, tab) in _OverviewTab.values.indexed)
              SizedBox(
                width: switch (tab) {
                  _OverviewTab.all => 64,
                  _OverviewTab.personal => 94,
                  _OverviewTab.friends => 132,
                  _OverviewTab.completed => 104,
                },
                child: Semantics(
                  selected: tab == value,
                  button: true,
                  child: InkWell(
                    onTap: () => onChanged(tab),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: tab == value ? colors.text : colors.line,
                            width: tab == value ? 2 : 1,
                          ),
                        ),
                      ),
                      child: Text(
                        labels[index],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: tab == value
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: tab == value ? colors.text : colors.text2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OverviewSummary extends ConsumerWidget {
  const _OverviewSummary({
    required this.personal,
    required this.friends,
    required this.overdue,
    required this.tab,
  });
  final List<EmiDetail> personal;
  final List<EmiDetail> friends;
  final List<EmiDetail> overdue;
  final _OverviewTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.homePaletteOf(context);
    final personalTotal = personal.fold<int>(
      0,
      (sum, item) => sum + item.remainingBalancePaise,
    );
    final friendTotal = friends.fold<int>(
      0,
      (sum, item) => sum + item.remainingBalancePaise,
    );
    final scheduled =
        [...personal, ...friends]
            .where(
              (item) =>
                  item.emi.status != EmiStatus.paused &&
                  item.nextUnpaidInstallment != null,
            )
            .toList()
          ..sort(
            (a, b) => a.nextUnpaidInstallment!.dueDate.compareTo(
              b.nextUnpaidInstallment!.dueDate,
            ),
          );
    final nextPay = scheduled
        .where((item) => item.category == EmiCategory.personal)
        .firstOrNull;
    final nextReceive = scheduled
        .where((item) => item.category == EmiCategory.givenToFriends)
        .firstOrNull;
    final received = friends.fold<int>(0, (sum, item) => sum + item.paidPaise);
    final receivedTotal = friends.fold<int>(
      0,
      (sum, item) => sum + item.totalRepaymentPaise,
    );
    final income = ref.watch(personalEmiIncomeProvider).valueOrNull;
    final now = DateTime.now();
    final thisShare = personalEmiIncomePercent(
      scheduledPersonalEmiAmountInMonth(personal, now),
      income,
    );
    final nextShare = personalEmiIncomePercent(
      scheduledPersonalEmiAmountInMonth(
        personal,
        DateTime(now.year, now.month + 1),
      ),
      income,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: _emiCard(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (tab != _OverviewTab.friends)
                    Expanded(
                      child: _SummaryFigure(
                        label: 'To pay',
                        amount: personalTotal,
                        incoming: false,
                      ),
                    ),
                  if (tab == _OverviewTab.all) const SizedBox(width: 12),
                  if (tab != _OverviewTab.personal)
                    Expanded(
                      child: _SummaryFigure(
                        label: 'To receive',
                        amount: friendTotal,
                        incoming: true,
                      ),
                    ),
                ],
              ),
              if (tab == _OverviewTab.personal && personalTotal > 0) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 3,
                  children: [
                    for (final item in personal.take(3))
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${item.emi.name} ',
                              style: TextStyle(color: colors.text2),
                            ),
                            TextSpan(
                              text: formatMoney(item.remainingBalancePaise),
                              style: TextStyle(
                                color: _expenseInk(context),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    if (personal.length > 3)
                      Text(
                        '+${personal.length - 3} more',
                        style: TextStyle(color: colors.text2, fontSize: 12),
                      ),
                  ],
                ),
              ],
              if (tab == _OverviewTab.friends && receivedTotal > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        value: received / receivedTotal,
                        strokeWidth: 5,
                        color: _incomeInk(context),
                        backgroundColor: colors.line,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${(received * 100 / receivedTotal).round()}% received · ${formatMoney(received)} of ${formatMoney(receivedTotal)}',
                        style: TextStyle(
                          color: _incomeInk(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (tab != _OverviewTab.friends && personal.isNotEmpty) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: () =>
                      openPersonalEmiIncomeInsight(context, ref, personal),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.speed_outlined,
                          size: 18,
                          color: _accentInk(context),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            income == null
                                ? 'Add income to see your EMI risk'
                                : 'EMI vs income · This month $thisShare% · Next $nextShare% · ${personalEmiIncomeZone(math.max(thisShare ?? 0, nextShare ?? 0))}',
                            style: TextStyle(
                              color: colors.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: colors.text2,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (nextPay != null || nextReceive != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: _emiCard(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next due',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (nextPay != null)
                  _NextDueLine(detail: nextPay, incoming: false),
                if (nextReceive != null)
                  _NextDueLine(detail: nextReceive, incoming: true),
              ],
            ),
          ),
        ],
        if (overdue.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Overdue · ${overdue.length} installment${overdue.length == 1 ? '' : 's'}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _NextDueLine extends StatelessWidget {
  const _NextDueLine({required this.detail, required this.incoming});
  final EmiDetail detail;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.homePaletteOf(context);
    final next = detail.nextUnpaidInstallment!;
    final ink = incoming ? _incomeInk(context) : _expenseInk(context);
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.emi.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Wrap(
                  spacing: 5,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      DateFormat('d MMM').format(next.dueDate),
                      style: TextStyle(
                        color: _accentInk(context),
                        fontSize: 12,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _accentInk(context).withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        _dueLabel(next.dueDate),
                        style: TextStyle(
                          color: _accentInk(context),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            '${_signedAmount(detail.unpaidAmountForInstallment(next.number), incoming: incoming)} ${incoming ? 'Receive' : 'Pay'}',
            style: TextStyle(color: ink, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _EmiMonthlySchedule extends StatefulWidget {
  const _EmiMonthlySchedule({required this.details});
  final List<EmiDetail> details;

  @override
  State<_EmiMonthlySchedule> createState() => _EmiMonthlyScheduleState();
}

class _EmiMonthlyScheduleState extends State<_EmiMonthlySchedule> {
  DateTime? _selectedMonth;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.homePaletteOf(context);
    final schedule = HomeOverview.build(
      widget.details,
      const [],
      const [],
      DateTime.now(),
    );
    final months = schedule.months;
    final hasIncoming = widget.details.any(
      (detail) => detail.category == EmiCategory.givenToFriends,
    );
    final hasOutgoing = widget.details.any(
      (detail) => detail.category == EmiCategory.personal,
    );
    final largest = months.fold<int>(
      0,
      (value, month) =>
          math.max(value, math.max(month.incoming, month.outgoing)),
    );
    double barHeight(int value) =>
        value == 0 || largest == 0 ? 0 : math.max(4, 36 * value / largest);
    final halfHeight = math.max(
      52.0,
      MediaQuery.textScalerOf(context).scale(11) + 44,
    );
    String monthTooltip(HomeMonth month) =>
        '${DateFormat('MMMM yyyy').format(month.start)}: ${[if (month.incoming > 0) '${formatMoney(month.incoming)} expected back', if (month.outgoing > 0) '${formatMoney(month.outgoing)} to pay', if (month.incoming == 0 && month.outgoing == 0) 'No installments due'].join(', ')}';
    if (months.every((month) => month.items.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _emiCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Next 6 months',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 10),
          RepaintBoundary(
            child: Row(
              children: [
                for (final month in months)
                  Expanded(
                    child: InkWell(
                      key: ValueKey(
                        'emi-month-${month.start.year}-${month.start.month}',
                      ),
                      onTap: () {
                        setState(() => _selectedMonth = month.start);
                        _showMonth(context, month);
                      },
                      child: Tooltip(
                        message: monthTooltip(month),
                        child: Column(
                          children: [
                            if (hasIncoming || !hasOutgoing)
                              SizedBox(
                                height: halfHeight,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (month.incoming > 0)
                                      Text(
                                        '+${_chartAmount(month.incoming)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: _incomeInk(context),
                                          fontSize: 11,
                                        ),
                                      ),
                                    Align(
                                      alignment: Alignment.bottomCenter,
                                      child: Container(
                                        width: 13,
                                        height: barHeight(month.incoming),
                                        decoration: BoxDecoration(
                                          color: _incomeInk(context),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (!hasIncoming && hasOutgoing)
                              SizedBox(
                                height: halfHeight,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (month.outgoing > 0)
                                      Text(
                                        '−${_chartAmount(month.outgoing)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: _expenseInk(context),
                                          fontSize: 11,
                                        ),
                                      ),
                                    Container(
                                      width: 13,
                                      height: barHeight(month.outgoing),
                                      decoration: BoxDecoration(
                                        color: _expenseInk(context),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Container(height: 1, color: colors.line),
                            if (hasIncoming && hasOutgoing)
                              SizedBox(
                                height: halfHeight,
                                child: Column(
                                  children: [
                                    Align(
                                      alignment: Alignment.topCenter,
                                      child: Container(
                                        width: 13,
                                        height: barHeight(month.outgoing),
                                        decoration: BoxDecoration(
                                          color: _expenseInk(context),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (month.outgoing > 0)
                                      Text(
                                        '−${_chartAmount(month.outgoing)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: _expenseInk(context),
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 3),
                            Text(
                              DateFormat('MMM').format(month.start),
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.text2,
                              ),
                            ),
                            if (_selectedMonth?.year == month.start.year &&
                                _selectedMonth?.month == month.start.month)
                              Container(
                                height: 2,
                                width: 20,
                                color: _accentInk(context),
                              )
                            else
                              const SizedBox(height: 2),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (hasIncoming && hasOutgoing)
            Text(
              '↑ Receive   ↓ Pay',
              style: TextStyle(fontSize: 12, color: colors.text2),
            ),
          if (_selectedMonth != null)
            Builder(
              builder: (context) {
                final selected = months
                    .where(
                      (month) =>
                          month.start.year == _selectedMonth!.year &&
                          month.start.month == _selectedMonth!.month,
                    )
                    .firstOrNull;
                if (selected == null) return const SizedBox.shrink();
                final net = selected.incoming - selected.outgoing;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              '${DateFormat('MMM').format(selected.start)} · ',
                          style: TextStyle(color: colors.text2),
                        ),
                        if (selected.outgoing > 0)
                          TextSpan(
                            text: '−${formatMoney(selected.outgoing)} Pay',
                            style: TextStyle(color: _expenseInk(context)),
                          ),
                        if (selected.incoming > 0 && selected.outgoing > 0)
                          TextSpan(
                            text: ' · ',
                            style: TextStyle(color: colors.text2),
                          ),
                        if (selected.incoming > 0)
                          TextSpan(
                            text: '+${formatMoney(selected.incoming)} Receive',
                            style: TextStyle(color: _incomeInk(context)),
                          ),
                        if (selected.incoming > 0 && selected.outgoing > 0)
                          TextSpan(
                            text:
                                ' · Net ${net < 0 ? '−' : '+'}${formatMoney(net.abs())}',
                            style: TextStyle(color: _accentInk(context)),
                          ),
                        if (selected.incoming == 0 && selected.outgoing == 0)
                          TextSpan(
                            text: 'No installments due',
                            style: TextStyle(color: colors.text2),
                          ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showMonth(BuildContext context, HomeMonth month) {
    final colors = AppTheme.homePaletteOf(context);
    final hasIncoming = month.incoming > 0;
    final hasOutgoing = month.outgoing > 0;
    final mixed = hasIncoming && hasOutgoing;
    final net = month.incoming - month.outgoing;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: colors.surface,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: math.min(
            MediaQuery.sizeOf(sheetContext).height * .75,
            245.0 + month.items.length * 72.0,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('MMMM yyyy').format(month.start),
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                    color: colors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${month.items.length} unpaid installment${month.items.length == 1 ? '' : 's'}',
                  style: TextStyle(color: colors.text2, fontSize: 13),
                ),
                if (month.items.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: _emiCard(sheetContext),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mixed
                              ? 'Net for ${DateFormat('MMMM').format(month.start)}'
                              : hasIncoming
                              ? 'To receive'
                              : 'To pay',
                          style: TextStyle(
                            color: colors.text2,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          mixed
                              ? '${net < 0 ? '−' : '+'}${formatMoney(net.abs())}'
                              : hasIncoming
                              ? _signedAmount(month.incoming, incoming: true)
                              : _signedAmount(month.outgoing, incoming: false),
                          style: Theme.of(sheetContext).textTheme.headlineMedium
                              ?.copyWith(
                                color: mixed
                                    ? net < 0
                                          ? _expenseInk(sheetContext)
                                          : _incomeInk(sheetContext)
                                    : hasIncoming
                                    ? _incomeInk(sheetContext)
                                    : _expenseInk(sheetContext),
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                        if (mixed) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Text(
                                '${_signedAmount(month.incoming, incoming: true)} Receive',
                                style: TextStyle(
                                  color: _incomeInk(sheetContext),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${_signedAmount(month.outgoing, incoming: false)} Pay',
                                style: TextStyle(
                                  color: _expenseInk(sheetContext),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: month.items.isEmpty
                      ? Center(
                          child: Text(
                            'No installments due',
                            style: TextStyle(color: colors.text2),
                          ),
                        )
                      : ListView.builder(
                          itemCount: month.items.length,
                          itemBuilder: (context, index) {
                            final due = month.items[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: colors.surfaceAlt,
                                child: Icon(
                                  due.incoming
                                      ? Icons.south_west_rounded
                                      : Icons.north_east_rounded,
                                  size: 18,
                                  color: due.incoming
                                      ? _incomeInk(sheetContext)
                                      : _expenseInk(sheetContext),
                                ),
                              ),
                              title: Text(
                                due.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${DateFormat('EEE d MMM').format(due.date)} · ${due.incoming ? 'Receive' : 'Pay'}',
                                style: TextStyle(color: colors.text2),
                              ),
                              trailing: Text(
                                '${due.incoming ? '+' : '−'}${formatMoney(due.amount)}',
                                style: TextStyle(
                                  color: due.incoming
                                      ? _incomeInk(sheetContext)
                                      : _expenseInk(sheetContext),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        EmiAgreementDetailScreen(due.id),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryFigure extends StatelessWidget {
  const _SummaryFigure({
    required this.label,
    required this.amount,
    required this.incoming,
  });
  final String label;
  final int amount;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.homePaletteOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _signedAmount(amount, incoming: incoming),
              maxLines: 1,
              style: TextStyle(
                color: incoming ? _incomeInk(context) : _expenseInk(context),
                fontWeight: FontWeight.w800,
                fontSize: 28,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _dueLabel(DateTime date) {
  final days = dateOnly(date).difference(dateOnly(DateTime.now())).inDays;
  if (days < 0) return 'Overdue ${-days} day${days == -1 ? '' : 's'}';
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  return 'in $days days';
}

String _paidDueLabel(DateTime date) {
  final days = dateOnly(DateTime.now()).difference(dateOnly(date)).inDays;
  if (days == 0) return 'due today';
  if (days > 0) return 'due $days day${days == 1 ? '' : 's'} ago';
  return 'due in ${-days} day${days == -1 ? '' : 's'}';
}

class _AgreementCard extends StatelessWidget {
  const _AgreementCard({
    super.key,
    required this.detail,
    required this.onActions,
    required this.onLongPress,
    this.onRemind,
  });
  final EmiDetail detail;
  final VoidCallback onActions;
  final VoidCallback onLongPress;
  final void Function(BuildContext)? onRemind;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.homePaletteOf(context);
    final friend = detail.category == EmiCategory.givenToFriends;
    final due = detail.nextUnpaidInstallment!;
    final paused = detail.emi.status == EmiStatus.paused;
    final overdue =
        !paused && dateOnly(due.dueDate).isBefore(dateOnly(DateTime.now()));
    final nextAmount = detail.unpaidAmountForInstallment(due.number);
    final regularAmount = detail.emi.emiAmountPaise;
    final days = dateOnly(
      due.dueDate,
    ).difference(dateOnly(DateTime.now())).inDays;
    final directionInk = friend ? _incomeInk(context) : _expenseInk(context);
    final accent = _accentInk(context);
    return Material(
      color: colors.bg,
      child: InkWell(
        onLongPress: onLongPress,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EmiAgreementDetailScreen(detail.emi.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.line),
                    ),
                    child: Text(
                      detail.emi.name.isEmpty
                          ? '?'
                          : detail.emi.name[0].toUpperCase(),
                      style: TextStyle(
                        color: colors.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                detail.emi.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.text,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (detail.emi.notes?.trim().isNotEmpty ==
                                true) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.notes_outlined,
                                size: 15,
                                color: colors.text2,
                                semanticLabel: 'Has notes',
                              ),
                            ],
                          ],
                        ),
                        if (detail.emi.provider?.trim().isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              detail.emi.provider!.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.text2,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 116),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${friend ? '+' : '−'}${formatMoney(nextAmount)}',
                        style: TextStyle(
                          color: directionInk,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onActions,
                    tooltip: 'More actions',
                    icon: Icon(Icons.more_horiz, color: colors.text),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 50),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: overdue
                            ? _expenseInk(context).withValues(alpha: .1)
                            : !paused && days <= 7
                            ? accent
                            : accent.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        '${friend ? 'Receive' : 'Pay'} · ${DateFormat('d MMM').format(due.dueDate)} · ${paused ? 'Paused' : _dueLabel(due.dueDate)}',
                        style: TextStyle(
                          color: overdue
                              ? _expenseInk(context)
                              : !paused && days <= 7
                              ? colors.bg
                              : accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            friend
                                ? '${formatMoney(detail.paidPaise)} of ${formatMoney(detail.totalRepaymentPaise)} received'
                                : detail.emi.tenureMonths == 1
                                ? 'One-time'
                                : '${detail.paidInstallments}/${detail.emi.tenureMonths} paid',
                            style: TextStyle(
                              color: friend && detail.paidPaise > 0
                                  ? _incomeInk(context)
                                  : colors.text2,
                              fontSize: 12,
                              fontWeight: friend
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${formatMoney(detail.remainingBalancePaise)} left',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (detail.amountForInstallment(due.number) != regularAmount)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${formatMoney(regularAmount)}/mo · next ${formatMoney(nextAmount)}',
                    style: TextStyle(color: colors.text2, fontSize: 12),
                  ),
                ),
              if (onRemind != null)
                Builder(
                  builder: (buttonContext) => Align(
                    alignment: Alignment.centerRight,
                    child: _EmiRemindButton(
                      onPressed: () => onRemind!(buttonContext),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmiRemindButton extends StatelessWidget {
  const _EmiRemindButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.homePaletteOf(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(Icons.send_outlined, size: 17, color: _incomeInk(context)),
      label: const Text('Send reminder'),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.text,
        backgroundColor: colors.surfaceAlt,
        side: BorderSide(color: colors.line),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _EmptyCategory extends StatelessWidget {
  const _EmptyCategory({required this.tab, required this.onAdd});
  final _OverviewTab tab;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.homePaletteOf(context);
    final message = switch (tab) {
      _OverviewTab.all =>
        'Track a personal loan or money someone will repay you.',
      _OverviewTab.personal =>
        'Personal loans and credit-card installments appear here.',
      _OverviewTab.friends =>
        'Add an agreement to track repayments from someone else.',
      _OverviewTab.completed => 'Completed EMIs will appear here.',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 32, color: colors.text2),
          const SizedBox(height: 12),
          Text(
            'Nothing here yet',
            style: TextStyle(
              color: colors.text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.text2, fontSize: 13),
          ),
          const SizedBox(height: 15),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: colors.text),
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add EMI'),
          ),
        ],
      ),
    );
  }
}

Future<void> _remindFriendEmi(
  BuildContext context,
  FinanceRepository repository,
  EmiDetail detail,
) async {
  final phone = await repository.friendEmiPhone(detail.emi.id, detail.emi.name);
  if (!context.mounted) return;
  var digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) digits = '91$digits';
  if (digits.length == 11 && digits.startsWith('0')) {
    digits = '91${digits.substring(1)}';
  }
  final next = detail.nextUnpaidInstallment;
  if (next == null) return;
  final message = friendEmiReminderMessage(detail);
  if (digits.length < 11) {
    final box = context.findRenderObject();
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: message,
          sharePositionOrigin: box is! RenderBox
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error) {
      debugPrint('Friend repayment share failed: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the share sheet.')),
        );
      }
    }
    return;
  }
  final uri = Uri.https('wa.me', '/$digits', {'text': message});
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (error) {
    debugPrint('Friend repayment reminder failed: $error');
  }
  if (!context.mounted) return;
  final box = context.findRenderObject();
  try {
    await SharePlus.instance.share(
      ShareParams(
        text: message,
        sharePositionOrigin: box is! RenderBox
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  } catch (error) {
    debugPrint('Friend repayment fallback share failed: $error');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp or the share sheet.'),
        ),
      );
    }
  }
}

class EmiAgreementDetailScreen extends ConsumerWidget {
  const EmiAgreementDetailScreen(this.id, {super.key});
  final int id;

  Future<void> _settle(
    BuildContext context,
    WidgetRef ref,
    EmiDetail detail,
  ) async {
    final friend = detail.category == EmiCategory.givenToFriends;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          friend ? 'Record full repayment?' : 'Pay off the full balance?',
        ),
        content: Text(
          'This records ${formatMoney(detail.remainingBalancePaise)} '
          'against every remaining installment of ${detail.emi.name}. '
          'Existing partial payments stay in the history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final settled = await ref
        .read(financeRepositoryProvider)
        .settleEmiEarly(
          id,
          expectedRemainingPaise: detail.remainingBalancePaise,
        );
    if (context.mounted && !settled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The balance changed. Please review and try again.'),
        ),
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    EmiDetail detail,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Move to Deleted?'),
        content: Text(
          '${detail.emi.name} and its payment history can be restored from Deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final repository = ref.read(financeRepositoryProvider);
    await repository.deleteEmi(id);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    showTimedSnackBar(
      messenger,
      SnackBar(
        content: const Text('Moved to Deleted'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repository.restoreEmi(id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.homePaletteOf(context);
    final all = ref.watch(allEmiDetailsProvider);
    final detail = all.valueOrNull
        ?.where((item) => item.emi.id == id)
        .firstOrNull;
    if (all.isLoading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: colors.text)),
      );
    }
    if (detail == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Record unavailable')),
      );
    }
    final friend = detail.category == EmiCategory.givenToFriends;
    final next = detail.nextUnpaidInstallment;
    final payments = [...detail.payments]
      ..sort((a, b) => b.paidOn.compareTo(a.paidOn));
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        title: Text(
          detail.emi.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => openFinanceSheet(
              context,
              EmiFormSheet(emi: detail.emi, category: detail.category),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            onSelected: (action) {
              if (action == 'delete') _delete(context, ref, detail);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: _emiCard(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend
                      ? 'Given to others'
                      : detail.emi.provider ?? 'Personal loan',
                  style: TextStyle(color: colors.text2, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Text(
                  friend ? 'Still to receive' : 'Still to pay',
                  style: TextStyle(
                    color: _accentInk(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _signedAmount(detail.remainingBalancePaise, incoming: friend),
                  style: TextStyle(
                    color: friend ? _incomeInk(context) : _expenseInk(context),
                    fontSize: 35,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    _DetailFigure(
                      label: friend ? 'Received' : 'Paid',
                      amount: detail.paidPaise,
                      ink: friend ? _incomeInk(context) : _expenseInk(context),
                      sign: friend ? '+' : '−',
                    ),
                    _DetailFigure(
                      label: 'Total scheduled',
                      amount: detail.totalRepaymentPaise,
                      ink: _accentInk(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (detail.emi.notes?.trim().isNotEmpty == true) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.notes_outlined, size: 20, color: colors.text2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notes',
                          style: TextStyle(
                            color: colors.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          detail.emi.notes!.trim(),
                          style: TextStyle(color: colors.text2, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (next != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: _emiCard(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Next installment · ${DateFormat('d MMM yyyy').format(next.dueDate)}',
                              style: TextStyle(
                                color: colors.text,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _dueLabel(next.dueDate),
                              style: TextStyle(
                                color: _accentInk(context),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _signedAmount(
                          detail.unpaidAmountForInstallment(next.number),
                          incoming: friend,
                        ),
                        style: TextStyle(
                          color: friend
                              ? _incomeInk(context)
                              : _expenseInk(context),
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  if (friend)
                    _EmiRemindButton(
                      onPressed: () => _remindFriendEmi(
                        context,
                        ref.read(financeRepositoryProvider),
                        detail,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 26),
          Text(
            'Installments',
            style: TextStyle(
              color: colors.text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          for (final installment in detail.installments) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: colors.surfaceAlt,
                    child: installment.isPaid
                        ? Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: _incomeInk(context),
                          )
                        : Text(
                            '${installment.number}',
                            style: TextStyle(
                              color: colors.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Installment ${installment.number} · ${DateFormat('MMM yyyy').format(installment.dueDate)}',
                          style: TextStyle(
                            color: colors.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${DateFormat('d MMM yyyy').format(installment.dueDate)} · ${installment.isPaid ? 'Paid · ${_paidDueLabel(installment.dueDate)}' : _dueLabel(installment.dueDate)}'
                          '${(detail.paidByInstallment[installment.number] ?? 0) > 0 && !installment.isPaid ? '\n${formatMoney(detail.paidByInstallment[installment.number]!)} of ${formatMoney(detail.amountForInstallment(installment.number))} ${friend ? 'received' : 'paid'} · ${formatMoney(detail.unpaidAmountForInstallment(installment.number))} due' : ''}',
                          style: TextStyle(color: colors.text2, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _signedAmount(
                      detail.amountForInstallment(installment.number),
                      incoming: friend,
                    ),
                    style: TextStyle(
                      color: friend
                          ? _incomeInk(context)
                          : _expenseInk(context),
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 26),
          Text(
            friend ? 'Payments received' : 'Payment history',
            style: TextStyle(
              color: colors.text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (payments.isEmpty)
            Text(
              'No payments recorded yet',
              style: TextStyle(color: colors.text2, fontSize: 13),
            ),
          for (final payment in payments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.payments_outlined,
                  color: _incomeInk(context),
                ),
                title: Text(DateFormat('d MMM yyyy').format(payment.paidOn)),
                subtitle: Text(
                  'Installment ${payment.installmentNumber}',
                  style: TextStyle(color: colors.text2, fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _signedAmount(payment.amountPaise, incoming: friend),
                      style: TextStyle(
                        color: friend
                            ? _incomeInk(context)
                            : _expenseInk(context),
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextButton(
                      child: const Text('Undo'),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialog) => AlertDialog(
                            title: const Text('Undo payment?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialog, false),
                                child: const Text('Keep'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(dialog, true),
                                child: const Text('Undo'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true || !context.mounted) return;
                        final reverted = await ref
                            .read(financeRepositoryProvider)
                            .revertEmiPayment(id, payment.id);
                        if (context.mounted && !reverted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not undo this payment'),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: next == null || detail.emi.status == EmiStatus.paused
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.text,
                          foregroundColor: colors.bg,
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          showDragHandle: true,
                          builder: (_) => _RecordPaymentSheet(detail: detail),
                        ),
                        icon: const Icon(Icons.add),
                        label: Text(
                          friend ? 'Record repayment' : 'Record payment',
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: colors.text,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      onPressed: () => _settle(context, ref, detail),
                      child: Text(
                        friend
                            ? 'Received full balance'
                            : 'Pay off full balance',
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _DetailFigure extends StatelessWidget {
  const _DetailFigure({
    required this.label,
    required this.amount,
    required this.ink,
    this.sign = '',
  });
  final String label;
  final int amount;
  final Color ink;
  final String sign;
  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.homePaletteOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: colors.text2, fontSize: 12)),
        Text(
          '$sign${formatMoney(amount)}',
          style: TextStyle(
            color: ink,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  const _RecordPaymentSheet({required this.detail});
  final EmiDetail detail;
  @override
  ConsumerState<_RecordPaymentSheet> createState() =>
      _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  late final _amount = TextEditingController(text: rupeesText(_stillDue));
  late final String _requestKey =
      '${DateTime.now().microsecondsSinceEpoch}-${widget.detail.emi.id}';
  DateTime _paidOn = DateTime.now();
  bool _saving = false;
  String? _error;

  int get _stillDue {
    final next = widget.detail.nextUnpaidInstallment!;
    return widget.detail.amountForInstallment(next.number) -
        (widget.detail.paidByInstallment[next.number] ?? 0);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    int paise;
    try {
      paise = parseRupeesToPaise(_amount.text);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    if (paise > _stillDue) {
      setState(
        () => _error =
            'This installment has only ${formatMoney(_stillDue)} left.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final next = widget.detail.nextUnpaidInstallment!;
    try {
      final recorded = await ref
          .read(financeRepositoryProvider)
          .recordEmiPayment(
            widget.detail.emi.id,
            expectedDueDate: next.dueDate,
            expectedInstallmentNumber: next.number,
            amountPaise: paise,
            paidOn: _paidOn,
            requestKey: _requestKey,
            paidEarly: _paidOn.isBefore(next.dueDate),
          );
      if (!mounted) return;
      if (recorded) {
        Navigator.pop(context);
      } else {
        setState(() {
          _saving = false;
          _error = 'This installment changed. Close and reopen to refresh it.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.homePaletteOf(context);
    final friend = widget.detail.category == EmiCategory.givenToFriends;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        6,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            friend ? 'Record money received' : 'Record installment paid',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: _emiCard(context),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Installment ${widget.detail.nextUnpaidInstallment!.number}',
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Due ${DateFormat('d MMM yyyy').format(widget.detail.nextUnpaidInstallment!.dueDate)}',
                        style: TextStyle(color: colors.text2, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${formatMoney(_stillDue)} left',
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: false,
            style: TextStyle(
              color: colors.text,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(
              labelText: friend ? 'Amount received' : 'Amount paid',
              prefixText: '${activeAmountFormatter.value.symbol} ',
              filled: true,
              fillColor: colors.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.text,
              side: BorderSide(color: colors.line),
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _paidOn,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (date != null && mounted) setState(() => _paidOn = date);
            },
            icon: const Icon(Icons.event),
            label: Text(formatDate(_paidOn)),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.text,
                foregroundColor: colors.bg,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save payment'),
            ),
          ),
        ],
      ),
    );
  }
}
