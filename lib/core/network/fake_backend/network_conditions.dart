import 'dart:math';

import 'package:flutter/foundation.dart';

/// Knobs for the fake backend so offline and flaky-network behaviour can be
/// demonstrated (and tested) without a real server.
class NetworkConditions {
  NetworkConditions({
    this.latency = const Duration(milliseconds: 350),
    this.failureRate = 0,
    this.dropResponseRate = 0,
    Random? random,
  }) : _random = random ?? Random();

  /// Toggled from the developer section in Settings.
  final ValueNotifier<bool> offline = ValueNotifier(false);

  Duration latency;

  /// Probability that the server answers 503 without processing the request.
  double failureRate;

  /// Probability that the server *processes* the request but the response is
  /// lost — the scenario idempotency keys exist for.
  double dropResponseRate;

  final Random _random;

  bool roll(double probability) => probability > 0 && _random.nextDouble() < probability;
}
