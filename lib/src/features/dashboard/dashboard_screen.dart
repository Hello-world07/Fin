import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../domain/enums.dart';
import '../../shared/finance_display_widgets.dart';
import '../../shared/forms.dart';
import '../../shared/notched_navigation_bar.dart';
import '../emis/emis_screen.dart';
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

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(homeOverviewProvider);
    final hasAnyEmi = ref.watch(emiDetailsProvider.select(
      (state) => state.valueOrNull?.isNotEmpty ?? false,
    ));
    final private = ref.watch(privacyModeProvider.select((s) => s.enabled));
    final home = AppTheme.homePaletteOf(context);
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
        if (overview.dues.any((due) => !due.date.isAfter(overview.today)))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: _TodayStrip(data: overview),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: RepaintBoundary(child: _MoneyBalance(data: overview)),
        ),
        if (overview.toCollect > 0 || overview.emis.isNotEmpty)
          _Band(child: _SecondaryTiles(data: overview)),
        if (overview.emis.isNotEmpty || overview.nextFiveWeeks.isNotEmpty)
          _Band(child: _Next30(data: overview)),
        if (overview.dues.isNotEmpty)
          _Band(child: _ThisWeek(data: overview)),
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
                bottom: NotchedNavigationMetrics.contentPadding(context) -
                    NotchedNavigationMetrics.contentGap + 16,
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
    ));
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
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top,
        16, 0),
      child: Row(children: [
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FinKeep',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontSize: 28,
              color: palette.text,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '$greeting · ${formatShortDate(now, today: now)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(
              fontSize: 13,
              color: palette.text2,
            ),
          ),
        ],
      )),
        IconButton(
          tooltip: private ? 'Show amounts' : 'Hide amounts',
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          onPressed: onPrivacy,
          icon: Icon(
            private ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 24,
            semanticLabel: private ? 'Show amounts' : 'Hide amounts',
          ),
        ),
        IconButton(
          tooltip: 'Settings',
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          onPressed: onSettings,
          icon: const Icon(Icons.settings_outlined, size: 24, semanticLabel: 'Settings'),
        ),
      ]),
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: RepaintBoundary(child: child),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: AppTheme.colorsOf(context).surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: AppTheme.homePaletteOf(context).line),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(padding: padding, child: child),
    ),
  );
}

TextStyle? _title(BuildContext context) =>
    Theme.of(context).textTheme.titleMedium?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
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
    return Column(children: [
      _Band(child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [palette.heroStart, palette.heroEnd]),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Net owed to you', style: _label(context)?.copyWith(
            color: palette.heroText2, fontSize: 13)),
          const SizedBox(height: 8),
          AmountText(0, style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            color: palette.heroText, fontSize: 40, fontWeight: FontWeight.w800)),
        ]),
      )),
      _Band(child: _Card(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add your first EMI, loan or subscription', style: _title(context)),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => openFinanceSheet(context, const EmiFormSheet()),
            child: const Text('Add EMI'),
          ),
          FilledButton.tonal(
            onPressed: () => openFinanceSheet(context,
                const MoneyFormSheet(initialDirection: MoneyDirection.borrowed)),
            child: const Text('Add loan'),
          ),
          FilledButton.tonal(
            onPressed: () => openFinanceSheet(context, const SubscriptionFormSheet()),
            child: const Text('Add subscription'),
          ),
        ],
      ))),
    ]);
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
    final tint = overdue.isNotEmpty ? palette.out.tint
        : mixed ? palette.surfaceAlt
        : incoming.isNotEmpty ? palette.incoming.tint : palette.out.tint;
    final ink = overdue.isNotEmpty ? palette.out.text
        : mixed ? palette.text2
        : incoming.isNotEmpty ? palette.incoming.text : palette.out.text;
    final icon = mixed ? Icons.calendar_today_outlined
        : incoming.isNotEmpty ? Icons.south_west : Icons.north_east;
    return Material(
      color: overdue.isNotEmpty ? palette.out.tint : palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: palette.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showBreakdown(context, shown, lead, data: data),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: tint,
                borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 20, color: ink),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(children: [
              if (incoming.isNotEmpty)
                _TodayFlowLine(items: incoming, today: data.today,
                  incoming: true),
              if (mixed) const SizedBox(height: 6),
              if (outgoing.isNotEmpty)
                _TodayFlowLine(items: outgoing, today: data.today,
                  incoming: false),
            ])),
          ]),
        ),
      ),
    );
  }
}

