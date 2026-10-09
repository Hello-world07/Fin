import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../domain/enums.dart';
import '../../shared/finance_display_widgets.dart';
import '../../shared/forms.dart';
import '../emis/emis_screen.dart';
import '../money/money_screen.dart';
import '../subscriptions/subscriptions_screen.dart';
import 'assistant_commands.dart';
import 'assistant_actions.dart';
import 'assistant_engine.dart';
import 'assistant_visual_widgets.dart';

class AssistantChatController {
  final input = TextEditingController();
  final scroll = ScrollController();
  final focus = FocusNode();

  void dispose() {
    input.dispose();
    scroll.dispose();
    focus.dispose();
  }
}

final assistantChatControllerProvider = Provider<AssistantChatController>((
  ref,
) {
  final controller = AssistantChatController();
  ref.onDispose(controller.dispose);
  return controller;
});

Future<void> openAskFinKeep(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  enableDrag: false,
  backgroundColor: Theme.of(context).colorScheme.surface,
  barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.54),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  sheetAnimationStyle: const AnimationStyle(
    duration: Duration(milliseconds: 220),
    reverseDuration: Duration(milliseconds: 220),
  ),
  builder: (_) => const AskFinKeepSheet(),
);

class _ChatMessage {
  const _ChatMessage.user(this.question) : reply = null, animate = false;
  const _ChatMessage.assistant(this.reply, {this.animate = true})
    : question = null;
  final String? question;
  final AssistantReply? reply;
  final bool animate;
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
  late final AssistantChatController _chat;
  TextEditingController get _input => _chat.input;
  ScrollController get _scroll => _chat.scroll;
  FocusNode get _focus => _chat.focus;
  final _messages = <_ChatMessage>[
    const _ChatMessage.assistant(
      AssistantReply(
        'Hi! What would you like to know about your money?',
        suggestions: ['Today', ..._initialSuggestions],
      ),
      animate: false,
    ),
  ];
  bool _typing = false;
  double _lastKeyboardInset = 0;
  bool _followLatest = true;
  bool _showJump = false;
  double _lastScrollOffset = 0;
  String? _lastEntityName;
  AssistantEntityType? _lastEntityType;
  final _resolvedMutationIds = <String>{};
  final _speech = stt.SpeechToText();
  String _speechLocale = 'en_IN';
  double _headerDrag = 0;
  bool _wantsListening = false;
  bool _startingSpeech = false;
  DateTime? _speechStarted;
  String _committedTranscript = '';
  String _currentTranscript = '';
  String? _availableLocale;
  Timer? _restartSpeechTimer;
  Timer? _speechLimitTimer;
  final _soundLevel = ValueNotifier<double>(0);
  final _micKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _chat = ref.read(assistantChatControllerProvider);
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset != _lastKeyboardInset) {
      _lastKeyboardInset = inset;
      _followNewest();
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _wantsListening = false;
    _restartSpeechTimer?.cancel();
    _speechLimitTimer?.cancel();
    _speech.cancel();
    _soundLevel.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final offset = _scroll.offset;
    if (offset > _lastScrollOffset + 1 &&
        _scroll.position.userScrollDirection != ScrollDirection.idle) {
      _followLatest = false;
    } else if (offset <= 8) {
      _followLatest = true;
    }
    _lastScrollOffset = offset;
    final show = offset > 80;
    if (show != _showJump && mounted) setState(() => _showJump = show);
  }

  void _followNewest({bool force = false}) {
    if (!force && !_followLatest) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || (!force && !_followLatest)) return;
      _scroll.animateTo(
        0,
        duration: AppTheme.motionDuration,
        curve: Curves.easeOut,
      );
    });
  }

  void _jumpToLatest() {
    _followLatest = true;
    _followNewest(force: true);
  }

  Future<void> _toggleListening() async {
    if (_wantsListening) {
      await _stopListening();
      return;
    }
    try {
      final ready = await _speech.initialize(
        options: [stt.SpeechToText.androidNoBluetooth],
        onStatus: _onSpeechStatus,
        onError: _onSpeechError,
      );
      if (!mounted) return;
      if (!ready) {
        _voiceError(
          'Microphone permission or on-device speech recognition is unavailable.',
        );
        return;
      }
      final locales = await _speech.locales();
      if (!mounted) return;
      final wanted = _speechLocale.split('_').first;
      final locale = locales
          .where((item) => item.localeId.toLowerCase().startsWith(wanted))
          .firstOrNull;
      if (locale == null) {
        _voiceError(
          'Install the $wanted offline speech pack to use voice input.',
        );
        return;
      }
      _availableLocale = locale.localeId;
      _committedTranscript = _input.text.trim();
      _currentTranscript = '';
      _speechStarted = DateTime.now();
      _wantsListening = true;
      _speechLimitTimer?.cancel();
      _speechLimitTimer = Timer(const Duration(minutes: 2), () {
        if (mounted) unawaited(_stopListening());
      });
      setState(() {});
      await _startSpeechSession();
    } catch (_) {
      if (mounted) {
        await _stopListening();
        _voiceError(
          'Offline speech recognition is unavailable. Check the language pack and microphone permission.',
        );
      }
    }
  }

  Future<void> _startSpeechSession() async {
    if (!_wantsListening || _startingSpeech || _availableLocale == null) return;
    if (DateTime.now().difference(_speechStarted!) >=
        const Duration(minutes: 2)) {
      await _stopListening();
      return;
    }
    _startingSpeech = true;
    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted || !_wantsListening) return;
          _currentTranscript = result.recognizedWords.trim();
          _showTranscript();
        },
        onSoundLevelChange: (level) {
          if (mounted && _wantsListening) _soundLevel.value = level;
        },
        listenOptions: stt.SpeechListenOptions(
          onDevice: true,
          localeId: _availableLocale,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 8),
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
          cancelOnError: false,
        ),
      );
    } catch (_) {
      await _stopListening();
      if (mounted) {
        _voiceError(
          'Offline speech recognition could not start. Check the language pack and microphone permission.',
        );
      }
    } finally {
      _startingSpeech = false;
    }
  }

  void _onSpeechStatus(String status) {
    if (!mounted) return;
    if (status == stt.SpeechToText.doneStatus ||
        status == stt.SpeechToText.notListeningStatus) {
      _scheduleSpeechRestart();
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted || !_wantsListening) return;
    final message = error.errorMsg.toString().toLowerCase();
    if (message.contains('permission') ||
        message.contains('not_available') ||
        message.contains('language_unavailable') ||
        message.contains('language_not_supported')) {
      unawaited(_stopListening());
      _voiceError(
        'Allow microphone access and install an offline speech pack to use voice input.',
      );
      return;
    }
    _scheduleSpeechRestart();
  }

  void _scheduleSpeechRestart() {
    if (!_wantsListening || !mounted || _restartSpeechTimer?.isActive == true) {
      return;
    }
    _commitTranscript();
    if (DateTime.now().difference(_speechStarted!) >=
        const Duration(minutes: 2)) {
      unawaited(_stopListening());
      return;
    }
    _restartSpeechTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted && _wantsListening) unawaited(_startSpeechSession());
    });
  }

  void _showTranscript() {
    final text = [
      _committedTranscript,
      _currentTranscript,
    ].where((part) => part.isNotEmpty).join(' ');
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _commitTranscript() {
    if (_currentTranscript.isEmpty) return;
    _committedTranscript = [
      _committedTranscript,
      _currentTranscript,
    ].where((part) => part.isNotEmpty).join(' ');
    _currentTranscript = '';
    _showTranscript();
  }

  Future<void> _stopListening() async {
    _wantsListening = false;
    _restartSpeechTimer?.cancel();
    _speechLimitTimer?.cancel();
    _commitTranscript();
    _soundLevel.value = 0;
    try {
      await _speech.stop();
    } catch (_) {
      // The recognizer may already have stopped after silence.
    }
    if (mounted) setState(() {});
  }

  void _selectSpeechLocale(String value) {
    setState(() => _speechLocale = value);
    if (_wantsListening) {
      unawaited(_stopListening());
    }
  }

  Future<void> _showLanguageMenu() async {
    final box = _micKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final size = MediaQuery.sizeOf(context);
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy - 150,
        size.width - origin.dx - box.size.width,
        size.height - origin.dy,
      ),
      items: const [
        PopupMenuItem(value: 'en_IN', child: Text('English')),
        PopupMenuItem(value: 'hi_IN', child: Text('Hindi')),
        PopupMenuItem(value: 'te_IN', child: Text('Telugu')),
      ],
    );
    if (value != null && mounted) _selectSpeechLocale(value);
  }

  void _voiceError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _typing) return;
    _input.clear();
    setState(() {
      _messages.add(_ChatMessage.user(trimmed));
      _typing = true;
    });
    _followNewest();
    try {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      final engine = ref.read(assistantEngineProvider);
      final previous = [
        for (final item in _messages.take(_messages.length - 1))
          if (item.question != null) item.question!,
      ];
      final started = DateTime.now();
      var reply = await engine.ask(
        trimmed,
        ConversationContext(
          now: started,
          previousQuestions: previous,
          lastEntityName: _lastEntityName,
          lastEntityType: _lastEntityType,
        ),
      );
      reply = _withFollowUps(trimmed, reply);
      final elapsed = DateTime.now().difference(started);
      final thinkingMs = (500 + reply.text.split(RegExp(r'\s+')).length * 5)
          .clamp(500, 900);
      final thinking = Duration(milliseconds: thinkingMs);
      if (!reduceMotion && elapsed < thinking) {
        await Future<void>.delayed(thinking - elapsed);
      }
      if (!mounted) return;
      setState(() {
        _typing = false;
        _messages.add(_ChatMessage.assistant(reply));
        _lastEntityName = reply.confirmation?.entityName ?? _lastEntityName;
        _lastEntityType = reply.confirmation?.entityType ?? _lastEntityType;
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
    _followNewest();
  }

  AssistantReply _withFollowUps(String question, AssistantReply reply) {
    if (reply.suggestions.isNotEmpty ||
        reply.confirmation != null ||
        reply.openForm != null) {
      return reply;
    }
    final q = question.toLowerCase();
    final suggestions = q.contains('due')
        ? const ['What about next week?', 'What do I need to pay this month?']
        : q.contains('emi')
        ? const ['When is my next EMI?', 'Total debt left']
        : q.contains('subscription')
        ? const ['Subscriptions per month', "What's due this week?"]
        : const ['My financial status', "What's due this week?"];
    return AssistantReply(
      reply.text,
      rows: reply.rows,
      chart: reply.chart,
      actions: reply.actions,
      suggestions: suggestions,
      visuals: reply.visuals,
      undoMutation: reply.undoMutation,
    );
  }

  Future<void> _confirm(AssistantPendingMutation mutation) async {
    if (_typing || _resolvedMutationIds.contains(mutation.id)) return;
    final engine = ref.read(assistantEngineProvider);
    if (engine is! AssistantActionEngine) return;
    final actionEngine = engine as AssistantActionEngine;
    setState(() {
      _typing = true;
      _resolvedMutationIds.add(mutation.id);
    });
    _followNewest();
    try {
      final reply = await actionEngine.confirm(mutation);
      if (!mounted) return;
      setState(() {
        _typing = false;
        _messages.add(_ChatMessage.assistant(reply));
        _lastEntityName = mutation.entityName;
        _lastEntityType = mutation.entityType;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _typing = false;
        _resolvedMutationIds.remove(mutation.id);
        _messages.add(
          const _ChatMessage.assistant(
            AssistantReply(
              'That change could not be completed. Your data was not changed.',
            ),
          ),
        );
      });
    }
    _followNewest();
  }

  void _cancelMutation(AssistantPendingMutation mutation) {
    if (_resolvedMutationIds.contains(mutation.id)) return;
    setState(() {
      _resolvedMutationIds.add(mutation.id);
      _messages.add(
        _ChatMessage.assistant(
          AssistantReply(
            '${mutation.confirmationTitle} cancelled. Nothing changed.',
          ),
        ),
      );
    });
    _followNewest();
  }

  Future<void> _undo(AssistantUndoMutation mutation) async {
    if (_typing) return;
    final engine = ref.read(assistantEngineProvider);
    if (engine is! AssistantActionEngine) return;
    final actionEngine = engine as AssistantActionEngine;
    setState(() => _typing = true);
    try {
      final reply = await actionEngine.undo(mutation);
      if (!mounted) return;
      setState(() {
        _typing = false;
        _messages.add(_ChatMessage.assistant(reply));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _typing = false;
        _messages.add(
          const _ChatMessage.assistant(
            AssistantReply('Undo could not be completed.'),
          ),
        );
      });
    }
    _followNewest();
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
              suggestions: ['Today', ..._initialSuggestions],
            ),
            animate: false,
          ),
        );
    });
    _followNewest();
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
    final compact = MediaQuery.sizeOf(context).height < 500;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final latestAssistant = _messages.lastIndexWhere(
      (item) => item.reply != null,
    );
    final showEmptyDisclaimer =
        _messages.length == 1 && !_typing && !keyboardOpen;
    return FractionallySizedBox(
      heightFactor: compact ? 1 : 0.92,
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) => _headerDrag = 0,
            onVerticalDragUpdate: (details) => _headerDrag += details.delta.dy,
            onVerticalDragEnd: (details) {
              if (_headerDrag > 80 || (details.primaryVelocity ?? 0) > 600) {
                Navigator.of(context).pop();
              }
            },
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 10, 4),
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
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'More options',
                        onSelected: (value) {
                          if (value == 'clear') {
                            _clear();
                          } else {
                            _selectSpeechLocale(value);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'en_IN',
                            child: Text('Voice: English'),
                          ),
                          PopupMenuItem(
                            value: 'hi_IN',
                            child: Text('Voice: Hindi'),
                          ),
                          PopupMenuItem(
                            value: 'te_IN',
                            child: Text('Voice: Telugu'),
                          ),
                          PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'clear',
                            child: Text('Clear chat'),
                          ),
                        ],
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedPadding(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppTheme.motionDuration,
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          findChildIndexCallback: (key) {
                            if (key is ValueKey<String> &&
                                key.value == 'thinking') {
                              return _typing ? 0 : null;
                            }
                            if (key is! ObjectKey ||
                                key.value is! _ChatMessage) {
                              return null;
                            }
                            final index = _messages.indexOf(
                              key.value as _ChatMessage,
                            );
                            if (index < 0) return null;
                            return (_typing ? 1 : 0) +
                                (showEmptyDisclaimer ? 1 : 0) +
                                _messages.length -
                                1 -
                                index;
                          },
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          itemCount:
                              _messages.length +
                              (_typing ? 1 : 0) +
                              (showEmptyDisclaimer ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_typing && index == 0) {
                              return const RepaintBoundary(
                                key: ValueKey('thinking'),
                                child: _AssistantBubble(child: _ThinkingDots()),
                              );
                            }
                            final adjusted = index - (_typing ? 1 : 0);
                            if (showEmptyDisclaimer && adjusted == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Answers use only data on this phone. Not financial advice.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: AppTheme.colorsOf(
                                      context,
                                    ).secondaryText,
                                  ),
                                ),
                              );
                            }
                            final messageIndex =
                                _messages.length -
                                1 -
                                (adjusted - (showEmptyDisclaimer ? 1 : 0));
                            final message = _messages[messageIndex];
                            if (message.question != null) {
                              return RepaintBoundary(
                                key: ObjectKey(message),
                                child: _UserBubble(question: message.question!),
                              );
                            }
                            return RepaintBoundary(
                              key: ObjectKey(message),
                              child: _AssistantBubble(
                                child: _AnimatedReply(
                                  reply: message.reply!,
                                  animate: message.animate,
                                  showSuggestions:
                                      messageIndex == latestAssistant,
                                  onSuggestion: _ask,
                                  onAction: _openDestination,
                                  onConfirm: _confirm,
                                  onCancel: _cancelMutation,
                                  onUndo: _undo,
                                  isMutationResolved: (id) =>
                                      _resolvedMutationIds.contains(id),
                                ),
                              ),
                            );
                          },
                        ),
                        if (_showJump)
                          Positioned(
                            right: 16,
                            bottom: 10,
                            child: FloatingActionButton.small(
                              heroTag: 'assistant-jump-latest',
                              tooltip: 'Jump to latest',
                              onPressed: _jumpToLatest,
                              child: const Icon(Icons.keyboard_arrow_down),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 5, 12, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _input,
                              focusNode: _focus,
                              minLines: 1,
                              maxLines: 5,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                              textInputAction: TextInputAction.send,
                              onSubmitted: (value) {
                                if (!_wantsListening) _ask(value);
                              },
                              decoration: InputDecoration(
                                hintText: 'Ask about your money',
                                filled: true,
                                fillColor:
                                    theme.colorScheme.surfaceContainerHigh,
                                isDense: true,
                                constraints: const BoxConstraints(
                                  minHeight: 52,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 15,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                                suffixIcon: _wantsListening
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _SoundWave(level: _soundLevel),
                                          const SizedBox(width: 4),
                                          Text(
                                            _speechLocale
                                                .split('_')
                                                .first
                                                .toUpperCase(),
                                            style: theme.textTheme.labelSmall,
                                          ),
                                          const SizedBox(width: 10),
                                        ],
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            key: _micKey,
                            width: 52,
                            height: 52,
                            child: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _input,
                              builder: (context, value, _) {
                                final send =
                                    !_wantsListening &&
                                    value.text.trim().isNotEmpty;
                                return Tooltip(
                                  message: _wantsListening
                                      ? 'Stop listening'
                                      : send
                                      ? 'Send'
                                      : 'Speak offline',
                                  child: Material(
                                    color: theme.colorScheme.primary,
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: _typing
                                          ? null
                                          : send
                                          ? () => _ask(_input.text)
                                          : _toggleListening,
                                      onLongPress: _showLanguageMenu,
                                      child: Center(
                                        child: AnimatedSwitcher(
                                          duration:
                                              MediaQuery.disableAnimationsOf(
                                                context,
                                              )
                                              ? Duration.zero
                                              : AppTheme.motionDuration,
                                          child: Icon(
                                            _wantsListening
                                                ? Icons.stop_rounded
                                                : send
                                                ? Icons.arrow_upward_rounded
                                                : Icons.mic_none_rounded,
                                            key: ValueKey(
                                              _wantsListening
                                                  ? 'stop'
                                                  : send
                                                  ? 'send'
                                                  : 'mic',
                                            ),
                                            color: theme.colorScheme.onPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
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
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.question});
  final String question;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.82,
      ),
      margin: const EdgeInsets.only(left: 42, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        question,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppTheme.heroTextOf(context)),
      ),
    ),
  );
}

class _SoundWave extends StatelessWidget {
  const _SoundWave({required this.level});
  final ValueListenable<double> level;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: level,
    builder: (context, value, _) {
      final intensity = (value.abs() / 20).clamp(0.1, 1.0);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final factor in const [0.5, 1.0, 0.7])
            AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              width: 3,
              height: 5 + 14 * intensity * factor,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      );
    },
  );
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
            ? AppTheme.colorsOf(context).fieldFill
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

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots> {
  Timer? _timer;
  int _count = 1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 130), (_) {
      if (mounted) setState(() => _count = _count % 3 + 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    MediaQuery.disableAnimationsOf(context)
        ? 'Thinking...'
        : 'Thinking${'.' * _count}',
  );
}

