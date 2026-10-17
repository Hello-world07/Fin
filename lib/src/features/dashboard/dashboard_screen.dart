import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../data/repositories.dart';
import '../../domain/enums.dart';
import '../../shared/calculator_sheet.dart';
import '../../shared/finance_display_widgets.dart';
import '../../shared/forms.dart';
import '../../shared/notched_navigation_bar.dart';
import '../../shared/screen_header.dart';
import '../assistant/ask_finkeep_sheet.dart';
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
  bool _dialOpen = false;
  bool _fabVisible = true;
  Timer? _scrollStop;

  @override
  void dispose() {
    _scrollStop?.cancel();
    super.dispose();
  }

  bool _onScroll(ScrollNotification event) {
    if (event is UserScrollNotification) {
      if (event.direction == ScrollDirection.reverse && _fabVisible) {
        setState(() {
          _fabVisible = false;
          _dialOpen = false;
        });
      } else if (event.direction == ScrollDirection.forward && !_fabVisible) {
        setState(() => _fabVisible = true);
      }
    }
    _scrollStop?.cancel();
    _scrollStop = Timer(const Duration(milliseconds: 300), () {
      if (mounted && !_fabVisible) setState(() => _fabVisible = true);
    });
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(homeOverviewProvider);
    final private = ref.watch(privacyModeProvider.select((s) => s.enabled));
    final tokens = AppTheme.colorsOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final sections = <Widget>[
      _Header(
        private: private,
        onAsk: () => openAskFinKeep(context),
        onPrivacy: () => ref
            .read(privacyModeProvider.notifier)
            .setEnabled(
              !ref.read(privacyModeProvider).enabled,
              context: context,
            ),
        onSettings: () => openSettings(context),
      ),
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
      if (overview == null)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (overview.emis.isEmpty &&
          overview.money.isEmpty &&
          overview.subscriptions.isEmpty)
        const _FirstRun()
      else ...[
        _Band(child: _MoneyBalance(data: overview)),
        _Band(child: _PrimaryTiles(data: overview)),
        _Band(child: _SecondaryTiles(data: overview)),
        _Band(child: _ThisWeek(data: overview)),
        _Band(child: _Insights(data: overview)),
      ],
    ];
    return Scaffold(
      backgroundColor: tokens.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: ListView.builder(
                padding: EdgeInsets.only(
                  bottom:
                      NotchedNavigationMetrics.tabContentPadding(context) + 16,
                ),
                itemCount: sections.length,
                itemBuilder: (context, index) => sections[index],
              ),
            ),
          ),
          if (_dialOpen && !keyboard)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _dialOpen = false),
                child: ColoredBox(color: tokens.text.withValues(alpha: 0.38)),
              ),
            ),
          if (!keyboard)
            Positioned(
              right: 16,
              bottom:
                  NotchedNavigationMetrics.fabBottomPadding +
                  MediaQuery.viewPaddingOf(context).bottom +
                  16,
              child: AnimatedSlide(
                offset: _fabVisible ? Offset.zero : const Offset(0, 1.5),
                duration: const Duration(milliseconds: 200),
                child: AnimatedOpacity(
                  opacity: _fabVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_dialOpen) ...[
                        _DialAction(
                          'Calculator',
                          Icons.calculate_outlined,
                          () => _openAdd(_Add.calculator),
                        ),
                        _DialAction(
                          'Add Subscription',
                          Icons.autorenew,
                          () => _openAdd(_Add.subscription),
                        ),
                        _DialAction(
                          'Add Money',
                          Icons.swap_horiz,
                          () => _openAdd(_Add.money),
                        ),
                        _DialAction(
                          'Add EMI',
                          Icons.account_balance_outlined,
                          () => _openAdd(_Add.emi),
                        ),
                        const SizedBox(height: 8),
                      ],
                      FloatingActionButton(
                        heroTag: 'home_add',
                        onPressed: () => setState(() => _dialOpen = !_dialOpen),
                        tooltip: _dialOpen ? 'Close add menu' : 'Add',
                        child: Icon(_dialOpen ? Icons.close : Icons.add),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top,
            child: ColoredBox(color: tokens.background),
          ),
        ],
      ),
    );
  }

  void _openAdd(_Add action) {
    setState(() => _dialOpen = false);
    switch (action) {
      case _Add.emi:
        openFinanceSheet(context, const EmiFormSheet());
      case _Add.money:
        openFinanceSheet(context, const MoneyFormSheet());
      case _Add.subscription:
        openFinanceSheet(context, const SubscriptionFormSheet());
      case _Add.calculator:
        openCalculator(
          context,
          onDestination: (destination, amount) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              switch (destination) {
                case CalculatorDestination.emi:
                  openFinanceSheet(
                    context,
                    EmiFormSheet(initialEmiAmount: amount),
                  );
                case CalculatorDestination.moneyGiven:
                  openFinanceSheet(
                    context,
                    MoneyFormSheet(
                      initialAmount: amount,
                      initialDirection: MoneyDirection.given,
                    ),
                  );
                case CalculatorDestination.moneyBorrowed:
                  openFinanceSheet(
                    context,
                    MoneyFormSheet(
                      initialAmount: amount,
                      initialDirection: MoneyDirection.borrowed,
                    ),
                  );
                case CalculatorDestination.subscription:
                  openFinanceSheet(
                    context,
                    SubscriptionFormSheet(initialAmount: amount),
                  );
              }
            });
          },
          onEmiDraft: (draft) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              openFinanceSheet(
                context,
                EmiFormSheet(
                  initialEmiAmount: draft.monthlyEmi.toStringAsFixed(2),
                  initialPrincipal: draft.principal.toStringAsFixed(2),
                  initialInterestRate: draft.annualRate.toString(),
                  initialTenureMonths: draft.months,
                ),
              );
            });
          },
        );
    }
  }
}

