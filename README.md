# Світло

Графіки відключень світла DTEK: Київ, Київська, Дніпропетровська, Одеська
та Донецька області. Для інших областей — посилання на сайт обленерго.

Дані беруться з сайтів DTEK (`DisconSchedule.fact`). Якщо сайт закритий
захистом від ботів — з дзеркала тих самих даних
[outage-data-ua](https://github.com/Baskerville42/outage-data-ua).
Без мережі показується останній збережений графік.

## Збірка

GitHub Actions збирає `Svitlo.ipa` для iPhone на кожен пуш у `main` —
файл зʼявляється в Releases.

IPA не підписана: на iPhone її ставлять через Sideloadly або AltStore
з власним Apple ID (безкоштовний акаунт — на 7 днів, потім переставити).

Локально:

```
flutter pub get
flutter run
```

Шрифти Unbounded і Golos Text — SIL Open Font License (`assets/fonts`).
