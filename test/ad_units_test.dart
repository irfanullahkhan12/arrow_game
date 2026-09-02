import 'dart:io';

import 'package:arowgame/main.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ad ids are the one piece of configuration that fails *silently*: a wrong id
/// does not crash, it just never fills, and a live id in a debug build gets the
/// AdMob account suspended for invalid traffic. So they are pinned down here.
void main() {
  const testPublisher = 'ca-app-pub-3940256099942544';

  test('a debug build only ever uses Google test units', () {
    // Tests run in debug, which is exactly the mode that must never touch a
    // live unit.
    expect(AdUnits.usingTestUnits, isTrue);
    for (final id in [
      AdUnits.banner,
      AdUnits.interstitial,
      AdUnits.rewarded,
      AdUnits.appOpen,
    ]) {
      expect(
        id,
        startsWith('$testPublisher/'),
        reason: 'a debug build must not serve $id',
      );
    }
  });

  test('the manifest app id and the live units belong to one account', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final appId = RegExp(
      r'com\.google\.android\.gms\.ads\.APPLICATION_ID"\s*\n?\s*android:value="([^"]+)"',
    ).firstMatch(manifest)?.group(1);

    expect(appId, isNotNull, reason: 'no AdMob APPLICATION_ID in the manifest');
    expect(
      appId,
      isNot(startsWith(testPublisher)),
      reason: 'the manifest still holds Google\'s test app id',
    );
    // "ca-app-pub-<account>~<app>" and "ca-app-pub-<account>/<unit>" have to
    // agree on the account, or nothing fills.
    final publisher = appId!.split('~').first;

    final source = File('lib/services/ads_service.dart').readAsStringSync();
    final live = RegExp(
      r"_live\w+ = '([^']+)'",
    ).allMatches(source).map((m) => m.group(1)!).toList();

    expect(live.length, 4, reason: 'expected four live ad units');
    for (final id in live) {
      expect(
        id,
        startsWith('$publisher/'),
        reason: '$id does not belong to $publisher',
      );
    }
    // All four are distinct — a copy-paste slip here is invisible at runtime.
    expect(live.toSet().length, 4);
  });
}
