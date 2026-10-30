import 'job.dart';
import 'json.dart';

/// An airport the player owns.
class AirportState {
  const AirportState({
    required this.cityId,
    this.level = 1,
    this.pathTiers = const {},
    this.board = const [],
  });

  final String cityId;

  /// 1 to 5.
  final int level;

  /// Tiers bought in each upgrade path (`passenger`, `cargo`, `gateway`,
  /// `transfer`), 0 to 3. Missing paths are 0.
  final Map<String, int> pathTiers;

  /// The job board: fresh jobs plus jobs waiting here to connect.
  final List<Job> board;

  int tier(String pathId) => pathTiers[pathId] ?? 0;

  AirportState copyWith({
    int? level,
    Map<String, int>? pathTiers,
    List<Job>? board,
  }) => AirportState(
    cityId: cityId,
    level: level ?? this.level,
    pathTiers: pathTiers ?? this.pathTiers,
    board: board ?? this.board,
  );

  Map<String, dynamic> toJson() => {
    'cityId': cityId,
    'level': level,
    'pathTiers': pathTiers,
    'board': [for (final j in board) j.toJson()],
  };

  factory AirportState.fromJson(Map<String, dynamic> json) => AirportState(
    cityId: json['cityId'] as String,
    level: json['level'] as int,
    pathTiers: (json['pathTiers'] as Map<String, dynamic>).cast<String, int>(),
    board: [for (final j in jsonList(json['board'])) Job.fromJson(j)],
  );

  @override
  bool operator ==(Object other) =>
      other is AirportState && jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => Object.hash(cityId, level);
}
