1. **Fix layout clipping and overlapping caused by the bottom bar (ArcNavBar)**
   - The screenshot shows that the bottom list items and their bottom paddings are clipped or obscured. The ArcNavBar is floating, so the `home_screen.dart` needs enough bottom padding to ensure the last item is fully visible and not blocked by the floating bar.
   - Adjust `SliverSafeArea` or the bottom `SliverToBoxAdapter` in `home_screen.dart` to provide appropriate bottom padding (e.g. `120`).

2. **Fix Thumbnail and Status Bar alignment (`GlassSliverAppBar`)**
   - The thumbnail and badges within the `PdfCustomCard` need minor adjustments to look polished. The "not nice" feedback might be related to how the card content is padded or how the app bar looks.
   - Improve `GlassSliverAppBar` padding and layout so the "ArcPDF" title and the "workspace" subtitle are correctly aligned and don't look cramped or incorrectly spaced.
   - Adjust `pdf_custom_card.dart` layout, ensuring `ParallaxWrapper` doesn't cause clipping, and padding around thumbnails/text is well-balanced.

3. **Improve the App Transitions (Opening/Closing animations)**
   - The user complained about the opening/closing animation being "choppier" and not smooth.
   - Use `ZoomPageTransitionsBuilder` globally instead of `FadeUpwardsPageTransitionsBuilder` for a smoother, standard Android 14+ style zoom transition.
   - Ensure the ghost transition logic in `pdf_viewer_screen.dart` provides an immediate surface while `pdfrx` loads, avoiding the black screen or choppy start.

4. **Enhance PDF Viewer Rendering smoothness**
   - Make sure `pdfrx` viewer isn't causing jitters.

5. **Pre-commit checks**
   - Complete pre-commit checks to verify the code passes linting and testing.

6. **Submit**
   - Submit the changes using the existing branch.
