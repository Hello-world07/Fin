import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';
import 'package:personal_finance/src/features/dashboard/home_overview.dart';

void main() {
  test(
    'repayments stay on their transaction date and balance on its due date',
    () async {
      final database = AppDatabase.test(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = FinanceRepository(database);
      final id = await repository.saveMoneyRecord(
        MoneyRecordsCompanion.insert(
          personName: 'Dinesh',
          direction: MoneyDirection.given,
          amountPaise: 300000,
          recordDate: DateTime(2026, 10, 10),
          dueDate: Value(DateTime(2026, 10, 25)),
          status: MoneyStatus.active,
        ),
      );
      await repository.addRepayment(id, 150000, null, DateTime(2026, 10, 12));

      final activity = await repository.watchActivity().first;
      expect(
        activity
            .where((entry) => entry.type == ActivityType.moneyGiven)
            .single
            .occurredAt,
        DateTime(2026, 10, 10),
      );
      expect(
        activity
            .where((entry) => entry.type == ActivityType.moneyRepayment)
            .single
            .occurredAt,
        DateTime(2026, 10, 12),
      );

      final detail = await repository.moneyDetail(id);
      final overview = HomeOverview.build(
        const [],
        [detail],
        const [],
        DateTime(2026, 10, 19),
      );
      expect(overview.toCollect, 150000);
      expect(overview.dues, hasLength(1));
      expect(overview.dues.single.date, DateTime(2026, 10, 25));
      expect(overview.dues.single.amount, 150000);
      expect(
        overview.dues.where((due) => due.date == DateTime(2026, 10, 19)),
        isEmpty,
      );
    },
  );
}
