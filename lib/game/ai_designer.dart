import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../models/palette.dart';
import '../models/silhouette.dart';

class AiDesign {
  const AiDesign({this.silhouette, this.palette});

  /// The outline the designer drew for this level, or null if it only sent
  /// colours back.
  final Silhouette? silhouette;
  final Palette? palette;

  bool get isEmpty => silhouette == null && palette == null;
}

/// The online level designer. It speaks the OpenAI chat-completions protocol,
/// so any OpenAI-compatible provider works. The defaults point at Groq's free
/// tier running OpenAI's small open-weight model, so a free key is all that is
/// needed — the whole call costs a few hundred tokens:
///
/// ```
/// flutter run --dart-define=AI_API_KEY=gsk_...
/// flutter build apk --dart-define-from-file=env.json
/// ```
///
/// Endpoint and model are overridable, e.g. an even cheaper non-reasoning one:
/// `--dart-define=AI_MODEL=llama-3.1-8b-instant`
///
/// **What the AI actually designs.** It does not pick from a menu of shapes —
/// it hands back an outline as a family plus numbers (a nine-point star with a
/// hole, a twelve-tooth gear, a wobbling blob with these harmonics), so every
/// level it touches is a shape that has never been drawn before. Every number
/// is clamped on arrival, so a bad reply still yields a playable board, and the
/// solver always builds the actual arrows — the AI never decides those.
///
/// With no key, offline, or on any error at all, [design] returns null and the
/// game falls back to the twenty-five built-in silhouettes. The game never
/// needs the network.
class AiDesigner {
  static const _apiKey = String.fromEnvironment('AI_API_KEY');
  static const _baseUrl = String.fromEnvironment(
    'AI_BASE_URL',
    defaultValue: 'https://api.groq.com/openai/v1/chat/completions',
  );
  static const _model = String.fromEnvironment(
    'AI_MODEL',
    defaultValue: 'openai/gpt-oss-20b',
  );

  /// Is an online designer configured at all?
  static bool get enabled => _apiKey.isNotEmpty;

  static final _rng = math.Random();

  static Future<AiDesign?> design(int level) async {
    if (_apiKey.isEmpty) return null;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      final request = await client
          .postUrl(Uri.parse(_baseUrl))
          .timeout(const Duration(seconds: 4));
      request.headers
        // The charset is not decoration: without it dart:io encodes the body
        // as latin1, so any non-ASCII character in the prompt throws.
        ..set('content-type', 'application/json; charset=utf-8')
        ..set('authorization', 'Bearer $_apiKey');
      request.write(
        jsonEncode({
          'model': _model,
          'max_tokens': 500,
          'temperature': 1.15,
          // Reasoning models would burn tokens deliberating over a palette;
          // the plain chat models reject the field outright, hence the check.
          if (_model.contains('gpt-oss')) 'reasoning_effort': 'low',
          'messages': [
            {'role': 'system', 'content': _system},
            {'role': 'user', 'content': _prompt(level)},
          ],
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final body = await response.transform(utf8.decoder).join();
      client.close();
      if (response.statusCode != 200) return null;

      final choices = (jsonDecode(body) as Map)['choices'] as List?;
      if (choices == null || choices.isEmpty) return null;
      final text =
          ((choices.first as Map)['message'] as Map)['content'] as String;
      return parse(text);
    } catch (_) {
      return null; // offline / bad key / bad reply → built-in designer
    }
  }

  static const _system =
      'You are a puzzle game level designer. Reply with raw JSON only, no '
      'prose and no markdown fences.';

  /// The seed is in the prompt on purpose: it is what stops the model handing
  /// back the same tidy hexagon every single level.
  static String _prompt(int level) {
    final seed = _rng.nextInt(1 << 30);
    return '''
Design the board outline for level $level of a neon arrow puzzle. Design seed $seed — make this outline clearly different from an ordinary circle or square, and different from what seed ${seed - 1} would have produced.

Reply with ONLY this JSON:
{
  "name": "two or three words naming the shape",
  "family": one of "star","polygon","flower","gear","ring","superellipse","blob","cross",
  "points": 3-14        // star points, flower petals, or gear teeth
  "inner": 0.2-0.85     // star valley radius, or ring hole radius
  "rotation": -3.1-3.1  // radians
  "depth": 0.1-0.6      // petal or tooth depth
  "sides": 3-14         // polygon sides
  "exponent": 0.6-8     // superellipse: 1 diamond, 2 circle, 6 square
  "hole": 0 or 0.2-0.6  // optional hole punched through the middle
  "arm": 0.18-0.5       // cross arm width
  "diagonal": true/false // cross drawn as an X
  "harmonics": [-0.35..0.35 x4] // blob wobble
  "colors": [12 distinct bright neon hex colors like "#FF3D8B" that glow against a deep purple board]
}
Include every field. Pick the family that suits the shape you have in mind, and choose bold values — the outline should read as a deliberate design at a glance.''';
  }

  /// Pulls a design out of a model reply. Exposed so it can be tested without
  /// a network call.
  static AiDesign? parse(String text) {
    try {
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      final json =
          jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;

      final family = ShapeFamily.fromName(
        (json['family'] as String?)?.toLowerCase().trim(),
      );
      double num_(Object? v, double fallback) =>
          v is num ? v.toDouble() : fallback;
      int int_(Object? v, int fallback) => v is num ? v.toInt() : fallback;

      final silhouette = family == null
          ? null
          : DesignedSilhouette(
              family: family,
              name: json['name'] as String?,
              points: int_(json['points'], 6),
              inner: num_(json['inner'], 0.45),
              rotation: num_(json['rotation'], 0),
              depth: num_(json['depth'], 0.35),
              sides: int_(json['sides'], 6),
              exponent: num_(json['exponent'], 2.5),
              hole: num_(json['hole'], 0),
              arm: num_(json['arm'], 0.34),
              diagonal: json['diagonal'] == true,
              harmonics: [
                for (final h in (json['harmonics'] as List? ?? const []))
                  if (h is num) h.toDouble(),
              ],
            );

      final design = AiDesign(
        silhouette: silhouette,
        palette: Palette.fromHexList(json['colors'] as List? ?? const []),
      );
      return design.isEmpty ? null : design;
    } catch (_) {
      return null;
    }
  }
}
