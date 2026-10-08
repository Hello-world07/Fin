import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/backup_service.dart';
import '../data/csv_export_service.dart';
import '../data/repositories.dart';
import '../domain/enums.dart';
import '../features/assistant/assistant_engine.dart';
import 'formatters.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  return FinanceRepository(ref.watch(databaseProvider));
});

final assistantEngineProvider = Provider<AssistantEngine>((ref) {
  return LocalAssistantEngine(ref.watch(financeRepositoryProvider));
});

final pdfExportProvider = Provider<PdfExportService>((ref) {
  return PdfExportService(ref.watch(databaseProvider));
});

final csvExportProvider = Provider<CsvExportService>((ref) {
  return CsvExportService(ref.watch(databaseProvider));
});

final localBackupProvider = Provider<LocalBackupService>((ref) {
  return LocalBackupService(ref.watch(databaseProvider));
});

final backupStatusProvider = FutureProvider<BackupStatus>((ref) {
  return ref.watch(localBackupProvider).status();
});

final dashboardProvider = StreamProvider<DashboardSummary>((ref) {
  return ref.watch(financeRepositoryProvider).watchDashboard();
});

final emisProvider = StreamProvider<List<Emi>>((ref) {
  return ref.watch(financeRepositoryProvider).watchEmis();
});

final emiDetailsProvider = StreamProvider<List<EmiDetail>>((ref) {
  return ref.watch(financeRepositoryProvider).watchEmiDetails();
});

final moneyRecordsProvider = StreamProvider<List<MoneyRecordDetail>>((ref) {
  return ref.watch(financeRepositoryProvider).watchMoneyRecords();
});

final subscriptionsProvider = StreamProvider<List<Subscription>>((ref) {
  return ref.watch(financeRepositoryProvider).watchSubscriptions();
});

final paymentMethodsProvider = StreamProvider<List<PaymentMethod>>((ref) {
  return ref.watch(financeRepositoryProvider).watchPaymentMethods();
});

final remindersProvider = StreamProvider<List<ReminderItem>>((ref) {
  return ref.watch(financeRepositoryProvider).watchReminders();
});

final financialActionsProvider = StreamProvider<List<ReminderItem>>((ref) {
  return ref
      .watch(financeRepositoryProvider)
      .watchReminders(attentionOnly: false);
});

final activityProvider = StreamProvider<List<ActivityLog>>((ref) {
  return ref.watch(financeRepositoryProvider).watchActivity();
});

final payingEmisProvider = StateProvider<Set<int>>((ref) => <int>{});

final appThemeModeProvider =
    StateNotifierProvider<AppThemeModeController, ThemeMode>(
      (ref) => AppThemeModeController(ref.watch(databaseProvider)),
    );

final numberGroupingProvider =
    StateNotifierProvider<NumberGroupingController, bool>(
      (ref) => NumberGroupingController(ref.watch(databaseProvider)),
    );

class NumberGroupingController extends StateNotifier<bool> {
  NumberGroupingController(this._database) : super(true) {
    unawaited(_restore());
  }

  final AppDatabase _database;
  bool _hasUserSelection = false;

  Future<void> _restore() async {
    final row =
        await (_database.select(_database.settings)
              ..where((item) => item.key.equals('appearance.indianGrouping')))
            .getSingleOrNull();
    if (!_hasUserSelection) {
      state = row?.value != 'false';
      useIndianNumberGrouping = state;
    }
  }

  Future<void> setIndian(bool value) async {
    _hasUserSelection = true;
    state = value;
    useIndianNumberGrouping = value;
    await _database
        .into(_database.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: 'appearance.indianGrouping',
            value: value.toString(),
          ),
        );
  }
}

class AppThemeModeController extends StateNotifier<ThemeMode> {
  AppThemeModeController(this._database) : super(ThemeMode.light) {
    ready = _restoreSavedMode();
  }

  static const _settingKey = 'appearance.themeMode';
  final AppDatabase _database;
  late final Future<void> ready;
  bool _hasUserSelection = false;

  Future<void> _restoreSavedMode() async {
    final saved = await (_database.select(
      _database.settings,
    )..where((setting) => setting.key.equals(_settingKey))).getSingleOrNull();
    if (_hasUserSelection) return;
    state = ThemeMode.values.firstWhere(
      (mode) => mode.name == saved?.value,
      orElse: () => ThemeMode.light,
    );
  }

  void setMode(ThemeMode mode) {
    _hasUserSelection = true;
    state = mode;
    unawaited(_persistMode(mode));
  }

  Future<void> _persistMode(ThemeMode mode) async {
    try {
      await _database
          .into(_database.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(key: _settingKey, value: mode.name),
          );
    } catch (_) {
      // Keep the selected mode active for this session if storage is unavailable.
    }
  }
}

final shellIndexProvider = StateProvider<int>((ref) => 0);

final emiStatusFilterProvider = StateProvider<EmiStatus?>((ref) => null);
