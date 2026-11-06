# Vendored media_kit_video

This is `media_kit_video` 2.0.1 from pub.dev with one change: upstream commit
[`f702a64`](https://github.com/media-kit/media-kit/commit/f702a64) (#1440) in
`linux/texture_gl.cc`, which passes `MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME = 0`.
The example app was removed to save space.

Without that change, each frame blocks Flutter's raster thread, and 24 fps video
visibly stutters on Linux. On a debug build of a 1080p episode, it dropped 38
frames in 20 seconds without the fix and 7 with it. A profile build with the fix
dropped none in 60 seconds.

The fix isn't on pub.dev yet. When a release newer than 2.0.1 includes it, delete
this folder and the `dependency_overrides` entry in `pubspec.yaml`, then raise the
`media_kit_video` version there.
