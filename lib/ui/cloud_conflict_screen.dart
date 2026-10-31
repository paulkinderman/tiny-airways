import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/save/cloud_sync.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// Shown when this device and iCloud each have an airline the other hasn't
/// seen: a side-by-side summary, and the player keeps one.
class CloudConflictScreen extends ConsumerStatefulWidget {
  const CloudConflictScreen({super.key});

  @override
  ConsumerState<CloudConflictScreen> createState() =>
      _CloudConflictScreenState();
}

class _CloudConflictScreenState extends ConsumerState<CloudConflictScreen> {
  var _busy = false;

  Future<void> _choose({required bool keepLocal}) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(cloudConflictProvider.notifier)
          .choose(keepLocal: keepLocal);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conflict = ref.watch(cloudConflictProvider);
    if (conflict == null) return const SizedBox.shrink();
    return Scaffold(
      backgroundColor: Board.ground,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('PICK YOUR AIRLINE', style: Board.flapStyle(size: 20)),
            const SizedBox(height: 8),
            const Text(
              'This device and iCloud have both been played since they last '
              'synced. Keep one airline; the other is replaced on every '
              'device.',
              style: TextStyle(color: Board.muted),
            ),
            const SizedBox(height: 16),
            _Comparison(
              local: conflict.local.summary,
              cloud: conflict.cloud.summary,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AmberButton(
                    key: const Key('conflict.keepLocal'),
                    label: 'Keep this device',
                    onPressed: _busy ? null : () => _choose(keepLocal: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AmberButton(
                    key: const Key('conflict.keepCloud'),
                    label: 'Keep iCloud',
                    onPressed: _busy ? null : () => _choose(keepLocal: false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The two airlines side by side: home, money, level, fleet, airports and
/// when each was last played.
class _Comparison extends ConsumerWidget {
  const _Comparison({required this.local, required this.cloud});

  final SaveSummary local;
  final SaveSummary cloud;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final world = ref.watch(gameConfigProvider).world;
    String home(SaveSummary s) =>
        s.homeCityId == null ? '—' : world.city(s.homeCityId!).name;
    String played(SaveSummary s) {
      final t = s.savedAt.toLocal();
      return '${t.month}/${t.day} ${formatClock(s.savedAt)}';
    }

    final rows = [
      ('Home', home(local), home(cloud)),
      ('Money', formatCoins(local.money), formatCoins(cloud.money)),
      ('Level', '${local.level}', '${cloud.level}'),
      ('Planes', '${local.planes}', '${cloud.planes}'),
      ('Airports', '${local.airports}', '${cloud.airports}'),
      ('Last played', played(local), played(cloud)),
    ];
    Widget cell(String text, {Color color = Board.ink, bool bold = true}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        );
    return BoardSection(
      title: 'Your airlines',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(1),
            1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(1.2),
          },
          children: [
            TableRow(
              children: [
                const SizedBox.shrink(),
                cell('This device', color: Board.amber),
                cell('iCloud', color: Board.amber),
              ],
            ),
            for (final (label, a, b) in rows)
              TableRow(
                children: [
                  cell(label, color: Board.muted, bold: false),
                  cell(a),
                  cell(b),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
