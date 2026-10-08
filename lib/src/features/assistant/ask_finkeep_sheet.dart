import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../domain/enums.dart';
import '../../shared/finance_display_widgets.dart';
import '../../shared/finance_form_widgets.dart';
import '../../shared/finance_bottom_sheet.dart';
import '../../shared/forms.dart';
import '../emis/emis_screen.dart';
import '../money/money_screen.dart';
import '../subscriptions/subscriptions_screen.dart';
import 'assistant_commands.dart';
import 'assistant_engine.dart';

Future<void> openAskFinKeep(BuildContext context) =>
    showFinanceBottomSheet<void>(
      context,
      builder: (_) => const AskFinKeepSheet(),
    );

class _ChatMessage {
  const _ChatMessage.user(this.question) : reply = null;
  const _ChatMessage.assistant(this.reply) : question = null;
  final String? question;
  final AssistantReply? reply;
}

class AskFinKeepSheet extends ConsumerStatefulWidget {
  const AskFinKeepSheet({super.key});

  @override
  ConsumerState<AskFinKeepSheet> createState() => _AskFinKeepSheetState();
}

class _AskFinKeepSheetState extends ConsumerState<AskFinKeepSheet> {
  static const _initialSuggestions = [
    'My financial status',
    "What's due this week?",
    'Total debt left',
    'Who owes me?',
  ];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _messages = <_ChatMessage>[
    const _ChatMessage.assistant(
      AssistantReply(
        'Hi! What would you like to know about your money?',
        suggestions: _initialSuggestions,
      ),
    ),
  ];
  bool _typing = false;
  double _lastKeyboardInset = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset != _lastKeyboardInset) {
      _lastKeyboardInset = inset;
      _scrollToEnd();
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: AppTheme.motionDuration,
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _typing) return;
    _input.clear();
    setState(() {
      _messages.add(_ChatMessage.user(trimmed));
      _typing = true;
    });
    _scrollToEnd();
    try {
      final engine = ref.read(assistantEngineProvider);
      final previous = [
        for (final item in _messages)
          if (item.question != null) item.question!,
      ];
      final started = DateTime.now();
      final reply = await engine.ask(
        trimmed,
        ConversationContext(now: started, previousQuestions: previous),
      );
      final elapsed = DateTime.now().difference(started);
      if (elapsed < const Duration(milliseconds: 400)) {
        await Future<void>.delayed(const Duration(milliseconds: 400) - elapsed);
      }
      if (!mounted) return;
      setState(() {
        _typing = false;
        _messages.add(_ChatMessage.assistant(reply));
      });
      if (reply.openForm != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openDraft(reply.openForm!);
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _typing = false;
        _messages.add(
          const _ChatMessage.assistant(
            AssistantReply(
              'I could not read the local finance data just now. Please try again.',
            ),
          ),
        );
      });
    }
    _scrollToEnd();
  }

  void _clear() {
    if (_typing) return;
    setState(() {
      _messages
        ..clear()
        ..add(
          const _ChatMessage.assistant(
            AssistantReply(
              'Hi! What would you like to know about your money?',
              suggestions: _initialSuggestions,
            ),
          ),
        );
    });
    _scrollToEnd();
  }

  void _openDraft(AssistantFormDraft draft) {
    final amount = draft.amountPaise == null
        ? null
        : rupeesText(draft.amountPaise!);
    final form = switch (draft.kind) {
      AssistantFormKind.emi => EmiFormSheet(
        initialEmiAmount: amount,
        initialName: draft.name,
        initialTenureMonths: draft.tenureMonths,
        initialFrequency: draft.frequency,
        initialDueDate: draft.dueDate,
      ),
      AssistantFormKind.moneyGiven => MoneyFormSheet(
        initialAmount: amount,
        initialDirection: MoneyDirection.given,
        initialPerson: draft.name,
        initialDueDate: draft.dueDate,
      ),
      AssistantFormKind.moneyBorrowed => MoneyFormSheet(
        initialAmount: amount,
        initialDirection: MoneyDirection.borrowed,
        initialPerson: draft.name,
        initialDueDate: draft.dueDate,
      ),
      AssistantFormKind.subscription => SubscriptionFormSheet(
        initialAmount: amount,
        initialName: draft.name,
        initialFrequency: draft.frequency,
        initialNextBillingDate: draft.dueDate,
      ),
    };
    openFinanceSheet(context, form);
  }

  void _openDestination(AssistantAction action) {
    if (action.formDraft != null) {
      _openDraft(action.formDraft!);
      return;
    }
    final destination = action.destination;
    final index = switch (destination) {
      AssistantDestination.home => 0,
      AssistantDestination.emis => 1,
      AssistantDestination.money => 2,
      AssistantDestination.subscriptions => 3,
    };
    Navigator.of(context).pop();
    ref.read(shellIndexProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact =
        MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom <
        360;
    return FractionallySizedBox(
      heightFactor: compact ? 1 : 0.96,
      child: Column(
        children: [
          if (!compact) const SizedBox(height: 10),
          Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(12, 0, 8, 0)
                : const EdgeInsets.fromLTRB(18, 2, 12, 10),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ask FinKeep',
                    style:
                        (compact
                                ? theme.textTheme.titleMedium
                                : theme.textTheme.titleLarge)
                            ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Clear chat',
                  onPressed: _clear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (!compact) const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              itemCount: _messages.length + (_typing ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return const _AssistantBubble(child: Text('. . .'));
                }
                final message = _messages[index];
                if (message.question != null) {
                  return Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                      ),
                      margin: const EdgeInsets.only(left: 42, bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: const BoxDecoration(
                        color: AppTheme.heroStart,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                      child: Text(
                        message.question!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.onHero,
                        ),
                      ),
                    ),
                  );
                }
                return _AssistantBubble(
                  child: _ReplyContent(
                    reply: message.reply!,
                    onSuggestion: _ask,
                    onAction: _openDestination,
                  ),
                );
              },
            ),
          ),
          if (!compact) const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: compact
                  ? const EdgeInsets.fromLTRB(12, 2, 12, 2)
                  : const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!compact) const FinanceFieldLabel('MESSAGE'),
                  if (!compact) const SizedBox(height: 7),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          focusNode: _focus,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: _ask,
                          decoration: financeFieldDecoration(
                            context,
                            hint: 'Ask about your money',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Send',
                        onPressed: _typing ? null : () => _ask(_input.text),
                        icon: const Icon(Icons.send_outlined),
                      ),
                    ],
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Answers use only data on this phone. Not financial advice.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.mutedText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.9,
      ),
      margin: const EdgeInsets.only(right: 24, bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.light
            ? AppTheme.fieldFill
            : Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: child,
    ),
  );
}

