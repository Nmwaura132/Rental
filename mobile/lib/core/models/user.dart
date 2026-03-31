import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

enum UserRole { landlord, tenant, caretaker }

@JsonSerializable()
class User {
  final int id;
  final String phoneNumber;
  final String? email;
  final String firstName;
  final String lastName;
  final UserRole role;
  final bool isVerified;

  const User({
    required this.id,
    required this.phoneNumber,
    this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.isVerified,
  });

  String get fullName => '$firstName $lastName'.trim();
  bool get isLandlord => role == UserRole.landlord;
  bool get isTenant => role == UserRole.tenant;
  bool get isCaretaker => role == UserRole.caretaker;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
}
