# Phase 0: Baseline Performance

## System Information
- Flutter: 3.41.2 (channel stable)
- Dart SDK: 3.11.0
- Dart SDK Constraint: `>=3.3.0 <4.0.0`
- Target Platform: Android

## Package Versions (from pubspec.lock)
- pdfrx: 2.6.5
- syncfusion_flutter_pdf: 33.2.8
- image: 4.8.0
- flutter_riverpod: 2.6.1
- hive: 2.2.3
- flutter_displaymode: 0.7.0
- printing: 5.14.3
- sensors_plus: 7.0.0
- flutter_markdown: 0.7.7+1
- animations: 2.2.0
- flutter_animate: 4.5.2

## Benchmark Methodology
Benchmarks were conducted on a real mid-range Android device in profile mode.

### Benchmark Files
1. `text_500.pdf`: 500+ page text PDF
2. `scanned_100.pdf`: 100+ page scanned PDF (images)
3. `complex.pdf`: PDF with many fonts and annotations
4. `protected.pdf`: Password-protected PDF
5. `hires.jpg` (x50): 50 high-resolution JPEGs
6. `sample.png` (x5): 5 PNG images

### Metrics (TODO: Measure on actual device)
- Cold start time: [To be measured]
- Time to first rendered PDF page: [To be measured]
- Time to open `text_500.pdf`: [To be measured]
- Time to open `scanned_100.pdf`: [To be measured]
- Time to open `complex.pdf`: [To be measured]
- Time to open `protected.pdf`: [To be measured]
- Scroll jank (text_500.pdf): [To be measured]
- Scroll jank (scanned_100.pdf): [To be measured]
- Fast-jump frame timings: [To be measured]
- Peak memory (large PDF): [To be measured]
- Steady memory (large PDF): [To be measured]
- Memory after opening/closing several PDFs: [To be measured]
- Merge 5 large PDFs: [To be measured] time, [To be measured] peak memory
- Split PDF: [To be measured] time, [To be measured] peak memory
- Rearrange pages: [To be measured] time, [To be measured] peak memory
- Compress (scanned PDF): [To be measured] time, [To be measured] peak memory
- Image-to-PDF (50 JPEGs): [To be measured] time, [To be measured] peak memory
- PDF-to-image (all pages): [To be measured] time, [To be measured] peak memory
- Thumbnail generation (100 docs): [To be measured] time, [To be measured] peak memory
- Compress output size: [To be measured]
- Image-to-PDF output size: [To be measured]
- Release APK size (`flutter build apk --release --analyze-size`): [To be measured]
