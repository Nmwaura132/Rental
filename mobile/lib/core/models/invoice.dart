import 'package:json_annotation/json_annotation.dart';

part 'invoice.g.dart';

@JsonSerializable()
class Invoice {
  final int id;
  final String invoiceNumber;
  final int lease;
  final String tenantName;
  final String unitNumber;
  final double amountDue;
  final double amountPaid;
  final double balance;
  final DateTime dueDate;
  final String status;
  final DateTime periodStart;
  final DateTime periodEnd;

  const Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.lease,
    required this.tenantName,
    required this.unitNumber,
    required this.amountDue,
    required this.amountPaid,
    required this.balance,
    required this.dueDate,
    required this.status,
    required this.periodStart,
    required this.periodEnd,
  });

  bool get isPaid => status == 'paid';
  bool get isOverdue => status == 'overdue';

  factory Invoice.fromJson(Map<String, dynamic> json) => _$InvoiceFromJson(json);
  Map<String, dynamic> toJson() => _$InvoiceToJson(this);
}
