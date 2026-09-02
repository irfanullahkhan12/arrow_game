import 'package:audioplayers/audioplayers.dart';

import '../models/arrow_kind.dart';
import '../models/arrow_piece.dart';
import 'player_profile.dart';

/// Every fire sound in the game, and the players that play them.
///
/// Ordinary arrows go through a pool of low-latency players — Android backs
/// that with SoundPool, so a burst of taps overlaps cheaply. The specials get
/// their own players in media-player mode instead: their samples are seconds
/// long, and SoundPool refuses anything much over a megabyte once decoded, so
/// a pooled black-arrow sound would simply never be heard.
class SoundService {
  SoundService._();

  static final SoundService instance = SoundService._();

  static const _poolSize = 6;
  static const _specialPoolSize = 3;

  /// One sample per special, matched by name.
  static const _specialSamples = <ArrowKind, String>{
    ArrowKind.boost: 'sounds/black.wav',
    ArrowKind.rainbow: 'sounds/rainbow.wav',
    ArrowKind.ghost: 'sounds/gost.wav',
    ArrowKind.bomb: 'sounds/bomb.wav',
  };

  /// Plain arrows keep the two-sample split: a long arrow lands heavier than
  /// a stubby one.
  static const _bigSample = 'sounds/arrow_big.mp3';
  static const _smallSample = 'sounds/arrow_small.mp3';

  /// A blocked arrow was tapped and a life went with it.
  static const missSample = 'sounds/chancemiss.wav';

  /// The last life is gone.
  static const gameOverSample = 'sounds/gameover.wav';

  /// An arrow this long or longer counts as big.
  static const _bigFrom = 5;

  /// The asset [piece] fires with. Public so a test can check every one of
  /// them is actually shipped — a missing sound asset fails silently.
  static String sampleFor(ArrowPiece piece) =>
      _specialSamples[piece.kind] ??
      (piece.cells.length >= _bigFrom ? _bigSample : _smallSample);

  /// Every sample the game can play.
  static Set<String> get samples => {
    ..._specialSamples.values,
    _bigSample,
    _smallSample,
    missSample,
    gameOverSample,
  };

  final List<AudioPlayer> _pool = [];
  final List<AudioPlayer> _specialPool = [];
  int _index = 0;
  int _specialIndex = 0;

  void start() {
    if (_pool.isNotEmpty) return;

    // Game SFX must not fight over Android audio focus: with focus requests
    // on, every shot pauses the previous one and floods the main thread with
    // focus-change messages.
    AudioPlayer.global.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.none,
        ),
      ),
    );

    // Low-latency mode uses Android's SoundPool: samples are cached after the
    // first play and overlapping shots are cheap.
    for (var i = 0; i < _poolSize; i++) {
      _pool.add(AudioPlayer()..setPlayerMode(PlayerMode.lowLatency));
    }
    for (var i = 0; i < _specialPoolSize; i++) {
      _specialPool.add(AudioPlayer()..setPlayerMode(PlayerMode.mediaPlayer));
    }
  }

  void dispose() {
    for (final player in [..._pool, ..._specialPool]) {
      player.dispose();
    }
    _pool.clear();
    _specialPool.clear();
  }

  /// Round-robin over the right pool, so rapid taps — even two fingers at
  /// once — each play a full sound that overlaps freely with the others.
  Future<void> playFire(ArrowPiece piece) async {
    if (!PlayerProfile.instance.soundOn) return;

    final special = _specialSamples.containsKey(piece.kind);
    final pool = special ? _specialPool : _pool;
    if (pool.isEmpty) return;

    final AudioPlayer player;
    if (special) {
      player = pool[_specialIndex];
      _specialIndex = (_specialIndex + 1) % pool.length;
    } else {
      player = pool[_index];
      _index = (_index + 1) % pool.length;
    }

    try {
      await player.stop();
      // A special sounds like itself; only the plain arrows are pitched, so a
      // long one lands heavier than a stubby one.
      await player.setPlaybackRate(
        special ? 1.0 : (piece.cells.length >= _bigFrom ? 0.85 : 1.15),
      );
      await player.play(AssetSource(sampleFor(piece)));
    } catch (_) {
      // Sound must never break the game.
    }
  }

  /// The thud of tapping an arrow that has nowhere to go — one life gone.
  Future<void> playMiss() => _playCue(missSample);

  /// The last life. Played just before the out-of-lives dialog appears.
  Future<void> playGameOver() => _playCue(gameOverSample);

  /// One-off cues share the specials' players: they are the same shape of
  /// sound — a second or two long, never more than one at a time.
  Future<void> _playCue(String asset) async {
    if (!PlayerProfile.instance.soundOn || _specialPool.isEmpty) return;
    final player = _specialPool[_specialIndex];
    _specialIndex = (_specialIndex + 1) % _specialPool.length;
    try {
      await player.stop();
      await player.setPlaybackRate(1);
      await player.play(AssetSource(asset));
    } catch (_) {
      // Sound must never break the game.
    }
  }
}
