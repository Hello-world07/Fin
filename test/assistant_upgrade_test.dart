import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';
import 'package:personal_finance/src/features/assistant/assistant_commands.dart';
import 'package:personal_finance/src/features/assistant/assistant_engine.dart';
import 'package:personal_finance/src/features/assistant/assistant_math.dart';

void main() {
  final now = DateTime(2026, 10, 7);

  test(
    'safe maths handles percentages, grouping, Indian units, and errors',
    () {
      expect(evaluateAssistantMath('2+2'), 4);
      expect(evaluateAssistantMath('10000*12'), 120000);
      expect(evaluateAssistantMath('15% of 8000'), 1200);
      expect(evaluateAssistantMath('8000 + 18%'), 9440);
      expect(evaluateAssistantMath('8000 - 10%'), 7200);
      expect(evaluateAssistantMath('(500+250)/3'), 250);
      expect(evaluateAssistantMath('1.2k + 3k'), 4200);
      expect(evaluateAssistantMath('1 lakh + 2 cr'), 20100000);
      expect(() => evaluateAssistantMath('1/0'), throwsFormatException);
      expect(() => evaluateAssistantMath('1+bad'), throwsFormatException);
      expect(formatAssistantResult(10000), contains('Ten thousand'));
      expect(formatAssistantResult(20100000), contains('₹2,01,00,000'));
      expect(calculateAssistantEmiPaise(500000, 9, 60), greaterThan(0));
    },
  );

  test(
    'commands extract amount, name, kind, tenure, frequency and due date',
    () {
      final emi = parseAssistantCommand(
        'emi 5000 for 12 months due next friday',
        now,
      )!;
      expect(emi.draft.kind, AssistantFormKind.emi);
      expect(emi.draft.amountPaise, 500000);
      expect(emi.draft.tenureMonths, 12);
      expect(emi.draft.dueDate, DateTime(2026, 10, 9));
      expect(
        parseAssistantCommand('add 10000 to emi', now)!.draft.amountPaise,
        1000000,
      );
      expect(
        parseAssistantCommand('10000 add to emi', now)!.draft.amountPaise,
        1000000,
      );
      final given = parseAssistantCommand(
        'I gave Nivas 500 due tomorrow',
        now,
      )!;
      expect(given.draft.kind, AssistantFormKind.moneyGiven);
      expect(given.draft.name, 'Nivas');
      expect(given.draft.dueDate, DateTime(2026, 10, 8));
      expect(
        parseAssistantCommand('lent 2000 to Ravi', now)!.draft.name,
        'Ravi',
      );
      final borrowed = parseAssistantCommand(
        'borrowed 3000 from Sandeep',
        now,
      )!;
      expect(borrowed.draft.kind, AssistantFormKind.moneyBorrowed);
      expect(borrowed.draft.name, 'Sandeep');
      final subscription = parseAssistantCommand(
        'add subscription Netflix 649 monthly due 15 oct',
        now,
      )!;
      expect(subscription.draft.name, 'Netflix');
      expect(subscription.draft.frequency, PaymentFrequency.monthly);
      expect(subscription.draft.dueDate, DateTime(2026, 10, 15));
      expect(
        parseAssistantCommand('add 10000 to money', now)!.ambiguousMoney,
        isTrue,
      );
    },
  );

  test(
    'greetings, small talk, maths and commands produce offline replies',
    () async {
      final db = AppDatabase.test(NativeDatabase.memory());
      addTearDown(db.close);
      final engine = LocalAssistantEngine(FinanceRepository(db));
      final ctx = ConversationContext(now: now);
      final hello = await engine.ask('hello da', ctx);
      expect(hello.text, startsWith('Welcome to FinKeep!'));
      expect(hello.suggestions, hasLength(4));
      expect((await engine.ask('help', ctx)).text, contains('Maths:'));
      expect((await engine.ask('thank you', ctx)).text, contains('welcome'));
      expect(
        (await engine.ask('who are you', ctx)).text,
        contains('Ask FinKeep'),
      );
      final result = await engine.ask('15% of 8000', ctx);
      expect(result.text, contains('₹1,200'));
      expect(result.actions, hasLength(4));
      expect(
        (await engine.ask('emi for 500000 at 9% for 5 years', ctx)).text,
        contains('Estimated monthly EMI'),
      );
      expect(
        (await engine.ask('simple interest 10000 at 8% for 2 years', ctx)).text,
        contains('₹1,600'),
      );
      final bad = await engine.ask('3/0', ctx);
      expect(bad.text, contains('Division by zero'));
      final command = await engine.ask('I gave Nivas 500', ctx);
      expect(command.openForm!.name, 'Nivas');
      expect(command.openForm!.amountPaise, 50000);
      expect(
        (await engine.ask('add money', ctx)).text,
        contains('What amount'),
      );
      final ambiguous = await engine.ask('add 10000 to money', ctx);
      expect(ambiguous.suggestions, hasLength(2));
      final followup = await engine.ask(
        '2000',
        ConversationContext(now: now, previousQuestions: ['add emi']),
      );
      expect(followup.openForm?.amountPaise, 200000);
    },
  );

  test(
    'next EMI, incoming, pay range, follow-up and analysis use live data',
    () async {
      final db = AppDatabase.test(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = FinanceRepository(db);
      await repo.saveEmi(
        EmisCompanion.insert(
          name: 'Phone',
          principalPaise: 988860,
          emiAmountPaise: 500000,
          tenureMonths: 2,
          startDate: DateTime(2026, 10, 1),
          nextDueDate: DateTime(2026, 10, 1),
          frequency: PaymentFrequency.monthly,
          interestRate: const Value(9),
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
          personName: 'Ravi',
          direction: MoneyDirection.given,
          amountPaise: 5000,
          recordDate: now,
          status: MoneyStatus.active,
        ),
      );
      await repo.saveMoneyRecord(
        MoneyRecordsCompanion.insert(
          personName: 'Sandeep',
          direction: MoneyDirection.borrowed,
          amountPaise: 7500,
          recordDate: now,
          dueDate: Value(DateTime(2026, 10, 10)),
          status: MoneyStatus.active,
        ),
      );
      await repo.saveSubscription(
        SubscriptionsCompanion.insert(
          name: 'Netflix',
          amountPaise: 2000,
          frequency: PaymentFrequency.monthly,
          nextBillingDate: DateTime(2026, 10, 8),
          status: SubscriptionStatus.active,
        ),
      );
      final engine = LocalAssistantEngine(repo);
      final ctx = ConversationContext(now: now);
      final next = await engine.ask('when is my next EMI', ctx);
      expect(next.text, contains('01 Oct 2026'));
      expect(next.rows.first.value, '₹5,000');
      final incoming = await engine.ask(
        'how much will come to me this month',
        ctx,
      );
      expect(incoming.text, contains('₹100'));
      expect(incoming.rows.last.value, contains('₹50'));
      final pay = await engine.ask('how much do I need to pay this month', ctx);
      expect(pay.text, contains('₹95'));
      expect(pay.rows.last.value, '₹95');
      final status = await engine.ask('my financial status', ctx);
      expect(status.rows.first.value, '₹150');
      expect(
        status.rows.any(
          (row) =>
              row.label == 'Monthly recurring commitments' &&
              row.value == '₹5,020',
        ),
        isTrue,
      );
      final nextMonth = await engine.ask(
        'and next month?',
        ConversationContext(
          now: now,
          previousQuestions: ['how much do I need to pay this month'],
        ),
      );
      expect(nextMonth.text, contains('₹5,020'));
      final emiMonth = await engine.ask('next month emi amount', ctx);
      expect(emiMonth.text, contains('₹5,000'));
      final emiYear = await engine.ask('total emi this year', ctx);
      expect(emiYear.text, contains('₹10,000'));
      final person = await engine.ask('how much does Nivas owe me', ctx);
      expect(person.text, contains('₹100'));
      final analysis = await engine.ask('analyze my portfolio', ctx);
      expect(analysis.text, contains('Not financial advice'));
      expect(analysis.text, contains('highest recorded rate'));
      expect(
        analysis.rows.any((row) => row.label == 'Overdue payments'),
        isTrue,
      );
      expect(
        analysis.rows.any((row) => row.value.contains('above 40%')),
        isTrue,
      );
    },
  );
}
