import 'dart:async';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'providers.dart';

class AppLockSettings {
  const AppLockSettings({this.enabled = false, this.biometricEnabled = false});

  final bool enabled;
  final bool biometricEnabled;
}

const appLockGracePeriod = Duration(minutes: 1);

bool isAppBackgroundingState(AppLifecycleState state) =>
    state == AppLifecycleState.paused ||
    state == AppLifecycleState.hidden ||
    state == AppLifecycleState.detached;

bool shouldLockOnResume({
  required bool enabled,
  required bool wasBackgrounded,
  required DateTime? backgroundedAt,
  required DateTime resumedAt,
  required bool isSuppressed,
}) =>
    enabled &&
    wasBackgrounded &&
    backgroundedAt != null &&
    resumedAt.difference(backgroundedAt) >= appLockGracePeriod &&
    !isSuppressed;

bool supportsBiometricUnlock({
  required bool deviceSupported,
  required bool canCheckBiometrics,
  required bool hasEnrolledBiometric,
}) => deviceSupported && canCheckBiometrics && hasEnrolledBiometric;

class AppLockSession {
  AppLockSession._();
  static final instance = AppLockSession._();

  int _foregroundOperationCount = 0;
  bool get suppressBackgroundLock => _foregroundOperationCount > 0;

  Future<T> keepUnlocked<T>(Future<T> Function() operation) async {
    _foregroundOperationCount++;
    try {
      return await operation();
    } finally {
      _foregroundOperationCount--;
    }
  }
}

final appLockSettingsProvider = FutureProvider<AppLockSettings>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.select(db.settings).get();
  final values = {for (final row in rows) row.key: row.value};
  return AppLockSettings(
    enabled: values['privacy.appLock.enabled'] == 'true',
    biometricEnabled: values['privacy.appLock.biometric'] == 'true',
  );
});

