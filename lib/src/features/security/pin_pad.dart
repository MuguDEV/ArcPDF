import 'dart:math';
import 'package:flutter/material.dart';

import 'package:pinput/pinput.dart';

import '../settings/haptic_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PinPad extends ConsumerStatefulWidget {
  const PinPad({
    super.key,
    required this.onCompleted,
    this.errorText,
    this.length = 4,
  });

  final ValueChanged<String> onCompleted;
  final String? errorText;
  final int length;

  @override
  ConsumerState<PinPad> createState() => _PinPadState();
}

class _PinPadState extends ConsumerState<PinPad> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onKeypadTap(String value) {
    if (_pinController.text.length < widget.length) {
      _triggerHaptic();
      _pinController.text += value;
    }
  }

  void _onBackspaceTap() {
    if (_pinController.text.isNotEmpty) {
      _triggerHaptic();
      _pinController.text = _pinController.text.substring(0, _pinController.text.length - 1);
    }
  }

  void _triggerHaptic() async {
    ref.read(hapticServiceProvider).vibrate();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);


    final defaultPinTheme = PinTheme(
      width: 56,
      height: 64,
      textStyle: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
    );

    final errorPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration?.copyWith(
        border: Border.all(color: theme.colorScheme.error),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Pinput(
          length: widget.length,
          controller: _pinController,
          focusNode: _focusNode,
          defaultPinTheme: defaultPinTheme,
          errorPinTheme: errorPinTheme,
          errorText: widget.errorText,
          forceErrorState: widget.errorText != null,
          obscureText: true,
          obscuringWidget: const _AnimatedObscureChar(),
          useNativeKeyboard: false, // We use custom keypad
          onCompleted: widget.onCompleted,
          showCursor: true,
        ),
        const SizedBox(height: 32),
        _buildKeypad(theme),
      ],
    );
  }

  Widget _buildKeypad(ThemeData theme) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      child: GridView.count(
        shrinkWrap: true,
        crossAxisCount: 3,
        childAspectRatio: 1.2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 1; i <= 9; i++) _KeypadButton(text: '$i', onTap: () => _onKeypadTap('$i')),
          const SizedBox.shrink(), // Empty space
          _KeypadButton(text: '0', onTap: () => _onKeypadTap('0')),
          _KeypadButton(icon: Icons.backspace_outlined, onTap: _onBackspaceTap),
        ],
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({this.text, this.icon, required this.onTap});

  final String? text;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        splashColor: theme.colorScheme.primary.withValues(alpha: 0.1),
        highlightColor: theme.colorScheme.primary.withValues(alpha: 0.05),
        child: Center(
          child: text != null
              ? Text(
                  text!,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w500),
                )
              : Icon(icon, size: 28, color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}

class _AnimatedObscureChar extends StatefulWidget {
  const _AnimatedObscureChar();

  @override
  State<_AnimatedObscureChar> createState() => _AnimatedObscureCharState();
}

class _AnimatedObscureCharState extends State<_AnimatedObscureChar> {
  final _chars = ['!', '@', '#', '\$', '%', '&', '*', '?', 'X', 'O'];
  late String _currentChar;
  bool _isSettled = false;

  @override
  void initState() {
    super.initState();
    _currentChar = _chars[Random().nextInt(_chars.length)];
    _startAnimation();
  }

  void _startAnimation() async {
    for (int i = 0; i < 5; i++) {
      if (!mounted) return;
      setState(() {
        _currentChar = _chars[Random().nextInt(_chars.length)];
      });
      await Future.delayed(const Duration(milliseconds: 60));
    }
    if (mounted) {
      setState(() {
        _currentChar = '●'; // Settle on dot
        _isSettled = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: Text(
        _currentChar,
        key: ValueKey(_currentChar),
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: _isSettled ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