class _TodayFlowLine extends StatelessWidget {
  const _TodayFlowLine({required this.items, required this.today,
    required this.incoming});
  final List<HomeDue> items;
  final DateTime today;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.homePaletteOf(context);
    final amount = items.fold<int>(0, (sum, due) => sum + due.amount);
    final names = items.map((item) => displayName(item.name)).toSet().join(', ');
    final hasOverdue = items.any((item) => item.date.isBefore(today));
    final hasToday = items.any((item) => item.date == today);
    final lead = hasOverdue && hasToday ? 'Overdue + today'
        : hasOverdue ? 'Overdue' : 'Today';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('$lead · ${items.length} ${incoming ? 'to collect' : 'to pay'}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: palette.text, fontSize: 15, fontWeight: FontWeight.w700))),
        const SizedBox(width: 6),
        FittedBox(fit: BoxFit.scaleDown,
          child: _SignedAmount(incoming ? amount : -amount,
            style: _label(context)?.copyWith(fontSize: 14,
              fontWeight: FontWeight.w700))),
      ]),
      Text(names, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: _label(context)?.copyWith(fontSize: 13, color: palette.text2)),
    ]);
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
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: card.border),
        boxShadow: [
          BoxShadow(color: card.shadow, blurRadius: 32,
            offset: const Offset(0, 12)),
        ],
      ),
      child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text('Net owed to you',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: card.muted, fontSize: 14, fontWeight: FontWeight.w600))),
            IconButton(
                tooltip: 'About net owed to you',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: EdgeInsets.zero,
                icon: Icon(Icons.info_outline, size: 20, color: card.muted),
                onPressed: () => showModalBottomSheet<void>(
                  context: context, backgroundColor: palette.surface,
                  showDragHandle: true,
                  builder: (sheetContext) => SafeArea(child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Net owed to you', style: _title(sheetContext)),
                      const SizedBox(height: 8),
                      Text('Money owed to you minus money you borrowed. Total debt includes EMIs and borrowed money.',
                        style: Theme.of(sheetContext).textTheme.bodyMedium),
                    ]),
                  )),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
            child: AmountText(net, maskWithSymbol: true,
              symbolStyle: TextStyle(fontSize: 28,
                fontWeight: FontWeight.w600, color: card.muted),
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                color: card.text, fontSize: 52, height: 1,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()]))),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _HeroFlowChip(label: 'Lent', amount: data.toCollect,
              tint: card.lentBg, ink: card.greenText, muted: card.muted,
              icon: Icons.arrow_drop_up_rounded)),
            const SizedBox(width: 10),
            Expanded(child: _HeroFlowChip(label: 'Borrowed', amount: data.toPay,
              tint: card.borrowedBg, ink: card.redText, muted: card.muted,
              icon: Icons.arrow_drop_down_rounded)),
          ]),
          const SizedBox(height: 20),
          _Forecast(data: data),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: card.debtBg,
              borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total debt', style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: card.text, fontSize: 14,
                      fontWeight: FontWeight.w700)),
                  Text('EMIs + borrowed', style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: card.muted, fontSize: 12)),
                ],
              )),
              const SizedBox(width: 8),
              FittedBox(fit: BoxFit.scaleDown,
                child: _SignedAmount(-data.totalDebt, color: card.redText,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 20, fontWeight: FontWeight.w800))),
            ]),
          ),
        ],
      ),
      ),
    );
  }
}

