import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'providers.dart';
import 'app_lock_policy.dart';
import 'pin_keypad.dart';
import 'formatters.dart';

class AppLockSettings {
  const AppLockSettings({
    this.enabled = false,
    this.biometricEnabled = false,
    this.autoBiometric = false,
    this.secureScreen = false,
    this.delay = AutoLockDelay.oneMinute,
  });

  final bool enabled;
  final bool biometricEnabled;
  final bool autoBiometric;
  final bool secureScreen;
  final AutoLockDelay delay;
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
  AutoLockDelay delay = AutoLockDelay.oneMinute,
}) => shouldLockAfterBackground(
  enabled: enabled,
  wasBackgrounded: wasBackgrounded,
  backgroundedAt: backgroundedAt,
  resumedAt: resumedAt,
  delay: delay,
  isSuppressed: isSuppressed,
);

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
    autoBiometric: values['privacy.appLock.autoBiometric'] == 'true',
    secureScreen: values['privacy.appLock.secureScreen'] == 'true',
    delay: AutoLockDelay.values.firstWhere(
      (item) => item.name == values['privacy.appLock.delay'],
      orElse: () => AutoLockDelay.oneMinute,
    ),
  );
});

class LockDisplayService {
  static const _channel = MethodChannel('finkeep/app_lock');

  static Future<void> setSecure(bool enabled) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('setSecure', enabled);
    }
  }

  static Future<void> openAppInfo() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('openAppInfo');
    }
  }
}

class PinAttempt {
  const PinAttempt(this.success, this.lockout);
  final bool success;
  final PinLockoutState lockout;
}

class PinLockService {
  PinLockService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _saltKey = 'finkeep.lock.pinSalt';
  static const _hashKey = 'finkeep.lock.pinHash';
  static const _fastHashKey = 'finkeep.lock.pinHashV2';
  static const _lengthKey = 'finkeep.lock.pinLength';
  static const _failuresKey = 'finkeep.lock.failures';
  static const _levelKey = 'finkeep.lock.level';
  static const _blockedKey = 'finkeep.lock.blockedUntil';
  static const _legacyIterations = 60000;
  static const _iterations = 18000;
  final FlutterSecureStorage _storage;
  Map<String, String>? _values;
  Future<void>? _warming;

  Future<void> warm() => _warming ??= _readAll();

  Future<void> refresh() {
    _warming = null;
    _values = null;
    return warm();
  }

