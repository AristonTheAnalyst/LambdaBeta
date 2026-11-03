import 'package:flutter/material.dart';

import '../../core/styles/app_colors.dart';

/// The placeholder profile picture (2026-10-30): the Lambda mark on a tinted
/// disc.
///
/// Real pictures are a later feature. Until then every person draws as the
/// mark, so a friend row, a profile header and every future avatar slot carry
/// the same shape — a hole where a face will go would read as a broken image.
class LambdaAvatar extends StatelessWidget {
  const LambdaAvatar({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      // The glyph sits a little under half the disc, the way a face fills a
      // picture without touching its edge.
      child: LambdaGlyph(height: size * 0.46, color: AppColors.accent),
    );
  }
}

/// The Lambda mark itself, drawn from the landing site's logo path
/// (`LambdaLandingSite/Filled Logo.svg`). A widget rather than an image so it
/// scales without assets and repaints with the palette.
class LambdaGlyph extends StatelessWidget {
  const LambdaGlyph({super.key, required this.height, required this.color});

  /// How tall the glyph draws; width follows the mark's own 314 : 528 aspect.
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(height * 314 / 528, height),
      painter: _LambdaGlyphPainter(color),
    );
  }
}

class _LambdaGlyphPainter extends CustomPainter {
  const _LambdaGlyphPainter(this.color);

  final Color color;

  /// The source viewBox — every coordinate below is in these units.
  static const double _vw = 314;
  static const double _vh = 528;

  /// The source's stroke width. The logo is drawn as a filled path WITH a
  /// round-joined stroke, which is what rounds its corners; both are painted
  /// so the silhouette matches the mark.
  static const double _stroke = 12.76;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / _vh;
    canvas.save();
    canvas.translate((size.width - _vw * scale) / 2, 0);
    canvas.scale(scale);

    final path = Path()
      ..moveTo(222, 521)
      ..lineTo(157.03, 330.888)
      ..lineTo(92.86, 521.622)
      ..lineTo(6.8, 521.622)
      ..lineTo(114, 206)
      ..lineTo(46, 6)
      ..lineTo(132, 6)
      ..lineTo(308, 521)
      ..close();

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fill);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, stroke);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_LambdaGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}
