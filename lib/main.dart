import 'dart:async';

import 'package:fintech_wallet/app/app.dart';
import 'package:fintech_wallet/app/di.dart';
import 'package:fintech_wallet/features/auth/presentation/session_cubit.dart';
import 'package:fintech_wallet/features/sync/data/sync_engine.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  getIt<SyncEngine>().start();
  unawaited(getIt<SessionCubit>().bootstrap());
  runApp(const WalletApp());
}
