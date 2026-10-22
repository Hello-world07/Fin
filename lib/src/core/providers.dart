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
import 'app_lock.dart';
import 'privacy_reveal.dart';

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

final allEmiDetailsProvider = StreamProvider<List<EmiDetail>>((ref) {
  return ref
      .watch(financeRepositoryProvider)
      .watchEmiDetails(includeFriends: true);
});

// null selects All; Home can deep-link to one EMI category without a new route.
final emiOverviewCategoryProvider = StateProvider<EmiCategory?>((ref) => null);

final personalEmiIncomeProvider = StreamProvider<int?>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.settings)
        ..where((table) => table.key.equals('emi.monthlyIncomePaise')))
      .watchSingleOrNull()
      .map((row) {
        final amount = int.tryParse(row?.value ?? '');
        return amount != null && amount > 0 ? amount : null;
      });
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

final dashboardActivityProvider = StreamProvider<List<ActivityLog>>((ref) {
  return ref.watch(financeRepositoryProvider).watchActivity(limit: 5);
});

final payingEmisProvider = StateProvider<Set<int>>((ref) => <int>{});

final appThemeModeProvider =
    StateNotifierProvider<AppThemeModeController, ThemeMode>(
      (ref) => AppThemeModeController(ref.watch(databaseProvider)),
    );

final privacyModeProvider =
    StateNotifierProvider<PrivacyModeController, PrivacySettings>(
      (ref) => PrivacyModeController(ref.watch(databaseProvider)),
    );

enum PrivacyGateRule { revealOnly, hideAndReveal }

class PrivacySettings {
  const PrivacySettings({
    this.enabled = false,
    this.hideOnOpen = false,
    this.requireUnlock = false,
    this.gateRule = PrivacyGateRule.revealOnly,
  });

  final bool enabled;
  final bool hideOnOpen;
  final bool requireUnlock;
  final PrivacyGateRule gateRule;
}

class PrivacyModeController extends StateNotifier<PrivacySettings> {
  PrivacyModeController(this._database) : super(const PrivacySettings()) {
    ready = _restore();
  }

  final AppDatabase _database;
  late final Future<void> ready;
  bool _changed = false;

  Future<void> _restore() async {
    final rows =
        await (_database.select(_database.settings)..where(
              (row) => row.key.isIn([
                'privacy.mode',
                'privacy.hideOnOpen',
                'privacy.requireUnlock',
                'privacy.gateRule',
                'privacy.appLock.enabled',
                'privacy.appLock.secureScreen',
              ]),
            ))
            .get();
    if (_changed || !mounted) return;
    final values = {for (final row in rows) row.key: row.value};
    final hideOnOpen = values['privacy.hideOnOpen'] == 'true';
    final enabled = values['privacy.mode'] == 'true' || hideOnOpen;
    final requireUnlock = values['privacy.requireUnlock'] == null
        ? values['privacy.appLock.enabled'] == 'true'
        : values['privacy.requireUnlock'] == 'true';
    final gateRule = values['privacy.gateRule'] == 'hideAndReveal'
        ? PrivacyGateRule.hideAndReveal
        : PrivacyGateRule.revealOnly;
    PrivacyRevealGate.instance.requiresUnlock = requireUnlock;
    privacyAmountsHidden = enabled;
    state = PrivacySettings(
      enabled: enabled,
      hideOnOpen: hideOnOpen,
      requireUnlock: requireUnlock,
      gateRule: gateRule,
    );
    await _setSecure(enabled, values['privacy.appLock.secureScreen'] == 'true');
  }

  Future<void> setEnabled(bool enabled, {required BuildContext context}) async {
    if (enabled != state.enabled &&
        state.requireUnlock &&
        (!enabled || state.gateRule == PrivacyGateRule.hideAndReveal) &&
        !await PrivacyRevealGate.instance.authorize(context)) {
      return;
    }
    if (!mounted || !context.mounted) return;
    _changed = true;
    privacyAmountsHidden = enabled;
    state = PrivacySettings(
      enabled: enabled,
      hideOnOpen: state.hideOnOpen,
      requireUnlock: state.requireUnlock,
      gateRule: state.gateRule,
    );
    await _write('privacy.mode', enabled);
    final secure =
        await (_database.select(_database.settings)
              ..where((row) => row.key.equals('privacy.appLock.secureScreen')))
            .getSingleOrNull();
    await _setSecure(enabled, secure?.value == 'true');
    unawaited(
      FinanceRepository(
        _database,
      ).refreshLocalReminders().catchError((Object _) {}),
    );
  }

