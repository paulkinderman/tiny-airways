import 'json.dart';

/// How a crew member's last leg turned into XP, for the skill tree screen's
/// "Last flight" card.
class CrewFlightXp {
  const CrewFlightXp({
    required this.fromCityId,
    required this.toCityId,
    required this.distanceKm,
    required this.modelId,
    required this.planeFactor,
    required this.loadUsed,
    required this.loadCapacity,
    required this.loadFactor,
    required this.bonusPct,
    required this.xp,
  });

  final String fromCityId;
  final String toCityId;
  final double distanceKm;
  final String modelId;
  final double planeFactor;
  final int loadUsed;
  final int loadCapacity;
  final double loadFactor;

  /// Flight bonuses added together (cross-region, VIP or bulk, earlier
  /// stops, mentors, Codeshare), and Passport's doubling folded in.
  final double bonusPct;
  final int xp;

  Map<String, dynamic> toJson() => {
    'fromCityId': fromCityId,
    'toCityId': toCityId,
    'distanceKm': distanceKm,
    'modelId': modelId,
    'planeFactor': planeFactor,
    'loadUsed': loadUsed,
    'loadCapacity': loadCapacity,
    'loadFactor': loadFactor,
    'bonusPct': bonusPct,
    'xp': xp,
  };

  factory CrewFlightXp.fromJson(Map<String, dynamic> json) => CrewFlightXp(
    fromCityId: json['fromCityId'] as String,
    toCityId: json['toCityId'] as String,
    distanceKm: (json['distanceKm'] as num).toDouble(),
    modelId: json['modelId'] as String,
    planeFactor: (json['planeFactor'] as num).toDouble(),
    loadUsed: json['loadUsed'] as int,
    loadCapacity: json['loadCapacity'] as int,
    loadFactor: (json['loadFactor'] as num).toDouble(),
    bonusPct: (json['bonusPct'] as num).toDouble(),
    xp: json['xp'] as int,
  );
}

/// One person on staff: flight crew (assigned to a plane, earning XP and
/// skill points) or airport staff (assigned to an airport, upgraded with
/// money).
class CrewMember {
  const CrewMember({
    required this.id,
    required this.name,
    required this.roleId,
    required this.homeCityId,
    required this.hirePrice,
    this.signatureId,
    this.namedId,
    this.isVeteran = false,
    this.level = 1,
    this.xp = 0,
    this.nodes = const [],
    this.bonusNodes = const [],
    this.staffTiers = const {},
    this.planeId,
    this.cityId,
    this.lastFlight,
  });

  final String id;
  final String name;
  final String roleId;

  /// Their own fourth branch. Null for airport staff.
  final String? signatureId;

  /// The named crew entry they were hired from, if any.
  final String? namedId;
  final String homeCityId;
  final bool isVeteran;

  /// What they cost; respec costs a share of it.
  final int hirePrice;

  /// 1 to `crew.levels.maxLevel`.
  final int level;

  /// XP toward the next level.
  final int xp;

  /// Skill nodes learned with skill points, in the order learned.
  final List<String> nodes;

  /// Nodes given for free (Legacy). They cost no points and survive a
  /// respec.
  final List<String> bonusNodes;

  /// Airport staff: tiers bought in each staff path (0 to 3).
  final Map<String, int> staffTiers;

  /// The plane (flight crew) or airport city (staff) they work at; both
  /// null while unassigned.
  final String? planeId;
  final String? cityId;
  final CrewFlightXp? lastFlight;

  bool get isAssigned => planeId != null || cityId != null;
  int tier(String pathId) => staffTiers[pathId] ?? 0;

  /// Every node whose effect they have.
  Iterable<String> get allNodes => [...nodes, ...bonusNodes];

  CrewMember copyWith({
    int? level,
    int? xp,
    List<String>? nodes,
    List<String>? bonusNodes,
    Map<String, int>? staffTiers,
    String? Function()? planeId,
    String? Function()? cityId,
    CrewFlightXp? lastFlight,
  }) => CrewMember(
    id: id,
    name: name,
    roleId: roleId,
    signatureId: signatureId,
    namedId: namedId,
    homeCityId: homeCityId,
    isVeteran: isVeteran,
    hirePrice: hirePrice,
    level: level ?? this.level,
    xp: xp ?? this.xp,
    nodes: nodes ?? this.nodes,
    bonusNodes: bonusNodes ?? this.bonusNodes,
    staffTiers: staffTiers ?? this.staffTiers,
    planeId: planeId != null ? planeId() : this.planeId,
    cityId: cityId != null ? cityId() : this.cityId,
    lastFlight: lastFlight ?? this.lastFlight,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'roleId': roleId,
    'signatureId': signatureId,
    'namedId': namedId,
    'homeCityId': homeCityId,
    'isVeteran': isVeteran,
    'hirePrice': hirePrice,
    'level': level,
    'xp': xp,
    'nodes': nodes,
    'bonusNodes': bonusNodes,
    'staffTiers': staffTiers,
    'planeId': planeId,
    'cityId': cityId,
    'lastFlight': lastFlight?.toJson(),
  };

