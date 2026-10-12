/// Звідки беремо графік і чергу за адресою.
enum SourceKind {
  /// API Yasno: пошук адреси і графік без захисту від ботів.
  yasno,

  /// Сайт DTEK: працюємо через невидимий браузер, бо сайти закриті Incapsula.
  dtek,

  /// Своє обленерго: показуємо його офіційну сторінку в застосунку.
  web,
}

class Oblast {
  final String id;
  final String name;
  final String company;
  final SourceKind kind;

  /// Yasno: регіон і оператори мереж (у Дніпропетровській їх два — DTEK і ЦЕК).
  final int? yasnoRegion;
  final List<int> yasnoDsos;

  /// Yasno: чи треба спершу обрати населений пункт (Київ — ні).
  final bool hasCities;

  /// Сторінка DTEK з `DisconSchedule` (для [SourceKind.dtek]).
  final String? dtekUrl;

  /// Дзеркало даних DTEK, коли сайт недоступний.
  final String? mirrorUrl;

  /// Офіційна сторінка з графіком / пошуком за адресою.
  final String webUrl;

  const Oblast({
    required this.id,
    required this.name,
    required this.company,
    required this.kind,
    required this.webUrl,
    this.yasnoRegion,
    this.yasnoDsos = const [],
    this.hasCities = true,
    this.dtekUrl,
    this.mirrorUrl,
  });

  bool get supportsAddress => kind != SourceKind.web;
}

const _mirror =
    'https://raw.githubusercontent.com/Baskerville42/outage-data-ua/main/data';

