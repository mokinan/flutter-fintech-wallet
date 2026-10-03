import 'package:fintech_wallet/core/money/currency.dart';
import 'package:fintech_wallet/core/money/money.dart';
import 'package:fintech_wallet/core/result/failure.dart';
import 'package:fintech_wallet/core/result/result.dart';
import 'package:fintech_wallet/features/accounts/domain/account.dart';
import 'package:fintech_wallet/features/transactions/domain/transactions_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/wallet_transaction.dart';
import 'package:fintech_wallet/features/transactions/presentation/add/add_transaction_cubit.dart';
import 'package:fintech_wallet/features/transactions/presentation/add/add_transaction_page.dart';
import 'package:fintech_wallet/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements TransactionsRepository {}

void main() {
  const kwdAccount = Account(
    id: 'k',
    name: 'Kuwait account',
    type: AccountType.bank,
    balance: Money(5000, Currency.kwd),
  );
  late _MockRepository repository;

  setUpAll(() {
    registerFallbackValue(TransactionCategory.other);
    registerFallbackValue(const Money.zero(Currency.sar));
    registerFallbackValue(DateTime(2026));
  });

  setUp(() {
    repository = _MockRepository();
  });

  Future<void> pumpPage(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    // A phone-sized surface instead of the default 800x600.
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider(
          create: (_) => AddTransactionCubit(repository, initialAccount: kwdAccount),
          child: const AddTransactionView(accounts: [kwdAccount]),
        ),
      ),
    );
  }

  testWidgets('shows a precision error for the account currency', (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byKey(const Key('amount')), '1.2345');
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid amount (up to 3 decimal places)'), findsOneWidget);
    verifyNever(
      () => repository.add(
        accountId: any(named: 'accountId'),
        amount: any(named: 'amount'),
        category: any(named: 'category'),
        note: any(named: 'note'),
        occurredAt: any(named: 'occurredAt'),
      ),
    );
  });

  testWidgets('saves an expense as a negative amount', (tester) async {
    Money? saved;
    when(
      () => repository.add(
        accountId: any(named: 'accountId'),
        amount: any(named: 'amount'),
        category: any(named: 'category'),
        note: any(named: 'note'),
        occurredAt: any(named: 'occurredAt'),
      ),
    ).thenAnswer((i) async {
      saved = i.namedArguments[#amount] as Money;
      return const Err(InsufficientFundsFailure());
    });

    await pumpPage(tester);
    await tester.enterText(find.byKey(const Key('amount')), '1.250');
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();

    expect(saved, const Money(-1250, Currency.kwd));
    expect(find.text('Insufficient balance in this account'), findsOneWidget);
  });

  testWidgets('renders right-to-left in Arabic', (tester) async {
    await pumpPage(tester, locale: const Locale('ar'));
    expect(find.text('إضافة عملية'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byKey(const Key('amount')))), TextDirection.rtl);
  });
}
