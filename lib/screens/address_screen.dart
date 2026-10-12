import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../address.dart';
import '../models.dart';
import '../regions.dart';
import '../sources/address_source.dart';
import '../sources/common.dart';
import '../sources/dtek_bridge.dart';
import '../sources/regional.dart';
import '../theme.dart';
import '../widgets/pressable.dart';
import 'web_page_screen.dart';

/// Результат вибору: область і, якщо треба, адреса / черга.
class AddressResult {
  final Oblast oblast;
  final SavedAddress? address;
  const AddressResult(this.oblast, this.address);
}

Future<AddressResult?> pickAddress(BuildContext context) =>
    Navigator.push<AddressResult>(
      context,
      MaterialPageRoute(builder: (_) => const OblastScreen()),
    );

AddressSource? addressSourceFor(Oblast o) => switch (o.kind) {
      RegionKind.yasno => YasnoAddressSource(o),
      RegionKind.dtek => DtekBridge.supported ? DtekAddressSource(o) : null,
      RegionKind.native => o.addressSearch ? regionalProvider(o.id)?.address : null,
      RegionKind.web => null,
    };

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Align(
      alignment: Alignment.centerLeft,
      child: Pressable(
        onTap: () => Navigator.maybePop(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(CupertinoIcons.back, color: p.ink, size: 22),
            const SizedBox(width: 2),
            Text('Назад', style: body(16, color: p.ink)),
          ]),
        ),
      ),
    );
  }
}

class _Search extends StatelessWidget {
  const _Search({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return CupertinoSearchTextField(
      controller: controller,
      autofocus: autofocus,
      placeholder: placeholder,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: body(16.5, color: p.ink),
      placeholderStyle: body(16.5, color: p.muted),
      backgroundColor: p.surface,
      itemColor: p.muted,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      borderRadius: BorderRadius.circular(12),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, this.subtitle, required this.onTap, this.trailing});

  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: body(16.5, weight: FontWeight.w500, color: p.ink)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: body(13, color: p.muted)),
                ],
              ],
            ),
          ),
          trailing ?? Icon(CupertinoIcons.chevron_right, size: 15, color: p.muted),
        ]),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.over, required this.title, this.subtitle});
  final String over;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (over.isNotEmpty) ...[
          Text(over.toUpperCase(), style: label(p.muted)),
          const SizedBox(height: 6),
        ],
        Text(title, style: display(30, color: p.ink)),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, style: body(15.5, color: p.muted)),
        ],
      ],
    );
  }
}

// ===========================================================================
// Крок 1: область

class OblastScreen extends StatefulWidget {
  const OblastScreen({super.key});

  @override
  State<OblastScreen> createState() => _OblastScreenState();
}

