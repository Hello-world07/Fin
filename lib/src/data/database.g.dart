// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $PaymentMethodsTable extends PaymentMethods
    with TableInfo<$PaymentMethodsTable, PaymentMethod> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PaymentMethodsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 60,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Other'),
  );
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    label,
    kind,
    isArchived,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'payment_methods';
  @override
  VerificationContext validateIntegrity(
    Insertable<PaymentMethod> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PaymentMethod map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PaymentMethod(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PaymentMethodsTable createAlias(String alias) {
    return $PaymentMethodsTable(attachedDatabase, alias);
  }
}

class PaymentMethod extends DataClass implements Insertable<PaymentMethod> {
  final int id;
  final String label;
  final String kind;
  final bool isArchived;
  final DateTime createdAt;
  const PaymentMethod({
    required this.id,
    required this.label,
    required this.kind,
    required this.isArchived,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['label'] = Variable<String>(label);
    map['kind'] = Variable<String>(kind);
    map['is_archived'] = Variable<bool>(isArchived);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PaymentMethodsCompanion toCompanion(bool nullToAbsent) {
    return PaymentMethodsCompanion(
      id: Value(id),
      label: Value(label),
      kind: Value(kind),
      isArchived: Value(isArchived),
      createdAt: Value(createdAt),
    );
  }

  factory PaymentMethod.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PaymentMethod(
      id: serializer.fromJson<int>(json['id']),
      label: serializer.fromJson<String>(json['label']),
      kind: serializer.fromJson<String>(json['kind']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'label': serializer.toJson<String>(label),
      'kind': serializer.toJson<String>(kind),
      'isArchived': serializer.toJson<bool>(isArchived),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PaymentMethod copyWith({
    int? id,
    String? label,
    String? kind,
    bool? isArchived,
    DateTime? createdAt,
  }) => PaymentMethod(
    id: id ?? this.id,
    label: label ?? this.label,
    kind: kind ?? this.kind,
    isArchived: isArchived ?? this.isArchived,
    createdAt: createdAt ?? this.createdAt,
  );
  PaymentMethod copyWithCompanion(PaymentMethodsCompanion data) {
    return PaymentMethod(
      id: data.id.present ? data.id.value : this.id,
      label: data.label.present ? data.label.value : this.label,
      kind: data.kind.present ? data.kind.value : this.kind,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PaymentMethod(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('kind: $kind, ')
          ..write('isArchived: $isArchived, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, label, kind, isArchived, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PaymentMethod &&
          other.id == this.id &&
          other.label == this.label &&
          other.kind == this.kind &&
          other.isArchived == this.isArchived &&
          other.createdAt == this.createdAt);
}

class PaymentMethodsCompanion extends UpdateCompanion<PaymentMethod> {
  final Value<int> id;
  final Value<String> label;
  final Value<String> kind;
  final Value<bool> isArchived;
  final Value<DateTime> createdAt;
  const PaymentMethodsCompanion({
    this.id = const Value.absent(),
    this.label = const Value.absent(),
    this.kind = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  PaymentMethodsCompanion.insert({
    this.id = const Value.absent(),
    required String label,
    this.kind = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : label = Value(label);
  static Insertable<PaymentMethod> custom({
    Expression<int>? id,
    Expression<String>? label,
    Expression<String>? kind,
    Expression<bool>? isArchived,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (label != null) 'label': label,
      if (kind != null) 'kind': kind,
      if (isArchived != null) 'is_archived': isArchived,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  PaymentMethodsCompanion copyWith({
    Value<int>? id,
    Value<String>? label,
    Value<String>? kind,
    Value<bool>? isArchived,
    Value<DateTime>? createdAt,
  }) {
    return PaymentMethodsCompanion(
      id: id ?? this.id,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PaymentMethodsCompanion(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('kind: $kind, ')
          ..write('isArchived: $isArchived, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $EmisTable extends Emis with TableInfo<$EmisTable, Emi> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EmisTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 90,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _principalPaiseMeta = const VerificationMeta(
    'principalPaise',
  );
  @override
  late final GeneratedColumn<int> principalPaise = GeneratedColumn<int>(
    'principal_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emiAmountPaiseMeta = const VerificationMeta(
    'emiAmountPaise',
  );
  @override
  late final GeneratedColumn<int> emiAmountPaise = GeneratedColumn<int>(
    'emi_amount_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _interestRateMeta = const VerificationMeta(
    'interestRate',
  );
  @override
  late final GeneratedColumn<double> interestRate = GeneratedColumn<double>(
    'interest_rate',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tenureMonthsMeta = const VerificationMeta(
    'tenureMonths',
  );
  @override
  late final GeneratedColumn<int> tenureMonths = GeneratedColumn<int>(
    'tenure_months',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<DateTime> startDate = GeneratedColumn<DateTime>(
    'start_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nextDueDateMeta = const VerificationMeta(
    'nextDueDate',
  );
  @override
  late final GeneratedColumn<DateTime> nextDueDate = GeneratedColumn<DateTime>(
    'next_due_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<PaymentFrequency, String>
  frequency = GeneratedColumn<String>(
    'frequency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<PaymentFrequency>($EmisTable.$converterfrequency);
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Loan'),
  );
  late final GeneratedColumn<int> initialPaidInstallments =
      GeneratedColumn<int>(
        'initial_paid_installments',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _paymentMethodIdMeta = const VerificationMeta(
    'paymentMethodId',
  );
  @override
  late final GeneratedColumn<int> paymentMethodId = GeneratedColumn<int>(
    'payment_method_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES payment_methods (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<EmiStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<EmiStatus>($EmisTable.$converterstatus);
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    provider,
    principalPaise,
    emiAmountPaise,
    interestRate,
    tenureMonths,
    startDate,
    nextDueDate,
    frequency,
    type,
    initialPaidInstallments,
    paymentMethodId,
    status,
    notes,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'emis';
  @override
  VerificationContext validateIntegrity(
    Insertable<Emi> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    }
    if (data.containsKey('principal_paise')) {
      context.handle(
        _principalPaiseMeta,
        principalPaise.isAcceptableOrUnknown(
          data['principal_paise']!,
          _principalPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_principalPaiseMeta);
    }
    if (data.containsKey('emi_amount_paise')) {
      context.handle(
        _emiAmountPaiseMeta,
        emiAmountPaise.isAcceptableOrUnknown(
          data['emi_amount_paise']!,
          _emiAmountPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_emiAmountPaiseMeta);
    }
    if (data.containsKey('interest_rate')) {
      context.handle(
        _interestRateMeta,
        interestRate.isAcceptableOrUnknown(
          data['interest_rate']!,
          _interestRateMeta,
        ),
      );
    }
    if (data.containsKey('tenure_months')) {
      context.handle(
        _tenureMonthsMeta,
        tenureMonths.isAcceptableOrUnknown(
          data['tenure_months']!,
          _tenureMonthsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_tenureMonthsMeta);
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    } else if (isInserting) {
      context.missing(_startDateMeta);
    }
    if (data.containsKey('next_due_date')) {
      context.handle(
        _nextDueDateMeta,
        nextDueDate.isAcceptableOrUnknown(
          data['next_due_date']!,
          _nextDueDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nextDueDateMeta);
    }
    if (data.containsKey('payment_method_id')) {
      context.handle(
        _paymentMethodIdMeta,
        paymentMethodId.isAcceptableOrUnknown(
          data['payment_method_id']!,
          _paymentMethodIdMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Emi map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Emi(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      ),
      principalPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}principal_paise'],
      )!,
      emiAmountPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}emi_amount_paise'],
      )!,
      interestRate: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}interest_rate'],
      ),
      tenureMonths: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tenure_months'],
      )!,
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_date'],
      )!,
      nextDueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_due_date'],
      )!,
      frequency: $EmisTable.$converterfrequency.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}frequency'],
        )!,
      ),
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      initialPaidInstallments: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}initial_paid_installments'],
      )!,
      paymentMethodId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}payment_method_id'],
      ),
      status: $EmisTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $EmisTable createAlias(String alias) {
    return $EmisTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<PaymentFrequency, String, String>
  $converterfrequency = const EnumNameConverter<PaymentFrequency>(
    PaymentFrequency.values,
  );
  static JsonTypeConverter2<EmiStatus, String, String> $converterstatus =
      const EnumNameConverter<EmiStatus>(EmiStatus.values);
}

class Emi extends DataClass implements Insertable<Emi> {
  final int id;
  final String name;
  final String? provider;
  final int principalPaise;
  final int emiAmountPaise;
  final double? interestRate;
  final int tenureMonths;
  final DateTime startDate;
  final DateTime nextDueDate;
  final PaymentFrequency frequency;
  final String type;
  final int initialPaidInstallments;
  final int? paymentMethodId;
  final EmiStatus status;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Emi({
    required this.id,
    required this.name,
    this.provider,
    required this.principalPaise,
    required this.emiAmountPaise,
    this.interestRate,
    required this.tenureMonths,
    required this.startDate,
    required this.nextDueDate,
    required this.frequency,
    this.type = 'Loan',
    this.initialPaidInstallments = 0,
    this.paymentMethodId,
    required this.status,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || provider != null) {
      map['provider'] = Variable<String>(provider);
    }
    map['principal_paise'] = Variable<int>(principalPaise);
    map['emi_amount_paise'] = Variable<int>(emiAmountPaise);
    if (!nullToAbsent || interestRate != null) {
      map['interest_rate'] = Variable<double>(interestRate);
    }
    map['tenure_months'] = Variable<int>(tenureMonths);
    map['start_date'] = Variable<DateTime>(startDate);
    map['next_due_date'] = Variable<DateTime>(nextDueDate);
    {
      map['frequency'] = Variable<String>(
        $EmisTable.$converterfrequency.toSql(frequency),
      );
    }
    map['type'] = Variable<String>(type);
    map['initial_paid_installments'] = Variable<int>(initialPaidInstallments);
    if (!nullToAbsent || paymentMethodId != null) {
      map['payment_method_id'] = Variable<int>(paymentMethodId);
    }
    {
      map['status'] = Variable<String>(
        $EmisTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  EmisCompanion toCompanion(bool nullToAbsent) {
    return EmisCompanion(
      id: Value(id),
      name: Value(name),
      provider: provider == null && nullToAbsent
          ? const Value.absent()
          : Value(provider),
      principalPaise: Value(principalPaise),
      emiAmountPaise: Value(emiAmountPaise),
      interestRate: interestRate == null && nullToAbsent
          ? const Value.absent()
          : Value(interestRate),
      tenureMonths: Value(tenureMonths),
      startDate: Value(startDate),
      nextDueDate: Value(nextDueDate),
      frequency: Value(frequency),
      type: Value(type),
      initialPaidInstallments: Value(initialPaidInstallments),
      paymentMethodId: paymentMethodId == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentMethodId),
      status: Value(status),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Emi.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Emi(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      provider: serializer.fromJson<String?>(json['provider']),
      principalPaise: serializer.fromJson<int>(json['principalPaise']),
      emiAmountPaise: serializer.fromJson<int>(json['emiAmountPaise']),
      interestRate: serializer.fromJson<double?>(json['interestRate']),
      tenureMonths: serializer.fromJson<int>(json['tenureMonths']),
      startDate: serializer.fromJson<DateTime>(json['startDate']),
      nextDueDate: serializer.fromJson<DateTime>(json['nextDueDate']),
      frequency: $EmisTable.$converterfrequency.fromJson(
        serializer.fromJson<String>(json['frequency']),
      ),
      type: serializer.fromJson<String>(json['type'] ?? 'Loan'),
      initialPaidInstallments: serializer.fromJson<int>(
        json['initialPaidInstallments'] ?? 0,
      ),
      paymentMethodId: serializer.fromJson<int?>(json['paymentMethodId']),
      status: $EmisTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'provider': serializer.toJson<String?>(provider),
      'principalPaise': serializer.toJson<int>(principalPaise),
      'emiAmountPaise': serializer.toJson<int>(emiAmountPaise),
      'interestRate': serializer.toJson<double?>(interestRate),
      'tenureMonths': serializer.toJson<int>(tenureMonths),
      'startDate': serializer.toJson<DateTime>(startDate),
      'nextDueDate': serializer.toJson<DateTime>(nextDueDate),
      'frequency': serializer.toJson<String>(
        $EmisTable.$converterfrequency.toJson(frequency),
      ),
      'type': serializer.toJson<String>(type),
      'initialPaidInstallments': serializer.toJson<int>(
        initialPaidInstallments,
      ),
      'paymentMethodId': serializer.toJson<int?>(paymentMethodId),
      'status': serializer.toJson<String>(
        $EmisTable.$converterstatus.toJson(status),
      ),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Emi copyWith({
    int? id,
    String? name,
    Value<String?> provider = const Value.absent(),
    int? principalPaise,
    int? emiAmountPaise,
    Value<double?> interestRate = const Value.absent(),
    int? tenureMonths,
    DateTime? startDate,
    DateTime? nextDueDate,
    PaymentFrequency? frequency,
    String? type,
    int? initialPaidInstallments,
    Value<int?> paymentMethodId = const Value.absent(),
    EmiStatus? status,
    Value<String?> notes = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Emi(
    id: id ?? this.id,
    name: name ?? this.name,
    provider: provider.present ? provider.value : this.provider,
    principalPaise: principalPaise ?? this.principalPaise,
    emiAmountPaise: emiAmountPaise ?? this.emiAmountPaise,
    interestRate: interestRate.present ? interestRate.value : this.interestRate,
    tenureMonths: tenureMonths ?? this.tenureMonths,
    startDate: startDate ?? this.startDate,
    nextDueDate: nextDueDate ?? this.nextDueDate,
    frequency: frequency ?? this.frequency,
    type: type ?? this.type,
    initialPaidInstallments:
        initialPaidInstallments ?? this.initialPaidInstallments,
    paymentMethodId: paymentMethodId.present
        ? paymentMethodId.value
        : this.paymentMethodId,
    status: status ?? this.status,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Emi copyWithCompanion(EmisCompanion data) {
    return Emi(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      provider: data.provider.present ? data.provider.value : this.provider,
      principalPaise: data.principalPaise.present
          ? data.principalPaise.value
          : this.principalPaise,
      emiAmountPaise: data.emiAmountPaise.present
          ? data.emiAmountPaise.value
          : this.emiAmountPaise,
      interestRate: data.interestRate.present
          ? data.interestRate.value
          : this.interestRate,
      tenureMonths: data.tenureMonths.present
          ? data.tenureMonths.value
          : this.tenureMonths,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      nextDueDate: data.nextDueDate.present
          ? data.nextDueDate.value
          : this.nextDueDate,
      frequency: data.frequency.present ? data.frequency.value : this.frequency,
      type: data.type.present ? data.type.value : this.type,
      initialPaidInstallments: data.initialPaidInstallments.present
          ? data.initialPaidInstallments.value
          : this.initialPaidInstallments,
      paymentMethodId: data.paymentMethodId.present
          ? data.paymentMethodId.value
          : this.paymentMethodId,
      status: data.status.present ? data.status.value : this.status,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Emi(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('provider: $provider, ')
          ..write('principalPaise: $principalPaise, ')
          ..write('emiAmountPaise: $emiAmountPaise, ')
          ..write('interestRate: $interestRate, ')
          ..write('tenureMonths: $tenureMonths, ')
          ..write('startDate: $startDate, ')
          ..write('nextDueDate: $nextDueDate, ')
          ..write('frequency: $frequency, ')
          ..write('type: $type, ')
          ..write('initialPaidInstallments: $initialPaidInstallments, ')
          ..write('paymentMethodId: $paymentMethodId, ')
          ..write('status: $status, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    provider,
    principalPaise,
    emiAmountPaise,
    interestRate,
    tenureMonths,
    startDate,
    nextDueDate,
    frequency,
    type,
    initialPaidInstallments,
    paymentMethodId,
    status,
    notes,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Emi &&
          other.id == this.id &&
          other.name == this.name &&
          other.provider == this.provider &&
          other.principalPaise == this.principalPaise &&
          other.emiAmountPaise == this.emiAmountPaise &&
          other.interestRate == this.interestRate &&
          other.tenureMonths == this.tenureMonths &&
          other.startDate == this.startDate &&
          other.nextDueDate == this.nextDueDate &&
          other.frequency == this.frequency &&
          other.type == this.type &&
          other.initialPaidInstallments == this.initialPaidInstallments &&
          other.paymentMethodId == this.paymentMethodId &&
          other.status == this.status &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class EmisCompanion extends UpdateCompanion<Emi> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> provider;
  final Value<int> principalPaise;
  final Value<int> emiAmountPaise;
  final Value<double?> interestRate;
  final Value<int> tenureMonths;
  final Value<DateTime> startDate;
  final Value<DateTime> nextDueDate;
  final Value<PaymentFrequency> frequency;
  final Value<String> type;
  final Value<int> initialPaidInstallments;
  final Value<int?> paymentMethodId;
  final Value<EmiStatus> status;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const EmisCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.provider = const Value.absent(),
    this.principalPaise = const Value.absent(),
    this.emiAmountPaise = const Value.absent(),
    this.interestRate = const Value.absent(),
    this.tenureMonths = const Value.absent(),
    this.startDate = const Value.absent(),
    this.nextDueDate = const Value.absent(),
    this.frequency = const Value.absent(),
    this.type = const Value.absent(),
    this.initialPaidInstallments = const Value.absent(),
    this.paymentMethodId = const Value.absent(),
    this.status = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  EmisCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.provider = const Value.absent(),
    required int principalPaise,
    required int emiAmountPaise,
    this.interestRate = const Value.absent(),
    required int tenureMonths,
    required DateTime startDate,
    required DateTime nextDueDate,
    required PaymentFrequency frequency,
    this.type = const Value.absent(),
    this.initialPaidInstallments = const Value.absent(),
    this.paymentMethodId = const Value.absent(),
    required EmiStatus status,
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : name = Value(name),
       principalPaise = Value(principalPaise),
       emiAmountPaise = Value(emiAmountPaise),
       tenureMonths = Value(tenureMonths),
       startDate = Value(startDate),
       nextDueDate = Value(nextDueDate),
       frequency = Value(frequency),
       status = Value(status);
  static Insertable<Emi> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? provider,
    Expression<int>? principalPaise,
    Expression<int>? emiAmountPaise,
    Expression<double>? interestRate,
    Expression<int>? tenureMonths,
    Expression<DateTime>? startDate,
    Expression<DateTime>? nextDueDate,
    Expression<String>? frequency,
    Expression<String>? type,
    Expression<int>? initialPaidInstallments,
    Expression<int>? paymentMethodId,
    Expression<String>? status,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (provider != null) 'provider': provider,
      if (principalPaise != null) 'principal_paise': principalPaise,
      if (emiAmountPaise != null) 'emi_amount_paise': emiAmountPaise,
      if (interestRate != null) 'interest_rate': interestRate,
      if (tenureMonths != null) 'tenure_months': tenureMonths,
      if (startDate != null) 'start_date': startDate,
      if (nextDueDate != null) 'next_due_date': nextDueDate,
      if (frequency != null) 'frequency': frequency,
      if (type != null) 'type': type,
      if (initialPaidInstallments != null)
        'initial_paid_installments': initialPaidInstallments,
      if (paymentMethodId != null) 'payment_method_id': paymentMethodId,
      if (status != null) 'status': status,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  EmisCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? provider,
    Value<int>? principalPaise,
    Value<int>? emiAmountPaise,
    Value<double?>? interestRate,
    Value<int>? tenureMonths,
    Value<DateTime>? startDate,
    Value<DateTime>? nextDueDate,
    Value<PaymentFrequency>? frequency,
    Value<String>? type,
    Value<int>? initialPaidInstallments,
    Value<int?>? paymentMethodId,
    Value<EmiStatus>? status,
    Value<String?>? notes,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return EmisCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      principalPaise: principalPaise ?? this.principalPaise,
      emiAmountPaise: emiAmountPaise ?? this.emiAmountPaise,
      interestRate: interestRate ?? this.interestRate,
      tenureMonths: tenureMonths ?? this.tenureMonths,
      startDate: startDate ?? this.startDate,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      frequency: frequency ?? this.frequency,
      type: type ?? this.type,
      initialPaidInstallments:
          initialPaidInstallments ?? this.initialPaidInstallments,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (principalPaise.present) {
      map['principal_paise'] = Variable<int>(principalPaise.value);
    }
    if (emiAmountPaise.present) {
      map['emi_amount_paise'] = Variable<int>(emiAmountPaise.value);
    }
    if (interestRate.present) {
      map['interest_rate'] = Variable<double>(interestRate.value);
    }
    if (tenureMonths.present) {
      map['tenure_months'] = Variable<int>(tenureMonths.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<DateTime>(startDate.value);
    }
    if (nextDueDate.present) {
      map['next_due_date'] = Variable<DateTime>(nextDueDate.value);
    }
    if (frequency.present) {
      map['frequency'] = Variable<String>(
        $EmisTable.$converterfrequency.toSql(frequency.value),
      );
    }
    if (type.present) map['type'] = Variable<String>(type.value);
    if (initialPaidInstallments.present) {
      map['initial_paid_installments'] = Variable<int>(
        initialPaidInstallments.value,
      );
    }
    if (paymentMethodId.present) {
      map['payment_method_id'] = Variable<int>(paymentMethodId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $EmisTable.$converterstatus.toSql(status.value),
      );
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EmisCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('provider: $provider, ')
          ..write('principalPaise: $principalPaise, ')
          ..write('emiAmountPaise: $emiAmountPaise, ')
          ..write('interestRate: $interestRate, ')
          ..write('tenureMonths: $tenureMonths, ')
          ..write('startDate: $startDate, ')
          ..write('nextDueDate: $nextDueDate, ')
          ..write('frequency: $frequency, ')
          ..write('type: $type, ')
          ..write('initialPaidInstallments: $initialPaidInstallments, ')
          ..write('paymentMethodId: $paymentMethodId, ')
          ..write('status: $status, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $EmiPaymentsTable extends EmiPayments
    with TableInfo<$EmiPaymentsTable, EmiPayment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EmiPaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _emiIdMeta = const VerificationMeta('emiId');
  @override
  late final GeneratedColumn<int> emiId = GeneratedColumn<int>(
    'emi_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES emis (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _amountPaiseMeta = const VerificationMeta(
    'amountPaise',
  );
  @override
  late final GeneratedColumn<int> amountPaise = GeneratedColumn<int>(
    'amount_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paidOnMeta = const VerificationMeta('paidOn');
  @override
  late final GeneratedColumn<DateTime> paidOn = GeneratedColumn<DateTime>(
    'paid_on',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _installmentNumberMeta = const VerificationMeta(
    'installmentNumber',
  );
  @override
  late final GeneratedColumn<int> installmentNumber = GeneratedColumn<int>(
    'installment_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paidEarlyMeta = const VerificationMeta(
    'paidEarly',
  );
  @override
  late final GeneratedColumn<bool> paidEarly = GeneratedColumn<bool>(
    'paid_early',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("paid_early" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    emiId,
    amountPaise,
    paidOn,
    installmentNumber,
    paidEarly,
    notes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'emi_payments';
  @override
  VerificationContext validateIntegrity(
    Insertable<EmiPayment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('emi_id')) {
      context.handle(
        _emiIdMeta,
        emiId.isAcceptableOrUnknown(data['emi_id']!, _emiIdMeta),
      );
    } else if (isInserting) {
      context.missing(_emiIdMeta);
    }
    if (data.containsKey('amount_paise')) {
      context.handle(
        _amountPaiseMeta,
        amountPaise.isAcceptableOrUnknown(
          data['amount_paise']!,
          _amountPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountPaiseMeta);
    }
    if (data.containsKey('paid_on')) {
      context.handle(
        _paidOnMeta,
        paidOn.isAcceptableOrUnknown(data['paid_on']!, _paidOnMeta),
      );
    } else if (isInserting) {
      context.missing(_paidOnMeta);
    }
    if (data.containsKey('installment_number')) {
      context.handle(
        _installmentNumberMeta,
        installmentNumber.isAcceptableOrUnknown(
          data['installment_number']!,
          _installmentNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_installmentNumberMeta);
    }
    if (data.containsKey('paid_early')) {
      context.handle(
        _paidEarlyMeta,
        paidEarly.isAcceptableOrUnknown(data['paid_early']!, _paidEarlyMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {emiId, installmentNumber},
  ];
  @override
  EmiPayment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EmiPayment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      emiId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}emi_id'],
      )!,
      amountPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_paise'],
      )!,
      paidOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}paid_on'],
      )!,
      installmentNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}installment_number'],
      )!,
      paidEarly: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}paid_early'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
    );
  }

  @override
  $EmiPaymentsTable createAlias(String alias) {
    return $EmiPaymentsTable(attachedDatabase, alias);
  }
}

class EmiPayment extends DataClass implements Insertable<EmiPayment> {
  final int id;
  final int emiId;
  final int amountPaise;
  final DateTime paidOn;
  final int installmentNumber;
  final bool paidEarly;
  final String? notes;
  const EmiPayment({
    required this.id,
    required this.emiId,
    required this.amountPaise,
    required this.paidOn,
    required this.installmentNumber,
    required this.paidEarly,
    this.notes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['emi_id'] = Variable<int>(emiId);
    map['amount_paise'] = Variable<int>(amountPaise);
    map['paid_on'] = Variable<DateTime>(paidOn);
    map['installment_number'] = Variable<int>(installmentNumber);
    map['paid_early'] = Variable<bool>(paidEarly);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    return map;
  }

  EmiPaymentsCompanion toCompanion(bool nullToAbsent) {
    return EmiPaymentsCompanion(
      id: Value(id),
      emiId: Value(emiId),
      amountPaise: Value(amountPaise),
      paidOn: Value(paidOn),
      installmentNumber: Value(installmentNumber),
      paidEarly: Value(paidEarly),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
    );
  }

  factory EmiPayment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EmiPayment(
      id: serializer.fromJson<int>(json['id']),
      emiId: serializer.fromJson<int>(json['emiId']),
      amountPaise: serializer.fromJson<int>(json['amountPaise']),
      paidOn: serializer.fromJson<DateTime>(json['paidOn']),
      installmentNumber: serializer.fromJson<int>(json['installmentNumber']),
      paidEarly: serializer.fromJson<bool>(json['paidEarly']),
      notes: serializer.fromJson<String?>(json['notes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'emiId': serializer.toJson<int>(emiId),
      'amountPaise': serializer.toJson<int>(amountPaise),
      'paidOn': serializer.toJson<DateTime>(paidOn),
      'installmentNumber': serializer.toJson<int>(installmentNumber),
      'paidEarly': serializer.toJson<bool>(paidEarly),
      'notes': serializer.toJson<String?>(notes),
    };
  }

  EmiPayment copyWith({
    int? id,
    int? emiId,
    int? amountPaise,
    DateTime? paidOn,
    int? installmentNumber,
    bool? paidEarly,
    Value<String?> notes = const Value.absent(),
  }) => EmiPayment(
    id: id ?? this.id,
    emiId: emiId ?? this.emiId,
    amountPaise: amountPaise ?? this.amountPaise,
    paidOn: paidOn ?? this.paidOn,
    installmentNumber: installmentNumber ?? this.installmentNumber,
    paidEarly: paidEarly ?? this.paidEarly,
    notes: notes.present ? notes.value : this.notes,
  );
  EmiPayment copyWithCompanion(EmiPaymentsCompanion data) {
    return EmiPayment(
      id: data.id.present ? data.id.value : this.id,
      emiId: data.emiId.present ? data.emiId.value : this.emiId,
      amountPaise: data.amountPaise.present
          ? data.amountPaise.value
          : this.amountPaise,
      paidOn: data.paidOn.present ? data.paidOn.value : this.paidOn,
      installmentNumber: data.installmentNumber.present
          ? data.installmentNumber.value
          : this.installmentNumber,
      paidEarly: data.paidEarly.present ? data.paidEarly.value : this.paidEarly,
      notes: data.notes.present ? data.notes.value : this.notes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EmiPayment(')
          ..write('id: $id, ')
          ..write('emiId: $emiId, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('paidOn: $paidOn, ')
          ..write('installmentNumber: $installmentNumber, ')
          ..write('paidEarly: $paidEarly, ')
          ..write('notes: $notes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    emiId,
    amountPaise,
    paidOn,
    installmentNumber,
    paidEarly,
    notes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EmiPayment &&
          other.id == this.id &&
          other.emiId == this.emiId &&
          other.amountPaise == this.amountPaise &&
          other.paidOn == this.paidOn &&
          other.installmentNumber == this.installmentNumber &&
          other.paidEarly == this.paidEarly &&
          other.notes == this.notes);
}

class EmiPaymentsCompanion extends UpdateCompanion<EmiPayment> {
  final Value<int> id;
  final Value<int> emiId;
  final Value<int> amountPaise;
  final Value<DateTime> paidOn;
  final Value<int> installmentNumber;
  final Value<bool> paidEarly;
  final Value<String?> notes;
  const EmiPaymentsCompanion({
    this.id = const Value.absent(),
    this.emiId = const Value.absent(),
    this.amountPaise = const Value.absent(),
    this.paidOn = const Value.absent(),
    this.installmentNumber = const Value.absent(),
    this.paidEarly = const Value.absent(),
    this.notes = const Value.absent(),
  });
  EmiPaymentsCompanion.insert({
    this.id = const Value.absent(),
    required int emiId,
    required int amountPaise,
    required DateTime paidOn,
    required int installmentNumber,
    this.paidEarly = const Value.absent(),
    this.notes = const Value.absent(),
  }) : emiId = Value(emiId),
       amountPaise = Value(amountPaise),
       paidOn = Value(paidOn),
       installmentNumber = Value(installmentNumber);
  static Insertable<EmiPayment> custom({
    Expression<int>? id,
    Expression<int>? emiId,
    Expression<int>? amountPaise,
    Expression<DateTime>? paidOn,
    Expression<int>? installmentNumber,
    Expression<bool>? paidEarly,
    Expression<String>? notes,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (emiId != null) 'emi_id': emiId,
      if (amountPaise != null) 'amount_paise': amountPaise,
      if (paidOn != null) 'paid_on': paidOn,
      if (installmentNumber != null) 'installment_number': installmentNumber,
      if (paidEarly != null) 'paid_early': paidEarly,
      if (notes != null) 'notes': notes,
    });
  }

  EmiPaymentsCompanion copyWith({
    Value<int>? id,
    Value<int>? emiId,
    Value<int>? amountPaise,
    Value<DateTime>? paidOn,
    Value<int>? installmentNumber,
    Value<bool>? paidEarly,
    Value<String?>? notes,
  }) {
    return EmiPaymentsCompanion(
      id: id ?? this.id,
      emiId: emiId ?? this.emiId,
      amountPaise: amountPaise ?? this.amountPaise,
      paidOn: paidOn ?? this.paidOn,
      installmentNumber: installmentNumber ?? this.installmentNumber,
      paidEarly: paidEarly ?? this.paidEarly,
      notes: notes ?? this.notes,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (emiId.present) {
      map['emi_id'] = Variable<int>(emiId.value);
    }
    if (amountPaise.present) {
      map['amount_paise'] = Variable<int>(amountPaise.value);
    }
    if (paidOn.present) {
      map['paid_on'] = Variable<DateTime>(paidOn.value);
    }
    if (installmentNumber.present) {
      map['installment_number'] = Variable<int>(installmentNumber.value);
    }
    if (paidEarly.present) {
      map['paid_early'] = Variable<bool>(paidEarly.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EmiPaymentsCompanion(')
          ..write('id: $id, ')
          ..write('emiId: $emiId, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('paidOn: $paidOn, ')
          ..write('installmentNumber: $installmentNumber, ')
          ..write('paidEarly: $paidEarly, ')
          ..write('notes: $notes')
          ..write(')'))
        .toString();
  }
}

class $MoneyRecordsTable extends MoneyRecords
    with TableInfo<$MoneyRecordsTable, MoneyRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MoneyRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _personNameMeta = const VerificationMeta(
    'personName',
  );
  @override
  late final GeneratedColumn<String> personName = GeneratedColumn<String>(
    'person_name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 90,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<MoneyDirection, String>
  direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<MoneyDirection>($MoneyRecordsTable.$converterdirection);
  static const VerificationMeta _amountPaiseMeta = const VerificationMeta(
    'amountPaise',
  );
  @override
  late final GeneratedColumn<int> amountPaise = GeneratedColumn<int>(
    'amount_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordDateMeta = const VerificationMeta(
    'recordDate',
  );
  @override
  late final GeneratedColumn<DateTime> recordDate = GeneratedColumn<DateTime>(
    'record_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _paymentMethodIdMeta = const VerificationMeta(
    'paymentMethodId',
  );
  @override
  late final GeneratedColumn<int> paymentMethodId = GeneratedColumn<int>(
    'payment_method_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES payment_methods (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<MoneyStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<MoneyStatus>($MoneyRecordsTable.$converterstatus);
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    personName,
    direction,
    amountPaise,
    recordDate,
    dueDate,
    paymentMethodId,
    status,
    notes,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'money_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<MoneyRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('person_name')) {
      context.handle(
        _personNameMeta,
        personName.isAcceptableOrUnknown(data['person_name']!, _personNameMeta),
      );
    } else if (isInserting) {
      context.missing(_personNameMeta);
    }
    if (data.containsKey('amount_paise')) {
      context.handle(
        _amountPaiseMeta,
        amountPaise.isAcceptableOrUnknown(
          data['amount_paise']!,
          _amountPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountPaiseMeta);
    }
    if (data.containsKey('record_date')) {
      context.handle(
        _recordDateMeta,
        recordDate.isAcceptableOrUnknown(data['record_date']!, _recordDateMeta),
      );
    } else if (isInserting) {
      context.missing(_recordDateMeta);
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('payment_method_id')) {
      context.handle(
        _paymentMethodIdMeta,
        paymentMethodId.isAcceptableOrUnknown(
          data['payment_method_id']!,
          _paymentMethodIdMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MoneyRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MoneyRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      personName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}person_name'],
      )!,
      direction: $MoneyRecordsTable.$converterdirection.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}direction'],
        )!,
      ),
      amountPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_paise'],
      )!,
      recordDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}record_date'],
      )!,
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      ),
      paymentMethodId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}payment_method_id'],
      ),
      status: $MoneyRecordsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MoneyRecordsTable createAlias(String alias) {
    return $MoneyRecordsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<MoneyDirection, String, String>
  $converterdirection = const EnumNameConverter<MoneyDirection>(
    MoneyDirection.values,
  );
  static JsonTypeConverter2<MoneyStatus, String, String> $converterstatus =
      const EnumNameConverter<MoneyStatus>(MoneyStatus.values);
}

class MoneyRecord extends DataClass implements Insertable<MoneyRecord> {
  final int id;
  final String personName;
  final MoneyDirection direction;
  final int amountPaise;
  final DateTime recordDate;
  final DateTime? dueDate;
  final int? paymentMethodId;
  final MoneyStatus status;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  const MoneyRecord({
    required this.id,
    required this.personName,
    required this.direction,
    required this.amountPaise,
    required this.recordDate,
    this.dueDate,
    this.paymentMethodId,
    required this.status,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['person_name'] = Variable<String>(personName);
    {
      map['direction'] = Variable<String>(
        $MoneyRecordsTable.$converterdirection.toSql(direction),
      );
    }
    map['amount_paise'] = Variable<int>(amountPaise);
    map['record_date'] = Variable<DateTime>(recordDate);
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<DateTime>(dueDate);
    }
    if (!nullToAbsent || paymentMethodId != null) {
      map['payment_method_id'] = Variable<int>(paymentMethodId);
    }
    {
      map['status'] = Variable<String>(
        $MoneyRecordsTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  MoneyRecordsCompanion toCompanion(bool nullToAbsent) {
    return MoneyRecordsCompanion(
      id: Value(id),
      personName: Value(personName),
      direction: Value(direction),
      amountPaise: Value(amountPaise),
      recordDate: Value(recordDate),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      paymentMethodId: paymentMethodId == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentMethodId),
      status: Value(status),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory MoneyRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MoneyRecord(
      id: serializer.fromJson<int>(json['id']),
      personName: serializer.fromJson<String>(json['personName']),
      direction: $MoneyRecordsTable.$converterdirection.fromJson(
        serializer.fromJson<String>(json['direction']),
      ),
      amountPaise: serializer.fromJson<int>(json['amountPaise']),
      recordDate: serializer.fromJson<DateTime>(json['recordDate']),
      dueDate: serializer.fromJson<DateTime?>(json['dueDate']),
      paymentMethodId: serializer.fromJson<int?>(json['paymentMethodId']),
      status: $MoneyRecordsTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'personName': serializer.toJson<String>(personName),
      'direction': serializer.toJson<String>(
        $MoneyRecordsTable.$converterdirection.toJson(direction),
      ),
      'amountPaise': serializer.toJson<int>(amountPaise),
      'recordDate': serializer.toJson<DateTime>(recordDate),
      'dueDate': serializer.toJson<DateTime?>(dueDate),
      'paymentMethodId': serializer.toJson<int?>(paymentMethodId),
      'status': serializer.toJson<String>(
        $MoneyRecordsTable.$converterstatus.toJson(status),
      ),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  MoneyRecord copyWith({
    int? id,
    String? personName,
    MoneyDirection? direction,
    int? amountPaise,
    DateTime? recordDate,
    Value<DateTime?> dueDate = const Value.absent(),
    Value<int?> paymentMethodId = const Value.absent(),
    MoneyStatus? status,
    Value<String?> notes = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => MoneyRecord(
    id: id ?? this.id,
    personName: personName ?? this.personName,
    direction: direction ?? this.direction,
    amountPaise: amountPaise ?? this.amountPaise,
    recordDate: recordDate ?? this.recordDate,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    paymentMethodId: paymentMethodId.present
        ? paymentMethodId.value
        : this.paymentMethodId,
    status: status ?? this.status,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  MoneyRecord copyWithCompanion(MoneyRecordsCompanion data) {
    return MoneyRecord(
      id: data.id.present ? data.id.value : this.id,
      personName: data.personName.present
          ? data.personName.value
          : this.personName,
      direction: data.direction.present ? data.direction.value : this.direction,
      amountPaise: data.amountPaise.present
          ? data.amountPaise.value
          : this.amountPaise,
      recordDate: data.recordDate.present
          ? data.recordDate.value
          : this.recordDate,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      paymentMethodId: data.paymentMethodId.present
          ? data.paymentMethodId.value
          : this.paymentMethodId,
      status: data.status.present ? data.status.value : this.status,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MoneyRecord(')
          ..write('id: $id, ')
          ..write('personName: $personName, ')
          ..write('direction: $direction, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('recordDate: $recordDate, ')
          ..write('dueDate: $dueDate, ')
          ..write('paymentMethodId: $paymentMethodId, ')
          ..write('status: $status, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    personName,
    direction,
    amountPaise,
    recordDate,
    dueDate,
    paymentMethodId,
    status,
    notes,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MoneyRecord &&
          other.id == this.id &&
          other.personName == this.personName &&
          other.direction == this.direction &&
          other.amountPaise == this.amountPaise &&
          other.recordDate == this.recordDate &&
          other.dueDate == this.dueDate &&
          other.paymentMethodId == this.paymentMethodId &&
          other.status == this.status &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class MoneyRecordsCompanion extends UpdateCompanion<MoneyRecord> {
  final Value<int> id;
  final Value<String> personName;
  final Value<MoneyDirection> direction;
  final Value<int> amountPaise;
  final Value<DateTime> recordDate;
  final Value<DateTime?> dueDate;
  final Value<int?> paymentMethodId;
  final Value<MoneyStatus> status;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const MoneyRecordsCompanion({
    this.id = const Value.absent(),
    this.personName = const Value.absent(),
    this.direction = const Value.absent(),
    this.amountPaise = const Value.absent(),
    this.recordDate = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.paymentMethodId = const Value.absent(),
    this.status = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  MoneyRecordsCompanion.insert({
    this.id = const Value.absent(),
    required String personName,
    required MoneyDirection direction,
    required int amountPaise,
    required DateTime recordDate,
    this.dueDate = const Value.absent(),
    this.paymentMethodId = const Value.absent(),
    required MoneyStatus status,
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : personName = Value(personName),
       direction = Value(direction),
       amountPaise = Value(amountPaise),
       recordDate = Value(recordDate),
       status = Value(status);
  static Insertable<MoneyRecord> custom({
    Expression<int>? id,
    Expression<String>? personName,
    Expression<String>? direction,
    Expression<int>? amountPaise,
    Expression<DateTime>? recordDate,
    Expression<DateTime>? dueDate,
    Expression<int>? paymentMethodId,
    Expression<String>? status,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (personName != null) 'person_name': personName,
      if (direction != null) 'direction': direction,
      if (amountPaise != null) 'amount_paise': amountPaise,
      if (recordDate != null) 'record_date': recordDate,
      if (dueDate != null) 'due_date': dueDate,
      if (paymentMethodId != null) 'payment_method_id': paymentMethodId,
      if (status != null) 'status': status,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  MoneyRecordsCompanion copyWith({
    Value<int>? id,
    Value<String>? personName,
    Value<MoneyDirection>? direction,
    Value<int>? amountPaise,
    Value<DateTime>? recordDate,
    Value<DateTime?>? dueDate,
    Value<int?>? paymentMethodId,
    Value<MoneyStatus>? status,
    Value<String?>? notes,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return MoneyRecordsCompanion(
      id: id ?? this.id,
      personName: personName ?? this.personName,
      direction: direction ?? this.direction,
      amountPaise: amountPaise ?? this.amountPaise,
      recordDate: recordDate ?? this.recordDate,
      dueDate: dueDate ?? this.dueDate,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (personName.present) {
      map['person_name'] = Variable<String>(personName.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(
        $MoneyRecordsTable.$converterdirection.toSql(direction.value),
      );
    }
    if (amountPaise.present) {
      map['amount_paise'] = Variable<int>(amountPaise.value);
    }
    if (recordDate.present) {
      map['record_date'] = Variable<DateTime>(recordDate.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (paymentMethodId.present) {
      map['payment_method_id'] = Variable<int>(paymentMethodId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $MoneyRecordsTable.$converterstatus.toSql(status.value),
      );
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MoneyRecordsCompanion(')
          ..write('id: $id, ')
          ..write('personName: $personName, ')
          ..write('direction: $direction, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('recordDate: $recordDate, ')
          ..write('dueDate: $dueDate, ')
          ..write('paymentMethodId: $paymentMethodId, ')
          ..write('status: $status, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $MoneyRepaymentsTable extends MoneyRepayments
    with TableInfo<$MoneyRepaymentsTable, MoneyRepayment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MoneyRepaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _moneyRecordIdMeta = const VerificationMeta(
    'moneyRecordId',
  );
  @override
  late final GeneratedColumn<int> moneyRecordId = GeneratedColumn<int>(
    'money_record_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES money_records (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _amountPaiseMeta = const VerificationMeta(
    'amountPaise',
  );
  @override
  late final GeneratedColumn<int> amountPaise = GeneratedColumn<int>(
    'amount_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paidOnMeta = const VerificationMeta('paidOn');
  @override
  late final GeneratedColumn<DateTime> paidOn = GeneratedColumn<DateTime>(
    'paid_on',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    moneyRecordId,
    amountPaise,
    paidOn,
    notes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'money_repayments';
  @override
  VerificationContext validateIntegrity(
    Insertable<MoneyRepayment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('money_record_id')) {
      context.handle(
        _moneyRecordIdMeta,
        moneyRecordId.isAcceptableOrUnknown(
          data['money_record_id']!,
          _moneyRecordIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_moneyRecordIdMeta);
    }
    if (data.containsKey('amount_paise')) {
      context.handle(
        _amountPaiseMeta,
        amountPaise.isAcceptableOrUnknown(
          data['amount_paise']!,
          _amountPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountPaiseMeta);
    }
    if (data.containsKey('paid_on')) {
      context.handle(
        _paidOnMeta,
        paidOn.isAcceptableOrUnknown(data['paid_on']!, _paidOnMeta),
      );
    } else if (isInserting) {
      context.missing(_paidOnMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MoneyRepayment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MoneyRepayment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      moneyRecordId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}money_record_id'],
      )!,
      amountPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_paise'],
      )!,
      paidOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}paid_on'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
    );
  }

  @override
  $MoneyRepaymentsTable createAlias(String alias) {
    return $MoneyRepaymentsTable(attachedDatabase, alias);
  }
}

class MoneyRepayment extends DataClass implements Insertable<MoneyRepayment> {
  final int id;
  final int moneyRecordId;
  final int amountPaise;
  final DateTime paidOn;
  final String? notes;
  const MoneyRepayment({
    required this.id,
    required this.moneyRecordId,
    required this.amountPaise,
    required this.paidOn,
    this.notes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['money_record_id'] = Variable<int>(moneyRecordId);
    map['amount_paise'] = Variable<int>(amountPaise);
    map['paid_on'] = Variable<DateTime>(paidOn);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    return map;
  }

  MoneyRepaymentsCompanion toCompanion(bool nullToAbsent) {
    return MoneyRepaymentsCompanion(
      id: Value(id),
      moneyRecordId: Value(moneyRecordId),
      amountPaise: Value(amountPaise),
      paidOn: Value(paidOn),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
    );
  }

  factory MoneyRepayment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MoneyRepayment(
      id: serializer.fromJson<int>(json['id']),
      moneyRecordId: serializer.fromJson<int>(json['moneyRecordId']),
      amountPaise: serializer.fromJson<int>(json['amountPaise']),
      paidOn: serializer.fromJson<DateTime>(json['paidOn']),
      notes: serializer.fromJson<String?>(json['notes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'moneyRecordId': serializer.toJson<int>(moneyRecordId),
      'amountPaise': serializer.toJson<int>(amountPaise),
      'paidOn': serializer.toJson<DateTime>(paidOn),
      'notes': serializer.toJson<String?>(notes),
    };
  }

  MoneyRepayment copyWith({
    int? id,
    int? moneyRecordId,
    int? amountPaise,
    DateTime? paidOn,
    Value<String?> notes = const Value.absent(),
  }) => MoneyRepayment(
    id: id ?? this.id,
    moneyRecordId: moneyRecordId ?? this.moneyRecordId,
    amountPaise: amountPaise ?? this.amountPaise,
    paidOn: paidOn ?? this.paidOn,
    notes: notes.present ? notes.value : this.notes,
  );
  MoneyRepayment copyWithCompanion(MoneyRepaymentsCompanion data) {
    return MoneyRepayment(
      id: data.id.present ? data.id.value : this.id,
      moneyRecordId: data.moneyRecordId.present
          ? data.moneyRecordId.value
          : this.moneyRecordId,
      amountPaise: data.amountPaise.present
          ? data.amountPaise.value
          : this.amountPaise,
      paidOn: data.paidOn.present ? data.paidOn.value : this.paidOn,
      notes: data.notes.present ? data.notes.value : this.notes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MoneyRepayment(')
          ..write('id: $id, ')
          ..write('moneyRecordId: $moneyRecordId, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('paidOn: $paidOn, ')
          ..write('notes: $notes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, moneyRecordId, amountPaise, paidOn, notes);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MoneyRepayment &&
          other.id == this.id &&
          other.moneyRecordId == this.moneyRecordId &&
          other.amountPaise == this.amountPaise &&
          other.paidOn == this.paidOn &&
          other.notes == this.notes);
}

class MoneyRepaymentsCompanion extends UpdateCompanion<MoneyRepayment> {
  final Value<int> id;
  final Value<int> moneyRecordId;
  final Value<int> amountPaise;
  final Value<DateTime> paidOn;
  final Value<String?> notes;
  const MoneyRepaymentsCompanion({
    this.id = const Value.absent(),
    this.moneyRecordId = const Value.absent(),
    this.amountPaise = const Value.absent(),
    this.paidOn = const Value.absent(),
    this.notes = const Value.absent(),
  });
  MoneyRepaymentsCompanion.insert({
    this.id = const Value.absent(),
    required int moneyRecordId,
    required int amountPaise,
    required DateTime paidOn,
    this.notes = const Value.absent(),
  }) : moneyRecordId = Value(moneyRecordId),
       amountPaise = Value(amountPaise),
       paidOn = Value(paidOn);
  static Insertable<MoneyRepayment> custom({
    Expression<int>? id,
    Expression<int>? moneyRecordId,
    Expression<int>? amountPaise,
    Expression<DateTime>? paidOn,
    Expression<String>? notes,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (moneyRecordId != null) 'money_record_id': moneyRecordId,
      if (amountPaise != null) 'amount_paise': amountPaise,
      if (paidOn != null) 'paid_on': paidOn,
      if (notes != null) 'notes': notes,
    });
  }

  MoneyRepaymentsCompanion copyWith({
    Value<int>? id,
    Value<int>? moneyRecordId,
    Value<int>? amountPaise,
    Value<DateTime>? paidOn,
    Value<String?>? notes,
  }) {
    return MoneyRepaymentsCompanion(
      id: id ?? this.id,
      moneyRecordId: moneyRecordId ?? this.moneyRecordId,
      amountPaise: amountPaise ?? this.amountPaise,
      paidOn: paidOn ?? this.paidOn,
      notes: notes ?? this.notes,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (moneyRecordId.present) {
      map['money_record_id'] = Variable<int>(moneyRecordId.value);
    }
    if (amountPaise.present) {
      map['amount_paise'] = Variable<int>(amountPaise.value);
    }
    if (paidOn.present) {
      map['paid_on'] = Variable<DateTime>(paidOn.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MoneyRepaymentsCompanion(')
          ..write('id: $id, ')
          ..write('moneyRecordId: $moneyRecordId, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('paidOn: $paidOn, ')
          ..write('notes: $notes')
          ..write(')'))
        .toString();
  }
}

class $SubscriptionsTable extends Subscriptions
    with TableInfo<$SubscriptionsTable, Subscription> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SubscriptionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 90,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountPaiseMeta = const VerificationMeta(
    'amountPaise',
  );
  @override
  late final GeneratedColumn<int> amountPaise = GeneratedColumn<int>(
    'amount_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<PaymentFrequency, String>
  frequency = GeneratedColumn<String>(
    'frequency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<PaymentFrequency>($SubscriptionsTable.$converterfrequency);
  static const VerificationMeta _nextBillingDateMeta = const VerificationMeta(
    'nextBillingDate',
  );
  @override
  late final GeneratedColumn<DateTime> nextBillingDate =
      GeneratedColumn<DateTime>(
        'next_billing_date',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _paymentMethodIdMeta = const VerificationMeta(
    'paymentMethodId',
  );
  @override
  late final GeneratedColumn<int> paymentMethodId = GeneratedColumn<int>(
    'payment_method_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES payment_methods (id)',
    ),
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SubscriptionStatus, String>
  status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<SubscriptionStatus>($SubscriptionsTable.$converterstatus);
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    amountPaise,
    frequency,
    nextBillingDate,
    paymentMethodId,
    category,
    status,
    notes,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'subscriptions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Subscription> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('amount_paise')) {
      context.handle(
        _amountPaiseMeta,
        amountPaise.isAcceptableOrUnknown(
          data['amount_paise']!,
          _amountPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountPaiseMeta);
    }
    if (data.containsKey('next_billing_date')) {
      context.handle(
        _nextBillingDateMeta,
        nextBillingDate.isAcceptableOrUnknown(
          data['next_billing_date']!,
          _nextBillingDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nextBillingDateMeta);
    }
    if (data.containsKey('payment_method_id')) {
      context.handle(
        _paymentMethodIdMeta,
        paymentMethodId.isAcceptableOrUnknown(
          data['payment_method_id']!,
          _paymentMethodIdMeta,
        ),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Subscription map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Subscription(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      amountPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_paise'],
      )!,
      frequency: $SubscriptionsTable.$converterfrequency.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}frequency'],
        )!,
      ),
      nextBillingDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_billing_date'],
      )!,
      paymentMethodId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}payment_method_id'],
      ),
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      status: $SubscriptionsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SubscriptionsTable createAlias(String alias) {
    return $SubscriptionsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<PaymentFrequency, String, String>
  $converterfrequency = const EnumNameConverter<PaymentFrequency>(
    PaymentFrequency.values,
  );
  static JsonTypeConverter2<SubscriptionStatus, String, String>
  $converterstatus = const EnumNameConverter<SubscriptionStatus>(
    SubscriptionStatus.values,
  );
}

class Subscription extends DataClass implements Insertable<Subscription> {
  final int id;
  final String name;
  final int amountPaise;
  final PaymentFrequency frequency;
  final DateTime nextBillingDate;
  final int? paymentMethodId;
  final String? category;
  final SubscriptionStatus status;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Subscription({
    required this.id,
    required this.name,
    required this.amountPaise,
    required this.frequency,
    required this.nextBillingDate,
    this.paymentMethodId,
    this.category,
    required this.status,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['amount_paise'] = Variable<int>(amountPaise);
    {
      map['frequency'] = Variable<String>(
        $SubscriptionsTable.$converterfrequency.toSql(frequency),
      );
    }
    map['next_billing_date'] = Variable<DateTime>(nextBillingDate);
    if (!nullToAbsent || paymentMethodId != null) {
      map['payment_method_id'] = Variable<int>(paymentMethodId);
    }
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    {
      map['status'] = Variable<String>(
        $SubscriptionsTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SubscriptionsCompanion toCompanion(bool nullToAbsent) {
    return SubscriptionsCompanion(
      id: Value(id),
      name: Value(name),
      amountPaise: Value(amountPaise),
      frequency: Value(frequency),
      nextBillingDate: Value(nextBillingDate),
      paymentMethodId: paymentMethodId == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentMethodId),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      status: Value(status),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Subscription.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Subscription(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      amountPaise: serializer.fromJson<int>(json['amountPaise']),
      frequency: $SubscriptionsTable.$converterfrequency.fromJson(
        serializer.fromJson<String>(json['frequency']),
      ),
      nextBillingDate: serializer.fromJson<DateTime>(json['nextBillingDate']),
      paymentMethodId: serializer.fromJson<int?>(json['paymentMethodId']),
      category: serializer.fromJson<String?>(json['category']),
      status: $SubscriptionsTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'amountPaise': serializer.toJson<int>(amountPaise),
      'frequency': serializer.toJson<String>(
        $SubscriptionsTable.$converterfrequency.toJson(frequency),
      ),
      'nextBillingDate': serializer.toJson<DateTime>(nextBillingDate),
      'paymentMethodId': serializer.toJson<int?>(paymentMethodId),
      'category': serializer.toJson<String?>(category),
      'status': serializer.toJson<String>(
        $SubscriptionsTable.$converterstatus.toJson(status),
      ),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Subscription copyWith({
    int? id,
    String? name,
    int? amountPaise,
    PaymentFrequency? frequency,
    DateTime? nextBillingDate,
    Value<int?> paymentMethodId = const Value.absent(),
    Value<String?> category = const Value.absent(),
    SubscriptionStatus? status,
    Value<String?> notes = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Subscription(
    id: id ?? this.id,
    name: name ?? this.name,
    amountPaise: amountPaise ?? this.amountPaise,
    frequency: frequency ?? this.frequency,
    nextBillingDate: nextBillingDate ?? this.nextBillingDate,
    paymentMethodId: paymentMethodId.present
        ? paymentMethodId.value
        : this.paymentMethodId,
    category: category.present ? category.value : this.category,
    status: status ?? this.status,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Subscription copyWithCompanion(SubscriptionsCompanion data) {
    return Subscription(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      amountPaise: data.amountPaise.present
          ? data.amountPaise.value
          : this.amountPaise,
      frequency: data.frequency.present ? data.frequency.value : this.frequency,
      nextBillingDate: data.nextBillingDate.present
          ? data.nextBillingDate.value
          : this.nextBillingDate,
      paymentMethodId: data.paymentMethodId.present
          ? data.paymentMethodId.value
          : this.paymentMethodId,
      category: data.category.present ? data.category.value : this.category,
      status: data.status.present ? data.status.value : this.status,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Subscription(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('frequency: $frequency, ')
          ..write('nextBillingDate: $nextBillingDate, ')
          ..write('paymentMethodId: $paymentMethodId, ')
          ..write('category: $category, ')
          ..write('status: $status, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    amountPaise,
    frequency,
    nextBillingDate,
    paymentMethodId,
    category,
    status,
    notes,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Subscription &&
          other.id == this.id &&
          other.name == this.name &&
          other.amountPaise == this.amountPaise &&
          other.frequency == this.frequency &&
          other.nextBillingDate == this.nextBillingDate &&
          other.paymentMethodId == this.paymentMethodId &&
          other.category == this.category &&
          other.status == this.status &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SubscriptionsCompanion extends UpdateCompanion<Subscription> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> amountPaise;
  final Value<PaymentFrequency> frequency;
  final Value<DateTime> nextBillingDate;
  final Value<int?> paymentMethodId;
  final Value<String?> category;
  final Value<SubscriptionStatus> status;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const SubscriptionsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.amountPaise = const Value.absent(),
    this.frequency = const Value.absent(),
    this.nextBillingDate = const Value.absent(),
    this.paymentMethodId = const Value.absent(),
    this.category = const Value.absent(),
    this.status = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  SubscriptionsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required int amountPaise,
    required PaymentFrequency frequency,
    required DateTime nextBillingDate,
    this.paymentMethodId = const Value.absent(),
    this.category = const Value.absent(),
    required SubscriptionStatus status,
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : name = Value(name),
       amountPaise = Value(amountPaise),
       frequency = Value(frequency),
       nextBillingDate = Value(nextBillingDate),
       status = Value(status);
  static Insertable<Subscription> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? amountPaise,
    Expression<String>? frequency,
    Expression<DateTime>? nextBillingDate,
    Expression<int>? paymentMethodId,
    Expression<String>? category,
    Expression<String>? status,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (amountPaise != null) 'amount_paise': amountPaise,
      if (frequency != null) 'frequency': frequency,
      if (nextBillingDate != null) 'next_billing_date': nextBillingDate,
      if (paymentMethodId != null) 'payment_method_id': paymentMethodId,
      if (category != null) 'category': category,
      if (status != null) 'status': status,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  SubscriptionsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? amountPaise,
    Value<PaymentFrequency>? frequency,
    Value<DateTime>? nextBillingDate,
    Value<int?>? paymentMethodId,
    Value<String?>? category,
    Value<SubscriptionStatus>? status,
    Value<String?>? notes,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return SubscriptionsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      amountPaise: amountPaise ?? this.amountPaise,
      frequency: frequency ?? this.frequency,
      nextBillingDate: nextBillingDate ?? this.nextBillingDate,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      category: category ?? this.category,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (amountPaise.present) {
      map['amount_paise'] = Variable<int>(amountPaise.value);
    }
    if (frequency.present) {
      map['frequency'] = Variable<String>(
        $SubscriptionsTable.$converterfrequency.toSql(frequency.value),
      );
    }
    if (nextBillingDate.present) {
      map['next_billing_date'] = Variable<DateTime>(nextBillingDate.value);
    }
    if (paymentMethodId.present) {
      map['payment_method_id'] = Variable<int>(paymentMethodId.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $SubscriptionsTable.$converterstatus.toSql(status.value),
      );
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SubscriptionsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('frequency: $frequency, ')
          ..write('nextBillingDate: $nextBillingDate, ')
          ..write('paymentMethodId: $paymentMethodId, ')
          ..write('category: $category, ')
          ..write('status: $status, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Setting copyWith({String? key, String? value}) =>
      Setting(key: key ?? this.key, value: value ?? this.value);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActivityLogsTable extends ActivityLogs
    with TableInfo<$ActivityLogsTable, ActivityLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivityLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<ActivityType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ActivityType>($ActivityLogsTable.$convertertype);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 90,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<int> entityId = GeneratedColumn<int>(
    'entity_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    title,
    description,
    entityType,
    entityId,
    occurredAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activity_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActivityLog> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ActivityLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActivityLog(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      type: $ActivityLogsTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      ),
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}entity_id'],
      ),
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
    );
  }

  @override
  $ActivityLogsTable createAlias(String alias) {
    return $ActivityLogsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ActivityType, String, String> $convertertype =
      const EnumNameConverter<ActivityType>(ActivityType.values);
}

class ActivityLog extends DataClass implements Insertable<ActivityLog> {
  final int id;
  final ActivityType type;
  final String title;
  final String? description;
  final String? entityType;
  final int? entityId;
  final DateTime occurredAt;
  const ActivityLog({
    required this.id,
    required this.type,
    required this.title,
    this.description,
    this.entityType,
    this.entityId,
    required this.occurredAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['type'] = Variable<String>(
        $ActivityLogsTable.$convertertype.toSql(type),
      );
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || entityType != null) {
      map['entity_type'] = Variable<String>(entityType);
    }
    if (!nullToAbsent || entityId != null) {
      map['entity_id'] = Variable<int>(entityId);
    }
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    return map;
  }

  ActivityLogsCompanion toCompanion(bool nullToAbsent) {
    return ActivityLogsCompanion(
      id: Value(id),
      type: Value(type),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      entityType: entityType == null && nullToAbsent
          ? const Value.absent()
          : Value(entityType),
      entityId: entityId == null && nullToAbsent
          ? const Value.absent()
          : Value(entityId),
      occurredAt: Value(occurredAt),
    );
  }

  factory ActivityLog.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActivityLog(
      id: serializer.fromJson<int>(json['id']),
      type: $ActivityLogsTable.$convertertype.fromJson(
        serializer.fromJson<String>(json['type']),
      ),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      entityType: serializer.fromJson<String?>(json['entityType']),
      entityId: serializer.fromJson<int?>(json['entityId']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'type': serializer.toJson<String>(
        $ActivityLogsTable.$convertertype.toJson(type),
      ),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'entityType': serializer.toJson<String?>(entityType),
      'entityId': serializer.toJson<int?>(entityId),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
    };
  }

  ActivityLog copyWith({
    int? id,
    ActivityType? type,
    String? title,
    Value<String?> description = const Value.absent(),
    Value<String?> entityType = const Value.absent(),
    Value<int?> entityId = const Value.absent(),
    DateTime? occurredAt,
  }) => ActivityLog(
    id: id ?? this.id,
    type: type ?? this.type,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    entityType: entityType.present ? entityType.value : this.entityType,
    entityId: entityId.present ? entityId.value : this.entityId,
    occurredAt: occurredAt ?? this.occurredAt,
  );
  ActivityLog copyWithCompanion(ActivityLogsCompanion data) {
    return ActivityLog(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActivityLog(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('occurredAt: $occurredAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    title,
    description,
    entityType,
    entityId,
    occurredAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActivityLog &&
          other.id == this.id &&
          other.type == this.type &&
          other.title == this.title &&
          other.description == this.description &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.occurredAt == this.occurredAt);
}

class ActivityLogsCompanion extends UpdateCompanion<ActivityLog> {
  final Value<int> id;
  final Value<ActivityType> type;
  final Value<String> title;
  final Value<String?> description;
  final Value<String?> entityType;
  final Value<int?> entityId;
  final Value<DateTime> occurredAt;
  const ActivityLogsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.occurredAt = const Value.absent(),
  });
  ActivityLogsCompanion.insert({
    this.id = const Value.absent(),
    required ActivityType type,
    required String title,
    this.description = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.occurredAt = const Value.absent(),
  }) : type = Value(type),
       title = Value(title);
  static Insertable<ActivityLog> custom({
    Expression<int>? id,
    Expression<String>? type,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? entityType,
    Expression<int>? entityId,
    Expression<DateTime>? occurredAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (occurredAt != null) 'occurred_at': occurredAt,
    });
  }

  ActivityLogsCompanion copyWith({
    Value<int>? id,
    Value<ActivityType>? type,
    Value<String>? title,
    Value<String?>? description,
    Value<String?>? entityType,
    Value<int?>? entityId,
    Value<DateTime>? occurredAt,
  }) {
    return ActivityLogsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      occurredAt: occurredAt ?? this.occurredAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $ActivityLogsTable.$convertertype.toSql(type.value),
      );
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<int>(entityId.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivityLogsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('occurredAt: $occurredAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PaymentMethodsTable paymentMethods = $PaymentMethodsTable(this);
  late final $EmisTable emis = $EmisTable(this);
  late final $EmiPaymentsTable emiPayments = $EmiPaymentsTable(this);
  late final $MoneyRecordsTable moneyRecords = $MoneyRecordsTable(this);
  late final $MoneyRepaymentsTable moneyRepayments = $MoneyRepaymentsTable(
    this,
  );
  late final $SubscriptionsTable subscriptions = $SubscriptionsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $ActivityLogsTable activityLogs = $ActivityLogsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    paymentMethods,
    emis,
    emiPayments,
    moneyRecords,
    moneyRepayments,
    subscriptions,
    settings,
    activityLogs,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'emis',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('emi_payments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'money_records',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('money_repayments', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$PaymentMethodsTableCreateCompanionBuilder =
    PaymentMethodsCompanion Function({
      Value<int> id,
      required String label,
      Value<String> kind,
      Value<bool> isArchived,
      Value<DateTime> createdAt,
    });
typedef $$PaymentMethodsTableUpdateCompanionBuilder =
    PaymentMethodsCompanion Function({
      Value<int> id,
      Value<String> label,
      Value<String> kind,
      Value<bool> isArchived,
      Value<DateTime> createdAt,
    });

final class $$PaymentMethodsTableReferences
    extends BaseReferences<_$AppDatabase, $PaymentMethodsTable, PaymentMethod> {
  $$PaymentMethodsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$EmisTable, List<Emi>> _emisRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.emis,
    aliasName: 'payment_methods__id__emis__payment_method_id',
  );

  $$EmisTableProcessedTableManager get emisRefs {
    final manager = $$EmisTableTableManager(
      $_db,
      $_db.emis,
    ).filter((f) => f.paymentMethodId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_emisRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MoneyRecordsTable, List<MoneyRecord>>
  _moneyRecordsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.moneyRecords,
    aliasName: 'payment_methods__id__money_records__payment_method_id',
  );

  $$MoneyRecordsTableProcessedTableManager get moneyRecordsRefs {
    final manager = $$MoneyRecordsTableTableManager(
      $_db,
      $_db.moneyRecords,
    ).filter((f) => f.paymentMethodId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_moneyRecordsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SubscriptionsTable, List<Subscription>>
  _subscriptionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.subscriptions,
    aliasName: 'payment_methods__id__subscriptions__payment_method_id',
  );

  $$SubscriptionsTableProcessedTableManager get subscriptionsRefs {
    final manager = $$SubscriptionsTableTableManager(
      $_db,
      $_db.subscriptions,
    ).filter((f) => f.paymentMethodId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_subscriptionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PaymentMethodsTableFilterComposer
    extends Composer<_$AppDatabase, $PaymentMethodsTable> {
  $$PaymentMethodsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> emisRefs(
    Expression<bool> Function($$EmisTableFilterComposer f) f,
  ) {
    final $$EmisTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.emis,
      getReferencedColumn: (t) => t.paymentMethodId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EmisTableFilterComposer(
            $db: $db,
            $table: $db.emis,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> moneyRecordsRefs(
    Expression<bool> Function($$MoneyRecordsTableFilterComposer f) f,
  ) {
    final $$MoneyRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.moneyRecords,
      getReferencedColumn: (t) => t.paymentMethodId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MoneyRecordsTableFilterComposer(
            $db: $db,
            $table: $db.moneyRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> subscriptionsRefs(
    Expression<bool> Function($$SubscriptionsTableFilterComposer f) f,
  ) {
    final $$SubscriptionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.subscriptions,
      getReferencedColumn: (t) => t.paymentMethodId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubscriptionsTableFilterComposer(
            $db: $db,
            $table: $db.subscriptions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PaymentMethodsTableOrderingComposer
    extends Composer<_$AppDatabase, $PaymentMethodsTable> {
  $$PaymentMethodsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PaymentMethodsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PaymentMethodsTable> {
  $$PaymentMethodsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> emisRefs<T extends Object>(
    Expression<T> Function($$EmisTableAnnotationComposer a) f,
  ) {
    final $$EmisTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.emis,
      getReferencedColumn: (t) => t.paymentMethodId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EmisTableAnnotationComposer(
            $db: $db,
            $table: $db.emis,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> moneyRecordsRefs<T extends Object>(
    Expression<T> Function($$MoneyRecordsTableAnnotationComposer a) f,
  ) {
    final $$MoneyRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.moneyRecords,
      getReferencedColumn: (t) => t.paymentMethodId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MoneyRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.moneyRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> subscriptionsRefs<T extends Object>(
    Expression<T> Function($$SubscriptionsTableAnnotationComposer a) f,
  ) {
    final $$SubscriptionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.subscriptions,
      getReferencedColumn: (t) => t.paymentMethodId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubscriptionsTableAnnotationComposer(
            $db: $db,
            $table: $db.subscriptions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PaymentMethodsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PaymentMethodsTable,
          PaymentMethod,
          $$PaymentMethodsTableFilterComposer,
          $$PaymentMethodsTableOrderingComposer,
          $$PaymentMethodsTableAnnotationComposer,
          $$PaymentMethodsTableCreateCompanionBuilder,
          $$PaymentMethodsTableUpdateCompanionBuilder,
          (PaymentMethod, $$PaymentMethodsTableReferences),
          PaymentMethod,
          PrefetchHooks Function({
            bool emisRefs,
            bool moneyRecordsRefs,
            bool subscriptionsRefs,
          })
        > {
  $$PaymentMethodsTableTableManager(
    _$AppDatabase db,
    $PaymentMethodsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PaymentMethodsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PaymentMethodsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PaymentMethodsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => PaymentMethodsCompanion(
                id: id,
                label: label,
                kind: kind,
                isArchived: isArchived,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String label,
                Value<String> kind = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => PaymentMethodsCompanion.insert(
                id: id,
                label: label,
                kind: kind,
                isArchived: isArchived,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PaymentMethodsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                emisRefs = false,
                moneyRecordsRefs = false,
                subscriptionsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (emisRefs) db.emis,
                    if (moneyRecordsRefs) db.moneyRecords,
                    if (subscriptionsRefs) db.subscriptions,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (emisRefs)
                        await $_getPrefetchedData<
                          PaymentMethod,
                          $PaymentMethodsTable,
                          Emi
                        >(
                          currentTable: table,
                          referencedTable: $$PaymentMethodsTableReferences
                              ._emisRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PaymentMethodsTableReferences(
                                db,
                                table,
                                p0,
                              ).emisRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.paymentMethodId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (moneyRecordsRefs)
                        await $_getPrefetchedData<
                          PaymentMethod,
                          $PaymentMethodsTable,
                          MoneyRecord
                        >(
                          currentTable: table,
                          referencedTable: $$PaymentMethodsTableReferences
                              ._moneyRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PaymentMethodsTableReferences(
                                db,
                                table,
                                p0,
                              ).moneyRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.paymentMethodId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (subscriptionsRefs)
                        await $_getPrefetchedData<
                          PaymentMethod,
                          $PaymentMethodsTable,
                          Subscription
                        >(
                          currentTable: table,
                          referencedTable: $$PaymentMethodsTableReferences
                              ._subscriptionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PaymentMethodsTableReferences(
                                db,
                                table,
                                p0,
                              ).subscriptionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.paymentMethodId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$PaymentMethodsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PaymentMethodsTable,
      PaymentMethod,
      $$PaymentMethodsTableFilterComposer,
      $$PaymentMethodsTableOrderingComposer,
      $$PaymentMethodsTableAnnotationComposer,
      $$PaymentMethodsTableCreateCompanionBuilder,
      $$PaymentMethodsTableUpdateCompanionBuilder,
      (PaymentMethod, $$PaymentMethodsTableReferences),
      PaymentMethod,
      PrefetchHooks Function({
        bool emisRefs,
        bool moneyRecordsRefs,
        bool subscriptionsRefs,
      })
    >;
typedef $$EmisTableCreateCompanionBuilder =
    EmisCompanion Function({
      Value<int> id,
      required String name,
      Value<String?> provider,
      required int principalPaise,
      required int emiAmountPaise,
      Value<double?> interestRate,
      required int tenureMonths,
      required DateTime startDate,
      required DateTime nextDueDate,
      required PaymentFrequency frequency,
      Value<int?> paymentMethodId,
      required EmiStatus status,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$EmisTableUpdateCompanionBuilder =
    EmisCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> provider,
      Value<int> principalPaise,
      Value<int> emiAmountPaise,
      Value<double?> interestRate,
      Value<int> tenureMonths,
      Value<DateTime> startDate,
      Value<DateTime> nextDueDate,
      Value<PaymentFrequency> frequency,
      Value<int?> paymentMethodId,
      Value<EmiStatus> status,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

final class $$EmisTableReferences
    extends BaseReferences<_$AppDatabase, $EmisTable, Emi> {
  $$EmisTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PaymentMethodsTable _paymentMethodIdTable(_$AppDatabase db) => db
      .paymentMethods
      .createAlias('emis__payment_method_id__payment_methods__id');

  $$PaymentMethodsTableProcessedTableManager? get paymentMethodId {
    final $_column = $_itemColumn<int>('payment_method_id');
    if ($_column == null) return null;
    final manager = $$PaymentMethodsTableTableManager(
      $_db,
      $_db.paymentMethods,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_paymentMethodIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$EmiPaymentsTable, List<EmiPayment>>
  _emiPaymentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.emiPayments,
    aliasName: 'emis__id__emi_payments__emi_id',
  );

  $$EmiPaymentsTableProcessedTableManager get emiPaymentsRefs {
    final manager = $$EmiPaymentsTableTableManager(
      $_db,
      $_db.emiPayments,
    ).filter((f) => f.emiId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_emiPaymentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$EmisTableFilterComposer extends Composer<_$AppDatabase, $EmisTable> {
  $$EmisTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get principalPaise => $composableBuilder(
    column: $table.principalPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get emiAmountPaise => $composableBuilder(
    column: $table.emiAmountPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get interestRate => $composableBuilder(
    column: $table.interestRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tenureMonths => $composableBuilder(
    column: $table.tenureMonths,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextDueDate => $composableBuilder(
    column: $table.nextDueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PaymentFrequency, PaymentFrequency, String>
  get frequency => $composableBuilder(
    column: $table.frequency,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<EmiStatus, EmiStatus, String> get status =>
      $composableBuilder(
        column: $table.status,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PaymentMethodsTableFilterComposer get paymentMethodId {
    final $$PaymentMethodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentMethodId,
      referencedTable: $db.paymentMethods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentMethodsTableFilterComposer(
            $db: $db,
            $table: $db.paymentMethods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> emiPaymentsRefs(
    Expression<bool> Function($$EmiPaymentsTableFilterComposer f) f,
  ) {
    final $$EmiPaymentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.emiPayments,
      getReferencedColumn: (t) => t.emiId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EmiPaymentsTableFilterComposer(
            $db: $db,
            $table: $db.emiPayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$EmisTableOrderingComposer extends Composer<_$AppDatabase, $EmisTable> {
  $$EmisTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get principalPaise => $composableBuilder(
    column: $table.principalPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get emiAmountPaise => $composableBuilder(
    column: $table.emiAmountPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get interestRate => $composableBuilder(
    column: $table.interestRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tenureMonths => $composableBuilder(
    column: $table.tenureMonths,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextDueDate => $composableBuilder(
    column: $table.nextDueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get frequency => $composableBuilder(
    column: $table.frequency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PaymentMethodsTableOrderingComposer get paymentMethodId {
    final $$PaymentMethodsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentMethodId,
      referencedTable: $db.paymentMethods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentMethodsTableOrderingComposer(
            $db: $db,
            $table: $db.paymentMethods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EmisTableAnnotationComposer
    extends Composer<_$AppDatabase, $EmisTable> {
  $$EmisTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<int> get principalPaise => $composableBuilder(
    column: $table.principalPaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get emiAmountPaise => $composableBuilder(
    column: $table.emiAmountPaise,
    builder: (column) => column,
  );

  GeneratedColumn<double> get interestRate => $composableBuilder(
    column: $table.interestRate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tenureMonths => $composableBuilder(
    column: $table.tenureMonths,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<DateTime> get nextDueDate => $composableBuilder(
    column: $table.nextDueDate,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<PaymentFrequency, String> get frequency =>
      $composableBuilder(column: $table.frequency, builder: (column) => column);

  GeneratedColumnWithTypeConverter<EmiStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$PaymentMethodsTableAnnotationComposer get paymentMethodId {
    final $$PaymentMethodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentMethodId,
      referencedTable: $db.paymentMethods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentMethodsTableAnnotationComposer(
            $db: $db,
            $table: $db.paymentMethods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> emiPaymentsRefs<T extends Object>(
    Expression<T> Function($$EmiPaymentsTableAnnotationComposer a) f,
  ) {
    final $$EmiPaymentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.emiPayments,
      getReferencedColumn: (t) => t.emiId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EmiPaymentsTableAnnotationComposer(
            $db: $db,
            $table: $db.emiPayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$EmisTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EmisTable,
          Emi,
          $$EmisTableFilterComposer,
          $$EmisTableOrderingComposer,
          $$EmisTableAnnotationComposer,
          $$EmisTableCreateCompanionBuilder,
          $$EmisTableUpdateCompanionBuilder,
          (Emi, $$EmisTableReferences),
          Emi,
          PrefetchHooks Function({bool paymentMethodId, bool emiPaymentsRefs})
        > {
  $$EmisTableTableManager(_$AppDatabase db, $EmisTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EmisTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EmisTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EmisTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> provider = const Value.absent(),
                Value<int> principalPaise = const Value.absent(),
                Value<int> emiAmountPaise = const Value.absent(),
                Value<double?> interestRate = const Value.absent(),
                Value<int> tenureMonths = const Value.absent(),
                Value<DateTime> startDate = const Value.absent(),
                Value<DateTime> nextDueDate = const Value.absent(),
                Value<PaymentFrequency> frequency = const Value.absent(),
                Value<int?> paymentMethodId = const Value.absent(),
                Value<EmiStatus> status = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => EmisCompanion(
                id: id,
                name: name,
                provider: provider,
                principalPaise: principalPaise,
                emiAmountPaise: emiAmountPaise,
                interestRate: interestRate,
                tenureMonths: tenureMonths,
                startDate: startDate,
                nextDueDate: nextDueDate,
                frequency: frequency,
                paymentMethodId: paymentMethodId,
                status: status,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String?> provider = const Value.absent(),
                required int principalPaise,
                required int emiAmountPaise,
                Value<double?> interestRate = const Value.absent(),
                required int tenureMonths,
                required DateTime startDate,
                required DateTime nextDueDate,
                required PaymentFrequency frequency,
                Value<int?> paymentMethodId = const Value.absent(),
                required EmiStatus status,
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => EmisCompanion.insert(
                id: id,
                name: name,
                provider: provider,
                principalPaise: principalPaise,
                emiAmountPaise: emiAmountPaise,
                interestRate: interestRate,
                tenureMonths: tenureMonths,
                startDate: startDate,
                nextDueDate: nextDueDate,
                frequency: frequency,
                paymentMethodId: paymentMethodId,
                status: status,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$EmisTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({paymentMethodId = false, emiPaymentsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (emiPaymentsRefs) db.emiPayments,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (paymentMethodId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.paymentMethodId,
                                    referencedTable: $$EmisTableReferences
                                        ._paymentMethodIdTable(db),
                                    referencedColumn: $$EmisTableReferences
                                        ._paymentMethodIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (emiPaymentsRefs)
                        await $_getPrefetchedData<Emi, $EmisTable, EmiPayment>(
                          currentTable: table,
                          referencedTable: $$EmisTableReferences
                              ._emiPaymentsRefsTable(db),
                          managerFromTypedResult: (p0) => $$EmisTableReferences(
                            db,
                            table,
                            p0,
                          ).emiPaymentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.emiId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$EmisTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EmisTable,
      Emi,
      $$EmisTableFilterComposer,
      $$EmisTableOrderingComposer,
      $$EmisTableAnnotationComposer,
      $$EmisTableCreateCompanionBuilder,
      $$EmisTableUpdateCompanionBuilder,
      (Emi, $$EmisTableReferences),
      Emi,
      PrefetchHooks Function({bool paymentMethodId, bool emiPaymentsRefs})
    >;
typedef $$EmiPaymentsTableCreateCompanionBuilder =
    EmiPaymentsCompanion Function({
      Value<int> id,
      required int emiId,
      required int amountPaise,
      required DateTime paidOn,
      required int installmentNumber,
      Value<bool> paidEarly,
      Value<String?> notes,
    });
typedef $$EmiPaymentsTableUpdateCompanionBuilder =
    EmiPaymentsCompanion Function({
      Value<int> id,
      Value<int> emiId,
      Value<int> amountPaise,
      Value<DateTime> paidOn,
      Value<int> installmentNumber,
      Value<bool> paidEarly,
      Value<String?> notes,
    });

final class $$EmiPaymentsTableReferences
    extends BaseReferences<_$AppDatabase, $EmiPaymentsTable, EmiPayment> {
  $$EmiPaymentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $EmisTable _emiIdTable(_$AppDatabase db) =>
      db.emis.createAlias('emi_payments__emi_id__emis__id');

  $$EmisTableProcessedTableManager get emiId {
    final $_column = $_itemColumn<int>('emi_id')!;

    final manager = $$EmisTableTableManager(
      $_db,
      $_db.emis,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_emiIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EmiPaymentsTableFilterComposer
    extends Composer<_$AppDatabase, $EmiPaymentsTable> {
  $$EmiPaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get paidOn => $composableBuilder(
    column: $table.paidOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get installmentNumber => $composableBuilder(
    column: $table.installmentNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get paidEarly => $composableBuilder(
    column: $table.paidEarly,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  $$EmisTableFilterComposer get emiId {
    final $$EmisTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.emiId,
      referencedTable: $db.emis,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EmisTableFilterComposer(
            $db: $db,
            $table: $db.emis,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EmiPaymentsTableOrderingComposer
    extends Composer<_$AppDatabase, $EmiPaymentsTable> {
  $$EmiPaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get paidOn => $composableBuilder(
    column: $table.paidOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get installmentNumber => $composableBuilder(
    column: $table.installmentNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get paidEarly => $composableBuilder(
    column: $table.paidEarly,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  $$EmisTableOrderingComposer get emiId {
    final $$EmisTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.emiId,
      referencedTable: $db.emis,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EmisTableOrderingComposer(
            $db: $db,
            $table: $db.emis,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EmiPaymentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EmiPaymentsTable> {
  $$EmiPaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get paidOn =>
      $composableBuilder(column: $table.paidOn, builder: (column) => column);

  GeneratedColumn<int> get installmentNumber => $composableBuilder(
    column: $table.installmentNumber,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get paidEarly =>
      $composableBuilder(column: $table.paidEarly, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  $$EmisTableAnnotationComposer get emiId {
    final $$EmisTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.emiId,
      referencedTable: $db.emis,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EmisTableAnnotationComposer(
            $db: $db,
            $table: $db.emis,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EmiPaymentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EmiPaymentsTable,
          EmiPayment,
          $$EmiPaymentsTableFilterComposer,
          $$EmiPaymentsTableOrderingComposer,
          $$EmiPaymentsTableAnnotationComposer,
          $$EmiPaymentsTableCreateCompanionBuilder,
          $$EmiPaymentsTableUpdateCompanionBuilder,
          (EmiPayment, $$EmiPaymentsTableReferences),
          EmiPayment,
          PrefetchHooks Function({bool emiId})
        > {
  $$EmiPaymentsTableTableManager(_$AppDatabase db, $EmiPaymentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EmiPaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EmiPaymentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EmiPaymentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> emiId = const Value.absent(),
                Value<int> amountPaise = const Value.absent(),
                Value<DateTime> paidOn = const Value.absent(),
                Value<int> installmentNumber = const Value.absent(),
                Value<bool> paidEarly = const Value.absent(),
                Value<String?> notes = const Value.absent(),
              }) => EmiPaymentsCompanion(
                id: id,
                emiId: emiId,
                amountPaise: amountPaise,
                paidOn: paidOn,
                installmentNumber: installmentNumber,
                paidEarly: paidEarly,
                notes: notes,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int emiId,
                required int amountPaise,
                required DateTime paidOn,
                required int installmentNumber,
                Value<bool> paidEarly = const Value.absent(),
                Value<String?> notes = const Value.absent(),
              }) => EmiPaymentsCompanion.insert(
                id: id,
                emiId: emiId,
                amountPaise: amountPaise,
                paidOn: paidOn,
                installmentNumber: installmentNumber,
                paidEarly: paidEarly,
                notes: notes,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EmiPaymentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({emiId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (emiId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.emiId,
                                referencedTable: $$EmiPaymentsTableReferences
                                    ._emiIdTable(db),
                                referencedColumn: $$EmiPaymentsTableReferences
                                    ._emiIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$EmiPaymentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EmiPaymentsTable,
      EmiPayment,
      $$EmiPaymentsTableFilterComposer,
      $$EmiPaymentsTableOrderingComposer,
      $$EmiPaymentsTableAnnotationComposer,
      $$EmiPaymentsTableCreateCompanionBuilder,
      $$EmiPaymentsTableUpdateCompanionBuilder,
      (EmiPayment, $$EmiPaymentsTableReferences),
      EmiPayment,
      PrefetchHooks Function({bool emiId})
    >;
typedef $$MoneyRecordsTableCreateCompanionBuilder =
    MoneyRecordsCompanion Function({
      Value<int> id,
      required String personName,
      required MoneyDirection direction,
      required int amountPaise,
      required DateTime recordDate,
      Value<DateTime?> dueDate,
      Value<int?> paymentMethodId,
      required MoneyStatus status,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$MoneyRecordsTableUpdateCompanionBuilder =
    MoneyRecordsCompanion Function({
      Value<int> id,
      Value<String> personName,
      Value<MoneyDirection> direction,
      Value<int> amountPaise,
      Value<DateTime> recordDate,
      Value<DateTime?> dueDate,
      Value<int?> paymentMethodId,
      Value<MoneyStatus> status,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

final class $$MoneyRecordsTableReferences
    extends BaseReferences<_$AppDatabase, $MoneyRecordsTable, MoneyRecord> {
  $$MoneyRecordsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PaymentMethodsTable _paymentMethodIdTable(_$AppDatabase db) => db
      .paymentMethods
      .createAlias('money_records__payment_method_id__payment_methods__id');

  $$PaymentMethodsTableProcessedTableManager? get paymentMethodId {
    final $_column = $_itemColumn<int>('payment_method_id');
    if ($_column == null) return null;
    final manager = $$PaymentMethodsTableTableManager(
      $_db,
      $_db.paymentMethods,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_paymentMethodIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$MoneyRepaymentsTable, List<MoneyRepayment>>
  _moneyRepaymentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.moneyRepayments,
    aliasName: 'money_records__id__money_repayments__money_record_id',
  );

  $$MoneyRepaymentsTableProcessedTableManager get moneyRepaymentsRefs {
    final manager = $$MoneyRepaymentsTableTableManager(
      $_db,
      $_db.moneyRepayments,
    ).filter((f) => f.moneyRecordId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _moneyRepaymentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MoneyRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $MoneyRecordsTable> {
  $$MoneyRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<MoneyDirection, MoneyDirection, String>
  get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get recordDate => $composableBuilder(
    column: $table.recordDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<MoneyStatus, MoneyStatus, String> get status =>
      $composableBuilder(
        column: $table.status,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PaymentMethodsTableFilterComposer get paymentMethodId {
    final $$PaymentMethodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentMethodId,
      referencedTable: $db.paymentMethods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentMethodsTableFilterComposer(
            $db: $db,
            $table: $db.paymentMethods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> moneyRepaymentsRefs(
    Expression<bool> Function($$MoneyRepaymentsTableFilterComposer f) f,
  ) {
    final $$MoneyRepaymentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.moneyRepayments,
      getReferencedColumn: (t) => t.moneyRecordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MoneyRepaymentsTableFilterComposer(
            $db: $db,
            $table: $db.moneyRepayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MoneyRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $MoneyRecordsTable> {
  $$MoneyRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get recordDate => $composableBuilder(
    column: $table.recordDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PaymentMethodsTableOrderingComposer get paymentMethodId {
    final $$PaymentMethodsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentMethodId,
      referencedTable: $db.paymentMethods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentMethodsTableOrderingComposer(
            $db: $db,
            $table: $db.paymentMethods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MoneyRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MoneyRecordsTable> {
  $$MoneyRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<MoneyDirection, String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get recordDate => $composableBuilder(
    column: $table.recordDate,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumnWithTypeConverter<MoneyStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$PaymentMethodsTableAnnotationComposer get paymentMethodId {
    final $$PaymentMethodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentMethodId,
      referencedTable: $db.paymentMethods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentMethodsTableAnnotationComposer(
            $db: $db,
            $table: $db.paymentMethods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> moneyRepaymentsRefs<T extends Object>(
    Expression<T> Function($$MoneyRepaymentsTableAnnotationComposer a) f,
  ) {
    final $$MoneyRepaymentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.moneyRepayments,
      getReferencedColumn: (t) => t.moneyRecordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MoneyRepaymentsTableAnnotationComposer(
            $db: $db,
            $table: $db.moneyRepayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MoneyRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MoneyRecordsTable,
          MoneyRecord,
          $$MoneyRecordsTableFilterComposer,
          $$MoneyRecordsTableOrderingComposer,
          $$MoneyRecordsTableAnnotationComposer,
          $$MoneyRecordsTableCreateCompanionBuilder,
          $$MoneyRecordsTableUpdateCompanionBuilder,
          (MoneyRecord, $$MoneyRecordsTableReferences),
          MoneyRecord,
          PrefetchHooks Function({
            bool paymentMethodId,
            bool moneyRepaymentsRefs,
          })
        > {
  $$MoneyRecordsTableTableManager(_$AppDatabase db, $MoneyRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MoneyRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MoneyRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MoneyRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> personName = const Value.absent(),
                Value<MoneyDirection> direction = const Value.absent(),
                Value<int> amountPaise = const Value.absent(),
                Value<DateTime> recordDate = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<int?> paymentMethodId = const Value.absent(),
                Value<MoneyStatus> status = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => MoneyRecordsCompanion(
                id: id,
                personName: personName,
                direction: direction,
                amountPaise: amountPaise,
                recordDate: recordDate,
                dueDate: dueDate,
                paymentMethodId: paymentMethodId,
                status: status,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String personName,
                required MoneyDirection direction,
                required int amountPaise,
                required DateTime recordDate,
                Value<DateTime?> dueDate = const Value.absent(),
                Value<int?> paymentMethodId = const Value.absent(),
                required MoneyStatus status,
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => MoneyRecordsCompanion.insert(
                id: id,
                personName: personName,
                direction: direction,
                amountPaise: amountPaise,
                recordDate: recordDate,
                dueDate: dueDate,
                paymentMethodId: paymentMethodId,
                status: status,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MoneyRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({paymentMethodId = false, moneyRepaymentsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (moneyRepaymentsRefs) db.moneyRepayments,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (paymentMethodId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.paymentMethodId,
                                    referencedTable:
                                        $$MoneyRecordsTableReferences
                                            ._paymentMethodIdTable(db),
                                    referencedColumn:
                                        $$MoneyRecordsTableReferences
                                            ._paymentMethodIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (moneyRepaymentsRefs)
                        await $_getPrefetchedData<
                          MoneyRecord,
                          $MoneyRecordsTable,
                          MoneyRepayment
                        >(
                          currentTable: table,
                          referencedTable: $$MoneyRecordsTableReferences
                              ._moneyRepaymentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MoneyRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).moneyRepaymentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.moneyRecordId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MoneyRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MoneyRecordsTable,
      MoneyRecord,
      $$MoneyRecordsTableFilterComposer,
      $$MoneyRecordsTableOrderingComposer,
      $$MoneyRecordsTableAnnotationComposer,
      $$MoneyRecordsTableCreateCompanionBuilder,
      $$MoneyRecordsTableUpdateCompanionBuilder,
      (MoneyRecord, $$MoneyRecordsTableReferences),
      MoneyRecord,
      PrefetchHooks Function({bool paymentMethodId, bool moneyRepaymentsRefs})
    >;
typedef $$MoneyRepaymentsTableCreateCompanionBuilder =
    MoneyRepaymentsCompanion Function({
      Value<int> id,
      required int moneyRecordId,
      required int amountPaise,
      required DateTime paidOn,
      Value<String?> notes,
    });
typedef $$MoneyRepaymentsTableUpdateCompanionBuilder =
    MoneyRepaymentsCompanion Function({
      Value<int> id,
      Value<int> moneyRecordId,
      Value<int> amountPaise,
      Value<DateTime> paidOn,
      Value<String?> notes,
    });

final class $$MoneyRepaymentsTableReferences
    extends
        BaseReferences<_$AppDatabase, $MoneyRepaymentsTable, MoneyRepayment> {
  $$MoneyRepaymentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MoneyRecordsTable _moneyRecordIdTable(_$AppDatabase db) => db
      .moneyRecords
      .createAlias('money_repayments__money_record_id__money_records__id');

  $$MoneyRecordsTableProcessedTableManager get moneyRecordId {
    final $_column = $_itemColumn<int>('money_record_id')!;

    final manager = $$MoneyRecordsTableTableManager(
      $_db,
      $_db.moneyRecords,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_moneyRecordIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MoneyRepaymentsTableFilterComposer
    extends Composer<_$AppDatabase, $MoneyRepaymentsTable> {
  $$MoneyRepaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get paidOn => $composableBuilder(
    column: $table.paidOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  $$MoneyRecordsTableFilterComposer get moneyRecordId {
    final $$MoneyRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.moneyRecordId,
      referencedTable: $db.moneyRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MoneyRecordsTableFilterComposer(
            $db: $db,
            $table: $db.moneyRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MoneyRepaymentsTableOrderingComposer
    extends Composer<_$AppDatabase, $MoneyRepaymentsTable> {
  $$MoneyRepaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get paidOn => $composableBuilder(
    column: $table.paidOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  $$MoneyRecordsTableOrderingComposer get moneyRecordId {
    final $$MoneyRecordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.moneyRecordId,
      referencedTable: $db.moneyRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MoneyRecordsTableOrderingComposer(
            $db: $db,
            $table: $db.moneyRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MoneyRepaymentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MoneyRepaymentsTable> {
  $$MoneyRepaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get paidOn =>
      $composableBuilder(column: $table.paidOn, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  $$MoneyRecordsTableAnnotationComposer get moneyRecordId {
    final $$MoneyRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.moneyRecordId,
      referencedTable: $db.moneyRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MoneyRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.moneyRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MoneyRepaymentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MoneyRepaymentsTable,
          MoneyRepayment,
          $$MoneyRepaymentsTableFilterComposer,
          $$MoneyRepaymentsTableOrderingComposer,
          $$MoneyRepaymentsTableAnnotationComposer,
          $$MoneyRepaymentsTableCreateCompanionBuilder,
          $$MoneyRepaymentsTableUpdateCompanionBuilder,
          (MoneyRepayment, $$MoneyRepaymentsTableReferences),
          MoneyRepayment,
          PrefetchHooks Function({bool moneyRecordId})
        > {
  $$MoneyRepaymentsTableTableManager(
    _$AppDatabase db,
    $MoneyRepaymentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MoneyRepaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MoneyRepaymentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MoneyRepaymentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> moneyRecordId = const Value.absent(),
                Value<int> amountPaise = const Value.absent(),
                Value<DateTime> paidOn = const Value.absent(),
                Value<String?> notes = const Value.absent(),
              }) => MoneyRepaymentsCompanion(
                id: id,
                moneyRecordId: moneyRecordId,
                amountPaise: amountPaise,
                paidOn: paidOn,
                notes: notes,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int moneyRecordId,
                required int amountPaise,
                required DateTime paidOn,
                Value<String?> notes = const Value.absent(),
              }) => MoneyRepaymentsCompanion.insert(
                id: id,
                moneyRecordId: moneyRecordId,
                amountPaise: amountPaise,
                paidOn: paidOn,
                notes: notes,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MoneyRepaymentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({moneyRecordId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (moneyRecordId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.moneyRecordId,
                                referencedTable:
                                    $$MoneyRepaymentsTableReferences
                                        ._moneyRecordIdTable(db),
                                referencedColumn:
                                    $$MoneyRepaymentsTableReferences
                                        ._moneyRecordIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MoneyRepaymentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MoneyRepaymentsTable,
      MoneyRepayment,
      $$MoneyRepaymentsTableFilterComposer,
      $$MoneyRepaymentsTableOrderingComposer,
      $$MoneyRepaymentsTableAnnotationComposer,
      $$MoneyRepaymentsTableCreateCompanionBuilder,
      $$MoneyRepaymentsTableUpdateCompanionBuilder,
      (MoneyRepayment, $$MoneyRepaymentsTableReferences),
      MoneyRepayment,
      PrefetchHooks Function({bool moneyRecordId})
    >;
typedef $$SubscriptionsTableCreateCompanionBuilder =
    SubscriptionsCompanion Function({
      Value<int> id,
      required String name,
      required int amountPaise,
      required PaymentFrequency frequency,
      required DateTime nextBillingDate,
      Value<int?> paymentMethodId,
      Value<String?> category,
      required SubscriptionStatus status,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$SubscriptionsTableUpdateCompanionBuilder =
    SubscriptionsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<int> amountPaise,
      Value<PaymentFrequency> frequency,
      Value<DateTime> nextBillingDate,
      Value<int?> paymentMethodId,
      Value<String?> category,
      Value<SubscriptionStatus> status,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

final class $$SubscriptionsTableReferences
    extends BaseReferences<_$AppDatabase, $SubscriptionsTable, Subscription> {
  $$SubscriptionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PaymentMethodsTable _paymentMethodIdTable(_$AppDatabase db) => db
      .paymentMethods
      .createAlias('subscriptions__payment_method_id__payment_methods__id');

  $$PaymentMethodsTableProcessedTableManager? get paymentMethodId {
    final $_column = $_itemColumn<int>('payment_method_id');
    if ($_column == null) return null;
    final manager = $$PaymentMethodsTableTableManager(
      $_db,
      $_db.paymentMethods,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_paymentMethodIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SubscriptionsTableFilterComposer
    extends Composer<_$AppDatabase, $SubscriptionsTable> {
  $$SubscriptionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PaymentFrequency, PaymentFrequency, String>
  get frequency => $composableBuilder(
    column: $table.frequency,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get nextBillingDate => $composableBuilder(
    column: $table.nextBillingDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SubscriptionStatus, SubscriptionStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PaymentMethodsTableFilterComposer get paymentMethodId {
    final $$PaymentMethodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentMethodId,
      referencedTable: $db.paymentMethods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentMethodsTableFilterComposer(
            $db: $db,
            $table: $db.paymentMethods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubscriptionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SubscriptionsTable> {
  $$SubscriptionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get frequency => $composableBuilder(
    column: $table.frequency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextBillingDate => $composableBuilder(
    column: $table.nextBillingDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PaymentMethodsTableOrderingComposer get paymentMethodId {
    final $$PaymentMethodsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentMethodId,
      referencedTable: $db.paymentMethods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentMethodsTableOrderingComposer(
            $db: $db,
            $table: $db.paymentMethods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubscriptionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SubscriptionsTable> {
  $$SubscriptionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<PaymentFrequency, String> get frequency =>
      $composableBuilder(column: $table.frequency, builder: (column) => column);

  GeneratedColumn<DateTime> get nextBillingDate => $composableBuilder(
    column: $table.nextBillingDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SubscriptionStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$PaymentMethodsTableAnnotationComposer get paymentMethodId {
    final $$PaymentMethodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentMethodId,
      referencedTable: $db.paymentMethods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentMethodsTableAnnotationComposer(
            $db: $db,
            $table: $db.paymentMethods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubscriptionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SubscriptionsTable,
          Subscription,
          $$SubscriptionsTableFilterComposer,
          $$SubscriptionsTableOrderingComposer,
          $$SubscriptionsTableAnnotationComposer,
          $$SubscriptionsTableCreateCompanionBuilder,
          $$SubscriptionsTableUpdateCompanionBuilder,
          (Subscription, $$SubscriptionsTableReferences),
          Subscription,
          PrefetchHooks Function({bool paymentMethodId})
        > {
  $$SubscriptionsTableTableManager(_$AppDatabase db, $SubscriptionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SubscriptionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SubscriptionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SubscriptionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> amountPaise = const Value.absent(),
                Value<PaymentFrequency> frequency = const Value.absent(),
                Value<DateTime> nextBillingDate = const Value.absent(),
                Value<int?> paymentMethodId = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<SubscriptionStatus> status = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => SubscriptionsCompanion(
                id: id,
                name: name,
                amountPaise: amountPaise,
                frequency: frequency,
                nextBillingDate: nextBillingDate,
                paymentMethodId: paymentMethodId,
                category: category,
                status: status,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required int amountPaise,
                required PaymentFrequency frequency,
                required DateTime nextBillingDate,
                Value<int?> paymentMethodId = const Value.absent(),
                Value<String?> category = const Value.absent(),
                required SubscriptionStatus status,
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => SubscriptionsCompanion.insert(
                id: id,
                name: name,
                amountPaise: amountPaise,
                frequency: frequency,
                nextBillingDate: nextBillingDate,
                paymentMethodId: paymentMethodId,
                category: category,
                status: status,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SubscriptionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({paymentMethodId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (paymentMethodId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.paymentMethodId,
                                referencedTable: $$SubscriptionsTableReferences
                                    ._paymentMethodIdTable(db),
                                referencedColumn: $$SubscriptionsTableReferences
                                    ._paymentMethodIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SubscriptionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SubscriptionsTable,
      Subscription,
      $$SubscriptionsTableFilterComposer,
      $$SubscriptionsTableOrderingComposer,
      $$SubscriptionsTableAnnotationComposer,
      $$SubscriptionsTableCreateCompanionBuilder,
      $$SubscriptionsTableUpdateCompanionBuilder,
      (Subscription, $$SubscriptionsTableReferences),
      Subscription,
      PrefetchHooks Function({bool paymentMethodId})
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $$ActivityLogsTableCreateCompanionBuilder =
    ActivityLogsCompanion Function({
      Value<int> id,
      required ActivityType type,
      required String title,
      Value<String?> description,
      Value<String?> entityType,
      Value<int?> entityId,
      Value<DateTime> occurredAt,
    });
typedef $$ActivityLogsTableUpdateCompanionBuilder =
    ActivityLogsCompanion Function({
      Value<int> id,
      Value<ActivityType> type,
      Value<String> title,
      Value<String?> description,
      Value<String?> entityType,
      Value<int?> entityId,
      Value<DateTime> occurredAt,
    });

class $$ActivityLogsTableFilterComposer
    extends Composer<_$AppDatabase, $ActivityLogsTable> {
  $$ActivityLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ActivityType, ActivityType, String> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ActivityLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $ActivityLogsTable> {
  $$ActivityLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ActivityLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ActivityLogsTable> {
  $$ActivityLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ActivityType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );
}

class $$ActivityLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ActivityLogsTable,
          ActivityLog,
          $$ActivityLogsTableFilterComposer,
          $$ActivityLogsTableOrderingComposer,
          $$ActivityLogsTableAnnotationComposer,
          $$ActivityLogsTableCreateCompanionBuilder,
          $$ActivityLogsTableUpdateCompanionBuilder,
          (
            ActivityLog,
            BaseReferences<_$AppDatabase, $ActivityLogsTable, ActivityLog>,
          ),
          ActivityLog,
          PrefetchHooks Function()
        > {
  $$ActivityLogsTableTableManager(_$AppDatabase db, $ActivityLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivityLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActivityLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActivityLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<ActivityType> type = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> entityType = const Value.absent(),
                Value<int?> entityId = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
              }) => ActivityLogsCompanion(
                id: id,
                type: type,
                title: title,
                description: description,
                entityType: entityType,
                entityId: entityId,
                occurredAt: occurredAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required ActivityType type,
                required String title,
                Value<String?> description = const Value.absent(),
                Value<String?> entityType = const Value.absent(),
                Value<int?> entityId = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
              }) => ActivityLogsCompanion.insert(
                id: id,
                type: type,
                title: title,
                description: description,
                entityType: entityType,
                entityId: entityId,
                occurredAt: occurredAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ActivityLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ActivityLogsTable,
      ActivityLog,
      $$ActivityLogsTableFilterComposer,
      $$ActivityLogsTableOrderingComposer,
      $$ActivityLogsTableAnnotationComposer,
      $$ActivityLogsTableCreateCompanionBuilder,
      $$ActivityLogsTableUpdateCompanionBuilder,
      (
        ActivityLog,
        BaseReferences<_$AppDatabase, $ActivityLogsTable, ActivityLog>,
      ),
      ActivityLog,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PaymentMethodsTableTableManager get paymentMethods =>
      $$PaymentMethodsTableTableManager(_db, _db.paymentMethods);
  $$EmisTableTableManager get emis => $$EmisTableTableManager(_db, _db.emis);
  $$EmiPaymentsTableTableManager get emiPayments =>
      $$EmiPaymentsTableTableManager(_db, _db.emiPayments);
  $$MoneyRecordsTableTableManager get moneyRecords =>
      $$MoneyRecordsTableTableManager(_db, _db.moneyRecords);
  $$MoneyRepaymentsTableTableManager get moneyRepayments =>
      $$MoneyRepaymentsTableTableManager(_db, _db.moneyRepayments);
  $$SubscriptionsTableTableManager get subscriptions =>
      $$SubscriptionsTableTableManager(_db, _db.subscriptions);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$ActivityLogsTableTableManager get activityLogs =>
      $$ActivityLogsTableTableManager(_db, _db.activityLogs);
}