class _HeroFlowChip extends StatelessWidget {
  const _HeroFlowChip({required this.label, required this.amount,
    required this.tint, required this.ink, required this.muted,
    required this.icon});
  final String label;
  final int amount;
  final Color tint, ink, muted;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(18)),
    child: Row(children: [
      CircleAvatar(radius: 14, backgroundColor: ink.withValues(alpha: .12),
        child: Icon(icon, size: 22, color: ink)),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: muted, fontSize: 12)),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
            child: AmountText(amount,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: ink, fontSize: 16, fontWeight: FontWeight.w800))),
        ])),
    ]),
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
  int? _selectedWeek;
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
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = AppTheme.netCardOf(context);
    final weeks = widget.data.weeks;
    final heavy = widget.data.heaviestDueDay;
    final maxValue = weeks.fold<int>(0, (max, week) =>
      math.max(max, math.max(week.incoming, week.outgoing)));
    int? heaviestIndex;
    for (var i = 0; i < weeks.length; i++) {
      if (weeks[i].outgoing > 0 &&
          (heaviestIndex == null ||
              weeks[i].outgoing > weeks[heaviestIndex].outgoing)) {
        heaviestIndex = i;
      }
    }
    final selected = _selectedWeek ?? heaviestIndex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Next 5 weeks', style:
              Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: card.text, fontSize: 14, fontWeight: FontWeight.w700))),
            Text('Tap a week', style:
              Theme.of(context).textTheme.bodySmall?.copyWith(
                color: card.muted, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 8),
        RepaintBoundary(child: AnimatedBuilder(
          animation: _grow,
          builder: (context, _) => Row(children: [
            for (var i = 0; i < weeks.length; i++)
              Expanded(child: Semantics(
                button: true,
                label: '${formatWeekRange(weeks[i].start, today: widget.data.today)}, '
                    '${formatMoney(weeks[i].incoming)} in, '
                    '${formatMoney(weeks[i].outgoing)} out',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _selectedWeek = i);
                    _showBreakdown(context, weeks[i].items,
                      formatWeekRange(weeks[i].start, today: widget.data.today),
                      data: widget.data);
                  },
                  child: _ForecastWeekColumn(
                    week: weeks[i], card: card,
                    today: widget.data.today,
                    selected: selected == i,
                    maxValue: maxValue,
                    grow: MediaQuery.disableAnimationsOf(context)
                      ? 1 : _grow.value,
                  ),
                ),
              )),
          ]),
        )),
        const SizedBox(height: 8),
        Row(children: [
          _flowLegend(context, card.greenBar, 'In', card.muted),
          const SizedBox(width: 12),
          _flowLegend(context, card.redBar, 'Out', card.muted),
          const SizedBox(width: 8),
          if (heavy != null)
            Expanded(child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Heaviest ${formatShortDate(heavy.date, today: widget.data.today)} · ',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: card.muted, fontSize: 12)),
                _SignedAmount(-widget.data.heaviestDueDayAmount,
                  color: card.redText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            )),
        ]),
      ],
    );
  }
}

class _ForecastWeekColumn extends StatelessWidget {
  const _ForecastWeekColumn({required this.week, required this.card,
    required this.today, required this.selected, required this.maxValue,
    required this.grow});
  final HomeWeek week;
  final NetCardPalette card;
  final DateTime today;
  final bool selected;
  final int maxValue;
  final double grow;

  @override
  Widget build(BuildContext context) {
    double height(int value) => value == 0 || maxValue == 0
      ? 0 : math.max(6, 60 * value / maxValue) * grow;
    final inHeight = height(week.incoming);
    final outHeight = height(week.outgoing);
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 12, fontWeight: selected ? FontWeight.w800 : FontWeight.w700);
    return Container(
      decoration: BoxDecoration(
        color: selected ? card.selectedBg : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        SizedBox(height: 168, child: Stack(children: [
          if (inHeight > 0) ...[
            Positioned(left: 0, right: 0, bottom: 84 + inHeight + 4,
              height: 16, child: FittedBox(fit: BoxFit.scaleDown,
                child: _SignedAmount(week.incoming, compact: true,
                  color: card.greenText, style: labelStyle))),
            Positioned(left: 0, right: 0, bottom: 84, child: Center(
              child: Container(width: 26, height: inHeight,
                decoration: BoxDecoration(color: card.greenBar,
                  borderRadius: BorderRadius.circular(8))))),
          ],
          if (outHeight > 0) ...[
            Positioned(left: 0, right: 0, top: 84, child: Center(
              child: Container(width: 26, height: outHeight,
                decoration: BoxDecoration(
                  color: selected ? card.redBar : card.mutedRedBar,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: selected ? [BoxShadow(
                    color: card.redBar.withValues(alpha: .22),
                    blurRadius: 12)] : null,
                )))),
            Positioned(left: 0, right: 0, top: 84 + outHeight + 4,
              height: 16, child: FittedBox(fit: BoxFit.scaleDown,
                child: _SignedAmount(-week.outgoing, compact: true,
                  color: card.redText, style: labelStyle))),
          ],
          if (week.incoming == 0 && week.outgoing == 0)
            Positioned(left: 0, right: 0, top: 81, child: Center(
              child: CircleAvatar(radius: 3, backgroundColor: card.muted))),
        ])),
        Text(formatShortDate(week.start, today: today),
          textAlign: TextAlign.center, maxLines: 2,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? card.text : card.muted)),
      ]),
    );
  }
}

