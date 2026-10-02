import 'package:flutter/material.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

/// Small attribution for the extension runtime that powers MStream and
/// MultiProviders: the AnymeX Extension Runtime Bridge by RyanYuuki.
///
/// Shown wherever the user adds or manages extensions so the runtime's
/// author is credited in-product, not just in the changelog.
class BridgeCredit extends StatelessWidget {
  const BridgeCredit({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.extension_rounded,
          size: 14,
          color: Theme.of(context).textTheme.bodySmall?.color,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            l10n.extensionRuntimeCredit,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
          ),
        ),
      ],
    );
  }
}
