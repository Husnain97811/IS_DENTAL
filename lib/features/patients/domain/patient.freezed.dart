// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'patient.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Patient {

 int get id; String get uuid; String get code; String get fullName; Gender get gender; int get age; String get phone; String? get allergies; String? get insurance; DateTime? get lastVisit; int get visitCount; int get balance; PatientStatus get status; String get treatmentSummary;
/// Create a copy of Patient
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PatientCopyWith<Patient> get copyWith => _$PatientCopyWithImpl<Patient>(this as Patient, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Patient&&(identical(other.id, id) || other.id == id)&&(identical(other.uuid, uuid) || other.uuid == uuid)&&(identical(other.code, code) || other.code == code)&&(identical(other.fullName, fullName) || other.fullName == fullName)&&(identical(other.gender, gender) || other.gender == gender)&&(identical(other.age, age) || other.age == age)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.allergies, allergies) || other.allergies == allergies)&&(identical(other.insurance, insurance) || other.insurance == insurance)&&(identical(other.lastVisit, lastVisit) || other.lastVisit == lastVisit)&&(identical(other.visitCount, visitCount) || other.visitCount == visitCount)&&(identical(other.balance, balance) || other.balance == balance)&&(identical(other.status, status) || other.status == status)&&(identical(other.treatmentSummary, treatmentSummary) || other.treatmentSummary == treatmentSummary));
}


@override
int get hashCode => Object.hash(runtimeType,id,uuid,code,fullName,gender,age,phone,allergies,insurance,lastVisit,visitCount,balance,status,treatmentSummary);

@override
String toString() {
  return 'Patient(id: $id, uuid: $uuid, code: $code, fullName: $fullName, gender: $gender, age: $age, phone: $phone, allergies: $allergies, insurance: $insurance, lastVisit: $lastVisit, visitCount: $visitCount, balance: $balance, status: $status, treatmentSummary: $treatmentSummary)';
}


}

/// @nodoc
abstract mixin class $PatientCopyWith<$Res>  {
  factory $PatientCopyWith(Patient value, $Res Function(Patient) _then) = _$PatientCopyWithImpl;
@useResult
$Res call({
 int id, String uuid, String code, String fullName, Gender gender, int age, String phone, String? allergies, String? insurance, DateTime? lastVisit, int visitCount, int balance, PatientStatus status, String treatmentSummary
});




}
/// @nodoc
class _$PatientCopyWithImpl<$Res>
    implements $PatientCopyWith<$Res> {
  _$PatientCopyWithImpl(this._self, this._then);

  final Patient _self;
  final $Res Function(Patient) _then;

/// Create a copy of Patient
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? uuid = null,Object? code = null,Object? fullName = null,Object? gender = null,Object? age = null,Object? phone = null,Object? allergies = freezed,Object? insurance = freezed,Object? lastVisit = freezed,Object? visitCount = null,Object? balance = null,Object? status = null,Object? treatmentSummary = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,uuid: null == uuid ? _self.uuid : uuid // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,fullName: null == fullName ? _self.fullName : fullName // ignore: cast_nullable_to_non_nullable
as String,gender: null == gender ? _self.gender : gender // ignore: cast_nullable_to_non_nullable
as Gender,age: null == age ? _self.age : age // ignore: cast_nullable_to_non_nullable
as int,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,allergies: freezed == allergies ? _self.allergies : allergies // ignore: cast_nullable_to_non_nullable
as String?,insurance: freezed == insurance ? _self.insurance : insurance // ignore: cast_nullable_to_non_nullable
as String?,lastVisit: freezed == lastVisit ? _self.lastVisit : lastVisit // ignore: cast_nullable_to_non_nullable
as DateTime?,visitCount: null == visitCount ? _self.visitCount : visitCount // ignore: cast_nullable_to_non_nullable
as int,balance: null == balance ? _self.balance : balance // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as PatientStatus,treatmentSummary: null == treatmentSummary ? _self.treatmentSummary : treatmentSummary // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Patient].
extension PatientPatterns on Patient {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Patient value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Patient() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Patient value)  $default,){
final _that = this;
switch (_that) {
case _Patient():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Patient value)?  $default,){
final _that = this;
switch (_that) {
case _Patient() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String uuid,  String code,  String fullName,  Gender gender,  int age,  String phone,  String? allergies,  String? insurance,  DateTime? lastVisit,  int visitCount,  int balance,  PatientStatus status,  String treatmentSummary)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Patient() when $default != null:
return $default(_that.id,_that.uuid,_that.code,_that.fullName,_that.gender,_that.age,_that.phone,_that.allergies,_that.insurance,_that.lastVisit,_that.visitCount,_that.balance,_that.status,_that.treatmentSummary);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String uuid,  String code,  String fullName,  Gender gender,  int age,  String phone,  String? allergies,  String? insurance,  DateTime? lastVisit,  int visitCount,  int balance,  PatientStatus status,  String treatmentSummary)  $default,) {final _that = this;
switch (_that) {
case _Patient():
return $default(_that.id,_that.uuid,_that.code,_that.fullName,_that.gender,_that.age,_that.phone,_that.allergies,_that.insurance,_that.lastVisit,_that.visitCount,_that.balance,_that.status,_that.treatmentSummary);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String uuid,  String code,  String fullName,  Gender gender,  int age,  String phone,  String? allergies,  String? insurance,  DateTime? lastVisit,  int visitCount,  int balance,  PatientStatus status,  String treatmentSummary)?  $default,) {final _that = this;
switch (_that) {
case _Patient() when $default != null:
return $default(_that.id,_that.uuid,_that.code,_that.fullName,_that.gender,_that.age,_that.phone,_that.allergies,_that.insurance,_that.lastVisit,_that.visitCount,_that.balance,_that.status,_that.treatmentSummary);case _:
  return null;

}
}

}

