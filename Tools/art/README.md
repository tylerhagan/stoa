# Art scripts

Python (Pillow + NumPy) scripts that cut Stoa's console textures. The game never loads them.

- `chat_tabs.py <Media/Textures>` draws `ChatTab{Open,Closed}[Lines].tga` by bending the console edge's profile (`ConsoleEdge*.tga`) around a rounded tab.
- `plate_corners.py <Media/Textures>` draws `PlateFill.tga` and `PlateEdge.tga`, the small rounded pieces (3px corners, nine-sliced at 5px) that nameplate tracks and target edges use.
- `round_medallion.py <src dir> <out dir>` takes the 512x256 medallion cut from the source art and stretches its ring into a true circle on a 512x512 canvas.

Gold `*Lines` textures are white with alpha, and the theme accent tints them in game.
