import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:fintech_wallet/core/network/connectivity_service.dart';
import 'package:fintech_wallet/features/sync/data/sync_engine.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SyncIndicator extends Equatable {
  const SyncIndicator({this.pending = 0, this.online = true});

  final int pending;
  final bool online;

  @override
  List<Object> get props => [pending, online];
}

class SyncStatusCubit extends Cubit<SyncIndicator> {
  SyncStatusCubit(this._engine, this._connectivity) : super(SyncIndicator(online: _connectivity.isOnline)) {
    _subscriptions
      ..add(_engine.watchPendingCount().listen((count) => emit(SyncIndicator(pending: count, online: state.online))))
      ..add(
        _connectivity.onlineChanges.listen((online) => emit(SyncIndicator(pending: state.pending, online: online))),
      );
  }

  final SyncEngine _engine;
  final ConnectivityService _connectivity;
  final _subscriptions = <StreamSubscription<Object?>>[];

  Future<void> syncNow() => _engine.syncNow();

  @override
  Future<void> close() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    return super.close();
  }
}
