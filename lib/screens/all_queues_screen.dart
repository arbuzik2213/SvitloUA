import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/day_strip.dart';
import '../widgets/pressable.dart';

/// Усі черги регіону на обраний день. Тап по черзі повертає її ключ.
class AllQueuesScreen extends StatefulWidget {
  const AllQueuesScreen({
    super.key,
    required this.schedule,
    required this.regionName,
    required this.now,
    this.selected,
  });

  final RegionSchedule schedule;
  final String regionName;
  final int now;
  final String? selected;

  @override
  State<AllQueuesScreen> createState() => _AllQueuesScreenState();
}

class _AllQueuesScreenState extends State<AllQueuesScreen> {
  late int _day = widget.schedule.sortedDays.contains(widget.schedule.today)
      ? widget.schedule.today
      : widget.schedule.sortedDays.first;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final days = widget.schedule.sortedDays;
    final queues = widget.schedule.days[_day]!;

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverSafeArea(
            bottom: false,
            sliver: SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Pressable(
                    onTap: () => Navigator.pop(context),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(CupertinoIcons.back, color: p.ink, size: 22),
                        const SizedBox(width: 2),
                        Text('Назад', style: body(16, color: p.ink)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.regionName.toUpperCase(), style: label(p.muted)),
                  const SizedBox(height: 6),
                  Text('Усі черги', style: display(30, color: p.ink)),
                  const SizedBox(height: 20),
                  if (days.length > 1)
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoSlidingSegmentedControl<int>(
                        groupValue: _day,
                        backgroundColor: p.line.withValues(alpha: 0.6),
                        thumbColor: p.surface,
                        children: {
                          for (final d in days)
                            d: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                d == widget.schedule.today
                                    ? 'Сьогодні'
                                    : d > widget.schedule.today
                                        ? 'Завтра'
                                        : kyivShortDate(d),
                                style: body(14, weight: FontWeight.w500, color: p.ink),
                              ),
                            ),
                        },
                        onValueChanged: (v) {
                          if (v != null) setState(() => _day = v);
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Legend(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            sliver: SliverList.list(children: [
              for (final key in widget.schedule.queueNames.keys)
                if (queues[key] != null)
                  Pressable(
                    onTap: () => Navigator.pop(context, key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: p.line)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(
                              queueShort(key),
                              style: display(15,
                                  weight: key == widget.selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: p.ink),
                            ),
                            if (key == widget.selected) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                    color: p.light, shape: BoxShape.circle),
                              ),
                            ],
                            const Spacer(),
                            Text(
                              queues[key]!.offSeconds == 0
                                  ? 'без відключень'
                                  : 'без світла ${formatDuration(queues[key]!.offSeconds)}',
                              style: numbers(13, weight: FontWeight.w400, color: p.muted),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          DayStrip(
                            day: queues[key]!,
                            now: widget.now,
                            height: 14,
                            showHours: false,
                          ),
                        ],
                      ),
                    ),
                  ),
            ]),
          ),
        ],
      ),
    );
  }
}
