## 0.6.0

- **Fixed**: Markdown rendering now shows rendered result when textfield is unfocused (previously showed raw syntax)
- **Fixed**: Image spacing now works correctly on initial load - virtual newlines are injected for proper image widget spacing
- **Improved**: Focus state tracking - clearing focused line when textfield loses focus

## 0.5.0

- Fixed `onLinkTap` crash on desktop platforms (Linux, Windows, macOS)
- Replaced TapGestureRecognizer with offset-based tap handling to comply with Flutter's RenderEditable assertion

## 0.1.1

* replace depricated "withOpacity" with "withValues"