class _OblastScreenState extends State<OblastScreen> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _choose(Oblast o) async {
    SavedAddress? address;
    final source = addressSourceFor(o);
    if (source != null) {
      address = await Navigator.push<SavedAddress>(
        context,
        MaterialPageRoute(builder: (_) => AddressSearchScreen(oblast: o, source: source)),
      );
      if (address == null) return;
    } else if (o.manualQueue) {
      address = await Navigator.push<SavedAddress>(
        context,
        MaterialPageRoute(builder: (_) => QueuePickScreen(oblast: o)),
      );
      if (address == null) return;
    }
    if (mounted) Navigator.pop(context, AddressResult(o, address));
  }

  String _subtitle(Oblast o) {
    if (o.findsByAddress) return '${o.company} · пошук за адресою';
    if (o.manualQueue) return '${o.company} · за номером черги';
    if (o.imageUrl != null) return '${o.company} · графік картинкою';
    return '${o.company} · графік на сайті';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final list = oblasts
        .where((o) => _q.isEmpty || o.name.toLowerCase().contains(_q.toLowerCase()))
        .toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            if (Navigator.canPop(context)) const SliverToBoxAdapter(child: _TopBar()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Heading(
                      over: '',
                      title: 'Де ви живете?',
                      subtitle: 'Оберіть область — далі знайдемо ваш будинок.',
                    ),
                    const SizedBox(height: 20),
                    _Search(
                      controller: _search,
                      placeholder: 'Область',
                      onChanged: (v) => setState(() => _q = v.trim()),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              sliver: SliverList.list(children: [
                for (final o in list)
                  _Row(
                    title: o.title,
                    subtitle: _subtitle(o),
                    trailing: o.needsAddress
                        ? null
                        : Icon(CupertinoIcons.globe, size: 16, color: p.muted),
                    onTap: () => _choose(o),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Крок 2: пошук адреси (рівні задає джерело)

class AddressSearchScreen extends StatefulWidget {
  const AddressSearchScreen({super.key, required this.oblast, required this.source});
  final Oblast oblast;
  final AddressSource source;

  @override
  State<AddressSearchScreen> createState() => _AddressSearchScreenState();
}

class _AddressSearchScreenState extends State<AddressSearchScreen> {
  AddressSource get _source => widget.source;
  final _search = TextEditingController();

  int _level = 0;
  final _chosen = <AddressOption>[];

  List<AddressOption> _results = const [];
  bool _loading = false;
  bool _firstLoad = true;
  String? _error;
  Timer? _debounce;
  int _request = 0;

  AddressLevel get _lv => _source.levels[_level];

  @override
  void initState() {
    super.initState();
    _query('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(
      Duration(milliseconds: _source.isLocal || _lv.freeText ? 0 : 350),
      () => _query(v),
    );
  }

  Future<void> _query(String q) async {
    final id = ++_request;
    if (q.trim().length < _lv.minQuery) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _source.options(_level, _chosen, q);
      if (!mounted || id != _request) return;
      setState(() {
        _results = r;
        _firstLoad = false;
      });
      // Єдиний варіант без назви (село без вулиць) — одразу далі.
      if (r.length == 1 && r.first.id.isEmpty && !_lv.grid) _pick(r.first);
    } catch (e) {
      if (!mounted || id != _request) return;
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && id == _request) setState(() => _loading = false);
    }
  }

  void _goTo(int level) {
    _search.clear();
    setState(() {
      _level = level;
      _chosen.removeRange(level, _chosen.length);
      _results = const [];
    });
    _query('');
  }

  Future<void> _pick(AddressOption o) async {
    if (_level < _source.levels.length - 1) {
      _chosen.add(o);
      _goTo(_level + 1);
      return;
    }
    await _finish([..._chosen, o]);
  }

  Future<void> _finish(List<AddressOption> path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final queue = await _source.queue(path);
      if (!mounted) return;
      if (queue == null) {
        // Обленерго не повернуло черги — обираємо вручну.
        final manual = await Navigator.push<SavedAddress>(
          context,
          MaterialPageRoute(
            builder: (_) => QueuePickScreen(
              oblast: widget.oblast,
              path: path,
              reason: 'Обленерго не повернуло черги для цієї адреси. '
                  'Оберіть її вручну — номер є в офіційному списку адрес.',
            ),
          ),
        );
        if (manual != null && mounted) Navigator.pop(context, manual);
        return;
      }
      final address = SavedAddress(oblastId: widget.oblast.id, path: path, queue: queue);
      await address.save();
      if (mounted) Navigator.pop(context, address);
    } on NotInQueueException catch (e) {
      if (mounted) setState(() => _error = '$e');
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return PopScope(
      canPop: _level == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _level > 0) _goTo(_level - 1);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              const SliverToBoxAdapter(child: _TopBar()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Heading(over: widget.oblast.title, title: _lv.title),
                      if (_chosen.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (var i = 0; i < _chosen.length; i++)
                            if (_chosen[i].label.isNotEmpty && _chosen[i].id.isNotEmpty)
                              _Crumb(text: _chosen[i].label, onTap: () => _goTo(i)),
                        ]),
                      ],
                      const SizedBox(height: 18),
                      _Search(
                        key: ValueKey(_level),
                        controller: _search,
                        placeholder: _lv.placeholder,
                        onChanged: _onChanged,
                        onSubmitted: _lv.freeText ? (v) => _query(v) : null,
                        autofocus: !_source.isLocal || _level > 0,
                      ),
                      const SizedBox(height: 8),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(_error!, style: body(14.5, color: p.ink)),
                        ),
                    ],
                  ),
                ),
              ),
              ..._resultsSliver(p),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _resultsSliver(Palette p) {
    if (_loading && (_results.isEmpty || _lv.grid)) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Column(children: [
              const CupertinoActivityIndicator(radius: 12),
              if (_source.loadingHint != null && _firstLoad) ...[
                const SizedBox(height: 14),
                Text(_source.loadingHint!, style: body(14, color: p.muted)),
              ],
            ]),
          ),
        ),
      ];
    }

    if (_results.isEmpty) {
      final q = _search.text.trim();
      final hint = q.length < _lv.minQuery
          ? (_lv.freeText
              ? 'Введіть назву повністю, без скорочень.'
              : 'Почніть вводити — підкажемо варіанти.')
          : 'Нічого не знайдено.';
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(child: Text(hint, style: body(15, color: p.muted))),
        ),
      ];
    }

    if (_lv.grid) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          sliver: SliverToBoxAdapter(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final h in _results.take(400))
                  Pressable(
                    onTap: () => _pick(h),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 64),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: p.line),
                      ),
                      child: Text(
                        h.label,
                        textAlign: TextAlign.center,
                        style: body(16, weight: FontWeight.w500, color: p.ink),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        sliver: SliverList.builder(
          itemCount: _results.length,
          itemBuilder: (_, i) => _Row(
            title: _lv.freeText ? 'Шукати «${_results[i].label}»' : _results[i].label,
            subtitle: (_results[i].extra['otg'] as String?)?.isNotEmpty == true
                ? '${_results[i].extra['otg']} громада'
                : null,
            onTap: () => _pick(_results[i]),
          ),
        ),
      ),
    ];
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(text, overflow: TextOverflow.ellipsis, style: body(13.5, color: p.ink)),
          ),
          const SizedBox(width: 4),
          Icon(CupertinoIcons.xmark, size: 12, color: p.muted),
        ]),
      ),
    );
  }
}

