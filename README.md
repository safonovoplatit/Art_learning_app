# App for learning arts

Native art gallery app for IOS 26 and higher. Allows you to read about artworks in real time. Based on open API of Cleveland museum of art 

Build and Run
1. Open ArtGallery.xcodeproj from the source directory. This standalone project contains the app and test targets.
2. Select the ArtGallery scheme and an iPhone simulator, then click Run. The app fetches artwork and images from the museum API and reuses cached images when available.
3. For a physical iPhone, select your team under Signing & Capabilities, set a bundle identifier you control, and run on the device.
4. For TestFlight, use an Apple Developer Program account to create an App Store Connect record with the same team and bundle identifier. In Xcode, choose Product → Archive → Distribute App.
The shared scheme includes Release. To verify compilation without signing, run:
```sh
xcodebuild -project ArtGallery.xcodeproj -scheme ArtGallery \
  -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```


Museum Collections
The gallery defaults to Cleveland Museum of Art Open Access and serves CC0 images from its CDN. To enable Harvard Art Museums in the Museum menu, add HARVARD_API_KEY = your-key to Config/HarvardKey.local.xcconfig, which Git ignores. The key is embedded in the built app’s Info.plist, so public distribution requires a server-side proxy to protect it. Cleveland Open Access API

Harvard metadata expires after two weeks and is purged when the gallery restores. Harvard images stay off disk. Cards show the museum link, credit line, and image rights. Rights are checked on API responses, and cached records retain their last known status until refreshed. If Harvard’s image server returns HTTP 403, users can switch to Cleveland. Harvard API documentation
Architecture and Storage
- Domain defines Artwork, the versioned translation model, and source and repository protocols.
- Data contains ClevelandAPI, HarvardAPI, separate DTOs, HTML-to-text conversion via system libxml2, the SwiftData repository, ImagePipeline, and TranslationService. Adding a museum requires a MuseumAPIProvider adapter and a MuseumSource identifier.
- Features contains the gallery model, pager, artwork card, favorites, and full-screen viewer. MyApp wires dependencies. There are no external packages.
SwiftData keeps original cards, translations, feed order, cursors, last positions, viewing history, and favorites on-device, with separate pages and positions per museum. At launch, the gallery shuffles saved artwork and opens the first card. New pages are shuffled before appending, and each page and cursor are committed together.

Decoded images use a 48 MB NSCache cleared on memory warnings. Disk caches allow 300 MB for regular images and 100 MB for favorites, evicting the least recently used files first while retaining metadata. Cache-Control: no-store images stay in memory only while displayed. Harvard IIIF variants are 600 or 843 px wide for cards and up to 1800 px for zoom. Downloads and decoding run off the main actor, and concurrent requests for the same URL are coalesced.
Translation and Navigation
GalleryTranslation uses a view-bound Apple Translation session for English → Russian. Installed language packs are used automatically. Users can download a pack from the navigation bar via a system prompt. Original text stays visible while translation is pending or the language pair is unsupported.

Translation runs sequentially, prioritizing the current, next, and previous cards. Cache entries track the artwork ID, source fields, language pair, and translation version. Changes to the source text or version invalidate the result. A dictionary preserves preferred spellings for common artist names.

ArtworkPager uses a horizontal ScrollView and LazyHStack with native one-card snapping. It saves the artwork ID after scrolling settles. Arrow buttons and VoiceOver actions also support navigation.
Tests and Acceptance
Run Product → Test on an iPhone simulator. Unit tests cover decoding, HTML conversion, filtering, gesture thresholds, deduplication, position restoration, and translation caching. UI tests use local fixtures with stubbed museum API and image loading.

Use a physical iPhone to verify Apple Translation packs and translation quality. Measure FPS, cold start, memory, and leaks in Instruments, including a 100-card navigation run.
Install a Prebuilt App
On an Apple Silicon Mac, unzip Artifacts/ArtGallery-Simulator-arm64.zip, boot an iPhone simulator, and run these commands from the extracted directory:

## Музейные коллекции

