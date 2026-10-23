import 'package:drift/drift.dart';

import 'database.dart';

const cardEntryKinds = <String>{
  'purchase',
  'refund',
  'payment',
  'interest',
  'fuelFee',
  'walletFee',
  'annualFee',
};

class CreditCardRepository {
  const CreditCardRepository(this.db);
  final AppDatabase db;

  Stream<List<CreditCard>> watchCards() => (db.select(
    db.creditCards,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();

  Stream<List<CardStatement>> watchStatements(int cardId) =>
      (db.select(db.cardStatements)
            ..where((t) => t.cardId.equals(cardId))
            ..orderBy([(t) => OrderingTerm.desc(t.statementDate)]))
          .watch();

  Stream<List<CardLedgerEntry>> watchEntries(int cardId) =>
      (db.select(db.cardLedgerEntries)
            ..where((t) => t.cardId.equals(cardId))
            ..orderBy([
              (t) => OrderingTerm.desc(t.occurredOn),
              (t) => OrderingTerm.desc(t.id),
            ]))
          .watch();

  Stream<List<CardEmiConversion>> watchConversions(int cardId) => (db.select(
    db.cardEmiConversions,
  )..where((t) => t.cardId.equals(cardId))).watch();

  Stream<List<CardConversionPayment>> watchConversionPayments(int cardId) =>
      (db.select(db.cardConversionPayments).join([
        innerJoin(
          db.cardEmiConversions,
          db.cardEmiConversions.id.equalsExp(
            db.cardConversionPayments.conversionId,
          ),
        ),
      ])..where(db.cardEmiConversions.cardId.equals(cardId))).watch().map(
        (rows) => rows
            .map((row) => row.readTable(db.cardConversionPayments))
            .toList(),
      );

  Future<int> addCard(String name, String issuer, {String? lastFour}) {
    if (name.trim().isEmpty ||
        issuer.trim().isEmpty ||
        (lastFour != null && !RegExp(r'^\d{4}$').hasMatch(lastFour))) {
      throw ArgumentError(
        'Enter a card name, issuer and optional four digits.',
      );
    }
    return db
        .into(db.creditCards)
        .insert(
          CreditCardsCompanion.insert(
            name: name.trim(),
            issuer: issuer.trim(),
            lastFour: Value(lastFour),
          ),
        );
  }

  Future<int> addStatement(
    int cardId,
    DateTime date,
    DateTime due,
    int balancePaise,
    int minimumDuePaise,
  ) {
    if (balancePaise < 0 ||
        minimumDuePaise < 0 ||
        minimumDuePaise > balancePaise ||
        due.isBefore(date)) {
      throw ArgumentError('Check the balance, minimum due and dates.');
    }
    return db
        .into(db.cardStatements)
        .insert(
          CardStatementsCompanion.insert(
            cardId: cardId,
            statementDate: date,
            dueDate: due,
            balancePaise: balancePaise,
            minimumDuePaise: minimumDuePaise,
          ),
        );
  }

  Future<int> addEntry(
    int cardId,
    String kind,
    String description,
    int amountPaise,
    DateTime date, {
    int? statementId,
  }) async {
    if (!cardEntryKinds.contains(kind) ||
        description.trim().isEmpty ||
        amountPaise <= 0) {
      throw ArgumentError('Enter a valid type, description and amount.');
    }
    return db.transaction(() async {
      if (statementId != null) {
        final statement =
            await (db.select(db.cardStatements)..where(
                  (t) => t.id.equals(statementId) & t.cardId.equals(cardId),
                ))
                .getSingleOrNull();
        if (statement == null) {
          throw ArgumentError('Statement does not belong to this card.');
        }
        if (kind == 'payment') {
          final entries =
              await (db.select(db.cardLedgerEntries)..where(
                    (t) =>
                        t.statementId.equals(statementId) &
                        t.kind.equals('payment'),
                  ))
                  .get();
          final paid = entries.fold<int>(
            0,
            (sum, row) => sum + row.amountPaise,
          );
          if (paid + amountPaise > statement.balancePaise) {
            throw ArgumentError('Payment exceeds the statement balance.');
          }
        }
      } else if (kind == 'payment') {
        throw ArgumentError('Choose the statement this payment pays.');
      }
      return db
          .into(db.cardLedgerEntries)
          .insert(
            CardLedgerEntriesCompanion.insert(
              cardId: cardId,
              statementId: Value(statementId),
              kind: kind,
              description: description.trim(),
              amountPaise: amountPaise,
              occurredOn: date,
            ),
          );
    });
  }

  Future<int> convertPurchase(
    int cardId,
    int purchaseEntryId,
    int monthlyEmiPaise,
    int tenureMonths,
    DateTime firstDueDate,
  ) async {
    return db.transaction(() async {
      final purchase =
          await (db.select(db.cardLedgerEntries)..where(
                (t) =>
                    t.id.equals(purchaseEntryId) &
                    t.cardId.equals(cardId) &
                    t.kind.equals('purchase'),
              ))
              .getSingleOrNull();
      if (purchase == null || monthlyEmiPaise <= 0 || tenureMonths <= 0) {
        throw ArgumentError('Choose a purchase and valid EMI terms.');
      }
      final existing =
          await (db.select(db.cardEmiConversions)
                ..where((t) => t.purchaseEntryId.equals(purchaseEntryId)))
              .getSingleOrNull();
      if (existing != null) {
        throw StateError('This purchase is already converted.');
      }
      return db
          .into(db.cardEmiConversions)
          .insert(
            CardEmiConversionsCompanion.insert(
              cardId: cardId,
              purchaseEntryId: purchaseEntryId,
              principalPaise: purchase.amountPaise,
              monthlyEmiPaise: monthlyEmiPaise,
              tenureMonths: tenureMonths,
              firstDueDate: firstDueDate,
            ),
          );
    });
  }

  Future<int> recordConversionPayment(
    int conversionId,
    int installmentNumber,
    int amountPaise,
    DateTime paidOn,
  ) async {
    return db.transaction(() async {
      final conversion = await (db.select(
        db.cardEmiConversions,
      )..where((t) => t.id.equals(conversionId))).getSingleOrNull();
      if (conversion == null ||
          amountPaise <= 0 ||
          installmentNumber < 1 ||
          installmentNumber > conversion.tenureMonths) {
        throw ArgumentError('Invalid conversion installment payment.');
      }
      final existing =
          await (db.select(db.cardConversionPayments)..where(
                (t) =>
                    t.conversionId.equals(conversionId) &
                    t.installmentNumber.equals(installmentNumber),
              ))
              .getSingleOrNull();
      if (existing != null) {
        throw StateError('This installment is already paid.');
      }
      return db
          .into(db.cardConversionPayments)
          .insert(
            CardConversionPaymentsCompanion.insert(
              conversionId: conversionId,
              installmentNumber: installmentNumber,
              amountPaise: amountPaise,
              paidOn: paidOn,
            ),
          );
    });
  }

  static int paidFor(
    CardStatement statement,
    Iterable<CardLedgerEntry> entries,
  ) => entries
      .where((e) => e.statementId == statement.id && e.kind == 'payment')
      .fold(0, (sum, e) => sum + e.amountPaise);

  static int outstandingFor(
    CardStatement statement,
    Iterable<CardLedgerEntry> entries,
  ) => (statement.balancePaise - paidFor(statement, entries)).clamp(
    0,
    statement.balancePaise,
  );
}
