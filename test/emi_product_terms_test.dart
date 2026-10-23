import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';

void main() {
  test(
    'editing product fees preserves contractual terms and payment history',
    () async {
      final db = AppDatabase.test(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = FinanceRepository(db);
      final due = DateTime(2026, 11, 1);
      final id = await repo.saveEmi(
        EmisCompanion.insert(
          name: 'Phone EMI',
          principalPaise: 2500000,
          emiAmountPaise: 900000,
          tenureMonths: 3,
          startDate: due,
          nextDueDate: due,
          frequency: PaymentFrequency.monthly,
          status: EmiStatus.active,
          type: const Value('Phone/Product'),
          interestRate: const Value(16),
          interestMethod: const Value(EmiInterestMethod.flat),
          interestPeriod: const Value(EmiRatePeriod.annual),
          productPricePaise: const Value(3000000),
          downPaymentPaise: const Value(500000),
          feesPaise: const Value(100000),
          contractualEmi: const Value(true),
        ),
      );
      expect(await repo.markEmiPaid(id, expectedDueDate: due), isTrue);

      await repo.saveEmi(
        EmisCompanion(
          id: Value(id),
          feesPaise: const Value(150000),
          notes: const Value('Updated fee'),
        ),
      );
      final detail = await repo.emiDetail(id);
      expect(detail.emi.principalPaise, 2500000);
      expect(detail.emi.emiAmountPaise, 900000);
      expect(detail.emi.productPricePaise, 3000000);
      expect(detail.emi.downPaymentPaise, 500000);
      expect(detail.emi.feesPaise, 150000);
      expect(detail.emi.interestMethod, EmiInterestMethod.flat);
      expect(detail.payments, hasLength(1));
      expect(detail.remainingBalancePaise, 1800000);
    },
  );
}
