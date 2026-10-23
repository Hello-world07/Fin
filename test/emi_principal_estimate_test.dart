import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/domain/emi_math.dart';
import 'package:personal_finance/src/domain/enums.dart';

void main() {
  test('blank principal uses total payments at zero interest', () {
    expect(
      estimatedPrincipalPaise(installmentPaise: 100000, tenure: 12),
      1200000,
    );
  });

  test('interest-bearing principal reproduces the entered installment', () {
    final principal = estimatedPrincipalPaise(
      installmentPaise: 1000000,
      tenure: 12,
      annualInterestRate: 9,
    );
    expect(principal, lessThan(12000000));
    expect(
      expectedEmiInstallmentPaise(
        principalPaise: principal,
        tenure: 12,
        annualInterestRate: 9,
      ),
      closeTo(1000000, 1),
    );
  });

  test('flat interest uses principal plus simple interest', () {
    final installment = expectedEmiInstallmentPaise(
      principalPaise: 12000000,
      tenure: 12,
      annualInterestRate: 12,
      interestMethod: EmiInterestMethod.flat,
    );
    expect(installment, 1120000);
    expect(
      estimatedPrincipalPaise(
        installmentPaise: installment,
        tenure: 12,
        annualInterestRate: 12,
        interestMethod: EmiInterestMethod.flat,
      ),
      12000000,
    );
    expect(
      expectedEmiInstallmentPaise(
        principalPaise: 12000000,
        tenure: 12,
        annualInterestRate: 12,
      ),
      lessThan(installment),
    );
  });

  test('monthly rate is annualized before the same EMI calculation', () {
    final annual = annualizedEmiRate(1, EmiRatePeriod.monthly);
    expect(annual, 12);
    expect(
      expectedEmiInstallmentPaise(
        principalPaise: 12000000,
        tenure: 12,
        annualInterestRate: annual,
      ),
      expectedEmiInstallmentPaise(
        principalPaise: 12000000,
        tenure: 12,
        annualInterestRate: 12,
      ),
    );
  });

  test(
    '20,000 principal at 20% monthly for two months uses the chosen method',
    () {
      const principal = 2000000;
      final rate = annualizedEmiRate(20, EmiRatePeriod.monthly);
      final reducing = expectedEmiInstallmentPaise(
        principalPaise: principal,
        tenure: 2,
        annualInterestRate: rate,
      );
      final flat = expectedEmiInstallmentPaise(
        principalPaise: principal,
        tenure: 2,
        annualInterestRate: rate,
        interestMethod: EmiInterestMethod.flat,
      );
      expect(reducing, 1309091);
      expect(flat, 1400000);
      expect(
        expectedEmiInstallmentPaise(
          principalPaise: 1000000,
          tenure: 2,
          annualInterestRate: rate,
          interestMethod: EmiInterestMethod.flat,
        ),
        700000,
      );
      final reducingSchedule = calculateEmiSchedule(
        principalPaise: principal,
        installmentPaise: reducing,
        tenure: 2,
        annualInterestRate: rate,
      );
      final flatSchedule = calculateEmiSchedule(
        principalPaise: principal,
        installmentPaise: flat,
        tenure: 2,
        annualInterestRate: rate,
        interestMethod: EmiInterestMethod.flat,
      );
      expect(reducingSchedule.isConsistent, isTrue);
      expect(reducingSchedule.totalRepaymentPaise, 2618182);
      expect(reducingSchedule.totalRepaymentPaise - principal, 618182);
      expect(flatSchedule.isConsistent, isTrue);
      expect(flatSchedule.totalRepaymentPaise, 2800000);
      expect(flatSchedule.totalRepaymentPaise - principal, 800000);
      final locked = calculateEmiSchedule(
        principalPaise: principal,
        installmentPaise: flat,
        tenure: 2,
        annualInterestRate: rate,
        contractualEmi: true,
      );
      expect(locked.isConsistent, isFalse);
      expect(locked.expectedInstallmentPaise, reducing);
      expect(locked.principalPaise, principal);
      expect(locked.totalRepaymentPaise, 2800000);
    },
  );

  test('contractual EMI retains entered payment and principal separately', () {
    final schedule = calculateEmiSchedule(
      principalPaise: 2500000,
      installmentPaise: 900000,
      tenure: 3,
      annualInterestRate: 16,
      interestMethod: EmiInterestMethod.flat,
      contractualEmi: true,
      paidInstallmentAmounts: const [900000],
    );
    expect(schedule.isConsistent, isFalse);
    expect(schedule.principalPaise, 2500000);
    expect(schedule.totalRepaymentPaise, 2700000);
    expect(schedule.remainingBalancePaise, 1800000);
  });
}