class _AnimatedReply extends StatefulWidget {
  const _AnimatedReply({
    required this.reply,
    required this.animate,
    required this.showSuggestions,
    required this.onSuggestion,
    required this.onAction,
    required this.onConfirm,
    required this.onCancel,
    required this.onUndo,
    required this.isMutationResolved,
  });

  final AssistantReply reply;
  final bool animate;
  final bool showSuggestions;
  final ValueChanged<String> onSuggestion;
  final ValueChanged<AssistantAction> onAction;
  final ValueChanged<AssistantPendingMutation> onConfirm;
  final ValueChanged<AssistantPendingMutation> onCancel;
  final ValueChanged<AssistantUndoMutation> onUndo;
  final bool Function(String id) isMutationResolved;

  @override
  State<_AnimatedReply> createState() => _AnimatedReplyState();
}

class _AnimatedReplyState extends State<_AnimatedReply> {
  Timer? _timer;
  int _wordCount = 0;
  bool _started = false;
  late final List<String> _words = RegExp(
    r'\S+\s*',
  ).allMatches(widget.reply.text).map((match) => match.group(0)!).toList();
  late final List<int> _delays = _revealDelays(
    _words,
    widget.reply.text.hashCode,
  );

  List<int> _revealDelays(List<String> words, int seed) {
    final random = math.Random(seed);
    final delays = <int>[];
    for (var i = 0; i < words.length; i++) {
      final prior = i == 0 ? '' : words[i - 1].trimRight();
      final pause =
          prior.endsWith('.') || prior.endsWith('!') || prior.endsWith('?')
          ? 300
          : prior.endsWith(',')
          ? 150
          : 0;
      delays.add((55 * (0.7 + random.nextDouble() * 0.6)).round() + pause);
    }
    final total = delays.fold<int>(0, (sum, value) => sum + value);
    if (total > 5000) {
      final scale = 5000 / total;
      return [for (final value in delays) math.max(1, (value * scale).round())];
    }
    return delays;
  }

