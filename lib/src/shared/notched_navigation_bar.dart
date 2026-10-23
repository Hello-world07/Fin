import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_theme.dart';
import '../core/providers.dart';
import '../data/database.dart';
import '../data/repositories.dart';
import '../domain/enums.dart';
import '../features/assistant/ask_finkeep_sheet.dart';
import '../features/emis/emis_screen.dart';
import '../features/emis/emi_entry_flow.dart';
import '../features/emis/emi_overview_screen.dart';
import '../features/money/money_screen.dart';
import '../features/subscriptions/subscriptions_screen.dart';
import 'calculator_sheet.dart';
import 'forms.dart';
import 'timed_snackbar.dart';

class NotchedNavigationMetrics {
  static const height = 64.0;
  static const centerLift = 0.0;
  static const bottomMargin = 12.0;
  static const contentGap = 16.0;
  static const fabHeight = 56.0;
  static const fabGap = 16.0;

  static double contentPadding(BuildContext context, {bool hasFab = false}) =>
      height +
      bottomMargin +
      _safeBottom(context) +
      contentGap +
      (hasFab ? fabHeight + fabGap : 0);

  static double tabContentPadding(BuildContext context) =>
      contentPadding(context, hasFab: true);

  static const fabBottomPadding = height + bottomMargin;

  static double _safeBottom(BuildContext context) {
    final view = View.of(context);
    final windowInset = view.viewPadding.bottom / view.devicePixelRatio;
    return windowInset > MediaQuery.viewPaddingOf(context).bottom
        ? windowInset
        : MediaQuery.viewPaddingOf(context).bottom;
  }
}

enum _MenuAction {
  moneyLent,
  moneyBorrowed,
  emi,
  personalEmi,
  friendEmi,
  subscription,
  calculator,
  markEmiPaid,
  editEmi,
  deleteEmi,
  repayment,
  editMoney,
  deleteMoney,
  pauseSubscription,
  editSubscription,
  deleteSubscription,
}

typedef _MenuItem = ({_MenuAction action, String label, IconData icon});

List<_MenuItem> _menuFor(int tab) => switch (tab) {
  1 => [
    (
      action: _MenuAction.personalEmi,
      label: 'My personal loan or credit card',
      icon: Icons.account_balance_outlined,
    ),
    (
      action: _MenuAction.friendEmi,
      label: 'Money I gave to someone',
      icon: Icons.person_outline_rounded,
    ),
    (
      action: _MenuAction.markEmiPaid,
      label: 'Mark installment paid',
      icon: Icons.check_circle_outline,
    ),
    (action: _MenuAction.editEmi, label: 'Edit EMI', icon: Icons.edit_outlined),
    (
      action: _MenuAction.deleteEmi,
      label: 'Delete EMI',
      icon: Icons.delete_outline,
    ),
    (
      action: _MenuAction.calculator,
      label: 'Calculator',
      icon: Icons.calculate_outlined,
    ),
  ],
  2 => [
    (
      action: _MenuAction.moneyLent,
      label: 'Lend money',
      icon: Icons.call_made_outlined,
    ),
    (
      action: _MenuAction.moneyBorrowed,
      label: 'Borrow money',
      icon: Icons.call_received_outlined,
    ),
    (
      action: _MenuAction.repayment,
      label: 'Record repayment',
      icon: Icons.payments_outlined,
    ),
    (
      action: _MenuAction.editMoney,
      label: 'Edit record',
      icon: Icons.edit_outlined,
    ),
    (
      action: _MenuAction.deleteMoney,
      label: 'Delete record',
      icon: Icons.delete_outline,
    ),
    (
      action: _MenuAction.calculator,
      label: 'Calculator',
      icon: Icons.calculate_outlined,
    ),
  ],
  3 => [
    (
      action: _MenuAction.subscription,
      label: 'Add subscription',
      icon: Icons.add_circle_outline,
    ),
    (
      action: _MenuAction.pauseSubscription,
      label: 'Pause or resume',
      icon: Icons.pause_circle_outline,
    ),
    (
      action: _MenuAction.editSubscription,
      label: 'Edit subscription',
      icon: Icons.edit_outlined,
    ),
    (
      action: _MenuAction.deleteSubscription,
      label: 'Delete subscription',
      icon: Icons.delete_outline,
    ),
    (
      action: _MenuAction.calculator,
      label: 'Calculator',
      icon: Icons.calculate_outlined,
    ),
  ],
  _ => [
    (
      action: _MenuAction.moneyLent,
      label: 'Money lent',
      icon: Icons.call_made_outlined,
    ),
    (
      action: _MenuAction.moneyBorrowed,
      label: 'Money borrowed',
      icon: Icons.call_received_outlined,
    ),
    (
      action: _MenuAction.emi,
      label: 'Add EMI',
      icon: Icons.account_balance_outlined,
    ),
    (
      action: _MenuAction.subscription,
      label: 'Add subscription',
      icon: Icons.autorenew_outlined,
    ),
    (
      action: _MenuAction.calculator,
      label: 'EMI calculator',
      icon: Icons.calculate_outlined,
    ),
  ],
};

