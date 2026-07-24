// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'branch.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Branch {

 int get id; String get uuid; String get name; String get location; bool get isPrimary; int get openMinutes; int get closeMinutes; int get slotMinutes; String get closedDays;
/// Create a copy of Branch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BranchCopyWith<Branch> get copyWith => _$BranchCopyWithImpl<Branch>(this as Branch, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Branch&&(identical(other.id, id) || other.id == id)&&(identical(other.uuid, uuid) || other.uuid == uuid)&&(identical(other.name, name) || other.name == name)&&(identical(other.location, location) || other.location == location)&&(identical(other.isPrimary, isPrimary) || other.isPrimary == isPrimary)&&(identical(other.openMinutes, openMinutes) || other.openMinutes == openMinutes)&&(identical(other.closeMinutes, closeMinutes) || other.closeMinutes == closeMinutes)&&(identical(other.slotMinutes, slotMinutes) || other.slotMinutes == slotMinutes)&&(identical(other.closedDays, closedDays) || other.closedDays == closedDays));
}


@override
int get hashCode => Object.hash(runtimeType,id,uuid,name,location,isPrimary,openMinutes,closeMinutes,slotMinutes,closedDays);

@override
String toString() {
  return 'Branch(id: $id, uuid: $uuid, name: $name, location: $location, isPrimary: $isPrimary, openMinutes: $openMinutes, closeMinutes: $closeMinutes, slotMinutes: $slotMinutes, closedDays: $closedDays)';
}


}

/// @nodoc
abstract mixin class $BranchCopyWith<$Res>  {
  factory $BranchCopyWith(Branch value, $Res Function(Branch) _then) = _$BranchCopyWithImpl;
@useResult
$Res call({
 int id, String uuid, String name, String location, bool isPrimary, int openMinutes, int closeMinutes, int slotMinutes, String closedDays
});




}
/// @nodoc
class _$BranchCopyWithImpl<$Res>
    implements $BranchCopyWith<$Res> {
  _$BranchCopyWithImpl(this._self, this._then);

  final Branch _self;
  final $Res Function(Branch) _then;

/// Create a copy of Branch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? uuid = null,Object? name = null,Object? location = null,Object? isPrimary = null,Object? openMinutes = null,Object? closeMinutes = null,Object? slotMinutes = null,Object? closedDays = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,uuid: null == uuid ? _self.uuid : uuid // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,location: null == location ? _self.location : location // ignore: cast_nullable_to_non_nullable
as String,isPrimary: null == isPrimary ? _self.isPrimary : isPrimary // ignore: cast_nullable_to_non_nullable
as bool,openMinutes: null == openMinutes ? _self.openMinutes : openMinutes // ignore: cast_nullable_to_non_nullable
as int,closeMinutes: null == closeMinutes ? _self.closeMinutes : closeMinutes // ignore: cast_nullable_to_non_nullable
as int,slotMinutes: null == slotMinutes ? _self.slotMinutes : slotMinutes // ignore: cast_nullable_to_non_nullable
as int,closedDays: null == closedDays ? _self.closedDays : closedDays // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Branch].
extension BranchPatterns on Branch {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Branch value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Branch() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Branch value)  $default,){
final _that = this;
switch (_that) {
case _Branch():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Branch value)?  $default,){
final _that = this;
switch (_that) {
case _Branch() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String uuid,  String name,  String location,  bool isPrimary,  int openMinutes,  int closeMinutes,  int slotMinutes,  String closedDays)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Branch() when $default != null:
return $default(_that.id,_that.uuid,_that.name,_that.location,_that.isPrimary,_that.openMinutes,_that.closeMinutes,_that.slotMinutes,_that.closedDays);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String uuid,  String name,  String location,  bool isPrimary,  int openMinutes,  int closeMinutes,  int slotMinutes,  String closedDays)  $default,) {final _that = this;
switch (_that) {
case _Branch():
return $default(_that.id,_that.uuid,_that.name,_that.location,_that.isPrimary,_that.openMinutes,_that.closeMinutes,_that.slotMinutes,_that.closedDays);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String uuid,  String name,  String location,  bool isPrimary,  int openMinutes,  int closeMinutes,  int slotMinutes,  String closedDays)?  $default,) {final _that = this;
switch (_that) {
case _Branch() when $default != null:
return $default(_that.id,_that.uuid,_that.name,_that.location,_that.isPrimary,_that.openMinutes,_that.closeMinutes,_that.slotMinutes,_that.closedDays);case _:
  return null;

}
}

}

