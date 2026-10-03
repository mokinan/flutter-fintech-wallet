import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:fintech_wallet/features/transactions/domain/transactions_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/wallet_transaction.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class HistoryEvent {
  const HistoryEvent();
}

final class HistoryStarted extends HistoryEvent {
  const HistoryStarted();
}

final class HistorySearchChanged extends HistoryEvent {
  const HistorySearchChanged(this.search);
  final String search;
}

final class HistoryKindChanged extends HistoryEvent {
  const HistoryKindChanged(this.kind);
  final TransactionKind kind;
}

final class HistoryAccountChanged extends HistoryEvent {
  const HistoryAccountChanged(this.accountId);
  final String? accountId;
}

final class HistoryNextPageRequested extends HistoryEvent {
  const HistoryNextPageRequested();
}

final class HistoryDeleteRequested extends HistoryEvent {
  const HistoryDeleteRequested(this.transaction);
  final WalletTransaction transaction;
}

final class _HistoryDataChanged extends HistoryEvent {
  const _HistoryDataChanged();
}

enum HistoryStatus { loading, ready, failure }

class HistoryState extends Equatable {
  const HistoryState({
    this.status = HistoryStatus.loading,
    this.query = const TransactionQuery(),
    this.items = const [],
    this.cursor,
    this.loadingMore = false,
  });

  final HistoryStatus status;
  final TransactionQuery query;
  final List<WalletTransaction> items;
  final PageCursor? cursor;
  final bool loadingMore;

  bool get hasMore => cursor != null;

  HistoryState copyWith({
    HistoryStatus? status,
    TransactionQuery? query,
    List<WalletTransaction>? items,
    PageCursor? Function()? cursor,
    bool? loadingMore,
  }) => HistoryState(
    status: status ?? this.status,
    query: query ?? this.query,
    items: items ?? this.items,
    cursor: cursor != null ? cursor() : this.cursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );

  @override
  List<Object?> get props => [status, query, items, cursor, loadingMore];
}

/// Paginated, filterable transaction history.
///
/// * Search is debounced, and a newer query cancels an in-flight one
///   (`restartable`), so results never arrive out of order.
/// * Page requests are `droppable`: scrolling fast cannot load a page twice.
class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  HistoryBloc(this._repository, {this.pageSize = 20, this.debounce = const Duration(milliseconds: 300)})
    : super(const HistoryState()) {
    on<HistoryStarted>(_onStarted);
    on<HistorySearchChanged>(_onSearchChanged, transformer: _debounceRestartable(debounce));
    on<HistoryKindChanged>((e, emit) => _reload(state.query.copyWith(kind: e.kind), emit), transformer: restartable());
    on<HistoryAccountChanged>(
      (e, emit) => _reload(state.query.copyWith(accountId: () => e.accountId), emit),
      transformer: restartable(),
    );
    on<HistoryNextPageRequested>(_onNextPage, transformer: droppable());
    on<HistoryDeleteRequested>((e, _) => _repository.delete(e.transaction));
    on<_HistoryDataChanged>(_onDataChanged, transformer: restartable());
  }

  final TransactionsRepository _repository;
  final int pageSize;
  final Duration debounce;
  StreamSubscription<void>? _changes;

  Future<void> _onStarted(HistoryStarted event, Emitter<HistoryState> emit) async {
    await _changes?.cancel();
    _changes = _repository.watchChanges().listen((_) => add(const _HistoryDataChanged()));
    await _reload(state.query, emit);
  }

  Future<void> _onSearchChanged(HistorySearchChanged event, Emitter<HistoryState> emit) async {
    if (event.search.trim() == state.query.search.trim()) return;
    await _reload(state.query.copyWith(search: event.search), emit);
  }

  Future<void> _reload(TransactionQuery query, Emitter<HistoryState> emit, {int? limit}) async {
    emit(state.copyWith(status: HistoryStatus.loading, query: query));
    try {
      final page = await _repository.page(query, limit: limit ?? pageSize);
      emit(state.copyWith(status: HistoryStatus.ready, items: page.items, cursor: () => page.next));
    } on Exception {
      emit(state.copyWith(status: HistoryStatus.failure));
    }
  }

  Future<void> _onNextPage(HistoryNextPageRequested event, Emitter<HistoryState> emit) async {
    final cursor = state.cursor;
    if (cursor == null || state.status != HistoryStatus.ready) return;
    emit(state.copyWith(loadingMore: true));
    try {
      final page = await _repository.page(state.query, after: cursor, limit: pageSize);
      emit(state.copyWith(items: [...state.items, ...page.items], cursor: () => page.next, loadingMore: false));
    } on Exception {
      emit(state.copyWith(loadingMore: false));
    }
  }

  /// Local data changed (new transaction, sync status update): reload as many
  /// rows as are currently shown, keeping the scroll position meaningful.
  Future<void> _onDataChanged(_HistoryDataChanged event, Emitter<HistoryState> emit) async {
    final limit = state.items.length < pageSize ? pageSize : state.items.length;
    try {
      final page = await _repository.page(state.query, limit: limit);
      emit(state.copyWith(status: HistoryStatus.ready, items: page.items, cursor: () => page.next));
    } on Exception {
      // Keep showing the current list.
    }
  }

  @override
  Future<void> close() async {
    await _changes?.cancel();
    return super.close();
  }
}

EventTransformer<E> _debounceRestartable<E>(Duration duration) =>
    (events, mapper) => restartable<E>().call(events.transform(_DebounceTransformer(duration)), mapper);

class _DebounceTransformer<T> extends StreamTransformerBase<T, T> {
  const _DebounceTransformer(this.duration);
  final Duration duration;

  @override
  Stream<T> bind(Stream<T> stream) {
    Timer? timer;
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;
    controller = StreamController<T>(
      sync: true,
      onListen: () {
        subscription = stream.listen(
          (event) {
            timer?.cancel();
            timer = Timer(duration, () => controller.add(event));
          },
          onError: controller.addError,
          onDone: () {
            timer?.cancel();
            unawaited(controller.close());
          },
        );
      },
      onCancel: () {
        timer?.cancel();
        return subscription?.cancel();
      },
    );
    return controller.stream;
  }
}
