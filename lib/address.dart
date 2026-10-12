import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Варіант у пошуку адреси: район, місто, вулиця або будинок.
class AddressOption {
  final String id;
  final String label;

  /// Додаткові дані джерела: оператор Yasno, черга будинку тощо.
  final Map<String, dynamic> extra;

  const AddressOption(this.id, this.label, [this.extra = const {}]);

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'extra': extra};

  factory AddressOption.fromJson(Map<String, dynamic> j) => AddressOption(
        '${j['id']}',
        '${j['label']}',
        Map<String, dynamic>.from(j['extra'] as Map? ?? const {}),
      );
}

/// Збережена адреса: ланцюжок вибору (останній — будинок) і черга.
/// Для областей без пошуку за адресою ланцюжок порожній, є лише черга.
class SavedAddress {
  final String oblastId;
  final List<AddressOption> path;

  /// Ключ черги: GPV3.1 (або GPV7 для груп Чернівців).
  final String queue;

  const SavedAddress({
    required this.oblastId,
    required this.path,
    required this.queue,
  });

  bool get hasAddress => path.isNotEmpty;

  AddressOption? get house => path.isEmpty ? null : path.last;
  AddressOption? get street => path.length < 2 ? null : path[path.length - 2];

  /// "вул. Хрещатик, 1"
  String get line {
    if (path.isEmpty) return '';
    if (path.length == 1) return path.first.label;
    final s = path[path.length - 2].label;
    final h = path.last.label;
    return s.isEmpty || s == 'Без вулиці' ? h : '$s, $h';
  }

  /// Населений пункт — рівень перед вулицею (у Києві його немає).
  String get place => path.length >= 3 ? path[path.length - 3].label : '';

  Map<String, dynamic> toJson() => {
        'oblastId': oblastId,
        'path': [for (final o in path) o.toJson()],
        'queue': queue,
      };

  factory SavedAddress.fromJson(Map<String, dynamic> j) => SavedAddress(
        oblastId: '${j['oblastId']}',
        path: [
          for (final o in (j['path'] as List? ?? const []))
            AddressOption.fromJson(Map<String, dynamic>.from(o as Map)),
        ],
        queue: '${j['queue']}',
      );

  static const _key = 'address_v3';

  static Future<SavedAddress?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_key);
    if (s == null) return _migrate(prefs);
    try {
      return SavedAddress.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Адреса з версії 1.1 (city/street/house окремими полями).
  static SavedAddress? _migrate(SharedPreferences prefs) {
    final s = prefs.getString('address_v2');
    if (s == null) return null;
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      AddressOption opt(dynamic o) => AddressOption.fromJson(Map<String, dynamic>.from(o as Map));
      return SavedAddress(
        oblastId: '${j['oblastId']}',
        path: [
          if (j['city'] != null) opt(j['city']),
          opt(j['street']),
          opt(j['house']),
        ],
        queue: '${j['queue']}',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(toJson()));
  }

  static Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}

/// Обрана область (навіть без адреси — для областей лише з офіційною сторінкою).
class SavedOblast {
  static const _key = 'oblast_v2';

  static Future<String?> load() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  static Future<void> save(String id) async =>
      (await SharedPreferences.getInstance()).setString(_key, id);
}
