import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/error_codes.dart';
import '../../../../core/auth/account_generation.dart';
import '../../../../core/result.dart';
import '../../../auth/data/profile_repository.dart';
import '../../../auth/domain/dob_validator.dart';

/// Collects DOB without leaving the selected trip or submitting another booking.
class BookingDobDialog extends ConsumerStatefulWidget {
  const BookingDobDialog({super.key});

  @override
  ConsumerState<BookingDobDialog> createState() => _BookingDobDialogState();
}

class _BookingDobDialogState extends ConsumerState<BookingDobDialog> {
  late final int _generation;
  DateTime? _date;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _generation = ref.read(accountGenerationProvider);
  }

  bool get _sameAccount =>
      mounted && _generation == ref.read(accountGenerationProvider);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select your date of birth',
    );
    if (!_sameAccount || picked == null) return;
    setState(() {
      _date = picked;
      _error = DobValidator.validate(picked);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_sameAccount) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final invalid = DobValidator.validate(_date);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await ref
        .read(profileRepositoryProvider)
        .patch(dateOfBirth: DobValidator.format(_date!));
    if (!mounted) return;
    if (!_sameAccount) {
      Navigator.of(context).pop();
      return;
    }
    switch (result) {
      case Ok(:final value):
        Navigator.of(context).pop(value);
      case Err(:final error):
        setState(() {
          _saving = false;
          _error = RiderErrorCopy.messageFor(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Date of birth'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add your date of birth before booking.'),
          const SizedBox(height: 12),
          const Text(
            'You must be at least 13. Once saved, contact support if you need to correct it.',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _saving ? null : _pickDate,
            child: Text(
              _date == null
                  ? 'Select date'
                  : '${_date!.day.toString().padLeft(2, '0')}/${_date!.month.toString().padLeft(2, '0')}/${_date!.year}',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving...' : 'Save date of birth'),
      ),
    ],
  );
}
