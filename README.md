# Markdown Editor Live for Flutter

A Flutter widget that provides a **WYSIWYG-style markdown editing experience** with live syntax highlighting (similar to Obsidian or Typora). Markdown syntax is displayed only on the line you're currently editing, and on other lines, the formatted result is shown directly.

[![pub package](https://img.shields.io/pub/v/markdown_editor_live.svg)](https://pub.dev/packages/markdown_editor_live)
[![License: BSD-3](https://img.shields.io/badge/license-BSD--3-blue.svg)](https://opensource.org/licenses/BSD-3-Clause)

## Features

- **Live WYSIWYG Editing** — Syntax markers (like `**`, `#`, etc.) are hidden except on the line you're currently editing
- **Syntax Highlighting** — Visual distinction for headers, bold, italic, code, and more
- **Auto-Continuing Lists** — Press Enter on a list item to automatically add the next bullet or number
- **Tab Support** — Tab key inserts indentation; supports both soft tabs (spaces) and hard tabs
- **Multi-line Selection Indent** — Select multiple lines and press Tab to indent them all
- **Customizable Styling** — Pass your own `TextStyle` and `InputDecoration`

### Currently Supported Markdown Syntax

| Element           | Syntax                        |
|-------------------|-------------------------------|
| Headers (H1–H6)   | `# Header` through `###### H6`|
| Bold              | `**text**` or `__text__`      |
| Italic            | `*text*` or `_text_`          |
| Strikethrough     | `~~text~~`                    |
| Inline code       | `` `code` ``                  |
| Code blocks       | ` ``` code ``` `              |
| Unordered lists   | `- item`, `* item`, `+ item`  |
| Ordered lists     | `1. item`, `2. item`          |
| Thematic breaks   | `---`, `***`, `___`           |
| Images            | `![alt text](url)`            |

## Getting Started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  markdown_editor_live: ^0.1.0
```

Then run:

```bash
flutter pub get
```

## Usage

### Basic Example

```dart
import 'package:flutter/material.dart';
import 'package:markdown_editor_live/markdown_editor_live.dart';

class MyEditor extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MarkdownEditor(
      initialValue: '# Hello World\n\nThis is **bold** and *italic*.',
      onChanged: (text) {
        print('Content: $text');
      },
    );
  }
}
```

### With Custom Styling

```dart
MarkdownEditor(
  initialValue: '# Styled Editor',
  onChanged: (text) => setState(() => _content = text),
  style: const TextStyle(
    fontSize: 16,
    fontFamily: 'Roboto',
    height: 1.5,
  ),
  decoration: const InputDecoration(
    border: OutlineInputBorder(),
    hintText: 'Start typing markdown...',
  ),
)
```

### Image Tap Handling

You can handle image taps using the `onImageTap` callback:

```dart
MarkdownEditor(
  initialValue: '# Image Example\n\n![Logo](https://example.com/logo.png)',
  onImageTap: (url) {
    // Handle image tap - e.g., open in full screen
    print('Image tapped: $url');
  },
)
```

### Tab Configuration

Control how the Tab key behaves:

```dart
MarkdownEditor(
  initialValue: 'Press Tab to indent!',
  useSoftTabs: true,   // Use spaces instead of \t (default: true)
  tabWidth: 4,         // Number of spaces per tab (default: 2)
)
```

## API Reference

### MarkdownEditor

| Property       | Type                      | Default | Description                                          |
|----------------|---------------------------|---------|------------------------------------------------------|
| `initialValue` | `String?`                 | `null`  | Initial markdown content                             |
| `onChanged`    | `ValueChanged<String>?`   | `null`  | Callback when content changes                        |
| `onImageTap`   | `void Function(String url)?` | `null` | Callback fired when an image is tapped. Receives the image URL as parameter. |
| `style`        | `TextStyle?`              | `null`  | Text style for the editor                            |
| `decoration`   | `InputDecoration?`        | `null`  | Input decoration for the TextField                   |
| `useSoftTabs`  | `bool`                    | `true`  | Use spaces instead of tab characters                 |
| `tabWidth`     | `int`                     | `2`     | Number of spaces per soft tab                        |

### MarkdownEditingController

For advanced use cases, you can use `MarkdownEditingController` directly with a standard `TextField`:

```dart
final controller = MarkdownEditingController(text: '# My Content');

TextField(
  controller: controller,
  maxLines: null,
)
```

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│  MarkdownEditor (markdown_editor.dart)                       │
│  StatefulWidget — owns & orchestrates everything             │
│                                                              │
│  State:                                                      │
│    List<Block>     _blocks      ← the document model         │
│    List<FocusNode> _focusNodes  ← one per block              │
│    List<GlobalKey> _blockKeys   ← for widget identity        │
│                                                              │
│  ┌──────────────┐    parse()     ┌──────────────────────┐    │
│  │ String input  │──────────────▶│ MarkdownParser       │    │
│  │ (initialValue)│               │ (document_model.dart)│    │
│  └──────────────┘               └──────────┬───────────┘    │
│                                             ▼                │
│                                    List<Block>               │
│                                    (7 sealed subtypes)       │
│                                             │                │
│  ┌──────────────────────────────────────────┼────────────┐   │
│  │ ListView.builder                         │            │   │
│  │   _buildBlock(index) switches on type:   ▼            │   │
│  │   ┌──────────────────────────────────────────────┐    │   │
│  │   │ ParagraphBlock → TextBlockWidget             │    │   │
│  │   │ HeadingBlock   → HeadingBlockWidget          │    │   │
│  │   │ ListItemBlock  → ListItemBlockWidget         │    │   │
│  │   │ CodeBlock      → CodeBlockWidget             │    │   │
│  │   │ TableBlock     → TableBlockWidget            │    │   │
│  │   │ ImageBlock     → ImageBlockWidget            │    │   │
│  │   │ ThematicBreak  → ThematicBreakWidget         │    │   │
│  │   └──────────────────────────────────────────────┘    │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                              │
│  On any change, blocks → MarkdownSerializer.serialize()      │
│  → onChanged(String) callback to consumer                    │
└──────────────────────────────────────────────────────────────┘
```

### File Responsibilities


| File                                                                                                                                                                                    | Role                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [**document_model.dart**](vscode-file://vscode-app/c:/Program%20Files/Microsoft%20VS%20Code/10c8e557c8/resources/app/out/vs/code/electron-browser/workbench/workbench.html)             | **Data layer.** Defines the `sealed class Block` with 7 subtypes (`ParagraphBlock`, `HeadingBlock`, `ListItemBlock`, `CodeBlock`, `TableBlock`, `ImageBlock`, `ThematicBreakBlock`). Contains `MarkdownParser.parse(String)` (line-by-line state machine that turns raw markdown into `List<Block>`) and `MarkdownSerializer.serialize(List<Block>)` (turns blocks back to a markdown string). Each block has a `toMarkdown()` method.                        |
| [**block_widgets.dart**](vscode-file://vscode-app/c:/Program%20Files/Microsoft%20VS%20Code/10c8e557c8/resources/app/out/vs/code/electron-browser/workbench/workbench.html)              | **View layer.** One `StatefulWidget` per block type. Each widget owns its own `TextEditingController` + `FocusNode`, handles keyboard events (Enter → split, Backspace@0 → merge, ArrowUp/Down → navigate), and calls callbacks to notify the editor. The widget decides what to render when focused vs unfocused (e.g. heading shows `#` prefix when focused, hides it when not).                                                                         |
| [**markdown_editor.dart**](vscode-file://vscode-app/c:/Program%20Files/Microsoft%20VS%20Code/10c8e557c8/resources/app/out/vs/code/electron-browser/workbench/workbench.html)            | **Controller/orchestrator.** Owns the `List<Block>`, `List<FocusNode>`, and `List<GlobalKey>`. Builds a `ListView.builder` that switches on block type to instantiate the right widget. Handles structural operations: `_onBlockDelete` (merge blocks), `_onBlockNewline` (split block), `_insertBlockAfter`, navigation between blocks, and serializes back to markdown on every change.                                                                     |
| [**inline_markdown_controller.dart**](vscode-file://vscode-app/c:/Program%20Files/Microsoft%20VS%20Code/10c8e557c8/resources/app/out/vs/code/electron-browser/workbench/workbench.html) | **Inline formatting engine.** A custom `TextEditingController` used by text-bearing blocks (`TextBlockWidget`, `HeadingBlockWidget`, `ListItemBlockWidget`). Overrides `buildTextSpan()` to apply rich text styling for bold, italic, strikethrough, inline code, and links. Has a `showSyntax` toggle — when focused it shows raw markers (`**`, `~~`, etc.), when unfocused it hides them and renders styled text. Tracks `_linkRanges` for tap detection. |

**Data flow:** User types → block widget's controller updates → `onTextChanged` callback → `_MarkdownEditorState` updates the `Block` object → calls `_notifyChanged()` → `MarkdownSerializer.serialize(_blocks)` → `widget.onChanged(markdownString)`.


## Example App

Check out the [example](example/) directory for a complete demo application showing the editor in action with a side-by-side raw text preview.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

This project is licensed under the BSD-3-Clause License — see the [LICENSE](LICENSE) file for details.


Created by [Janek](https://janekwenzlik.de)