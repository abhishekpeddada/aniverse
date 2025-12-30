# Changelog

## [1.2.0] - 2025-12-30

### Added
- **Resume Playback**: New popup dialog prompts to resume video from last position (Streaming & Offline).
- **Download Recovery**: Added 'Sync' button in Downloads screen to scan and restore existing files after reinstall.
- **Smart Metadata**: Restored downloads automatically fetch correct titles and thumbnails.

### Fixed
- **Continue Watching**: Fixed issue where completed series were hidden.
- **Offline Playback**: Improved integration for restored files.

## [1.1.0] - 2025-12-04

### Added
- Integrated Raiden API as a secondary source for hanime content.
- implemented dual-source architecture to query both AllAnime and Raiden APIs.
- Added Adult Mode toggle in Profile settings.
- Added genre filter to Latest Releases screen with pagination and caching.
- Added source badges (Raiden/AllAnime) to search results.

### Changed
- Updated bottom navigation bar background color to pitch black.
- Modified Latest Releases to support content without episode numbers.
- Updated video player to handle direct video URLs without API fetching.

### Fixed
- Fixed app crash on startup caused by Hive schema changes.
- Fixed video player failing to play Raiden content by using cached download URLs.
- Fixed grey boxes in Latest Releases by providing default values for missing fields.

## [1.0.0] - 2025-12-01

### Added
- Initial release
- Browse and search anime catalog
- Stream episodes with multi-quality support
- Adaptive video player with gesture controls (seek, volume, brightness)
- Continue watching history with local resume
- Watchlist and favorites management
- Google Sign-In integration
- Cloud sync via Firebase Firestore
- Episode search functionality
- HTML rendering for anime descriptions

### Video Player Features
- Multi-source playback with automatic failover
- Smart error handling to prevent premature failures during buffering
- Horizontal swipe to seek
- Vertical swipe for volume (right side) and brightness (left side)
- Double tap for 10-second skip forward/backward
- Quality selector for multiple video sources
- SUB/DUB toggle support

### Performance Optimizations
- Reduced Firestore write operations by storing playback position locally only
- Cloud sync triggers only on session start/end
- Automatic source switching on video load failure
- Wixmp proxy link extraction for improved source compatibility

### Bug Fixes
- Fixed stuck feedback icons after gesture controls
- Fixed history deletion not syncing to cloud
- Fixed transparent app icon background
- Fixed HTML tags displaying in descriptions
- Fixed premature source switching during seek operations
- Fixed background audio playing after video errors

### Platform Support
- Android
- iOS
- Web
- Linux (via external mpv player)
- Windows

### Known Limitations
- Playback position does not sync across devices (intentional to reduce database costs)
- Linux version requires mpv to be installed
- Cross-device resume requires manual episode selection
