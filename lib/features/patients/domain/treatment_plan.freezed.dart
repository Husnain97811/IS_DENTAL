// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'treatment_plan.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TreatmentStep {

 int get id; int get order; String get label; String get detail; StepStatus get status; DateTime? get completedAt;
/// Create a copy of TreatmentStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TreatmentStepCopyWith<TreatmentStep> get copyWith => _$TreatmentStepCopyWithImpl<TreatmentStep>(this as TreatmentStep, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TreatmentStep&&(identical(other.id, id) || other.id == id)&&(identical(other.order, order) || other.order == order)&&(identical(other.label, label) || other.label == label)&&(identical(other.detail, detail) || other.detail == detail)&&(identical(other.status, status) || other.status == status)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,order,label,detail,status,completedAt);

@override
String toString() {
  return 'TreatmentStep(id: $id, order: $order, label: $label, detail: $detail, status: $status, completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class $TreatmentStepCopyWith<$Res>  {
  factory $TreatmentStepCopyWith(TreatmentStep value, $Res Function(TreatmentStep) _then) = _$TreatmentStepCopyWithImpl;
@useResult
$Res call({
 int id, int order, String label, String detail, StepStatus status, DateTime? completedAt
});




}
/// @nodoc
class _$TreatmentStepCopyWithImpl<$Res>
    implements $TreatmentStepCopyWith<$Res> {
  _$TreatmentStepCopyWithImpl(this._self, this._then);

  final TreatmentStep _self;
  final $Res Function(TreatmentStep) _then;

/// Create a copy of TreatmentStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? order = null,Object? label = null,Object? detail = null,Object? status = null,Object? completedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,order: null == order ? _self.order : order // ignore: cast_nullable_to_non_nullable
as int,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as StepStatus,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [TreatmentStep].
extension TreatmentStepPatterns on TreatmentStep {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TreatmentStep value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TreatmentStep() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TreatmentStep value)  $default,){
final _that = this;
switch (_that) {
case _TreatmentStep():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TreatmentStep value)?  $default,){
final _that = this;
switch (_that) {
case _TreatmentStep() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  int order,  String label,  String detail,  StepStatus status,  DateTime? completedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TreatmentStep() when $default != null:
return $default(_that.id,_that.order,_that.label,_that.detail,_that.status,_that.completedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  int order,  String label,  String detail,  StepStatus status,  DateTime? completedAt)  $default,) {final _that = this;
switch (_that) {
case _TreatmentStep():
return $default(_that.id,_that.order,_that.label,_that.detail,_that.status,_that.completedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  int order,  String label,  String detail,  StepStatus status,  DateTime? completedAt)?  $default,) {final _that = this;
switch (_that) {
case _TreatmentStep() when $default != null:
return $default(_that.id,_that.order,_that.label,_that.detail,_that.status,_that.completedAt);case _:
  return null;

}
}

}

/// @nodoc


class _TreatmentStep implements TreatmentStep {
  const _TreatmentStep({required this.id, required this.order, required this.label, this.detail = '', required this.status, this.completedAt});
  

@override final  int id;
@override final  int order;
@override final  String label;
@override@JsonKey() final  String detail;
@override final  StepStatus status;
@override final  DateTime? completedAt;

/// Create a copy of TreatmentStep
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TreatmentStepCopyWith<_TreatmentStep> get copyWith => __$TreatmentStepCopyWithImpl<_TreatmentStep>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TreatmentStep&&(identical(other.id, id) || other.id == id)&&(identical(other.order, order) || other.order == order)&&(identical(other.label, label) || other.label == label)&&(identical(other.detail, detail) || other.detail == detail)&&(identical(other.status, status) || other.status == status)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,order,label,detail,status,completedAt);

@override
String toString() {
  return 'TreatmentStep(id: $id, order: $order, label: $label, detail: $detail, status: $status, completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class _$TreatmentStepCopyWith<$Res> implements $TreatmentStepCopyWith<$Res> {
  factory _$TreatmentStepCopyWith(_TreatmentStep value, $Res Function(_TreatmentStep) _then) = __$TreatmentStepCopyWithImpl;
@override @useResult
$Res call({
 int id, int order, String label, String detail, StepStatus status, DateTime? completedAt
});




}
/// @nodoc
class __$TreatmentStepCopyWithImpl<$Res>
    implements _$TreatmentStepCopyWith<$Res> {
  __$TreatmentStepCopyWithImpl(this._self, this._then);

  final _TreatmentStep _self;
  final $Res Function(_TreatmentStep) _then;

/// Create a copy of TreatmentStep
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? order = null,Object? label = null,Object? detail = null,Object? status = null,Object? completedAt = freezed,}) {
  return _then(_TreatmentStep(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,order: null == order ? _self.order : order // ignore: cast_nullable_to_non_nullable
as int,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as StepStatus,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc
mixin _$TreatmentPlan {

 int get id; String get title; List<TreatmentStep> get steps;
/// Create a copy of TreatmentPlan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TreatmentPlanCopyWith<TreatmentPlan> get copyWith => _$TreatmentPlanCopyWithImpl<TreatmentPlan>(this as TreatmentPlan, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TreatmentPlan&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other.steps, steps));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,const DeepCollectionEquality().hash(steps));

@override
String toString() {
  return 'TreatmentPlan(id: $id, title: $title, steps: $steps)';
}


}

/// @nodoc
abstract mixin class $TreatmentPlanCopyWith<$Res>  {
  factory $TreatmentPlanCopyWith(TreatmentPlan value, $Res Function(TreatmentPlan) _then) = _$TreatmentPlanCopyWithImpl;
@useResult
$Res call({
 int id, String title, List<TreatmentStep> steps
});




}
/// @nodoc
class _$TreatmentPlanCopyWithImpl<$Res>
    implements $TreatmentPlanCopyWith<$Res> {
  _$TreatmentPlanCopyWithImpl(this._self, this._then);

  final TreatmentPlan _self;
  final $Res Function(TreatmentPlan) _then;

/// Create a copy of TreatmentPlan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? steps = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,steps: null == steps ? _self.steps : steps // ignore: cast_nullable_to_non_nullable
as List<TreatmentStep>,
  ));
}

}