Widget _flowLegend(BuildContext context, Color color, String label,
    Color muted) =>
    Row(mainAxisSize: MainAxisSize.min, children: [
      CircleAvatar(radius: 3, backgroundColor: color),
      const SizedBox(width: 5),
      Text(label, style: _label(context)?.copyWith(
        color: muted, fontSize: 12)),
    ]);

class _Next30 extends StatelessWidget {
  const _Next30({required this.data});
  final HomeOverview data;

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.homePaletteOf(context);
    final items = data.nextFiveWeeks
        .where((due) => due.date.isBefore(data.today.add(const Duration(days: 30))))
        .toList();
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
          items.where((item) => item.type == part.$2)
              .fold<int>(0, (sum, item) => sum + item.amount),
        ),
    ]..sort((a, b) => b.$3.compareTo(a.$3));
    final total = breakdown.fold<int>(0, (sum, part) => sum + part.$3);
    final paid = data.emis.fold<int>(0, (sum, item) => sum + item.paidPaise);
    final left = data.emis.fold<int>(0, (sum, item) => sum + item.remainingBalancePaise);
    final paidCount = data.emis.fold<int>(0, (sum, item) => sum + item.paidInstallments);
    final installmentCount = data.emis.fold<int>(0, (sum, item) => sum + item.emi.tenureMonths);
    final ringPaid = paid + left > 0 ? paid : paidCount;
    final ringLeft = paid + left > 0 ? left : installmentCount - paidCount;
    final progress = ringPaid + ringLeft > 0
        ? ringPaid / (ringPaid + ringLeft) : 0.0;
    final endings = data.emis.toList()
      ..sort((a, b) => a.installments.last.dueDate
          .compareTo(b.installments.last.dueDate));
    final firstEnd = endings.firstOrNull?.installments.last.dueDate;
    final lastEnd = endings.lastOrNull?.installments.last.dueDate;
    final lastNames = lastEnd == null ? ''
        : endings.where((item) => item.installments.last.dueDate == lastEnd)
            .map((item) => displayName(item.emi.name)).join(' & ');
    final months = lastEnd == null ? 0 : math.max(0,
        (lastEnd.year - data.today.year) * 12 + lastEnd.month - data.today.month);
    return _Card(
      onTap: items.isEmpty ? null : () =>
          _showBreakdown(context, items, 'Obligations · next 30 days', data: data),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (total > 0) ...[
          Row(children: [
            Expanded(child: Text('Next 30 days · to pay', style: _title(context))),
            _SignedAmount(-total,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 10,
              child: total == 0
                  ? ColoredBox(color: palette.surfaceAlt)
                  : Row(children: [
                      for (final part in breakdown.where((part) => part.$3 > 0)) ...[
                        if (part != breakdown.where((part) => part.$3 > 0).first)
                          const SizedBox(width: 2),
                        Expanded(flex: part.$3, child: ColoredBox(color: part.$2)),
                      ],
                    ]),
            ),
          ),
          const SizedBox(height: 12),
          for (final part in breakdown.where((part) => part.$3 > 0))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                CircleAvatar(radius: 4, backgroundColor: part.$2),
                const SizedBox(width: 8),
                Expanded(child: Text(part.$1, style: _label(context)?.copyWith(
                  color: palette.text2, fontSize: 13))),
                _SignedAmount(-part.$3, style: _label(context)?.copyWith(
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 8),
                SizedBox(width: 34, child: Text(
                  '${total == 0 ? 0 : (100 * part.$3 / total).round()}%',
                  textAlign: TextAlign.right,
                  style: _label(context)?.copyWith(color: palette.text3))),
              ]),
            ),
          if (endings.isNotEmpty) Divider(height: 24, color: palette.line),
          ],
          if (endings.isNotEmpty) ...[
          Text('Debt-free', style: _title(context)),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox.square(
              dimension: 72,
              child: _DebtProgressRing(
                paid: ringPaid,
                left: ringLeft,
                percentage: (progress * 100).round(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: endings.isEmpty
                ? Text('No active EMIs', style: _label(context))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$months ${months == 1 ? 'month' : 'months'} to go · ${formatMonthYear(lastEnd!)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.text, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Next to finish: ${displayName(endings.first.emi.name)} · ${formatShortDate(firstEnd!, today: data.today)}',
                        style: _label(context)?.copyWith(color: palette.text2)),
                      const SizedBox(height: 4),
                      Text('Last: $lastNames · ${formatMonthYear(lastEnd)}',
                        style: _label(context)?.copyWith(color: palette.text2)),
                    ],
                  )),
          ]),
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
        child: Center(child: Text('${widget.percentage}% paid',
          style: _label(context)?.copyWith(
            color: palette.text, fontWeight: FontWeight.w700))),
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
        canvas.drawArc(rect, start, sweep * grow, false, paint..color = colors[i]);
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
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.toCollect > 0) Expanded(child: _ToCollect(data: data)),
        if (data.toCollect > 0 && data.emis.isNotEmpty)
          const SizedBox(width: 12),
        if (data.emis.isNotEmpty) Expanded(child: _NextPay(data: data)),
      ],
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
    var later = 0;
    final windowEnd = data.today.add(const Duration(days: 35));
    for (final detail in data.money) {
      if (detail.record.direction != MoneyDirection.given ||
          detail.summary.remainingAmountPaise <= 0) {
        continue;
      }
      final name = detail.record.personName;
      totals.update(name, (value) => value + detail.summary.remainingAmountPaise,
          ifAbsent: () => detail.summary.remainingAmountPaise);
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
    return _Card(
      onTap: () => _tab(context, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text('To receive', style: _title(context))),
            Icon(Icons.chevron_right, size: 18, color: palette.text2),
          ]),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: _SignedAmount(data.toCollect,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: palette.incoming.text, fontSize: 26,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
          ),
          const SizedBox(height: 10),
          for (final name in people.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: palette.surfaceAlt,
                  child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: palette.text2)),
                ),
                const SizedBox(width: 5),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName(name), maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _label(context)?.copyWith(color: palette.text)),
                    Text(dates[name] == null
                        ? 'No due date'
                        : formatDayDistance(dates[name]!, data.today, alwaysDays: true),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: _label(context)?.copyWith(color: palette.text2)),
                  ],
                )),
                const SizedBox(width: 3),
                FittedBox(fit: BoxFit.scaleDown,
                  child: _SignedAmount(totals[name]!,
                    style: _label(context)?.copyWith(
                      color: palette.text, fontWeight: FontWeight.w700))),
              ]),
            ),
          if (people.isEmpty)
            Text('Nothing to receive', style: _label(context)),
          const Spacer(),
          if (later > 0) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              _SignedAmount(later, style: _label(context)),
              Text(' later', style: _label(context)),
            ]),
          ),
        ],
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
    final dayText = date == null ? 'No EMI due'
        : formatDayDistance(date, data.today, alwaysDays: true);
    return _Card(
      onTap: () => _tab(context, 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text('Next EMI', style: _title(context))),
            Icon(Icons.chevron_right, size: 18, color: palette.text2),
          ]),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
            child: Text(dayText, style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontSize: 28, fontWeight: FontWeight.w800,
                    color: palette.text)),
          ),
          if (date != null) ...[
            const SizedBox(height: 4),
            Text(formatWeekdayShortDate(date, today: data.today),
              style: _label(context)?.copyWith(fontSize: 13, color: palette.text2)),
            const SizedBox(height: 6),
            Wrap(spacing: 3, children: [
              Text('${sameDay.length} ${sameDay.length == 1 ? 'payment' : 'payments'} ·',
                style: _label(context)),
              _SignedAmount(-total, style: _label(context)?.copyWith(
                fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text('${displayName(sameDay.first.name)}${sameDay.length > 1 ? ' +${sameDay.length - 1} more' : ''}',
              maxLines: 2, style: _label(context)?.copyWith(color: palette.text2)),
          ],
          const Spacer(),
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: palette.emiTone.tint,
                borderRadius: BorderRadius.circular(6)),
            child: Text('EMI', style: _label(context)?.copyWith(
                color: palette.emiTone.text, fontWeight: FontWeight.w700)),
          ),
        ],
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
    final week = data.dues.where((due) =>
        !due.date.isBefore(data.today) &&
        due.date.isBefore(data.today.add(const Duration(days: 7)))).toList();
    final selected = _selected ?? data.today;
    final onDay = week.where((due) => due.date == selected).toList();
    final dayNet = onDay.fold<int>(0,
      (sum, due) => sum + (due.incoming ? due.amount : -due.amount));
    final next = data.dues.where((due) => due.date.isAfter(selected)).firstOrNull;
    String subtitleFor(HomeDue due) {
      if (due.type == 'money') {
        final record = data.money.where((item) => item.record.id == due.id).firstOrNull;
        final status = (record?.summary.repaidAmountPaise ?? 0) > 0
            ? 'Partly paid' : 'Unpaid';
        return '${due.incoming ? 'Money given' : 'Money borrowed'} · $status';
      }
      return due.type == 'emi' ? 'EMI · Due' : 'Bill · Renewal';
    }
    final subscription = data.dues.where((due) =>
        due.type == 'subscription' && !due.date.isBefore(data.today)).firstOrNull;
    final endings = data.emis.toList()
      ..sort((a, b) => a.installments.last.dueDate
          .compareTo(b.installments.last.dueDate));
    final insights = <Widget>[
      if (subscription != null)
        _InsightLine(
          icon: Icons.autorenew_outlined,
          tint: palette.bills.tint,
          ink: palette.bills.text,
          text: '${displayName(subscription.name)} renews ${formatDayDistance(subscription.date, data.today, alwaysDays: true)} · ',
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
          text: '${displayName(endings.first.emi.name)} ends ${formatDayDistance(endings.first.installments.last.dueDate, data.today, alwaysDays: true)} · frees ',
          amount: endings.first.scheduledInstallmentPaise,
          suffix: ' a month',
          incoming: true,
          onTap: () => _tab(context, 1),
        ),
    ];
    return _Card(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text('This week', style: _title(context))),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: palette.text,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const UpcomingScreen())),
              child: const Text('See all ›'),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 0; i < 7; i++)
              Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Builder(builder: (context) {
                final day = data.today.add(Duration(days: i));
                final dayItems = week.where((due) => due.date == day).toList();
                final active = selected == day;
                return Tooltip(
                  message: '${formatShortDate(day, today: data.today)}: ${dayItems.length} due',
                  child: InkWell(
                    onTap: () => setState(() => _selected = day),
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: double.infinity, height: 64,
                      decoration: BoxDecoration(
                        color: i == 0 ? palette.text
                            : active ? palette.surfaceAlt : palette.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: active && i != 0
                            ? Border.all(color: palette.line) : null,
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Text(
                        const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day.weekday - 1],
                        style: _label(context)?.copyWith(
                          fontSize: 12,
                          color: i == 0 ? palette.surface : palette.text3)),
                      Text('${day.day}', style: Theme.of(context)
                            .textTheme.bodyMedium?.copyWith(
                              fontSize: 16, fontWeight: FontWeight.w700,
                              color: i == 0 ? palette.surface : palette.text)),
                      const SizedBox(height: 4),
                      SizedBox(height: 8, child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (dayItems.any((due) => due.incoming))
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 1),
                                child: CircleAvatar(radius: 2.5,
                                  backgroundColor: palette.incoming.graphic),
                              ),
                          if (dayItems.any((due) => !due.incoming))
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 1),
                                child: CircleAvatar(radius: 2.5,
                                  backgroundColor: palette.out.graphic),
                              ),
                        ],
                      )),
                    ])),
                  ),
                );
              }))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text(
              '${formatDayDistance(selected, data.today, alwaysDays: true)} · ${formatShortDate(selected, today: data.today)}',
              style: _title(context)?.copyWith(fontSize: 15))),
            if (onDay.isNotEmpty)
              _SignedAmount(dayNet, style: _title(context)?.copyWith(fontSize: 15)),
          ]),
          const SizedBox(height: 4),
          if (onDay.isEmpty) ...[
            Text('Nothing due', style: _label(context)?.copyWith(
              color: palette.text2, fontSize: 13)),
            if (next != null)
              FlowRow(item: next, today: data.today,
                subtitle: subtitleFor(next),
                onTap: () => _openDue(context, next, data)),
          ] else ...[
            for (final item in onDay.take(3))
              FlowRow(item: item, today: data.today,
                subtitle: subtitleFor(item),
                onTap: () => _openDue(context, item, data)),
            if (onDay.length > 3)
              TextButton(
                onPressed: () => _showBreakdown(context, onDay,
                  formatShortDate(selected, today: data.today), data: data),
                child: Text('${onDay.length - 3} more'),
              ),
          ],
          if (insights.isNotEmpty) ...[
            Divider(height: 24, color: palette.line),
            Text('Worth knowing', style: _title(context)?.copyWith(fontSize: 14)),
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
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontSize: 14, color: palette.text);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          CircleAvatar(radius: 16, backgroundColor: tint,
            child: Icon(icon, size: 18, color: ink)),
          const SizedBox(width: 10),
          Expanded(child: Wrap(
            spacing: 3, runSpacing: 2,
            children: [
              Text(text, style: style),
              _SignedAmount(incoming ? amount : -amount, style: style),
              if (suffix.isNotEmpty) Text(suffix, style: style),
            ],
          )),
          Icon(Icons.chevron_right, size: 18, color: palette.text2),
        ]),
      ),
    );
  }
}

