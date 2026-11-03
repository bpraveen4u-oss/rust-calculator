import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';
import '../guardian_access.dart';

class GuardianControlsPage extends StatefulWidget {
  const GuardianControlsPage({
    required this.guardianAccess,
    required this.syncClient,
    required this.localProfileId,
    super.key,
  });

  final GuardianAccess guardianAccess;
  final SyncClient syncClient;
  final String localProfileId;

  @override
  State<GuardianControlsPage> createState() => _GuardianControlsPageState();
}

class _GuardianControlsPageState extends State<GuardianControlsPage> {
  late final Future<bool> _hasPin;
  late final Future<bool> _canUseBiometrics;
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _pairingCodeController = TextEditingController();
  String? _message;
  String? _createdCode;
  bool _isUnlocked = false;
  bool _pairingRequested = false;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _hasPin = widget.guardianAccess.hasPin();
    _canUseBiometrics = widget.guardianAccess.canUseBiometrics();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    _pairingCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guardian controls')),
      body: FutureBuilder<bool>(
        future: _hasPin,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text('Guardian protection is unavailable on this device.'),
            );
          }
          if (_isUnlocked) return _buildControls(context);
          if (snapshot.data ?? false) return _buildUnlock();
          return _buildPinSetup();
        },
      ),
    );
  }

  Widget _buildPinSetup() {
    return _form(
      title: 'Protect guardian controls',
      description: 'Create a six-digit PIN to restrict device-linking settings.',
      fields: [
        _pinField(
          controller: _pinController,
          key: const Key('guardian-pin'),
          label: 'Guardian PIN',
        ),
        const SizedBox(height: 12),
        _pinField(
          controller: _confirmPinController,
          key: const Key('guardian-pin-confirm'),
          label: 'Confirm PIN',
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('guardian-save-pin'),
          onPressed: _isBusy ? null : _savePin,
          child: const Text('Set guardian PIN'),
        ),
      ],
    );
  }

  Widget _buildUnlock() {
    return _form(
      title: 'Unlock guardian controls',
      description: 'Enter the guardian PIN to continue.',
      fields: [
        _pinField(
          controller: _pinController,
          key: const Key('guardian-unlock-pin'),
          label: 'Guardian PIN',
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('guardian-unlock'),
          onPressed: _isBusy ? null : _unlockWithPin,
          child: const Text('Unlock'),
        ),
        FutureBuilder<bool>(
          future: _canUseBiometrics,
          builder: (context, snapshot) {
            if (snapshot.data != true) return const SizedBox.shrink();
            return TextButton(
              onPressed: _isBusy ? null : _unlockWithBiometrics,
              child: const Text('Use biometrics'),
            );
          },
        ),
      ],
    );
  }

  Widget _form({
    required String title,
    required String description,
    required List<Widget> fields,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 20),
            ...fields,
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                key: const Key('guardian-message'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pinField({
    required TextEditingController controller,
    required Key key,
    required String label,
  }) {
    return TextField(
      key: key,
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 6,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        counterText: '',
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Device linking and cloud data',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              'Pairing is optional and starts only when a guardian requests it. '
              'If paired, the pseudonymous profile ID, grade, and calculation '
              'history (expression, result, timestamp, and topic) would leave '
              'this device.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Each synced history entry is deleted 90 days after recording. '
              'Empty cloud profile metadata expires after 90 days without '
              'linked-device activity. Local history remains on this device '
              'until cleared.',
            ),
            const SizedBox(height: 12),
            const Text(
              'There is no recovery key. If every linked device is lost, '
              'progress cannot be restored.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Production cloud sync remains disabled pending legal/privacy '
              'review. The explicitly enabled local test configuration must '
              'never be used with real learner data.',
              key: Key('guardian-sync-disabled'),
            ),
            const SizedBox(height: 8),
            const Text(
              'This acknowledgement does not provide consent or enable sync.',
            ),
            CheckboxListTile(
              key: const Key('guardian-pairing-opt-in'),
              value: _pairingRequested,
              contentPadding: EdgeInsets.zero,
              title: const Text('I want to start the pairing flow'),
              onChanged: (requested) {
                setState(() {
                  _pairingRequested = requested ?? false;
                  _message = null;
                });
              },
            ),
            FilledButton(
              key: const Key('guardian-start-pairing'),
              onPressed: _pairingRequested ? _requestPairing : null,
              child: const Text('Continue to device pairing'),
            ),
            if (_pairingRequested && widget.syncClient.pairingAvailable) ...[
              const SizedBox(height: 12),
              const Text(
                'Enter the one-time code shown in guardian controls on an '
                'already paired device. It expires after about ten minutes.',
              ),
              TextField(
                key: const Key('guardian-pairing-code'),
                controller: _pairingCodeController,
                textCapitalization: TextCapitalization.characters,
                maxLength: 16,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Pairing code',
                ),
              ),
              FilledButton(
                key: const Key('guardian-submit-pairing-code'),
                onPressed: _isBusy ? null : _submitPairingCode,
                child: const Text('Pair this device'),
              ),
              OutlinedButton(
                key: const Key('guardian-create-pairing-code'),
                onPressed: _isBusy ? null : _createPairingCode,
                child: const Text('Create a code for another device'),
              ),
              if (_createdCode case final code?)
                SelectableText(
                  code,
                  key: const Key('guardian-created-pairing-code'),
                ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, key: const Key('guardian-message')),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _savePin() async {
    final pin = _pinController.text;
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      setState(() => _message = 'Enter a six-digit PIN.');
      return;
    }
    if (pin != _confirmPinController.text) {
      setState(() => _message = 'PINs do not match.');
      return;
    }
    setState(() {
      _isBusy = true;
      _message = null;
    });
    try {
      await widget.guardianAccess.setPin(pin);
      if (mounted) setState(() => _isUnlocked = true);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Could not save the PIN on this device.');
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _unlockWithPin() async {
    setState(() {
      _isBusy = true;
      _message = null;
    });
    try {
      final verified = await widget.guardianAccess.verifyPin(
        _pinController.text,
      );
      if (mounted) {
        setState(() {
          _isUnlocked = verified;
          _message = verified ? null : 'Incorrect PIN.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Could not verify the PIN on this device.');
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _unlockWithBiometrics() async {
    setState(() {
      _isBusy = true;
      _message = null;
    });
    try {
      final verified =
          await widget.guardianAccess.authenticateWithBiometrics();
      if (mounted) {
        setState(() {
          _isUnlocked = verified;
          _message = verified ? null : 'Biometric unlock was not completed.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Biometric unlock is unavailable on this device.',
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _requestPairing() {
    setState(() {
      _message = widget.syncClient.pairingAvailable
          ? null
          : 'Pairing is not available in this experiment.';
      _createdCode = null;
    });
  }

  Future<void> _submitPairingCode() async {
    setState(() {
      _isBusy = true;
      _message = null;
    });
    try {
      await widget.syncClient.pairDevice(
        widget.localProfileId,
        _pairingCodeController.text,
      );
      if (mounted) {
        setState(() {
          _pairingCodeController.clear();
          _message = 'Device paired. Sync will continue when connected.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Could not pair this device. Check the code and '
              'connection, then try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _createPairingCode() async {
    setState(() {
      _isBusy = true;
      _message = null;
      _createdCode = null;
    });
    try {
      final code = await widget.syncClient.createPairingCode(
        widget.localProfileId,
      );
      if (mounted) {
        setState(() {
          _createdCode = code;
          _message = 'Enter this code on the other device before it expires.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Could not create a pairing code. Pair this device first '
              'and check the connection.';
        });
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }
}
