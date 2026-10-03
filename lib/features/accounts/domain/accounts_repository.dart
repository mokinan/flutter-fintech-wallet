import 'package:fintech_wallet/core/money/money.dart';
import 'package:fintech_wallet/core/result/result.dart';
import 'package:fintech_wallet/features/accounts/domain/account.dart';

abstract interface class AccountsRepository {
  /// Emits whenever an account or any of its transactions changes.
  Stream<List<Account>> watchAccounts();

  Future<Account?> findById(String id);

  Future<Result<Account>> create({required String name, required AccountType type, required Money openingBalance});
}
