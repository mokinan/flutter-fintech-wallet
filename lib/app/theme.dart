import 'package:fintech_wallet/features/transactions/domain/wallet_transaction.dart';
import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seed = Color(0xFF0B6E4F);

  static ThemeData light() => _build(ColorScheme.fromSeed(seedColor: _seed));
  static ThemeData dark() => _build(ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark));

  static ThemeData _build(ColorScheme scheme) => ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, scrolledUnderElevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

/// Positive and negative amount colours that work in light and dark themes.
extension AmountColors on ColorScheme {
  Color get positive => brightness == Brightness.light ? const Color(0xFF1B7F3B) : const Color(0xFF7BD88F);
  Color get negative => error;
}

extension CategoryStyle on TransactionCategory {
  IconData get icon => switch (this) {
    TransactionCategory.groceries => Icons.shopping_basket_outlined,
    TransactionCategory.dining => Icons.restaurant_outlined,
    TransactionCategory.transport => Icons.directions_car_outlined,
    TransactionCategory.shopping => Icons.shopping_bag_outlined,
    TransactionCategory.bills => Icons.receipt_long_outlined,
    TransactionCategory.health => Icons.local_hospital_outlined,
    TransactionCategory.entertainment => Icons.movie_outlined,
    TransactionCategory.salary => Icons.work_outline,
    TransactionCategory.freelance => Icons.laptop_mac_outlined,
    TransactionCategory.transfer => Icons.swap_horiz,
    TransactionCategory.other => Icons.more_horiz,
  };

  Color get color => switch (this) {
    TransactionCategory.groceries => const Color(0xFF2E7D32),
    TransactionCategory.dining => const Color(0xFFEF6C00),
    TransactionCategory.transport => const Color(0xFF1565C0),
    TransactionCategory.shopping => const Color(0xFFAD1457),
    TransactionCategory.bills => const Color(0xFF6A1B9A),
    TransactionCategory.health => const Color(0xFFC62828),
    TransactionCategory.entertainment => const Color(0xFF00838F),
    TransactionCategory.salary => const Color(0xFF1B7F3B),
    TransactionCategory.freelance => const Color(0xFF4E7D1B),
    TransactionCategory.transfer => const Color(0xFF546E7A),
    TransactionCategory.other => const Color(0xFF757575),
  };
}
