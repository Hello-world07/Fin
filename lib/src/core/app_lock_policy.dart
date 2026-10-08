enum AutoLockDelay {
  immediately(Duration.zero, 'Immediately'),
  thirtySeconds(Duration(seconds: 30), '30 seconds'),
  oneMinute(Duration(minutes: 1), '1 minute'),
  fiveMinutes(Duration(minutes: 5), '5 minutes');

  const AutoLockDelay(this.duration, this.label);
  final Duration duration;
  final String label;
}

bool shouldLockAfterBackground({
  required bool enabled,
  required bool wasBackgrounded,
  required DateTime? backgroundedAt,
  required DateTime resumedAt,
  required AutoLockDelay delay,
  required bool isSuppressed,
}) =>
    enabled &&
    wasBackgrounded &&
    backgroundedAt != null &&
    !isSuppressed &&
    resumedAt.difference(backgroundedAt) >= delay.duration;

class PinLockoutState {
  const PinLockoutState({this.failures = 0, this.level = 0, this.blockedUntil});

  final int failures;
  final int level;
  final DateTime? blockedUntil;

  Duration remainingAt(DateTime now) {
    final until = blockedUntil;
    if (until == null || !until.isAfter(now)) return Duration.zero;
    return until.difference(now);
  }

  PinLockoutState recordFailure(DateTime now) {
    if (remainingAt(now) > Duration.zero) return this;
    final nextFailures = failures + 1;
    if (nextFailures < 5) {
      return PinLockoutState(failures: nextFailures, level: level);
    }
    final nextLevel = level + 1;
    final wait = switch (nextLevel) {
      1 => const Duration(seconds: 30),
      2 => const Duration(minutes: 1),
      _ => const Duration(minutes: 5),
    };
    return PinLockoutState(level: nextLevel, blockedUntil: now.add(wait));
  }
}
