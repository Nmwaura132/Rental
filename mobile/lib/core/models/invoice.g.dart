// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invoice.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Invoice _$InvoiceFromJson(Map<String, dynamic> json) => Invoice(
      id: (json['id'] as num).toInt(),
      invoiceNumber: json['invoiceNumber'] as String,
      lease: (json['lease'] as num).toInt(),
      tenantName: json['tenantName'] as String,
      unitNumber: json['unitNumber'] as String,
      amountDue: (json['amountDue'] as num).toDouble(),
      amountPaid: (json['amountPaid'] as num).toDouble(),
      balance: (json['balance'] as num).toDouble(),
      dueDate: DateTime.parse(json['dueDate'] as String),
      status: json['status'] as String,
      periodStart: DateTime.parse(json['periodStart'] as String),
      periodEnd: DateTime.parse(json['periodEnd'] as String),
    );

Map<String, dynamic> _$InvoiceToJson(Invoice instance) => <String, dynamic>{
      'id': instance.id,
      'invoiceNumber': instance.invoiceNumber,
      'lease': instance.lease,
      'tenantName': instance.tenantName,
      'unitNumber': instance.unitNumber,
      'amountDue': instance.amountDue,
      'amountPaid': instance.amountPaid,
      'balance': instance.balance,
      'dueDate': instance.dueDate.toIso8601String(),
      'status': instance.status,
      'periodStart': instance.periodStart.toIso8601String(),
      'periodEnd': instance.periodEnd.toIso8601String(),
    };
