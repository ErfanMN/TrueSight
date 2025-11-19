import 'package:flutter/material.dart';

class HexagonLogo extends StatelessWidget {
  const HexagonLogo({
    super.key,
    this.size = 24,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size.square(size),
      painter: _HexagonPainter(
        fill: colorScheme.primary,
        outline: colorScheme.onPrimary.withOpacity(0.9),
      ),
    );
  }
}

class _HexagonPainter extends CustomPainter {
  _HexagonPainter({
    required this.fill,
    required this.outline,
  });

  final Color fill;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = fill;

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..color = outline;

    final path = Path();
    final w = size.width;
    final h = size.height;

    path.moveTo(w * 0.5, 0);
    path.lineTo(w, h * 0.25);
    path.lineTo(w, h * 0.75);
    path.lineTo(w * 0.5, h);
    path.lineTo(0, h * 0.75);
    path.lineTo(0, h * 0.25);
    path.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