// ===========================================================================
// Ручний вибір черги (області без пошуку за адресою)

class QueuePickScreen extends StatelessWidget {
  const QueuePickScreen({
    super.key,
    required this.oblast,
    this.path = const [],
    this.reason,
  });

  final Oblast oblast;
  final List<AddressOption> path;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final queues = regionalProvider(oblast.id)?.manualQueues ?? standardQueues;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 40),
          children: [
            const _TopBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Heading(
                    over: oblast.title,
                    title: 'Ваша черга',
                    subtitle: reason ??
                        oblast.note ??
                        '${oblast.company} не має пошуку черги за адресою, '
                            'тож оберіть номер черги самі.',
                  ),
                  if (oblast.queueHelpUrl != null) ...[
                    const SizedBox(height: 14),
                    Pressable(
                      onTap: () => openOfficialPage(context, 'Де дізнатися чергу', oblast.queueHelpUrl!),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Де дізнатися свою чергу',
                            style: body(15.5, weight: FontWeight.w600, color: p.ink)
                                .copyWith(decoration: TextDecoration.underline)),
                        const SizedBox(width: 4),
                        Icon(CupertinoIcons.arrow_up_right, size: 14, color: p.ink),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 22),
                  LayoutBuilder(builder: (context, c) {
                    const cols = 4;
                    const gap = 8.0;
                    final w = (c.maxWidth - gap * (cols - 1)) / cols;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final q in queues)
                          Pressable(
                            onTap: () async {
                              final a = SavedAddress(oblastId: oblast.id, path: path, queue: q);
                              await a.save();
                              if (context.mounted) Navigator.pop(context, a);
                            },
                            child: Container(
                              width: w,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: p.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: p.line),
                              ),
                              child: Text(queueShort(q),
                                  style: display(17, weight: FontWeight.w500, color: p.ink)),
                            ),
                          ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
