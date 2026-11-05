import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'theme.dart';
import 'top_bar.dart';
import 'ui_state.dart';

/// What a message is about, shown by the colour of its edge and icon.
enum ToastKind {
  /// Something didn't work: red.
  error,

  /// Something worked: green.
  done,

  /// Anything else: amber.
  info,
}

/// One message in the top bar's toast tray.
class HudToast {
  HudToast({
    required this.message,
    this.kind = ToastKind.info,
    this.actionLabel,
    this.onAction,
    this.icon,
    this.duration = HudToast.short,
    this.key,
  }) : id = _next++;

  static int _next = 0;

  /// How long most messages stay up.
  static const short = Duration(seconds: 2);

  /// How long a message with something to do (a level-up) stays up.
  static const long = Duration(seconds: 5);

  final int id;
  final String message;
  final ToastKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Replaces the kind's own icon.
  final IconData? icon;
  final Duration duration;
  final Key? key;
}

/// The message showing in the top bar, if any. A new one replaces the old.
class ToastController extends Notifier<HudToast?> {
  @override
  HudToast? build() => null;

  void show(HudToast toast) => state = toast;

  /// Hides [id] if it is still the one showing.
  void dismiss(int id) {
    if (state?.id == id) state = null;
  }
}

final toastProvider = NotifierProvider<ToastController, HudToast?>(
  ToastController.new,
);

/// Shows [message] in the top bar's toast tray.
void showToast(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.info,
  String? actionLabel,
  VoidCallback? onAction,
  IconData? icon,
  Duration duration = HudToast.short,
  Key? key,
}) => ProviderScope.containerOf(context, listen: false)
    .read(toastProvider.notifier)
    .show(
      HudToast(
        message: message,
        kind: kind,
        actionLabel: actionLabel,
        onAction: onAction,
        icon: icon,
        duration: duration,
        key: key,
      ),
    );

/// The top bar's toast tray: the bar's dark panel stretches down and the
/// message slides out of it, then folds back up. It sits over the whole app
/// (sheets included), so messages always show in the same place.
class HudToastTray extends ConsumerStatefulWidget {
  const HudToastTray({super.key});

  /// How long the tray takes to unfold and fold back.
  static const slideTime = Duration(milliseconds: 240);

  @override
  ConsumerState<HudToastTray> createState() => _HudToastTrayState();
}

class _HudToastTrayState extends ConsumerState<HudToastTray>
    with TickerProviderStateMixin {
  late final _slide = AnimationController(
    vsync: this,
    duration: HudToastTray.slideTime,
  );
  late final _countdown = AnimationController(vsync: this);

  /// The message drawn, kept while the tray folds away after it is gone.
  HudToast? _shown;

  @override
  void initState() {
    super.initState();
    _countdown.addStatusListener((status) {
      if (status == AnimationStatus.completed) _dismiss();
    });
    final current = ref.read(toastProvider);
    if (current != null) _present(current);
  }

  @override
  void dispose() {
    _slide.dispose();
    _countdown.dispose();
    super.dispose();
  }

  void _present(HudToast toast) {
    setState(() => _shown = toast);
    _countdown
      ..duration = toast.duration
      ..forward(from: 0);
    _slide.forward();
  }

  void _dismiss() {
    final shown = _shown;
    if (shown != null) ref.read(toastProvider.notifier).dismiss(shown.id);
  }

  Future<void> _hide() async {
    _countdown.stop();
    await _slide.reverse();
    if (mounted && ref.read(toastProvider) == null) {
      setState(() => _shown = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(toastProvider, (_, next) {
      if (next == null) {
        _hide();
      } else {
        _present(next);
      }
    });
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();

    // Hangs from the top bar when it is on screen (or the route picker's
    // header, which is a little taller); before the game starts there is no
    // bar, so it drops from the top of the screen as a card.
    final hud =
        ref.watch(gameSessionProvider.select((s) => s.hasStarted)) &&
        ref.watch(cloudConflictProvider) == null;
    final routing = ref.watch(
      uiProvider.select(
        (ui) => ui.tab == HomeTab.map && ui.panel is RoutePanel,
      ),
    );
    final safeTop = MediaQuery.paddingOf(context).top;
    final top = hud ? safeTop + TopBar.height + (routing ? 8 : 0) : safeTop + 8;

    return Positioned(
      key: const Key('toast.tray'),
      top: top,
      left: hud ? 0 : 12,
      right: hud ? 0 : 12,
      child: SizeTransition(
        sizeFactor: CurvedAnimation(
          parent: _slide,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
        alignment: Alignment.bottomCenter,
        // A plain message lets taps through to whatever it covers (a
        // screen's back button, say); it is gone in a moment anyway. One
        // with a button takes taps, and a tap or swipe up dismisses it.
        child: IgnorePointer(
          ignoring: shown.actionLabel == null,
          child: GestureDetector(
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < 0) _dismiss();
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
              decoration: BoxDecoration(
                color: Board.ground,
                borderRadius: hud
                    ? const BorderRadius.vertical(bottom: Radius.circular(18))
                    : BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x59000000),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ToastCard(toast: shown, onTap: _dismiss),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: AnimatedBuilder(
                        animation: _countdown,
                        builder: (context, _) => LinearProgressIndicator(
                          value: 1 - _countdown.value,
                          minHeight: 3,
                          backgroundColor: Board.line,
                          color: _accent(shown.kind),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _accent(ToastKind kind) => switch (kind) {
  ToastKind.error => Board.bad,
  ToastKind.done => Board.good,
  ToastKind.info => Board.amber,
};

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.toast, required this.onTap});

  final HudToast toast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _accent(toast.kind);
    final action = toast.actionLabel;
    return Semantics(
      liveRegion: true,
      child: Material(
        key: toast.key,
        color: Board.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: accent, width: 4)),
            ),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    toast.icon ??
                        switch (toast.kind) {
                          ToastKind.error => Icons.priority_high_rounded,
                          ToastKind.done => Icons.check_rounded,
                          ToastKind.info => Icons.info_outline_rounded,
                        },
                    size: 15,
                    color: Board.amberInk,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    toast.message,
                    style: const TextStyle(
                      fontFamily: Board.sans,
                      fontSize: 14,
                      height: 1.3,
                      color: Board.ink,
                    ),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: 10),
                  Material(
                    color: Board.amber,
                    shape: const StadiumBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: const Key('toast.action'),
                      onTap: () {
                        toast.onAction?.call();
                        onTap();
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 36),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Center(
                            widthFactor: 1,
                            child: Text(
                              action,
                              style: const TextStyle(
                                fontFamily: Board.sans,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Board.amberInk,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