/// @nodoc


class _Branch implements Branch {
  const _Branch({required this.id, required this.uuid, required this.name, this.location = '', this.isPrimary = false, this.openMinutes = 600, this.closeMinutes = 1020, this.slotMinutes = 20, this.closedDays = ''});
  

@override final  int id;
@override final  String uuid;
@override final  String name;
@override@JsonKey() final  String location;
@override@JsonKey() final  bool isPrimary;
@override@JsonKey() final  int openMinutes;
@override@JsonKey() final  int closeMinutes;
@override@JsonKey() final  int slotMinutes;
@override@JsonKey() final  String closedDays;

/// Create a copy of Branch
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BranchCopyWith<_Branch> get copyWith => __$BranchCopyWithImpl<_Branch>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Branch&&(identical(other.id, id) || other.id == id)&&(identical(other.uuid, uuid) || other.uuid == uuid)&&(identical(other.name, name) || other.name == name)&&(identical(other.location, location) || other.location == location)&&(identical(other.isPrimary, isPrimary) || other.isPrimary == isPrimary)&&(identical(other.openMinutes, openMinutes) || other.openMinutes == openMinutes)&&(identical(other.closeMinutes, closeMinutes) || other.closeMinutes == closeMinutes)&&(identical(other.slotMinutes, slotMinutes) || other.slotMinutes == slotMinutes)&&(identical(other.closedDays, closedDays) || other.closedDays == closedDays));
}


@override
int get hashCode => Object.hash(runtimeType,id,uuid,name,location,isPrimary,openMinutes,closeMinutes,slotMinutes,closedDays);

@override
String toString() {
  return 'Branch(id: $id, uuid: $uuid, name: $name, location: $location, isPrimary: $isPrimary, openMinutes: $openMinutes, closeMinutes: $closeMinutes, slotMinutes: $slotMinutes, closedDays: $closedDays)';
}


}

/// @nodoc
abstract mixin class _$BranchCopyWith<$Res> implements $BranchCopyWith<$Res> {
  factory _$BranchCopyWith(_Branch value, $Res Function(_Branch) _then) = __$BranchCopyWithImpl;
@override @useResult
$Res call({
 int id, String uuid, String name, String location, bool isPrimary, int openMinutes, int closeMinutes, int slotMinutes, String closedDays
});




}
/// @nodoc
class __$BranchCopyWithImpl<$Res>
    implements _$BranchCopyWith<$Res> {
  __$BranchCopyWithImpl(this._self, this._then);

  final _Branch _self;
  final $Res Function(_Branch) _then;

/// Create a copy of Branch
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? uuid = null,Object? name = null,Object? location = null,Object? isPrimary = null,Object? openMinutes = null,Object? closeMinutes = null,Object? slotMinutes = null,Object? closedDays = null,}) {
  return _then(_Branch(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,uuid: null == uuid ? _self.uuid : uuid // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,location: null == location ? _self.location : location // ignore: cast_nullable_to_non_nullable
as String,isPrimary: null == isPrimary ? _self.isPrimary : isPrimary // ignore: cast_nullable_to_non_nullable
as bool,openMinutes: null == openMinutes ? _self.openMinutes : openMinutes // ignore: cast_nullable_to_non_nullable
as int,closeMinutes: null == closeMinutes ? _self.closeMinutes : closeMinutes // ignore: cast_nullable_to_non_nullable
as int,slotMinutes: null == slotMinutes ? _self.slotMinutes : slotMinutes // ignore: cast_nullable_to_non_nullable
as int,closedDays: null == closedDays ? _self.closedDays : closedDays // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
