# Cubelyze app icon

The icon combines an isometric cube with a segmented review timeline and playhead.
The cube uses ivory, cyan, and orange stickers against a midnight-blue tile.
A play symbol was considered but emphasized playback; a viewport frame was
considered but made the silhouette busier. The timeline emphasizes solve analysis.

`cubelyze-icon.png` is the 1024px RGBA master artwork, generated using the built-in
image generation tool. Transparent space surrounds the rounded tile. No external
case diagrams or third-party icon artwork are used.

Run `sh scripts/generate-app-icon.sh` after updating the master. This regenerates
the ten macOS AppIcon PNGs (16, 32, 128, 256, and 512 points at 1x/2x) and the ICNS
used by the command-line build. Xcode uses `Assets.xcassets` with AppIcon selected
in Debug and Release; `scripts/build.sh` copies the ICNS and declares it in the
bundle metadata. Commit the master, asset catalog, and ICNS together.

## Generation prompt

Use case: logo-brand. Create a production-quality macOS app icon for Cubelyze, a Rubik's Cube solve video analysis tool. One square 1024x1024 icon, no text or letters. Centered macOS rounded-square deep midnight-blue tile, gently bevelled with restrained depth and soft highlights. A large clean isometric 3x3 cube with precise regular sticker geometry, warm ivory top, rich cyan left face, coral orange right face, dark narrow divisions. Under the cube, a minimal horizontal review timeline with three broad segments and one bright ivory vertical playhead. Bold simple composition, ample negative space, serious technical desktop utility, not a toy. Design must remain readable at 16 pixels; no tiny decorations, no extra symbols, no photorealistic setting, no surrounding mockup, no watermark. Transparent canvas outside the rounded-square tile, subtle tight shadow only. Deliver the final isolated icon.
