import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'split_flap.dart';
import 'theme.dart';

/// Amber capitals on a dark flap, like a split-flap departures board. When
/// the text changes, the letters flip over to the new value.
class FlapText extends StatelessWidget {
  const FlapText(
    this.text, {
    this.size = 14,
    this.color = Board.amber,
    this.minWidth,
    super.key,
  });

  final String text;
  final double size;
  final Color color;
  final double? minWidth;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minWidth: minWidth ?? 0),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: Board.flap,
      borderRadius: BorderRadius.circular(4),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Board.raised, Board.raised, Board.flap, Board.flap],
        stops: [0, 0.5, 0.5, 1],
      ),
    ),
    child: SplitFlapText(
      text.toUpperCase(),
      style: Board.flapStyle(size: size, color: color),
    ),
  );
}

/// A rounded panel with an amber board heading over an amber rule.
class BoardSection extends StatelessWidget {
  const BoardSection({
    required this.title,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Board.flap,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Board.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Board.amber, width: 2)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: Board.flapStyle(size: 15),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        child,
      ],
    ),
  );
}

class AmberButton extends StatelessWidget {
  const AmberButton({
    required this.label,
    required this.onPressed,
    this.height = 44,
    this.mono = false,
    this.outlined = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;

  /// Board-style capitals, for small buttons in board rows.
  final bool mono;

  /// An amber outline instead of a fill (the loading sheet's Add).
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = outlined
        ? Board.amber
        : enabled
        ? Board.amberInk
        : Board.muted;
    return SizedBox(
      height: height,
      child: Material(
        color: outlined
            ? Colors.transparent
            : enabled
            ? Board.amber
            : Board.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: outlined
              ? const BorderSide(color: Board.amber, width: 1.5)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              widthFactor: 1,
              child: Text(
                mono ? label.toUpperCase() : label,
                maxLines: 1,
                style: mono
                    ? Board.flapStyle(size: 13, color: fg)
                    : TextStyle(
                        fontSize: height >= 52 ? 18 : 15,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small label over a big number ("Gates / 2 / 3").
class StatTile extends StatelessWidget {
  const StatTile({
    required this.label,
    required this.value,
    this.valueColor = Board.ink,
    super.key,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Board.panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Board.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Board.muted)),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    ),
  );
}

/// The header of a full sheet: back arrow, amber title, grey subtitle.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(4, 8, 16, 10),
    decoration: const BoxDecoration(
      color: Board.panel,
      border: Border(bottom: BorderSide(color: Board.line)),
    ),
    child: Row(
      children: [
        if (onBack != null)
          IconButton(
            key: const Key('sheet.back'),
            tooltip: 'Back',
            onPressed: onBack,
            icon: const Icon(Icons.chevron_left, color: Board.ink, size: 28),
          )
        else
          const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Board.flapStyle(size: 20),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Board.muted),
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Rebuilds once a second with the game clock's time, for countdowns.
class TickBuilder extends ConsumerStatefulWidget {
  const TickBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  ConsumerState<TickBuilder> createState() => _TickBuilderState();
}

class _TickBuilderState extends ConsumerState<TickBuilder> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, ref.read(clockProvider).now());
}

/// A rounded chip used for filters and city choices.
class BoardChip extends StatelessWidget {
  const BoardChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dashed = false,
    this.icon,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool dashed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? Board.amber : Board.panel,
    shape: StadiumBorder(
      side: BorderSide(
        color: dashed ? Board.amber : (selected ? Board.amber : Board.line),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected ? Board.amberInk : Board.amber,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Board.amberInk
                    : (dashed ? Board.amber : Board.ink),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
}
