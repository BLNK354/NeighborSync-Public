import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/form_helpers.dart';
import '../theme/app_theme.dart';

/// The kinds of failed request, each with a plain title and what to do next.
enum RequestErrorKind {
  /// 400 -- the request was refused (bad value or filter).
  badRequest('400', 'That request could not be completed',
      'Something in the request was not accepted. Try again; if it keeps '
          'happening, tell the HOA office what you were doing.'),

  /// 401 -- signed out or the session expired.
  unauthorized('401', 'Please sign in again',
      'Your session has ended. Sign in again to carry on.'),

  /// 403 -- signed in, but this account may not do that.
  forbidden('403', 'You do not have access to this',
      'Your account is not allowed to open or change this. If you think it '
          'should be, ask the HOA office.'),

  /// 404 -- the record is gone or belongs to another phase.
  missing('404', 'That record is not available',
      'It may have been removed, or it belongs to another phase.'),

  /// No connection at all.
  offline('', 'You appear to be offline',
      'Check your internet connection, then try again.'),

  /// 5xx or anything unrecognised.
  server('500', 'Something went wrong on our side',
      'The server could not answer just now. Wait a moment and try again.');

  final String code;
  final String title;
  final String help;
  const RequestErrorKind(this.code, this.title, this.help);

  static RequestErrorKind fromCode(String? code) => switch (code) {
        '400' => badRequest,
        '401' => unauthorized,
        '403' => forbidden,
        '404' => missing,
        'offline' => offline,
        _ => server,
      };

  /// Best guess from a thrown error. Database errors carry a SQLSTATE or
  /// PGRST code, not the HTTP status, so they are mapped by code family.
  static RequestErrorKind of(Object error) {
    final text = error.toString().toLowerCase();
    if (error is AuthException) {
      final s = error.statusCode ?? '';
      if (s == '401') return unauthorized;
      if (s == '403') return forbidden;
      return s.startsWith('4') ? badRequest : server;
    }
    if (error is PostgrestException) {
      final c = error.code ?? '';
      if (c == '42501' || c == 'PGRST301' || c == 'PGRST302') return forbidden;
      if (c == 'PGRST116') return missing;
      if (c.startsWith('PGRST1') || c.startsWith('22') || c.startsWith('23')) {
        return badRequest;
      }
      return server;
    }
    if (text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('clientexception') ||
        text.contains('failed to fetch') ||
        text.contains('network')) {
      return offline;
    }
    return server;
  }
}

/// Shows a failed request in place of the content that could not load.
/// [detail] is an optional specific sentence shown under the standard help.
class RequestErrorView extends StatelessWidget {
  final RequestErrorKind kind;
  final String? detail;
  final VoidCallback? onRetry;
  final String retryLabel;
  final Widget? extra;

  const RequestErrorView({
    super.key,
    required this.kind,
    this.detail,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.extra,
  });

  /// Builds the view straight from a caught error.
  factory RequestErrorView.fromError(Object error, {VoidCallback? onRetry}) =>
      RequestErrorView(
        kind: RequestErrorKind.of(error),
        detail: friendlyError(error),
        onRetry: onRetry,
      );

  @override
  Widget build(BuildContext context) {
    final showDetail = (detail ?? '').trim().isNotEmpty &&
        detail!.trim() != kind.help &&
        !detail!.toLowerCase().startsWith('something went wrong');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.badgeAmberBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  kind == RequestErrorKind.offline
                      ? Icons.wifi_off_rounded
                      : kind == RequestErrorKind.forbidden
                          ? Icons.lock_outline
                          : Icons.error_outline,
                  color: AppColors.badgeAmberText,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(kind.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text(kind.help,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13.5, height: 1.5, color: AppColors.textMuted)),
              if (showDetail) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.contentBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(detail!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary)),
                ),
              ],
              if (kind.code.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Error ${kind.code}',
                    style: const TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 0.4,
                        color: AppColors.textMuted)),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(retryLabel),
                ),
              ],
              if (extra != null) ...[const SizedBox(height: 8), extra!],
            ],
          ),
        ),
      ),
    );
  }
}