Future<void> showAddMenu(BuildContext context, {int tabIndex = 0}) async {
  final items = _menuFor(tabIndex);
  final choice = await showModalBottomSheet<_MenuAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final palette = AppTheme.homePaletteOf(sheetContext);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .84,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  switch (tabIndex) {
                    1 => 'EMIs & Loans',
                    2 => 'Money',
                    3 => 'Subscriptions',
                    _ => 'Add to FinKeep',
                  },
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose an action',
                  style: TextStyle(color: palette.text2),
                ),
                const SizedBox(height: 18),
                for (final (index, item) in items.indexed) ...[
                  if (index == 0 ||
                      _addMenuGroup(items[index - 1].action) !=
                          _addMenuGroup(item.action)) ...[
                    if (index != 0) const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _addMenuGroup(item.action).toUpperCase(),
                        style: TextStyle(
                          color: palette.text2,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8,
                        ),
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: palette.surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(sheetContext, item.action),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: Icon(
                                  item.icon,
                                  color: palette.text,
                                  size: 23,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.label,
                                      style: TextStyle(
                                        color: palette.text,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      _addMenuDescription(item.action),
                                      style: TextStyle(
                                        color: palette.text2,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: palette.text2,
                                size: 20,
                              ),
                            ],
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
      );
    },
  );
  if (choice == null || !context.mounted) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) _runMenuAction(context, choice);
  });
}

String _addMenuGroup(_MenuAction action) => switch (action) {
  _MenuAction.calculator => 'Tools',
  _MenuAction.markEmiPaid ||
  _MenuAction.editEmi ||
  _MenuAction.deleteEmi ||
  _MenuAction.repayment ||
  _MenuAction.editMoney ||
  _MenuAction.deleteMoney ||
  _MenuAction.pauseSubscription ||
  _MenuAction.editSubscription ||
  _MenuAction.deleteSubscription => 'Manage',
  _ => 'Create',
};

String _addMenuDescription(_MenuAction action) => switch (action) {
  _MenuAction.personalEmi => 'Track a loan or card installment',
  _MenuAction.friendEmi => 'Collect installments from someone',
  _MenuAction.emi => 'Add a repayment schedule',
  _MenuAction.moneyLent => 'Track money owed to you',
  _MenuAction.moneyBorrowed => 'Track money you owe',
  _MenuAction.subscription => 'Track a recurring payment',
  _MenuAction.calculator => 'Estimate payments and totals',
  _MenuAction.markEmiPaid || _MenuAction.repayment => 'Record a payment',
  _MenuAction.editEmi ||
  _MenuAction.editMoney ||
  _MenuAction.editSubscription => 'Update an existing record',
  _MenuAction.deleteEmi ||
  _MenuAction.deleteMoney ||
  _MenuAction.deleteSubscription => 'Move an item to Deleted',
  _MenuAction.pauseSubscription => 'Change a subscription status',
};

