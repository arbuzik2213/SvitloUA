/// Звідки беремо графік і чергу за адресою.
enum RegionKind {
  /// API Yasno (Київ, Дніпропетровщина).
  yasno,

  /// Сайти DTEK через невидимий браузер.
  dtek,

  /// Власні сервіси обленерго, розібрані в `sources/regional.dart`.
  native,

  /// Лише офіційна сторінка обленерго.
  web,
}

class Oblast {
  final String id;
  final String name;
  final String company;
  final RegionKind kind;

  /// Офіційна сторінка з графіком.
  final String webUrl;

  /// Yasno: регіон і оператори мереж (у Дніпропетровській їх два — DTEK і ЦЕК).
  final int? yasnoRegion;
  final List<int> yasnoDsos;
  final bool hasCities;

  /// Сторінка DTEK з `DisconSchedule`.
  final String? dtekUrl;

  /// Дзеркало даних DTEK, коли сайт недоступний.
  final String? mirrorUrl;

  /// Native: є пошук черги за адресою.
  final bool addressSearch;

  /// Native: є графік по чергах, який застосунок уміє розібрати.
  final bool schedule;

  /// Де офіційно дізнатися чергу, якщо пошуку за адресою немає
  /// (сторінка або PDF зі списком адрес).
  final String? queueHelpUrl;

  /// Графік публікують лише картинкою — показуємо її в застосунку.
  final String? imageUrl;

  /// Пояснення для користувача про особливості області.
  final String? note;

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
    this.addressSearch = true,
    this.schedule = true,
    this.queueHelpUrl,
    this.imageUrl,
    this.note,
  });

  String get title => id == 'kyiv' ? name : '$name область';

  /// Користувач обирає адресу (і черга визначається сама).
  bool get findsByAddress =>
      kind == RegionKind.yasno || kind == RegionKind.dtek || (kind == RegionKind.native && addressSearch);

  /// Користувач обирає чергу вручну (адреса не шукається).
  bool get manualQueue =>
      kind == RegionKind.native && !addressSearch && imageUrl == null;

  /// Застосунок показує графік сам (а не сторінку обленерго).
  bool get nativeSchedule =>
      kind != RegionKind.web && (kind != RegionKind.native || schedule);

  /// Потрібно щось обрати (адресу чи чергу), перш ніж показати графік.
  bool get needsAddress => findsByAddress || manualQueue;
}

const _mirror =
    'https://raw.githubusercontent.com/Baskerville42/outage-data-ua/main/data';

