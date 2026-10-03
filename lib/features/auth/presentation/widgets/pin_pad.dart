import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Numeric keypad with dot indicators. Calls [onCompleted] once [length]
/// digits are entered, then clears itself.
class PinPad extends StatefulWidget {
  const PinPad({required this.onCompleted, this.length = 6, this.enabled = true, this.leading, super.key});

  final int length;
  final bool enabled;
  final ValueChanged<String> onCompleted;

  /// Optional button in the bottom-left slot (e.g. biometrics).
  final Widget? leading;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';

  void _press(String digit) {
    if (!widget.enabled || _pin.length >= widget.length) return;
    unawaitedHaptic();
    setState(() => _pin += digit);
    if (_pin.length == widget.length) {
      final pin = _pin;
      setState(() => _pin = '');
      widget.onCompleted(pin);
    }
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void unawaitedHaptic() => HapticFeedback.selectionClick().ignore();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String digit) => _PadButton(
      onPressed: () => _press(digit),
      child: Text(digit, style: Theme.of(context).textTheme.headlineSmall),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '${_pin.length} of ${widget.length}',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? scheme.primary : Colors.transparent,
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        // Keypads are never mirrored in RTL.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                Row(mainAxisAlignment: MainAxisAlignment.center, children: row.map(key).toList()),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 88, height: 72, child: widget.leading),
                  key('0'),
                  _PadButton(onPressed: _backspace, child: const Icon(Icons.backspace_outlined)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({required this.onPressed, required this.child});

  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 88,
    height: 72,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(shape: const CircleBorder()),
      child: child,
    ),
  );
}
