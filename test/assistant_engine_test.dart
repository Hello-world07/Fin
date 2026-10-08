import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';
import 'package:personal_finance/src/features/assistant/assistant_engine.dart';

void main() {
  final now = DateTime(2026, 10, 7);

  test('matches English, Hinglish, person names, and a light typo', () {
    expect(
      matchAssistantIntent('What is my net position?', const []).intent,
      AssistantIntent.status,
    );
    expect(
      matchAssistantIntent('kitna baki EMI hai?', const []).intent,
      AssistantIntent.emi,
    );
    expect(
      matchAssistantIntent('udhar kitna baki?', const []).intent,
      AssistantIntent.owe,
    );
    expect(
      matchAssistantIntent('EMI kab due hai?', const []).intent,
      AssistantIntent.nextEmi,
    );
    expect(
      matchAssistantIntent('next 10 days', const []).intent,
      AssistantIntent.due,
    );
    expect(
      matchAssistantIntent('subscrption cost', const []).intent,
      AssistantIntent.subscriptions,
    );
    final person = matchAssistantIntent('Nivas ka balance?', const ['Nivas']);
    expect(person.intent, AssistantIntent.personBalance);
    expect(person.personName, 'Nivas');
    expect(
      matchAssistantIntent('purple elephant', const []).intent,
      AssistantIntent.unknown,
    );
  });

  test('parses common time phrases against a fixed date', () {
    expect(parseAssistantDateRange('today', now).end, now);
    expect(parseAssistantDateRange('tomorrow', now).end, DateTime(2026, 10, 8));
    expect(
      parseAssistantDateRange('this week', now).end,
      DateTime(2026, 10, 11),
    );
    expect(
      parseAssistantDateRange('this month', now).end,
      DateTime(2026, 10, 31),
    );
    expect(
      parseAssistantDateRange('next month', now).end,
      DateTime(2026, 11, 30),
    );
    expect(
      parseAssistantDateRange('next 10 days', now).end,
      DateTime(2026, 10, 17),
    );
    expect(
      parseAssistantDateRange('due by 15 Oct', now).end,
      DateTime(2026, 10, 15),
    );
    expect(
      parseAssistantDateRange('due by 15/10/2026', now).end,
      DateTime(2026, 10, 15),
    );
  });

  test(
    'calculates net position, due total, and debt-free date from fixed data',
    () async {
      final db = AppDatabase.test(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = FinanceRepository(db);
      await repo.saveEmi(
        EmisCompanion.insert(
          name: 'Phone',
          principalPaise: 1000000,
          emiAmountPaise: 500000,
          tenureMonths: 2,
          startDate: DateTime(2026, 10, 1),
          nextDueDate: DateTime(2026, 10, 1),
          frequency: PaymentFrequency.monthly,
          status: EmiStatus.active,
        ),
      );
      await repo.saveMoneyRecord(
        MoneyRecordsCompanion.insert(
          personName: 'Nivas',
          direction: MoneyDirection.given,
          amountPaise: 10000,
          recordDate: now,
          dueDate: Value(DateTime(2026, 10, 15)),
          status: MoneyStatus.active,
        ),
      );
      await repo.saveMoneyRecord(
        MoneyRecordsCompanion.insert(
          personName: 'Asha',
          direction: MoneyDirection.borrowed,
          amountPaise: 5000,
          recordDate: now,
          dueDate: Value(DateTime(2026, 10, 10)),
          status: MoneyStatus.active,
        ),
      );
      await repo.saveSubscription(
        SubscriptionsCompanion.insert(
          name: 'Music',
          amountPaise: 2000,
          frequency: PaymentFrequency.monthly,
          nextBillingDate: DateTime(2026, 10, 8),
          status: SubscriptionStatus.active,
        ),
      );

      final facts = FinanceFacts(
        emis: await repo.watchEmiDetails().first,
        money: await repo.moneyDetails(),
        subscriptions: await repo.watchSubscriptions().first,
        now: now,
      );
      expect(facts.netPositionPaise, 5000);
      expect(facts.totalDebtPaise, 1005000);
      expect(facts.totalDueInRange(now, DateTime(2026, 10, 31)), 7000);
      expect(
        facts.totalDueInRange(
          now,
          DateTime(2026, 10, 31),
          includeOverdue: true,
        ),
        507000,
      );
      expect(
        facts.totalDueInRange(
          DateTime(2026, 11, 1),
          DateTime(2026, 11, 30),
          includeOverdue: true,
        ),
        1002000,
      );
      expect(facts.debtFreeDate, DateTime(2026, 11, 1));

      final engine = LocalAssistantEngine(repo);
      final due = await engine.ask(
        'What is due this month?',
        ConversationContext(now: now),
      );
      expect(due.text, contains('₹5,070'));
      final person = await engine.ask(
        'Nivas balance',
        ConversationContext(now: now),
      );
      expect(person.rows.first.value, '₹100');
      final priority = await engine.ask(
        'Which debt should I clear first?',
        ConversationContext(now: now),
      );
      expect(priority.text, contains('smallest-balance rule'));
      expect(priority.text, contains('Asha'));
      final unknown = await engine.ask(
        'purple elephant',
        ConversationContext(now: now),
      );
      expect(unknown.suggestions, hasLength(3));
      final invalidDate = await engine.ask(
        'due by 31 Feb 2026',
        ConversationContext(now: now),
      );
      expect(invalidDate.text, contains('could not read that date'));
    },
  );
}
