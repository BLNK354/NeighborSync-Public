import '../core/field_rules.dart';
import 'package:flutter/material.dart';
import '../core/branding.dart';
import '../core/form_helpers.dart';
import 'package:go_router/go_router.dart';
import '../core/roles.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_screen_scaffold.dart';
import '../widgets/legal_documents.dart';
import '../widgets/password_feedback.dart';
import '../core/safe_state.dart';

/// Sign-up form with a two-column field grid.
/// Every signup gets [defaultSelfServiceRole]; the approving officer sets
/// the real role and the unit later.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with SafeSetState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _suffixCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  /// Hidden bot trap. People can't see or reach it; a script that fills
  /// every input will fill it, and the server rejects those signups.
  final _hpCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePw = true;
  bool _obscureConfirm = true;
  String? _error;

  /// Required consent. The terms version is sent with the signup and the
  /// database records it on the profile (see handle_new_auth_user()).
  bool _acceptedTerms = false;

  /// Agree checkbox with links that open the documents in a dialog.
  /// Keep it a dialog: leaving this route would wipe the typed fields.
  Widget _termsCheckbox() {
    return ListenableBuilder(
      listenable: AppBranding.instance,
      builder: (context, _) {
        final b = AppBranding.instance;
        final link = TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.sidebarActiveText,
          decoration: TextDecoration.underline,
        );
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          decoration: BoxDecoration(
            border: Border.all(
                color: _acceptedTerms
                    ? const Color(0xFFD9D9DB)
                    : Colors.redAccent
                        .withValues(alpha: _error == null ? 0.0 : 0.55)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _acceptedTerms,
                onChanged: (v) => setState(() {
                  _acceptedTerms = v ?? false;
                  // Clear the terms error as soon as the box is ticked.
                  if (_acceptedTerms && _error == _kTermsError) _error = null;
                }),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('I have read and agree to the ',
                          style: TextStyle(
                              fontSize: 12.5, color: Color(0xFF5C5C66))),
                      if (b.hasTerms)
                        InkWell(
                          onTap: () =>
                              showLegalDocument(context, LegalDoc.terms),
                          child: Text(b.termsTitle, style: link),
                        )
                      else
                        Text(b.termsTitle,
                            style: const TextStyle(
                                fontSize: 12.5, color: Color(0xFF5C5C66))),
                      const Text(' and the ',
                          style: TextStyle(
                              fontSize: 12.5, color: Color(0xFF5C5C66))),
                      if (b.hasPrivacy)
                        InkWell(
                          onTap: () =>
                              showLegalDocument(context, LegalDoc.privacy),
                          child: Text(b.privacyTitle, style: link),
                        )
                      else
                        Text(b.privacyTitle,
                            style: const TextStyle(
                                fontSize: 12.5, color: Color(0xFF5C5C66))),
                      const Text('.',
                          style: TextStyle(
                              fontSize: 12.5, color: Color(0xFF5C5C66))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static const _kTermsError =
      'Please read and agree to the terms before creating an account.';

  /// The hidden bot-trap field. Keep it out of screen readers, out of tab
  /// order and zero-size, or real people could fill it. Leave autofillHints
  /// unset so password managers ignore it.
  Widget _honeypot() {
    return ExcludeSemantics(
      child: Offstage(
        child: SizedBox(
          height: 0,
          width: 0,
          child: TextField(
            controller: _hpCtrl,
            focusNode: FocusNode(skipTraversal: true, canRequestFocus: false),
            canRequestFocus: false,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Website',
              counterText: '',
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Checked after the field validators so field errors show first.
    if (!_acceptedTerms) {
      setState(() => _error = _kTermsError);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await SupabaseService.instance.register(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        middleName: _middleNameCtrl.text.trim(),
        suffix: _suffixCtrl.text.trim(),
        phoneNumber: normalizePhone(_phoneCtrl.text),
        role: defaultSelfServiceRole,
        termsVersion: AppBranding.instance.legalVersion,
        honeypot: _hpCtrl.text,
        // Sent with the signup so the confirmation email can show the
        // association's name.
        communityName: AppBranding.instance.communityName,
      );
      if (mounted) context.go('/verify-email');
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _suffixCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _hpCtrl.dispose();
    super.dispose();
  }

  static const _fieldLabelStyle = TextStyle(
      fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFF5C5C66));

  /// A field with its label above it.
  Widget _labeled(String label, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _fieldLabelStyle),
        const SizedBox(height: 6),
        field,
      ],
    );
  }

  /// Two fields side by side, or stacked when the row is under 380px wide.
  /// It checks the row's own width, not the screen's.
  Widget _row(Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 380) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 16), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 16),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScreenScaffold(
      brandPanelBreakpoint: 980,
      maxContentWidth: 460,
      showBackToHome: true,
      formKey: _formKey,
      children: [
        Text('Create your account',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        const Text('Join your community on NeighborSync',
            style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
        const SizedBox(height: 28),
        _row(
          _labeled(
            'First Name',
            TextFormField(
              controller: _firstNameCtrl,
              inputFormatters: nameInputFormatters,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'First name is required'
                  : nameRule(v, const {}),
            ),
          ),
          _labeled(
            'Last Name',
            TextFormField(
              controller: _lastNameCtrl,
              inputFormatters: nameInputFormatters,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Last name is required'
                  : nameRule(v, const {}),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _row(
          _labeled('Middle Name (optional)',
              TextFormField(controller: _middleNameCtrl)),
          _labeled('Suffix (optional)', TextFormField(controller: _suffixCtrl)),
        ),
        const SizedBox(height: 16),
        _labeled(
          'Email Address',
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            validator: emailError,
          ),
        ),
        const SizedBox(height: 16),
        _labeled(
          'Phone Number',
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: phoneInputFormatters,
            decoration: const InputDecoration(hintText: '09XXXXXXXXX'),
            validator: phoneError,
          ),
        ),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('So the HOA office and the guardhouse can reach you.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ),
        const SizedBox(height: 16),
        _row(
          _labeled(
            'Password',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePw,
                  decoration: InputDecoration(
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscurePw
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: AppColors.textMuted),
                      onPressed: () => setState(() => _obscurePw = !_obscurePw),
                    ),
                  ),
                  // Mirrors the Supabase password policy, so rules fail here
                  // instead of as a raw API error.
                  validator: passwordError,
                ),
                // Advice only; passwordError above is the real check.
                PasswordStrengthBar(controller: _passwordCtrl),
              ],
            ),
          ),
          _labeled(
            'Confirm Password',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _confirmPasswordCtrl,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: AppColors.textMuted),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) =>
                      v != _passwordCtrl.text ? 'Passwords do not match' : null,
                ),
                PasswordMatchNote(
                  passwordController: _passwordCtrl,
                  confirmController: _confirmPasswordCtrl,
                ),
              ],
            ),
          ),
        ),
        // Under the whole row because _row() takes exactly two children.
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(kPasswordHint,
              style: TextStyle(
                  fontSize: 11.5, color: AppColors.textMuted, height: 1.35)),
        ),
        _honeypot(),
        const SizedBox(height: 20),
        _termsCheckbox(),
        const SizedBox(height: 20),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(_error!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
          ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Create Account'),
        ),
        const SizedBox(height: 24),
        const Divider(color: Color(0xFFD9D9DB), height: 1),
        const SizedBox(height: 20),
        InkWell(
          onTap: () => context.go('/login'),
          child: Text.rich(
            TextSpan(
              text: 'Already have an account? ',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF5C5C66)),
              children: [
                TextSpan(
                  text: 'Log In',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.sidebarActiveText),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
