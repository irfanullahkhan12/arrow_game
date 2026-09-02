import 'shape_math.dart';

/// The built-in board silhouettes.
///
/// These are the *fallback* set: when the online designer is switched off, has
/// no key, or the device is offline, levels rotate through this list so the
/// board never repeats itself for twenty-five levels at a time. When the AI is
/// reachable it draws its own outline instead — see `DesignedSilhouette`.
enum BoardShape {
  rectangle('Board'),
  circle('Circle'),
  diamond('Diamond'),
  cross('Plus'),
  xCross('Cross'),
  heart('Heart'),
  star5('Star'),
  star6('Six-point Star'),
  star8('Eight-point Star'),
  triangle('Triangle'),
  pentagon('Pentagon'),
  hexagon('Hexagon'),
  octagon('Octagon'),
  flower('Flower'),
  gear('Gear'),
  ring('Ring'),
  squircle('Squircle'),
  butterfly('Butterfly'),
  shield('Shield'),
  arrow('Arrow'),
  gem('Gem'),
  moon('Moon'),
  clover('Clover'),
  hourglass('Hourglass'),
  bowtie('Bowtie');

  const BoardShape(this.label);

  final String label;

  static BoardShape? fromName(String? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// Is normalized point (x, y) — both in [-1, 1] — inside the silhouette?
  bool contains(double x, double y) => switch (this) {
    BoardShape.rectangle => true,
    BoardShape.circle => x * x + y * y <= 1,
    BoardShape.diamond => x.abs() + y.abs() <= 1,
    BoardShape.cross => crossContains(x, y, 0.34, false),
    BoardShape.xCross => crossContains(x, y, 0.30, true),
    BoardShape.heart => heartContains(x, y),
    BoardShape.star5 => starContains(x, y, 5, 0.45, -1.5708),
    BoardShape.star6 => starContains(x, y, 6, 0.52, 0),
    BoardShape.star8 => starContains(x, y, 8, 0.58, 0),
    BoardShape.triangle => polygonContains(x, y, 3, -1.5708),
    BoardShape.pentagon => polygonContains(x, y, 5, -1.5708),
    BoardShape.hexagon => polygonContains(x, y, 6, 0),
    BoardShape.octagon => polygonContains(x, y, 8, 0.3927),
    BoardShape.flower => flowerContains(x, y, 6, 0.42),
    BoardShape.gear => gearContains(x, y, 10, 0.24),
    BoardShape.ring => ringContains(x, y, 0.45),
    BoardShape.squircle => superellipseContains(x, y, 4),
    BoardShape.butterfly => butterflyContains(x, y),
    BoardShape.shield => shieldContains(x, y),
    BoardShape.arrow => arrowContains(x, y),
    BoardShape.gem => gemContains(x, y),
    BoardShape.moon => moonContains(x, y),
    BoardShape.clover => cloverContains(x, y),
    BoardShape.hourglass => hourglassContains(x, y),
    BoardShape.bowtie => bowtieContains(x, y),
  };

  /// Everything except the plain rectangle — what levels rotate through.
  static const shaped = <BoardShape>[
    BoardShape.circle,
    BoardShape.diamond,
    BoardShape.cross,
    BoardShape.xCross,
    BoardShape.heart,
    BoardShape.star5,
    BoardShape.star6,
    BoardShape.star8,
    BoardShape.triangle,
    BoardShape.pentagon,
    BoardShape.hexagon,
    BoardShape.octagon,
    BoardShape.flower,
    BoardShape.gear,
    BoardShape.ring,
    BoardShape.squircle,
    BoardShape.butterfly,
    BoardShape.shield,
    BoardShape.arrow,
    BoardShape.gem,
    BoardShape.moon,
    BoardShape.clover,
    BoardShape.hourglass,
    BoardShape.bowtie,
  ];
}
