import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../address.dart';
import '../regions.dart';
import '../sources/address_source.dart';
import '../theme.dart';
import '../widgets/pressable.dart';

/// Результат вибору: область і, якщо вона підтримує пошук, адреса.
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.backLabel});
  final String backLabel;

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
            Text(backLabel, style: body(16, color: p.ink)),
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
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return CupertinoSearchTextField(
      controller: controller,
      autofocus: autofocus,
      placeholder: placeholder,
      onChanged: onChanged,
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
  const _Row(
      {required this.title, this.subtitle, required this.onTap, this.trailing});

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
        decoration:
            BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: body(16.5, weight: FontWeight.w500, color: p.ink)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: body(13, color: p.muted)),
                ],
              ],
            ),
          ),
          trailing ??
              Icon(CupertinoIcons.chevron_right, size: 15, color: p.muted),
        ]),
      ),
    );
  }
}

/// Крок 1: область.
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
    if (!o.supportsAddress) {
      Navigator.pop(context, AddressResult(o, null));
      return;
    }
    final address = await Navigator.push<SavedAddress>(
      context,
      MaterialPageRoute(builder: (_) => AddressSearchScreen(oblast: o)),
    );
    if (address != null && mounted) {
      Navigator.pop(context, AddressResult(o, address));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final list = oblasts
        .where((o) =>
            _q.isEmpty || o.name.toLowerCase().contains(_q.toLowerCase()))
        .toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            if (Navigator.canPop(context))
              const SliverToBoxAdapter(child: _TopBar(backLabel: 'Назад')),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Де ви живете?', style: display(30, color: p.ink)),
                    const SizedBox(height: 8),
                    Text('Оберіть область — далі знайдемо ваш будинок.',
                        style: body(15.5, color: p.muted)),
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
                    title: o.id == 'kyiv' ? o.name : '${o.name} область',
                    subtitle: o.supportsAddress
                        ? o.company
                        : '${o.company} · графік на сайті',
                    trailing: o.supportsAddress
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

enum _Step { city, street, house }

/// Крок 2: населений пункт → вулиця → будинок.
class AddressSearchScreen extends StatefulWidget {
  const AddressSearchScreen({super.key, required this.oblast});
  final Oblast oblast;

  @override
  State<AddressSearchScreen> createState() => _AddressSearchScreenState();
}

class _AddressSearchScreenState extends State<AddressSearchScreen> {
  late final AddressSource _source = AddressSource.of(widget.oblast);
  final _search = TextEditingController();

  late _Step _step = _source.needsCity ? _Step.city : _Step.street;
  AddressOption? _city;
  AddressOption? _street;

  List<AddressOption> _results = const [];
  bool _loading = false;
  bool _firstLoad = true;
  String? _error;
  Timer? _debounce;
  int _request = 0;

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
      Duration(milliseconds: _source.isLocal ? 0 : 350),
      () => _query(v),
    );
  }

  Future<void> _query(String q) async {
    final id = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = switch (_step) {
        _Step.city => await _source.cities(q),
        _Step.street => await _source.streets(_city, q),
        _Step.house => await _source.houses(_city, _street!, q),
      };
      if (!mounted || id != _request) return;
      setState(() {
        _results = r;
        _firstLoad = false;
      });
      // Вулиця одна і без назви (село) — одразу далі.
      if (_step == _Step.street && r.length == 1 && r.first.id.isEmpty) {
        _pick(r.first);
      }
    } catch (e) {
      if (!mounted || id != _request) return;
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && id == _request) setState(() => _loading = false);
    }
  }

  void _goTo(_Step step) {
    _search.clear();
    setState(() {
      _step = step;
      _results = const [];
      if (step == _Step.city) {
        _city = null;
        _street = null;
      }
      if (step == _Step.street) _street = null;
    });
    _query('');
  }

  Future<void> _pick(AddressOption o) async {
    switch (_step) {
      case _Step.city:
        _city = o;
        _goTo(_Step.street);
      case _Step.street:
        _street = o;
        _goTo(_Step.house);
      case _Step.house:
        await _finish(o);
    }
  }

  Future<void> _finish(AddressOption house) async {
    setState(() => _loading = true);
    try {
      final queue = await _source.queue(_city, _street!, house);
      if (!mounted) return;
      if (queue == null) {
        setState(() => _error =
            'Для цього будинку черга не знайдена. Спробуйте сусідній номер.');
        return;
      }
      final address = SavedAddress(
        oblastId: widget.oblast.id,
        city: _city,
        street: _street!,
        house: house,
        queue: queue,
      );
      await address.save();
      if (mounted) Navigator.pop(context, address);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _onBack() {
    if (_step == _Step.house) {
      _goTo(_Step.street);
      return false;
    }
    if (_step == _Step.street && _source.needsCity) {
      _goTo(_Step.city);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (title, placeholder) = switch (_step) {
      _Step.city => ('Населений пункт', 'Назва міста чи села'),
      _Step.street => ('Вулиця', 'Назва вулиці'),
      _Step.house => ('Будинок', 'Номер будинку'),
    };

    return PopScope(
      canPop: _step == (_source.needsCity ? _Step.city : _Step.street),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              const SliverToBoxAdapter(child: _TopBar(backLabel: 'Назад')),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.oblast.id == 'kyiv'
                            ? widget.oblast.name.toUpperCase()
                            : '${widget.oblast.name} область'.toUpperCase(),
                        style: label(p.muted),
                      ),
                      const SizedBox(height: 6),
                      Text(title, style: display(30, color: p.ink)),
                      if (_city != null || _street != null) ...[
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          if (_city != null)
                            _Crumb(
                                text: _city!.label,
                                onTap: () => _goTo(_Step.city)),
                          if (_street != null && _street!.id.isNotEmpty)
                            _Crumb(
                                text: _street!.label,
                                onTap: () => _goTo(_Step.street)),
                        ]),
                      ],
                      const SizedBox(height: 18),
                      _Search(
                        key: ValueKey(_step),
                        controller: _search,
                        placeholder: placeholder,
                        onChanged: _onChanged,
                        autofocus: !_source.isLocal || _step != _Step.city,
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
    if (_loading && (_results.isEmpty || _step == _Step.house)) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Column(children: [
              const CupertinoActivityIndicator(radius: 12),
              if (_source.isLocal && _firstLoad) ...[
                const SizedBox(height: 14),
                Text('Завантажуємо адреси з сайту DTEK…',
                    style: body(14, color: p.muted)),
              ],
            ]),
          ),
        ),
      ];
    }

    if (_results.isEmpty) {
      final q = _search.text.trim();
      final hint = !_source.isLocal && q.length < 2 && _step != _Step.house
          ? 'Почніть вводити — підкажемо варіанти.'
          : 'Нічого не знайдено.';
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(
              child: Text(hint, style: body(15, color: p.muted))),
        ),
      ];
    }

    if (_step == _Step.house) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          sliver: SliverToBoxAdapter(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final h in _results)
                  Pressable(
                    onTap: () => _pick(h),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 64),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
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
            title: _results[i].label,
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
            child: Text(text,
                overflow: TextOverflow.ellipsis,
                style: body(13.5, color: p.ink)),
          ),
          const SizedBox(width: 4),
          Icon(CupertinoIcons.xmark, size: 12, color: p.muted),
        ]),
      ),
    );
  }
}
