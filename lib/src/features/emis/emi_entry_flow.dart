import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../domain/enums.dart';
import '../../shared/forms.dart';
import 'emis_screen.dart';

Future<void> openEmiEntryFlow(BuildContext context) async {
  final category = await showModalBottomSheet<EmiCategory>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      final colors = AppTheme.homePaletteOf(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What do you want to track?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _EntryChoice(
              icon: Icons.account_balance_outlined,
              title: 'My personal loan or credit card',
              subtitle: 'Payments you make to a lender',
              color: colors.owe.graphic,
              onTap: () => Navigator.pop(context, EmiCategory.personal),
            ),
            const SizedBox(height: 10),
            _EntryChoice(
              icon: Icons.person_outline_rounded,
              title: 'Money I gave to someone',
              subtitle: 'Installments you expect to receive',
              color: colors.bills.graphic,
              onTap: () => Navigator.pop(context, EmiCategory.givenToFriends),
            ),
          ],
        ),
      );
    },
  );
  if (!context.mounted || category == null) return;
  await openFinanceSheet(context, EmiFormSheet(category: category));
}

class _EntryChoice extends StatelessWidget {
  const _EntryChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.homePaletteOf(context);
    return Material(
      color: colors.surfaceAlt,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(color: colors.text2, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.text2),
            ],
          ),
        ),
      ),
    );
  }
}
