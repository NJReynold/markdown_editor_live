import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_editor_live/src/markdown_text_editing_controller.dart';

void main() {
  group('MarkdownEditingController', () {
    test('Initializes with text', () {
      final controller = MarkdownEditingController(text: 'Hello');
      expect(controller.text, 'Hello');
    });

    testWidgets('Builds TextSpan with styles', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final controller = MarkdownEditingController(
                  text: '# Header\n\n**Bold**',
                );
                final TextSpan span = controller.buildTextSpan(
                  context: context,
                  withComposing: false,
                );

                // We expect a TextSpan with children
                expect(span, isA<TextSpan>());
                expect(span.children, isNotEmpty);

                // Check for Header style
                // The first child should match '# Header' with bold and larger font
                // Note: Our naive parser might return a list of spans where the text is split.
                // '# Header' should be one span if it matched the regex.

                // Let's print the structure to verify in logs if test fails
                // print(span.toPlainText());
                return Container();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('Parses bold text correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final controller = MarkdownEditingController(
                  text: 'This is **bold** text',
                );
                final TextSpan span = controller.buildTextSpan(
                  context: context,
                  withComposing: false,
                );

                // Based on our logic (no line focused, so syntax is hidden):
                // "This is " (default)
                // "**" (hidden prefix)
                // "bold" (bold content)
                // "**" (hidden suffix)
                // " text" (default)

                expect(span.children?.length, 5);
                expect(span.children![0].toPlainText(), 'This is ');
                expect(span.children![1].toPlainText(), '**');
                expect(span.children![1].style?.fontSize, 0.0); // hidden
                expect(span.children![2].toPlainText(), 'bold');
                expect(span.children![2].style?.fontWeight, FontWeight.bold);
                expect(span.children![3].toPlainText(), '**');
                expect(span.children![3].style?.fontSize, 0.0); // hidden
                expect(span.children![4].toPlainText(), ' text');

                return Container();
              },
            ),
          ),
        ),
      );
    });
  });
}
