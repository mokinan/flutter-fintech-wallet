import 'package:fintech_wallet/core/result/failure.dart';
import 'package:fintech_wallet/features/transactions/domain/wallet_transaction.dart';
import 'package:fintech_wallet/l10n/gen/app_localizations.dart';
import 'package:flutter/widgets.dart';

export 'package:fintech_wallet/l10n/gen/app_localizations.dart';

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  String get localeName => Localizations.localeOf(this).toLanguageTag();
}

extension FailureMessage on AppLocalizations {
  /// Maps a domain failure to a message; raw details never reach the user.
  String failureMessage(Failure failure) => switch (failure) {
    NetworkFailure() => errorNetwork,
    AuthFailure(detail: 'invalid_credentials') => errorInvalidCredentials,
    AuthFailure() => sessionExpiredMessage,
    InsufficientFundsFailure() => errorInsufficientFunds,
    ValidationFailure(detail: 'same_account') => errorSameAccount,
    ServerFailure() => errorServer,
    ValidationFailure() || StorageFailure() => errorGeneric,
  };

  String category(TransactionCategory category) => switch (category) {
    TransactionCategory.groceries => categoryGroceries,
    TransactionCategory.dining => categoryDining,
    TransactionCategory.transport => categoryTransport,
    TransactionCategory.shopping => categoryShopping,
    TransactionCategory.bills => categoryBills,
    TransactionCategory.health => categoryHealth,
    TransactionCategory.entertainment => categoryEntertainment,
    TransactionCategory.salary => categorySalary,
    TransactionCategory.freelance => categoryFreelance,
    TransactionCategory.transfer => categoryTransfer,
    TransactionCategory.other => categoryOther,
  };
}
