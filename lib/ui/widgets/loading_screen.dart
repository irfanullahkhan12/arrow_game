import 'package:flutter/material.dart';

import '../../theme/game_theme.dart';
import 'neon_widgets.dart';

/// The loader shown while a board is being built — at app start and again
/// before every new level. It carries the app icon, a neon progress bar and a
/// rotating tip, so the wait tells the player something.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({
    super.key,
    required this.message,
    required this.tip,
    this.compact = false,
  });

  /// e.g. "Building level 12…"
  final String message;

  /// One line from [GameFacts].
  final String tip;

  /// Compact mode drops the big logo — used for the in-game overlay.
  final bool compact;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.compact) ...[
          _Logo(sweep: _sweep),
          const SizedBox(height: 22),
          Text(
            'ARROW ESCAPE',
            style: GameTheme.font(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 26),
        ],
        SizedBox(
          width: 210,
          child: _NeonBar(sweep: _sweep),
        ),
        const SizedBox(height: 14),
        Text(
          widget.message,
          textAlign: TextAlign.center,
          style: GameTheme.font(
            color: GameTheme.ink,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            widget.tip,
            textAlign: TextAlign.center,
            style: GameTheme.font(
              color: GameTheme.inkSoft,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );

    if (widget.compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
        decoration: BoxDecoration(
          color: GameTheme.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: GameTheme.lilac.withValues(alpha: 0.5),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: GameTheme.lilac.withValues(alpha: 0.30),
              blurRadius: 26,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: content,
      );
    }

    return NeonBackground(
      child: Center(child: Padding(padding: const EdgeInsets.all(24), child: content)),
    );
  }
}

/// The app icon in its own glowing frame.
class _Logo extends StatelessWidget {
  const _Logo({required this.sweep});

  final Animation<double> sweep;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: sweep,
      builder: (context, child) {
        final pulse = 0.5 + 0.5 * (1 - (sweep.value * 2 - 1).abs());
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            boxShadow: [
              BoxShadow(
                color: GameTheme.boardEdge.withValues(alpha: 0.30 + 0.30 * pulse),
                blurRadius: 34 + 14 * pulse,
                spreadRadius: 2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: Image.asset(
          'assets/images/app_icon.png',
          width: 148,
          height: 148,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

/// An indeterminate neon progress bar: a bright comet sweeping a dim track.
class _NeonBar extends StatelessWidget {
  const _NeonBar({required this.sweep});

  final Animation<double> sweep;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 8,
        child: AnimatedBuilder(
          animation: sweep,
          builder: (context, _) {
            return CustomPaint(
              painter: _NeonBarPainter(sweep.value),
              size: Size.infinite,
            );
          },
        ),
      ),
    );
  }
}

class _NeonBarPainter extends CustomPainter {
  _NeonBarPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas.drawRRect(
      track,
      Paint()..color = GameTheme.lilac.withValues(alpha: 0.20),
    );

    final width = size.width * 0.42;
    // Ease the comet so it slows at each end instead of teleporting.
    final travel = Curves.easeInOutCubic.transform(
      (t * 2 <= 1) ? t * 2 : 2 - t * 2,
    );
    final left = (size.width + width) * travel - width;

    canvas.save();
    canvas.clipRRect(track);
    canvas.drawRect(
      Rect.fromLTWH(left, 0, width, size.height),
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0x0033E0FF),
            Color(0xFF3ED7F0),
            Color(0xFFFF3D8B),
            Color(0x00FF3D8B),
          ],
          stops: [0, 0.35, 0.72, 1],
        ).createShader(Rect.fromLTWH(left, 0, width, size.height)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NeonBarPainter oldDelegate) =>
      oldDelegate.t != t;
}
