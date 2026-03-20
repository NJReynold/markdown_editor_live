# Plan: Remove Image Rendering from Markdown Editor

## Overview

This plan outlines the steps to fully remove image rendering functionality from the Flutter markdown editor live package. The image rendering feature includes parsing `![alt](url)` syntax and displaying actual images using `Image.network` widgets.

## Current Implementation Analysis

Image rendering is currently implemented in the following locations:

### 1. [`lib/src/markdown_editor.dart`](lib/src/markdown_editor.dart)
- **Line 9**: `onImageTap` callback parameter in `MarkdownEditor` widget
- **Line 20**: Constructor parameter `this.onImageTap`
- **Lines 41-42**: Passing `onImageTap` to `MarkdownEditingController`

### 2. [`lib/src/markdown_text_editing_controller.dart`](lib/src/markdown_text_editing_controller.dart)
- **Line 5**: Constructor parameter `this.onImageTap`
- **Lines 10-11**: `onImageTap` field declaration and documentation
- **Lines 180-185**: Image pattern definition in the patterns list
- **Lines 286-383**: Image handling block with `WidgetSpan` and `Image.network`
- **Line 513**: `image` value in `_PatternType` enum

### 3. [`example/lib/main.dart`](example/lib/main.dart)
- **Lines 66-68**: Image demo content in the example markdown

### 4. [`test/markdown_text_editing_controller_test.dart`](test/markdown_text_editing_controller_test.dart)
- **Lines 78-105**: Test case `Parses image syntax correctly`
- **Lines 107-134**: Test case `Image and link patterns do not conflict`

## Detailed Removal Steps

### Step 1: Remove `onImageTap` from `MarkdownEditor` widget

**File**: [`lib/src/markdown_editor.dart`](lib/src/markdown_editor.dart)

Remove:
```dart
final void Function(String url)? onImageTap;  // Line 9
```

Remove from constructor:
```dart
this.onImageTap,  // Line 20
```

Remove from controller initialization:
```dart
onImageTap: widget.onImageTap,  // Lines 41-42
```

### Step 2: Remove `onImageTap` from `MarkdownEditingController`

**File**: [`lib/src/markdown_text_editing_controller.dart`](lib/src/markdown_text_editing_controller.dart)

Remove from constructor:
```dart
this.onImageTap  // Line 5
```

Remove field declaration:
```dart
/// Called when an image is tapped. Receives the image URL as a string.
final void Function(String url)? onImageTap;  // Lines 10-11
```

### Step 3: Remove image pattern from patterns list

**File**: [`lib/src/markdown_text_editing_controller.dart`](lib/src/markdown_text_editing_controller.dart)

Remove the image pattern definition (Lines 180-185):
```dart
// Images ![alt](url) — must come before links
_MarkdownPattern(
  RegExp(r'(!\[)([^\]]*?)(\]\()([^\)]+)(\))'),
  (match) => const TextStyle(color: Colors.teal),
  type: _PatternType.image,
),
```

### Step 4: Remove image handling block

**File**: [`lib/src/markdown_text_editing_controller.dart`](lib/src/markdown_text_editing_controller.dart)

Remove the entire `else if (pattern.type == _PatternType.image)` block (Lines 286-383):
```dart
} else if (pattern.type == _PatternType.image) {
  // ... entire image rendering logic with WidgetSpan and Image.network
}
```

### Step 5: Remove `image` from `_PatternType` enum

**File**: [`lib/src/markdown_text_editing_controller.dart`](lib/src/markdown_text_editing_controller.dart)

Change line 513 from:
```dart
enum _PatternType { header, list, inline, image, link, thematicBreak }
```

To:
```dart
enum _PatternType { header, list, inline, link, thematicBreak }
```

### Step 6: Update example app

**File**: [`example/lib/main.dart`](example/lib/main.dart)

Remove the image section from the demo markdown (Lines 66-68):
```markdown
## Images

![Flutter logo](https://picsum.photos/id/237/200/300)
```

### Step 7: Update tests

**File**: [`test/markdown_text_editing_controller_test.dart`](test/markdown_text_editing_controller_test.dart)

Remove the following test cases:
- `Parses image syntax correctly` (Lines 78-105)
- `Image and link patterns do not conflict` (Lines 107-134)

## Files to Modify

| File | Changes |
|------|---------|
| `lib/src/markdown_editor.dart` | Remove `onImageTap` parameter and usage |
| `lib/src/markdown_text_editing_controller.dart` | Remove `onImageTap`, image pattern, image handling, and enum value |
| `example/lib/main.dart` | Remove image demo content |
| `test/markdown_text_editing_controller_test.dart` | Remove image-related tests |

## Impact Analysis

### Breaking Changes
- **API Change**: `onImageTap` callback will be removed from both `MarkdownEditor` widget and `MarkdownEditingController`
- **Behavior Change**: Image syntax `![alt](url)` will no longer be parsed or rendered as images

### Non-Breaking Changes
- All other markdown features (headers, lists, bold, italic, links, code, etc.) remain unchanged
- The `onLinkTap` callback for links remains functional

## Verification Checklist

After implementation:
- [ ] No compilation errors
- [ ] All remaining tests pass
- [ ] Example app runs without errors
- [ ] No references to `onImageTap` remain
- [ ] No references to `_PatternType.image` remain
- [ ] No `Image.network` usage in the library code
