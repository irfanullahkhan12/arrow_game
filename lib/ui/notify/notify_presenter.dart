import 'package:flutter/material.dart';

import 'notify_style.dart';
import 'notify_widgets.dart';

/// Puts a notification on screen and takes it off again.
///
/// The widgets themselves know nothing about position or timing — that lives
/// here, so the same [NotifyToast] can be dropped into an overlay, a dialog,
/// or the gallery without changing a line of it.
///
/// Entrance specs (all from [NotifyStyle], so they can be retuned in one
/// place, and they translate directly into Rive/Lottie):
///
/// | Type   | Motion                              | Duration | Curve         |
/// | ---    | ---                                 | ---      | ---           |
/// | Toast  | slide up 28px + fade, slight overshoot | 420 ms | easeOutBack   |
/// | Banner | slide down 28px + fade, no bounce    | 420 ms   | easeOutCubic  |
/// | Pill   | scale 0.85 → 1 + fade                | 420 ms   | easeOutBack   |
/// | Exit   | fade + 12px travel back              | 220 ms   | easeInCubic   |
class Notify {
  const Notify._();

  /// Bottom-anchored toast. Auto-dismisses.
  static void toast(
    BuildContext context, {
    required String message,
    String? title,
    NotifyTone tone = NotifyTone.brand,
    NotifySkin skin = NotifySkin.solid,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? dwell,
  }) => _show(
    context,
    dwell: dwell ?? NotifyStyle.dwellNormal,
    from: _From.bottom,
    builder: (dismiss) => NotifyToast(
      message: message,
      title: title,
      tone: tone,
      skin: skin,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              dismiss();
              onAction();
            },
    ),
  );

  /// Top-anchored banner. Auto-dismisses unless [sticky].
  static void banner(
    BuildContext context, {
    required String title,
    String? message,
    NotifyTone tone = NotifyTone.info,
    NotifySkin skin = NotifySkin.solid,
    IconData? icon,
    bool sticky = false,
  }) => _show(
    context,
    dwell: sticky ? null : NotifyStyle.dwellLong,
    from: _From.top,
    builder: (dismiss) => NotifyBanner(
      title: title,
      message: message,
      tone: tone,
      skin: skin,
      icon: icon,
      onDismiss: dismiss,
    ),
  );

  /// The little capsule for "Saved" / "Copied". Centred, brief, no action.
  static void pill(
    BuildContext context, {
    required String label,
    NotifyTone tone = NotifyTone.success,
    NotifySkin skin = NotifySkin.solid,
    IconData? icon,
  }) => _show(
    context,
    dwell: NotifyStyle.dwellShort,
    from: _From.centre,
    builder: (_) =>
        NotifyPill(label: label, tone: tone, skin: skin, icon: icon),
  );

  /// The one that asks a question: stays until an action is taken.
  static void rich(
    BuildContext context, {
    required String title,
    required String body,
    required String primaryLabel,
    String? secondaryLabel,
    VoidCallback? onPrimary,
    VoidCallback? onSecondary,
    NotifyTone tone = NotifyTone.brand,
    NotifySkin skin = NotifySkin.gradient,
    IconData? icon,
    ImageProvider? thumbnail,
  }) => _show(
    context,
    dwell: null,
    from: _From.bottom,
    builder: (dismiss) => NotifyRich(
      title: title,
      body: body,
      primaryLabel: primaryLabel,
      secondaryLabel: secondaryLabel,
      tone: tone,
      skin: skin,
      icon: icon,
      thumbnail: thumbnail,
      onPrimary: () {
        dismiss();
        onPrimary?.call();
      },
      onSecondary: () {
        dismiss();
        onSecondary?.call();
      },
    ),
  );

  // ── Plumbing ─────────────────────────────────────────────────────────────

  static OverlayEntry? _current;

  static void _show(
    BuildContext context, {
    required Duration? dwell,
    required _From from,
    required Widget Function(VoidCallback dismiss) builder,
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    // One at a time: a stack of toasts is a stack nobody reads.
    _current?.remove();
    _current = null;

    late OverlayEntry entry;
    void dismiss() {
      if (_current == entry) {
        entry.remove();
        _current = null;
      }
    }

    entry = OverlayEntry(
      builder: (context) => _NotifyHost(
        from: from,
        dwell: dwell,
        onDone: dismiss,
        child: builder(dismiss),
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

enum _From { top, bottom, centre }

/// Positions a notification, animates it in, and takes it away again.
class _NotifyHost extends StatefulWidget {
  const _NotifyHost({
    required this.child,
    required this.from,
    required this.dwell,
    required this.onDone,
  });

  final Widget child;
  final _From from;
  final Duration? dwell;
  final VoidCallback onDone;

  @override
  State<_NotifyHost> createState() => _NotifyHostState();
}

class _NotifyHostState extends State<_NotifyHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: NotifyStyle.enterDuration,
    reverseDuration: NotifyStyle.exitDuration,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
    final dwell = widget.dwell;
    if (dwell != null) {
      Future<void>.delayed(dwell + NotifyStyle.enterDuration, () async {
        if (!mounted) return;
        await _controller.reverse();
        widget.onDone();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    final curve = widget.from == _From.top
        ? NotifyStyle.bannerCurve
        : NotifyStyle.enterCurve;
    final animation = CurvedAnimation(
      parent: _controller,
      curve: curve,
      reverseCurve: NotifyStyle.exitCurve,
    );

    final travel = switch (widget.from) {
      _From.top => -NotifyStyle.slideDistance,
      _From.bottom => NotifyStyle.slideDistance,
      _From.centre => 0.0,
    };

    return Positioned(
      top: widget.from == _From.top ? padding.top + 12 : null,
      bottom: widget.from == _From.bottom ? padding.bottom + 20 : null,
      left: 16,
      right: 16,
      child: widget.from == _From.centre
          ? Align(alignment: Alignment.center, child: _animate(animation, 0))
          : _animate(animation, travel),
    );
  }

  Widget _animate(Animation<double> animation, double travel) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        return Opacity(
          // The fade runs ahead of the slide, so nothing is ever half-drawn
          // in an odd place.
          opacity: _controller.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, travel * (1 - t)),
            child: widget.from == _From.centre
                ? Transform.scale(scale: 0.85 + 0.15 * t, child: child)
                : child,
          ),
        );
      },
      child: Material(color: Colors.transparent, child: widget.child),
    );
  }
}
