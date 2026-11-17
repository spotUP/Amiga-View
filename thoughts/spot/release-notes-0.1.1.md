Amiga-View 0.1.1 makes the CRT shader load fast.

- Compiled CRT shader passes are now cached on disk (in ~/Library/Caches/librashader). A preset that was loaded before comes back in about 0.1 s instead of 2-3 s; the Standard preset went from 2.2 s to 91 ms. The first load of a preset also compiles its passes in parallel (about 0.7 s instead of 2.2 s). The very first launch after installing can still take longer while macOS builds its own Metal cache.
- The cache lives in a patched librashader 0.12.1 (patches/librashader); the picture is pixel-identical to an uncached load.

Install: unzip Amiga-View-0.1.1.zip and move Amiga-View.app to Applications, replacing 0.1.0. The app is signed with a self-made certificate, not notarised, so the first launch needs right-click > Open.

Licences are unchanged from 0.1.0: the app is MIT, pi/stk1160 is GPL-2.0, the bundled librashader is MPL-2.0 and the Mega Bezel and slang-shaders presets are GPL-3.0; their licence texts ship in the app.
