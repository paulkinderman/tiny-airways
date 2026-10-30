import 'json.dart';

/// A job uses a passenger seat or a cargo slot.
enum JobType { passenger, cargo }

/// Plain jobs, and the special kinds with a twist (design doc, Extras).
enum JobKind { standard, vip, rush, bulk, fragile, sightseeing, partCrate }

/// One passenger or one cargo crate waiting on a board or riding a plane.
///
/// [payout] is fixed when the job appears and already includes the bonuses
/// known then (distance, kind, the origin airport's paths, cross-region,
/// weather). Bonuses earned on the way ([bonusPct] from transfers and
/// [loadBonusPct] from a charter or full hold) are added on delivery.
class Job {
  const Job({
    required this.id,
    required this.type,
    required this.originCityId,
    required this.destCityId,
    required this.payout,
    required this.createdAt,
    this.kind = JobKind.standard,
    this.slots = 1,
    this.deadline,
    this.dropAtCityId,
    this.connectingSince,
    this.bonusPct = 0,
    this.loadBonusPct = 0,
  });

  final String id;
  final JobType type;
  final JobKind kind;
  final String originCityId;
  final String destCityId;
  final int payout;
  final DateTime createdAt;

  /// Seats or slots it takes (bulk crates take 2).
  final int slots;

  /// Pays nothing if it lands after this (VIP jobs).
  final DateTime? deadline;

  /// Where the player asked for it to be dropped to connect, if not its
  /// destination.
  final String? dropAtCityId;

  /// Set while the job waits on a board for a connecting flight. Connecting
  /// jobs survive board rotations and paid refreshes.
  final DateTime? connectingSince;

  /// Percent added on delivery from airports it connected through.
  final double bonusPct;

  /// Percent added on delivery for flying in a charter or full hold.
  final double loadBonusPct;

  bool get isConnecting => connectingSince != null;

  /// The city where this job next leaves the plane.
  String get unloadCityId => dropAtCityId ?? destCityId;

  Job copyWith({
    int? payout,
    String? Function()? dropAtCityId,
    DateTime? Function()? connectingSince,
    double? bonusPct,
    double? loadBonusPct,
  }) => Job(
    id: id,
    type: type,
    kind: kind,
    originCityId: originCityId,
    destCityId: destCityId,
    payout: payout ?? this.payout,
    createdAt: createdAt,
    slots: slots,
    deadline: deadline,
    dropAtCityId: dropAtCityId != null ? dropAtCityId() : this.dropAtCityId,
    connectingSince: connectingSince != null
        ? connectingSince()
        : this.connectingSince,
    bonusPct: bonusPct ?? this.bonusPct,
    loadBonusPct: loadBonusPct ?? this.loadBonusPct,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'kind': kind.name,
    'originCityId': originCityId,
    'destCityId': destCityId,
    'payout': payout,
    'createdAt': encodeTime(createdAt),
    'slots': slots,
    'deadline': encodeTimeOrNull(deadline),
    'dropAtCityId': dropAtCityId,
    'connectingSince': encodeTimeOrNull(connectingSince),
    'bonusPct': bonusPct,
    'loadBonusPct': loadBonusPct,
  };

  factory Job.fromJson(Map<String, dynamic> json) => Job(
    id: json['id'] as String,
    type: JobType.values.byName(json['type'] as String),
    kind: JobKind.values.byName(json['kind'] as String),
    originCityId: json['originCityId'] as String,
    destCityId: json['destCityId'] as String,
    payout: json['payout'] as int,
    createdAt: decodeTime(json['createdAt']),
    slots: json['slots'] as int,
    deadline: decodeTimeOrNull(json['deadline']),
    dropAtCityId: json['dropAtCityId'] as String?,
    connectingSince: decodeTimeOrNull(json['connectingSince']),
    bonusPct: (json['bonusPct'] as num).toDouble(),
    loadBonusPct: (json['loadBonusPct'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      other is Job && jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => Object.hash(id, payout);

  @override
  String toString() => 'Job($id ${type.name} $originCityId->$destCityId)';
}