enum _Add { emi, money, subscription, calculator }

class _DialAction extends StatelessWidget {
  const _DialAction(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.private,
    required this.onAsk,
    required this.onPrivacy,
    required this.onSettings,
  });
  final bool private;
  final VoidCallback onAsk, onPrivacy, onSettings;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final colors = AppTheme.colorsOf(context);
    return ScreenHeader(
      horizontalPadding: 16,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FinKeep',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: colors.text,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '$greeting · ${formatDate(now)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.secondaryText),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: private ? 'Show amounts' : 'Hide amounts',
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          onPressed: onPrivacy,
          icon: Icon(
            private ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          ),
        ),
        IconButton(
          tooltip: 'Settings',
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          onPressed: onSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
      bottom: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onAsk,
          borderRadius: BorderRadius.circular(16),
          child: const SizedBox(
            height: 56,
            child: Row(
              children: [
                SizedBox(width: 16),
                Icon(Icons.auto_awesome_outlined),
                SizedBox(width: 12),
                Expanded(child: Text("Ask: what's due this week?")),
              ],
            ),
          ),
        ),
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

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: AppTheme.colorsOf(context).surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(
        color: Theme.of(context).brightness == Brightness.light
            ? AppTheme.homeCardOutline
            : AppTheme.colorsOf(context).outline,
      ),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
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
TextStyle? _big(BuildContext context, {Color? color}) =>
    Theme.of(context).textTheme.headlineMedium?.copyWith(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      color: color ?? AppTheme.colorsOf(context).text,
    );

class _FirstRun extends StatelessWidget {
  const _FirstRun();
  @override
  Widget build(BuildContext context) => _Band(
    child: _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Start your money picture', style: _title(context)),
          const SizedBox(height: 8),
          const Text('Your records stay on this phone.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => openFinanceSheet(context, const EmiFormSheet()),
            child: const Text('Add your first EMI'),
          ),
          FilledButton(
            onPressed: () => openFinanceSheet(context, const MoneyFormSheet()),
            child: const Text('Add your first Money record'),
          ),
          FilledButton(
            onPressed: () =>
                openFinanceSheet(context, const SubscriptionFormSheet()),
            child: const Text('Add your first Subscription'),
          ),
        ],
      ),
    ),
  );
}