class PinLockService {
  PinLockService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _saltKey = 'finkeep.lock.pinSalt';
  static const _hashKey = 'finkeep.lock.pinHash';
  static const _iterations = 60000;
  final FlutterSecureStorage _storage;

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      throw const FormatException('Choose a PIN with 4 to 6 digits.');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final hash = await derivePinHash(pin, salt, iterations: _iterations);
    await _storage.write(key: _saltKey, value: _hex(salt));
    await _storage.write(key: _hashKey, value: hash);
  }

  Future<bool> verifyPin(String pin) async {
    final saltHex = await _storage.read(key: _saltKey);
    final expected = await _storage.read(key: _hashKey);
    if (saltHex == null || expected == null) return false;
    final actual = await derivePinHash(
      pin,
      _fromHex(saltHex),
      iterations: _iterations,
    );
    return _constantTimeEquals(actual, expected);
  }

  Future<void> clearPin() async {
    await _storage.delete(key: _saltKey);
    await _storage.delete(key: _hashKey);
  }

  static Future<String> derivePinHash(
    String pin,
    List<int> salt, {
    int iterations = _iterations,
  }) async {
    final hmac = Hmac(sha256, pin.codeUnits);
    final blockInput = Uint8List.fromList([...salt, 0, 0, 0, 1]);
    var u = hmac.convert(blockInput).bytes;
    final result = List<int>.from(u);
    for (var round = 1; round < iterations; round++) {
      u = hmac.convert(u).bytes;
      for (var i = 0; i < result.length; i++) {
        result[i] ^= u[i];
      }
      if (round % 1000 == 0) await Future<void>.delayed(Duration.zero);
    }
    return _hex(result);
  }

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _fromHex(String value) => [
    for (var i = 0; i + 1 < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ];

  static bool _constantTimeEquals(String a, String b) {
    var mismatch = a.length ^ b.length;
    final length = max(a.length, b.length);
    for (var i = 0; i < length; i++) {
      mismatch |=
          (i < a.length ? a.codeUnitAt(i) : 0) ^
          (i < b.length ? b.codeUnitAt(i) : 0);
    }
    return mismatch == 0;
  }
}

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  final _lock = PinLockService();
  final _pinController = TextEditingController();
  final _auth = LocalAuthentication();
  bool _ready = false;
  bool _enabled = false;
  bool _biometric = false;
  bool _locked = false;
  bool _pendingLock = false;
  DateTime? _backgroundedAt;
  bool _busy = false;
  bool _showPin = false;
  String? _error;
  int _failedAttempts = 0;
  DateTime? _blockedUntil;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_readSettings(lockImmediately: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pinController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (isAppBackgroundingState(state)) {
      if (_enabled && !AppLockSession.instance.suppressBackgroundLock) {
        _backgroundedAt ??= DateTime.now();
        _pendingLock = true;
      }
    } else if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      final shouldLock = shouldLockOnResume(
        enabled: _enabled,
        wasBackgrounded: _pendingLock,
        backgroundedAt: backgroundedAt,
        resumedAt: DateTime.now(),
        isSuppressed: AppLockSession.instance.suppressBackgroundLock,
      );
      unawaited(_readSettings(lockImmediately: shouldLock));
      _pendingLock = false;
      _backgroundedAt = null;
    }
  }

  Future<void> _readSettings({required bool lockImmediately}) async {
    try {
      final rows = await ref
          .read(databaseProvider)
          .select(ref.read(databaseProvider).settings)
          .get();
      final values = {for (final row in rows) row.key: row.value};
      final biometricEnabled = values['privacy.appLock.biometric'] == 'true';
      var biometricAvailable = false;
      if (biometricEnabled) {
        try {
          biometricAvailable = supportsBiometricUnlock(
            deviceSupported: await _auth.isDeviceSupported(),
            canCheckBiometrics: await _auth.canCheckBiometrics,
            hasEnrolledBiometric:
                (await _auth.getAvailableBiometrics()).isNotEmpty,
          );
        } catch (_) {
          biometricAvailable = false;
        }
      }
      if (!mounted) return;
      setState(() {
        _enabled = values['privacy.appLock.enabled'] == 'true';
        _biometric = biometricAvailable;
        if (_enabled && lockImmediately) _locked = true;
        if (!_enabled) _locked = false;
        _ready = true;
      });
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
  }

  Future<void> _unlockWithPin() async {
    if (_busy) return;
    if (_blockedUntil case final until? when until.isAfter(DateTime.now())) {
      setState(() => _error = 'Too many attempts. Try again in 30 seconds.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (await _lock.verifyPin(_pinController.text)) {
        _failedAttempts = 0;
        _blockedUntil = null;
        if (mounted) {
          setState(() {
            _locked = false;
            _pinController.clear();
          });
        }
      } else if (mounted) {
        _failedAttempts++;
        if (_failedAttempts >= 5) {
          _failedAttempts = 0;
          _blockedUntil = DateTime.now().add(const Duration(seconds: 30));
          setState(
            () => _error = 'Too many attempts. Try again in 30 seconds.',
          );
        } else {
          setState(() => _error = 'That PIN is not correct.');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not verify the PIN. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlockBiometric() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await AppLockSession.instance.keepUnlocked(
        () => _auth.authenticate(
          localizedReason: 'Unlock FinKeep',
          biometricOnly: true,
        ),
      );
      if (ok && mounted) setState(() => _locked = false);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Biometric unlock was unavailable. Use your PIN.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appLockSettingsProvider, (previous, next) {
      next.whenData((_) => unawaited(_readSettings(lockImmediately: false)));
    });
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_enabled || !_locked) return widget.child;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 42,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Unlock FinKeep',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    obscureText: !_showPin,
                    maxLength: 6,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      errorText: _error,
                      counterText: '',
                      suffixIcon: IconButton(
                        tooltip: _showPin ? 'Hide PIN' : 'Show PIN',
                        onPressed: () => setState(() => _showPin = !_showPin),
                        icon: Icon(
                          _showPin ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _unlockWithPin(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _unlockWithPin,
                    child: Text(_busy ? 'Checking...' : 'Unlock'),
                  ),
                  if (_biometric) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _busy ? null : _unlockBiometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Use biometrics'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
