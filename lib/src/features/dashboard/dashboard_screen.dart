import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../domain/enums.dart';
import '../../domain/emi_affordability.dart';
import '../../shared/finance_display_widgets.dart';
import '../../shared/forms.dart';
import '../../shared/notched_navigation_bar.dart';
import '../emis/emis_screen.dart';
import '../emis/emi_entry_flow.dart';
import '../emis/emi_overview_screen.dart';
import '../money/money_screen.dart';
import '../reminders/upcoming_screen.dart';
import '../settings/backup_settings_section.dart';
import '../settings/settings_screen.dart';
import '../subscriptions/subscriptions_screen.dart';
import 'home_overview.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  Timer? _dayRefresh;
  late DateTime _overviewDay;

  @override
  void initState() {
    super.initState();
    _overviewDay = DateUtils.dateOnly(DateTime.now());
    WidgetsBinding.instance.addObserver(this);
    _scheduleDayRefresh();
  }

  void _scheduleDayRefresh() {
    _dayRefresh?.cancel();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _dayRefresh = Timer(
      tomorrow.difference(now) + const Duration(seconds: 1),
      () {
        if (!mounted) return;
        _refreshForNewDay();
        _scheduleDayRefresh();
      },
    );
  }

  void _refreshForNewDay() {
    final today = DateUtils.dateOnly(DateTime.now());
    if (today == _overviewDay) return;
    _overviewDay = today;
    ref.invalidate(homeOverviewProvider);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshForNewDay();
      _scheduleDayRefresh();
    }
  }

  @override
  void dispose() {
    _dayRefresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(homeOverviewProvider);
    final hasAnyEmi = ref.watch(
      allEmiDetailsProvider.select(
        (state) => state.valueOrNull?.isNotEmpty ?? false,
      ),
    );
    final private = ref.watch(privacyModeProvider.select((s) => s.enabled));
    final baseHome = AppTheme.homePaletteOf(context);
    final appColors = AppTheme.colorsOf(context);
    final home = baseHome.copyWith(
      incoming: AppTone(
        Theme.of(context).brightness == Brightness.dark
            ? appColors.receive
            : AppTheme.heroEnd,
        appColors.receive,
        appColors.selectedFill,
      ),
    );
    final sections = <Widget>[
      _Header(
        private: private,
        onPrivacy: () => ref
            .read(privacyModeProvider.notifier)
            .setEnabled(
              !ref.read(privacyModeProvider).enabled,
              context: context,
            ),
        onSettings: () => openSettings(context),
      ),
      if (overview == null)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (!hasAnyEmi &&
          overview.money.isEmpty &&
          overview.subscriptions.isEmpty)
        const _FirstRun()
      else ...[
        if (overview.emis.isNotEmpty || overview.friendEmis.isNotEmpty)
          _Band(child: _EmiCategorySummaries(data: overview)),
        if (overview.emis.isNotEmpty || overview.friendTotal > 0)
          _Band(child: _IncomeRecovery(data: overview)),
        if (overview.dues.any((due) => !due.date.isAfter(overview.today)))
          _Band(child: _TodayStrip(data: overview)),
        _Band(child: _MoneyBalance(data: overview)),
        if (overview.months.any((month) => month.items.isNotEmpty))
          _Band(child: _MonthlyProjection(data: overview)),
        if (overview.toCollect > 0 || overview.emis.isNotEmpty)
          _Band(child: _SecondaryTiles(data: overview)),
        if (overview.emis.isNotEmpty || overview.next30OutgoingTotal > 0)
          _Band(child: _Next30(data: overview)),
        if (overview.dues.isNotEmpty) _Band(child: _ThisWeek(data: overview)),
      ],
      BackupReminderBanner(
        onBackUp: () async {
          try {
            await showCreateBackupFlow(context, ref);
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not save the backup.')),
              );
            }
          }
        },
      ),
    ];
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        extensions: [...theme.extensions.values, home.homeColors, home],
        colorScheme: theme.colorScheme.copyWith(
          primary: home.brand,
          onPrimary: home.onBrand,
          surface: home.surface,
          onSurface: home.text,
          onSurfaceVariant: home.text2,
          surfaceContainerLow: home.surfaceAlt,
          surfaceContainer: home.surfaceAlt,
          outline: home.line,
        ),
        textTheme: theme.textTheme.apply(
          bodyColor: home.text,
          displayColor: home.text,
        ),
      ),
      child: Scaffold(
        backgroundColor: home.bg,
        body: Stack(
          children: [
            Positioned.fill(
              child: ListView.builder(
                padding: EdgeInsets.only(
                  bottom: NotchedNavigationMetrics.tabContentPadding(context),
                ),
                itemCount: sections.length,
                itemBuilder: (context, index) => sections[index],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.paddingOf(context).top,
              child: ColoredBox(color: home.bg),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.private,
    required this.onPrivacy,
    required this.onSettings,
  });
  final bool private;
  final VoidCallback onPrivacy, onSettings;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final palette = AppTheme.homePaletteOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top,
        16,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FinKeep',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: 28,
                    color: palette.brand,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$greeting · ${formatShortDate(now, today: now)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    color: palette.text2,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: private ? 'Show amounts' : 'Hide amounts',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: onPrivacy,
            icon: Icon(
              private
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 24,
              semanticLabel: private ? 'Show amounts' : 'Hide amounts',
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: onSettings,
            icon: const Icon(
              Icons.settings_outlined,
              size: 24,
              semanticLabel: 'Settings',
            ),
          ),
        ],
      ),
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: RepaintBoundary(child: child),
  );
}

Color _dashboardSurface(BuildContext context) {
  final palette = AppTheme.homePaletteOf(context);
  return Theme.of(context).brightness == Brightness.dark
      ? palette.surface
      : Color.lerp(palette.bg, palette.surface, .55)!;
}

