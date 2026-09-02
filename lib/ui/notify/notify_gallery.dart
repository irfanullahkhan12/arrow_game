import 'package:flutter/material.dart';

import 'notify_presenter.dart';
import 'notify_style.dart';
import 'notify_widgets.dart';

/// A canvas of every notification variant, grouped by type, so they can be
/// compared side by side and the winner picked.
///
/// The light/dark switch at the top flips the whole page, and the skin chips
/// swap solid / gradient / glass across every card at once — the point is to
/// see one decision applied everywhere, not to hunt through a list.
class NotifyGallery extends StatefulWidget {
  const NotifyGallery({super.key});

  @override
  State<NotifyGallery> createState() => _NotifyGalleryState();
}

class _NotifyGalleryState extends State<NotifyGallery> {
  Brightness _brightness = Brightness.dark;
  NotifySkin _skin = NotifySkin.solid;
  bool _compact = false;

  static const _tones = NotifyTone.values;

  @override
  Widget build(BuildContext context) {
    final dark = _brightness == Brightness.dark;
    final theme = ThemeData(
      brightness: _brightness,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF0E0B12)
          : const Color(0xFFF6F4F8),
      fontFamily: 'Roboto',
    );

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          foregroundColor: dark ? Colors.white : Colors.black,
          title: const Text(
            'Notification kit',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          actions: [
            IconButton(
              tooltip: dark ? 'Light mode' : 'Dark mode',
              onPressed: () => setState(
                () => _brightness = dark ? Brightness.light : Brightness.dark,
              ),
              icon: Icon(
                dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            _controls(dark),

            _section('Toast', 'Bottom-anchored. Auto-dismiss.'),
            for (final tone in _tones)
              _slot(
                NotifyToast(
                  tone: tone,
                  skin: _skin,
                  compact: _compact,
                  title: _compact ? null : _titleFor(tone),
                  message: _messageFor(tone),
                  actionLabel: tone == NotifyTone.error ? 'RETRY' : null,
                ),
              ),

            _section('Top banner', 'Slides in from the top. Alerts, status.'),
            for (final tone in _tones)
              _slot(
                NotifyBanner(
                  tone: tone,
                  skin: _skin,
                  compact: _compact,
                  title: _titleFor(tone),
                  message: _messageFor(tone),
                  onDismiss: () {},
                ),
              ),

            _section('Inbox card', 'A row in the notification feed.'),
            for (var i = 0; i < _tones.length; i++)
              _slot(
                NotifyCard(
                  tone: _tones[i],
                  skin: _skin,
                  compact: _compact,
                  unread: i.isEven,
                  title: _titleFor(_tones[i]),
                  body: _messageFor(_tones[i]),
                  timestamp: ['now', '2m', '1h', 'Tue', '12 Aug'][i],
                ),
              ),

            _section('Floating pill', 'Quick confirmations. No action.'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final tone in _tones)
                  NotifyPill(
                    tone: tone,
                    skin: _skin,
                    label: _pillFor(tone),
                    icon: NotifyStyle.iconFor(tone),
                  ),
              ],
            ),
            const SizedBox(height: 18),

            _section('Rich card', 'Thumbnail, two actions, asks a question.'),
            for (final tone in [
              NotifyTone.brand,
              NotifyTone.success,
              NotifyTone.warning,
            ])
              _slot(
                NotifyRich(
                  tone: tone,
                  skin: _skin,
                  compact: _compact,
                  title: _richTitleFor(tone),
                  body: _richBodyFor(tone),
                  primaryLabel: 'OPEN',
                  secondaryLabel: 'LATER',
                  thumbnail: tone == NotifyTone.brand
                      ? const AssetImage('assets/images/app_icon.png')
                      : null,
                ),
              ),

            _section('Live', 'Tap to see the entrance animation.'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _demo('Toast', () {
                  Notify.toast(
                    context,
                    tone: NotifyTone.success,
                    skin: _skin,
                    title: 'Level cleared',
                    message: 'You earned 120 coins.',
                    actionLabel: 'NEXT',
                  );
                }),
                _demo('Banner', () {
                  Notify.banner(
                    context,
                    tone: NotifyTone.warning,
                    skin: _skin,
                    title: 'Only one life left',
                    message: 'Watch a video to get three more.',
                  );
                }),
                _demo('Pill', () {
                  Notify.pill(context, label: 'Saved', skin: _skin);
                }),
                _demo('Rich', () {
                  Notify.rich(
                    context,
                    tone: NotifyTone.brand,
                    skin: _skin,
                    title: 'Your daily gift is ready',
                    body: 'Day 4 pays 120 coins and a rainbow arrow.',
                    primaryLabel: 'COLLECT',
                    secondaryLabel: 'LATER',
                    thumbnail: const AssetImage('assets/images/app_icon.png'),
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Chrome ───────────────────────────────────────────────────────────────

  Widget _controls(bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final skin in NotifySkin.values)
              ChoiceChip(
                label: Text(skin.name),
                selected: _skin == skin,
                onSelected: (_) => setState(() => _skin = skin),
              ),
            FilterChip(
              label: const Text('compact'),
              selected: _compact,
              onSelected: (v) => setState(() => _compact = v),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Glass needs something behind it — try it over the board.',
          style: TextStyle(
            fontSize: 11,
            color: dark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    );
  }

  Widget _section(String title, String subtitle) {
    final dark = _brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 26, 2, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: dark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11.5,
              color: dark ? Colors.white38 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _slot(Widget child) =>
      Padding(padding: const EdgeInsets.only(bottom: 12), child: child);

  Widget _demo(String label, VoidCallback onTap) => FilledButton.tonal(
    onPressed: onTap,
    child: Text(label),
  );

  // ── Sample copy ──────────────────────────────────────────────────────────

  static String _titleFor(NotifyTone tone) => switch (tone) {
    NotifyTone.brand => 'Rainbow arrow unlocked',
    NotifyTone.success => 'Level cleared',
    NotifyTone.error => 'Purchase failed',
    NotifyTone.warning => 'One life left',
    NotifyTone.info => 'New shapes ahead',
  };

  static String _messageFor(NotifyTone tone) => switch (tone) {
    NotifyTone.brand => 'It laps the whole board edge on its way out.',
    NotifyTone.success => 'You earned 120 coins and kept four lives.',
    NotifyTone.error => 'Nothing was charged. Check your connection.',
    NotifyTone.warning => 'Watch a short video to get three more.',
    NotifyTone.info => 'Level 24 is carved into a gear.',
  };

  static String _pillFor(NotifyTone tone) => switch (tone) {
    NotifyTone.brand => 'Armed',
    NotifyTone.success => 'Saved',
    NotifyTone.error => 'Failed',
    NotifyTone.warning => 'Careful',
    NotifyTone.info => 'Copied',
  };

  static String _richTitleFor(NotifyTone tone) => switch (tone) {
    NotifyTone.success => 'Day 4 streak!',
    NotifyTone.warning => 'Out of lives',
    _ => 'Your daily gift is ready',
  };

  static String _richBodyFor(NotifyTone tone) => switch (tone) {
    NotifyTone.success => 'Come back tomorrow and day 5 pays even more.',
    NotifyTone.warning => 'Watch a video to keep this board, or start again.',
    _ => 'It pays 120 coins and a rainbow arrow this time.',
  };
}
