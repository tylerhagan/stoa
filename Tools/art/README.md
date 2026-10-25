# Art scripts

Python (Pillow + NumPy) scripts that cut Stoa's console textures. The game never loads them.

- `chat_tabs.py <Media/Textures>` draws `ChatTab{Open,Closed}[Lines].tga` by bending the console edge's profile (`ConsoleEdge*.tga`) around a rounded tab.
- `plate_corners.py <Media/Textures>` draws `PlateFill.tga` and `PlateEdge.tga`, the small rounded pieces (3px corners, nine-sliced at 5px) that nameplate tracks and target edges use.
- `console_cut.py <source png> <Media/Textures>` cuts `ConsoleEdge[Lines].tga` and `ConsoleMedallion[Lines].tga` from the painting `source/console-basis.png`: scaled so the inner ring is 122 texels, the ring pulled round, both brass rings kept all the way under the seal, the long drop shadow trimmed to a soft edge. It prints the rows `Console.lua` uses. Rerun `chat_tabs.py` after it, since the tabs bend the edge.
- `round_medallion.py <src dir> <out dir>` (the older cut) takes the 512x256 medallion cut from the source art and stretches its ring into a true circle on a 512x512 canvas.

Gold `*Lines` textures are white with alpha, and the theme accent tints them in game.
- `window_stone.py <source png> <WindowStone.tga>` cuts the window stone from `source/wizard-stone2.png` (the first version, `wizard-stone.png`, is kept): its rings and grain as white with alpha (the art's dark ground turns clear), 1024x1024. The theme's text colour tints it in game.
- `window_corners.py <Media/Textures>` draws the window and tooltip pieces: `WindowFill`/`WindowEdge` (10px corners), `WindowTop` and `WindowBottom` (header band and footer tray, rounded on one side), `CardTop` (a tooltip's header band) and `TabFill`/`TabEdge` (window tabs, square on top so they tuck under the window). All 32x32, nine-sliced at 12px.
- `minimap_frames.py <source dir> <Media/Textures>` cuts `MinimapFrameSquare[Lines].tga` and `MinimapFrameRing[Lines].tga` (512x512) from `source/minimap-square.png` and `source/minimap-ring.png`, centred on each frame's opening, and prints how much wider than the map each frame is (`PAINTED` in `Minimap.lua`).
