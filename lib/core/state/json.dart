import 'package:collection/collection.dart';

/// Small helpers shared by the save schema classes.

String encodeTime(DateTime time) => time.toUtc().toIso8601String();

String? encodeTimeOrNull(DateTime? time) =>
    time == null ? null : encodeTime(time);

DateTime decodeTime(Object? value) => DateTime.parse(value as String).toUtc();

DateTime? decodeTimeOrNull(Object? value) =>
    value == null ? null : decodeTime(value);

List<Map<String, dynamic>> jsonList(Object? value) =>
    (value as List<dynamic>).cast<Map<String, dynamic>>();

const _deep = DeepCollectionEquality();

/// Deep equality for `toJson()` maps, so state classes compare by value.
bool jsonEquals(Object? a, Object? b) => _deep.equals(a, b);