class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(dark ? 20 : 16);
    return Material(
      color: _dashboardSurface(context),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: dark
            ? BorderSide(
                color: AppTheme.homePaletteOf(
                  context,
                ).line.withValues(alpha: .55),
              )
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

TextStyle? _title(BuildContext context) =>
    Theme.of(context).textTheme.titleMedium?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: AppTheme.colorsOf(context).text,
    );
TextStyle? _label(BuildContext context) => Theme.of(context)
    .textTheme
    .labelSmall
    ?.copyWith(fontSize: 12, color: AppTheme.colorsOf(context).secondaryText);

class _FirstRun extends StatelessWidget {
  const _FirstRun();
  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.homePaletteOf(context);
    return Column(
      children: [
        _Band(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [palette.heroStart, palette.heroEnd],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: palette.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Net owed to you',
                  style: _label(
                    context,
                  )?.copyWith(color: palette.heroText2, fontSize: 13),
                ),
                const SizedBox(height: 8),
                AmountText(
                  0,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: palette.heroText,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        _Band(
          child: _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Add your first EMI, loan or subscription',
                  style: _title(context),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => openEmiEntryFlow(context),
                  child: const Text('Add EMI'),
                ),
                FilledButton.tonal(
                  onPressed: () => openFinanceSheet(
                    context,
                    const MoneyFormSheet(
                      initialDirection: MoneyDirection.borrowed,
                    ),
                  ),
                  child: const Text('Add loan'),
                ),
                FilledButton.tonal(
                  onPressed: () =>
                      openFinanceSheet(context, const SubscriptionFormSheet()),
                  child: const Text('Add subscription'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TodayStrip extends StatelessWidget {
  const _TodayStrip({required this.data});
  final HomeOverview data;

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.homePaletteOf(context);
    final today = data.dues.where((due) => due.date == data.today).toList();
    final overdue = data.overdueDues;
    final shown = [...overdue, ...today];
    if (shown.isEmpty) return const SizedBox.shrink();
    final incoming = shown.where((due) => due.incoming).toList();
    final outgoing = shown.where((due) => !due.incoming).toList();
    final mixed = incoming.isNotEmpty && outgoing.isNotEmpty;
    final lead = overdue.isNotEmpty ? 'Overdue and today' : 'Today';
    final tint = overdue.isNotEmpty
        ? palette.out.tint
        : mixed
        ? palette.surfaceAlt
        : incoming.isNotEmpty
        ? palette.incoming.tint
        : palette.out.tint;
    final ink = overdue.isNotEmpty
        ? palette.out.text
        : mixed
        ? palette.text2
        : incoming.isNotEmpty
        ? palette.incoming.text
        : palette.out.text;
    final icon = mixed
        ? Icons.calendar_today_outlined
        : incoming.isNotEmpty
        ? Icons.south_west
        : Icons.north_east;
    return Material(
      color: overdue.isNotEmpty ? palette.out.tint : _dashboardSurface(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: Theme.of(context).brightness == Brightness.dark
            ? BorderSide(color: palette.line.withValues(alpha: .55))
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showBreakdown(context, shown, lead, data: data),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 20, color: ink),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  children: [
                    if (incoming.isNotEmpty)
                      _TodayFlowLine(
                        items: incoming,
                        today: data.today,
                        incoming: true,
                      ),
                    if (mixed) const SizedBox(height: 6),
                    if (outgoing.isNotEmpty)
                      _TodayFlowLine(
                        items: outgoing,
                        today: data.today,
                        incoming: false,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayFlowLine extends StatelessWidget {
  const _TodayFlowLine({
    required this.items,
    required this.today,
    required this.incoming,
  });
  final List<HomeDue> items;
  final DateTime today;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.homePaletteOf(context);
    final amount = items.fold<int>(0, (sum, due) => sum + due.amount);
    final names = items
        .map((item) => displayName(item.name))
        .toSet()
        .join(', ');
    final hasOverdue = items.any((item) => item.date.isBefore(today));
    final hasToday = items.any((item) => item.date == today);
    final lead = hasOverdue && hasToday
        ? 'Overdue + today'
        : hasOverdue
        ? 'Overdue'
        : 'Today';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$lead · ${items.length} ${incoming ? 'to collect' : 'to pay'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: _SignedAmount(
                incoming ? amount : -amount,
                style: _label(
                  context,
                )?.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        Text(
          names,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _label(context)?.copyWith(fontSize: 13, color: palette.text2),
        ),
      ],
    );
  }
}

class _EmiCategorySummaries extends StatelessWidget {
  const _EmiCategorySummaries({required this.data});
  final HomeOverview data;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.homePaletteOf(context);
    Widget summary({
      required EmiCategory category,
      required String title,
      required int amount,
      required int overdue,
    }) {
      final tone = category == EmiCategory.personal
          ? colors.owe
          : colors.incoming;
      return Expanded(
        child: _Card(
          onTap: () {
            final scope = ProviderScope.containerOf(context, listen: false);
            scope.read(emiOverviewCategoryProvider.notifier).state = category;
            scope.read(shellIndexProvider.notifier).state = 1;
          },
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    category == EmiCategory.personal
                        ? Icons.account_balance_outlined
                        : Icons.people_outline,
                    size: 18,
                    color: tone.text,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.text,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 17, color: colors.text2),
                ],
              ),
              const SizedBox(height: 10),
              AmountText(
                amount,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: colors.text,
                ),
              ),
              if (overdue > 0) ...[
                const SizedBox(height: 5),
                Text(
                  'Overdue to ${category == EmiCategory.personal ? 'pay' : 'receive'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.out.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                AmountText(
                  overdue,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.out.text,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        summary(
          category: EmiCategory.personal,
          title: 'Personal EMI debt',
          amount: data.emiRemaining,
          overdue: data.personalOverdue,
        ),
        const SizedBox(width: 10),
        summary(
          category: EmiCategory.givenToFriends,
          title: 'Given-to-others EMI',
          amount: data.friendRemaining,
          overdue: data.friendOverdue,
        ),
      ],
    );
  }
}

class _IncomeRecovery extends ConsumerWidget {
  const _IncomeRecovery({required this.data});
  final HomeOverview data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.homePaletteOf(context);
    final income = ref.watch(personalEmiIncomeProvider).valueOrNull;
    final percent = personalEmiIncomePercent(data.personalDueThisMonth, income);
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.emis.isNotEmpty)
            Expanded(
              child: InkWell(
                onTap: () =>
                    openPersonalEmiIncomeInsight(context, ref, data.emis),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Personal EMIs / income',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      percent == null
                          ? 'Add income'
                          : '$percent% · ${personalEmiIncomeZone(percent)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.text,
                      ),
                    ),
                    Text(
                      'Scheduled this month',
                      style: TextStyle(fontSize: 12, color: colors.text2),
                    ),
                  ],
                ),
              ),
            ),
          if (data.emis.isNotEmpty && data.friendTotal > 0)
            const SizedBox(width: 14),
          if (data.friendTotal > 0)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Repayment progress',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(data.friendPaid * 100 / data.friendTotal).round()}% received',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.incoming.text,
                    ),
                  ),
                  AmountText(
                    data.friendPaid,
                    style: TextStyle(fontSize: 12, color: colors.text2),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthlyProjection extends StatelessWidget {
  const _MonthlyProjection({required this.data});
  final HomeOverview data;

  void _openMonth(BuildContext context, HomeMonth month) {
    final colors = AppTheme.homePaletteOf(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: math.min(
            MediaQuery.sizeOf(sheetContext).height * .72,
            210.0 + month.items.length * 64.0,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('MMMM yyyy').format(month.start),
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Future unpaid dues · overdue shown separately',
                  style: TextStyle(fontSize: 13, color: colors.text2),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Coming in  ',
                          style: TextStyle(color: colors.text2),
                        ),
                        AmountText(
                          month.incoming,
                          style: TextStyle(
                            color: colors.incoming.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Going out  ',
                          style: TextStyle(color: colors.text2),
                        ),
                        AmountText(
                          month.outgoing,
                          style: TextStyle(
                            color: colors.out.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: month.items.isEmpty
                      ? Center(
                          child: Text(
                            'Nothing scheduled for this month',
                            style: TextStyle(color: colors.text2),
                          ),
                        )
                      : ListView.builder(
                          itemCount: month.items.length,
                          itemBuilder: (context, index) {
                            final item = month.items[index];
                            return FlowRow(
                              item: item,
                              today: data.today,
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _openDue(context, item, data);
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

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.homePaletteOf(context);
    final largest = data.months.fold<int>(
      0,
      (value, month) =>
          math.max(value, math.max(month.incoming, month.outgoing)),
    );
    double height(int value) =>
        value == 0 || largest == 0 ? 0 : math.max(5, 50 * value / largest);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monthly outlook', style: _title(context)),
          const SizedBox(height: 4),
          Text(
            'Next 6 months · future unpaid dues; overdue shown above',
            style: TextStyle(fontSize: 12, color: colors.text2),
          ),
          const SizedBox(height: 16),
          RepaintBoundary(
            child: Row(
              children: [
                for (final month in data.months)
                  Expanded(
                    child: Semantics(
                      button: true,
                      label:
                          '${DateFormat('MMMM yyyy').format(month.start)}, '
                          'coming in ${formatMoney(month.incoming)}, '
                          'going out ${formatMoney(month.outgoing)}',
                      child: InkWell(
                        key: ValueKey(
                          'home-month-${month.start.year}-${month.start.month}',
                        ),
                        onTap: () => _openMonth(context, month),
                        child: Column(
                          children: [
                            SizedBox(
                              height: 51,
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  width: 13,
                                  height: height(month.incoming),
                                  decoration: BoxDecoration(
                                    color: colors.incoming.graphic,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            SizedBox(
                              height: 51,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: Container(
                                  width: 13,
                                  height: height(month.outgoing),
                                  decoration: BoxDecoration(
                                    color: colors.out.graphic,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              DateFormat('MMM').format(month.start),
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.text2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: [
              Text(
                '● Expected in',
                style: TextStyle(fontSize: 12, color: colors.incoming.text),
              ),
              Text(
                '● Due out',
                style: TextStyle(fontSize: 12, color: colors.out.text),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoneyBalance extends StatelessWidget {
  const _MoneyBalance({required this.data});
  final HomeOverview data;
  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.homePaletteOf(context);
    final card = AppTheme.netCardOf(context);
    final net = data.toCollect - data.toPay;
    return Container(
      decoration: BoxDecoration(
        color: card.surface,
        borderRadius: BorderRadius.circular(24),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: card.border.withValues(alpha: .75))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Money records balance',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: card.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'About money records balance',
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.info_outline, size: 20, color: card.muted),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: palette.surface,
                    showDragHandle: true,
                    builder: (sheetContext) => SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Money records balance',
                              style: _title(sheetContext),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Outstanding Money lent minus Money borrowed. Personal EMIs and repayment agreements given to others are shown separately above so overlapping records are not merged here.',
                              style: Theme.of(
                                sheetContext,
                              ).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AmountText(
                net,
                maskWithSymbol: true,
                symbolStyle: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: card.muted,
                ),
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  color: card.text,
                  fontSize: 52,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _HeroFlowChip(
                    label: 'Lent',
                    amount: data.toCollect,
                    tint: palette.incoming.tint,
                    ink: palette.incoming.text,
                    muted: card.muted,
                    icon: Icons.arrow_drop_up_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HeroFlowChip(
                    label: 'Borrowed',
                    amount: data.toPay,
                    tint: card.borrowedBg,
                    ink: card.redText,
                    muted: card.muted,
                    icon: Icons.arrow_drop_down_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Forecast(data: data),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Color.lerp(
                  card.surface,
                  card.debtBg,
                  Theme.of(context).brightness == Brightness.dark ? .6 : .35,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    Expanded(
                      child: constraints.maxWidth >= 330
                          ? Row(
                              children: [
                                Text(
                                  'Total debt',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: card.text,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'EMIs + borrowed',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: card.muted,
                                        fontSize: 12,
                                      ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total debt',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: card.text,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                Text(
                                  'EMIs + borrowed',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: card.muted,
                                        fontSize: 12,
                                      ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(width: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _SignedAmount(
                        -data.totalDebt,
                        color: card.redText,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroFlowChip extends StatelessWidget {
  const _HeroFlowChip({
    required this.label,
    required this.amount,
    required this.tint,
    required this.ink,
    required this.muted,
    required this.icon,
  });
  final String label;
  final int amount;
  final Color tint, ink, muted;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Color.lerp(
        AppTheme.netCardOf(context).surface,
        tint,
        Theme.of(context).brightness == Brightness.dark ? .6 : .4,
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: ink.withValues(alpha: .12),
          child: Icon(icon, size: 18, color: ink),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: muted, fontSize: 12),
                ),
                const SizedBox(width: 5),
                AmountText(
                  amount,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _Forecast extends StatefulWidget {
  const _Forecast({required this.data});
  final HomeOverview data;
  @override
  State<_Forecast> createState() => _ForecastState();
}

class _ForecastState extends State<_Forecast>
    with SingleTickerProviderStateMixin {
  static bool _hasAnimated = false;
  DateTime? _selectedWeekStart;
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    value: _hasAnimated ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    if (!_hasAnimated) {
      _hasAnimated = true;
      _grow.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _Forecast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.today != widget.data.today) {
      _selectedWeekStart = null;
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = AppTheme.netCardOf(context);
    final incoming = AppTheme.homePaletteOf(context).incoming;
    final weeks = widget.data.weeks;
    final heavy = widget.data.heaviestDueDay;
    final maxIn = weeks.fold<int>(
      0,
      (max, week) => math.max(max, week.incoming),
    );
    final maxOut = weeks.fold<int>(
      0,
      (max, week) => math.max(max, week.outgoing),
    );
    final maxValue = math.max(maxIn, maxOut);
    double fullHeight(int value) =>
        value == 0 || maxValue == 0 ? 0 : math.max(6, 40 * value / maxValue);
    final upperHeight = maxIn == 0 ? 16.0 : fullHeight(maxIn) + 20;
    final lowerHeight = maxOut == 0 ? 16.0 : fullHeight(maxOut) + 20;
    final selectedIndex = weeks.indexWhere(
      (week) => week.start == _selectedWeekStart,
    );
    final selected = selectedIndex < 0 ? 0 : selectedIndex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Next 5 weeks',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: card.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              'Tap a week',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: card.muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _grow,
            builder: (context, _) => Row(
              children: [
                for (var i = 0; i < weeks.length; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      label:
                          '${formatWeekRange(weeks[i].start, today: widget.data.today)}, '
                          '${formatMoney(weeks[i].incoming)} in, '
                          '${formatMoney(weeks[i].outgoing)} out',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() => _selectedWeekStart = weeks[i].start);
                          _showBreakdown(
                            context,
                            weeks[i].items,
                            formatWeekRange(
                              weeks[i].start,
                              today: widget.data.today,
                            ),
                            data: widget.data,
                          );
                        },
                        child: _ForecastWeekColumn(
                          week: weeks[i],
                          card: card,
                          today: widget.data.today,
                          selected: selected == i,
                          maxValue: maxValue,
                          upperHeight: upperHeight,
                          lowerHeight: lowerHeight,
                          grow: MediaQuery.disableAnimationsOf(context)
                              ? 1
                              : _grow.value,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            CircleAvatar(radius: 3, backgroundColor: incoming.graphic),
            const SizedBox(width: 5),
            Text(
              'In',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: incoming.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 14),
            CircleAvatar(radius: 3, backgroundColor: card.redBar),
            const SizedBox(width: 5),
            Text(
              'Out',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: card.redText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (heavy != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Heaviest ${formatShortDate(heavy.date, today: widget.data.today)} · ',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: card.muted, fontSize: 12),
                        ),
                        _SignedAmount(
                          -widget.data.heaviestDueDayAmount,
                          color: card.redText,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ForecastWeekColumn extends StatelessWidget {
  const _ForecastWeekColumn({
    required this.week,
    required this.card,
    required this.today,
    required this.selected,
    required this.maxValue,
    required this.upperHeight,
    required this.lowerHeight,
    required this.grow,
  });
  final HomeWeek week;
  final NetCardPalette card;
  final DateTime today;
  final bool selected;
  final int maxValue;
  final double upperHeight, lowerHeight;
  final double grow;

  @override
  Widget build(BuildContext context) {
    final incoming = AppTheme.homePaletteOf(context).incoming;
    double height(int value) => value == 0 || maxValue == 0
        ? 0
        : math.max(6, 40 * value / maxValue) * grow;
    final inHeight = height(week.incoming);
    final outHeight = height(week.outgoing);
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 12,
      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
    );
    return Container(
      decoration: BoxDecoration(
        color: selected ? card.selectedBg : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          SizedBox(
            height: upperHeight + lowerHeight,
            child: Stack(
              children: [
                if (inHeight > 0) ...[
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: lowerHeight + inHeight + 4,
                    height: 16,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _SignedAmount(
                        week.incoming,
                        compact: true,
                        color: incoming.text,
                        style: labelStyle,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: lowerHeight,
                    child: Center(
                      child: Container(
                        width: 24,
                        height: inHeight,
                        decoration: BoxDecoration(
                          color: incoming.graphic,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
                if (outHeight > 0) ...[
                  Positioned(
                    left: 0,
                    right: 0,
                    top: upperHeight,
                    child: Center(
                      child: Container(
                        width: 24,
                        height: outHeight,
                        decoration: BoxDecoration(
                          color: selected ? card.redBar : card.mutedRedBar,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: upperHeight + outHeight + 4,
                    height: 16,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _SignedAmount(
                        -week.outgoing,
                        compact: true,
                        color: card.redText,
                        style: labelStyle,
                      ),
                    ),
                  ),
                ],
                if (week.incoming == 0 && week.outgoing == 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: upperHeight - 3,
                    child: Center(
                      child: CircleAvatar(
                        radius: 3,
                        backgroundColor: card.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              formatShortDate(week.start, today: today),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? card.text : card.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Next30 extends StatelessWidget {
  const _Next30({required this.data});
  final HomeOverview data;

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.homePaletteOf(context);
    final items = data.next30Outgoing;
    final parts = [
      ('EMI', 'emi', palette.emiTone.graphic),
      ('Money', 'money', palette.owe.graphic),
      ('Bills', 'subscription', palette.bills.graphic),
    ];
    final breakdown = [
      for (final part in parts)
        (
          part.$1,
          part.$3,
          items
              .where((item) => item.type == part.$2)
              .fold<int>(0, (sum, item) => sum + item.amount),
        ),
    ]..sort((a, b) => b.$3.compareTo(a.$3));
    final total = breakdown.fold<int>(0, (sum, part) => sum + part.$3);
    assert(total == data.next30OutgoingTotal);
    final paid = data.emis.fold<int>(0, (sum, item) => sum + item.paidPaise);
    final left = data.emis.fold<int>(
      0,
      (sum, item) => sum + item.remainingBalancePaise,
    );
    final paidCount = data.emis.fold<int>(
      0,
      (sum, item) => sum + item.paidInstallments,
    );
    final installmentCount = data.emis.fold<int>(
      0,
      (sum, item) => sum + item.emi.tenureMonths,
    );
    final ringPaid = paid + left > 0 ? paid : paidCount;
    final ringLeft = paid + left > 0 ? left : installmentCount - paidCount;
    final progress = ringPaid + ringLeft > 0
        ? ringPaid / (ringPaid + ringLeft)
        : 0.0;
    final hasPausedEmi = data.emis.any(
      (item) => item.emi.status == EmiStatus.paused,
    );
    final endings = [
      for (final item in data.emis)
        if (item.emi.status != EmiStatus.paused)
          (
            item,
            item.installments
                .lastWhere((installment) => !installment.isPaid)
                .dueDate,
          ),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    final firstEnd = endings.firstOrNull?.$2;
    final lastEnd = hasPausedEmi ? null : data.debtFreeDate;
    final lastNames = lastEnd == null
        ? ''
        : endings
              .where((item) => item.$2 == lastEnd)
              .map((item) => displayName(item.$1.emi.name))
              .join(' & ');
    final months = lastEnd == null
        ? 0
        : math.max(
            0,
            (lastEnd.year - data.today.year) * 12 +
                lastEnd.month -
                data.today.month,
          );
    return _Card(
      onTap: items.isEmpty
          ? null
          : () => _showBreakdown(
              context,
              items,
              'Obligations · next 30 days',
              data: data,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (total > 0) ...[
            Row(
              children: [
                Expanded(
                  child: Text('Next 30 days · to pay', style: _title(context)),
                ),
                _SignedAmount(
                  -total,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final part in breakdown.where((part) => part.$3 > 0))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    CircleAvatar(radius: 4, backgroundColor: part.$2),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        part.$1,
                        style: _label(
                          context,
                        )?.copyWith(color: palette.text2, fontSize: 13),
                      ),
                    ),
                    _SignedAmount(
                      -part.$3,
                      style: _label(context)?.copyWith(
                        fontSize: 13,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${total == 0 ? 0 : (100 * part.$3 / total).round()}%',
                        textAlign: TextAlign.right,
                        style: _label(context)?.copyWith(color: palette.text3),
                      ),
                    ),
                  ],
                ),
              ),
            if (data.emis.isNotEmpty)
              Divider(height: 24, color: palette.line.withValues(alpha: .55)),
          ],
          if (data.emis.isNotEmpty) ...[
            Text('Debt-free', style: _title(context)),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox.square(
                  dimension: 72,
                  child: _DebtProgressRing(
                    paid: ringPaid,
                    left: ringLeft,
                    percentage: (progress * 100).round(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: lastEnd == null
                      ? Text(
                          'Debt-free date unavailable while an EMI is paused',
                          style: _label(
                            context,
                          )?.copyWith(color: palette.text2),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$months ${months == 1 ? 'month' : 'months'} to go · ${formatMonthYear(lastEnd)}',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: palette.text,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Next to finish: ${displayName(endings.first.$1.emi.name)} · ${formatShortDate(firstEnd!, today: data.today)}',
                              style: _label(
                                context,
                              )?.copyWith(color: palette.text2),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Last: $lastNames · ${formatMonthYear(lastEnd)}',
                              style: _label(
                                context,
                              )?.copyWith(color: palette.text2),
                            ),
                          ],
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

class _DebtProgressRing extends StatefulWidget {
  const _DebtProgressRing({
    required this.paid,
    required this.left,
    required this.percentage,
  });

  final int paid, left, percentage;

  @override
  State<_DebtProgressRing> createState() => _DebtProgressRingState();
}

class _DebtProgressRingState extends State<_DebtProgressRing>
    with SingleTickerProviderStateMixin {
  static bool _hasAnimated = false;
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: _hasAnimated ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    if (!_hasAnimated) {
      _hasAnimated = true;
      _grow.forward();
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.homePaletteOf(context);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _grow,
        child: Center(
          child: Text(
            '${widget.percentage}% paid',
            style: _label(
              context,
            )?.copyWith(color: palette.text, fontWeight: FontWeight.w700),
          ),
        ),
        builder: (context, child) => CustomPaint(
          painter: _DonutPainter(
            [widget.paid, widget.left],
            [palette.incoming.graphic, palette.surfaceAlt],
            palette.surfaceAlt,
            MediaQuery.disableAnimationsOf(context) ? 1 : _grow.value,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.values, this.colors, this.track, this.grow);
  final List<int> values;
  final List<Color> colors;
  final Color track;
  final double grow;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(6);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    final total = values.fold<int>(0, (n, e) => n + e);
    if (total == 0) return;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = 2 * math.pi * values[i] / total;
      if (sweep > 0) {
        canvas.drawArc(
          rect,
          start,
          sweep * grow,
          false,
          paint..color = colors[i],
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.track != track ||
      old.grow != grow ||
      old.values.toString() != values.toString() ||
      old.colors.toString() != colors.toString();
}

class _SecondaryTiles extends StatelessWidget {
  const _SecondaryTiles({required this.data});
  final HomeOverview data;
  @override
  Widget build(BuildContext context) => _Card(
    padding: EdgeInsets.zero,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(
        Theme.of(context).brightness == Brightness.dark ? 20 : 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (data.toCollect > 0) _ToCollect(data: data),
          if (data.emis.isNotEmpty) _NextPay(data: data),
        ],
      ),
    ),
  );
}

class _ToCollect extends StatelessWidget {
  const _ToCollect({required this.data});
  final HomeOverview data;

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.homePaletteOf(context);
    final totals = <String, int>{};
    final dates = <String, DateTime>{};
    final partlyPaid = <String, bool>{};
    var later = 0;
    final windowEnd = data.today.add(const Duration(days: 35));
    for (final detail in data.money) {
      if (detail.record.direction != MoneyDirection.given ||
          detail.summary.remainingAmountPaise <= 0) {
        continue;
      }
      final name = detail.record.personName;
      totals.update(
        name,
        (value) => value + detail.summary.remainingAmountPaise,
        ifAbsent: () => detail.summary.remainingAmountPaise,
      );
      partlyPaid[name] =
          (partlyPaid[name] ?? false) || detail.summary.repaidAmountPaise > 0;
      final due = detail.record.dueDate;
      if (due != null) {
        if (dates[name] == null || due.isBefore(dates[name]!)) {
          dates[name] = due;
        }
        if (!due.isBefore(windowEnd)) {
          later += detail.summary.remainingAmountPaise;
        }
      }
    }
    final people = totals.keys.toList()
      ..sort((a, b) {
        final aDate = dates[a], bDate = dates[b];
        if (aDate == null) return bDate == null ? a.compareTo(b) : 1;
        if (bDate == null) return -1;
        return aDate.compareTo(bDate);
      });
    Color dueColor(DateTime? due) {
      if (due == null) return palette.text2;
      final days = DateUtils.dateOnly(
        due,
      ).difference(DateUtils.dateOnly(data.today)).inDays;
      if (days < 0) return palette.out.text;
      if (days <= 7) return palette.emiTone.text;
      return palette.incoming.text;
    }

    String receivableStatus(String name) {
      final status = partlyPaid[name] == true ? 'Partly paid' : 'Unpaid';
      final due = dates[name];
      if (due == null) return '$status · No due date';
      return '$status · ${formatShortDate(due, today: data.today)} · '
          '${formatDayDistance(due, data.today, alwaysDays: true)}';
    }

    return Material(
      color: _dashboardSurface(context),
      child: InkWell(
        onTap: () => _tab(context, 2),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: palette.incoming.tint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.south_west_rounded,
                      size: 20,
                      color: palette.incoming.text,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'To receive',
                          style: _label(context)?.copyWith(
                            fontSize: 13,
                            color: palette.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: _SignedAmount(
                            data.toCollect,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: palette.incoming.text,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: palette.incoming.text,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final name in people.take(2))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: palette.incoming.tint,
                        child: Text(
                          name.isEmpty ? '?' : name[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: palette.incoming.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName(name),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _label(
                                context,
                              )?.copyWith(color: palette.text),
                            ),
                            Text(
                              receivableStatus(name),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _label(context)?.copyWith(
                                color: dueColor(dates[name]),
                                fontWeight: dates[name] == null
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _SignedAmount(
                          totals[name]!,
                          style: _label(context)?.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (people.isEmpty)
                Text('Nothing to receive', style: _label(context)),
              if (later > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      _SignedAmount(later, style: _label(context)),
                      Text(' later', style: _label(context)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextPay extends StatelessWidget {
  const _NextPay({required this.data});
  final HomeOverview data;

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.homePaletteOf(context);
    final upcoming = data.dues.where((due) => due.type == 'emi').toList();
    final date = upcoming.firstOrNull?.date;
    final sameDay = date == null
        ? upcoming
        : upcoming.where((due) => due.date == date).toList();
    final total = sameDay.fold<int>(0, (sum, due) => sum + due.amount);
    final dayText = date == null
        ? 'No EMI due'
        : formatDayDistance(date, data.today, alwaysDays: true);
    final daysUntilDue = date == null
        ? null
        : DateUtils.dateOnly(
            date,
          ).difference(DateUtils.dateOnly(data.today)).inDays;
    final overdue = daysUntilDue != null && daysUntilDue < 0;
    final dueColor = overdue ? palette.out.text : palette.emiTone.text;
    return Material(
      color: Color.lerp(
        _dashboardSurface(context),
        palette.surfaceAlt,
        Theme.of(context).brightness == Brightness.dark ? .6 : .25,
      ),
      child: InkWell(
        onTap: () => _tab(context, 1),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: overdue ? palette.out.tint : palette.emiTone.tint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (date == null)
                      Icon(
                        Icons.calendar_month_outlined,
                        size: 24,
                        color: palette.emiTone.text,
                      )
                    else
                      Text(
                        '${date.day}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: dueColor,
                        ),
                      ),
                    Text(
                      'EMI',
                      style: _label(
                        context,
                      )?.copyWith(color: dueColor, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next EMI',
                      style: _label(context)?.copyWith(
                        fontSize: 13,
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (overdue)
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: 'Overdue ',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            TextSpan(
                              text: plural(-daysUntilDue, 'day'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontSize: 22, color: dueColor),
                      )
                    else
                      Text(
                        dayText,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: dueColor,
                            ),
                      ),
                    if (date != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        formatWeekdayShortDate(date, today: data.today),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: overdue ? palette.out.text : palette.text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 3,
                        children: [
                          Text(
                            '${sameDay.length} ${sameDay.length == 1 ? 'payment' : 'payments'} ·',
                            style: _label(context),
                          ),
                          _SignedAmount(
                            -total,
                            style: _label(
                              context,
                            )?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${displayName(sameDay.first.name)}${sameDay.length > 1 ? ' +${sameDay.length - 1} more' : ''}',
                        maxLines: 2,
                        style: _label(context)?.copyWith(color: palette.text2),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: dueColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThisWeek extends StatefulWidget {
  const _ThisWeek({required this.data});
  final HomeOverview data;

  @override
  State<_ThisWeek> createState() => _ThisWeekState();
}

class _ThisWeekState extends State<_ThisWeek> {
  DateTime? _selected;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final palette = AppTheme.homePaletteOf(context);
    final week = data.dues
        .where(
          (due) =>
              !due.date.isBefore(data.today) &&
              due.date.isBefore(data.today.add(const Duration(days: 7))),
        )
        .toList();
    final selected = _selected ?? data.today;
    final onDay = week.where((due) => due.date == selected).toList();
    final dayNet = onDay.fold<int>(
      0,
      (sum, due) => sum + (due.incoming ? due.amount : -due.amount),
    );
    String subtitleFor(HomeDue due) {
      if (due.type == 'money') {
        final record = data.money
            .where((item) => item.record.id == due.id)
            .firstOrNull;
        final status = (record?.summary.repaidAmountPaise ?? 0) > 0
            ? 'Partly paid'
            : 'Unpaid';
        return '${due.incoming ? 'Money given' : 'Money borrowed'} · $status';
      }
      return switch (due.type) {
        'emi' => 'Personal EMI · Due',
        'friendEmi' => 'Friend repayment · Due',
        _ => 'Bill · Renewal',
      };
    }

    final subscription = data.dues
        .where(
          (due) => due.type == 'subscription' && !due.date.isBefore(data.today),
        )
        .firstOrNull;
    final endings = data.emis.toList()
      ..sort(
        (a, b) =>
            a.installments.last.dueDate.compareTo(b.installments.last.dueDate),
      );
    final insights = <Widget>[
      if (subscription != null)
        _InsightLine(
          icon: Icons.autorenew_outlined,
          tint: palette.bills.tint,
          ink: palette.bills.text,
          text:
              '${displayName(subscription.name)} renews ${formatDayDistance(subscription.date, data.today, alwaysDays: true)} · ',
          amount: subscription.amount,
          suffix: '',
          incoming: false,
          onTap: () => _openDue(context, subscription, data),
        ),
      if (endings.isNotEmpty)
        _InsightLine(
          icon: Icons.trending_down_outlined,
          tint: palette.emiTone.tint,
          ink: palette.emiTone.text,
          text:
              '${displayName(endings.first.emi.name)} ends ${formatDayDistance(endings.first.installments.last.dueDate, data.today, alwaysDays: true)} · frees ',
          amount: endings.first.scheduledInstallmentPaise,
          suffix: ' a month',
          incoming: true,
          onTap: () => _tab(context, 1),
        ),
    ];
    return _Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('This week', style: _title(context))),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: palette.text,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const UpcomingScreen(),
                  ),
                ),
                child: const Text('See all ›'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Builder(
                      builder: (context) {
                        final day = data.today.add(Duration(days: i));
                        final dayItems = week
                            .where((due) => due.date == day)
                            .toList();
                        final active = selected == day;
                        return Tooltip(
                          message:
                              '${formatShortDate(day, today: data.today)}: ${dayItems.length} due',
                          child: InkWell(
                            onTap: () => setState(() => _selected = day),
                            borderRadius: BorderRadius.circular(22),
                            child: Container(
                              width: double.infinity,
                              height: 64,
                              decoration: BoxDecoration(
                                color: i == 0
                                    ? palette.text
                                    : active
                                    ? palette.surfaceAlt
                                    : palette.surface,
                                borderRadius: BorderRadius.circular(22),
                                border: active && i != 0
                                    ? Border.all(color: palette.line)
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    const [
                                      'M',
                                      'T',
                                      'W',
                                      'T',
                                      'F',
                                      'S',
                                      'S',
                                    ][day.weekday - 1],
                                    style: _label(context)?.copyWith(
                                      fontSize: 12,
                                      color: i == 0
                                          ? palette.surface
                                          : palette.text3,
                                    ),
                                  ),
                                  Text(
                                    '${day.day}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: i == 0
                                              ? palette.surface
                                              : palette.text,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    height: 8,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if (dayItems.any((due) => due.incoming))
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 1,
                                            ),
                                            child: CircleAvatar(
                                              radius: 2.5,
                                              backgroundColor:
                                                  palette.incoming.graphic,
                                            ),
                                          ),
                                        if (dayItems.any(
                                          (due) => !due.incoming,
                                        ))
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 1,
                                            ),
                                            child: CircleAvatar(
                                              radius: 2.5,
                                              backgroundColor:
                                                  palette.out.graphic,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${formatDayDistance(selected, data.today, alwaysDays: true)} · ${formatShortDate(selected, today: data.today)}',
                  style: _title(context)?.copyWith(fontSize: 15),
                ),
              ),
              if (onDay.isNotEmpty)
                _SignedAmount(
                  dayNet,
                  style: _title(context)?.copyWith(fontSize: 15),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (onDay.isEmpty) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: palette.incoming.tint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: palette.incoming.text,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      selected == data.today
                          ? 'Nothing due today'
                          : 'Nothing due on ${formatShortDate(selected, today: data.today)}',
                      style: _label(context)?.copyWith(
                        color: palette.incoming.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            for (final item in onDay.take(3))
              FlowRow(
                item: item,
                today: data.today,
                subtitle: subtitleFor(item),
                onTap: () => _openDue(context, item, data),
              ),
            if (onDay.length > 3)
              TextButton(
                onPressed: () => _showBreakdown(
                  context,
                  onDay,
                  formatShortDate(selected, today: data.today),
                  data: data,
                ),
                child: Text('${onDay.length - 3} more'),
              ),
          ],
          if (insights.isNotEmpty) ...[
            Divider(height: 24, color: palette.line.withValues(alpha: .55)),
            Text(
              'Worth knowing',
              style: _title(context)?.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 6),
            ...insights.take(2),
          ],
        ],
      ),
    );
  }
}

class _InsightLine extends StatelessWidget {
  const _InsightLine({
    required this.icon,
    required this.tint,
    required this.ink,
    required this.text,
    required this.amount,
    required this.suffix,
    required this.incoming,
    required this.onTap,
  });

  final IconData icon;
  final Color tint, ink;
  final String text, suffix;
  final bool incoming;
  final int amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.homePaletteOf(context);
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontSize: 14, color: palette.text);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: tint,
              child: Icon(icon, size: 18, color: ink),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                spacing: 3,
                runSpacing: 2,
                children: [
                  Text(text, style: style),
                  _SignedAmount(incoming ? amount : -amount, style: style),
                  if (suffix.isNotEmpty) Text(suffix, style: style),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: palette.text2),
          ],
        ),
      ),
    );
  }
}

class _SignedAmount extends StatelessWidget {
  const _SignedAmount(
    this.value, {
    this.style,
    this.compact = false,
    this.color,
  });

  final int value;
  final TextStyle? style;
  final bool compact;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.homePaletteOf(context);
    final color = value > 0
        ? palette.incoming.text
        : value < 0
        ? palette.out.text
        : palette.text;
    final amountStyle =
        (style ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
            .copyWith(
              color: this.color ?? color,
              fontFeatures: const [FontFeature.tabularFigures()],
            );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (value != 0 && !privacyAmountsHidden)
          Text(value > 0 ? '+' : '−', style: amountStyle),
        AmountText(value.abs(), compact: compact, style: amountStyle),
      ],
    );
  }
}

class FlowRow extends StatelessWidget {
  const FlowRow({
    super.key,
    required this.item,
    required this.today,
    required this.onTap,
    this.subtitle,
  });
  final HomeDue item;
  final DateTime today;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.homePaletteOf(context);
    final tone = switch (item.type) {
      'emi' => palette.emiTone,
      'friendEmi' => palette.incoming,
      'subscription' => palette.bills,
      _ => palette.owe,
    };
    final icon = switch (item.type) {
      'emi' => Icons.account_balance_outlined,
      'friendEmi' => Icons.people_outline,
      'subscription' => Icons.autorenew_outlined,
      _ => Icons.people_outline,
    };
    final category = switch (item.type) {
      'emi' => 'Personal EMI',
      'friendEmi' => 'Friend repayment',
      'subscription' => 'Bill',
      _ => 'Money',
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tone.tint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: tone.graphic),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName(item.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 15,
                      color: palette.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        subtitle ??
                            '$category · ${formatWeekdayShortDate(item.date, today: today)}',
                        style: _label(
                          context,
                        )?.copyWith(fontSize: 13, color: palette.text2),
                      ),
                      if (item.date.isBefore(today))
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: palette.out.tint,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Overdue',
                            style: _label(
                              context,
                            )?.copyWith(fontSize: 12, color: palette.out.text),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _SignedAmount(
              item.incoming ? item.amount : -item.amount,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _tab(BuildContext context, int index) => ProviderScope.containerOf(
  context,
  listen: false,
).read(shellIndexProvider.notifier).state = index;

void _openDue(BuildContext context, HomeDue item, HomeOverview data) {
  switch (item.type) {
    case 'emi':
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => EmiDetailScreen(item.id)));
    case 'friendEmi':
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EmiAgreementDetailScreen(item.id),
        ),
      );
    case 'money':
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => MoneyDetailScreen(item.id)),
      );
    case 'subscription':
      final sub = data.subscriptions.where((e) => e.id == item.id).firstOrNull;
      if (sub != null) openSubscriptionDetailSheet(context, sub);
  }
}

void _showBreakdown(
  BuildContext context,
  List<HomeDue> items,
  String title, {
  HomeOverview? data,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: AppTheme.homePaletteOf(context).surface,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _title(context)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .55,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (_, index) {
                  final item = items[index];
                  return FlowRow(
                    item: item,
                    today: data?.today ?? DateTime.now(),
                    onTap: () {
                      if (data == null) return;
                      Navigator.of(sheetContext).pop();
                      _openDue(context, item, data);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'In',
                    style: TextStyle(
                      color: AppTheme.homePaletteOf(context).incoming.text,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: _SignedAmount(
                    items
                        .where((e) => e.incoming)
                        .fold(0, (n, e) => n + e.amount),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Out',
                    style: TextStyle(
                      color: AppTheme.homePaletteOf(context).out.text,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: _SignedAmount(
                    -items
                        .where((e) => !e.incoming)
                        .fold(0, (n, e) => n + e.amount),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(child: Text('Net')),
                Align(
                  alignment: Alignment.centerRight,
                  child: _SignedAmount(
                    items.fold<int>(
                      0,
                      (n, e) => n + (e.incoming ? e.amount : -e.amount),
                    ),
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
