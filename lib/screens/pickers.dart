import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../regions.dart';
import '../theme.dart';
import '../widgets/pressable.dart';

/// Шторка вибору регіону. Повертає [DtekRegion] або null.
Future<DtekRegion?> showRegionSheet(BuildContext context, {String? selectedId}) {
  return showModalBottomSheet<DtekRegion>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          _RegionList(controller: controller, selectedId: selectedId),
    ),
  );
}

class _RegionList extends StatelessWidget {
  const _RegionList({required this.controller, this.selectedId});

  final ScrollController controller;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Text('Регіон', style: display(24, color: p.ink)),
        const SizedBox(height: 24),
        Text('ГРАФІКИ DTEK', style: label(p.muted)),
        const SizedBox(height: 4),
        for (final r in dtekRegions)
          _Row(
            title: r.name,
            subtitle: r.company,
            selected: r.id == selectedId,
            onTap: () => Navigator.pop(context, r),
          ),
        const SizedBox(height: 32),
        Text('ІНШІ ОБЛАСТІ', style: label(p.muted)),
        const SizedBox(height: 8),
        Text(
          'Тут мережі обслуговує не DTEK. Графік — на сайті місцевого '
          'обленерго, відкриється в браузері.',
          style: body(13.5, color: p.muted),
        ),
        const SizedBox(height: 4),
        for (final o in otherOblasts)
          _Row(
            title: o.name,
            subtitle: o.company,
            trailing: Icon(Icons.north_east, size: 16, color: p.muted),
            onTap: () => launchUrl(
              Uri.parse(o.url),
              mode: LaunchMode.externalApplication,
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.line)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: body(16.5, weight: FontWeight.w500, color: p.ink)),
                const SizedBox(height: 2),
                Text(subtitle, style: body(13, color: p.muted)),
              ],
            ),
          ),
          if (selected)
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: p.light, shape: BoxShape.circle),
            )
          else if (trailing != null)
            trailing!,
        ]),
      ),
    );
  }
}

/// Шторка вибору черги. Повертає ключ (GPV3.1) або null.
Future<String?> showQueueSheet(
  BuildContext context, {
  required Map<String, String> queueNames,
  String? selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final p = context.palette;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ваша черга', style: display(24, color: p.ink)),
              const SizedBox(height: 8),
              Text(
                'Номер черги є на сайті DTEK за адресою або в особистому '
                'кабінеті.',
                style: body(14, color: p.muted),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(builder: (context, c) {
                const cols = 4;
                const gap = 8.0;
                final w = (c.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final key in queueNames.keys)
                      _QueueCell(
                        width: w,
                        text: queueShort(key),
                        selected: key == selected,
                        onTap: () => Navigator.pop(context, key),
                      ),
                  ],
                );
              }),
            ],
          ),
        ),
      );
    },
  );
}

class _QueueCell extends StatelessWidget {
  const _QueueCell({
    required this.width,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: width,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? p.ink : p.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? p.ink : p.line),
        ),
        child: Text(
          text,
          style: display(17, weight: FontWeight.w500, color: selected ? p.paper : p.ink),
        ),
      ),
    );
  }
}
