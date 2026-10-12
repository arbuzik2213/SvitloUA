import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Циферблат на 24 години: 48 сегментів по 30 хв, північ угорі.
/// Минулі півгодини приглушені, поточний момент — крапка на кільці.
class DayDial extends StatelessWidget {
  const DayDial({
    super.key,
    required this.day,
    required this.now,
    required this.child,
    this.size = 280,
  });

  final DaySchedule day;
  final int now;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _DialPainter(day: day, now: now, palette: context.palette),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(size * 0.2),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.day, required this.now, required this.palette});

  final DaySchedule day;
  final int now;
  final Palette palette;

  static const _stroke = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 26;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final slot = 2 * math.pi / 48;
    const gap = 0.012;
    final nowSlot = (now - day.dayStart) / 1800;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.butt;

    for (var i = 0; i < 48; i++) {
      final past = i + 1 <= nowSlot;
      final color = palette.of(day.slots[i]);
      paint.color = past ? color.withValues(alpha: 0.28) : color;
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * slot + gap / 2,
        slot - gap,
        false,
        paint,
      );
    }

    // Мітки годин зовні кільця.
    final tick = Paint()
      ..color = palette.muted
      ..strokeWidth = 1;
    for (var h = 0; h < 24; h++) {
      final a = -math.pi / 2 + h * 2 * math.pi / 24;
      final major = h % 6 == 0;
      final r1 = radius + _stroke / 2 + 3;
      final r2 = r1 + (major ? 6 : 3);
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * r1,
        center + Offset(math.cos(a), math.sin(a)) * r2,
        tick,
      );
      if (major) {
        final tp = TextPainter(
          text: TextSpan(
            text: h.toString().padLeft(2, '0'),
            style: numbers(10.5, color: palette.muted),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final pos = center + Offset(math.cos(a), math.sin(a)) * (r2 + 9);
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // Поточний момент.
    if (nowSlot >= 0 && nowSlot < 48) {
      final a = -math.pi / 2 + nowSlot * slot;
      final p = center + Offset(math.cos(a), math.sin(a)) * radius;
      canvas.drawCircle(p, _stroke / 2 + 3, Paint()..color = palette.paper);
      canvas.drawCircle(p, _stroke / 2 - 2, Paint()..color = palette.ink);
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.now != now || old.day != day || old.palette != palette;
}