class _SignedAmount extends StatelessWidget {
  const _SignedAmount(this.value, {this.style, this.compact = false, this.color});

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
    final amountStyle = (style ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: this.color ?? color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (value != 0 && !privacyAmountsHidden)
        Text(value > 0 ? '+' : '−', style: amountStyle),
      AmountText(value.abs(), compact: compact, style: amountStyle),
    ]);
  }
}

class FlowRow extends StatelessWidget {
  const FlowRow({super.key, required this.item, required this.today,
    required this.onTap, this.subtitle});
  final HomeDue item;
  final DateTime today;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.homePaletteOf(context);
    final tone = switch (item.type) {
      'emi' => palette.emiTone,
      'subscription' => palette.bills,
      _ => palette.owe,
    };
    final icon = switch (item.type) {
      'emi' => Icons.account_balance_outlined,
      'subscription' => Icons.autorenew_outlined,
      _ => Icons.people_outline,
    };
    final category = switch (item.type) {
      'emi' => 'EMI',
      'subscription' => 'Bill',
      _ => 'Money',
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: tone.tint,
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: tone.graphic),
          ),
          const SizedBox(width: 9),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(displayName(item.name), maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 15, color: palette.text, fontWeight: FontWeight.w600)),
              Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(subtitle ?? '$category · ${formatWeekdayShortDate(item.date, today: today)}',
                    style: _label(context)?.copyWith(
                      fontSize: 13, color: palette.text2)),
                  if (item.date.isBefore(today))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: palette.out.tint,
                        borderRadius: BorderRadius.circular(4)),
                      child: Text('Overdue', style: _label(context)?.copyWith(
                        fontSize: 12, color: palette.out.text)),
                    ),
                ]),
            ],
          )),
          const SizedBox(width: 6),
          _SignedAmount(item.incoming ? item.amount : -item.amount,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
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
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewPaddingOf(context).bottom),
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
                Expanded(child: Text('In', style: TextStyle(color: AppTheme.homePaletteOf(context).incoming.text))),
                Align(alignment: Alignment.centerRight, child: _SignedAmount(
                  items
                      .where((e) => e.incoming)
                      .fold(0, (n, e) => n + e.amount),
                )),
              ],
            ),
            Row(
              children: [
                Expanded(child: Text('Out', style: TextStyle(color: AppTheme.homePaletteOf(context).out.text))),
                Align(alignment: Alignment.centerRight, child: _SignedAmount(
                  -items
                      .where((e) => !e.incoming)
                      .fold(0, (n, e) => n + e.amount),
                )),
              ],
            ),
            Row(children: [
              const Expanded(child: Text('Net')),
              Align(alignment: Alignment.centerRight, child: _SignedAmount(items.fold<int>(0, (n, e) => n + (e.incoming ? e.amount : -e.amount)))),
            ]),
          ],
        ),
      ),
    ),
  );
}
