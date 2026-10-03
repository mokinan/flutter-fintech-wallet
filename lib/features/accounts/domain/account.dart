import 'package:equatable/equatable.dart';
import 'package:fintech_wallet/core/database/tables.dart';
import 'package:fintech_wallet/core/money/currency.dart';
import 'package:fintech_wallet/core/money/money.dart';

export 'package:fintech_wallet/core/database/tables.dart' show AccountType;

class Account extends Equatable {
  const Account({required this.id, required this.name, required this.type, required this.balance});

  final String id;
  final String name;
  final AccountType type;

  /// Opening balance plus every transaction, in the account currency.
  final Money balance;

  Currency get currency => balance.currency;

  @override
  List<Object> get props => [id, name, type, balance];
}
