import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme.dart';
import '../../models/report.dart';

/// Renders the Kerb pin/cluster designs into bitmaps for Google Maps markers
/// (native markers can't host Flutter widgets). Bitmaps are cached per key so
/// a viewport full of markers costs a handful of canvas paints.
class KerbMarkerIcons {
  KerbMarkerIcons(this.devicePixelRatio);

  final double devicePixelRatio;
  final _cache = <String, BitmapDescriptor>{};

  static const pinSize = Size(46, 49);
  static const _shadow = Color(0x2210222A);

  /// White puck, tier-coloured ring, shape-coded glyph, grounding notch —
  /// anchor at (0.5, 1.0) so the notch tip sits on the point.
  Future<BitmapDescriptor> pin(ReportTier tier) =>
      _memo('pin-${tier.name}', pinSize, (canvas) => _paintPin(canvas, tier));

  /// Count in the middle, ring split red/amber by substantiated share —
  /// the cluster itself is data. Anchor at (0.5, 0.5).
  Future<BitmapDescriptor> cluster(int count, double redFraction) {
    final s = count >= 100
        ? 60.0
        : count >= 10
            ? 52.0
            : 46.0;
    // Bucket the fraction so nearby clusters share cache entries.
    final bucket = (redFraction * 10).round();
    return _memo(
      'cluster-$count-$bucket',
      Size(s, s),
      (canvas) => _paintCluster(canvas, s, count, bucket / 10),
    );
  }

  /// Brand-teal pin for the new-report mini map. Anchor at (0.5, 1.0).
  static const brandPinSize = Size(40, 48);
  Future<BitmapDescriptor> brandPin() =>
      _memo('brand-pin', brandPinSize, _paintBrandPin);

  Future<BitmapDescriptor> _memo(
    String key,
    Size size,
    void Function(Canvas canvas) paint,
  ) async {
    final hit = _cache[key];
    if (hit != null) return hit;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    paint(canvas);
    final image = await recorder.endRecording().toImage(
          (size.width * devicePixelRatio).ceil(),
          (size.height * devicePixelRatio).ceil(),
        );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final descriptor = BitmapDescriptor.bytes(
      data!.buffer.asUint8List(),
      imagePixelRatio: devicePixelRatio,
    );
    _cache[key] = descriptor;
    return descriptor;
  }

  void _paintPin(Canvas canvas, ReportTier tier) {
    final color = TierStyle.color(tier);
    const center = Offset(23, 21);

    // Notch first so the puck overlaps its base.
    canvas.drawPath(
      Path()
        ..moveTo(17, 40)
        ..lineTo(29, 40)
        ..lineTo(23, 49)
        ..close(),
      Paint()..color = color,
    );
    canvas.drawCircle(
      center.translate(0, 1.5),
      19.5,
      Paint()
        ..color = _shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(center, 19.5, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      18,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    _paintGlyph(canvas, tier, color, center);
  }

  /// Shape-coded glyph (octagon / triangle / circle) so meaning never rides
  /// on colour alone — mirrors TierStyle.icon.
  void _paintGlyph(Canvas canvas, ReportTier tier, Color color, Offset c) {
    final fill = Paint()..color = color;
    switch (tier) {
      case ReportTier.substantiated:
        final octagon = Path();
        for (var i = 0; i < 8; i++) {
          final a = math.pi / 8 + i * math.pi / 4;
          final p = c + Offset(math.cos(a), math.sin(a)) * 11.5;
          i == 0 ? octagon.moveTo(p.dx, p.dy) : octagon.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(octagon..close(), fill);
        _paintBang(canvas, c);
      case ReportTier.partiallySubstantiated:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - 10.5)
            ..lineTo(c.dx + 11, c.dy + 8.5)
            ..lineTo(c.dx - 11, c.dy + 8.5)
            ..close(),
          fill,
        );
        _paintBang(canvas, c.translate(0, 2.2), scale: 0.8);
      case ReportTier.unsubstantiated:
        canvas.drawCircle(c, 11, fill);
        _paintText(canvas, '?', c, fontSize: 14, color: Colors.white);
    }
  }

  void _paintBang(Canvas canvas, Offset c, {double scale = 1}) {
    final paint = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: c.translate(0, -2.6 * scale),
          width: 2.8 * scale,
          height: 8.2 * scale,
        ),
        Radius.circular(1.4 * scale),
      ),
      paint,
    );
    canvas.drawCircle(c.translate(0, 4.6 * scale), 1.7 * scale, paint);
  }

  void _paintCluster(Canvas canvas, double s, int count, double redFraction) {
    final center = Offset(s / 2, s / 2);
    canvas.drawCircle(
      center.translate(0, 1.5),
      s / 2 - 1,
      Paint()
        ..color = _shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(center, s / 2 - 1, Paint()..color = Colors.white);

    const stroke = 4.5;
    final arcRect = (Offset.zero & Size(s, s)).deflate(stroke / 2 + 2);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    const start = -math.pi / 2;
    final redSweep = 2 * math.pi * redFraction;
    if (redFraction > 0) {
      canvas.drawArc(arcRect, start, redSweep, false, arc..color = KerbColors.danger);
    }
    if (redFraction < 1) {
      canvas.drawArc(arcRect, start + redSweep, 2 * math.pi - redSweep, false,
          arc..color = KerbColors.warnBright);
    }
    _paintText(canvas, '$count', center,
        fontSize: s * 0.3, color: KerbColors.ink900);
  }

  void _paintBrandPin(Canvas canvas) {
    const center = Offset(20, 17);
    canvas.drawPath(
      Path()
        ..moveTo(14, 34)
        ..lineTo(26, 34)
        ..lineTo(20, 46)
        ..close(),
      Paint()..color = KerbColors.brand600,
    );
    canvas.drawCircle(
      center.translate(0, 1.5),
      16,
      Paint()
        ..color = _shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(center, 16, Paint()..color = Colors.white);
    canvas.drawCircle(center, 13.5, Paint()..color = KerbColors.brand600);
    canvas.drawCircle(center, 4.5, Paint()..color = Colors.white);
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset center, {
    required double fontSize,
    required Color color,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }
}
