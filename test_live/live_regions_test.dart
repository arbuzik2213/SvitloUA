// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svitlo_ua/address.dart';
import 'package:svitlo_ua/models.dart';
import 'package:svitlo_ua/sources/regional.dart';

/// Проходить рівні, на кожному обирає варіант, що містить підказку (або перший).
Future<SavedAddress?> walk(String id, List<String> picks) async {
  final src = regionalProvider(id)!.address!;
  final chosen = <AddressOption>[];
  for (var i = 0; i < src.levels.length; i++) {
    final lv = src.levels[i];
    final hint = picks[i];
    final q = lv.minQuery > 0 || lv.freeText ? hint : '';
    final opts = await src.options(i, chosen, q);
    if (opts.isEmpty) {
      print('  [$id] level ${lv.title}: НЕМАЄ варіантів для "$q"');
      return null;
    }
    final pick = opts.firstWhere(
        (o) => o.label.toLowerCase().contains(hint.toLowerCase()),
        orElse: () => opts.first);
    print('  [$id] ${lv.title}: ${opts.length} → ${pick.label}');
    chosen.add(pick);
  }
  try {
    final q = await src.queue(chosen);
    print('  [$id] ЧЕРГА: $q');
    return q == null ? null : SavedAddress(oblastId: id, path: chosen, queue: q);
  } on NotInQueueException {
    print('  [$id] ЧЕРГА: не входить до ГПВ');
    return SavedAddress(oblastId: id, path: chosen, queue: 'GPV1.1');
  }
}

Future<void> sched(String id, SavedAddress a) async {
  final p = regionalProvider(id)!;
  final s = await p.schedule(a);
  print('  [$id] ГРАФІК: днів=${s.days.length} черг=${s.queueNames.length} джерело=${s.source}');
  for (final d in s.sortedDays) {
    final q = s.days[d]!.containsKey(a.queue) ? a.queue : s.days[d]!.keys.first;
    final off = s.intervalsFor(q).where((i) => i.power != Power.on && i.start >= d && i.start < d + 86400);
    print('     ${kyivDate(d)} ${queueShort(q)}: ${off.map((i) => '${kyivTime(i.start)}-${kyivTime(i.end)}').join(', ')}');
  }
  final n = await p.notice(a);
  if (n != null) print('  [$id] ПОВІДОМЛЕННЯ: ${n.replaceAll('\n', ' / ')}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
  });

  const t = Timeout(Duration(minutes: 3));
  final addr = {
    'mykolaiv': ['Миколаївський', 'Миколаїв', 'Велика Морська', '1'],
    'cherkasy': ['Черкаські міські', 'Черкаси', 'Шевченка', '4'],
    'ternopil': ['Тернопіль', 'Руська', '1'],
    'lviv': ['Львів', 'Шевченка Т', '1'],
    'zhytomyr': ['Житомирський', 'місто Житомир', 'Київська', '59'],
    'chernivtsi': ['ЧЕРНІВЦІ', 'Чернівці', 'ЄВДОКІМЕНКА', '1'],
    'volyn': ['Луцьк', 'Шевченка', '1'],
    'sumy': ['Суми', 'Харківська', '1'],
    'khmelnytskyi': ['Хмельницький', 'Проскурівська', '2'],
  };
  for (final e in addr.entries) {
    test(e.key, () async {
      final a = await walk(e.key, e.value);
      if (a != null && e.key != 'khmelnytskyi') await sched(e.key, a);
      if (a != null && e.key == 'khmelnytskyi') await sched(e.key, a).catchError((_) {});
    }, timeout: t);
  }
  for (final id in ['kharkiv', 'poltava', 'rivne', 'ivano-frankivsk', 'zaporizhzhia', 'zakarpattia']) {
    test(id, () => sched(id, SavedAddress(oblastId: id, path: const [], queue: 'GPV3.1')), timeout: t);
  }
}
