import 'package:flutter/material.dart';

class CeroLogo extends StatelessWidget {
  final double size;
  final List<Color>? gradientColors;

  const CeroLogo({
    super.key,
    this.size = 24.0,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final colors = gradientColors ?? [
      const Color(0xFF818CF8),
      const Color(0xFFC084FC),
    ];

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CeroLogoPainter(colors: colors),
      ),
    );
  }
}

class _CeroLogoPainter extends CustomPainter {
  final List<Color> colors;

  _CeroLogoPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final double strokeWidth = size.width * 0.12;
    final double radius = (size.width - strokeWidth) * 0.32;
    final center = Offset(size.width / 2, size.height / 2);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    paint.shader = LinearGradient(
      colors: colors,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawCircle(center, radius, paint);

    final startSlash = Offset(size.width * 0.41, size.height * 0.28);
    final endSlash = Offset(size.width * 0.59, size.height * 0.72);
    canvas.drawLine(startSlash, endSlash, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
