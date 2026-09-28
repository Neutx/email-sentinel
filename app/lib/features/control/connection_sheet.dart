import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/connection_config.dart';
import '../../core/providers.dart';
import '../../core/theme/sentinel_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/guard.dart';

Future<void> showConnectionSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (context) => const ConnectionSheet(),
  );
}

class ConnectionSheet extends ConsumerStatefulWidget {
  const ConnectionSheet({super.key});

  @override
  ConsumerState<ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends ConsumerState<ConnectionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _url;
  late final TextEditingController _token;
  bool _obscure = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(connectionProvider).value;
    _url = TextEditingController(text: config?.baseUrl ?? kDefaultServerUrl);
    _token = TextEditingController(text: config?.token ?? '');
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final ok = await guardAction(context, () async {
      await ref
          .read(connectionProvider.notifier)
          .connect(_url.text, _token.text);
    });
    if (mounted) {
      setState(() => _busy = false);
      if (ok) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _pasteToken() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) _token.text = text;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.gutter(context),
        Space.s2,
        Space.gutter(context),
        bottomInset + bottomPadding + Space.s6,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Server connection', style: context.text.titleLarge),
            const SizedBox(height: Space.s2),
            Text(
              'Edit Sentinel server URL and API token.',
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Space.s6),
            TextFormField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Server URL'),
              validator: (v) => ConnectionConfig.validateUrl(v ?? ''),
            ),
            const SizedBox(height: Space.s4),
            TextFormField(
              controller: _token,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'API token',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Paste token',
                      icon: const Icon(Icons.content_paste_rounded),
                      onPressed: _pasteToken,
                    ),
                    IconButton(
                      tooltip: _obscure ? 'Show token' : 'Hide token',
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ],
                ),
              ),
              validator: (v) => ConnectionConfig.validateToken(v ?? ''),
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Space.s6),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save & reconnect'),
            ),
          ],
        ),
      ),
    );
  }
}
