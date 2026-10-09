import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/features/assistant/assistant_planning.dart';

void main() {
  test('what-if commands parse amount, target and pause duration', () {
    final extra = parseWhatIf('what if I pay 5000 extra on Navi loan')!;
    expect(extra.kind, WhatIfKind.extraEmi);
    expect(extra.amountPaise, 500000);
    expect(extra.target, contains('navi'));
    expect(parseWhatIf('if I close Slice EMI now')!.kind, WhatIfKind.closeEmi);
    final pause = parseWhatIf('what if I pause WiFi for 3 months')!;
    expect(pause.kind, WhatIfKind.pauseSubscription);
    expect(pause.months, 3);
  });

  test(
    'extra EMI moves final installment earlier without inventing interest',
    () {
      final dates = [DateTime(2026, 11), DateTime(2026, 12), DateTime(2027, 1)];
      final result = calculateEmiWhatIf(
        remainingPaise: 3000000,
        installmentPaise: 1000000,
        unpaidDueDates: dates,
        extraPaise: 1000000,
        today: DateTime(2026, 10, 9),
      );
      expect(result.monthsSaved, 1);
      expect(result.newDebtFreeDate, DateTime(2026, 12));
      expect(result.interestSavedPaise, isNull);
      final close = calculateEmiWhatIf(
        remainingPaise: 3000000,
        installmentPaise: 1000000,
        unpaidDueDates: dates,
        extraPaise: 3000000,
        annualRate: 0,
        today: DateTime(2026, 10, 9),
      );
      expect(close.newDebtFreeDate, DateTime(2026, 10, 9));
      expect(close.interestSavedPaise, 0);
    },
  );

  test('reminder parser uses upcoming Friday and renewal offset', () {
    final now = DateTime(2026, 10, 9, 10);
    final friday = parseChatReminder('remind me to pay Nivas on Friday', now)!;
    expect(friday.target, 'nivas');
    expect(friday.when, DateTime(2026, 10, 16, 9));
    final renewal = parseChatReminder(
      'remind me 2 days before Wifi renews',
      now,
      renewalDate: DateTime(2026, 10, 20),
    )!;
    expect(renewal.isSubscription, isTrue);
    expect(renewal.when, DateTime(2026, 10, 18, 9));
  });
}
