import 'package:flutter/material.dart';

class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    required this.title,
    this.actions = const [],
    this.bottom,
    this.horizontalPadding = 20,
    super.key,
  });

  final Widget title;
  final List<Widget> actions;
  final Widget? bottom;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      horizontalPadding,
      MediaQuery.paddingOf(context).top + 8,
      horizontalPadding,
      12,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DefaultTextStyle.merge(
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                child: title,
              ),
            ),
            ...actions,
          ],
        ),
        if (bottom != null) ...[const SizedBox(height: 16), bottom!],
      ],
    ),
  );
}
