import 'board_shape.dart';
import 'shape_math.dart';

/// A board outline. All the game ever asks of one is "is this point inside?",
/// which is why a hand-drawn preset and an outline the AI invented on the spot
/// are interchangeable here.
sealed class Silhouette {
  const Silhouette();

  bool contains(double x, double y);

  /// Shown on the board chip, e.g. "Seven-point Star".
  String get label;

  /// True only for the plain rectangle, which the mask builder sizes with its
  /// own phone-shaped aspect rather than by growing an outline.
  bool get isRectangle => false;

  Map<String, dynamic> toJson();

  static Silhouette fromJson(Map<String, dynamic> json) {
    if (json['t'] == 'design') {
      return DesignedSilhouette.fromJson(json) ??
          const PresetSilhouette(BoardShape.rectangle);
    }
    return PresetSilhouette(
      BoardShape.fromName(json['s'] as String?) ?? BoardShape.rectangle,
    );
  }
}

/// One of the built-in shapes.
class PresetSilhouette extends Silhouette {
  const PresetSilhouette(this.shape);

  final BoardShape shape;

  @override
  bool contains(double x, double y) => shape.contains(x, y);

  @override
  String get label => shape.label;

  @override
  bool get isRectangle => shape == BoardShape.rectangle;

  @override
  Map<String, dynamic> toJson() => {'t': 'preset', 's': shape.name};
}

/// The shape families the online designer draws with. Each one covers a whole
/// space of outlines rather than a single fixed picture, so the designer can
/// hand back something genuinely new every level while never producing an
/// outline the carver cannot use.
enum ShapeFamily {
  star,
  polygon,
  flower,
  gear,
  ring,
  superellipse,
  blob,
  cross;

  static ShapeFamily? fromName(String? name) {
    for (final f in values) {
      if (f.name == name) return f;
    }
    return null;
  }
}

/// An outline the designer described with numbers. Every parameter is clamped
/// on the way in, so even a nonsense reply from the model still produces a
/// board that is drawable and playable.
class DesignedSilhouette extends Silhouette {
  DesignedSilhouette({
    required this.family,
    String? name,
    int points = 6,
    double inner = 0.45,
    double rotation = 0,
    double depth = 0.35,
    int sides = 6,
    double exponent = 2.5,
    double hole = 0,
    double arm = 0.34,
    this.diagonal = false,
    List<double> harmonics = const [],
  }) : points = points.clamp(3, 14),
       inner = inner.clamp(0.2, 0.85),
       rotation = rotation.clamp(-6.3, 6.3),
       depth = depth.clamp(0.1, 0.6),
       sides = sides.clamp(3, 14),
       exponent = exponent.clamp(0.6, 8),
       // A hole big enough to matter but never big enough to leave a hoop too
       // thin for an arrow to sit in.
       hole = hole <= 0.05 ? 0 : hole.clamp(0.2, 0.6),
       arm = arm.clamp(0.18, 0.5),
       harmonics = [
         for (final h in harmonics.take(6)) h.clamp(-0.35, 0.35),
       ],
       name = (name == null || name.trim().isEmpty)
           ? _defaultName(family)
           : name.trim();

  final ShapeFamily family;
  final String name;
  final int points;
  final double inner;
  final double rotation;
  final double depth;
  final int sides;
  final double exponent;
  final double hole;
  final double arm;
  final bool diagonal;
  final List<double> harmonics;

  static String _defaultName(ShapeFamily family) => switch (family) {
    ShapeFamily.star => 'Star',
    ShapeFamily.polygon => 'Polygon',
    ShapeFamily.flower => 'Flower',
    ShapeFamily.gear => 'Gear',
    ShapeFamily.ring => 'Ring',
    ShapeFamily.superellipse => 'Curve',
    ShapeFamily.blob => 'Blob',
    ShapeFamily.cross => 'Cross',
  };

  @override
  bool contains(double x, double y) {
    if (hole > 0 && radiusOf(x, y) < hole) return false;
    return switch (family) {
      ShapeFamily.star => starContains(x, y, points, inner, rotation),
      ShapeFamily.polygon => polygonContains(x, y, sides, rotation),
      ShapeFamily.flower => flowerContains(x, y, points, depth, rotation),
      ShapeFamily.gear => gearContains(x, y, points, depth, rotation),
      ShapeFamily.ring => ringContains(x, y, inner),
      ShapeFamily.superellipse => superellipseContains(x, y, exponent),
      ShapeFamily.blob => blobContains(x, y, harmonics),
      ShapeFamily.cross => crossContains(x, y, arm, diagonal),
    };
  }

  @override
  String get label => name;

  @override
  Map<String, dynamic> toJson() => {
    't': 'design',
    'f': family.name,
    'n': name,
    'p': points,
    'i': inner,
    'ro': rotation,
    'd': depth,
    'sd': sides,
    'e': exponent,
    'h': hole,
    'a': arm,
    'dg': diagonal,
    'hm': harmonics,
  };

  static DesignedSilhouette? fromJson(Map<String, dynamic> json) {
    final family = ShapeFamily.fromName(json['f'] as String?);
    if (family == null) return null;
    double num_(Object? v, double fallback) =>
        v is num ? v.toDouble() : fallback;
    int int_(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    return DesignedSilhouette(
      family: family,
      name: json['n'] as String?,
      points: int_(json['p'], 6),
      inner: num_(json['i'], 0.45),
      rotation: num_(json['ro'], 0),
      depth: num_(json['d'], 0.35),
      sides: int_(json['sd'], 6),
      exponent: num_(json['e'], 2.5),
      hole: num_(json['h'], 0),
      arm: num_(json['a'], 0.34),
      diagonal: json['dg'] == true,
      harmonics: [
        for (final h in (json['hm'] as List? ?? const []))
          if (h is num) h.toDouble(),
      ],
    );
  }
}
