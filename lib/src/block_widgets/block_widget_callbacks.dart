// ============================================================
// @remind CALLBACKS
// ============================================================

/// Signals the editor should merge this block with the previous one.
typedef BlockDeleteCallback = void Function();

/// Signals the editor should split this block at the cursor position.
typedef BlockNewlineCallback = void Function(int cursorPosition);

/// Signals focus should move to the adjacent block.
typedef BlockNavigateCallback = void Function();

/// Signals the block's text content changed.
typedef BlockTextChangedCallback = void Function(String text);

/// Signals a table cell changed.
typedef TableCellChangedCallback = void Function(int row, int col, String text);

/// Signals focus changed on a block.
typedef BlockFocusCallback = void Function(bool hasFocus);