/// Усі області, крім тимчасово окупованих. Київ першим, далі за алфавітом.
const oblasts = <Oblast>[
  Oblast(
    id: 'kyiv',
    name: 'Київ',
    company: 'ДТЕК Київські електромережі',
    kind: RegionKind.yasno,
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
    kind: RegionKind.web,
    webUrl: 'https://www.voe.com.ua/informatsiya-pro-cherhy-hrafika-pohodynnykh-vidklyuchen-hpv-1',
    queueHelpUrl: 'https://www.voe.com.ua/sites/default/files/2026-09/gpv-2026-2027-na-sayt.pdf',
    note: 'Вінницяобленерго не публікує погодинний графік на сайті — лише у '
        'Viber-боті та кабінеті E-Svitlo. Список адрес за чергами — у PDF.',
  ),
  Oblast(
    id: 'volyn',
    name: 'Волинська',
    company: 'Волиньобленерго',
    kind: RegionKind.native,
    webUrl: 'https://energy.volyn.ua/spozhyvacham/perervy-u-elektropostachanni/hrafik-vidkliuchen/',
  ),
  Oblast(
    id: 'dnipro',
    name: 'Дніпропетровська',
    company: 'ДТЕК Дніпровські електромережі / ЦЕК',
    kind: RegionKind.yasno,
    yasnoRegion: 3,
    yasnoDsos: [301, 303],
    mirrorUrl: '$_mirror/dnipro.json',
    webUrl: 'https://www.dtek-dnem.com.ua/ua/shutdowns',
  ),
  Oblast(
    id: 'donetsk',
    name: 'Донецька',
    company: 'ДТЕК Донецькі електромережі',
    kind: RegionKind.dtek,
    dtekUrl: 'https://www.dtek-dem.com.ua/ua/shutdowns',
    webUrl: 'https://www.dtek-dem.com.ua/ua/shutdowns',
  ),
  Oblast(
    id: 'zhytomyr',
    name: 'Житомирська',
    company: 'Житомиробленерго',
    kind: RegionKind.native,
    webUrl: 'https://www.ztoe.com.ua/unhooking-search.php',
  ),
  Oblast(
    id: 'zakarpattia',
    name: 'Закарпатська',
    company: 'Закарпаттяобленерго',
    kind: RegionKind.native,
    addressSearch: false,
    webUrl: 'https://zakarpat.energy/customers/break-in-electricity-supply/updated-information/',
    queueHelpUrl: 'https://zakarpat.energy/customers/break-in-electricity-supply/schedule/',
  ),
  Oblast(
    id: 'zaporizhzhia',
    name: 'Запорізька',
    company: 'Запоріжжяобленерго',
    kind: RegionKind.native,
    addressSearch: false,
    webUrl: 'https://www.zoe.com.ua/outage/',
    queueHelpUrl:
        'https://script.google.com/macros/s/AKfycbwFgBo9W8JL_7FqghJ1hDiE-Fyxzs4GZJAq2xhTseOiv5ZnkusMKj0_g9R0DJKko19r/exec',
  ),
  Oblast(
    id: 'ivano-frankivsk',
    name: 'Івано-Франківська',
    company: 'Прикарпаттяобленерго',
    kind: RegionKind.native,
    addressSearch: false,
    webUrl: 'https://svitlo.oe.if.ua',
    queueHelpUrl: 'https://svitlo.oe.if.ua',
    note: 'Прикарпаттяобленерго визначає чергу за особовим рахунком, а не за адресою.',
  ),
  Oblast(
    id: 'kyiv-region',
    name: 'Київська',
    company: 'ДТЕК Київські регіональні електромережі',
    kind: RegionKind.dtek,
    dtekUrl: 'https://www.dtek-krem.com.ua/ua/shutdowns',
    mirrorUrl: '$_mirror/kyiv-region.json',
    webUrl: 'https://www.dtek-krem.com.ua/ua/shutdowns',
  ),
  Oblast(
    id: 'kirovohrad',
    name: 'Кіровоградська',
    company: 'Кіровоградобленерго',
    kind: RegionKind.web,
    webUrl: 'https://kiroe.com.ua/warning',
    note: 'Кіровоградобленерго зараз не публікує графік і черги на сайті.',
  ),
  Oblast(
    id: 'lviv',
    name: 'Львівська',
    company: 'Львівобленерго',
    kind: RegionKind.native,
    webUrl: 'https://poweron.loe.lviv.ua',
  ),
  Oblast(
    id: 'mykolaiv',
    name: 'Миколаївська',
    company: 'Миколаївобленерго',
    kind: RegionKind.native,
    webUrl: 'https://off.energy.mk.ua',
  ),
  Oblast(
    id: 'odesa',
    name: 'Одеська',
    company: 'ДТЕК Одеські електромережі',
    kind: RegionKind.dtek,
    dtekUrl: 'https://www.dtek-oem.com.ua/ua/shutdowns',
    mirrorUrl: '$_mirror/odesa.json',
    webUrl: 'https://www.dtek-oem.com.ua/ua/shutdowns',
  ),
  Oblast(
    id: 'poltava',
    name: 'Полтавська',
    company: 'Полтаваобленерго',
    kind: RegionKind.native,
    addressSearch: false,
    webUrl: 'https://www.poe.pl.ua/',
    queueHelpUrl: 'https://www.poe.pl.ua/wp-content/uploads/2026/10/HPV_26_27-sajt-8.10.2026.pdf',
  ),
  Oblast(
    id: 'rivne',
    name: 'Рівненська',
    company: 'Рівнеобленерго',
    kind: RegionKind.native,
    addressSearch: false,
    webUrl: 'https://www.roe.vsei.ua/disconnections',
    queueHelpUrl: 'https://www.roe.vsei.ua/disconnections',
  ),
  Oblast(
    id: 'sumy',
    name: 'Сумська',
    company: 'Сумиобленерго',
    kind: RegionKind.native,
    webUrl: 'https://www.soe.com.ua/consumers/shutdowns?tab=hourly-schedules',
    queueHelpUrl: 'https://www.soe.com.ua/consumers/shutdowns?tab=outage-queue',
  ),
  Oblast(
    id: 'ternopil',
    name: 'Тернопільська',
    company: 'Тернопільобленерго',
    kind: RegionKind.native,
    webUrl: 'https://poweron.toe.com.ua',
  ),
  Oblast(
    id: 'kharkiv',
    name: 'Харківська',
    company: 'Харківобленерго',
    kind: RegionKind.native,
    addressSearch: false,
    webUrl: 'https://oblenergo.kharkiv.ua/uk',
    queueHelpUrl:
        'https://oblenergo.kharkiv.ua/sites/default/files/pdf/%D0%90%D0%B4%D1%80%D0%B5%D1%81%D0%B8%20%D1%82%D0%B0%20%D1%87%D0%B5%D1%80%D0%B3%D0%B8%2026-27.pdf',
  ),
  Oblast(
    id: 'kherson',
    name: 'Херсонська',
    company: 'Херсонобленерго',
    kind: RegionKind.web,
    webUrl: 'https://ksoe.com.ua/messages/',
    note: 'Херсонобленерго зараз не застосовує й не публікує погодинні графіки.',
  ),
  Oblast(
    id: 'khmelnytskyi',
    name: 'Хмельницька',
    company: 'Хмельницькобленерго',
    kind: RegionKind.native,
    schedule: false,
    webUrl: 'https://hoe.com.ua/shutdown/new',
    note: 'Хмельницькобленерго не публікує погодинний графік на сайті. '
        'Застосунок показує вашу чергу і поточні відключення за адресою.',
  ),
  Oblast(
    id: 'cherkasy',
    name: 'Черкаська',
    company: 'Черкасиобленерго',
    kind: RegionKind.native,
    webUrl: 'https://www.cherkasyoblenergo.com/vidkliuchennia?lang=uk',
  ),
  Oblast(
    id: 'chernivtsi',
    name: 'Чернівецька',
    company: 'Чернівціобленерго',
    kind: RegionKind.native,
    webUrl: 'https://oblenergo.cv.ua/shutdowns/',
  ),
  Oblast(
    id: 'chernihiv',
    name: 'Чернігівська',
    company: 'Чернігівобленерго',
    kind: RegionKind.native,
    addressSearch: false,
    schedule: false,
    webUrl: 'https://chernihivoblenergo.com.ua/blackouts',
    imageUrl: 'https://chernihivoblenergo.com.ua/files/other/schedule_groups.jpg',
    note: 'Чернігівобленерго публікує години ГПВ картинкою, а чергу визначає '
        'за особовим рахунком чи ЕІС-кодом.',
  ),
];

Oblast? oblastById(String? id) => oblasts.where((o) => o.id == id).firstOrNull;
