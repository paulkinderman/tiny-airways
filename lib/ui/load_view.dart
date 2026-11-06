import '../core/state/game_state.dart';
import '../logic/simulation.dart';
import 'rivals_screens.dart' show visibleBoard;

/// The loading sheet's filters: which city, seats or cargo only, and
/// whether to hide jobs too big for the room left.
class LoadFilter {
  const LoadFilter({
    this.cityId,
    this.seatsOnly = false,
    this.cargoOnly = false,
    this.fitsOnly = false,
  });

  /// Destination to show; null shows every city.
  final String? cityId;
  final bool seatsOnly;
  final bool cargoOnly;
  final bool fitsOnly;

  bool get isEmpty => cityId == null && !seatsOnly && !cargoOnly && !fitsOnly;

  LoadFilter copyWith({
    String? Function()? cityId,
    bool? seatsOnly,
    bool? cargoOnly,
    bool? fitsOnly,
  }) => LoadFilter(
    cityId: cityId == null ? this.cityId : cityId(),
    seatsOnly: seatsOnly ?? this.seatsOnly,
    cargoOnly: cargoOnly ?? this.cargoOnly,
    fitsOnly: fitsOnly ?? this.fitsOnly,
  );
}

/// How the city picker orders its cities.
enum CitySort { seats, pay, nearest, name }

/// What one destination's waiting jobs could do for the plane.
enum CityFill { none, seats, hold, all }

/// The jobs waiting for one destination.
class CityGroup {
  const CityGroup({
    required this.cityId,
    required this.jobs,
    required this.seats,
    required this.cargoSlots,
    required this.pay,
    required this.distanceKm,
    required this.fill,
  });

  final String cityId;

  /// Best-paying first, with jobs too big for the room left last.
  final List<Job> jobs;
  final int seats;
  final int cargoSlots;
  final int pay;
  final double distanceKm;

  /// Which of the plane's free seats and slots these jobs alone can fill
  /// exactly.
  final CityFill fill;
}

/// The board where a plane is parked, sorted out for hand-loading: jobs
/// grouped by city, which ones are too big for the room left, and which
/// the plane can never take.
class LoadView {
  const LoadView({
    required this.groups,
    required this.tooBig,
    required this.cantTake,
    required this.boardCount,
  });

  factory LoadView.of(
    Simulation sim,
    GameState state,
    Plane plane,
    DateTime now,
  ) {
    final airport = state.airport(plane.cityId)!;
    final board = visibleBoard(sim, state, airport, now)
      ..sort((a, b) => b.payout.compareTo(a.payout));
    final empty = plane.copyWith(load: const []);
    final tooBig = <String>{};
    final cantTake = <Job>[];
    final byCity = <String, List<Job>>{};
    for (final j in board) {
      final never = sim.loading.loadProblem(state, empty, j, now);
      if (never != null && never != RuleError.noRoom) {
        cantTake.add(j);
        continue;
      }
      if (sim.loading.loadProblem(state, plane, j, now) == RuleError.noRoom) {
        tooBig.add(j.id);
      }
      (byCity[j.destCityId] ??= []).add(j);
    }
    // Within a city, jobs that fit come first (best-paying first), then
    // the ones too big for the room left.
    for (final jobs in byCity.values) {
      final fit = [
        for (final j in jobs)
          if (!tooBig.contains(j.id)) j,
      ];
      final big = [
        for (final j in jobs)
          if (tooBig.contains(j.id)) j,
      ];
      jobs
        ..clear()
        ..addAll([...fit, ...big]);
    }
    final load = sim.loading.summary(state, plane, now);
    final crew = sim.rules.crew;
    int size(Job j) => crew.jobSlots(state, plane, j);
    final groups = [
      for (final MapEntry(key: cityId, value: jobs) in byCity.entries)
        () {
          final seatSizes = [
            for (final j in jobs)
              if (j.type == JobType.passenger) size(j),
          ];
          final cargoSizes = [
            for (final j in jobs)
              if (j.type == JobType.cargo) size(j),
          ];
          final freeSeats = load.freeSeats;
          final freeCargo = load.freeCargoSlots;
          final seatsFill =
              freeSeats > 0 && _reaches(seatSizes, freeSeats, freeSeats);
          final holdFill =
              freeCargo > 0 &&
              _reaches(
                cargoSizes,
                (freeCargo - load.holdSlack).clamp(1, freeCargo),
                freeCargo,
              );
          final fill = seatsFill && (holdFill || freeCargo <= 0)
              ? CityFill.all
              : holdFill && freeSeats <= 0
              ? CityFill.all
              : seatsFill
              ? CityFill.seats
              : holdFill
              ? CityFill.hold
              : CityFill.none;
          return CityGroup(
            cityId: cityId,
            jobs: jobs,
            seats: seatSizes.fold(0, (a, b) => a + b),
            cargoSlots: cargoSizes.fold(0, (a, b) => a + b),
            pay: jobs.fold(0, (sum, j) => sum + j.payout),
            distanceKm: sim.rules.distanceKm(plane.cityId, cityId),
            fill: fill,
          );
        }(),
    ];
    final lead = load.charterCityId ?? load.holdCityId;
    groups.sort((a, b) {
      if (a.cityId == lead) return -1;
      if (b.cityId == lead) return 1;
      final room = (b.seats + b.cargoSlots).compareTo(a.seats + a.cargoSlots);
      return room != 0 ? room : b.pay.compareTo(a.pay);
    });
    return LoadView(
      groups: groups,
      tooBig: tooBig,
      cantTake: cantTake,
      boardCount: board.length,
    );
  }

  /// Cities with jobs the plane can take, the city most of the load is
  /// going to first, then the most seats and slots waiting.
  final List<CityGroup> groups;

  /// Jobs that won't fit in the room left (tapping one offers a seat).
  final Set<String> tooBig;

  /// Jobs this plane can never take (another model, a missing loadmaster).
  final List<Job> cantTake;

  /// Every job on the board the player can see.
  final int boardCount;

  CityGroup? group(String cityId) =>
      groups.where((g) => g.cityId == cityId).firstOrNull;

  /// [groups] ordered for the city picker.
  List<CityGroup> sorted(CitySort sort, String Function(String) name) =>
      [...groups]..sort(
        (a, b) => switch (sort) {
          CitySort.seats => (b.seats + b.cargoSlots).compareTo(
            a.seats + a.cargoSlots,
          ),
          CitySort.pay => b.pay.compareTo(a.pay),
          CitySort.nearest => a.distanceKm.compareTo(b.distanceKm),
          CitySort.name => name(a.cityId).compareTo(name(b.cityId)),
        },
      );

  /// Whether some of [sizes] add up to between [min] and [max].
  static bool _reaches(List<int> sizes, int min, int max) {
    final can = List<bool>.filled(max + 1, false)..[0] = true;
    for (final s in sizes) {
      for (var c = max; c >= s; c--) {
        if (can[c - s]) can[c] = true;
      }
    }
    for (var c = min; c <= max; c++) {
      if (can[c]) return true;
    }
    return false;
  }
}
