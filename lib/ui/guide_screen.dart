import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../game/map/map_style.dart';
import 'guide_content.dart';
import 'theme.dart';
import 'widgets.dart';

/// The game guide: what things mean, what unlocks when, which planes can
/// land where, pilots, upgrades, jobs and weather. Everything in it is
/// written from the game data (see [buildGuide]), so it stays right when the
/// numbers are tuned. Open from the map's "?" button or the airline sheet.
class GuideScreen extends ConsumerStatefulWidget {
  const GuideScreen({required this.onClose, this.section, super.key});

  final VoidCallback onClose;

  /// The section to open on, by [GuideSection.id]; the first if null.
  final String? section;

  @override
  ConsumerState<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends ConsumerState<GuideScreen> {
  late List<GuideSection> _sections;
  var _tab = 0;
  var _query = '';
  final _search = TextEditingController();

  /// The chip of the section opened on, to scroll it into view.
  final _openChip = GlobalKey();

  @override
  void initState() {
    super.initState();
    _sections = buildGuide(ref.read(simulationProvider).rules);
    final i = _sections.indexWhere((s) => s.id == widget.section);
    if (i >= 0) _tab = i;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chip = _openChip.currentContext;
      if (chip != null && chip.mounted) Scrollable.ensureVisible(chip);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = ref.watch(gameSessionProvider.select((s) => s.player.level));
    final q = _query.trim().toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: 'Game guide',
          subtitle: 'Terms, unlocks and which planes go where',
          onBack: widget.onClose,
        ),
        Container(
          color: Board.panel,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('guide.search'),
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: Board.ink, fontSize: 15),
                cursorColor: Board.amber,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search the guide',
                  hintStyle: const TextStyle(color: Board.muted),
                  prefixIcon: const Icon(Icons.search, color: Board.muted),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('guide.clear'),
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close, color: Board.muted),
                          onPressed: () => setState(() {
                            _search.clear();
                            _query = '';
                          }),
                        ),
                  filled: true,
                  fillColor: Board.ground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: const BorderSide(color: Board.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: const BorderSide(color: Board.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: const BorderSide(color: Board.amber),
                  ),
                ),
              ),
              if (q.isEmpty) ...[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < _sections.length; i++) ...[
                        if (_sections[i].id == widget.section)
                          SizedBox(key: _openChip),
                        BoardChip(
                          key: Key('guide.tab.${_sections[i].id}'),
                          label: _sections[i].title,
                          selected: i == _tab,
                          onTap: () => setState(() => _tab = i),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView(
            key: const Key('guide.list'),
            padding: const EdgeInsets.all(12),
            children: q.isEmpty
                ? _section(_sections[_tab], level)
                : _results(q, level),
          ),
        ),
      ],
    );
  }

  List<Widget> _section(GuideSection s, int level) => [
    Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Text(
        s.intro,
        style: const TextStyle(fontSize: 14, color: Board.muted, height: 1.35),
      ),
    ),
    BoardSection(
      title: s.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in s.entries) _GuideRow(entry: e, playerLevel: level),
        ],
      ),
    ),
  ];

  List<Widget> _results(String q, int level) {
    bool match(GuideEntry e) =>
        e.title.toLowerCase().contains(q) ||
        e.text.toLowerCase().contains(q) ||
        (e.tag?.toLowerCase().contains(q) ?? false);
    final out = <Widget>[];
    for (final s in _sections) {
      final hits = s.entries.where(match).toList();
      if (hits.isEmpty) continue;
      out
        ..add(
          BoardSection(
            title: s.title,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in hits) _GuideRow(entry: e, playerLevel: level),
              ],
            ),
          ),
        )
        ..add(const SizedBox(height: 12));
    }
    if (out.isEmpty) {
      return [
        Padding(
          key: const Key('guide.noResults'),
          padding: const EdgeInsets.all(16),
          child: Text(
            'Nothing in the guide matches "${_query.trim()}".',
            style: const TextStyle(color: Board.muted),
          ),
        ),
      ];
    }
    return out;
  }
}

/// One guide entry: a title with an optional tag, and its text. A tag for
/// a level the airline has reached turns green.
class _GuideRow extends StatelessWidget {
  const _GuideRow({required this.entry, required this.playerLevel});

  final GuideEntry entry;
  final int playerLevel;

  @override
  Widget build(BuildContext context) {
    final reached = entry.level != null && playerLevel >= entry.level!;
    return Container(
      key: Key('guide.entry.${entry.title}'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Board.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  entry.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Board.ink,
                  ),
                ),
              ),
              if (entry.tag != null) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Board.flap,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: reached ? Board.good : Board.line,
                      ),
                    ),
                    child: Text(
                      entry.tag!.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Board.flapStyle(
                        size: 11,
                        color: reached ? Board.good : Board.amber,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            entry.text,
            style: const TextStyle(
              fontSize: 14,
              color: Board.muted,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// The "?" that opens the guide. It sits on the map under the zoom
/// buttons and matches them.
class GuideButton extends StatelessWidget {
  const GuideButton({required this.onTap, super.key});

  /// Where it goes below the top of the map: under the + and - buttons
  /// (each 44 points, 12 from the top and 10 apart).
  static const mapTop = 12.0 + 44 + 10 + 44 + 10;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Game guide',
    excludeSemantics: true,
    child: Material(
      color: MapStyle.amber,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: MapStyle.ink, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('map.guide'),
        onTap: onTap,
        child: const SizedBox.square(
          dimension: 44,
          child: Center(
            child: Text(
              '?',
              style: TextStyle(
                fontFamily: MapStyle.font,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: MapStyle.ink,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
