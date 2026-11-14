# App for learning arts

Native art gallery app for IOS 26 and higher. Allows you to read about artworks in real time. Based on open API of Cleveland museum of art 

Build and Run
1. Open ArtGallery.xcodeproj from the source directory. This standalone project contains the app and test targets.
2. Select the ArtGallery scheme and an iPhone simulator, then click Run. The app fetches artwork and images from the museum API and reuses cached images when available.
3. For a physical iPhone, select your team under Signing & Capabilities, set a bundle identifier you control, and run on the device.
4. For TestFlight, use an Apple Developer Program account to create an App Store Connect record with the same team and bundle identifier. In Xcode, choose Product → Archive → Distribute App.
The shared scheme includes Release. To verify compilation without signing, run:
xcodebuild -project ArtGallery.xcodeproj -scheme ArtGallery \
  -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

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
xcrun simctl install booted ArtGallery.app
xcrun simctl launch booted org.artgallery.ios

Artifacts/ArtGallery-iPhone-unsigned.zip contains the unsigned Release build for physical devices. Use the signing steps above to run the app on an iPhone.
