/// WHAT: Renders a reusable message composer for request-thread replies.
/// WHY: Customer and staff screens both need the same small send-message control with consistent button states.
/// HOW: Accept an external controller plus submit callback and render a chat-style composer with a compact send affordance.
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class RequestMessageComposer extends StatelessWidget {
  const RequestMessageComposer({
    super.key,
    required this.controller,
    required this.hintText,
    required this.buttonLabel,
    required this.isSubmitting,
    required this.isEnabled,
    required this.onSubmit,
    this.leadingActions = const <Widget>[],
    this.dark = false,
  });

  final TextEditingController controller;
  final String hintText;
  final String buttonLabel;
  final bool isSubmitting;
  final bool isEnabled;
  final VoidCallback onSubmit;
  final List<Widget> leadingActions;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark
            ? AppTheme.darkPage
            : AppTheme.shell.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: dark
              ? AppTheme.darkBorder
              : AppTheme.border.withValues(alpha: 0.56),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: (dark ? Colors.black : AppTheme.ink).withValues(
              alpha: dark ? 0.18 : 0.04,
            ),
            blurRadius: dark ? 16 : 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (leadingActions.isNotEmpty) ...<Widget>[
              ...leadingActions.expand<Widget>((Widget action) sync* {
                yield action;
                yield const SizedBox(width: 8);
              }),
            ],
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder:
                    (BuildContext context, TextEditingValue value, Widget? _) {
                      final hasText = value.text.trim().isNotEmpty;
                      final canSubmit = isEnabled && !isSubmitting && hasText;

                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: dark
                              ? AppTheme.darkText.withValues(
                                  alpha: canSubmit ? 0.98 : 0.74,
                                )
                              : AppTheme.shellMuted.withValues(
                                  alpha: canSubmit ? 0.86 : 0.7,
                                ),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: dark
                                ? AppTheme.darkText.withValues(alpha: 0.05)
                                : AppTheme.border.withValues(alpha: 0.42),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: TextField(
                                  controller: controller,
                                  enabled: isEnabled && !isSubmitting,
                                  minLines: 1,
                                  maxLines: 5,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  textInputAction: TextInputAction.send,
                                  decoration: InputDecoration(
                                    isCollapsed: true,
                                    border: InputBorder.none,
                                    hintText: hintText,
                                    hintStyle: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: dark
                                              ? Colors.black.withValues(
                                                  alpha: 0.42,
                                                )
                                              : AppTheme.textMuted,
                                        ),
                                    filled: false,
                                  ),
                                  style: TextStyle(
                                    color: dark ? Colors.black : AppTheme.ink,
                                  ),
                                  onSubmitted: (_) {
                                    if (canSubmit) {
                                      onSubmit();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
              ),
            ),
            const SizedBox(width: 10),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder:
                  (BuildContext context, TextEditingValue value, Widget? _) {
                    final hasText = value.text.trim().isNotEmpty;
                    final canSubmit = isEnabled && !isSubmitting && hasText;

                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            canSubmit
                                ? (dark ? AppTheme.darkAccent : AppTheme.cobalt)
                                : (dark
                                      ? AppTheme.darkAccent.withValues(
                                          alpha: 0.45,
                                        )
                                      : AppTheme.cobalt.withValues(
                                          alpha: 0.45,
                                        )),
                            canSubmit
                                ? (dark
                                      ? AppTheme.darkAccentSurface
                                      : AppTheme.cobalt.withValues(alpha: 0.82))
                                : (dark
                                      ? AppTheme.darkAccentSurface.withValues(
                                          alpha: 0.72,
                                        )
                                      : AppTheme.cobalt.withValues(
                                          alpha: 0.35,
                                        )),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: canSubmit
                            ? <BoxShadow>[
                                BoxShadow(
                                  color:
                                      (dark
                                              ? AppTheme.darkAccent
                                              : AppTheme.cobalt)
                                          .withValues(alpha: 0.24),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ]
                            : null,
                      ),
                      child: IconButton(
                        tooltip: buttonLabel,
                        onPressed: canSubmit ? onSubmit : null,
                        icon: Icon(
                          isSubmitting
                              ? Icons.more_horiz_rounded
                              : Icons.send_rounded,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
            ),
          ],
        ),
      ),
    );
  }
}
