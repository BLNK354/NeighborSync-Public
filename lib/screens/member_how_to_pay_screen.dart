import 'package:flutter/material.dart';
import '../theme/resident_theme.dart';
import '../widgets/member_shell.dart';
import '../widgets/payment_channels_view.dart';

/// "How to Pay": the association's GCash, Maya and bank accounts with QR
/// codes. It needs no bill, unlike the pay-one-bill screen.
/// The database limits which accounts a resident sees (their phase plus
/// shared ones), not this screen.
class MemberHowToPayScreen extends StatelessWidget {
  const MemberHowToPayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MemberShell(
      title: 'How to Pay',
      activeItem: 'How to Pay',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 30, 32, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          // Everything below is const; inner `const` is implied, and adding it trips `unnecessary_const`.
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Where to send your dues',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: ResidentColors.textPrimary)),
              SizedBox(height: 6),
              // Next step: the receipt must be sent so the treasurer can match it to a bill.
              Text(
                'Pay through any of the accounts below, then send your '
                'receipt from My Payments so the treasurer can match it to '
                'your bill.',
                style: TextStyle(
                    fontSize: 12.5,
                    color: ResidentColors.textSecondary,
                    height: 1.45),
              ),
              SizedBox(height: 20),
              PaymentChannelsView(),
            ],
          ),
        ),
      ),
    );
  }
}
