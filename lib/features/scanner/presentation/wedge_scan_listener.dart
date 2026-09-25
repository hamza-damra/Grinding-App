import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/formatting/digits.dart';

/// Hardware ("keyboard-wedge") scanner support. Rugged shop-floor devices and
/// USB/Bluetooth scanners type the barcode as key events followed by Enter.
///
/// This widget owns a focus node that holds focus whenever no text field
/// does, buffers digit key events (ASCII or Arabic-Indic) and calls [onScan]
/// with the buffer on Enter. It never focuses a text field, so the soft
/// keyboard does not pop up on the home screen. When a text field has focus
/// (the manual entry field) the keys go to that field instead, and its own
/// `onSubmitted` handles Enter — the two paths never both fire.
///
/// No Taleeb app had wedge support; this is new.
class WedgeScanListener extends StatefulWidget {
  const WedgeScanListener({
    required this.onScan,
    required this.child,
    this.enabled = true,
    this.focusNode,
    super.key,
  });

  final ValueChanged<String> onScan;
  final Widget child;
  final bool enabled;

  /// Optional external node (e.g. to re-take focus after the manual field).
  final FocusNode? focusNode;

  /// A pause longer than this between two keys starts a new code.
  static const Duration interKeyTimeout = Duration(seconds: 2);

  /// Bounded buffer: scanners emit 12 digits; anything longer is noise.
  static const int maxLength = 32;

  @override
  State<WedgeScanListener> createState() => _WedgeScanListenerState();
}

class _WedgeScanListenerState extends State<WedgeScanListener> {
  late final FocusNode _ownNode = FocusNode(debugLabel: 'wedge-scan');
  final StringBuffer _buffer = StringBuffer();
  DateTime? _lastKeyAt;

  FocusNode get _node => widget.focusNode ?? _ownNode;

  static final RegExp _digit = RegExp(r'^[0-9]$');

  @override
  void dispose() {
    _ownNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Only when no descendant (text field) holds the focus.
    if (!widget.enabled || !node.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final raw = _buffer.toString();
      _buffer.clear();
      _lastKeyAt = null;
      if (raw.isNotEmpty) widget.onScan(raw);
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (character == null || character.isEmpty) return KeyEventResult.ignored;
    final ascii = toAsciiDigits(character);
    if (!_digit.hasMatch(ascii)) return KeyEventResult.ignored;
    final now = DateTime.now();
    final last = _lastKeyAt;
    if (last != null &&
        now.difference(last) > WedgeScanListener.interKeyTimeout) {
      _buffer.clear();
    }
    _lastKeyAt = now;
    if (_buffer.length < WedgeScanListener.maxLength) _buffer.write(ascii);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: true,
      onKeyEvent: _onKey,
      child: widget.child,
    );
  }
}
