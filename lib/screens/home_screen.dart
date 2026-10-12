import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dtek_service.dart';
import '../models.dart';
import '../regions.dart';
import '../theme.dart';
import '../widgets/day_strip.dart';
import '../widgets/dial.dart';
import '../widgets/pressable.dart';
import 'all_queues_screen.dart';
import 'pickers.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _service = DtekService();

  DtekRegion? _region;
  String? _queue;
  LoadResult? _result;
  String? _error;
  bool _loading = false;
  int _now = _unixNow();
  Timer? _clock;
  Timer? _autoRefresh;

  static int _unixNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
    _clock = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() => _now = _unixNow()),
    );
    _autoRefresh = Timer.periodic(const Duration(minutes: 15), (_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _autoRefresh?.cancel();
    super.dispose();
  }

  /// Повернулися в застосунок — одразу оновлюємо час і графік.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _now = _unixNow());
      _load();
    }
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final regionId = prefs.getString('region');
    final region = dtekRegions.where((r) => r.id == regionId).firstOrNull;
    if (region == null) {
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickRegion());
      return;
    }
    setState(() {
      _region = region;
      _queue = prefs.getString('queue_${region.id}');
    });
    await _load();
  }

  Future<void> _load() async {
    final region = _region;
    if (region == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.load(region);
      if (!mounted || region != _region) return;
      setState(() {
        _result = result;
        _now = _unixNow();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRegion() async {
    final region = await showRegionSheet(context, selectedId: _region?.id);
    if (region == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('region', region.id);
    setState(() {
      _region = region;
      _queue = prefs.getString('queue_${region.id}');
      _result = null;
    });
    await _load();
    if (_queue == null && mounted) await _pickQueue();
  }

  Future<void> _setQueue(String? queue) async {
    if (queue == null || _region == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('queue_${_region!.id}', queue);
    setState(() => _queue = queue);
  }

  Future<void> _pickQueue() async {
    final schedule = _result?.schedule;
    if (schedule == null || schedule.queueNames.isEmpty) return;
    final queue = await showQueueSheet(
      context,
      queueNames: schedule.queueNames,
      selected: _queue,
    );
    await _setQueue(queue);
  }

  Future<void> _openAllQueues() async {
    final queue = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => AllQueuesScreen(
          schedule: _result!.schedule,
          regionName: _region!.name,
          now: _now,
          selected: _queue,
        ),
      ),
    );
    await _setQueue(queue);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final region = _region;

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverSafeArea(
            bottom: false,
            sliver: SliverToBoxAdapter(child: _header(p, region)),
          ),
          if (region != null) CupertinoSliverRefreshControl(onRefresh: _load),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
            sliver: SliverList.list(children: _content(p, region)),
          ),
        ],
      ),
    );
  }

  Widget _header(Palette p, DtekRegion? region) {
    final schedule = _result?.schedule;
    final queue = schedule?.queueNames.containsKey(_queue) == true ? _queue : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Pressable(
              onTap: _pickRegion,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('РЕГІОН', style: label(p.muted)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Flexible(
                      child: Text(
                        region?.name ?? 'Оберіть',
                        overflow: TextOverflow.ellipsis,
                        style: display(19, weight: FontWeight.w500, color: p.ink),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(CupertinoIcons.chevron_down, size: 15, color: p.muted),
                  ]),
                ],
              ),
            ),
          ),
          if (schedule != null && schedule.queueNames.isNotEmpty)
            Pressable(
              onTap: _pickQueue,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
                decoration: BoxDecoration(
                  color: queue == null ? p.ink : p.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: queue == null ? p.ink : p.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'ЧЕРГА',
                      style: label(queue == null ? p.paper.withValues(alpha: 0.7) : p.muted)
                          .copyWith(fontSize: 10),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      queue == null ? 'обрати' : queueShort(queue),
                      style: display(18,
                          weight: FontWeight.w600,
                          color: queue == null ? p.paper : p.ink),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _content(Palette p, DtekRegion? region) {
    if (region == null) {
      return [
        const SizedBox(height: 120),
        Text('Коли вимкнуть світло', style: display(28, color: p.ink)),
        const SizedBox(height: 12),
        Text(
          'Графіки відключень DTEK для вашої черги. Оберіть регіон, щоб почати.',
          style: body(16, color: p.muted),
        ),
        const SizedBox(height: 24),
        _TextButton(text: 'Обрати регіон', onTap: _pickRegion, filled: true),
      ];
    }

    final result = _result;
    if (result == null) {
      if (_loading || _error == null) {
        return const [
          SizedBox(height: 160),
          Center(child: CupertinoActivityIndicator(radius: 14)),
        ];
      }
      return [
        const SizedBox(height: 80),
        Text('Не вийшло\nзавантажити', style: display(26, color: p.ink)),
        const SizedBox(height: 12),
        Text(_error!, style: body(14, color: p.muted)),
        const SizedBox(height: 24),
        Row(children: [
          _TextButton(text: 'Ще раз', onTap: _load, filled: true),
          const SizedBox(width: 10),
          _TextButton(
            text: 'Сайт DTEK',
            onTap: () => launchUrl(
              Uri.parse(region.shutdownsUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ]),
      ];
    }

    final schedule = result.schedule;
    final queue = schedule.queueNames.containsKey(_queue) ? _queue : null;
    final widgets = <Widget>[];

    if (result.fromCache) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Немає зʼєднання — показано збережений графік.',
          style: body(13.5, color: p.muted),
        ),
      ));
    }

    if (schedule.days.isEmpty) {
      widgets.addAll(_noOutages(p, schedule));
    } else if (queue == null) {
      widgets.addAll(_chooseQueue(p, schedule));
    } else {
      widgets.addAll(_queueView(p, schedule, queue));
    }

    widgets.add(const SizedBox(height: 40));
    widgets.add(Text(
      'Дані: ${schedule.source}'
      '${schedule.updated.isEmpty ? '' : '\nDTEK оновив ${schedule.updated}'}',
      style: body(12, color: p.muted, height: 1.5),
    ));
    return widgets;
  }

  List<Widget> _noOutages(Palette p, RegionSchedule schedule) {
    final day = schedule.today == 0 ? _now - _now % 86400 : schedule.today;
    return [
      const SizedBox(height: 28),
      Center(
        child: DayDial(
          day: DaySchedule(day, List.filled(48, Power.on)),
          now: _now,
          child: _dialCenter(p, 'Світло є', 'відключень не\nзаплановано', null),
        ),
      ),
      const SizedBox(height: 28),
      Text(
        'DTEK зараз не публікує графік відключень для цього регіону. '
        'Якщо він зʼявиться — потягніть екран вниз, щоб оновити.',
        style: body(15, color: p.muted),
      ),
    ];
  }

  List<Widget> _chooseQueue(Palette p, RegionSchedule schedule) {
    return [
      const SizedBox(height: 64),
      Text('Яка у вас\nчерга?', style: display(30, color: p.ink)),
      const SizedBox(height: 12),
      Text(
        'Оберіть її, і застосунок покаже, коли саме вимкнуть світло.',
        style: body(16, color: p.muted),
      ),
      const SizedBox(height: 24),
      Row(children: [
        _TextButton(text: 'Обрати чергу', onTap: _pickQueue, filled: true),
        const SizedBox(width: 10),
        _TextButton(text: 'Усі черги', onTap: _openAllQueues),
      ]),
    ];
  }

  List<Widget> _queueView(Palette p, RegionSchedule schedule, String queue) {
    final intervals = schedule.intervalsFor(queue);
    final status = QueueStatus.compute(intervals, _now);
    final current = status.current;

    // Циферблат показує день, у якому ми зараз; якщо такого немає — перший.
    final dialDayKey = schedule.sortedDays.lastWhere(
      (d) => d <= _now,
      orElse: () => schedule.sortedDays.first,
    );
    final dialDay = schedule.days[dialDayKey]![queue];

    String title;
    String subtitle;
    String? left;
    if (current == null) {
      title = 'Невідомо';
      subtitle = 'графік на зараз\nще не опубліковано';
    } else {
      final ends = current.end;
      final endsText = _isLastSlot(intervals, current) ? 'до кінця графіка' : 'до ${kyivTime(ends)}';
      switch (current.power) {
        case Power.on:
          title = 'Світло є';
        case Power.off:
          title = 'Світла немає';
        case Power.maybe:
          title = 'Можливо';
      }
      subtitle = current.power == Power.off ? 'увімкнуть о ${kyivTime(ends)}' : endsText;
      left = 'ще ${formatDuration(ends - _now)}';
    }

    final widgets = <Widget>[
      const SizedBox(height: 28),
      if (dialDay != null)
        Center(
          child: DayDial(
            day: dialDay,
            now: _now,
            child: _dialCenter(p, title, subtitle, left),
          ),
        ),
      const SizedBox(height: 28),
    ];

    final next = status.nextOff;
    if (current?.power != Power.off) {
      widgets.add(_NextCard(
        title: 'НАСТУПНЕ ВІДКЛЮЧЕННЯ',
        value: next == null ? 'Не заплановано' : '${kyivTime(next.start)} – ${kyivTime(next.end)}',
        note: next == null
            ? 'в опублікованому графіку'
            : '${_dayWord(schedule, next.start)} · ${formatDuration(next.duration)}'
                ' · через ${formatDuration(next.start - _now)}',
      ));
    }

    for (final day in schedule.sortedDays) {
      final sch = schedule.days[day]![queue];
      if (sch == null || day + 86400 <= _now) continue;
      widgets.addAll(_daySection(p, schedule, day, sch, intervals));
    }

    widgets.add(const SizedBox(height: 20));
    widgets.add(Pressable(
      onTap: _openAllQueues,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border.symmetric(horizontal: BorderSide(color: p.line)),
        ),
        child: Row(children: [
          Text('Графік усіх черг', style: body(16, weight: FontWeight.w500, color: p.ink)),
          const Spacer(),
          Icon(CupertinoIcons.chevron_right, size: 16, color: p.muted),
        ]),
      ),
    ));
    return widgets;
  }

  bool _isLastSlot(List<PowerInterval> intervals, PowerInterval iv) =>
      identical(intervals.last, iv);

  String _dayWord(RegionSchedule schedule, int t) {
    final dayStart = schedule.sortedDays.lastWhere((d) => d <= t, orElse: () => t);
    if (dayStart == schedule.today) return 'сьогодні';
    if (dayStart > schedule.today) return 'завтра';
    return kyivShortDate(t);
  }

  Widget _dialCenter(Palette p, String title, String subtitle, String? left) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(title, style: display(24, color: p.ink)),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: body(14.5, color: p.ink, height: 1.3),
        ),
        if (left != null) ...[
          const SizedBox(height: 4),
          Text(left, style: numbers(13, weight: FontWeight.w400, color: p.muted)),
        ],
      ],
    );
  }

  List<Widget> _daySection(
    Palette p,
    RegionSchedule schedule,
    int day,
    DaySchedule sch,
    List<PowerInterval> intervals,
  ) {
    final dayEnd = day + 86400;
    final off = intervals
        .where((iv) => iv.power != Power.on && iv.start < dayEnd && iv.end > day)
        .toList();
    final heading = day == schedule.today
        ? 'Сьогодні'
        : day > schedule.today
            ? 'Завтра'
            : '';

    return [
      const SizedBox(height: 36),
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(heading, style: display(20, color: p.ink)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              kyivDate(day),
              overflow: TextOverflow.ellipsis,
              style: body(14, color: p.muted),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      DayStrip(day: sch, now: _now),
      const SizedBox(height: 14),
      if (off.isEmpty)
        Text('Відключень немає', style: body(15, color: p.muted))
      else ...[
        for (final iv in off)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.line)),
            ),
            child: Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: p.of(iv.power),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${kyivTime(iv.start < day ? day : iv.start)} – '
                '${iv.end >= dayEnd ? '24:00' : kyivTime(iv.end)}',
                style: numbers(16.5,
                    color: iv.end <= _now ? p.muted : p.ink),
              ),
              const Spacer(),
              Text(
                iv.power == Power.maybe
                    ? 'можливо'
                    : formatDuration((iv.end > dayEnd ? dayEnd : iv.end) -
                        (iv.start < day ? day : iv.start)),
                style: numbers(14, weight: FontWeight.w400, color: p.muted),
              ),
            ]),
          ),
        const SizedBox(height: 10),
        Text(
          'Разом без світла: ${formatDuration(sch.offSeconds)}',
          style: body(13.5, color: p.muted),
        ),
      ],
    ];
  }
}

class _NextCard extends StatelessWidget {
  const _NextCard({required this.title, required this.value, required this.note});

  final String title;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: label(p.muted)),
          const SizedBox(height: 10),
          Text(value, style: display(26, weight: FontWeight.w500, color: p.ink)
              .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(height: 6),
          Text(note, style: body(14, color: p.muted)),
        ],
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton({required this.text, required this.onTap, this.filled = false});

  final String text;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: filled ? p.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: filled ? p.ink : p.line),
        ),
        child: Text(
          text,
          style: body(15.5, weight: FontWeight.w500, color: filled ? p.paper : p.ink),
        ),
      ),
    );
  }
}
