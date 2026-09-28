import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/connection_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/providers.dart';
import '../../core/theme/sentinel_colors.dart';
import '../../core/theme/tokens.dart';

/// First-run screen (PRD §4.1, DESIGN_BRIEF §9.1). On success the router
/// redirects to the Briefing tab automatically.
class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController(text: kDefaultServerUrl);
  final _token = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(connectionProvider.notifier)
          .connect(_url.text, _token.text);
      await ref.read(notificationServiceProvider).requestPermission();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pasteToken() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) _token.text = text;
  }

  void _showTokenHelp() {
    showModalBottomSheet<void>(
      context: context,
      // Above the shell's floating nav pill, not inside the tab navigator.
      useRootNavigator: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.s6, 0, Space.s6, Space.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Where is the token?', style: context.text.titleLarge),
            const SizedBox(height: Space.s3),
            Text(
              'Open the .env file of Email Sentinel on your PC and copy the '
              'value of SENTINEL_API_TOKEN. Hermes can also show it: ask '
              '"what is the Sentinel API token?".',
              style: context.text.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gutter = Space.gutter(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: gutter,
              vertical: Space.s8,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 48,
                      color: colors.primary,
                    ),
                    const SizedBox(height: Space.s6),
                    Text(
                      'Connect to Sentinel',
                      style: context.text.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Space.s2),
                    Text(
                      'Your phone must be connected to Tailscale.',
                      style: context.text.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Space.s8),
                    TextFormField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Server URL',
                      ),
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
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ],
                        ),
                      ),
                      validator: (v) => ConnectionConfig.validateToken(v ?? ''),
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Space.s3),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: context.text.bodyMedium?.copyWith(
                            color: colors.error,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.s6),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Test & connect'),
                    ),
                    const SizedBox(height: Space.s2),
                    TextButton(
                      onPressed: _showTokenHelp,
                      child: const Text('Where do I find the token?'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
