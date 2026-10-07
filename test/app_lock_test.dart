import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import 'package:personal_finance/src/core/app_lock.dart';

void main() {
  test('PIN derivation is salted and does not store the raw PIN', () async {
    const salt = [1, 2, 3, 4, 5, 6, 7, 8];
    final first = await PinLockService.derivePinHash(
      '1234',
      salt,
      iterations: 1000,
    );
    final second = await PinLockService.derivePinHash('1234', const [
      8,
      7,
      6,
      5,
      4,
      3,
      2,
      1,
    ], iterations: 1000);

    expect(first, isNot('1234'));
    expect(first, hasLength(64));
    expect(second, isNot(first));
  });

  test('only real background lifecycle states can start a lock interval', () {
    expect(isAppBackgroundingState(AppLifecycleState.inactive), isFalse);
    expect(isAppBackgroundingState(AppLifecycleState.resumed), isFalse);
    expect(isAppBackgroundingState(AppLifecycleState.paused), isTrue);
    expect(isAppBackgroundingState(AppLifecycleState.hidden), isTrue);
  });

  test('app lock allows short app switches and relocks after one minute', () {
    final leftAt = DateTime(2026, 10, 5, 10);
    expect(
      shouldLockOnResume(
        enabled: true,
        wasBackgrounded: true,
        backgroundedAt: leftAt,
        resumedAt: leftAt.add(const Duration(seconds: 1)),
        isSuppressed: false,
      ),
      isFalse,
    );
    expect(
      shouldLockOnResume(
        enabled: true,
        wasBackgrounded: true,
        backgroundedAt: leftAt,
        resumedAt: leftAt.add(const Duration(minutes: 1)),
        isSuppressed: true,
      ),
      isFalse,
    );
    expect(
      shouldLockOnResume(
        enabled: true,
        wasBackgrounded: true,
        backgroundedAt: leftAt,
        resumedAt: leftAt.add(const Duration(minutes: 1)),
        isSuppressed: false,
      ),
      isTrue,
    );
  });

  test('biometric option requires a supported enrolled biometric', () {
    expect(
      supportsBiometricUnlock(
        deviceSupported: true,
        canCheckBiometrics: true,
        hasEnrolledBiometric: true,
      ),
      isTrue,
    );
    expect(
      supportsBiometricUnlock(
        deviceSupported: true,
        canCheckBiometrics: true,
        hasEnrolledBiometric: false,
      ),
      isFalse,
    );
    expect(
      supportsBiometricUnlock(
        deviceSupported: false,
        canCheckBiometrics: true,
        hasEnrolledBiometric: true,
      ),
      isFalse,
    );
  });

  test(
    'foreground system operation suppresses background lock until closed',
    () async {
      final done = Completer<void>();
      final operation = AppLockSession.instance.keepUnlocked(() => done.future);
      expect(AppLockSession.instance.suppressBackgroundLock, isTrue);
      done.complete();
      await operation;
      expect(AppLockSession.instance.suppressBackgroundLock, isFalse);
    },
  );
}
