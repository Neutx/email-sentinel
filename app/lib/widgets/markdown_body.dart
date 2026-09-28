import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/sentinel_colors.dart';
import '../core/theme/tokens.dart';

class MarkdownBody extends StatelessWidget {
  const MarkdownBody({required this.data, this.maxLines, super.key});

  final String data;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = context.text;
    final colors = context.colors;

    final styleSheet = md.MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: text.bodyLarge?.copyWith(color: colors.onSurface),
      h1: text.headlineSmall?.copyWith(color: colors.onSurface),
      h2: text.titleLarge?.copyWith(color: colors.onSurface),
      h3: text.titleMedium?.copyWith(color: colors.onSurface),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: colors.onSurface,
        backgroundColor: colors.surfaceContainerHigh,
      ),
      codeblockDecoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      codeblockPadding: const EdgeInsets.all(Space.s3),
    );

    return md.MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: styleSheet,
      onTapLink: (text, href, title) {
        if (href != null) {
          final uri = Uri.tryParse(href);
          if (uri != null) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      },
    );
  }
}
