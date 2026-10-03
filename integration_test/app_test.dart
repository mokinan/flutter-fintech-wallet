import 'dart:io';

import 'package:fintech_wallet/app/di.dart';
import 'package:fintech_wallet/core/network/fake_backend/fake_wallet_server.dart';
import 'package:fintech_wallet/core/network/fake_backend/network_conditions.dart';
import 'package:fintech_wallet/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end: sign in, create a PIN, add a transaction while offline, watch
/// it sync on reconnect, and make a cross-currency transfer.
///
/// Run with `flutter drive --driver=test_driver/integration_test.dart
/// --target=integration_test/app_test.dart` to also save screenshots.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester tester, String name) async {
    for (final messenger in tester.stateList<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))) {
      messenger.clearSnackBars();
    }
    // pump(duration) does not wait in live mode; let animations finish.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await binding.takeScreenshot(name);
  }

  testWidgets('offline write syncs after reconnecting', (tester) async {
    // Keychain entries survive app reinstalls on iOS; start clean.
    await const FlutterSecureStorage().deleteAll();
    await (await SharedPreferences.getInstance()).clear();
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();

    await app.main();
    await tester.pumpUntil(find.text('Use demo account'));

    // Sign in.
    await tester.tap(find.text('Use demo account'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpUntil(find.text('Create a PIN'));

    // Create and confirm the PIN.
    Future<void> enterPin() async {
      for (final digit in '135790'.split('')) {
        await tester.tap(find.text(digit));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await enterPin();
    await tester.pumpUntil(find.text('Confirm your PIN'));
    await enterPin();
    await tester.pumpUntil(find.text('Total balance'));
    await tester.pumpUntil(find.text('All changes synced'));
    await shot(tester, 'home');

    // Go offline and add an expense.
    getIt<NetworkConditions>().offline.value = true;
    await tester.pumpUntil(find.textContaining('Offline'));
    await tester.tap(find.text('Add transaction'));
    await tester.pumpUntil(find.byKey(const Key('amount')));
    await tester.enterText(find.byKey(const Key('amount')), '48.50');
    await tester.tap(find.text('Dining'));
    await tester.enterText(find.widgetWithText(TextField, 'Note (optional)'), 'Team lunch');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 600));
    await shot(tester, 'add_transaction');
    await tester.ensureVisible(find.byKey(const Key('save')));
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpUntil(find.textContaining('1 change saved on device'));
    await shot(tester, 'offline_pending');

    // Reconnect: the outbox drains on its own.
    getIt<NetworkConditions>().offline.value = false;
    await tester.pumpUntil(find.text('All changes synced'));
    await shot(tester, 'synced');
    expect(getIt<FakeWalletServer>().transactions.values.where((t) => t['note'] == 'Team lunch'), hasLength(1));

    // Cross-currency transfer preview.
    await tester.tap(find.byIcon(Icons.swap_horiz).first);
    await tester.pumpUntil(find.text('From'));
    await tester.tap(find.text('To'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('USD savings').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '375');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpUntil(find.text('Recipient account receives'));
    await tester.pump(const Duration(milliseconds: 600));
    await shot(tester, 'transfer');
    await tester.pageBack();
    await tester.pumpUntil(find.text('Total balance'));

    // History and insights.
    await tester.tap(find.text('History').last);
    await tester.pumpUntil(find.text('Team lunch'));
    await shot(tester, 'history');
    await tester.tap(find.text('Insights').last);
    await tester.pumpUntil(find.text('Spending by category'));
    // The current month has only just started; show a full one.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpUntil(find.text('Groceries'));
    await tester.pump(const Duration(seconds: 1));
    await shot(tester, 'insights');

    // Arabic, right-to-left.
    await tester.tap(find.text('Settings').last);
    await tester.pumpUntil(find.text('ع'));
    await tester.tap(find.text('ع'));
    await tester.pumpUntil(find.text('الإعدادات'));
    await tester.tap(find.text('الرئيسية'));
    await tester.pumpUntil(find.text('إجمالي الرصيد'));
    await shot(tester, 'home_arabic');
  });
}

extension on WidgetTester {
  /// Like `pumpAndSettle`, but works while progress indicators animate.
  Future<void> pumpUntil(Finder finder, {Duration timeout = const Duration(seconds: 15)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await pump(const Duration(milliseconds: 100));
      if (any(finder)) return;
    }
    throw TestFailure('Timed out waiting for $finder');
  }
}
