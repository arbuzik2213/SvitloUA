import '../address.dart';
import '../regions.dart';
import 'common.dart';
import 'dtek_bridge.dart';
import 'yasno.dart';

/// Один крок пошуку адреси.
class AddressLevel {
  final String title;
  final String placeholder;

  /// Скільки символів треба ввести, перш ніж шукати (0 — показати все одразу).
  final int minQuery;

  /// Будинки — плиткою.
  final bool grid;

  /// Пошуку немає: введений текст і є значенням (Волинь).
  final bool freeText;

  const AddressLevel(
    this.title,
    this.placeholder, {
    this.minQuery = 0,
    this.grid = false,
    this.freeText = false,
  });
}

const cityLevel = AddressLevel('Населений пункт', 'Назва міста чи села');
const streetLevel = AddressLevel('Вулиця', 'Назва вулиці');
const houseLevel = AddressLevel('Будинок', 'Номер будинку', grid: true);

/// Пошук адреси: ланцюжок рівнів, на останньому — черга будинку.
abstract class AddressSource {
  List<AddressLevel> get levels;

  /// Варіанти для рівня [level] з урахуванням уже обраних [chosen].
  Future<List<AddressOption>> options(
      int level, List<AddressOption> chosen, String query);

  /// Черга для повністю обраної адреси.
  Future<String?> queue(List<AddressOption> chosen);

  /// Пошук локальний (весь список уже є) — без затримки на введення.
  bool get isLocal => false;

  /// Підказка під час першого завантаження.
  String? get loadingHint => null;

  /// Черга, записана у варіанті будинку (більшість джерел так і віддають).
  static String? queueOf(AddressOption house) =>
      house.extra['queue'] as String?;
}

/// Будинки «2, 4, 10, 10А» — за числом, потім за рештою.
int compareHouses(String a, String b) {
  int n(String s) =>
      int.tryParse(RegExp(r'\d+').stringMatch(s) ?? '') ?? 1 << 30;
  final c = n(a).compareTo(n(b));
  return c != 0 ? c : a.compareTo(b);
}

/// Будинки, номер яких починається з введеного.
List<AddressOption> filterHouses(Iterable<AddressOption> list, String q) {
  final query = q.trim().toLowerCase();
  return list
      .where((h) => query.isEmpty || h.label.toLowerCase().startsWith(query))
      .toList()
    ..sort((a, b) => compareHouses(a.label, b.label));
}

/// Спершу точний збіг назви («Дніпро» → м. Дніпро, а не Верхньодніпровськ),
/// потім ті, що починаються з запиту, потім решта; міста — вище за села.
List<AddressOption> sortByRelevance(List<AddressOption> list, String query) {
  final q = query.trim().toLowerCase();
  String bare(String s) => s.toLowerCase().replaceFirst(
      RegExp(r'^(м\.|місто|смт\.?|с-ще|селище|с\.|вул\.|вулиця)\s*'), '');
  int rank(AddressOption o) {
    final l = o.label.toLowerCase();
    final name = bare(o.label);
    final kind = l.startsWith('м.') || l.startsWith('місто')
        ? 0
        : l.startsWith('смт')
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

// ---------------------------------------------------------------------------

class YasnoAddressSource extends AddressSource {
  YasnoAddressSource(this.oblast);
  final Oblast oblast;
  final _api = YasnoApi();

  @override
  late final List<AddressLevel> levels = [
    if (oblast.hasCities)
      const AddressLevel('Населений пункт', 'Назва міста чи села',
          minQuery: 2),
    AddressLevel('Вулиця', 'Назва вулиці',
        minQuery: oblast.hasCities ? 0 : 2),
    houseLevel,
  ];

  AddressOption? _city(List<AddressOption> c) =>
      oblast.hasCities ? c.first : null;

  @override
  Future<List<AddressOption>> options(
      int level, List<AddressOption> chosen, String q) async {
    final kind = oblast.hasCities ? level : level + 1;
    switch (kind) {
      case 0:
        return sortByRelevance(await _api.cities(oblast, q.trim()), q);
      case 1:
        return _api.streets(oblast, _city(chosen), q.trim());
      default:
        return filterHouses(
            await _api.houses(oblast, _city(chosen), chosen.last, ''), q);
    }
  }

  @override
  Future<String?> queue(List<AddressOption> c) =>
      _api.queue(oblast, _city(c), c[c.length - 2], c.last);
}

class DtekAddressSource extends AddressSource {
  DtekAddressSource(this.oblast);
  final Oblast oblast;
  Map<String, List<String>>? _streets;
  final _houses = <String, Map<String, Map<String, dynamic>>>{};

  @override
  final levels = const [cityLevel, streetLevel, houseLevel];
  @override
  bool get isLocal => true;
  @override
  String get loadingHint => 'Завантажуємо адреси з сайту DTEK…';

  Future<Map<String, List<String>>> _all() async =>
      _streets ??= await DtekBridge.instance.streets(oblast.dtekUrl!);

  @override
  Future<List<AddressOption>> options(
      int level, List<AddressOption> chosen, String q) async {
    final all = await _all();
    switch (level) {
      case 0:
        final list = [for (final c in all.keys) AddressOption(c, c)];
        return sortByRelevance(filterBy(list, (o) => o.label, q), q)
            .take(80)
            .toList();
      case 1:
        final list = (all[chosen[0].id] ?? const <String>[]).toList();
        // Населений пункт без вулиць: DTEK зберігає порожній рядок.
        if (list.length == 1 && list.first.isEmpty) {
          return const [AddressOption('', 'Без вулиці')];
        }
        list.sort();
        return filterBy([for (final s in list) AddressOption(s, s)],
                (o) => o.label, q)
            .take(150)
            .toList();
      default:
        final key = '${chosen[0].id}|${chosen[1].id}';
        final data = _houses[key] ??= await DtekBridge.instance
            .houses(oblast.dtekUrl!, chosen[0].id, chosen[1].id);
        return filterHouses([
          for (final e in data.entries)
            AddressOption(e.key, e.key == '-' ? 'Усі будинки' : e.key, {
              'queue': ((e.value['sub_type_reason'] as List?) ?? const [])
                  .map((x) => '$x')
                  .firstOrNull,
            }),
        ], q);
    }
  }

  @override
  Future<String?> queue(List<AddressOption> c) async =>
      AddressSource.queueOf(c.last);
}
