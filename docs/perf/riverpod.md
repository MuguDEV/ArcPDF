Riverpod Optimization:
- `pdfLibraryControllerProvider` is currently monolithic.
- We will instruct the app to use `select` when consuming from these providers, for instance in `HomeScreen`.
`openTabsProvider` is also heavily watched in `HomeScreen`'s `_SessionResumeBar`, `MultiTabViewerScreen`, and `TabSwitcherScreen`.
Using `select` is preferred to prevent unnecessary rebuilds. In `MultiTabViewerScreen`, since both `tabs` and `activeIndex` are needed, watching the whole state is somewhat justified.
