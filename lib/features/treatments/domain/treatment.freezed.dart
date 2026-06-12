// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'treatment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Treatment {

 int get id; String get uuid; String get name; String get category; int get price; String get duration;
/// Create a copy of Treatment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TreatmentCopyWith<Treatment> get copyWith => _$TreatmentCopyWithImpl<Treatment>(this as Treatment, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Treatment&&(identical(other.id, id) || other.id == id)&&(identical(other.uuid, uuid) || other.uuid == uuid)&&(identical(other.name, name) || other.name == name)&&(identical(other.category, category) || other.category == category)&&(identical(other.price, price) || other.price == price)&&(identical(other.duration, duration) || other.duration == duration));
}


@override
int get hashCode => Object.hash(runtimeType,id,uuid,name,category,price,duration);

@override
String toString() {
  return 'Treatment(id: $id, uuid: $uuid, name: $name, category: $category, price: $price, duration: $duration)';
}


}

/// @nodoc
abstract mixin class $TreatmentCopyWith<$Res>  {
  factory $TreatmentCopyWith(Treatment value, $Res Function(Treatment) _then) = _$TreatmentCopyWithImpl;
@useResult
$Res call({
 int id, String uuid, String name, String category, int price, String duration
});




}
/// @nodoc
class _$TreatmentCopyWithImpl<$Res>
    implements $TreatmentCopyWith<$Res> {
  _$TreatmentCopyWithImpl(this._self, this._then);

  final Treatment _self;
  final $Res Function(Treatment) _then;

/// Create a copy of Treatment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? uuid = null,Object? name = null,Object? category = null,Object? price = null,Object? duration = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,uuid: null == uuid ? _self.uuid : uuid // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as int,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Treatment].
extension TreatmentPatterns on Treatment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Treatment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Treatment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Treatment value)  $default,){
final _that = this;
switch (_that) {
case _Treatment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Treatment value)?  $default,){
final _that = this;
switch (_that) {
case _Treatment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String uuid,  String name,  String category,  int price,  String duration)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Treatment() when $default != null:
return $default(_that.id,_that.uuid,_that.name,_that.category,_that.price,_that.duration);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String uuid,  String name,  String category,  int price,  String duration)  $default,) {final _that = this;
switch (_that) {
case _Treatment():
return $default(_that.id,_that.uuid,_that.name,_that.category,_that.price,_that.duration);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String uuid,  String name,  String category,  int price,  String duration)?  $default,) {final _that = this;
switch (_that) {
case _Treatment() when $default != null:
return $default(_that.id,_that.uuid,_that.name,_that.category,_that.price,_that.duration);case _:
  return null;

}
}

}

/// @nodoc


class _Treatment implements Treatment {
  const _Treatment({required this.id, required this.uuid, required this.name, required this.category, this.price = 0, this.duration = ''});
  

@override final  int id;
@override final  String uuid;
@override final  String name;
@override final  String category;
@override@JsonKey() final  int price;
@override@JsonKey() final  String duration;

/// Create a copy of Treatment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TreatmentCopyWith<_Treatment> get copyWith => __$TreatmentCopyWithImpl<_Treatment>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Treatment&&(identical(other.id, id) || other.id == id)&&(identical(other.uuid, uuid) || other.uuid == uuid)&&(identical(other.name, name) || other.name == name)&&(identical(other.category, category) || other.category == category)&&(identical(other.price, price) || other.price == price)&&(identical(other.duration, duration) || other.duration == duration));
}


@override
int get hashCode => Object.hash(runtimeType,id,uuid,name,category,price,duration);

@override
String toString() {
  return 'Treatment(id: $id, uuid: $uuid, name: $name, category: $category, price: $price, duration: $duration)';
}


}

/// @nodoc
abstract mixin class _$TreatmentCopyWith<$Res> implements $TreatmentCopyWith<$Res> {
  factory _$TreatmentCopyWith(_Treatment value, $Res Function(_Treatment) _then) = __$TreatmentCopyWithImpl;
@override @useResult
$Res call({
 int id, String uuid, String name, String category, int price, String duration
});




}
/// @nodoc
class __$TreatmentCopyWithImpl<$Res>
    implements _$TreatmentCopyWith<$Res> {
  __$TreatmentCopyWithImpl(this._self, this._then);

  final _Treatment _self;
  final $Res Function(_Treatment) _then;

/// Create a copy of Treatment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? uuid = null,Object? name = null,Object? category = null,Object? price = null,Object? duration = null,}) {
  return _then(_Treatment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,uuid: null == uuid ? _self.uuid : uuid // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as int,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
