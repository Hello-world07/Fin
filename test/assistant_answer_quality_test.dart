import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/features/assistant/assistant_actions.dart';
import 'package:personal_finance/src/features/assistant/assistant_answer_style.dart';
import 'package:personal_finance/src/features/assistant/assistant_engine.dart';
import 'package:personal_finance/src/features/assistant/assistant_planning.dart';
import 'package:personal_finance/src/features/assistant/assistant_visuals.dart';

void main() {
  test(
    'spoken and partial EMI names resolve without silently choosing ambiguity',
    () {
      const values = [
        AssistantEntityCandidate('Navi loan by me', 1),
        AssistantEntityCandidate('Navi dinesh', 2),
        AssistantEntityCandidate('Slice', 3),
      ];
      expect(
        resolveAssistantEntity(
          'we loan app',
          values,
        ).ambiguous.map((e) => e.value),
        contains(1),
      );
      expect(resolveAssistantEntity('Navi', values).ambiguous, hasLength(2));
      expect(resolveAssistantEntity('Slic', values).match?.value, 3);
    },
  );

  test('extra-payment variations enter what-if preview', () {
    for (final phrase in [
      'pay 500 more on Navi',
      'prepay 500 on Navi',
      'pay now extra 500 on Navi',
    ]) {
      final request = parseWhatIf(phrase);
      expect(request?.kind, WhatIfKind.extraEmi);
      expect(request?.amountPaise, 50000);
    }
  });

  test('phrasing changes and repeated unchanged answer is acknowledged', () {
    final style = AssistantAnswerStyle();
    final now = DateTime(2026, 10, 9, 12);
    const reply = AssistantReply(
      'Your total is ₹100.',
      rows: [AssistantRow('Total', '₹100')],
    );
    final first = style.apply(AssistantIntent.status, 'my status', reply, now);
    final second = style.apply(
      AssistantIntent.status,
      'my status',
      reply,
      now.add(const Duration(seconds: 20)),
    );
    expect(first.text, isNot(second.text));
    expect(second.text, contains('Still the same'));
    final changed = style.apply(
      AssistantIntent.status,
      'my status',
      const AssistantReply('Your total is ₹200.'),
      now.add(const Duration(seconds: 30)),
    );
    expect(changed.text, isNot(contains('Still the same')));
  });

  test('weekly chart builder preserves total and overdue marking', () {
    final chart = buildWeeklyChartData([
      AssistantDatedAmount(DateTime(2026, 10, 8), 5000, overdue: true),
      AssistantDatedAmount(DateTime(2026, 10, 20), 12000),
    ], DateTime(2026, 10, 9));
    expect(chart.fold<double>(0, (sum, bar) => sum + bar.value), 17000);
    expect(chart.first.isOverdue, isTrue);
  });
}
