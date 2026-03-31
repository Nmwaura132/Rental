// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
      id: (json['id'] as num).toInt(),
      phoneNumber: json['phoneNumber'] as String,
      email: json['email'] as String?,
      firstName: json['firstName'] as String,
      lastName: json['lastName'] as String,
      role: $enumDecode(_$UserRoleEnumMap, json['role']),
      isVerified: json['isVerified'] as bool,
    );

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
      'id': instance.id,
      'phoneNumber': instance.phoneNumber,
      'email': instance.email,
      'firstName': instance.firstName,
      'lastName': instance.lastName,
      'role': _$UserRoleEnumMap[instance.role]!,
      'isVerified': instance.isVerified,
    };

const _$UserRoleEnumMap = {
  UserRole.landlord: 'landlord',
  UserRole.tenant: 'tenant',
  UserRole.caretaker: 'caretaker',
};
