import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_lock.dart';

class PinKeypad extends StatelessWidget {
  const PinKeypad({
    required this.length,
    required this.value,
    required this.onDigit,
    required this.onBackspace,
    this.enabled = true,
    super.key,
  });

  final int length;
  final String value;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            length,
            (index) => Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: index < value.length
                    ? scheme.primary
                    : scheme.surfaceContainerHighest,
              ),
            ),
          ),
        ),
        const SizedBox(height: 26),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 330),
          child: Column(
            children: [
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
                ['', '0', 'back'],
              ])
                Row(
                  children: [
                    for (final key in row)
                      Expanded(
                        child: SizedBox(
                          height: 70,
                          child: key.isEmpty
                              ? const SizedBox.shrink()
                              : key == 'back'
                              ? IconButton(
                                  tooltip: 'Delete digit',
                                  onPressed: enabled ? onBackspace : null,
                                  icon: const Icon(Icons.backspace_outlined),
                                )
                              : TextButton(
                                  onPressed: enabled
                                      ? () {
                                          HapticFeedback.selectionClick();
                                          onDigit(key);
                                        }
                                      : null,
                                  style: TextButton.styleFrom(
                                    foregroundColor: scheme.onSurface,
                                    shape: const CircleBorder(),
                                  ),
                                  child: Text(
                                    key,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineMedium,
                                  ),
                                ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  int length = 4;
  String entry = '';
  String? first;
  String? error;

  void add(String digit) {
    if (entry.length >= length) return;
    final next = '$entry$digit';
    setState(() {
      entry = next;
      error = null;
    });
    if (next.length != length) return;
    if (first == null) {
      Future<void>.delayed(const Duration(milliseconds: 180), () {
        if (mounted) {
          setState(() {
            first = next;
            entry = '';
          });
        }
      });
    } else if (first == next) {
      Navigator.pop(context, next);
    } else {
      setState(() {
        entry = '';
        first = null;
        error = 'PINs did not match. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Set a PIN')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 42,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                first == null ? 'Choose your PIN' : 'Confirm PIN',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              if (first == null)
                Text(
                  'Stored as a salted hash on this device.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (first == null) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final count in [4, 6])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: length == count
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainer,
                          ),
                          onPressed: () => setState(() {
                            length = count;
                            entry = '';
                          }),
                          child: Text('$count digits'),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              PinKeypad(
                length: length,
                value: entry,
                onDigit: add,
                onBackspace: () => setState(() {
                  if (entry.isNotEmpty) {
                    entry = entry.substring(0, entry.length - 1);
                  }
                }),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PinVerifyScreen extends StatefulWidget {
  const PinVerifyScreen({required this.title, super.key});
  final String title;

  @override
  State<PinVerifyScreen> createState() => _PinVerifyScreenState();
}

class _PinVerifyScreenState extends State<PinVerifyScreen> {
  final lock = PinLockService();
  Timer? countdown;
  int length = 4;
  bool legacy = false;
  String entry = '';
  String? error;
  bool busy = false;
  DateTime? blockedUntil;

  @override
  void initState() {
    super.initState();
    () async {
      final savedLength = await lock.pinLength();
      final state = await lock.lockoutState();
      if (mounted) {
        setState(() {
          length = savedLength ?? 6;
          legacy = savedLength == null;
          blockedUntil = state.blockedUntil;
        });
      }
    }();
    countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && blockedUntil != null) setState(() {});
    });
  }

  @override
  void dispose() {
    countdown?.cancel();
    super.dispose();
  }

  Future<void> add(String digit) async {
    if (busy || entry.length >= length) return;
    final next = '$entry$digit';
    setState(() {
      entry = next;
      error = null;
    });
    if (next.length < length || legacy) return;
    await submit(next);
  }

  Future<void> submit(String pin) async {
    if (busy || (blockedUntil?.isAfter(DateTime.now()) ?? false)) return;
    setState(() => busy = true);
    try {
      final attempt = await lock.tryPin(pin);
      if (!mounted) return;
      if (attempt.success) {
        Navigator.pop(context, true);
      } else {
        final wait = attempt.lockout.remainingAt(DateTime.now());
        setState(() {
          entry = '';
          blockedUntil = attempt.lockout.blockedUntil;
          error = wait > Duration.zero
              ? 'Too many attempts. Try again later.'
              : 'That PIN is not correct.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wait = blockedUntil?.difference(DateTime.now()) ?? Duration.zero;
    final blocked = wait > Duration.zero;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Enter your current PIN',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 30),
                PinKeypad(
                  length: length,
                  value: entry,
                  enabled: !busy && !blocked,
                  onDigit: add,
                  onBackspace: () => setState(() {
                    if (entry.isNotEmpty) {
                      entry = entry.substring(0, entry.length - 1);
                    }
                  }),
                ),
                if (blocked) Text('Try again in ${wait.inSeconds + 1}s'),
                if (legacy)
                  TextButton(
                    onPressed: entry.length >= 4 && !blocked && !busy
                        ? () => submit(entry)
                        : null,
                    child: const Text('Continue'),
                  ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
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