  Future<void> _readAll() async {
    _values = await _storage.readAll();
  }

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^(\d{4}|\d{6})$').hasMatch(pin)) {
      throw const FormatException('Choose a 4 or 6 digit PIN.');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final hash = await derivePinHash(pin, salt, iterations: _iterations);
    await _storage.write(key: _saltKey, value: _hex(salt));
    await _storage.write(key: _fastHashKey, value: hash);
    await _storage.write(key: _lengthKey, value: pin.length.toString());
    _values?.addAll({
      _saltKey: _hex(salt),
      _fastHashKey: hash,
      _lengthKey: pin.length.toString(),
    });
    await _storage.delete(key: _hashKey);
    _values?.remove(_hashKey);
    await resetLockout();
  }

  Future<int?> pinLength() async {
    await warm();
    return int.tryParse(_values?[_lengthKey] ?? '');
  }

  Future<void> rememberPinLength(int length) async {
    _values?[_lengthKey] = length.toString();
    await _storage.write(key: _lengthKey, value: length.toString());
  }

  Future<PinLockoutState> lockoutState() async {
    await warm();
    return PinLockoutState(
      failures: int.tryParse(_values?[_failuresKey] ?? '') ?? 0,
      level: int.tryParse(_values?[_levelKey] ?? '') ?? 0,
      blockedUntil: DateTime.tryParse(_values?[_blockedKey] ?? ''),
    );
  }

  Future<PinAttempt> tryPin(String pin) async {
    final current = await lockoutState();
    if (current.remainingAt(DateTime.now()) > Duration.zero) {
      return PinAttempt(false, current);
    }
    if (await verifyPin(pin)) {
      unawaited(resetLockout().catchError((Object _) {}));
      return const PinAttempt(true, PinLockoutState());
    }
    final next = current.recordFailure(DateTime.now());
    _values?.addAll({
      _failuresKey: next.failures.toString(),
      _levelKey: next.level.toString(),
      if (next.blockedUntil != null)
        _blockedKey: next.blockedUntil!.toIso8601String(),
    });
    await _storage.write(key: _failuresKey, value: next.failures.toString());
    await _storage.write(key: _levelKey, value: next.level.toString());
    await _storage.write(
      key: _blockedKey,
      value: next.blockedUntil?.toIso8601String(),
    );
    return PinAttempt(false, next);
  }

  Future<void> resetLockout() async {
    _values?.remove(_failuresKey);
    _values?.remove(_levelKey);
    _values?.remove(_blockedKey);
    await _storage.delete(key: _failuresKey);
    await _storage.delete(key: _levelKey);
    await _storage.delete(key: _blockedKey);
  }

  Future<bool> verifyPin(String pin) async {
    await warm();
    final saltHex = _values?[_saltKey];
    final fastHash = _values?[_fastHashKey];
    final expected = fastHash ?? _values?[_hashKey];
    if (saltHex == null || expected == null) return false;
    final salt = _fromHex(saltHex);
    final actual = await derivePinHash(
      pin,
      salt,
      iterations: fastHash == null ? _legacyIterations : _iterations,
    );
    final matched = _constantTimeEquals(actual, expected);
    if (matched && fastHash == null) {
      unawaited(_upgradeHash(pin, salt, expected));
    }
    return matched;
  }

  Future<void> _upgradeHash(String pin, List<int> salt, String oldHash) async {
    try {
      final fastHash = await derivePinHash(pin, salt, iterations: _iterations);
      if (_values?[_hashKey] != oldHash || _values?[_saltKey] != _hex(salt)) {
        return;
      }
      if (await _storage.read(key: _saltKey) != _hex(salt)) return;
      await _storage.write(key: _fastHashKey, value: fastHash);
      _values?[_fastHashKey] = fastHash;
    } catch (_) {
      // The legacy hash remains valid if migration cannot complete.
    }
  }

  Future<void> clearPin() async {
    await _storage.delete(key: _saltKey);
    await _storage.delete(key: _hashKey);
    await _storage.delete(key: _fastHashKey);
    await _storage.delete(key: _lengthKey);
    _values?.remove(_saltKey);
    _values?.remove(_hashKey);
    _values?.remove(_fastHashKey);
    _values?.remove(_lengthKey);
    await resetLockout();
  }

  static Future<String> derivePinHash(
    String pin,
    List<int> salt, {
    int iterations = _iterations,
  }) => compute(_derivePinHashJob, (pin, salt, iterations));

  static String _derivePinHashJob((String, List<int>, int) input) {
    final (pin, salt, iterations) = input;
    final hmac = Hmac(sha256, pin.codeUnits);
    final blockInput = Uint8List.fromList([...salt, 0, 0, 0, 1]);
    var u = hmac.convert(blockInput).bytes;
    final result = List<int>.from(u);
    for (var round = 1; round < iterations; round++) {
      u = hmac.convert(u).bytes;
      for (var i = 0; i < result.length; i++) {
        result[i] ^= u[i];
      }
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
  final _auth = LocalAuthentication();
  Timer? _countdown;
  bool _ready = false;
  bool _settingsFailed = false;
  bool _enabled = false;
  bool _biometric = false;
  bool _autoBiometric = false;
  AutoLockDelay _delay = AutoLockDelay.oneMinute;
  int _pinLength = 6;
  bool _legacyPinLength = false;
  String _entry = '';
  bool _locked = false;
  bool _pendingLock = false;
  DateTime? _backgroundedAt;
  bool _busy = false;
  bool _homeWarmed = false;
  String? _error;
  DateTime? _blockedUntil;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(databaseProvider);
    ref.read(financeRepositoryProvider);
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _locked && _blockedUntil != null) setState(() {});
    });
    unawaited(_readSettings(lockImmediately: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdown?.cancel();
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
        delay: _delay,
      );
      if (shouldLock && mounted) {
        setState(() {
          _locked = true;
          _entry = '';
        });
      }
      unawaited(_readSettings(lockImmediately: shouldLock));
      _pendingLock = false;
      _backgroundedAt = null;
    }
  }

  Future<void> _readSettings({required bool lockImmediately}) async {
    try {
      final db = ref.read(databaseProvider);
      final rowsFuture = db.select(db.settings).get();
      final secureFuture = _lock.refresh();
      final rows = await rowsFuture;
      await secureFuture;
      final values = {for (final row in rows) row.key: row.value};
      final pinLength = await _lock.pinLength();
      final lockout = await _lock.lockoutState();
      final biometricEnabled = values['privacy.appLock.biometric'] == 'true';
      if (!mounted) return;
      try {
        await LockDisplayService.setSecure(
          values['privacy.appLock.secureScreen'] == 'true' ||
              privacyAmountsHidden,
        );
      } catch (_) {
        // The PIN screen remains available even if secure-window control fails.
      }
      final wasLocked = _locked;
      setState(() {
        _settingsFailed = false;
        _enabled = values['privacy.appLock.enabled'] == 'true';
        _biometric = false;
        _autoBiometric = values['privacy.appLock.autoBiometric'] == 'true';
        _delay = AutoLockDelay.values.firstWhere(
          (item) => item.name == values['privacy.appLock.delay'],
          orElse: () => AutoLockDelay.oneMinute,
        );
        _pinLength = pinLength ?? 6;
        _legacyPinLength = pinLength == null;
        _blockedUntil = lockout.blockedUntil;
        if (_enabled && lockImmediately) _locked = true;
        if (!_enabled) _locked = false;
        _ready = true;
      });
      if (_locked && !_homeWarmed) {
        _homeWarmed = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(dashboardProvider);
          ref.read(emiDetailsProvider);
          ref.read(moneyRecordsProvider);
          ref.read(subscriptionsProvider);
          ref.read(financialActionsProvider);
          ref.read(dashboardActivityProvider);
        });
      }
      if (biometricEnabled) {
        unawaited(_readBiometrics(autoPrompt: !wasLocked && _locked));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _ready = true;
          _settingsFailed = true;
        });
      }
    }
  }

  Future<void> _readBiometrics({required bool autoPrompt}) async {
    var available = false;
    try {
      available = supportsBiometricUnlock(
        deviceSupported: await _auth.isDeviceSupported(),
        canCheckBiometrics: await _auth.canCheckBiometrics,
        hasEnrolledBiometric: (await _auth.getAvailableBiometrics()).isNotEmpty,
      );
    } catch (_) {
      // PIN remains available when biometric services cannot be queried.
    }
    if (!mounted) return;
    setState(() => _biometric = available);
    if (autoPrompt && available && _autoBiometric && _locked) {
      unawaited(_unlockBiometric());
    }
  }

  void _addDigit(String digit) {
    if (_busy || _entry.length >= _pinLength) return;
    final next = '$_entry$digit';
    setState(() {
      _entry = next;
      _error = null;
    });
    if (_legacyPinLength && next.length == 4) {
      unawaited(_unlockWithPin(next, legacyProbe: true));
    } else if (next.length == _pinLength) {
      unawaited(_unlockWithPin(next));
    }
  }

  Future<void> _unlockWithPin(String pin, {bool legacyProbe = false}) async {
    if (_busy) return;
    if (_blockedUntil case final until? when until.isAfter(DateTime.now())) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final attempt = legacyProbe
          ? (await _lock.verifyPin(pin)
                ? const PinAttempt(true, PinLockoutState())
                : null)
          : await _lock.tryPin(pin);
      if (attempt == null) return;
      if (attempt.success) {
        if (mounted) {
          setState(() {
            _locked = false;
            _entry = '';
            _blockedUntil = null;
            _busy = false;
            if (legacyProbe) {
              _pinLength = pin.length;
              _legacyPinLength = false;
            }
          });
          if (legacyProbe) {
            unawaited(_lock.rememberPinLength(pin.length));
            unawaited(_lock.resetLockout().catchError((Object _) {}));
          }
        }
      } else if (mounted) {
        setState(() {
          _entry = '';
          _blockedUntil = attempt.lockout.blockedUntil;
          _error = _blockedUntil?.isAfter(DateTime.now()) == true
              ? 'Too many attempts. Wait before trying again.'
              : 'That PIN is not correct.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not verify the PIN. Try again.');
      }
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
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

  Future<void> _forgotPin(BuildContext lockContext) async {
    final confirmed = await showDialog<bool>(
      context: lockContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Forgot your PIN?'),
        content: const Text(
          'FinKeep cannot recover your PIN. The only reset is clearing app data in Android Settings, which permanently removes local records. After reopening FinKeep, use Restore from backup to recover a saved file. Continue to Android app settings?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Open app settings'),
          ),
        ],
      ),
    );
    if (confirmed == true) await LockDisplayService.openAppInfo();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appLockSettingsProvider, (previous, next) {
      next.whenData((_) => unawaited(_readSettings(lockImmediately: false)));
    });
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_settingsFailed) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not read app security settings.'),
              TextButton(
                onPressed: () => _readSettings(lockImmediately: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_enabled || !_locked) return widget.child;
    return Navigator(
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (lockContext) => _buildLockScreen(lockContext),
      ),
    );
  }

  Widget _buildLockScreen(BuildContext lockContext) {
    final wait = _blockedUntil?.difference(DateTime.now()) ?? Duration.zero;
    final blocked = wait > Duration.zero;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
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
                    'Unlock FinKeep',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  PinKeypad(
                    length: _pinLength,
                    value: _entry,
                    enabled: !_busy && !blocked,
                    onDigit: _addDigit,
                    onBackspace: () => setState(() {
                      if (_entry.isNotEmpty) {
                        _entry = _entry.substring(0, _entry.length - 1);
                      }
                    }),
                  ),
                  if (blocked)
                    Text(
                      'Try again in ${wait.inSeconds + 1}s',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (_biometric) ...[
                    TextButton.icon(
                      onPressed: _busy ? null : _unlockBiometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Use fingerprint / face'),
                    ),
                  ],
                  TextButton(
                    onPressed: () => _forgotPin(lockContext),
                    child: const Text('Forgot PIN?'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
