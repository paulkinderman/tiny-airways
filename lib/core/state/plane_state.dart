import 'job.dart';
import 'json.dart';

/// Parked at an airport (loading or waiting), in the air, or circling an
/// airport it can't land at yet (gates full or weather).
enum PlaneStatus { parked, flying, holding }

/// Levels bought on a plane's upgrade tracks (0 to 3 each).
class PlaneUpgrades {
  const PlaneUpgrades({
    this.capacity = 0,
    this.cargo = 0,
    this.speed = 0,
    this.range = 0,
  });

  /// Seats, or slots on a cargo-only plane.
  final int capacity;

  /// Hold slots on a plane that also has seats.
  final int cargo;
  final int speed;
  final int range;

  Map<String, dynamic> toJson() => {
    'capacity': capacity,
    'cargo': cargo,
    'speed': speed,
    'range': range,
  };

  /// Saves from before the cargo track have no `cargo` key.
  factory PlaneUpgrades.fromJson(Map<String, dynamic> json) => PlaneUpgrades(
    capacity: json['capacity'] as int,
    cargo: json['cargo'] as int? ?? 0,
    speed: json['speed'] as int,
    range: json['range'] as int,
  );
}

/// One leg of a trip, timed when it took off.
class FlightLeg {
  const FlightLeg({
    required this.fromCityId,
    required this.toCityId,
    required this.departAt,
    required this.arriveAt,
    required this.distanceKm,
    this.diverted = false,
  });

  final String fromCityId;
  final String toCityId;
  final DateTime departAt;
  final DateTime arriveAt;
  final double distanceKm;

  /// True for a leg flown because weather closed the planned airport.
  final bool diverted;

  /// The stand-in leg of a newly bought plane that is waiting over
  /// [cityId] for a free gate: it starts and ends there and covers no
  /// distance.
  factory FlightLeg.delivery(String cityId, DateTime t) => FlightLeg(
    fromCityId: cityId,
    toCityId: cityId,
    departAt: t,
    arriveAt: t,
    distanceKm: 0,
  );

  /// True for a [FlightLeg.delivery] leg.
  bool get isDelivery => fromCityId == toCityId && distanceKm == 0;

  Map<String, dynamic> toJson() => {
    'fromCityId': fromCityId,
    'toCityId': toCityId,
    'departAt': encodeTime(departAt),
    'arriveAt': encodeTime(arriveAt),
    'distanceKm': distanceKm,
    'diverted': diverted,
  };

  factory FlightLeg.fromJson(Map<String, dynamic> json) => FlightLeg(
    fromCityId: json['fromCityId'] as String,
    toCityId: json['toCityId'] as String,
    departAt: decodeTime(json['departAt']),
    arriveAt: decodeTime(json['arriveAt']),
    distanceKm: (json['distanceKm'] as num).toDouble(),
    diverted: json['diverted'] as bool,
  );
}

/// A plane the player owns.
class Plane {
  const Plane({
    required this.id,
    required this.modelId,
    required this.cityId,
    this.nickname,
    this.upgrades = const PlaneUpgrades(),
    this.status = PlaneStatus.parked,
    this.leg,
    this.remainingStops = const [],
    this.load = const [],
    this.holdingSince,
    this.tripStops = 0,
    this.pickUpAtStops = false,
    this.tripFuel = 0,
    this.tripEarned = 0,
  });

  final String id;
  final String modelId;

  /// Player-given name; the UI shows the model name when it's null.
  final String? nickname;
  final PlaneUpgrades upgrades;
  final PlaneStatus status;

  /// Where it is parked or holding, or where the current leg left from.
  final String cityId;

  /// The leg being flown (or the leg that ended in a holding pattern).
  final FlightLeg? leg;

  /// Stops still to fly after the current leg, in order.
  final List<String> remainingStops;

  /// Jobs aboard.
  final List<Job> load;
  final DateTime? holdingSince;

  /// Stops already made on the current trip (crew XP counts these).
  final int tripStops;

  /// Whether the plane picks up jobs bound for later stops when it lands
  /// mid-trip.
  final bool pickUpAtStops;

  /// Fuel paid for the trip being flown (charged at departure).
  final int tripFuel;

  /// Coins earned at the stops already made on the trip being flown.
  final int tripEarned;

  /// The city it's flying to or holding over.
  String? get targetCityId =>
      status == PlaneStatus.parked ? null : leg?.toCityId;

  Plane copyWith({
    String? Function()? nickname,
    PlaneUpgrades? upgrades,
    PlaneStatus? status,
    String? cityId,
    FlightLeg? Function()? leg,
    List<String>? remainingStops,
    List<Job>? load,
    DateTime? Function()? holdingSince,
    int? tripStops,
    bool? pickUpAtStops,
    int? tripFuel,
    int? tripEarned,
  }) => Plane(
    id: id,
    modelId: modelId,
    nickname: nickname != null ? nickname() : this.nickname,
    upgrades: upgrades ?? this.upgrades,
    status: status ?? this.status,
    cityId: cityId ?? this.cityId,
    leg: leg != null ? leg() : this.leg,
    remainingStops: remainingStops ?? this.remainingStops,
    load: load ?? this.load,
    holdingSince: holdingSince != null ? holdingSince() : this.holdingSince,
    tripStops: tripStops ?? this.tripStops,
    pickUpAtStops: pickUpAtStops ?? this.pickUpAtStops,
    tripFuel: tripFuel ?? this.tripFuel,
    tripEarned: tripEarned ?? this.tripEarned,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'modelId': modelId,
    'nickname': nickname,
    'upgrades': upgrades.toJson(),
    'status': status.name,
    'cityId': cityId,
    'leg': leg?.toJson(),
    'remainingStops': remainingStops,
    'load': [for (final j in load) j.toJson()],
    'holdingSince': encodeTimeOrNull(holdingSince),
    'tripStops': tripStops,
    'pickUpAtStops': pickUpAtStops,
    'tripFuel': tripFuel,
    'tripEarned': tripEarned,
  };

  factory Plane.fromJson(Map<String, dynamic> json) => Plane(
    id: json['id'] as String,
    modelId: json['modelId'] as String,
    nickname: json['nickname'] as String?,
    upgrades: PlaneUpgrades.fromJson(json['upgrades'] as Map<String, dynamic>),
    status: PlaneStatus.values.byName(json['status'] as String),
    cityId: json['cityId'] as String,
    leg: json['leg'] == null
        ? null
        : FlightLeg.fromJson(json['leg'] as Map<String, dynamic>),
    remainingStops: (json['remainingStops'] as List<dynamic>).cast<String>(),
    load: [for (final j in jsonList(json['load'])) Job.fromJson(j)],
    holdingSince: decodeTimeOrNull(json['holdingSince']),
    tripStops: json['tripStops'] as int,
    // Added with stop pickups; older saves read as off, which is how those
    // trips were flying. No save migration needed.
    pickUpAtStops: json['pickUpAtStops'] as bool? ?? false,
    // Added with in-flight profit; trips already in the air on an older
    // save read as nothing spent or earned yet.
    tripFuel: json['tripFuel'] as int? ?? 0,
    tripEarned: json['tripEarned'] as int? ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      other is Plane && jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => Object.hash(id, status, cityId);
}
