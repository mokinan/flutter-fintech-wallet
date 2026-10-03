import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fintech_wallet/core/money/currency.dart';
import 'package:fintech_wallet/core/money/money.dart';
import 'package:fintech_wallet/features/transactions/domain/transactions_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/wallet_transaction.dart';
import 'package:fintech_wallet/features/transactions/presentation/history/history_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements TransactionsRepository {}

WalletTransaction _tx(int i) => WalletTransaction(
  id: 'tx$i',
  accountId: 'a',
  amount: Money(-100 * i, Currency.sar),
  category: TransactionCategory.dining,
  note: 'note $i',
  occurredAt: DateTime(2026, 3).subtract(Duration(hours: i)),
  syncStatus: SyncStatus.synced,
);

void main() {
  late _MockRepository repository;
  late StreamController<void> changes;

  final firstPage = TransactionPage([for (var i = 0; i < 2; i++) _tx(i)], PageCursor(_tx(1).occurredAt, 'tx1'));
  final lastPage = TransactionPage([_tx(2)], null);

  setUpAll(() => registerFallbackValue(const TransactionQuery()));

  setUp(() {
    repository = _MockRepository();
    changes = StreamController<void>.broadcast();
    when(() => repository.watchChanges()).thenAnswer((_) => changes.stream);
    when(
      () => repository.page(any(), limit: any(named: 'limit')),
    ).thenAnswer((_) async => firstPage);
    when(
      () => repository.page(
        any(),
        after: any(named: 'after'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((i) async => i.namedArguments[#after] == null ? firstPage : lastPage);
  });

  tearDown(() => changes.close());

  HistoryBloc build() => HistoryBloc(repository, pageSize: 2, debounce: const Duration(milliseconds: 50));

  blocTest<HistoryBloc, HistoryState>(
    'loads the first page',
    build: build,
    act: (bloc) => bloc.add(const HistoryStarted()),
    expect: () => [
      const HistoryState(),
      HistoryState(status: HistoryStatus.ready, items: firstPage.items, cursor: firstPage.next),
    ],
  );

  blocTest<HistoryBloc, HistoryState>(
    'appends the next page and stops at the end',
    build: build,
    seed: () => HistoryState(status: HistoryStatus.ready, items: firstPage.items, cursor: firstPage.next),
    act: (bloc) async {
      bloc.add(const HistoryNextPageRequested());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const HistoryNextPageRequested());
    },
    expect: () => [
      HistoryState(status: HistoryStatus.ready, items: firstPage.items, cursor: firstPage.next, loadingMore: true),
      HistoryState(status: HistoryStatus.ready, items: [...firstPage.items, ...lastPage.items]),
    ],
  );

  blocTest<HistoryBloc, HistoryState>(
    'debounces search so only the final text is queried',
    build: build,
    act: (bloc) async {
      for (final text in ['c', 'co', 'cof', 'coffee']) {
        bloc.add(HistorySearchChanged(text));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    },
    verify: (_) {
      final queries = verify(
        () => repository.page(captureAny(), limit: any(named: 'limit')),
      ).captured.cast<TransactionQuery>();
      expect(queries.map((q) => q.search), ['coffee']);
    },
  );

  blocTest<HistoryBloc, HistoryState>(
    'reloads when local data changes',
    build: build,
    act: (bloc) async {
      bloc.add(const HistoryStarted());
      await Future<void>.delayed(Duration.zero);
      changes.add(null);
      await Future<void>.delayed(Duration.zero);
    },
    verify: (_) => verify(() => repository.page(any(), limit: any(named: 'limit'))).called(2),
  );

  blocTest<HistoryBloc, HistoryState>(
    'changing the filter resets the list',
    build: build,
    seed: () => HistoryState(status: HistoryStatus.ready, items: [...firstPage.items, ...lastPage.items]),
    act: (bloc) => bloc.add(const HistoryKindChanged(TransactionKind.expense)),
    expect: () => [
      isA<HistoryState>()
          .having((s) => s.status, 'status', HistoryStatus.loading)
          .having((s) => s.query.kind, 'kind', TransactionKind.expense),
      isA<HistoryState>().having((s) => s.items, 'items', firstPage.items),
    ],
  );
}
