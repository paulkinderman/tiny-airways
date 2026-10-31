import 'json.dart';

/// One weather event, from forecast to clear.
///
/// Airport events ([cityId]) hit one airport; cluster events hit every city
/// within the cluster radius of [cityId]; a jet stream is a band of latitude
/// around [bandLat] blowing east or west.
class WeatherEvent {
  const WeatherEvent({
    required this.id,
    required this.typeId,
    required this.regionId,
    required this.forecastAt,
    required this.startsAt,
    required this.endsAt,
    this.cityId,
    this.bandLat,
    this.eastbound,
  });

  final String id;

  /// A `weather.events[].id`, such as `thunderstorm`.
  final String typeId;
  final String regionId;
  final DateTime forecastAt;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? cityId;
  final double? bandLat;
  final bool? eastbound;

  bool activeAt(DateTime t) => !t.isBefore(startsAt) && t.isBefore(endsAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'typeId': typeId,
    'regionId': regionId,
    'forecastAt': encodeTime(forecastAt),
    'startsAt': encodeTime(startsAt),
    'endsAt': encodeTime(endsAt),
    'cityId': cityId,
    'bandLat': bandLat,
    'eastbound': eastbound,
  };

  factory WeatherEvent.fromJson(Map<String, dynamic> json) => WeatherEvent(
    id: json['id'] as String,
    typeId: json['typeId'] as String,
    regionId: json['regionId'] as String,
    forecastAt: decodeTime(json['forecastAt']),
    startsAt: decodeTime(json['startsAt']),
    endsAt: decodeTime(json['endsAt']),
    cityId: json['cityId'] as String?,
    bandLat: (json['bandLat'] as num?)?.toDouble(),
    eastbound: json['eastbound'] as bool?,
  );
}

/// Forecast and active events, and when each region's next event starts.
class WeatherState {
  const WeatherState({this.events = const [], this.nextEventAt = const {}});

  final List<WeatherEvent> events;

  /// Start time of each region's next event, by region id. It is rolled (and
  /// shows as a forecast) `weather.forecastMinutes` before this.
  final Map<String, DateTime> nextEventAt;

  WeatherState copyWith({
    List<WeatherEvent>? events,
    Map<String, DateTime>? nextEventAt,
  }) => WeatherState(
    events: events ?? this.events,
    nextEventAt: nextEventAt ?? this.nextEventAt,
  );

  Map<String, dynamic> toJson() => {
    'events': [for (final e in events) e.toJson()],
    'nextEventAt': {
      for (final e in nextEventAt.entries) e.key: encodeTime(e.value),
    },
  };

  factory WeatherState.fromJson(Map<String, dynamic> json) => WeatherState(
    events: [
      for (final e in jsonList(json['events'])) WeatherEvent.fromJson(e),
    ],
    nextEventAt: {
      for (final e in (json['nextEventAt'] as Map<String, dynamic>).entries)
        e.key: decodeTime(e.value),
    },
  );
}

/// Network stats for the stats screen.
class StatsState {
  const StatsState({
    this.moneyEarned = 0,
    this.fuelSpent = 0,
    this.jobsDelivered = 0,
    this.jobsLate = 0,
    this.kmFlown = 0,
    this.legsFlown = 0,
    this.routeLegs = const {},
  });

  final int moneyEarned;
  final int fuelSpent;
  final int jobsDelivered;

  /// Jobs that landed after their deadline and paid nothing.
  final int jobsLate;
  final double kmFlown;
  final int legsFlown;

  /// Legs flown per route, keyed `cityA|cityB` with the ids sorted, for the
  /// busiest route.
  final Map<String, int> routeLegs;

  /// The most-flown route as its two city ids, or null before any flight.
  (String, String)? get busiestRoute {
    if (routeLegs.isEmpty) return null;
    final top = routeLegs.entries.reduce((a, b) => b.value > a.value ? b : a);
    final ids = top.key.split('|');
    return (ids[0], ids[1]);
  }

  static String routeKey(String a, String b) =>
      a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

  StatsState copyWith({
    int? moneyEarned,
    int? fuelSpent,
    int? jobsDelivered,
    int? jobsLate,
    double? kmFlown,
    int? legsFlown,
    Map<String, int>? routeLegs,
  }) => StatsState(
    moneyEarned: moneyEarned ?? this.moneyEarned,
    fuelSpent: fuelSpent ?? this.fuelSpent,
    jobsDelivered: jobsDelivered ?? this.jobsDelivered,
    jobsLate: jobsLate ?? this.jobsLate,
    kmFlown: kmFlown ?? this.kmFlown,
    legsFlown: legsFlown ?? this.legsFlown,
    routeLegs: routeLegs ?? this.routeLegs,
  );

  Map<String, dynamic> toJson() => {
    'moneyEarned': moneyEarned,
    'fuelSpent': fuelSpent,
    'jobsDelivered': jobsDelivered,
    'jobsLate': jobsLate,
    'kmFlown': kmFlown,
    'legsFlown': legsFlown,
    'routeLegs': routeLegs,
  };

  factory StatsState.fromJson(Map<String, dynamic> json) => StatsState(
    moneyEarned: json['moneyEarned'] as int,
    fuelSpent: json['fuelSpent'] as int,
    jobsDelivered: json['jobsDelivered'] as int,
    jobsLate: json['jobsLate'] as int,
    kmFlown: (json['kmFlown'] as num).toDouble(),
    legsFlown: json['legsFlown'] as int,
    routeLegs: (json['routeLegs'] as Map<String, dynamic>).cast<String, int>(),
  );
}
