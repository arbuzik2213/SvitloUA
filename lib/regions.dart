/// Регіон, для якого DTEK публікує графіки на своєму сайті.
class DtekRegion {
  final String id;
  final String name;
  final String company;

  /// Сторінка DTEK, де в HTML лежить `DisconSchedule.fact`.
  final String shutdownsUrl;

  /// Дзеркало тих самих даних DTEK (outage-data-ua парсить сайти DTEK).
  /// Використовується, коли сайт закритий антибот-захистом.
  final String? mirrorUrl;

  const DtekRegion({
    required this.id,
    required this.name,
    required this.company,
    required this.shutdownsUrl,
    this.mirrorUrl,
  });
}

const _mirror =
    'https://raw.githubusercontent.com/Baskerville42/outage-data-ua/main/data';

const dtekRegions = <DtekRegion>[
  DtekRegion(
    id: 'kyiv',
    name: 'Київ',
    company: 'ДТЕК Київські електромережі',
    shutdownsUrl: 'https://www.dtek-kem.com.ua/ua/shutdowns',
    mirrorUrl: '$_mirror/kyiv.json',
  ),
  DtekRegion(
    id: 'kyiv-region',
    name: 'Київська область',
    company: 'ДТЕК Київські регіональні електромережі',
    shutdownsUrl: 'https://www.dtek-krem.com.ua/ua/shutdowns',
    mirrorUrl: '$_mirror/kyiv-region.json',
  ),
  DtekRegion(
    id: 'dnipro',
    name: 'Дніпропетровська область',
    company: 'ДТЕК Дніпровські електромережі',
    shutdownsUrl: 'https://www.dtek-dnem.com.ua/ua/shutdowns',
    mirrorUrl: '$_mirror/dnipro.json',
  ),
  DtekRegion(
    id: 'odesa',
    name: 'Одеська область',
    company: 'ДТЕК Одеські електромережі',
    shutdownsUrl: 'https://www.dtek-oem.com.ua/ua/shutdowns',
    mirrorUrl: '$_mirror/odesa.json',
  ),
  DtekRegion(
    id: 'donetsk',
    name: 'Донецька область',
    company: 'ДТЕК Донецькі електромережі',
    shutdownsUrl: 'https://www.dtek-dem.com.ua/ua/shutdowns',
  ),
];

/// Області, де мережами керує не DTEK — там графіки публікує місцеве обленерго.
class OtherOblast {
  final String name;
  final String company;
  final String url;
  const OtherOblast(this.name, this.company, this.url);
}

const otherOblasts = <OtherOblast>[
  OtherOblast('Вінницька', 'Вінницяобленерго', 'https://www.voe.com.ua'),
  OtherOblast('Волинська', 'Волиньобленерго', 'https://energy.volyn.ua'),
  OtherOblast('Житомирська', 'Житомиробленерго', 'https://www.ztoe.com.ua'),
  OtherOblast('Закарпатська', 'Закарпаттяобленерго', 'https://zakarpat.energy'),
  OtherOblast('Запорізька', 'Запоріжжяобленерго', 'https://www.zoe.com.ua'),
  OtherOblast('Івано-Франківська', 'Прикарпаттяобленерго', 'https://www.oe.if.ua'),
  OtherOblast('Кіровоградська', 'Кіровоградобленерго', 'https://kiroe.com.ua'),
  OtherOblast('Львівська', 'Львівобленерго', 'https://poweron.loe.lviv.ua'),
  OtherOblast('Миколаївська', 'Миколаївобленерго', 'https://www.energy.mk.ua'),
  OtherOblast('Полтавська', 'Полтаваобленерго', 'https://www.poe.pl.ua'),
  OtherOblast('Рівненська', 'Рівнеобленерго', 'https://www.roe.vsei.ua'),
  OtherOblast('Сумська', 'Сумиобленерго', 'https://www.soe.com.ua'),
  OtherOblast('Тернопільська', 'Тернопільобленерго', 'https://www.toe.com.ua'),
  OtherOblast('Харківська', 'Харківобленерго', 'https://www.oblenergo.kharkov.ua'),
  OtherOblast('Херсонська', 'Херсонобленерго', 'https://ksoe.com.ua'),
  OtherOblast('Хмельницька', 'Хмельницькобленерго', 'https://www.hoe.com.ua'),
  OtherOblast('Черкаська', 'Черкасиобленерго', 'https://www.cherkasyoblenergo.com'),
  OtherOblast('Чернівецька', 'Чернівціобленерго', 'https://oblenergo.cv.ua'),
  OtherOblast('Чернігівська', 'Чернігівобленерго', 'https://chernigivoblenergo.com.ua'),
];