/// Усі області, крім тимчасово окупованих. Порядок — за алфавітом,
/// Київ першим.
const oblasts = <Oblast>[
  Oblast(
    id: 'kyiv',
    name: 'Київ',
    company: 'ДТЕК Київські електромережі',
    kind: SourceKind.yasno,
    yasnoRegion: 25,
    yasnoDsos: [902],
    hasCities: false,
    mirrorUrl: '$_mirror/kyiv.json',
    webUrl: 'https://www.dtek-kem.com.ua/ua/shutdowns',
  ),
  Oblast(
    id: 'vinnytsia',
    name: 'Вінницька',
    company: 'Вінницяобленерго',
    kind: SourceKind.web,
    webUrl:
        'https://www.voe.com.ua/informatsiya-pro-cherhy-hrafika-pohodynnykh-vidklyuchen-hpv-1',
  ),
  Oblast(
    id: 'volyn',
    name: 'Волинська',
    company: 'Волиньобленерго',
    kind: SourceKind.web,
    webUrl: 'https://energy.volyn.ua',
  ),
  Oblast(
    id: 'dnipro',
    name: 'Дніпропетровська',
    company: 'ДТЕК Дніпровські електромережі / ЦЕК',
    kind: SourceKind.yasno,
    yasnoRegion: 3,
    yasnoDsos: [301, 303],
    mirrorUrl: '$_mirror/dnipro.json',
    webUrl: 'https://www.dtek-dnem.com.ua/ua/shutdowns',
  ),
  Oblast(
    id: 'donetsk',
    name: 'Донецька',
    company: 'ДТЕК Донецькі електромережі',
    kind: SourceKind.dtek,
    dtekUrl: 'https://www.dtek-dem.com.ua/ua/shutdowns',
    webUrl: 'https://www.dtek-dem.com.ua/ua/shutdowns',
  ),
  Oblast(
    id: 'zhytomyr',
    name: 'Житомирська',
    company: 'Житомиробленерго',
    kind: SourceKind.web,
    webUrl: 'https://www.ztoe.com.ua',
  ),
  Oblast(
    id: 'zakarpattia',
    name: 'Закарпатська',
    company: 'Закарпаттяобленерго',
    kind: SourceKind.web,
    webUrl: 'https://zakarpat.energy',
  ),
  Oblast(
    id: 'zaporizhzhia',
    name: 'Запорізька',
    company: 'Запоріжжяобленерго',
    kind: SourceKind.web,
    webUrl: 'https://www.zoe.com.ua',
  ),
  Oblast(
    id: 'ivano-frankivsk',
    name: 'Івано-Франківська',
    company: 'Прикарпаттяобленерго',
    kind: SourceKind.web,
    webUrl: 'https://svitlo.oe.if.ua',
  ),
  Oblast(
    id: 'kyiv-region',
    name: 'Київська',
    company: 'ДТЕК Київські регіональні електромережі',
    kind: SourceKind.dtek,
    dtekUrl: 'https://www.dtek-krem.com.ua/ua/shutdowns',
    mirrorUrl: '$_mirror/kyiv-region.json',
    webUrl: 'https://www.dtek-krem.com.ua/ua/shutdowns',
  ),
  Oblast(
    id: 'kirovohrad',
    name: 'Кіровоградська',
    company: 'Кіровоградобленерго',
    kind: SourceKind.web,
    webUrl: 'https://kiroe.com.ua/energy',
  ),
  Oblast(
    id: 'lviv',
    name: 'Львівська',
    company: 'Львівобленерго',
    kind: SourceKind.web,
    webUrl: 'https://poweron.loe.lviv.ua',
  ),
  Oblast(
    id: 'mykolaiv',
    name: 'Миколаївська',
    company: 'Миколаївобленерго',
    kind: SourceKind.web,
    webUrl: 'https://off.energy.mk.ua',
  ),
  Oblast(
    id: 'odesa',
    name: 'Одеська',
    company: 'ДТЕК Одеські електромережі',
    kind: SourceKind.dtek,
    dtekUrl: 'https://www.dtek-oem.com.ua/ua/shutdowns',
    mirrorUrl: '$_mirror/odesa.json',
    webUrl: 'https://www.dtek-oem.com.ua/ua/shutdowns',
  ),
  Oblast(
    id: 'poltava',
    name: 'Полтавська',
    company: 'Полтаваобленерго',
    kind: SourceKind.web,
    webUrl:
        'https://www.poe.pl.ua/disconnection/hrafik-pohodynnoho-vidkliuchennia-elektroenerhii/',
  ),
  Oblast(
    id: 'rivne',
    name: 'Рівненська',
    company: 'Рівнеобленерго',
    kind: SourceKind.web,
    webUrl: 'https://www.roe.vsei.ua/disconnections',
  ),
  Oblast(
    id: 'sumy',
    name: 'Сумська',
    company: 'Сумиобленерго',
    kind: SourceKind.web,
    webUrl: 'https://www.soe.com.ua',
  ),
  Oblast(
    id: 'ternopil',
    name: 'Тернопільська',
    company: 'Тернопільобленерго',
    kind: SourceKind.web,
    webUrl: 'https://www.toe.com.ua',
  ),
  Oblast(
    id: 'kharkiv',
    name: 'Харківська',
    company: 'Харківобленерго',
    kind: SourceKind.web,
    webUrl: 'https://www.oblenergo.kharkov.ua',
  ),
  Oblast(
    id: 'kherson',
    name: 'Херсонська',
    company: 'Херсонобленерго',
    kind: SourceKind.web,
    webUrl: 'https://ksoe.com.ua/disconnection/search/',
  ),
  Oblast(
    id: 'khmelnytskyi',
    name: 'Хмельницька',
    company: 'Хмельницькобленерго',
    kind: SourceKind.web,
    webUrl: 'https://www.hoe.com.ua/page/vidkljuchennja',
  ),
  Oblast(
    id: 'cherkasy',
    name: 'Черкаська',
    company: 'Черкасиобленерго',
    kind: SourceKind.web,
    webUrl: 'https://www.cherkasyoblenergo.com/vidkliuchennia?lang=uk',
  ),
  Oblast(
    id: 'chernivtsi',
    name: 'Чернівецька',
    company: 'Чернівціобленерго',
    kind: SourceKind.web,
    webUrl: 'https://oblenergo.cv.ua/shutdowns/',
  ),
  Oblast(
    id: 'chernihiv',
    name: 'Чернігівська',
    company: 'Чернігівобленерго',
    kind: SourceKind.web,
    webUrl: 'https://chernigivoblenergo.com.ua',
  ),
];

Oblast? oblastById(String? id) => oblasts.where((o) => o.id == id).firstOrNull;
