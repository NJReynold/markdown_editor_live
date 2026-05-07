import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_editor_live/src/block_widgets/block_widget_callbacks.dart';

// ============================================================
// @remind CODE BLOCK
// ============================================================
class CodeBlockWidget extends StatefulWidget {
  const CodeBlockWidget({
    required this.language,
    required this.code,
    required this.style,
    this.showMarkdownSource = false,
    this.onCodeChanged,
    this.onDelete,
    this.onMovePrevious,
    this.onMoveNext,
    this.onFocusChanged,
    this.focusNode,
    super.key,
  });
  final String language;
  final String code;
  final TextStyle style;
  final bool showMarkdownSource;
  final BlockTextChangedCallback? onCodeChanged;
  final BlockDeleteCallback? onDelete;
  final BlockNavigateCallback? onMovePrevious;
  final BlockNavigateCallback? onMoveNext;
  final BlockFocusCallback? onFocusChanged;
  final FocusNode? focusNode;
  @override
  State<CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<CodeBlockWidget> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _hasFocus = false;
  bool _isEditing = false;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.code);
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(CodeBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.code != _controller.text && widget.code != oldWidget.code) {
      _controller.text = widget.code;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    if (widget.focusNode == null) _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() {
      _hasFocus = _focusNode.hasFocus;
      _isEditing = _hasFocus;
    });
    widget.onFocusChanged?.call(_hasFocus);
  }

  void _enterEditMode() {
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Backspace at position 0 with empty content → delete block
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_controller.text.isEmpty) {
        widget.onDelete?.call();
        return KeyEventResult.handled;
      }
    }
    // Up arrow at first line
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final int offset = _controller.selection.baseOffset;
      if (!_controller.text.substring(0, offset).contains('\n')) {
        widget.onMovePrevious?.call();
        return KeyEventResult.handled;
      }
    }
    // Down arrow at last line
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final int offset = _controller.selection.baseOffset;
      if (!_controller.text.substring(offset).contains('\n')) {
        widget.onMoveNext?.call();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle codeStyle = widget.style.copyWith(fontFamily: 'monospace');
    final TextStyle fenceStyle = codeStyle.copyWith(color: Colors.grey.shade500);
    final String langLabel = widget.language.isNotEmpty ? widget.language : '';

    if (!_isEditing) {
      return GestureDetector(
        onTap: _enterEditMode,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.all(8),
          child: Text('\`\`\`$langLabel\n${_controller.text}\n\`\`\`\n', style: codeStyle),
        ),
      );
    }

    return SelectionContainer.disabled(
      child: Focus(
        onKeyEvent: _handleKeyEvent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('```$langLabel', style: fenceStyle),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: codeStyle,
                maxLines: null,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: widget.onCodeChanged,
              ),
              Text('```', style: fenceStyle),
            ],
          ),
        ),
      ),
    );
  }
}
