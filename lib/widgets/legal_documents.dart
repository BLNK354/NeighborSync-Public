import 'package:flutter/material.dart';

import '../core/branding.dart';
import '../theme/app_theme.dart';

/// The Terms and Privacy Notice, shown as a dialog or a full page.
///
/// Text comes from [AppBranding] (edited in the CMS) and must be readable
/// when signed out, since people agree to it before they have an account.

/// Which document to show.
enum LegalDoc { terms, privacy }

/// Title of [doc] from the branding settings.
String legalTitleOf(LegalDoc doc) => doc == LegalDoc.terms
    ? AppBranding.instance.termsTitle
    : AppBranding.instance.privacyTitle;

/// Body text of [doc] from the branding settings.
String legalBodyOf(LegalDoc doc) => doc == LegalDoc.terms
    ? AppBranding.instance.termsContent
    : AppBranding.instance.privacyContent;

/// Opens the document in a dialog. It is a dialog, not a page, so a
/// half-filled signup form is not lost.
Future<void> showLegalDocument(BuildContext context, LegalDoc doc) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      // 128 = AlertDialog's own padding; a fixed width would overflow a phone.
      final maxW = MediaQuery.of(ctx).size.width - 128;
      final maxH = MediaQuery.of(ctx).size.height * 0.62;
      return AlertDialog(
        title: Text(legalTitleOf(doc), style: const TextStyle(fontSize: 17)),
        content: SizedBox(
          width: maxW < 560 ? (maxW < 240 ? 240 : maxW) : 560,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(child: LegalBody(doc: doc)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

/// The document text plus the version line, shared by the dialog and page.
class LegalBody extends StatelessWidget {
  final LegalDoc doc;
  const LegalBody({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    final b = AppBranding.instance;
    final body = legalBodyOf(doc).trim();

    if (body.isEmpty) {
      // Say what is missing instead of showing a blank page.
      return Text(
        'The ${legalTitleOf(doc).toLowerCase()} has not been published yet. '
        'An HOA officer can add it in Settings → CMS → Legal.',
        style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.textMuted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One block per paragraph, lead heading in bold; text is selectable.
        SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final para in body.split(RegExp(r'\n\s*\n')))
                if (para.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _paragraph(para.trim()),
                  ),
            ],
          ),
        ),
        if (b.legalVersion.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Text(
            'Version ${b.legalVersion} · ${b.communityName}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }
}

/// "3. Accurate information. The addresses..." -> the lead in bold.
/// A paragraph with nothing after its first sentence stays plain.
final _leadHeading = RegExp(r'^((?:\d+\.\s+)?[^.\n]{2,60}\.)\s+(\S[\s\S]*)$');

Widget _paragraph(String para) {
  const base = TextStyle(fontSize: 14.5, height: 1.7, color: AppColors.textPrimary);
  final m = _leadHeading.firstMatch(para);
  if (m == null) return Text(para, style: base);
  return Text.rich(TextSpan(style: base, children: [
    TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)),
    TextSpan(text: ' ${m.group(2)}'),
  ]));
}

/// Public page at `/terms` and `/privacy`. Updates live when branding changes.
class LegalPage extends StatelessWidget {
  final LegalDoc doc;
  const LegalPage({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: ListenableBuilder(
          listenable: AppBranding.instance,
          builder: (context, _) => Text(legalTitleOf(doc),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
      body: ListenableBuilder(
        listenable: AppBranding.instance,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: LegalBody(doc: doc),
            ),
          ),
        ),
      ),
    );
  }
}

/// Terms and Privacy links for public pages (landing footer, visitor page).
/// Each opens the same dialog as the register form.
class LegalLinks extends StatelessWidget {
  final Color? color;
  const LegalLinks({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: color ?? AppColors.textSecondary,
      decoration: TextDecoration.underline,
      decorationColor: color ?? AppColors.textSecondary,
    );
    Widget link(LegalDoc doc) => Semantics(
          link: true,
          child: InkWell(
            onTap: () => showLegalDocument(context, doc),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: ListenableBuilder(
                listenable: AppBranding.instance,
                builder: (context, _) => Text(legalTitleOf(doc), style: style),
              ),
            ),
          ),
        );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        link(LegalDoc.terms),
        Text('·', style: TextStyle(fontSize: 12, color: color ?? AppColors.textMuted)),
        link(LegalDoc.privacy),
      ],
    );
  }
}
