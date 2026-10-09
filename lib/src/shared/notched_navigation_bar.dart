import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';

class NotchedNavigationMetrics {
  static const height = 64.0;
  static const centerLift = 22.0;
  static const bottomMargin = 12.0;
  static const contentGap = 24.0;
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

class NotchedNavigationBar extends StatefulWidget {
  const NotchedNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.onAsk,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onAsk;

  @override
  State<NotchedNavigationBar> createState() => _NotchedNavigationBarState();
}

class _NotchedNavigationBarState extends State<NotchedNavigationBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dotController;
  late Animation<double> _dotPosition = AlwaysStoppedAnimation<double>(
    widget.selectedIndex.toDouble(),
  );
  bool _askPressed = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(covariant NotchedNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex == widget.selectedIndex) return;
    final start = _dotPosition.value;
    final end = widget.selectedIndex.toDouble();
    if (_reduceMotion) {
      _dotController.stop();
      _dotPosition = AlwaysStoppedAnimation<double>(end);
    } else {
      _dotController.reset();
      _dotPosition = Tween<double>(
        begin: start,
        end: end,
      ).animate(CurvedAnimation(parent: _dotController, curve: Curves.easeOut));
      _dotController.forward();
    }
  }

  @override
  void dispose() {
    _dotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboardOpen) return const SizedBox.shrink();
    final tokens = AppTheme.colorsOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          16,
          0,
          16,
          NotchedNavigationMetrics.bottomMargin,
        ),
        child: SizedBox(
          height:
              NotchedNavigationMetrics.height +
              NotchedNavigationMetrics.centerLift,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final tabWidth = (width - 88) / 4;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: NotchedNavigationMetrics.centerLift,
                    left: 0,
                    right: 0,
                    height: NotchedNavigationMetrics.height,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _NotchedBarPainter(
                          surface: tokens.surfaceHigh,
                          outline: dark ? tokens.outline : AppTheme.transparent,
                          shadow: tokens.navShadow,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: NotchedNavigationMetrics.centerLift,
                    left: 0,
                    right: 0,
                    height: NotchedNavigationMetrics.height,
                    child: Row(
                      children: [
                        _tab(
                          0,
                          'Home',
                          Icons.home_outlined,
                          Icons.home_rounded,
                        ),
                        _tab(
                          1,
                          'EMIs',
                          Icons.account_balance_outlined,
                          Icons.account_balance_rounded,
                        ),
                        const SizedBox(width: 88),
                        _tab(
                          2,
                          'Money',
                          Icons.payments_outlined,
                          Icons.payments_rounded,
                        ),
                        _tab(3, 'Subs', Icons.autorenew, Icons.autorenew),
                      ],
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _dotPosition,
                    builder: (context, _) => Positioned(
                      top: NotchedNavigationMetrics.centerLift + 54,
                      left: _dotCenter(_dotPosition.value, tabWidth) - 2.5,
                      child: SizedBox.square(
                        dimension: 5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: (width - 60) / 2,
                    child: Semantics(
                      button: true,
                      label: 'Ask FinKeep',
                      child: GestureDetector(
                        onTapDown: (_) => setState(() => _askPressed = true),
                        onTapUp: (_) => setState(() => _askPressed = false),
                        onTapCancel: () => setState(() => _askPressed = false),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          widget.onAsk();
                        },
                        child: AnimatedScale(
                          scale: _askPressed ? 0.92 : 1,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 140),
                          curve: Curves.easeOut,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [AppTheme.heroStart, AppTheme.heroEnd],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.heroStart.withValues(
                                    alpha: 0.23,
                                  ),
                                  blurRadius: 16,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              size: 27,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _tab(int index, String label, IconData outline, IconData filled) {
    final selected = widget.selectedIndex == index;
    final active = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.primary
        : AppTheme.heroEnd;
    final inactive = AppTheme.colorsOf(context).navInactive;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label tab${selected ? ', selected' : ''}',
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onSelected(index);
          },
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: selected ? 1.12 : 1,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: Icon(
                    selected ? filled : outline,
                    size: 24,
                    color: selected ? active : inactive,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? active : inactive,
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _dotCenter(double position, double tabWidth) {
    final lower = position.floor().clamp(0, 3);
    final upper = position.ceil().clamp(0, 3);
    double center(int index) =>
        index < 2 ? (index + 0.5) * tabWidth : (index + 0.5) * tabWidth + 88;
    return center(lower) + (center(upper) - center(lower)) * (position - lower);
  }
}

class _NotchedBarPainter extends CustomPainter {
  _NotchedBarPainter({
    required this.surface,
    required this.outline,
    required this.shadow,
  });
  final Color surface, outline, shadow;
  Size? _pathSize;
  Path? _path;

  @override
  void paint(Canvas canvas, Size size) {
    if (_pathSize != size) {
      _pathSize = size;
      _path = _buildPath(size);
    }
    final path = _path!;
    if (shadow.a > 0) {
      canvas.drawPath(path.shift(const Offset(0, 7)), Paint()..color = shadow);
      canvas.drawPath(path.shift(const Offset(0, 4)), Paint()..color = shadow);
    }
    canvas.drawPath(path, Paint()..color = surface);
    if (outline.a > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  Path _buildPath(Size size) {
    final width = size.width;
    final height = size.height;
    final center = width / 2;
    final path = Path()
      ..moveTo(28, 0)
      ..lineTo(center - 58, 0)
      ..cubicTo(center - 49, 0, center - 45, 4, center - 42, 12)
      ..cubicTo(center - 34, 32, center - 20, 38, center, 38)
      ..cubicTo(center + 20, 38, center + 34, 32, center + 42, 12)
      ..cubicTo(center + 45, 4, center + 49, 0, center + 58, 0)
      ..lineTo(width - 28, 0)
      ..arcToPoint(Offset(width, 28), radius: const Radius.circular(28))
      ..lineTo(width, height - 28)
      ..arcToPoint(
        Offset(width - 28, height),
        radius: const Radius.circular(28),
      )
      ..lineTo(28, height)
      ..arcToPoint(Offset(0, height - 28), radius: const Radius.circular(28))
      ..lineTo(0, 28)
      ..arcToPoint(const Offset(28, 0), radius: const Radius.circular(28))
      ..close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _NotchedBarPainter oldDelegate) =>
      oldDelegate.surface != surface ||
      oldDelegate.outline != outline ||
      oldDelegate.shadow != shadow;
}
