import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';
import 'package:personal_finance/src/features/assistant/assistant_actions.dart';
import 'package:personal_finance/src/features/assistant/assistant_engine.dart';
import 'package:personal_finance/src/features/assistant/assistant_visuals.dart';

void main() {
  test('action parser handles supported wording, typos and values', () {
    expect(
      parseAssistantActionCommand('puase Netflix for 2 months')!.kind,
      AssistantMutationKind.pauseSubscription,
    );
    expect(
      parseAssistantActionCommand('change Wifi to 600')!.amountPaise,
      60000,
    );
    expect(
      parseAssistantActionCommand(
        'mark January installment paid early',
      )!.installmentMonth,
      1,
    );
    expect(
      parseAssistantActionCommand('Nivas gave back 100')!.amountPaise,
      10000,
    );
    expect(
      parseAssistantActionCommand(
        'extend Nivas due date by 7 days',
      )!.extendDays,
      7,
    );
  });

  test('entity resolution returns exact, ambiguous and closest results', () {
    const values = [
      AssistantEntityCandidate('Wifi Home', 1),
      AssistantEntityCandidate('Wifi Office', 2),
      AssistantEntityCandidate('Netflix', 3),
    ];
    expect(resolveAssistantEntity('netflx', values).match?.value, 3);
    expect(resolveAssistantEntity('wifi', values).ambiguous, hasLength(2));
    expect(resolveAssistantEntity('prime', values).suggestions, hasLength(3));
  });

  test(
    'text creates confirmation; repository changes only after confirm',
    () async {
      final db = AppDatabase.test(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = FinanceRepository(db);
      final id = await repo.saveSubscription(
        SubscriptionsCompanion.insert(
          name: 'Wifi',
          amountPaise: 50000,
          frequency: PaymentFrequency.monthly,
          nextBillingDate: DateTime(2026, 10, 15),
          status: SubscriptionStatus.active,
        ),
      );
      final engine = LocalAssistantEngine(repo);
      final reply = await engine.ask(
        'pause Wifi',
        ConversationContext(now: DateTime(2026, 10, 8)),
      );
      expect(reply.confirmation, isNotNull);
      expect((await repo.subscription(id))!.status, SubscriptionStatus.active);

      final result = await engine.confirm(reply.confirmation!);
      expect((await repo.subscription(id))!.status, SubscriptionStatus.paused);
      expect(result.undoMutation, isNotNull);
      await engine.undo(result.undoMutation!);
      expect((await repo.subscription(id))!.status, SubscriptionStatus.active);
      final analysis = await engine.ask(
        'analyze my portfolio',
        ConversationContext(now: DateTime(2026, 10, 8)),
      );
      expect(analysis.visuals, hasLength(7));
      expect(
        analysis.visuals.map((part) => part.kind),
        contains(AssistantVisualKind.scoreRing),
      );
    },
  );

  test('repayment undo restores the prior outstanding balance', () async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = FinanceRepository(db);
    final id = await repo.saveMoneyRecord(
      MoneyRecordsCompanion.insert(
        personName: 'Nivas',
        direction: MoneyDirection.given,
        amountPaise: 10000,
        recordDate: DateTime(2026, 10, 8),
        status: MoneyStatus.active,
      ),
    );
    final engine = LocalAssistantEngine(repo);
    final proposal = await engine.ask(
      'Nivas paid 50',
      ConversationContext(now: DateTime(2026, 10, 8)),
    );
    expect((await repo.moneyDetail(id)).summary.remainingAmountPaise, 10000);
    final result = await engine.confirm(proposal.confirmation!);
    expect((await repo.moneyDetail(id)).summary.remainingAmountPaise, 5000);
    await engine.undo(result.undoMutation!);
    expect((await repo.moneyDetail(id)).summary.remainingAmountPaise, 10000);
  });

  test('delete confirmation archives and Restore returns the record', () async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = FinanceRepository(db);
    await repo.saveMoneyRecord(
      MoneyRecordsCompanion.insert(
        personName: 'Nivas',
        direction: MoneyDirection.given,
        amountPaise: 5000,
        recordDate: DateTime(2026, 10, 8),
        status: MoneyStatus.active,
      ),
    );
    final engine = LocalAssistantEngine(repo);
    final proposal = await engine.ask(
      'delete Nivas money',
      ConversationContext(now: DateTime(2026, 10, 8)),
    );
    expect(await repo.moneyDetails(), hasLength(1));
    final deleted = await engine.confirm(proposal.confirmation!);
    expect(await repo.moneyDetails(), isEmpty);
    expect(deleted.undoMutation!.restore, isTrue);
    await engine.undo(deleted.undoMutation!);
    expect(await repo.moneyDetails(), hasLength(1));
  });

  test('health score is deterministic and excludes backup freshness', () {
    final healthy = calculateAssistantHealthScore(
      const AssistantHealthInput(
        emiShare: 0.3,
        overdueCount: 0,
        undatedLentShare: 0,
        subscriptionShare: 0.1,
      ),
    );
    final pressured = calculateAssistantHealthScore(
      const AssistantHealthInput(
        emiShare: 0.7,
        overdueCount: 2,
        undatedLentShare: 0.5,
        subscriptionShare: 0.4,
      ),
    );
    expect(healthy.score, 100);
    expect(pressured.score, 50);
    expect(
      healthy.factors.map((item) => item.label),
      isNot(contains('Backup')),
    );
  });

  test('weekly chart builder groups overdue and next 30 days', () {
    final now = DateTime(2026, 10, 8);
    final data = buildWeeklyChartData([
      AssistantDatedAmount(DateTime(2026, 10, 7), 1000),
      AssistantDatedAmount(DateTime(2026, 10, 10), 2000),
      AssistantDatedAmount(DateTime(2026, 10, 20), 3000),
    ], now);
    expect(data, hasLength(5));
    expect(data.first.value, 3000);
    expect(data.first.isOverdue, isTrue);
    expect(data[1].value, 3000);
  });
}