class _MoneyBalance extends StatelessWidget {
  const _MoneyBalance({required this.data});
  final HomeOverview data;
  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final forecastEnd = data.today.add(const Duration(days: 35));
    final beyond = data.money
        .where(
          (detail) =>
              detail.record.direction == MoneyDirection.given &&
              detail.summary.remainingAmountPaise > 0 &&
              detail.record.dueDate != null &&
              !detail.record.dueDate!.isBefore(forecastEnd),
        )
        .fold<int>(
          0,
          (total, detail) => total + detail.summary.remainingAmountPaise,
        );
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text('Money balance', style: _title(context)),
                        ),
                        const SizedBox(width: 4),
                        const Tooltip(
                          message:
                              'Money owed to you minus money you owe. EMIs are in total debt.',
                          child: Icon(Icons.info_outline, size: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AmountText(data.balance, style: _big(context)),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 3,
                      runSpacing: 2,
                      children: [
                        Text('Lent', style: _label(context)),
                        AmountText(data.toCollect, style: _label(context)),
                        Text('− Borrowed', style: _label(context)),
                        AmountText(data.toPay, style: _label(context)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Total debt',
                      style: _label(context)?.copyWith(color: colors.pay),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: AmountText(
                        data.totalDebt,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: colors.pay,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    Text('incl. EMIs', style: _label(context)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Forecast(weeks: data.weeks),
          if (beyond > 0) ...[
            const SizedBox(height: 7),
            Wrap(
              spacing: 3,
              children: [
                Text('Beyond 5 weeks:', style: _label(context)),
                AmountText(beyond, style: _label(context)),
                Text('to collect', style: _label(context)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Forecast extends StatefulWidget {
  const _Forecast({required this.weeks});
  final List<HomeWeek> weeks;
  @override
  State<_Forecast> createState() => _ForecastState();
}

class _ForecastState extends State<_Forecast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  )..forward();
  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final maxOut = widget.weeks.map((w) => w.outgoing).fold(0, math.max);
    final maxIn = widget.weeks.map((w) => w.incoming).fold(0, math.max);
    final heavy = widget.weeks
        .where((w) => w.outgoing == maxOut && maxOut > 0)
        .firstOrNull;
    final biggestIn = widget.weeks.indexWhere(
      (w) => w.incoming == maxIn && maxIn > 0,
    );
    final biggestOut = widget.weeks.indexWhere(
      (w) => w.outgoing == maxOut && maxOut > 0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: 'Records without due dates are not shown.',
          child: Text('Next 5 weeks', style: _label(context)),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 96,
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _grow,
                  builder: (context, _) => RepaintBoundary(
                    child: CustomPaint(
                      painter: _ForecastPainter(
                        widget.weeks,
                        colors.receive,
                        colors.pay,
                        colors.outline,
                        MediaQuery.disableAnimationsOf(context)
                            ? 1
                            : _grow.value,
                        heavy?.start,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Row(
                  children: [
                    for (var i = 0; i < widget.weeks.length; i++)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showBreakdown(
                            context,
                            widget.weeks[i].items,
                            'Week of ${formatDate(widget.weeks[i].start)}',
                          ),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 18,
                                child: i == biggestIn
                                    ? FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: AmountText(
                                          widget.weeks[i].incoming,
                                          compact: true,
                                          style: _label(
                                            context,
                                          )?.copyWith(color: colors.receive),
                                        ),
                                      )
                                    : null,
                              ),
                              const Spacer(),
                              SizedBox(
                                height: 18,
                                child: i == biggestOut
                                    ? FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: AmountText(
                                          widget.weeks[i].outgoing,
                                          compact: true,
                                          style: _label(
                                            context,
                                          )?.copyWith(color: colors.pay),
                                        ),
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            for (final week in widget.weeks)
              Expanded(
                child: Text(
                  '${week.start.day}-${week.start.add(const Duration(days: 6)).day} ${_shortMonth(week.start)}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: _label(context)?.copyWith(fontSize: 11),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Green: money in − Red: money out',
          style: _label(context)?.copyWith(fontSize: 11),
        ),
        if (heavy != null) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 3,
            children: [
              Text(
                'Heaviest: ${heavy.start.day} ${_shortMonth(heavy.start)} −',
                style: _label(context)?.copyWith(fontWeight: FontWeight.w700),
              ),
              AmountText(
                heavy.outgoing,
                style: _label(
                  context,
                )?.copyWith(color: colors.pay, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ForecastPainter extends CustomPainter {
  const _ForecastPainter(
    this.weeks,
    this.receive,
    this.pay,
    this.track,
    this.grow,
    this.heavy,
  );
  final List<HomeWeek> weeks;
  final Color receive, pay, track;
  final double grow;
  final DateTime? heavy;
  @override
  void paint(Canvas canvas, Size size) {
    final axis = size.height / 2;
    canvas.drawLine(
      Offset(0, axis),
      Offset(size.width, axis),
      Paint()
        ..color = track
        ..strokeWidth = 1,
    );
    final maxValue = weeks.fold<int>(
      0,
      (n, w) => math.max(n, math.max(w.incoming, w.outgoing)),
    );
    final width = size.width / weeks.length;
    for (var i = 0; i < weeks.length; i++) {
      final x = (i + .5) * width;
      final w = weeks[i];
      if (w.incoming == 0 && w.outgoing == 0) {
        canvas.drawCircle(Offset(x, axis), 2, Paint()..color = track);
        continue;
      }
      final barWidth = w.start == heavy ? 9.0 : 7.0;
      final top = maxValue == 0 || w.incoming == 0
          ? 0.0
          : math.max(6.0, 30 * w.incoming / maxValue) * grow;
      final bottom = maxValue == 0 || w.outgoing == 0
          ? 0.0
          : math.max(6.0, 30 * w.outgoing / maxValue) * grow;
      if (top > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - barWidth / 2, axis - top, barWidth, top),
            const Radius.circular(3),
          ),
          Paint()..color = receive,
        );
      }
      if (bottom > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - barWidth / 2, axis, barWidth, bottom),
            const Radius.circular(3),
          ),
          Paint()..color = pay,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ForecastPainter old) =>
      old.weeks != weeks ||
      old.grow != grow ||
      old.receive != receive ||
      old.pay != pay ||
      old.track != track ||
      old.heavy != heavy;
}

class _PrimaryTiles extends StatelessWidget {
  const _PrimaryTiles({required this.data});
  final HomeOverview data;
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.emis.isNotEmpty) ...[
          Expanded(child: _DebtFree(data: data)),
          const SizedBox(width: 12),
        ],
        Expanded(child: _Next30(data: data)),
      ],
    ),
  );
}

class _DebtFree extends StatelessWidget {
  const _DebtFree({required this.data});
  final HomeOverview data;
  @override
  Widget build(BuildContext context) {
    final end = data.debtFreeDate;
    final months = end == null
        ? 0
        : math.max(
            0,
            (end.year - data.today.year) * 12 + end.month - data.today.month,
          );
    final ending = data.emis.toList()
      ..sort(
        (a, b) =>
            a.installments.last.dueDate.compareTo(b.installments.last.dueDate),
      );
    final first = ending.first;
    final firstEnd = first.installments.last.dueDate;
    final last = ending.last;
    final lastEnd = last.installments.last.dueDate;
    return _Card(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Debt-free', style: _title(context)),
          ),
          const SizedBox(height: 8),
          _HomeDebtRing(items: data.emis, months: months),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _tab(context, 1),
            child: Column(
              children: [
                Text(
                  'Last EMI: ${_displayHomeName(last.emi.name)} − ${_shortMonth(lastEnd)} ${lastEnd.year}',
                  textAlign: TextAlign.center,
                  style: _label(context),
                ),
                const SizedBox(height: 4),
                Text(
                  'Next to end: ${_displayHomeName(first.emi.name)} − ${_shortMonth(firstEnd)}',
                  textAlign: TextAlign.center,
                  style: _label(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeDebtRing extends StatefulWidget {
  const _HomeDebtRing({required this.items, required this.months});
  final List<EmiDetail> items;
  final int months;
  @override
  State<_HomeDebtRing> createState() => _HomeDebtRingState();
}

class _HomeDebtRingState extends State<_HomeDebtRing>
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
    final base = HSLColor.fromColor(AppTheme.colorsOf(context).emi);
    final colors = [
      for (var i = 0; i < widget.items.length; i++)
        base
            .withHue((base.hue - 12 + (i % 6) * 5).clamp(0.0, 360.0))
            .withLightness((.38 + (i % 3) * .08).clamp(0.0, 1.0))
            .toColor(),
    ];
    final values = [
      for (final item in widget.items) item.remainingBalancePaise,
    ];
    return Column(
      children: [
        GestureDetector(
          onTapDown: (details) {
            final delta = details.localPosition - const Offset(48, 48);
            if (delta.distance < 32 || delta.distance > 48) return;
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
            message: 'Tap an arc to see the EMI and remaining amount',
            child: SizedBox.square(
              dimension: 96,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _grow,
                      builder: (context, _) => CustomPaint(
                        size: const Size.square(96),
                        painter: _HomeDebtPainter(
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
                        'to debt-free',
                        style: _label(context)?.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_selected != null && _selected! < widget.items.length)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 3,
              children: [
                Text(
                  _displayHomeName(widget.items[_selected!].emi.name),
                  style: _label(context),
                ),
                AmountText(
                  widget.items[_selected!].remainingBalancePaise,
                  style: _label(context)?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HomeDebtPainter extends CustomPainter {
  const _HomeDebtPainter(
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
    final radius = rect.width / 2;
    final gap = 2 / radius;
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
  bool shouldRepaint(covariant _HomeDebtPainter old) =>
      old.grow != grow ||
      old.track != track ||
      old.gapColor != gapColor ||
      old.values.toString() != values.toString() ||
      old.colors.toString() != colors.toString();
}

class _Next30 extends StatelessWidget {
  const _Next30({required this.data});
  final HomeOverview data;
  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final items = data.next30;
    final parts = [
      ('EMI', 'emi', colors.emi),
      ('Subs', 'subscription', colors.subscriptions),
      ('Money', 'money', colors.pay),
    ];
    final values = [
      for (final part in parts)
        items
            .where((e) => e.type == part.$2)
            .fold<int>(0, (n, e) => n + e.amount),
    ];
    final total = values.fold<int>(0, (n, e) => n + e);
    return _Card(
      onTap: items.isEmpty
          ? null
          : () => _showBreakdown(context, items, 'Next 30 days'),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Next 30 days', style: _title(context)),
          ),
          const Spacer(),
          SizedBox.square(
            dimension: 96,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _DonutPainter(values, [
                  for (final p in parts) p.$3,
                ], colors.outline),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AmountText(
                      total,
                      compact: true,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 3,
            children: [
              for (var i = 0; i < parts.length; i++)
                if (values[i] > 0)
                  Tooltip(
                    message:
                        '${parts[i].$1}: ${total == 0 ? 0 : (values[i] * 100 / total).round()}%',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(radius: 3, backgroundColor: parts[i].$3),
                        const SizedBox(width: 3),
                        Text(
                          '${parts[i].$1} ${total == 0 ? 0 : (values[i] * 100 / total).round()}%',
                          style: _label(context),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.values, this.colors, this.track);
  final List<int> values;
  final List<Color> colors;
  final Color track;
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
        canvas.drawArc(rect, start, sweep, false, paint..color = colors[i]);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.track != track ||
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
        Expanded(child: _ToCollect(data: data)),
        const SizedBox(width: 12),
        Expanded(child: _NextPay(data: data)),
      ],
    ),
  );
}

class _ToCollect extends StatelessWidget {
  const _ToCollect({required this.data});
  final HomeOverview data;
  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final totals = <String, int>{};
    final dates = <String, DateTime>{};
    for (final detail in data.money) {
      if (detail.record.direction == MoneyDirection.given &&
          detail.summary.remainingAmountPaise > 0) {
        final name = detail.record.personName;
        totals.update(
          name,
          (n) => n + detail.summary.remainingAmountPaise,
          ifAbsent: () => detail.summary.remainingAmountPaise,
        );
        final due = detail.record.dueDate;
        if (due != null &&
            (dates[name] == null || due.isBefore(dates[name]!))) {
          dates[name] = due;
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
          Text('To collect', style: _title(context)),
          if (people.isEmpty) ...[
            const SizedBox(height: 12),
            Icon(Icons.person_outline, color: colors.secondaryText),
            Text('Nothing to collect', style: _label(context)),
          ] else ...[
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AmountText(
                data.toCollect,
                style: _big(context, color: colors.receive),
              ),
            ),
            const SizedBox(height: 6),
            for (final name in people.take(2))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.selectedFill,
                        border: Border.all(color: colors.surface, width: 2),
                      ),
                      child: Text(
                        name.isEmpty ? '?' : name[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayHomeName(name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _label(context),
                          ),
                          Wrap(
                            spacing: 3,
                            children: [
                              AmountText(totals[name]!, style: _label(context)),
                              Text(
                                dates[name] == null
                                    ? 'No date'
                                    : _collectDueLabel(
                                        dates[name]!,
                                        data.today,
                                      ),
                                style: _label(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
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
    final next = data.nextToPay;
    final colors = AppTheme.colorsOf(context);
    final days = next?.date.difference(data.today).inDays ?? 0;
    final sameDay = next == null
        ? <HomeDue>[]
        : data.dues
              .where((item) => !item.incoming && item.date == next.date)
              .toList();
    final combined = sameDay.fold<int>(0, (total, item) => total + item.amount);
    return _Card(
      onTap: next == null
          ? null
          : () => sameDay.length == 1
                ? _openDue(context, next, data)
                : _showBreakdown(
                    context,
                    sameDay,
                    formatDate(next.date),
                    data: data,
                  ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Next to pay', style: _title(context)),
          const Spacer(),
          if (next == null) ...[
            Icon(Icons.event_available_outlined, color: colors.secondaryText),
            Text('Nothing coming up', style: _label(context)),
          ] else ...[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                days < 0
                    ? '${-days} days overdue'
                    : days == 0
                    ? 'Today'
                    : '$days ${days == 1 ? 'day' : 'days'}',
                style: _big(
                  context,
                  color: days < 0
                      ? colors.pay
                      : days <= 7
                      ? colors.emi
                      : colors.text,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              sameDay.length == 1
                  ? _displayHomeName(next.name)
                  : '${sameDay.length} payments',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (sameDay.length > 1)
              Text(
                sameDay.map((item) => _displayHomeName(item.name)).join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _label(context),
              ),
            AmountText(combined, style: _label(context)),
          ],
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
    final week = data.dues
        .where(
          (e) =>
              !e.date.isBefore(data.today) &&
              e.date.isBefore(data.today.add(const Duration(days: 7))),
        )
        .toList();
    final selected = _selected ?? (week.isEmpty ? data.today : week.first.date);
    final onDay = week.where((e) => e.date == selected).take(3).toList();
    final colors = AppTheme.colorsOf(context);
    final next = data.dues
        .where((e) => !e.date.isBefore(data.today.add(const Duration(days: 7))))
        .firstOrNull;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('This week', style: _title(context))),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const UpcomingScreen(),
                  ),
                ),
                child: const Text('See all'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                Builder(
                  builder: (context) {
                    final day = data.today.add(Duration(days: i));
                    final items = week.where((e) => e.date == day).toList();
                    final active = selected == day;
                    return Expanded(
                      child: Tooltip(
                        message: '${formatDate(day)}: ${items.length} due',
                        child: InkWell(
                          onTap: () => setState(() => _selected = day),
                          child: Column(
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
                                style: _label(context),
                              ),
                              const SizedBox(height: 3),
                              Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i == 0
                                      ? Theme.of(context).colorScheme.primary
                                      : active
                                      ? colors.selectedFill
                                      : colors.surface,
                                ),
                                child: Text(
                                  '${day.day}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: i == 0
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.onPrimary
                                            : colors.text,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (final type in {
                                    'emi',
                                    'money',
                                    'subscription',
                                  })
                                    if (items.any((e) => e.type == type))
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 1,
                                        ),
                                        child: CircleAvatar(
                                          radius: 2.5,
                                          backgroundColor: _typeColor(
                                            context,
                                            type,
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
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            children: [
              for (final type in ['emi', 'money', 'subscription'])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 3,
                      backgroundColor: _typeColor(context, type),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      type == 'subscription'
                          ? 'Subs'
                          : type == 'emi'
                          ? 'EMI'
                          : 'Money',
                      style: _label(context),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (week.isEmpty)
            Text(
              next == null
                  ? 'All clear this week 🎉'
                  : 'All clear this week 🎉 Next: ${_displayHomeName(next.name)} in ${next.date.difference(data.today).inDays} days',
              style: _label(context),
            )
          else if (onDay.isEmpty)
            Text('Nothing due on this day', style: _label(context))
          else
            for (final item in onDay)
              _DueRow(
                item: item,
                today: data.today,
                onTap: () => _openDue(context, item, data),
              ),
        ],
      ),
    );
  }
}

class _DueRow extends StatelessWidget {
  const _DueRow({required this.item, required this.today, required this.onTap});
  final HomeDue item;
  final DateTime today;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          CircleAvatar(
            radius: 4,
            backgroundColor: _typeColor(context, item.type),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _displayHomeName(item.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AmountText(item.amount, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 6),
          Text(
            'in ${item.date.difference(today).inDays}d',
            style: _label(context),
          ),
        ],
      ),
    ),
  );
}

class _Insights extends StatelessWidget {
  const _Insights({required this.data});
  final HomeOverview data;
  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final sub = data.dues.where((e) => e.type == 'subscription').firstOrNull;
    if (sub != null) {
      rows.add(
        _InsightRow(
          '🔔',
          '${_displayHomeName(sub.name)} renews in ${sub.date.difference(data.today).inDays} days',
          () => _openDue(context, sub, data),
        ),
      );
    }
    final emi = data.emis.toList()
      ..sort(
        (a, b) =>
            a.installments.last.dueDate.compareTo(b.installments.last.dueDate),
      );
    if (emi.isNotEmpty) {
      final first = emi.first;
      final end = first.installments.last.dueDate;
      rows.add(
        _InsightAmountRow(
          '🎯',
          '${_displayHomeName(first.emi.name)} ends in ${end.difference(data.today).inDays} days:',
          first.scheduledInstallmentPaise,
          () => _tab(context, 1),
        ),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Insights', style: _title(context)),
          const SizedBox(height: 6),
          for (final row in rows.take(2)) row,
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow(this.emoji, this.label, this.onTap);
  final String emoji, label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(emoji),
          const SizedBox(width: 8),
          Expanded(child: Text(label, maxLines: 2, style: _label(context))),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    ),
  );
}

class _InsightAmountRow extends StatelessWidget {
  const _InsightAmountRow(this.emoji, this.label, this.amount, this.onTap);
  final String emoji, label;
  final int amount;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(emoji),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 3,
              children: [
                Text(label, style: _label(context)),
                AmountText(amount, style: _label(context)),
                Text('a month free', style: _label(context)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    ),
  );
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

Color _typeColor(BuildContext context, String type) => switch (type) {
  'emi' => AppTheme.colorsOf(context).emi,
  'money' => AppTheme.colorsOf(context).receive,
  'subscription' => AppTheme.colorsOf(context).subscriptions,
  _ => AppTheme.colorsOf(context).secondaryText,
};

String _shortMonth(DateTime date) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][date.month - 1];

String _displayHomeName(String name) => displayName(name);

String _collectDueLabel(DateTime date, DateTime today) {
  final day = DateTime(date.year, date.month, date.day);
  final days = day.difference(today).inDays;
  if (days < 0) return '${-days}d overdue';
  return days == 0 ? 'today' : '${days}d';
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
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
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
                  return ListTile(
                    onTap: data == null
                        ? null
                        : () {
                            Navigator.of(sheetContext).pop();
                            _openDue(context, item, data);
                          },
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 6,
                      backgroundColor: _typeColor(context, item.type),
                    ),
                    title: Text(_displayHomeName(item.name)),
                    subtitle: Text(formatDate(item.date)),
                    trailing: AmountText(item.amount),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: Text('In')),
                AmountText(
                  items
                      .where((e) => e.incoming)
                      .fold(0, (n, e) => n + e.amount),
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(child: Text('Out')),
                AmountText(
                  items
                      .where((e) => !e.incoming)
                      .fold(0, (n, e) => n + e.amount),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