  factory CrewMember.fromJson(Map<String, dynamic> json) => CrewMember(
    id: json['id'] as String,
    name: json['name'] as String,
    roleId: json['roleId'] as String,
    signatureId: json['signatureId'] as String?,
    namedId: json['namedId'] as String?,
    homeCityId: json['homeCityId'] as String,
    isVeteran: json['isVeteran'] as bool,
    hirePrice: json['hirePrice'] as int,
    level: json['level'] as int,
    xp: json['xp'] as int,
    nodes: (json['nodes'] as List<dynamic>).cast<String>(),
    bonusNodes: (json['bonusNodes'] as List<dynamic>).cast<String>(),
    staffTiers: (json['staffTiers'] as Map<String, dynamic>)
        .cast<String, int>(),
    planeId: json['planeId'] as String?,
    cityId: json['cityId'] as String?,
    lastFlight: json['lastFlight'] == null
        ? null
        : CrewFlightXp.fromJson(json['lastFlight'] as Map<String, dynamic>),
  );

  @override
  bool operator ==(Object other) =>
      other is CrewMember && jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => Object.hash(id, level, xp);
}

/// A plane flying a saved route on its own (the pilot's Autopilot capstone).
class AutopilotRoute {
  const AutopilotRoute({required this.stops, this.next = 1});

  /// The loop, starting where it was set up: the plane flies stops[0] to
  /// stops[1] and so on, then back to stops[0].
  final List<String> stops;

  /// Index in [stops] of the next airport to fly to.
  final int next;

  AutopilotRoute advanced() =>
      AutopilotRoute(stops: stops, next: (next + 1) % stops.length);

  Map<String, dynamic> toJson() => {'stops': stops, 'next': next};

  factory AutopilotRoute.fromJson(Map<String, dynamic> json) => AutopilotRoute(
    stops: (json['stops'] as List<dynamic>).cast<String>(),
    next: json['next'] as int,
  );
}

/// The airline's crew: everyone on staff, the offers already taken, the
/// planes that have had their free pilot, and planes on autopilot.
///
/// The rookie and veteran shelves aren't saved: they are worked out from
/// the time and the airline's seed, so only the hires need remembering.
class CrewState {
  const CrewState({
    this.members = const [],
    this.hiredOffers = const [],
    this.staffedPlaneIds = const [],
    this.autopilot = const {},
  });

  final List<CrewMember> members;

  /// Ids of shelf offers already hired, so they show as taken.
  final List<String> hiredOffers;

  /// Planes that have been given their free rookie pilot.
  final List<String> staffedPlaneIds;

  /// Planes flying a saved route on their own, by plane id.
  final Map<String, AutopilotRoute> autopilot;

  CrewMember? member(String id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  List<CrewMember> onPlane(String planeId) => [
    for (final m in members)
      if (m.planeId == planeId) m,
  ];

  List<CrewMember> atAirport(String cityId) => [
    for (final m in members)
      if (m.cityId == cityId) m,
  ];

  CrewState copyWith({
    List<CrewMember>? members,
    List<String>? hiredOffers,
    List<String>? staffedPlaneIds,
    Map<String, AutopilotRoute>? autopilot,
  }) => CrewState(
    members: members ?? this.members,
    hiredOffers: hiredOffers ?? this.hiredOffers,
    staffedPlaneIds: staffedPlaneIds ?? this.staffedPlaneIds,
    autopilot: autopilot ?? this.autopilot,
  );

  /// Replaces member [id] with `change(member)`.
  CrewState updateMember(String id, CrewMember Function(CrewMember m) change) =>
      copyWith(members: [for (final m in members) m.id == id ? change(m) : m]);

  Map<String, dynamic> toJson() => {
    'members': [for (final m in members) m.toJson()],
    'hiredOffers': hiredOffers,
    'staffedPlaneIds': staffedPlaneIds,
    'autopilot': {for (final e in autopilot.entries) e.key: e.value.toJson()},
  };

  factory CrewState.fromJson(Map<String, dynamic> json) => CrewState(
    members: [
      for (final m in jsonList(json['members'])) CrewMember.fromJson(m),
    ],
    hiredOffers: (json['hiredOffers'] as List<dynamic>).cast<String>(),
    staffedPlaneIds: (json['staffedPlaneIds'] as List<dynamic>).cast<String>(),
    autopilot: {
      for (final e in (json['autopilot'] as Map<String, dynamic>).entries)
        e.key: AutopilotRoute.fromJson(e.value as Map<String, dynamic>),
    },
  );
}
