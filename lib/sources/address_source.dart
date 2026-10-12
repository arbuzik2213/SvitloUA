import '../address.dart';
import '../regions.dart';
import 'dtek_bridge.dart';
import 'yasno.dart';

/// Пошук адреси: населений пункт → вулиця → будинок → черга.
abstract class AddressSource {
  bool get needsCity;
  Future<List<AddressOption>> cities(String query);
  Future<List<AddressOption>> streets(AddressOption? city, String query);
  Future<List<AddressOption>> houses(
      AddressOption? city, AddressOption street, String query);
  Future<String?> queue(
      AddressOption? city, AddressOption street, AddressOption house);

  /// Пошук іде локально (DTEK віддає весь список одразу) — без затримки на введення.
  bool get isLocal;

  static AddressSource of(Oblast o) => switch (o.kind) {
        SourceKind.yasno => YasnoAddressSource(o),
        SourceKind.dtek => DtekAddressSource(o),
        SourceKind.web =>
          throw UnsupportedError('пошук за адресою недоступний'),
      };
}

class YasnoAddressSource implements AddressSource {
  YasnoAddressSource(this.oblast);
  final Oblast oblast;
  final _api = YasnoApi();

  @override
  bool get needsCity => oblast.hasCities;
  @override
  bool get isLocal => false;

  @override
  Future<List<AddressOption>> cities(String q) async {
    if (q.trim().length < 2) return const [];
    return sortByRelevance(await _api.cities(oblast, q.trim()), q);
  }

  @override
  Future<List<AddressOption>> streets(AddressOption? city, String q) =>
      q.trim().length < 2 && !needsCity
          ? Future.value(const [])
          : _api.streets(oblast, city, q.trim());

  @override
  Future<List<AddressOption>> houses(
          AddressOption? city, AddressOption street, String q) =>
      _api.houses(oblast, city, street, q.trim());

  @override
  Future<String?> queue(
          AddressOption? city, AddressOption street, AddressOption house) =>
      _api.queue(oblast, city, street, house);
}

/// Спершу точний збіг назви («Дніпро» → м. Дніпро, а не Верхньодніпровськ),
/// потім ті, що починаються з запиту, потім решта; міста — вище за села.
List<AddressOption> sortByRelevance(List<AddressOption> list, String query) {
  final q = query.trim().toLowerCase();
  String bare(String s) =>
      s.toLowerCase().replaceFirst(RegExp(r'^(м\.|смт\.?|с-ще|с\.)\s*'), '');
  int rank(AddressOption o) {
    final name = bare(o.label);
    final kind = o.label.startsWith('м.')
        ? 0
        : o.label.startsWith('смт')
            ? 1
            : 2;
    final match = name == q
        ? 0
        : name.startsWith(q)
            ? 1
            : 2;
    return match * 3 + kind;
  }

  return [...list]..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.label.compareTo(b.label);
    });
}

class DtekAddressSource implements AddressSource {
  DtekAddressSource(this.oblast);
  final Oblast oblast;
  Map<String, List<String>>? _streets;
  final _houses = <String, Map<String, Map<String, dynamic>>>{};

  @override
  bool get needsCity => true;
  @override
  bool get isLocal => true;

  Future<Map<String, List<String>>> _all() async =>
      _streets ??= await DtekBridge.instance.streets(oblast.dtekUrl!);

  static bool _matches(String value, String q) =>
      q.isEmpty || value.toLowerCase().contains(q.trim().toLowerCase());

  @override
  Future<List<AddressOption>> cities(String q) async {
    final all = await _all();
    final list = [
      for (final c in all.keys)
        if (_matches(c, q)) AddressOption(c, c),
    ];
    return sortByRelevance(list, q).take(80).toList();
  }

  @override
  Future<List<AddressOption>> streets(AddressOption? city, String q) async {
    final all = await _all();
    final list = (all[city?.id] ?? const <String>[]).toList();
    // Населений пункт без вулиць: DTEK зберігає порожній рядок.
    if (list.length == 1 && list.first.isEmpty) {
      return const [AddressOption('', 'Без вулиці')];
    }
    list.sort();
    return [
      for (final s in list.where((s) => _matches(s, q)).take(150))
        AddressOption(s, s),
    ];
  }

  @override
  Future<List<AddressOption>> houses(
      AddressOption? city, AddressOption street, String q) async {
    final key = '${city?.id}|${street.id}';
    final data = _houses[key] ??=
        await DtekBridge.instance.houses(oblast.dtekUrl!, city!.id, street.id);
    final list = data.keys.toList()..sort(_compareHouses);
    return [
      for (final h in list.where((h) =>
          q.isEmpty || h.toLowerCase().startsWith(q.trim().toLowerCase())))
        AddressOption(h, h == '-' ? 'Усі будинки' : h, {
          'queue': ((data[h]!['sub_type_reason'] as List?) ?? const [])
              .cast<Object>()
              .map((e) => '$e')
              .firstOrNull,
        }),
    ];
  }

  @override
  Future<String?> queue(AddressOption? city, AddressOption street,
          AddressOption house) async =>
      house.extra['queue'] as String?;

  /// 2, 4, 10, 10А — за числом, потім за рештою.
  static int _compareHouses(String a, String b) {
    int n(String s) =>
        int.tryParse(RegExp(r'^\d+').stringMatch(s) ?? '') ?? 1 << 30;
    final c = n(a).compareTo(n(b));
    return c != 0 ? c : a.compareTo(b);
  }
}
