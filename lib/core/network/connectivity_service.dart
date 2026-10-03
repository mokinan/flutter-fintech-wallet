import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fintech_wallet/core/network/fake_backend/network_conditions.dart';

/// Combines real device connectivity with the simulated offline switch.
abstract interface class ConnectivityService {
  bool get isOnline;
  Stream<bool> get onlineChanges;
}

class DeviceConnectivityService implements ConnectivityService {
  DeviceConnectivityService(this._conditions, [Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity() {
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _deviceOnline = !results.every((r) => r == ConnectivityResult.none);
      _emit();
    });
    _conditions.offline.addListener(_emit);
    unawaited(
      _connectivity.checkConnectivity().then((results) {
        _deviceOnline = !results.every((r) => r == ConnectivityResult.none);
        _emit();
      }),
    );
  }

  final Connectivity _connectivity;
  final NetworkConditions _conditions;
  final _controller = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _deviceOnline = true;
  bool? _last;

  @override
  bool get isOnline => _deviceOnline && !_conditions.offline.value;

  @override
  Stream<bool> get onlineChanges => _controller.stream;

  void _emit() {
    if (_last == isOnline) return;
    _last = isOnline;
    _controller.add(isOnline);
  }

  Future<void> dispose() async {
    _conditions.offline.removeListener(_emit);
    await _subscription?.cancel();
    await _controller.close();
  }
}
