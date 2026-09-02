import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../theme/game_theme.dart';

/// The daily "come back and play" reminder.
///
/// One notification a day, in the evening, carrying the level the player is
/// actually on and a different line of copy each day — a reminder that says
/// the same thing every night is a reminder people swipe away without reading.
///
/// It is scheduled a week at a time and refreshed whenever the app opens, so
/// the level in it is never stale, and nothing has to run in the background.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _channelId = 'daily_play';
  static const _channelName = 'Daily reminder';
  static const _channelDescription =
      'One friendly nudge a day to come back and clear a board.';

  /// Local hour the reminder fires. Early evening: after school, before bed.
  static const _hour = 19;
  static const _minute = 30;

  /// How many days ahead are scheduled at once. Refreshed on every app open,
  /// so a player who opens the game weekly never runs out.
  static const _daysAhead = 7;

  /// Posts the reminder immediately on launch, so it can actually be looked
  /// at without waiting for the evening:
  ///
  /// ```
  /// flutter run --dart-define=NOTIFY_TEST=true
  /// ```
  ///
  /// A normal build never sets it.
  static const _testNow = bool.fromEnvironment('NOTIFY_TEST');

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> initialize() async {
    if (_ready || !supported) return;
    try {
      tz_data.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(
          // A white silhouette, as Android requires; the colour comes from
          // [AndroidNotificationDetails.color] and the app icon rides along
          // as the large icon.
          android: AndroidInitializationSettings('@drawable/ic_notification'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      _ready = true;
    } catch (_) {
      _ready = false; // a reminder is never worth crashing over
    }
  }

  /// Asks for permission on Android 13+ / iOS. Safe to call every launch —
  /// the system only shows the prompt once.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return await android?.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(alert: true, badge: true) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Lines the reminder rotates through. Each one names the level, so it
  /// reads as *this player's* game rather than a generic advert.
  static final List<(String, String)> _copy = [
    ('🏹 Level {L} is waiting!', 'Your arrows have not moved all day. Free them?'),
    ('🌈 One board. Two minutes.', 'Level {L} — a rainbow arrow would clear it fast.'),
    ('⚡ Your streak is on the line', 'Play level {L} today and keep the daily gift growing.'),
    ('🖤 A black arrow is calling', 'Level {L} has arrows that will not budge. Blow through them.'),
    ('🎁 Your daily gift is ready', 'Collect it and take another run at level {L}.'),
    ('💣 Boom?', 'Level {L} is jammed solid. A bomb arrow would love that.'),
    ('👻 Sneak through the gaps', 'The ghost arrow zigzags where nothing else fits — level {L}.'),
    ('⭐ So close!', 'Clear level {L} and the next shape is a brand new one.'),
    ('🔥 Do not lose the run', 'Level {L} is one good move away from falling apart.'),
    ('✨ Two minutes of neon', 'Level {L}. Tap. Fly. Done.'),
  ];

  /// Posts the reminder right now — the same notification the evening one
  /// shows, so what you see here is what a player sees.
  Future<void> showNow({required int level}) async {
    if (!_ready) return;
    try {
      final (title, body) = _copy[math.Random().nextInt(_copy.length)];
      await _plugin.show(
        id: 99,
        title: title.replaceAll('{L}', '$level'),
        body: body.replaceAll('{L}', '$level'),
        notificationDetails: _details(level),
      );
    } catch (_) {
      // Nothing to do.
    }
  }

  /// Rebuilds the whole schedule. Call it whenever the level changes.
  Future<void> scheduleDaily({required int level}) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();

      // The wall-clock time is worked out with the *device's* clock, not
      // with tz.local — that defaults to UTC unless the app looks the zone up,
      // and scheduling 19:30 UTC lands in the middle of the night for anyone
      // east of London. Converting the local instant afterwards keeps it at
      // half seven wherever the player is.
      final now = DateTime.now();
      var first = DateTime(now.year, now.month, now.day, _hour, _minute);
      if (!first.isAfter(now)) {
        first = first.add(const Duration(days: 1));
      }

      // A different line each day, and a different starting point each time
      // the schedule is rebuilt, so it never repeats in a recognisable cycle.
      final offset = math.Random().nextInt(_copy.length);

      for (var day = 0; day < _daysAhead; day++) {
        final (title, body) = _copy[(offset + day) % _copy.length];
        final when = DateTime(
          first.year,
          first.month,
          first.day + day,
          _hour,
          _minute,
        );
        await _plugin.zonedSchedule(
          id: 100 + day,
          scheduledDate: tz.TZDateTime.from(when, tz.local),
          title: title.replaceAll('{L}', '$level'),
          body: body.replaceAll('{L}', '$level'),
          notificationDetails: _details(level),
          // Inexact on purpose: an exact alarm needs a special permission on
          // Android 12+, and a reminder does not care about the minute.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
      // After the rebuild, never before — cancelAll() would take it straight
      // back off the shade.
      if (_testNow) await showNow(level: level);
    } catch (_) {
      // Scheduling failed (permission refused, or a locked-down ROM) — the
      // game is unaffected.
    }
  }

  NotificationDetails _details(int level) => NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      // Tints the small icon and the app name — the notification wears the
      // game's own pink rather than the system grey.
      color: GameTheme.accent,
      colorized: true,
      // The colourful app icon, beside the text. The name is a res/drawable
      // entry, not a mipmap path — that is the only place the plugin looks.
      largeIcon: const DrawableResourceAndroidBitmap('notification_large_icon'),
      styleInformation: BigTextStyleInformation(
        'Level $level is still on the board. '
        'Tap to pick up exactly where you left off.',
        contentTitle: '<b>Arrow Escape</b> · Level $level',
        htmlFormatContent: true,
        htmlFormatContentTitle: true,
        summaryText: 'Tap to play',
      ),
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      autoCancel: true,
      ticker: 'Arrow Escape',
    ),
    iOS: const DarwinNotificationDetails(),
  );

  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {
      // Nothing to do.
    }
  }
}