По умолчанию лента открывает Cleveland Museum of Art Open Access. Меню «Музей» позволяет переключиться на Harvard Art Museums при наличии ключа. Кливленд отображает свои работы и изображения CC0 из музейного CDN. [Cleveland Museum of Art Open Access](https://www.clevelandart.org/open-access-api). Для локальной сборки добавьте `HARVARD_API_KEY = ваш-ключ` в `Config/HarvardKey.local.xcconfig`. Файл исключён из Git. Значение попадает в Info.plist собранного приложения, поэтому для публичного распространения нужен серверный посредник для защиты ключа. Сборка без ключа открывает Кливленд.

Репозиторий хранит отдельные позиции и страницы для каждого музея. Harvard API разрешает хранить возвращённый контент до двух недель. При восстановлении галереи просроченные записи Harvard удаляются. Изображения Harvard не сохраняются на диск. Карточки показывают права на изображение и ссылку на страницу музея. [Документация Harvard Art Museums API](https://github.com/harvardartmuseums/api-docs).

## Архитектура

- **Domain** содержит `Artwork`, версионированную модель перевода и протоколы источника и репозитория.
- **Data** содержит адаптеры `ClevelandAPI` и `HarvardAPI`, отдельные DTO, преобразование HTML в обычный текст через системную libxml2, репозиторий SwiftData, `ImagePipeline` и `TranslationService`. Для нового музея нужен адаптер `MuseumAPIProvider` и идентификатор источника в `MuseumSource`.
- **Features** содержит модель экрана галереи, пагинатор, карточку, избранное и полноэкранный просмотр. `MyApp` собирает зависимости и передаёт их модели.
Внешних пакетов нет. Кливленд использует музейный CDN, Harvard — IIIF. Перевод работает через Apple Translation.

## Хранение данных

SwiftData хранит оригиналы карточек, переводы, порядок выдачи, последнюю позицию и избранное. При запуске галерея перемешивает сохранённые картины и открывается с первой картины получившегося списка. При подгрузке картины новой страницы перемешиваются и добавляются в конец. Страница и курсор фиксируются одной транзакцией.

Декодированные изображения хранятся в `NSCache` с бюджетом 48 МБ. При системном предупреждении о памяти кэш очищается. Дисковый кэш ограничен 300 МБ, изображения избранного хранятся отдельно с лимитом 100 МБ. При достижении лимита первыми удаляются дольше всего не использовавшиеся файлы. Ответы с `Cache-Control: no-store` пишутся только в память на время отображения. Метаданные остаются доступны при вытеснении изображения. На устройство загружаются варианты IIIF шириной 600 или 843 px. Для увеличиваемого полноэкранного изображения используется вариант до 1800 px. Загрузка и декодирование выполняются вне главного актора, одновременные запросы одинакового URL объединяются.

Карточка показывает ссылку на музей, кредитную строку и сведения о правах.

## TranslationService

`GalleryTranslation` создаёт привязанную к представлению системную сессию и проверяет доступность пары английский → русский. Установленный пакет используется автоматически. При необходимости можно загрузить его с помощью кнопки в панели навигации и системного диалога. До завершения перевода и при неподдерживаемой паре отображается оригинал.

Работы переводятся последовательно с приоритетом текущей, следующей и предыдущей карточек. Кэш хранит оригинальные поля, идентификатор работы, пару языков и версию перевода. При изменении исходного текста или версии результат считается устаревшим. UI сохраняет авторские написания из словаря для распространённых имён художников.

## ArtworkPager

Галерея использует горизонтальный ScrollView и LazyHStack с системной фиксацией по одной карточке. Позиция привязана к ID произведения и сохраняется после остановки прокрутки. Стрелки и действия VoiceOver дублируют навигацию.

## Тесты

В Xcode запустите **Product → Test** на симуляторе iPhone. Unit-тесты проверяют декодирование, HTML, фильтрацию, дедупликацию, восстановление позиции и кэш перевода. UI-тесты работают на локальных данных с подменой музейного API и изображений.

## Ограничения и приёмка

- Системные пакеты Apple Translation и качество перевода проверяются на физическом iPhone.
- Для приёмочного замера FPS, холодного старта, памяти и утечек нужен физический iPhone и прогон Instruments, включая сценарий со 100 переходами.
- Проверка прав выполняется при получении ответа API. Исторический кэш без нового ответа сохраняет последний известный статус.
- Сервер изображений Harvard может вернуть HTTP 403. В этом случае из галереи можно переключиться на Кливленд.

## Установка готовой сборки на симулятор

Распакуйте `Artifacts/ArtGallery-Simulator-arm64.zip` на Mac с Apple Silicon. Запустите симулятор iPhone. Из каталога с распакованным приложением выполните:

```sh
xcrun simctl install booted ArtGallery.app
xcrun simctl launch booted org.artgallery.ios

Artifacts/ArtGallery-iPhone-unsigned.zip contains the unsigned Release build for physical devices. Use the signing steps above to run the app on an iPhone.
