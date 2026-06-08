// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'tooth_record.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ToothRecord {

 int get fdi; ToothState get state; String? get note;
/// Create a copy of ToothRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ToothRecordCopyWith<ToothRecord> get copyWith => _$ToothRecordCopyWithImpl<ToothRecord>(this as ToothRecord, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ToothRecord&&(identical(other.fdi, fdi) || other.fdi == fdi)&&(identical(other.state, state) || other.state == state)&&(identical(other.note, note) || other.note == note));
}


@override
int get hashCode => Object.hash(runtimeType,fdi,state,note);

@override
String toString() {
  return 'ToothRecord(fdi: $fdi, state: $state, note: $note)';
}


}

/// @nodoc
abstract mixin class $ToothRecordCopyWith<$Res>  {
  factory $ToothRecordCopyWith(ToothRecord value, $Res Function(ToothRecord) _then) = _$ToothRecordCopyWithImpl;
@useResult
$Res call({
 int fdi, ToothState state, String? note
});




}
/// @nodoc
class _$ToothRecordCopyWithImpl<$Res>
    implements $ToothRecordCopyWith<$Res> {
  _$ToothRecordCopyWithImpl(this._self, this._then);

  final ToothRecord _self;
  final $Res Function(ToothRecord) _then;

/// Create a copy of ToothRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? fdi = null,Object? state = null,Object? note = freezed,}) {
  return _then(_self.copyWith(
fdi: null == fdi ? _self.fdi : fdi // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ToothState,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ToothRecord].
extension ToothRecordPatterns on ToothRecord {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ToothRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ToothRecord() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ToothRecord value)  $default,){
final _that = this;
switch (_that) {
case _ToothRecord():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ToothRecord value)?  $default,){
final _that = this;
switch (_that) {
case _ToothRecord() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int fdi,  ToothState state,  String? note)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ToothRecord() when $default != null:
return $default(_that.fdi,_that.state,_that.note);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int fdi,  ToothState state,  String? note)  $default,) {final _that = this;
switch (_that) {
case _ToothRecord():
return $default(_that.fdi,_that.state,_that.note);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int fdi,  ToothState state,  String? note)?  $default,) {final _that = this;
switch (_that) {
case _ToothRecord() when $default != null:
return $default(_that.fdi,_that.state,_that.note);case _:
  return null;

}
}

}

/// @nodoc


class _ToothRecord implements ToothRecord {
  const _ToothRecord({required this.fdi, required this.state, this.note});
  

@override final  int fdi;
@override final  ToothState state;
@override final  String? note;

/// Create a copy of ToothRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ToothRecordCopyWith<_ToothRecord> get copyWith => __$ToothRecordCopyWithImpl<_ToothRecord>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ToothRecord&&(identical(other.fdi, fdi) || other.fdi == fdi)&&(identical(other.state, state) || other.state == state)&&(identical(other.note, note) || other.note == note));
}


@override
int get hashCode => Object.hash(runtimeType,fdi,state,note);

@override
String toString() {
  return 'ToothRecord(fdi: $fdi, state: $state, note: $note)';
}


}

/// @nodoc
abstract mixin class _$ToothRecordCopyWith<$Res> implements $ToothRecordCopyWith<$Res> {
  factory _$ToothRecordCopyWith(_ToothRecord value, $Res Function(_ToothRecord) _then) = __$ToothRecordCopyWithImpl;
@override @useResult
$Res call({
 int fdi, ToothState state, String? note
});




}
/// @nodoc
class __$ToothRecordCopyWithImpl<$Res>
    implements _$ToothRecordCopyWith<$Res> {
  __$ToothRecordCopyWithImpl(this._self, this._then);

  final _ToothRecord _self;
  final $Res Function(_ToothRecord) _then;

/// Create a copy of ToothRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? fdi = null,Object? state = null,Object? note = freezed,}) {
  return _then(_ToothRecord(
fdi: null == fdi ? _self.fdi : fdi // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ToothState,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
