import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Смуга дня: 48 клітинок по 30 хв і риска «зараз».
class DayStrip extends StatelessWidget {
  const DayStrip({
    super.key,
    required this.day,
    required this.now,
    this.height = 26,
    this.showHours = true,
  });

  final DaySchedule day;
  final int now;
  final double height;
  final bool showHours;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pos = (now - day.dayStart) / 86400;
    final showNow = pos >= 0 && pos < 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: LayoutBuilder(builder: (context, c) {
            return Stack(clipBehavior: Clip.none, children: [
              Row(children: [
                for (var i = 0; i < 48; i++)
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.only(
                        right: i == 47 ? 0 : (i % 2 == 1 ? 2 : 0.5),
                      ),
                      decoration: BoxDecoration(
                        color: p.of(day.slots[i]),
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(i == 0 ? 5 : 1),
                          right: Radius.circular(i == 47 ? 5 : 1),
                        ),
                      ),
                    ),
                  ),
              ]),
              if (showNow)
                Positioned(
                  left: (c.maxWidth * pos - 1).clamp(0, c.maxWidth - 2),
                  top: -4,
                  bottom: -4,
                  child: Container(width: 2, color: p.ink),
                ),
            ]);
          }),
        ),
        if (showHours) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final h in const [0, 6, 12, 18, 24])
                Text(
                  h.toString().padLeft(2, '0'),
                  style: numbers(10.5, color: p.muted),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Легенда кольорів одним рядком.
class Legend extends StatelessWidget {
  const Legend({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget item(Power power, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: p.of(power),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(text, style: body(12.5, color: p.muted)),
          ],
        );
    return Wrap(spacing: 16, runSpacing: 6, children: [
      item(Power.on, 'є світло'),
      item(Power.off, 'немає'),
      item(Power.maybe, 'можливо'),
    ]);
  }
}
