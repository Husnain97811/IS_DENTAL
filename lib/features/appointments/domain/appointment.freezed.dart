// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'appointment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Appointment {

 int get id; String get uuid; int get patientId; String get patientName; String get dentist; int get chair; String get procedure; DateTime get startsAt; int get durationMin; AppointmentStatus get status;
/// Create a copy of Appointment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppointmentCopyWith<Appointment> get copyWith => _$AppointmentCopyWithImpl<Appointment>(this as Appointment, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Appointment&&(identical(other.id, id) || other.id == id)&&(identical(other.uuid, uuid) || other.uuid == uuid)&&(identical(other.patientId, patientId) || other.patientId == patientId)&&(identical(other.patientName, patientName) || other.patientName == patientName)&&(identical(other.dentist, dentist) || other.dentist == dentist)&&(identical(other.chair, chair) || other.chair == chair)&&(identical(other.procedure, procedure) || other.procedure == procedure)&&(identical(other.startsAt, startsAt) || other.startsAt == startsAt)&&(identical(other.durationMin, durationMin) || other.durationMin == durationMin)&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode => Object.hash(runtimeType,id,uuid,patientId,patientName,dentist,chair,procedure,startsAt,durationMin,status);

@override
String toString() {
  return 'Appointment(id: $id, uuid: $uuid, patientId: $patientId, patientName: $patientName, dentist: $dentist, chair: $chair, procedure: $procedure, startsAt: $startsAt, durationMin: $durationMin, status: $status)';
}


}

/// @nodoc
abstract mixin class $AppointmentCopyWith<$Res>  {
  factory $AppointmentCopyWith(Appointment value, $Res Function(Appointment) _then) = _$AppointmentCopyWithImpl;
@useResult
$Res call({
 int id, String uuid, int patientId, String patientName, String dentist, int chair, String procedure, DateTime startsAt, int durationMin, AppointmentStatus status
});




}
/// @nodoc
class _$AppointmentCopyWithImpl<$Res>
    implements $AppointmentCopyWith<$Res> {
  _$AppointmentCopyWithImpl(this._self, this._then);

  final Appointment _self;
  final $Res Function(Appointment) _then;

/// Create a copy of Appointment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? uuid = null,Object? patientId = null,Object? patientName = null,Object? dentist = null,Object? chair = null,Object? procedure = null,Object? startsAt = null,Object? durationMin = null,Object? status = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,uuid: null == uuid ? _self.uuid : uuid // ignore: cast_nullable_to_non_nullable
as String,patientId: null == patientId ? _self.patientId : patientId // ignore: cast_nullable_to_non_nullable
as int,patientName: null == patientName ? _self.patientName : patientName // ignore: cast_nullable_to_non_nullable
as String,dentist: null == dentist ? _self.dentist : dentist // ignore: cast_nullable_to_non_nullable
as String,chair: null == chair ? _self.chair : chair // ignore: cast_nullable_to_non_nullable
as int,procedure: null == procedure ? _self.procedure : procedure // ignore: cast_nullable_to_non_nullable
as String,startsAt: null == startsAt ? _self.startsAt : startsAt // ignore: cast_nullable_to_non_nullable
as DateTime,durationMin: null == durationMin ? _self.durationMin : durationMin // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as AppointmentStatus,
  ));
}

}


/// Adds pattern-matching-related methods to [Appointment].
extension AppointmentPatterns on Appointment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Appointment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Appointment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Appointment value)  $default,){
final _that = this;
switch (_that) {
case _Appointment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Appointment value)?  $default,){
final _that = this;
switch (_that) {
case _Appointment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String uuid,  int patientId,  String patientName,  String dentist,  int chair,  String procedure,  DateTime startsAt,  int durationMin,  AppointmentStatus status)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Appointment() when $default != null:
return $default(_that.id,_that.uuid,_that.patientId,_that.patientName,_that.dentist,_that.chair,_that.procedure,_that.startsAt,_that.durationMin,_that.status);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String uuid,  int patientId,  String patientName,  String dentist,  int chair,  String procedure,  DateTime startsAt,  int durationMin,  AppointmentStatus status)  $default,) {final _that = this;
switch (_that) {
case _Appointment():
return $default(_that.id,_that.uuid,_that.patientId,_that.patientName,_that.dentist,_that.chair,_that.procedure,_that.startsAt,_that.durationMin,_that.status);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String uuid,  int patientId,  String patientName,  String dentist,  int chair,  String procedure,  DateTime startsAt,  int durationMin,  AppointmentStatus status)?  $default,) {final _that = this;
switch (_that) {
case _Appointment() when $default != null:
return $default(_that.id,_that.uuid,_that.patientId,_that.patientName,_that.dentist,_that.chair,_that.procedure,_that.startsAt,_that.durationMin,_that.status);case _:
  return null;

}
}

}

