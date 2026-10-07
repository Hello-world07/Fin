import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/core/providers.dart';
import 'package:personal_finance/src/data/database.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase.test(NativeDatabase.memory()));
  tearDown(() => database.close());

  ProviderContainer makeContainer() => ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(database)],
  );

  test('first launch defaults to light when no appearance is saved', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    expect(container.read(appThemeModeProvider), ThemeMode.light);
    await container.read(appThemeModeProvider.notifier).ready;

    expect(container.read(appThemeModeProvider), ThemeMode.light);
  });

  test('manual appearance choice is restored on the next launch', () async {
    final firstLaunch = makeContainer();
    expect(firstLaunch.read(appThemeModeProvider), ThemeMode.light);
    final controller = firstLaunch.read(appThemeModeProvider.notifier);
    controller.setMode(ThemeMode.dark);
    await controller.ready;
    await database.select(database.settings).get();
    firstLaunch.dispose();

    final nextLaunch = makeContainer();
    addTearDown(nextLaunch.dispose);
    expect(nextLaunch.read(appThemeModeProvider), ThemeMode.light);
    await nextLaunch.read(appThemeModeProvider.notifier).ready;

    expect(nextLaunch.read(appThemeModeProvider), ThemeMode.dark);
  });
}