  void _revealNext() {
    if (!mounted || _wordCount >= _words.length) return;
    _timer = Timer(Duration(milliseconds: _delays[_wordCount]), () {
      if (!mounted) return;
      setState(() => _wordCount++);
      _revealNext();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.animate || MediaQuery.disableAnimationsOf(context)) {
      _timer?.cancel();
      _timer = null;
      _wordCount = _words.length;
      _started = true;
      return;
    }
    if (_started) return;
    _started = true;
    _revealNext();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _wordCount >= _words.length;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: done
          ? null
          : () {
              _timer?.cancel();
              _timer = null;
              setState(() => _wordCount = _words.length);
            },
      child: _ReplyContent(
        reply: widget.reply,
        visibleWordCount: _wordCount,
        showRich: done,
        showSuggestions: widget.showSuggestions,
        onSuggestion: widget.onSuggestion,
        onAction: widget.onAction,
        onConfirm: widget.onConfirm,
        onCancel: widget.onCancel,
        onUndo: widget.onUndo,
        isMutationResolved: widget.isMutationResolved,
      ),
    );
  }
}

class _ReplyContent extends StatelessWidget {
  const _ReplyContent({
    required this.reply,
    required this.visibleWordCount,
    required this.showRich,
    required this.showSuggestions,
    required this.onSuggestion,
    required this.onAction,
    required this.onConfirm,
    required this.onCancel,
    required this.onUndo,
    required this.isMutationResolved,
  });
  final AssistantReply reply;
  final int visibleWordCount;
  final bool showRich;
  final bool showSuggestions;
  final ValueChanged<String> onSuggestion;
  final ValueChanged<AssistantAction> onAction;
  final ValueChanged<AssistantPendingMutation> onConfirm;
  final ValueChanged<AssistantPendingMutation> onCancel;
  final ValueChanged<AssistantUndoMutation> onUndo;
  final bool Function(String id) isMutationResolved;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Builder(
        builder: (context) {
          final fullText = hideMoneyInText(reply.text);
          final words = RegExp(r'\S+\s*').allMatches(fullText).toList();
          final split = visibleWordCount <= 0
              ? 0
              : words[visibleWordCount.clamp(1, words.length) - 1].end;
          return Text.rich(
            TextSpan(
              children: [
                TextSpan(text: fullText.substring(0, split)),
                TextSpan(
                  text: fullText.substring(split),
                  style: const TextStyle(color: Colors.transparent),
                ),
              ],
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          );
        },
      ),
      AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: showRich
            ? Column(
                key: const ValueKey('rich'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (reply.confirmation != null) ...[
                    const SizedBox(height: 12),
                    _ConfirmationCard(
                      mutation: reply.confirmation!,
                      onConfirm: onConfirm,
                      onCancel: onCancel,
                      resolved: isMutationResolved(reply.confirmation!.id),
                    ),
                  ],
                  if (reply.visuals.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final visual in reply.visuals)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AssistantVisualWidget(part: visual),
                      ),
                  ],
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
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AppTheme.colorsOf(
                                        context,
                                      ).secondaryText,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                hideMoneyInText(row.value),
                                textAlign: TextAlign.end,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
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
                        child: Text(
                          '${(reply.chart!.fraction * 100).round()}%',
                        ),
                      )
                    else
                      LinearProgressIndicator(
                        value: reply.chart!.fraction,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      reply.chart!.label,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
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
                              label: Text(hideMoneyInText(action.label)),
                              onPressed: () => onAction(action),
                            )
                          else
                            TextButton.icon(
                              onPressed: () => onAction(action),
                              icon: const Icon(Icons.arrow_forward, size: 16),
                              label: Text(hideMoneyInText(action.label)),
                            ),
                      ],
                    ),
                  ],
                  if (showSuggestions && reply.suggestions.isNotEmpty) ...[
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
                  if (reply.undoMutation != null) ...[
                    const SizedBox(height: 8),
                    _UndoAction(mutation: reply.undoMutation!, onUndo: onUndo),
                  ],
                ],
              )
            : const SizedBox(key: ValueKey('waiting')),
      ),
    ],
  );
}

