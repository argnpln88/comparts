import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';

class QuantityInput extends StatefulWidget {
  const QuantityInput({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onValidityChanged,
    this.enabled = true,
  });
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final ValueChanged<bool> onValidityChanged;

  @override
  State<QuantityInput> createState() => _QuantityInputState();
}

class _QuantityInputState extends State<QuantityInput>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late final _controller = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(covariant QuantityInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        int.tryParse(_controller.text) != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _valid(String text) {
    final value = int.tryParse(text);
    return value != null && value >= 1 && value <= 20;
  }

  void _change(String text) {
    final valid = _valid(text);
    widget.onValidityChanged(valid);
    if (valid) widget.onChanged(int.parse(text));
    setState(() {});
  }

  void _step(int direction) {
    final current = int.tryParse(_controller.text);
    final value =
        ((current != null && current >= 1 && current <= 20
                    ? current
                    : widget.value) +
                direction)
            .clamp(1, 20);
    _controller.text = '$value';
    _change('$value');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final value = int.tryParse(_controller.text) ?? widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quantity',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '1–20 items',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              key: const Key('quantity-minus'),
              tooltip: 'Decrease quantity',
              onPressed: widget.enabled && value > 1 ? () => _step(-1) : null,
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: const Color(0xFFEDF3FF),
                foregroundColor: blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.remove),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: TextFormField(
                key: const Key('quantity-input'),
                controller: _controller,
                enabled: widget.enabled,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: ink,
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  semanticCounterText: 'Quantity',
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                  errorStyle: TextStyle(height: 0, fontSize: 0),
                ),
                onChanged: _change,
                validator: (text) =>
                    _valid(text ?? '') ? null : 'Enter 1–20 items.',
                onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('quantity-plus'),
              tooltip: 'Increase quantity',
              onPressed: widget.enabled && value < 20 ? () => _step(1) : null,
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (!_valid(_controller.text))
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Enter a quantity from 1 to 20.',
              style: TextStyle(color: Color(0xFFB42318), fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class CheckoutSection extends StatelessWidget {
  const CheckoutSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE0E8F3)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x060F2C5C),
          blurRadius: 20,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFFEDF3FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: blue, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ...children,
      ],
    ),
  );
}