/// Adds pattern-matching-related methods to [TreatmentPlan].
extension TreatmentPlanPatterns on TreatmentPlan {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TreatmentPlan value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TreatmentPlan() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TreatmentPlan value)  $default,){
final _that = this;
switch (_that) {
case _TreatmentPlan():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TreatmentPlan value)?  $default,){
final _that = this;
switch (_that) {
case _TreatmentPlan() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String title,  List<TreatmentStep> steps)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TreatmentPlan() when $default != null:
return $default(_that.id,_that.title,_that.steps);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String title,  List<TreatmentStep> steps)  $default,) {final _that = this;
switch (_that) {
case _TreatmentPlan():
return $default(_that.id,_that.title,_that.steps);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String title,  List<TreatmentStep> steps)?  $default,) {final _that = this;
switch (_that) {
case _TreatmentPlan() when $default != null:
return $default(_that.id,_that.title,_that.steps);case _:
  return null;

}
}

}

/// @nodoc


class _TreatmentPlan extends TreatmentPlan {
  const _TreatmentPlan({required this.id, required this.title, required final  List<TreatmentStep> steps}): _steps = steps,super._();
  

@override final  int id;
@override final  String title;
 final  List<TreatmentStep> _steps;
@override List<TreatmentStep> get steps {
  if (_steps is EqualUnmodifiableListView) return _steps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_steps);
}


/// Create a copy of TreatmentPlan
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TreatmentPlanCopyWith<_TreatmentPlan> get copyWith => __$TreatmentPlanCopyWithImpl<_TreatmentPlan>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TreatmentPlan&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other._steps, _steps));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,const DeepCollectionEquality().hash(_steps));

@override
String toString() {
  return 'TreatmentPlan(id: $id, title: $title, steps: $steps)';
}


}

/// @nodoc
abstract mixin class _$TreatmentPlanCopyWith<$Res> implements $TreatmentPlanCopyWith<$Res> {
  factory _$TreatmentPlanCopyWith(_TreatmentPlan value, $Res Function(_TreatmentPlan) _then) = __$TreatmentPlanCopyWithImpl;
@override @useResult
$Res call({
 int id, String title, List<TreatmentStep> steps
});




}
/// @nodoc
class __$TreatmentPlanCopyWithImpl<$Res>
    implements _$TreatmentPlanCopyWith<$Res> {
  __$TreatmentPlanCopyWithImpl(this._self, this._then);

  final _TreatmentPlan _self;
  final $Res Function(_TreatmentPlan) _then;

/// Create a copy of TreatmentPlan
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? steps = null,}) {
  return _then(_TreatmentPlan(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,steps: null == steps ? _self._steps : steps // ignore: cast_nullable_to_non_nullable
as List<TreatmentStep>,
  ));
}


}

// dart format on
