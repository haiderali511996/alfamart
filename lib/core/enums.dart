import 'package:flutter/material.dart';

enum UserRole {
  admin('Admin'),
  manager('Manager');

  const UserRole(this.label);
  final String label;

  static UserRole parse(String v) =>
      UserRole.values.firstWhere((e) => e.name == v, orElse: () => UserRole.manager);
}

/// Payment methods. The first four are accepted at the counters; `credit`
/// is only used for purchases bought on credit from a supplier.
enum PaymentMethod {
  cash('Cash', Icons.payments_outlined),
  pos('POS Machine', Icons.credit_card),
  online('Online Banking', Icons.account_balance),
  jazzcash('JazzCash', Icons.phone_android),
  credit('Credit (Pay Later)', Icons.schedule);

  const PaymentMethod(this.label, this.icon);
  final String label;
  final IconData icon;

  static const salesMethods = [cash, pos, online, jazzcash];

  static PaymentMethod parse(String? v) =>
      PaymentMethod.values.firstWhere((e) => e.name == v, orElse: () => PaymentMethod.cash);
}

const expenseCategories = <String>[
  'Utilities (Electricity/Gas/Water)',
  'Staff Salary / Wages',
  'Tea / Food',
  'Transport / Fuel',
  'Maintenance / Repair',
  'Rent',
  'Packaging / Shopping Bags',
  'Cleaning',
  'Stationery / Printing',
  'Other',
];
