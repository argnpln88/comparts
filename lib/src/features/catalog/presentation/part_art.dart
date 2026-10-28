import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../domain/product.dart';

// Code-drawn category artwork, not a photograph of a particular listing.
class PartArt extends StatelessWidget {
  const PartArt({
    super.key,
    required this.category,
    this.imageUrl,
    this.large = false,
  });
  final PartCategory category;
  final String? imageUrl;
  final bool large;
  @override
  Widget build(BuildContext context) {
    final art = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFEBF1FF),
            category == PartCategory.gpu
                ? const Color(0xFFD8E5F0)
                : const Color(0xFFF2F4FA),
          ],
        ),
      ),
      child: Center(
        child: SizedBox(
          width: large ? 240 : 140,
          height: large ? 190 : 105,
          child: CustomPaint(painter: _HardwarePainter(category)),
        ),
      ),
    );
    if (imageUrl == null) return art;
    return Image.network(
      imageUrl!,
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (_, _, _) => art,
      loadingBuilder: (_, child, progress) => progress == null ? child : art,
    );
  }
}

class _HardwarePainter extends CustomPainter {
  _HardwarePainter(this.category);
  final PartCategory category;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-.12);
    final scale = math.min(size.width / 140, size.height / 105);
    canvas.scale(scale);
    final paint = Paint();
    void rect(Rect r, Color color, [double radius = 5]) {
      paint.color = color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(radius)),
        paint,
      );
    }

    if (category == PartCategory.gpu ||
        category == PartCategory.psu ||
        category == PartCategory.cooler) {
      rect(const Rect.fromLTWH(-61, -29, 122, 62), const Color(0xFF24344C), 8);
      rect(const Rect.fromLTWH(-57, -25, 114, 5), const Color(0xFF4B6081), 2);
      final fans = category == PartCategory.gpu ? [-29.0, 29.0] : [0.0];
      for (final x in fans) {
        paint.color = const Color(0xFF101D30);
        canvas.drawCircle(Offset(x, 2), 24, paint);
        for (var i = 0; i < 7; i++) {
          canvas.save();
          canvas.translate(x, 2);
          canvas.rotate(i * math.pi * 2 / 7);
          rect(const Rect.fromLTWH(0, -5, 20, 9), const Color(0xFF5A6D86), 5);
          canvas.restore();
        }
        paint.color = const Color(0xFF9CB8E7);
        canvas.drawCircle(Offset(x, 2), 6, paint);
      }
      rect(const Rect.fromLTWH(-40, 33, 55, 5), const Color(0xFFB99C59), 0);
    } else if (category == PartCategory.cpu ||
        category == PartCategory.motherboard) {
      rect(const Rect.fromLTWH(-41, -40, 82, 82), const Color(0xFF2C4D57), 5);
      for (var i = -30; i <= 30; i += 10) {
        rect(
          Rect.fromLTWH(i.toDouble(), -45, 4, 7),
          const Color(0xFFB99C59),
          1,
        );
        rect(Rect.fromLTWH(i.toDouble(), 38, 4, 7), const Color(0xFFB99C59), 1);
      }
      rect(const Rect.fromLTWH(-31, -30, 62, 62), const Color(0xFFAFBCD0), 5);
      rect(const Rect.fromLTWH(-25, -24, 50, 50), const Color(0xFFDFE5EE), 3);
      final text = TextPainter(
        text: const TextSpan(
          text: 'CPU',
          style: TextStyle(
            color: ink,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
    } else if (category == PartCategory.ram ||
        category == PartCategory.storage) {
      for (final y in [-18.0, 15.0]) {
        rect(Rect.fromLTWH(-58, y, 116, 25), const Color(0xFF263E56), 3);
        for (var i = -47; i < 48; i += 23) {
          rect(
            Rect.fromLTWH(i.toDouble(), y + 4, 18, 15),
            const Color(0xFF506B89),
            2,
          );
        }
        rect(Rect.fromLTWH(-50, y + 25, 99, 4), const Color(0xFFB99C59), 0);
      }
    } else {
      rect(const Rect.fromLTWH(-49, -35, 98, 65), const Color(0xFF24344C), 5);
      rect(const Rect.fromLTWH(-43, -29, 86, 50), const Color(0xFF4A71AC), 3);
      rect(const Rect.fromLTWH(-5, 30, 10, 11), const Color(0xFF506B89), 1);
      rect(const Rect.fromLTWH(-23, 40, 46, 4), const Color(0xFF24344C), 2);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HardwarePainter oldDelegate) =>
      oldDelegate.category != category;
}
