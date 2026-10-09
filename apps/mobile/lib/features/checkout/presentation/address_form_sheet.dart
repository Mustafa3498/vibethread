import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/address.dart';

/// Bottom sheet that returns the new address, or null if dismissed.
Future<AddressDraft?> showAddressSheet(BuildContext context) {
  return showModalBottomSheet<AddressDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _AddressForm(),
  );
}

class _AddressForm extends StatefulWidget {
  const _AddressForm();

  @override
  State<_AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends State<_AddressForm> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController(text: 'Home');
  final _line1 = TextEditingController();
  final _line2 = TextEditingController();
  final _city = TextEditingController(text: 'Karachi');
  final _state = TextEditingController(text: 'Sindh');
  final _postal = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    _line1.dispose();
    _line2.dispose();
    _city.dispose();
    _state.dispose();
    _postal.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      AddressDraft(
        label: _label.text,
        line1: _line1.text,
        line2: _line2.text,
        city: _city.text,
        state: _state.text,
        postalCode: _postal.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, 16 + bottomInset),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'New delivery address',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(hintText: 'Label (Home, Office)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _line1,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Address line 1 (house, street, block)'),
                validator: (v) =>
                    (v == null || v.trim().length < 3) ? 'Enter your street address' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _line2,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Area / landmark (optional)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _city,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: 'City'),
                      validator: (v) =>
                          (v == null || v.trim().length < 2) ? 'Enter a city' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _state,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: 'Province'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _postal,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Postal code (optional)'),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _save, child: const Text('SAVE ADDRESS')),
            ],
          ),
        ),
      ),
    );
  }
}
