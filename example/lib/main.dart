import 'package:flutter/material.dart';
import 'package:markdown_editor_live/markdown_editor_live.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Markdown Editor Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Markdown Editor Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _markdownData = """
# Markdown Editor Demo

This is a **live** markdown editor.

## Features

- **Bold text**
- *Italic text*
- `Inline code`
- Headers

My favorite search engine is [Duck Duck Go](https://duckduckgo.com "The best search engine for privacy").

## Images

![Test Image](https://picsum.photos/id/237/200/300)

*Tap the image to see the tap handler in action!*

## Nested Lists (Try pressing Tab!)

- Level 1 item
  - Nested item (press Tab to indent)
  - Another nested item
- Back to level 1
  - Another nested item
    - Deeply nested item

## Ordered Lists

1. First item
   1. Nested ordered item
   2. Another nested item
2. Second item

```
Block code
```

Try typing here!
""";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: MarkdownEditor(
                initialValue: _markdownData,
                onChanged: (value) {
                  setState(() {
                    _markdownData = value;
                  });
                },
                onLinkTap: (url) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Link tapped: $url')),
                  );
                },
                onImageTap: (url) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Image tapped: $url')),
                  );
                },
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Type markdown here...',
                ),
                // Set image height to 10 lines (160px with fontSize 16)
                // Default is 5 lines if not specified
                imageHeightLines: 10,
              ),
            ),
          ),
          const VerticalDivider(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(child: Text(_markdownData)),
            ),
          ),
        ],
      ),
    );
  }
}
