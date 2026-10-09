import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'app_lock.dart';
import 'pin_keypad.dart';

class PrivacyRevealGate {
  PrivacyRevealGate._();
  static final instance = PrivacyRevealGate._();

  bool requiresUnlock = false;
  DateTime? _authorizedUntil;

  void clearGrace() => _authorizedUntil = null;

  Future<bool> ensurePin(BuildContext context) async {
    final lock = PinLockService();
    if (await lock.hasPin()) return true;
    if (!context.mounted) return false;
    final setUp = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Set a PIN first'),
        content: const Text(
          'A PIN is needed before amounts can require an unlock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Set PIN'),
          ),
        ],
      ),
    );
    if (setUp != true || !context.mounted) return false;
    final pin = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const PinSetupScreen()));
    if (pin == null) return false;
    await lock.setPin(pin);
    return true;
  }

  Future<bool> authorize(BuildContext context) async {
    if (!requiresUnlock ||
        (_authorizedUntil?.isAfter(DateTime.now()) ?? false)) {
      return true;
    }
    if (!await ensurePin(context) || !context.mounted) return false;
    final allowed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _PrivacyUnlockSheet(),
    );
    if (allowed == true) {
      _authorizedUntil = DateTime.now().add(const Duration(seconds: 30));
      return true;
    }
    return false;
  }
}

class _PrivacyUnlockSheet extends StatefulWidget {
  const _PrivacyUnlockSheet();

  @override
  State<_PrivacyUnlockSheet> createState() => _PrivacyUnlockSheetState();
}

class _PrivacyUnlockSheetState extends State<_PrivacyUnlockSheet> {
  final _lock = PinLockService();
  final _auth = LocalAuthentication();
  int _length = 4;
  bool _legacy = false;
  bool _biometric = false;
  bool _busy = true;
  String _entry = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final length = await _lock.pinLength();
    var biometricsAvailable = false;
    try {
      biometricsAvailable = (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      // PIN remains available if the biometric service is unavailable.
    }
    if (mounted) {
      setState(() {
        _length = length ?? 6;
        _legacy = length == null;
        _biometric = biometricsAvailable;
        _busy = false;
      });
    }
  }

  Future<void> _digit(String digit) async {
    if (_busy || _entry.length >= _length) return;
    setState(() {
      _entry += digit;
      _error = null;
    });
    if (_entry.length == _length && !_legacy) await _verify();
  }

  Future<void> _verify() async {
    if (_busy) return;
    setState(() => _busy = true);
    final attempt = await _lock.tryPin(_entry);
    if (!mounted) return;
    if (attempt.success) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _entry = '';
        final wait = attempt.lockout.remainingAt(DateTime.now());
        _error = wait > Duration.zero
            ? 'Too many attempts. Try again later.'
            : 'Incorrect PIN';
      });
    }
  }

  Future<void> _useBiometric() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final allowed = await AppLockSession.instance.keepUnlocked(
        () => _auth.authenticate(
          localizedReason: 'Reveal FinKeep amounts',
          biometricOnly: true,
        ),
      );
      if (mounted && allowed) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Biometric unlock unavailable');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: 0.78,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        children: [
          Text('Unlock amounts', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          PinKeypad(
            length: _length,
            value: _entry,
            enabled: !_busy,
            onDigit: _digit,
            onBackspace: () {
              if (_entry.isNotEmpty) {
                setState(() => _entry = _entry.substring(0, _entry.length - 1));
              }
            },
          ),
          if (_legacy)
            TextButton(
              onPressed: _entry.length >= 4 ? _verify : null,
              child: const Text('Continue'),
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_biometric)
            TextButton.icon(
              onPressed: _busy ? null : _useBiometric,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Use fingerprint / face'),
            ),
        ],
      ),
    ),
  );
}