Future<T?> _pickRecord<T>(
  BuildContext context,
  String title,
  List<T> items,
  String Function(T) name,
  String Function(T) detail,
) {
  if (items.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Nothing to choose yet.')));
    return Future.value(null);
  }
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * .75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(sheet).textTheme.titleMedium),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (_, index) => ListTile(
                  title: Text(name(items[index])),
                  subtitle: Text(detail(items[index])),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(sheet, items[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> _confirmDelete(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Delete $name?'),
        content: const Text(
          'This item will move to Deleted and can be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ??
    false;

void _showUndo(BuildContext context, Future<void> Function() restore) {
  showTimedSnackBar(
    ScaffoldMessenger.of(context),
    SnackBar(
      duration: const Duration(seconds: 6),
      content: const Text('Moved to Deleted'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          restore();
        },
      ),
    ),
  );
}

Future<void> _runMenuAction(BuildContext context, _MenuAction action) async {
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    switch (action) {
      case _MenuAction.moneyLent:
        openFinanceSheet(
          context,
          const MoneyFormSheet(initialDirection: MoneyDirection.given),
        );
      case _MenuAction.moneyBorrowed:
        openFinanceSheet(
          context,
          const MoneyFormSheet(initialDirection: MoneyDirection.borrowed),
        );
      case _MenuAction.emi:
        await openEmiEntryFlow(context);
      case _MenuAction.personalEmi:
        await openFinanceSheet(context, const EmiFormSheet());
      case _MenuAction.friendEmi:
        await openFinanceSheet(
          context,
          const EmiFormSheet(category: EmiCategory.givenToFriends),
        );
      case _MenuAction.subscription:
        openFinanceSheet(context, const SubscriptionFormSheet());
      case _MenuAction.calculator:
        _openMenuCalculator(context);
      case _MenuAction.markEmiPaid ||
          _MenuAction.editEmi ||
          _MenuAction.deleteEmi:
        final details = await container.read(allEmiDetailsProvider.future);
        if (!context.mounted) return;
        final selected = await _pickRecord<EmiDetail>(
          context,
          action == _MenuAction.markEmiPaid
              ? 'Choose an EMI to pay'
              : 'Choose an EMI',
          details
              .where(
                (item) =>
                    action != _MenuAction.markEmiPaid ||
                    item.nextUnpaidInstallment != null,
              )
              .toList(),
          (item) => item.emi.name,
          (item) => item.emi.provider ?? 'EMI',
        );
        if (selected == null || !context.mounted) return;
        if (action == _MenuAction.editEmi) {
          openFinanceSheet(
            context,
            EmiFormSheet(emi: selected.emi, category: selected.category),
          );
        } else if (action == _MenuAction.markEmiPaid) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EmiAgreementDetailScreen(selected.emi.id),
            ),
          );
        } else if (await _confirmDelete(context, selected.emi.name)) {
          final repo = container.read(financeRepositoryProvider);
          await repo.deleteEmi(selected.emi.id);
          if (context.mounted) {
            _showUndo(context, () => repo.restoreEmi(selected.emi.id));
          }
        }
      case _MenuAction.repayment ||
          _MenuAction.editMoney ||
          _MenuAction.deleteMoney:
        final details = await container.read(moneyRecordsProvider.future);
        if (!context.mounted) return;
        final selected = await _pickRecord<MoneyRecordDetail>(
          context,
          action == _MenuAction.repayment
              ? 'Choose a record to repay'
              : 'Choose a money record',
          details
              .where(
                (item) =>
                    action != _MenuAction.repayment ||
                    item.summary.remainingAmountPaise > 0,
              )
              .toList(),
          (item) => item.record.personName,
          (item) => 'Record #${item.record.id}',
        );
        if (selected == null || !context.mounted) return;
        if (action == _MenuAction.editMoney) {
          openFinanceSheet(context, MoneyFormSheet(record: selected.record));
        } else if (action == _MenuAction.repayment) {
          openFinanceSheet(
            context,
            RepaymentSheet(
              recordId: selected.record.id,
              remainingPaise: selected.summary.remainingAmountPaise,
            ),
          );
        } else if (await _confirmDelete(context, selected.record.personName)) {
          final repo = container.read(financeRepositoryProvider);
          await repo.deleteMoneyRecord(selected.record.id);
          if (context.mounted) {
            _showUndo(
              context,
              () => repo.restoreMoneyRecord(selected.record.id),
            );
          }
        }
      case _MenuAction.pauseSubscription ||
          _MenuAction.editSubscription ||
          _MenuAction.deleteSubscription:
        final items = await container.read(subscriptionsProvider.future);
        if (!context.mounted) return;
        final selected = await _pickRecord<Subscription>(
          context,
          'Choose a subscription',
          items,
          (item) => item.name,
          (item) => item.status.name,
        );
        if (selected == null || !context.mounted) return;
        if (action == _MenuAction.editSubscription) {
          openFinanceSheet(
            context,
            SubscriptionFormSheet(subscription: selected),
          );
        } else if (action == _MenuAction.pauseSubscription) {
          openSubscriptionDetailSheet(context, selected);
        } else if (await _confirmDelete(context, selected.name)) {
          final repo = container.read(financeRepositoryProvider);
          await repo.deleteSubscription(selected.id);
          if (context.mounted) {
            _showUndo(context, () => repo.restoreSubscription(selected));
          }
        }
    }
  } catch (error, stackTrace) {
    debugPrint('Add menu action failed: $error\n$stackTrace');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not complete that action.')),
      );
    }
  }
}

