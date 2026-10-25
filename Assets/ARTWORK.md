# Icon artwork

Created with the built-in image-generation tool using the user's supplied Lofree Touch product photo as a visual reference. No external API key, image API script or third-party image-generation service was used. The final raster is AppIcon.png; build.sh resizes it into standard macOS icon sizes and build_icon.py packages those PNGs as ICNS chunks. The menu-bar outline is a separate native NSBezierPath template drawing in Source/main.swift, 18×18 points in a 26-point-wide status item; it adapts to light/dark menu bars.

## Generation prompt

Use case: logo-brand. Create a polished macOS application icon inspired by the reference image of the Lofree Touch mouse. Reference image is visual reference only, not an edit target. A single warm stone-gray retro futuristic mouse, seen nearly top-down with a very slight isometric tilt, rounded sculptural lower palm shell, two distinct tall rectangular light-gray button caps at the upper end, centered metallic black vertical scroll wheel, tiny dark OLED window below the wheel with a restrained cyan glint, and a small coral-orange horizontal dash just below that. Include the characteristic left thumb wing. Soft premium 3D illustration, tactile matte PBT material, clean form, high contrast silhouette, subtle shadows. Center the mouse generously within a warm off-white rounded-square macOS icon tile with softly rounded corners and transparent outer corners. Square composition, mouse fills about 75 percent of tile, readable at small sizes. No lettering, no brand names, no watermark, no extra objects. Match the recognizable proportions and gray/coral color palette of the supplied photo.

Transparent background: true.

## Refinement prompt

Refine this macOS app icon. Keep the mouse design, composition, materials, colors and inner rounded-square tile essentially unchanged. Clean up the alpha mask: remove all speckles, fragments, white halos, and stray pixels outside the tile. Use one crisp smooth continuous rounded-square tile silhouette with clean transparent corners and about 3% fully transparent margin around the tile on all four sides. No shadow or decorative pixels outside the tile. The entire image must be square. No text, no watermark. Preserve transparency.

Transparent background: true. Edit target: first generated icon. The refinement was selected for the app.
