import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_editor_live/src/block_widgets/block_widget_callbacks.dart';

// ============================================================
// @remind TABLE BLOCK — Per-cell TextField editing
// ============================================================
class TableBlockWidget extends StatefulWidget {
  const TableBlockWidget({
    required this.headers,
    required this.alignments,
    required this.rows,
    required this.style,
    this.showMarkdownSource = false,
    this.onCellChanged,
    this.onMovePrevious,
    this.onMoveNext,
    this.onFocusChanged,
    this.focusNode,
    super.key,
  });
  final List<String> headers;
  final List<TextAlign> alignments;
  final List<List<String>> rows;
  final TextStyle style;
  final bool showMarkdownSource;
  final TableCellChangedCallback? onCellChanged;
  final BlockNavigateCallback? onMovePrevious;
  final BlockNavigateCallback? onMoveNext;
  final BlockFocusCallback? onFocusChanged;
  final FocusNode? focusNode;
  @override
  State<TableBlockWidget> createState() => _TableBlockWidgetState();
}

class _TableBlockWidgetState extends State<TableBlockWidget> {
  // 2D grid of controllers and focus nodes
  // Row 0 = headers, rows 1+ = data
  late List<List<TextEditingController>> _controllers;
  late List<List<FocusNode>> _cellFocusNodes;
  bool _anyFocused = false;
  int get _totalRows => 1 + widget.rows.length;
  int get _numCols => widget.headers.length;
  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    _controllers = [];
    _cellFocusNodes = [];
    // Header row
    final headerControllers = <TextEditingController>[];
    final headerFocusNodes = <FocusNode>[];
    for (var col = 0; col < _numCols; col++) {
      headerControllers.add(
        TextEditingController(text: col < widget.headers.length ? widget.headers[col] : ''),
      );
      final fn = FocusNode();
      fn.addListener(_onAnyCellFocusChanged);
      headerFocusNodes.add(fn);
    }
    _controllers.add(headerControllers);
    _cellFocusNodes.add(headerFocusNodes);
    // Data rows
    for (var row = 0; row < widget.rows.length; row++) {
      final rowControllers = <TextEditingController>[];
      final rowFocusNodes = <FocusNode>[];
      for (var col = 0; col < _numCols; col++) {
        final String cellText = col < widget.rows[row].length ? widget.rows[row][col] : '';
        rowControllers.add(TextEditingController(text: cellText));
        final fn = FocusNode();
        fn.addListener(_onAnyCellFocusChanged);
        rowFocusNodes.add(fn);
      }
      _controllers.add(rowControllers);
      _cellFocusNodes.add(rowFocusNodes);
    }
  }

  @override
  void dispose() {
    for (final List<TextEditingController> row in _controllers) {
      for (final c in row) {
        c.dispose();
      }
    }
    for (final List<FocusNode> row in _cellFocusNodes) {
      for (final fn in row) {
        fn.removeListener(_onAnyCellFocusChanged);
        fn.dispose();
      }
    }
    super.dispose();
  }

  void _onAnyCellFocusChanged() {
    final bool nowFocused = _cellFocusNodes.any((row) => row.any((fn) => fn.hasFocus));
    if (nowFocused != _anyFocused) {
      setState(() => _anyFocused = nowFocused);
      widget.onFocusChanged?.call(nowFocused);
    }
  }

  void _enterEditMode() {
    setState(() => _anyFocused = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_cellFocusNodes.isNotEmpty && _cellFocusNodes[0].isNotEmpty) {
        _cellFocusNodes[0][0].requestFocus();
      }
    });
  }

  String _buildMarkdownSource() {
    final headerRow = '| ${widget.headers.join(' | ')} |';
    final separator = '| ${widget.headers.map((_) => '---').join(' | ')} |';
    final dataRows = widget.rows.map((row) => '| ${row.join(' | ')} |').join('\n');
    if (dataRows.isEmpty) {
      return '$headerRow\n$separator';
    }
    return '$headerRow\n$separator\n$dataRows';
  }

  void _onCellChanged(int row, int col, String text) {
    widget.onCellChanged?.call(row, col, text);
  }

  KeyEventResult _handleCellKeyEvent(FocusNode node, KeyEvent event, int row, int col) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Tab → next cell
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _moveToPrevCell(row, col);
      } else {
        _moveToNextCell(row, col);
      }
      return KeyEventResult.handled;
    }

    // Enter → move to cell below (or next block if at last row)
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (row + 1 < _totalRows) {
        _cellFocusNodes[row + 1][col].requestFocus();
      } else {
        widget.onMoveNext?.call();
      }
      return KeyEventResult.handled;
    }

    // Arrow up at first row → previous block
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && row == 0) {
      widget.onMovePrevious?.call();
      return KeyEventResult.handled;
    }

    // Arrow down at last row → next block
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && row == _totalRows - 1) {
      widget.onMoveNext?.call();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _moveToNextCell(int row, int col) {
    if (col + 1 < _numCols) {
      _cellFocusNodes[row][col + 1].requestFocus();
    } else if (row + 1 < _totalRows) {
      _cellFocusNodes[row + 1][0].requestFocus();
    } else {
      widget.onMoveNext?.call();
    }
  }

  void _moveToPrevCell(int row, int col) {
    if (col - 1 >= 0) {
      _cellFocusNodes[row][col - 1].requestFocus();
    } else if (row - 1 >= 0) {
      _cellFocusNodes[row - 1][_numCols - 1].requestFocus();
    } else {
      widget.onMovePrevious?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_anyFocused) {
      if (widget.showMarkdownSource) {
        // Raw markdown pipe syntax for SelectionArea copy
        return GestureDetector(
          onTap: _enterEditMode,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '${_buildMarkdownSource()}\n',
              style: widget.style.copyWith(fontFamily: 'monospace'),
            ),
          ),
        );
      }

      return GestureDetector(
        onTap: _enterEditMode,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Table(
            border: TableBorder.all(color: Colors.grey.shade400),
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: List.generate(_totalRows, (row) {
              final isHeader = row == 0;
              return TableRow(
                decoration: isHeader ? BoxDecoration(color: Colors.grey.shade100) : null,
                children: List.generate(_numCols, (col) {
                  final TextStyle cellStyle = isHeader ? widget.style.copyWith(fontWeight: FontWeight.bold) : widget.style;
                  final String cellText = row == 0
                      ? (col < widget.headers.length ? widget.headers[col] : '')
                      : (col < widget.rows[row - 1].length ? widget.rows[row - 1][col] : '');
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      cellText,
                      style: cellStyle,
                      textAlign: col < widget.alignments.length ? widget.alignments[col] : TextAlign.left,
                    ),
                  );
                }),
              );
            }),
          ),
        ),
      );
    }

    return SelectionContainer.disabled(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Table(
          border: TableBorder.all(color: Colors.grey.shade400),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: List.generate(_totalRows, (row) {
            final isHeader = row == 0;
            return TableRow(
              decoration: isHeader ? BoxDecoration(color: Colors.grey.shade100) : null,
              children: List.generate(_numCols, (col) {
                final TextStyle cellStyle = isHeader ? widget.style.copyWith(fontWeight: FontWeight.bold) : widget.style;
                return Focus(
                  onKeyEvent: (node, event) => _handleCellKeyEvent(node, event, row, col),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: TextField(
                      controller: _controllers[row][col],
                      focusNode: _cellFocusNodes[row][col],
                      style: cellStyle,
                      textAlign: col < widget.alignments.length ? widget.alignments[col] : TextAlign.left,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                      ),
                      onChanged: (text) => _onCellChanged(row, col, text),
                    ),
                  ),
                );
              }),
            );
          }),
        ),
      ),
    );
  }
}