class _ReplyContent extends StatelessWidget {
  const _ReplyContent({
    required this.reply,
    required this.onSuggestion,
    required this.onAction,
  });
  final AssistantReply reply;
  final ValueChanged<String> onSuggestion;
  final ValueChanged<AssistantAction> onAction;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(reply.text, style: Theme.of(context).textTheme.bodyMedium),
      if (reply.rows.isNotEmpty) ...[
        const SizedBox(height: 10),
        for (final row in reply.rows)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    row.label,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppTheme.mutedText),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    row.value,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      if (reply.chart != null) ...[
        const SizedBox(height: 12),
        if (reply.chart!.kind == AssistantChartKind.ring)
          MiniProgressRing(
            progress: reply.chart!.fraction,
            size: 54,
            child: Text('${(reply.chart!.fraction * 100).round()}%'),
          )
        else
          LinearProgressIndicator(
            value: reply.chart!.fraction,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        const SizedBox(height: 4),
        Text(reply.chart!.label, style: Theme.of(context).textTheme.labelSmall),
      ],
      if (reply.actions.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final action in reply.actions)
              if (action.formDraft != null)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(action.label),
                  onPressed: () => onAction(action),
                )
              else
                TextButton.icon(
                  onPressed: () => onAction(action),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: Text(action.label),
                ),
          ],
        ),
      ],
      if (reply.suggestions.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 5,
          children: [
            for (final suggestion in reply.suggestions)
              ActionChip(
                label: Text(suggestion),
                onPressed: () => onSuggestion(suggestion),
              ),
          ],
        ),
      ],
    ],
  );
}
