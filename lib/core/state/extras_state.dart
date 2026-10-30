import 'json.dart';

/// A daily or weekly challenge on the player's board.
///
/// The target and rewards are fixed when it is rolled, so they don't move
/// while the player works on it.
class ActiveChallenge {
  const ActiveChallenge({
    required this.defId,
    required this.target,
    required this.xp,
    required this.money,
    this.progress = 0,
    this.bonus,
    this.claimed = false,
  });

  /// The challenge in `extras.challenges.daily` or `weekly`.
  final String defId;
  final int target;
  final int progress;
  final int xp;
  final int money;

  /// A weekly's extra: `partCrate` or `crewXp`.
  final String? bonus;

  /// Weeklies stay on the board, claimed, until the week ends.
  final bool claimed;

  bool get isDone => progress >= target;

  ActiveChallenge copyWith({int? progress, bool? claimed}) => ActiveChallenge(
    defId: defId,
    target: target,
    xp: xp,
    money: money,
    progress: progress ?? this.progress,
    bonus: bonus,
    claimed: claimed ?? this.claimed,
  );

  Map<String, dynamic> toJson() => {
    'defId': defId,
    'target': target,
    'progress': progress,
    'xp': xp,
    'money': money,
    'bonus': bonus,
    'claimed': claimed,
  };

  factory ActiveChallenge.fromJson(Map<String, dynamic> json) =>
      ActiveChallenge(
        defId: json['defId'] as String,
        target: json['target'] as int,
        progress: json['progress'] as int,
        xp: json['xp'] as int,
        money: json['money'] as int,
        bonus: json['bonus'] as String?,
        claimed: json['claimed'] as bool,
      );
}

/// A claimed challenge or milestone, for the Done list.
class ClaimRecord {
  const ClaimRecord({
    required this.text,
    required this.kind,
    required this.xp,
    required this.money,
    required this.at,
  });

  final String text;

  /// `daily`, `weekly` or `milestone`.
  final String kind;
  final int xp;
  final int money;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'text': text,
    'kind': kind,
    'xp': xp,
    'money': money,
    'at': encodeTime(at),
  };

  factory ClaimRecord.fromJson(Map<String, dynamic> json) => ClaimRecord(
    text: json['text'] as String,
    kind: json['kind'] as String,
    xp: json['xp'] as int,
    money: json['money'] as int,
    at: decodeTime(json['at']),
  );
}

/// Plane parts, special planes built, challenges and milestones (design doc,
/// Extras).
///
/// Saves from before package 10 have no `extras` key and load as
/// [ExtrasState.empty], so adding it needed no save migration.
class ExtrasState {
  const ExtrasState({
    this.parts = const {},
    this.builtPlanes = const [],
    this.counters = const {},
    this.dailies = const [],
    this.weekly,
    this.day = 0,
    this.week = 0,
    this.rerollsLeft = 0,
    this.claimedMilestones = const [],
    this.unlocks = const [],
    this.pendingCrewXp = 0,
    this.log = const [],
  });

  static const empty = ExtrasState();

  /// Parts held, by part id (`barnstormer.engine`). Parts are used up when
  /// their plane is built.
  final Map<String, int> parts;

  /// Special plane model ids built from parts. Each is built once.
  final List<String> builtPlanes;

  /// Lifetime totals of every counted metric, and the best value of each
  /// best-of metric, for milestones.
  final Map<String, int> counters;

  /// The daily challenges on the board (claimed ones are replaced at once).
  final List<ActiveChallenge> dailies;
  final ActiveChallenge? weekly;

  /// The local day and week the board was last rolled for (days since
  /// 1970-01-01; weeks start on Monday).
  final int day;
  final int week;

  /// Free daily rerolls left today.
  final int rerollsLeft;
  final List<String> claimedMilestones;

  /// Badges, liveries and veterans earned from milestones (see
  /// `MilestoneDef.unlock`).
  final List<String> unlocks;

  /// Crew XP for the whole roster, earned from weeklies, waiting for the
  /// crew system (package 7) to hand it out.
  final int pendingCrewXp;

  /// The latest claims, newest first.
  final List<ClaimRecord> log;

  int partCount(String partId) => parts[partId] ?? 0;
  int counter(String metric) => counters[metric] ?? 0;
  bool isBuilt(String modelId) => builtPlanes.contains(modelId);
  bool isClaimed(String milestoneId) => claimedMilestones.contains(milestoneId);

  ExtrasState copyWith({
    Map<String, int>? parts,
    List<String>? builtPlanes,
    Map<String, int>? counters,
    List<ActiveChallenge>? dailies,
    ActiveChallenge? Function()? weekly,
    int? day,
    int? week,
    int? rerollsLeft,
    List<String>? claimedMilestones,
    List<String>? unlocks,
    int? pendingCrewXp,
    List<ClaimRecord>? log,
  }) => ExtrasState(
    parts: parts ?? this.parts,
    builtPlanes: builtPlanes ?? this.builtPlanes,
    counters: counters ?? this.counters,
    dailies: dailies ?? this.dailies,
    weekly: weekly != null ? weekly() : this.weekly,
    day: day ?? this.day,
    week: week ?? this.week,
    rerollsLeft: rerollsLeft ?? this.rerollsLeft,
    claimedMilestones: claimedMilestones ?? this.claimedMilestones,
    unlocks: unlocks ?? this.unlocks,
    pendingCrewXp: pendingCrewXp ?? this.pendingCrewXp,
    log: log ?? this.log,
  );

  Map<String, dynamic> toJson() => {
    'parts': parts,
    'builtPlanes': builtPlanes,
    'counters': counters,
    'dailies': [for (final c in dailies) c.toJson()],
    'weekly': weekly?.toJson(),
    'day': day,
    'week': week,
    'rerollsLeft': rerollsLeft,
    'claimedMilestones': claimedMilestones,
    'unlocks': unlocks,
    'pendingCrewXp': pendingCrewXp,
    'log': [for (final r in log) r.toJson()],
  };

  factory ExtrasState.fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    Map<String, int> ints(Object? m) =>
        (m as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int));
    return ExtrasState(
      parts: ints(json['parts']),
      builtPlanes: (json['builtPlanes'] as List<dynamic>).cast<String>(),
      counters: ints(json['counters']),
      dailies: [
        for (final c in jsonList(json['dailies'])) ActiveChallenge.fromJson(c),
      ],
      weekly: json['weekly'] == null
          ? null
          : ActiveChallenge.fromJson(json['weekly'] as Map<String, dynamic>),
      day: json['day'] as int,
      week: json['week'] as int,
      rerollsLeft: json['rerollsLeft'] as int,
      claimedMilestones: (json['claimedMilestones'] as List<dynamic>)
          .cast<String>(),
      unlocks: (json['unlocks'] as List<dynamic>).cast<String>(),
      pendingCrewXp: json['pendingCrewXp'] as int,
      log: [for (final r in jsonList(json['log'])) ClaimRecord.fromJson(r)],
    );
  }
}