void _openMenuCalculator(BuildContext context) {
  openCalculator(
    context,
    onDestination: (destination, amount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        switch (destination) {
          case CalculatorDestination.emi:
            openFinanceSheet(context, EmiFormSheet(initialEmiAmount: amount));
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
        if (!context.mounted) return;
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

class NotchedNavigationBar extends StatelessWidget {
  const NotchedNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.onAsk,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback? onAsk;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }
    final tokens = AppTheme.homePaletteOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final narrow = MediaQuery.sizeOf(context).width < 360;
    final addSize = narrow ? 52.0 : 60.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        NotchedNavigationMetrics._safeBottom(context) +
            NotchedNavigationMetrics.bottomMargin,
      ),
      child: SizedBox(
        height: NotchedNavigationMetrics.height,
        child: Row(
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: dark
                      ? null
                      : [
                          BoxShadow(
                            color: tokens.text.withValues(alpha: .12),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: tokens.surface.withValues(alpha: .92),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: tokens.line),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final showLabel = constraints.maxWidth >= 244;
                          final activeWidth = showLabel
                              ? math.min(
                                  112.0,
                                  math.max(64.0, constraints.maxWidth - 3 * 48),
                                )
                              : constraints.maxWidth / 4;
                          final otherWidth =
                              (constraints.maxWidth - activeWidth) / 3;
                          return Stack(
                            children: [
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                left: selectedIndex * otherWidth,
                                top: 8,
                                width: activeWidth,
                                height: 48,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: tokens.text,
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  for (var index = 0; index < 4; index++)
                                    _tab(
                                      context,
                                      index,
                                      index == selectedIndex
                                          ? activeWidth
                                          : otherWidth,
                                      showLabel: showLabel,
                                    ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: narrow ? 6 : 8),
            _DockActionButton(
              label: 'Ask FinKeep',
              size: 44,
              icon: Icons.auto_awesome_outlined,
              fill: tokens.surfaceAlt,
              iconColor: tokens.text,
              glow: tokens.text,
              onTap: () {
                HapticFeedback.lightImpact();
                if (onAsk != null) {
                  onAsk!();
                } else {
                  openAskFinKeep(context);
                }
              },
            ),
            SizedBox(width: narrow ? 6 : 8),
            _DockActionButton(
              label: 'Add record',
              size: addSize,
              icon: Icons.add,
              fill: tokens.text,
              iconColor: tokens.surface,
              glow: tokens.text,
              rotateOnPress: true,
              onTap: () {
                HapticFeedback.lightImpact();
                showAddMenu(context, tabIndex: selectedIndex);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    int index,
    double width, {
    required bool showLabel,
  }) {
    const labels = ['Home', 'EMIs', 'Money', 'Bills'];
    final selected = selectedIndex == index;
    final tokens = AppTheme.homePaletteOf(context);
    final ink = selected ? tokens.text : tokens.text3;
    return Semantics(
      button: true,
      selected: selected,
      label: '${labels[index]} tab${selected ? ', selected' : ''}',
      child: Tooltip(
        message: labels[index],
        child: InkWell(
          onTap: () {
            if (selected) return;
            HapticFeedback.selectionClick();
            onSelected(index);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: width,
            height: 48,
            alignment: Alignment.center,
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _dockIcon(index, selected),
                  size: 24,
                  color: selected ? tokens.surface : ink,
                ),
                if (selected && showLabel) ...[
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      labels[index],
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tokens.surface,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockActionButton extends StatefulWidget {
  const _DockActionButton({
    required this.label,
    required this.size,
    required this.icon,
    required this.fill,
    required this.iconColor,
    required this.glow,
    required this.onTap,
    this.rotateOnPress = false,
  });

  final String label;
  final double size;
  final IconData icon;
  final Color fill, iconColor, glow;
  final VoidCallback onTap;
  final bool rotateOnPress;

  @override
  State<_DockActionButton> createState() => _DockActionButtonState();
}

class _DockActionButtonState extends State<_DockActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    return Semantics(
      button: true,
      label: widget.label,
      child: Tooltip(
        message: widget.label,
        child: AnimatedScale(
          scale: _pressed ? .90 : 1,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: duration,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.glow.withValues(alpha: _pressed ? .30 : .16),
                  blurRadius: _pressed ? 22 : 16,
                  spreadRadius: _pressed ? 2 : 1,
                ),
              ],
            ),
            child: Material(
              color: widget.fill,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onHighlightChanged: (pressed) {
                  if (mounted && _pressed != pressed) {
                    setState(() => _pressed = pressed);
                  }
                },
                onTap: widget.onTap,
                child: SizedBox.square(
                  dimension: widget.size,
                  child: Center(
                    child: AnimatedRotation(
                      turns: _pressed
                          ? (widget.rotateOnPress ? .125 : -.06)
                          : 0,
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        widget.icon,
                        size: widget.rotateOnPress ? 30 : 22,
                        color: widget.iconColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _dockIcon(int index, bool selected) => switch (index) {
  0 => selected ? Icons.home_rounded : Icons.home_outlined,
  1 =>
    selected ? Icons.account_balance_rounded : Icons.account_balance_outlined,
  2 => selected ? Icons.payments_rounded : Icons.payments_outlined,
  _ => selected ? Icons.autorenew_rounded : Icons.autorenew_outlined,
};