/// @nodoc


class _Appointment extends Appointment {
  const _Appointment({required this.id, required this.uuid, required this.patientId, required this.patientName, required this.dentist, this.chair = 1, required this.procedure, required this.startsAt, this.durationMin = 30, required this.status}): super._();
  

@override final  int id;
@override final  String uuid;
@override final  int patientId;
@override final  String patientName;
@override final  String dentist;
@override@JsonKey() final  int chair;
@override final  String procedure;
@override final  DateTime startsAt;
@override@JsonKey() final  int durationMin;
@override final  AppointmentStatus status;

/// Create a copy of Appointment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppointmentCopyWith<_Appointment> get copyWith => __$AppointmentCopyWithImpl<_Appointment>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Appointment&&(identical(other.id, id) || other.id == id)&&(identical(other.uuid, uuid) || other.uuid == uuid)&&(identical(other.patientId, patientId) || other.patientId == patientId)&&(identical(other.patientName, patientName) || other.patientName == patientName)&&(identical(other.dentist, dentist) || other.dentist == dentist)&&(identical(other.chair, chair) || other.chair == chair)&&(identical(other.procedure, procedure) || other.procedure == procedure)&&(identical(other.startsAt, startsAt) || other.startsAt == startsAt)&&(identical(other.durationMin, durationMin) || other.durationMin == durationMin)&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode => Object.hash(runtimeType,id,uuid,patientId,patientName,dentist,chair,procedure,startsAt,durationMin,status);

@override
String toString() {
  return 'Appointment(id: $id, uuid: $uuid, patientId: $patientId, patientName: $patientName, dentist: $dentist, chair: $chair, procedure: $procedure, startsAt: $startsAt, durationMin: $durationMin, status: $status)';
}


}

/// @nodoc
abstract mixin class _$AppointmentCopyWith<$Res> implements $AppointmentCopyWith<$Res> {
  factory _$AppointmentCopyWith(_Appointment value, $Res Function(_Appointment) _then) = __$AppointmentCopyWithImpl;
@override @useResult
$Res call({
 int id, String uuid, int patientId, String patientName, String dentist, int chair, String procedure, DateTime startsAt, int durationMin, AppointmentStatus status
});




}
/// @nodoc
class __$AppointmentCopyWithImpl<$Res>
    implements _$AppointmentCopyWith<$Res> {
  __$AppointmentCopyWithImpl(this._self, this._then);

  final _Appointment _self;
  final $Res Function(_Appointment) _then;

/// Create a copy of Appointment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? uuid = null,Object? patientId = null,Object? patientName = null,Object? dentist = null,Object? chair = null,Object? procedure = null,Object? startsAt = null,Object? durationMin = null,Object? status = null,}) {
  return _then(_Appointment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,uuid: null == uuid ? _self.uuid : uuid // ignore: cast_nullable_to_non_nullable
as String,patientId: null == patientId ? _self.patientId : patientId // ignore: cast_nullable_to_non_nullable
as int,patientName: null == patientName ? _self.patientName : patientName // ignore: cast_nullable_to_non_nullable
as String,dentist: null == dentist ? _self.dentist : dentist // ignore: cast_nullable_to_non_nullable
as String,chair: null == chair ? _self.chair : chair // ignore: cast_nullable_to_non_nullable
as int,procedure: null == procedure ? _self.procedure : procedure // ignore: cast_nullable_to_non_nullable
as String,startsAt: null == startsAt ? _self.startsAt : startsAt // ignore: cast_nullable_to_non_nullable
as DateTime,durationMin: null == durationMin ? _self.durationMin : durationMin // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as AppointmentStatus,
  ));
}


}

// dart format on