/// @nodoc


class _Patient extends Patient {
  const _Patient({required this.id, required this.uuid, required this.code, required this.fullName, required this.gender, this.age = 0, this.phone = '', this.allergies, this.insurance, this.lastVisit, this.visitCount = 0, this.balance = 0, required this.status, this.treatmentSummary = ''}): super._();
  

@override final  int id;
@override final  String uuid;
@override final  String code;
@override final  String fullName;
@override final  Gender gender;
@override@JsonKey() final  int age;
@override@JsonKey() final  String phone;
@override final  String? allergies;
@override final  String? insurance;
@override final  DateTime? lastVisit;
@override@JsonKey() final  int visitCount;
@override@JsonKey() final  int balance;
@override final  PatientStatus status;
@override@JsonKey() final  String treatmentSummary;

/// Create a copy of Patient
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PatientCopyWith<_Patient> get copyWith => __$PatientCopyWithImpl<_Patient>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Patient&&(identical(other.id, id) || other.id == id)&&(identical(other.uuid, uuid) || other.uuid == uuid)&&(identical(other.code, code) || other.code == code)&&(identical(other.fullName, fullName) || other.fullName == fullName)&&(identical(other.gender, gender) || other.gender == gender)&&(identical(other.age, age) || other.age == age)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.allergies, allergies) || other.allergies == allergies)&&(identical(other.insurance, insurance) || other.insurance == insurance)&&(identical(other.lastVisit, lastVisit) || other.lastVisit == lastVisit)&&(identical(other.visitCount, visitCount) || other.visitCount == visitCount)&&(identical(other.balance, balance) || other.balance == balance)&&(identical(other.status, status) || other.status == status)&&(identical(other.treatmentSummary, treatmentSummary) || other.treatmentSummary == treatmentSummary));
}


@override
int get hashCode => Object.hash(runtimeType,id,uuid,code,fullName,gender,age,phone,allergies,insurance,lastVisit,visitCount,balance,status,treatmentSummary);

@override
String toString() {
  return 'Patient(id: $id, uuid: $uuid, code: $code, fullName: $fullName, gender: $gender, age: $age, phone: $phone, allergies: $allergies, insurance: $insurance, lastVisit: $lastVisit, visitCount: $visitCount, balance: $balance, status: $status, treatmentSummary: $treatmentSummary)';
}


}

/// @nodoc
abstract mixin class _$PatientCopyWith<$Res> implements $PatientCopyWith<$Res> {
  factory _$PatientCopyWith(_Patient value, $Res Function(_Patient) _then) = __$PatientCopyWithImpl;
@override @useResult
$Res call({
 int id, String uuid, String code, String fullName, Gender gender, int age, String phone, String? allergies, String? insurance, DateTime? lastVisit, int visitCount, int balance, PatientStatus status, String treatmentSummary
});




}
/// @nodoc
class __$PatientCopyWithImpl<$Res>
    implements _$PatientCopyWith<$Res> {
  __$PatientCopyWithImpl(this._self, this._then);

  final _Patient _self;
  final $Res Function(_Patient) _then;

/// Create a copy of Patient
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? uuid = null,Object? code = null,Object? fullName = null,Object? gender = null,Object? age = null,Object? phone = null,Object? allergies = freezed,Object? insurance = freezed,Object? lastVisit = freezed,Object? visitCount = null,Object? balance = null,Object? status = null,Object? treatmentSummary = null,}) {
  return _then(_Patient(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,uuid: null == uuid ? _self.uuid : uuid // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,fullName: null == fullName ? _self.fullName : fullName // ignore: cast_nullable_to_non_nullable
as String,gender: null == gender ? _self.gender : gender // ignore: cast_nullable_to_non_nullable
as Gender,age: null == age ? _self.age : age // ignore: cast_nullable_to_non_nullable
as int,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,allergies: freezed == allergies ? _self.allergies : allergies // ignore: cast_nullable_to_non_nullable
as String?,insurance: freezed == insurance ? _self.insurance : insurance // ignore: cast_nullable_to_non_nullable
as String?,lastVisit: freezed == lastVisit ? _self.lastVisit : lastVisit // ignore: cast_nullable_to_non_nullable
as DateTime?,visitCount: null == visitCount ? _self.visitCount : visitCount // ignore: cast_nullable_to_non_nullable
as int,balance: null == balance ? _self.balance : balance // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as PatientStatus,treatmentSummary: null == treatmentSummary ? _self.treatmentSummary : treatmentSummary // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
