import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Варіант у пошуку адреси: місто, вулиця або будинок.
class AddressOption {
  final String id;
  final String label;

  /// Додаткові дані джерела: оператор мереж Yasno, черга будинку DTEK тощо.
  final Map<String, dynamic> extra;

  const AddressOption(this.id, this.label, [this.extra = const {}]);

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'extra': extra};

  factory AddressOption.fromJson(Map<String, dynamic> j) => AddressOption(
        '${j['id']}',
        '${j['label']}',
        Map<String, dynamic>.from(j['extra'] as Map? ?? const {}),
      );
}

/// Збережена адреса користувача і визначена для неї черга.
class SavedAddress {
  final String oblastId;
  final AddressOption? city;
  final AddressOption street;
  final AddressOption house;

  /// Ключ черги у форматі DTEK: GPV3.1.
  final String queue;

  const SavedAddress({
    required this.oblastId,
    required this.city,
    required this.street,
    required this.house,
    required this.queue,
  });

  /// "вул. Хрещатик, 1"
  String get line => '${street.label}, ${house.label}';

  /// "м. Бровари" або порожньо.
  String get place => city?.label ?? '';

  Map<String, dynamic> toJson() => {
        'oblastId': oblastId,
        'city': city?.toJson(),
        'street': street.toJson(),
        'house': house.toJson(),
        'queue': queue,
      };

  factory SavedAddress.fromJson(Map<String, dynamic> j) => SavedAddress(
        oblastId: '${j['oblastId']}',
        city: j['city'] == null
            ? null
            : AddressOption.fromJson(
                Map<String, dynamic>.from(j['city'] as Map)),
        street: AddressOption.fromJson(
            Map<String, dynamic>.from(j['street'] as Map)),
        house: AddressOption.fromJson(
            Map<String, dynamic>.from(j['house'] as Map)),
        queue: '${j['queue']}',
      );

  static const _key = 'address_v2';

  static Future<SavedAddress?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_key);
    if (s == null) return null;
    try {
      return SavedAddress.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(toJson()));
  }
}

/// Обрана область без адреси (для областей, де графік — на сайті обленерго).
class SavedOblast {
  static const _key = 'oblast_v2';

  static Future<String?> load() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  static Future<void> save(String id) async =>
      (await SharedPreferences.getInstance()).setString(_key, id);
}