  Future<void> setHideOnOpen(bool enabled) async {
    _changed = true;
    state = PrivacySettings(
      enabled: state.enabled,
      hideOnOpen: enabled,
      requireUnlock: state.requireUnlock,
      gateRule: state.gateRule,
    );
    await _write('privacy.hideOnOpen', enabled);
    unawaited(
      FinanceRepository(
        _database,
      ).refreshLocalReminders().catchError((Object _) {}),
    );
  }

  Future<void> setRequireUnlock(bool enabled, BuildContext context) async {
    if (enabled && !await PrivacyRevealGate.instance.ensurePin(context)) return;
    if (!mounted || !context.mounted) return;
    _changed = true;
    PrivacyRevealGate.instance.requiresUnlock = enabled;
    PrivacyRevealGate.instance.clearGrace();
    state = PrivacySettings(
      enabled: state.enabled,
      hideOnOpen: state.hideOnOpen,
      requireUnlock: enabled,
      gateRule: state.gateRule,
    );
    await _write('privacy.requireUnlock', enabled);
  }

  Future<void> setGateRule(PrivacyGateRule rule) async {
    _changed = true;
    state = PrivacySettings(
      enabled: state.enabled,
      hideOnOpen: state.hideOnOpen,
      requireUnlock: state.requireUnlock,
      gateRule: rule,
    );
    await _database
        .into(_database.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: 'privacy.gateRule', value: rule.name),
        );
  }

  Future<void> syncDefaultForAppLock(bool enabled) async {
    final explicit =
        await (_database.select(_database.settings)
              ..where((row) => row.key.equals('privacy.requireUnlock')))
            .getSingleOrNull();
    if (explicit != null || !mounted) return;
    PrivacyRevealGate.instance.requiresUnlock = enabled;
    state = PrivacySettings(
      enabled: state.enabled,
      hideOnOpen: state.hideOnOpen,
      requireUnlock: enabled,
      gateRule: state.gateRule,
    );
  }

  Future<void> _write(String key, bool value) => _database
      .into(_database.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(key: key, value: value.toString()),
      );

  Future<void> _setSecure(bool privacy, bool lockSetting) async {
    try {
      await LockDisplayService.setSecure(privacy || lockSetting);
    } catch (_) {
      // Privacy text masking remains active if platform window control fails.
    }
  }
}

final amountFormatProvider =
    StateNotifierProvider<AmountFormatController, AmountFormatter>(
      (ref) => AmountFormatController(ref.watch(databaseProvider)),
    );

class AmountFormatController extends StateNotifier<AmountFormatter> {
  AmountFormatController(this._database) : super(const AmountFormatter()) {
    unawaited(_restore());
  }

  final AppDatabase _database;
  bool _hasUserSelection = false;

  Future<void> _restore() async {
    final rows =
        await (_database.select(_database.settings)..where(
              (item) => item.key.isIn([
                'appearance.amountRegion',
                'appearance.currencySymbol',
                'appearance.indianGrouping',
              ]),
            ))
            .get();
    if (!_hasUserSelection) {
      final values = {for (final row in rows) row.key: row.value};
      final region =
          AmountRegion.values
              .where(
                (region) => region.name == values['appearance.amountRegion'],
              )
              .firstOrNull ??
          (values['appearance.indianGrouping'] == 'false'
              ? AmountRegion.unitedStates
              : AmountRegion.india);
      state = AmountFormatter(
        region: region,
        symbol: values['appearance.currencySymbol'] ?? '₹',
      );
      activeAmountFormatter.value = state;
    }
  }

  Future<void> setRegion(AmountRegion region) async {
    _hasUserSelection = true;
    state = AmountFormatter(region: region, symbol: state.symbol);
    activeAmountFormatter.value = state;
    await _write('appearance.amountRegion', region.name);
  }

  Future<void> setSymbol(String symbol) async {
    _hasUserSelection = true;
    state = AmountFormatter(region: state.region, symbol: symbol);
    activeAmountFormatter.value = state;
    await _write('appearance.currencySymbol', symbol);
  }

  Future<void> _write(String key, String value) => _database
      .into(_database.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
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
    state =
        ThemeMode.values
            .where((mode) => mode.name == saved?.value)
            .firstOrNull ??
        ThemeMode.light;
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