class _ConfirmationCard extends StatelessWidget {
  const _ConfirmationCard({
    required this.mutation,
    required this.onConfirm,
    required this.onCancel,
    required this.resolved,
  });

  final AssistantPendingMutation mutation;
  final ValueChanged<AssistantPendingMutation> onConfirm;
  final ValueChanged<AssistantPendingMutation> onCancel;
  final bool resolved;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hideMoneyInText(mutation.confirmationTitle),
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          hideMoneyInText(mutation.confirmationEffect),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: resolved ? null : () => onCancel(mutation),
                child: Text(resolved ? 'Resolved' : 'Cancel'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: resolved ? null : () => onConfirm(mutation),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Confirm'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _UndoAction extends StatefulWidget {
  const _UndoAction({required this.mutation, required this.onUndo});
  final AssistantUndoMutation mutation;
  final ValueChanged<AssistantUndoMutation> onUndo;

  @override
  State<_UndoAction> createState() => _UndoActionState();
}

class _UndoActionState extends State<_UndoAction> {
  bool expired = false;

  @override
  void initState() {
    super.initState();
    final expiry = widget.mutation.expiresAt;
    if (!widget.mutation.restore && expiry != null) {
      final remaining = expiry.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        expired = true;
      } else {
        Future<void>.delayed(remaining, () {
          if (mounted) setState(() => expired = true);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: expired ? null : () => widget.onUndo(widget.mutation),
    icon: Icon(widget.mutation.restore ? Icons.restore : Icons.undo, size: 18),
    label: Text(widget.mutation.restore ? 'Restore' : 'Undo'),
  );
}
