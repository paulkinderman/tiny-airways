import 'package:flutter/material.dart';

import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import 'format.dart';
import 'theme.dart';

/// Short labels for skill node effects, for the tree's small tiles.
const _shortEffect = {
  'speedPct': 'speed',
  'rangePct': 'range',
  'fuelPct': 'fuel',
  'passengerPayPct': 'pax',
  'cargoPayPct': 'cargo',
  'flightTimePct': 'time',
  'inRegionPayPct': 'local',
  'longFlightPassengerPayPct': 'long pax',
  'longFlightPayPct': 'long',
  'vipChancePct': 'VIP',
  'fullHoldBonusPct': 'hold',
  'fragilePayPct': 'fragile',
  'homeLegPayPct': 'home',
  'crossRegionPayPct': 'abroad',
  'mentorXpPct': 'XP',
  'doublePayChancePct': 'lucky',
  'jobPayPct': 'jobs',
  'transferPayPct': 'transfers',
  'cargoSlots': 'slot',
};

String _signed(double v) {
  final n = v == v.roundToDouble() ? v.round().toString() : v.toString();
  return v < 0 ? '−${n.substring(1)}' : '+$n';
}

/// "+5% range", or a capstone's name.
String nodeLabel(SkillNode node) {
  if (node.name != null) return node.name!;
  final label = _shortEffect[node.effect];
  if (label == null) return node.text;
  final pct = node.effect.endsWith('Pct') ? '%' : '';
  return '${_signed(node.value)}$pct $label';
}

/// Column headings for the skill tree, short enough for four columns.
const _branchLabel = {
  'fuel_saver': 'Fuel',
  'showmanship': 'Show',
  'long_haul': 'Long',
  'shortcuts': 'Short',
  'region_expert': 'Region',
  'vip_service': 'VIP',
  'fragile_goods': 'Fragile',
  'bulk_freight': 'Bulk',
  'night_owl': 'Owl',
  'globetrotter': 'Globe',
};

String branchLabel(SkillBranch branch) =>
    _branchLabel[branch.id] ?? branch.name.split(' ').first;

/// "cargo +10%": a role's base bonus, short.
String baseBonusShort(CrewRole role) {
  final label = _shortEffect[role.base.effect] ?? role.base.effect;
  return '$label ${_signed(role.base.value)}%';
}

/// "Rookie loadmaster · cargo +10%" or "Pilot · Lv 8".
String memberSubtitle(GameConfig config, CrewMember m) {
  final role = config.crew.role(m.roleId);
  final flight = role.isFlightCrew;
  if (!m.isVeteran && m.level == 1 && (!flight || m.nodes.isEmpty)) {
    return 'Rookie ${role.name.toLowerCase()} · ${baseBonusShort(role)}';
  }
  return flight
      ? '${role.name} · Lv ${m.level}'
      : '${role.name} · ${baseBonusShort(role)}';
}

/// Where [m] works: "flies Big Bird", "at Chicago" or "unassigned".
String memberPlace(GameConfig config, GameState state, CrewMember m) {
  if (m.planeId != null) {
    final plane = state.plane(m.planeId!);
    if (plane != null) return 'flies ${planeName(config, plane)}';
  }
  if (m.cityId != null) return 'at ${config.world.city(m.cityId!).name}';
  return 'unassigned';
}

/// What a signature grows into, in the member's own words: "+5% pay on legs
/// touching Atlanta, then Local hero".
String signatureBlurb(GameConfig config, CrewMember m) {
  if (m.signatureId == null) return '';
  final sig = config.crew.signature(m.signatureId!);
  final home = config.world.city(m.homeCityId).name;
  final first = sig.nodes.first.text.replaceAll('their home city', home);
  return '$first, then ${sig.capstone.name}';
}

/// "Range capstone · Night owl 3/4": how far a veteran has grown (for
/// staff, their bought tiers: "Connections 3/3").
String growthSummary(GameConfig config, CrewMember m) {
  final parts = <String>[];
  for (final p in config.crew.staffPaths[m.roleId] ?? const <StaffPath>[]) {
    if (m.tier(p.id) > 0) {
      parts.add('${p.name} ${m.tier(p.id)}/${p.tiers.length}');
    }
  }
  for (final b in config.crew.branchesFor(m.roleId, m.signatureId)) {
    final n = b.nodes.where((x) => m.allNodes.contains(x.id)).length;
    if (n == 0) continue;
    parts.add(
      n == b.nodes.length
          ? '${b.name} capstone'
          : '${b.name} $n/${b.nodes.length}',
    );
  }
  return parts.join(' · ');
}

String initials(String name) {
  final words = name.split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final first = words.first[0];
  final last = words.length > 1 ? words.last[0] : '';
  return (first + last).toUpperCase();
}

/// A round portrait placeholder with the member's initials (package 8
/// brings portraits).
class CrewAvatar extends StatelessWidget {
  const CrewAvatar({
    required this.name,
    this.size = 44,
    this.veteran = false,
    super.key,
  });

  final String name;
  final double size;
  final bool veteran;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: veteran ? const Color(0xFF3A2E10) : Board.raised,
    ),
    child: Text(initials(name), style: Board.flapStyle(size: size * 0.34)),
  );
}

/// A small purple chip naming a signature.
class SignatureChip extends StatelessWidget {
  const SignatureChip(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Board.signatureChip,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      name.toUpperCase(),
      style: Board.flapStyle(size: 10, color: Board.signature),
    ),
  );
}
