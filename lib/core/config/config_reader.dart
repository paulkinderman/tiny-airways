/// Thrown when a config file is missing, is not valid JSON, or does not have
/// the shape the game expects. The message always names the file and the
/// field so a bad config is quick to fix.
class ConfigException implements Exception {
  ConfigException(this.message);

  final String message;

  @override
  String toString() => 'ConfigException: $message';
}

/// Typed, path-aware access to one JSON object from a config file.
///
/// ```dart
/// final reader = ConfigReader(json, 'economy');
/// final money = reader.integer('startingMoney');
/// final rate = reader.child('rates').number('passengerPerKm');
/// ```
///
/// Every getter throws a [ConfigException] naming `economy.rates.passengerPerKm`
/// (for example) when the field is missing or has the wrong type.
class ConfigReader {
  ConfigReader(this.json, this.path);

  final Map<String, dynamic> json;

  /// Dotted location of [json], starting with the file name.
  final String path;

  bool has(String key) => json.containsKey(key);

  T _get<T>(String key, String typeName) {
    if (!json.containsKey(key)) {
      throw ConfigException('$path.$key is missing');
    }
    final value = json[key];
    if (value is! T) {
      throw ConfigException(
        '$path.$key should be $typeName but is ${_describe(value)}',
      );
    }
    return value;
  }

  String string(String key) => _get<String>(key, 'a string');

  bool boolean(String key) => _get<bool>(key, 'true or false');

  int integer(String key) {
    final value = _get<num>(key, 'a whole number');
    if (value is! int && value != value.roundToDouble()) {
      throw ConfigException('$path.$key should be a whole number, not $value');
    }
    return value.toInt();
  }

  double number(String key) => _get<num>(key, 'a number').toDouble();

  ConfigReader child(String key) =>
      ConfigReader(_get<Map<String, dynamic>>(key, 'an object'), '$path.$key');

  /// A list whose items are all objects, each wrapped in its own reader.
  List<ConfigReader> children(String key) {
    final list = _get<List<dynamic>>(key, 'a list');
    return [
      for (var i = 0; i < list.length; i++)
        if (list[i] is Map<String, dynamic>)
          ConfigReader(list[i] as Map<String, dynamic>, '$path.$key[$i]')
        else
          throw ConfigException(
            '$path.$key[$i] should be an object but is ${_describe(list[i])}',
          ),
    ];
  }

  List<T> list<T>(String key) {
    final list = _get<List<dynamic>>(key, 'a list');
    for (var i = 0; i < list.length; i++) {
      if (list[i] is! T) {
        throw ConfigException(
          '$path.$key[$i] has the wrong type: ${_describe(list[i])}',
        );
      }
    }
    return list.cast<T>();
  }

  static String _describe(Object? value) => switch (value) {
    null => 'null',
    String() => 'a string ("$value")',
    num() => 'a number ($value)',
    bool() => 'a boolean ($value)',
    List() => 'a list',
    Map() => 'an object',
    _ => value.runtimeType.toString(),
  };
}
