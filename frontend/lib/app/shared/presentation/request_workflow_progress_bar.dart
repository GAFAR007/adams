library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_language.dart';
import '../../core/models/service_request_model.dart';
import '../../theme/app_theme.dart';

class RequestWorkflowProgressBar extends ConsumerWidget {
  const RequestWorkflowProgressBar({
    super.key,
    required this.request,
    this.dark = false,
  });

  final ServiceRequestModel request;
  final bool dark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    final progress = _deriveWorkflowProgress(request);
    final ownership = _resolveWorkflowOwnership(
      progress.currentStep.definition.key,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              for (var index = 0; index < progress.steps.length; index += 1)
                _WorkflowStepItem(
                  step: progress.steps[index],
                  dark: dark,
                  language: language,
                  showConnector: index != progress.steps.length - 1,
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: <Widget>[
            _WorkflowOwnerPill(
              dark: dark,
              language: language,
              label: _ownerLineLabelCurrent,
              owner: ownership.currentOwner,
            ),
            if (ownership.nextOwner != null)
              _WorkflowOwnerPill(
                dark: dark,
                language: language,
                label: _ownerLineLabelNext,
                owner: ownership.nextOwner!,
              ),
          ],
        ),
      ],
    );
  }
}

class _WorkflowOwnerPill extends StatelessWidget {
  const _WorkflowOwnerPill({
    required this.dark,
    required this.language,
    required this.label,
    required this.owner,
  });

  final bool dark;
  final AppLanguage language;
  final _WorkflowOwnerLineLabel label;
  final _WorkflowOwner owner;

  @override
  Widget build(BuildContext context) {
    final foreground = dark
        ? Colors.white.withValues(alpha: 0.84)
        : AppTheme.ink.withValues(alpha: 0.82);
    final secondary = dark
        ? Colors.white.withValues(alpha: 0.56)
        : AppTheme.ink.withValues(alpha: 0.56);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.05)
            : AppTheme.shell.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : AppTheme.border.withValues(alpha: 0.72),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: RichText(
          text: TextSpan(
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontSize: 10, height: 1.0),
            children: <InlineSpan>[
              TextSpan(
                text: label.labelFor(language),
                style: TextStyle(color: secondary, fontWeight: FontWeight.w600),
              ),
              TextSpan(
                text: owner.labelFor(language),
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkflowStepItem extends StatelessWidget {
  const _WorkflowStepItem({
    required this.step,
    required this.dark,
    required this.language,
    required this.showConnector,
  });

  final _ResolvedWorkflowStep step;
  final bool dark;
  final AppLanguage language;
  final bool showConnector;

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(step.state);
    final foreground = style.foreground;
    final textColor = dark
        ? Colors.white.withValues(
            alpha: step.state == _WorkflowStepVisualState.future ? 0.5 : 0.88,
          )
        : AppTheme.ink.withValues(
            alpha: step.state == _WorkflowStepVisualState.future ? 0.46 : 0.82,
          );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Icon(_iconFor(step.state), size: 14, color: foreground),
        const SizedBox(width: 4),
        Text(
          step.labelFor(language),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: textColor,
            fontWeight: step.isCurrent ? FontWeight.w700 : FontWeight.w600,
            height: 1.0,
          ),
        ),
        if (showConnector) ...<Widget>[
          const SizedBox(width: 8),
          Container(
            width: 18,
            height: 2,
            color: step.state == _WorkflowStepVisualState.completed
                ? const Color(0xFF5EBB7F)
                : dark
                ? Colors.white.withValues(alpha: 0.14)
                : AppTheme.border.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }

  IconData _iconFor(_WorkflowStepVisualState state) {
    switch (state) {
      case _WorkflowStepVisualState.completed:
        return Icons.check_rounded;
      case _WorkflowStepVisualState.waitingCustomer:
        return Icons.schedule_rounded;
      case _WorkflowStepVisualState.paymentActive:
        return Icons.payments_rounded;
      case _WorkflowStepVisualState.blocked:
        return Icons.lock_clock_rounded;
      case _WorkflowStepVisualState.current:
        return Icons.adjust_rounded;
      case _WorkflowStepVisualState.future:
        return Icons.circle;
    }
  }

  _WorkflowStepStyle _styleFor(_WorkflowStepVisualState state) {
    switch (state) {
      case _WorkflowStepVisualState.completed:
        return const _WorkflowStepStyle(
          background: Color(0xFF173625),
          foreground: Color(0xFF7AE2A0),
          border: Color(0xFF4BA36C),
        );
      case _WorkflowStepVisualState.waitingCustomer:
        return const _WorkflowStepStyle(
          background: Color(0xFF3B2A10),
          foreground: Color(0xFFF4C165),
          border: Color(0xFFE0A83F),
        );
      case _WorkflowStepVisualState.paymentActive:
        return const _WorkflowStepStyle(
          background: Color(0xFF41250F),
          foreground: Color(0xFFFFB05E),
          border: Color(0xFFFF9A36),
        );
      case _WorkflowStepVisualState.blocked:
        return const _WorkflowStepStyle(
          background: Color(0xFF42181C),
          foreground: Color(0xFFFF8D8D),
          border: Color(0xFFE05A5A),
        );
      case _WorkflowStepVisualState.current:
        return const _WorkflowStepStyle(
          background: Color(0xFF163B3C),
          foreground: Color(0xFF7BE3D7),
          border: Color(0xFF4BAEAA),
        );
      case _WorkflowStepVisualState.future:
        return _WorkflowStepStyle(
          background: dark
              ? Colors.white.withValues(alpha: 0.06)
              : AppTheme.shell,
          foreground: dark
              ? Colors.white.withValues(alpha: 0.42)
              : AppTheme.ink.withValues(alpha: 0.34),
          border: dark
              ? Colors.white.withValues(alpha: 0.12)
              : AppTheme.border.withValues(alpha: 0.7),
        );
    }
  }
}

class _WorkflowStepStyle {
  const _WorkflowStepStyle({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;
}

enum _WorkflowPath { sharedOnly, remote, siteReview }

enum _WorkflowStepVisualState {
  completed,
  current,
  waitingCustomer,
  paymentActive,
  blocked,
  future,
}

class _WorkflowStepDefinition {
  const _WorkflowStepDefinition({
    required this.key,
    required this.en,
    required this.de,
  });

  final String key;
  final String en;
  final String de;
}

class _ResolvedWorkflowStep {
  const _ResolvedWorkflowStep({required this.definition, required this.state});

  final _WorkflowStepDefinition definition;
  final _WorkflowStepVisualState state;

  String labelFor(AppLanguage language) =>
      language.pick(en: definition.en, de: definition.de);

  bool get isCurrent =>
      state == _WorkflowStepVisualState.current ||
      state == _WorkflowStepVisualState.waitingCustomer ||
      state == _WorkflowStepVisualState.paymentActive ||
      state == _WorkflowStepVisualState.blocked;
}

class _WorkflowProgress {
  const _WorkflowProgress({required this.steps});

  final List<_ResolvedWorkflowStep> steps;

  _ResolvedWorkflowStep get currentStep {
    for (final step in steps) {
      if (step.isCurrent) {
        return step;
      }
    }

    if (steps.isNotEmpty) {
      return steps.last;
    }

    return const _ResolvedWorkflowStep(
      definition: _requestSubmittedDef,
      state: _WorkflowStepVisualState.current,
    );
  }
}

enum _WorkflowOwner { technicianOrContractor, admin, customerCare, customer }

enum _WorkflowOwnerLineLabel { current, next }

const _WorkflowOwnerLineLabel _ownerLineLabelCurrent =
    _WorkflowOwnerLineLabel.current;
const _WorkflowOwnerLineLabel _ownerLineLabelNext =
    _WorkflowOwnerLineLabel.next;

extension on _WorkflowOwner {
  String labelFor(AppLanguage language) {
    return switch (this) {
      _WorkflowOwner.technicianOrContractor => language.pick(
        en: 'Technician / contractor',
        de: 'Techniker / Auftragnehmer',
      ),
      _WorkflowOwner.admin => language.pick(en: 'Admin', de: 'Admin'),
      _WorkflowOwner.customerCare => language.pick(
        en: 'Customer care',
        de: 'Kundenservice',
      ),
      _WorkflowOwner.customer => language.pick(en: 'Customer', de: 'Kunde'),
    };
  }
}

extension on _WorkflowOwnerLineLabel {
  String labelFor(AppLanguage language) {
    return switch (this) {
      _WorkflowOwnerLineLabel.current => language.pick(
        en: 'Current owner: ',
        de: 'Aktuell zustaendig: ',
      ),
      _WorkflowOwnerLineLabel.next => language.pick(
        en: 'Next after that: ',
        de: 'Danach: ',
      ),
    };
  }
}

class _WorkflowOwnership {
  const _WorkflowOwnership({
    required this.currentOwner,
    required this.nextOwner,
  });

  final _WorkflowOwner currentOwner;
  final _WorkflowOwner? nextOwner;
}

const String _workflowStepRequestSubmitted = 'request_submitted';
const String _workflowStepAssessmentInReview = 'assessment_in_review';
const String _workflowStepAwaitingCustomerMedia = 'awaiting_customer_media';
const String _workflowStepSiteReviewRequired = 'site_review_required';
const String _workflowStepSiteReviewScheduled = 'site_review_scheduled';
const String _workflowStepSiteReviewInternalReview =
    'site_review_internal_review';
const String _workflowStepSiteReviewReadyForCustomerCare =
    'site_review_ready_for_customer_care';
const String _workflowStepSiteReviewInvoiceSent = 'site_review_invoice_sent';
const String _workflowStepSiteReviewPaymentPending =
    'site_review_payment_proof_pending';
const String _workflowStepSiteReviewPaid = 'site_review_paid';
const String _workflowStepSiteReviewCompleted = 'site_review_completed';
const String _workflowStepFinalEstimateSubmitted = 'final_estimate_submitted';
const String _workflowStepInternalReview = 'internal_review_in_progress';
const String _workflowStepReadyForCustomerCare = 'ready_for_customer_care';
const String _workflowStepQuotationSent = 'quotation_sent';
const String _workflowStepQuotationPaymentPending =
    'quotation_payment_proof_pending';
const String _workflowStepQuotationPaid = 'quotation_paid';
const String _workflowStepJobScheduled = 'job_scheduled';
const String _workflowStepJobInProgress = 'job_in_progress';
const String _workflowStepJobCompleted = 'job_completed';
const String _workflowStepDelivered = 'delivered';

const _WorkflowStepDefinition _requestSubmittedDef = _WorkflowStepDefinition(
  key: _workflowStepRequestSubmitted,
  en: 'Request sent',
  de: 'Anfrage gesendet',
);
const _WorkflowStepDefinition _assessmentInReviewDef = _WorkflowStepDefinition(
  key: _workflowStepAssessmentInReview,
  en: 'Assessment in review',
  de: 'Pruefung laeuft',
);
const _WorkflowStepDefinition _awaitingCustomerMediaDef =
    _WorkflowStepDefinition(
      key: _workflowStepAwaitingCustomerMedia,
      en: 'More photos/details needed',
      de: 'Mehr Fotos/Details noetig',
    );
const _WorkflowStepDefinition _siteReviewRequiredDef = _WorkflowStepDefinition(
  key: _workflowStepSiteReviewRequired,
  en: 'Site review required',
  de: 'Vor-Ort-Termin noetig',
);
const _WorkflowStepDefinition _siteReviewScheduledDef = _WorkflowStepDefinition(
  key: _workflowStepSiteReviewScheduled,
  en: 'Site review booked',
  de: 'Vor-Ort-Termin gebucht',
);
const _WorkflowStepDefinition _siteReviewInternalReviewDef =
    _WorkflowStepDefinition(
      key: _workflowStepSiteReviewInternalReview,
      en: 'Site review internal review',
      de: 'Besichtigungspruefung',
    );
const _WorkflowStepDefinition _siteReviewReadyForCustomerCareDef =
    _WorkflowStepDefinition(
      key: _workflowStepSiteReviewReadyForCustomerCare,
      en: 'Site review ready to send',
      de: 'Besichtigung bereit zum Senden',
    );
const _WorkflowStepDefinition _siteReviewInvoiceSentDef =
    _WorkflowStepDefinition(
      key: _workflowStepSiteReviewInvoiceSent,
      en: 'Site review invoice sent',
      de: 'Terminrechnung gesendet',
    );
const _WorkflowStepDefinition _siteReviewPaymentPendingDef =
    _WorkflowStepDefinition(
      key: _workflowStepSiteReviewPaymentPending,
      en: 'Site review payment due in 24h',
      de: 'Terminzahlung in 24h faellig',
    );
const _WorkflowStepDefinition _siteReviewPaidDef = _WorkflowStepDefinition(
  key: _workflowStepSiteReviewPaid,
  en: 'Site review paid',
  de: 'Vor-Ort-Termin bezahlt',
);
const _WorkflowStepDefinition _siteReviewCompletedDef = _WorkflowStepDefinition(
  key: _workflowStepSiteReviewCompleted,
  en: 'Site review completed',
  de: 'Vor-Ort-Termin erledigt',
);
const _WorkflowStepDefinition _finalEstimateSubmittedDef =
    _WorkflowStepDefinition(
      key: _workflowStepFinalEstimateSubmitted,
      en: 'Estimate ready',
      de: 'Schaetzung bereit',
    );
const _WorkflowStepDefinition _internalReviewDef = _WorkflowStepDefinition(
  key: _workflowStepInternalReview,
  en: 'Internal review',
  de: 'Interne Pruefung',
);
const _WorkflowStepDefinition _readyForCustomerCareDef =
    _WorkflowStepDefinition(
      key: _workflowStepReadyForCustomerCare,
      en: 'Ready to send',
      de: 'Bereit zum Senden',
    );
const _WorkflowStepDefinition _quotationSentDef = _WorkflowStepDefinition(
  key: _workflowStepQuotationSent,
  en: 'Quotation sent',
  de: 'Angebot gesendet',
);
const _WorkflowStepDefinition _quotationPaymentPendingDef =
    _WorkflowStepDefinition(
      key: _workflowStepQuotationPaymentPending,
      en: 'Payment proof due in 24h',
      de: 'Zahlungsnachweis in 24h faellig',
    );
const _WorkflowStepDefinition _quotationPaidDef = _WorkflowStepDefinition(
  key: _workflowStepQuotationPaid,
  en: 'Payment confirmed',
  de: 'Zahlung bestaetigt',
);
const _WorkflowStepDefinition _jobScheduledDef = _WorkflowStepDefinition(
  key: _workflowStepJobScheduled,
  en: 'Job scheduled',
  de: 'Einsatz geplant',
);
const _WorkflowStepDefinition _jobInProgressDef = _WorkflowStepDefinition(
  key: _workflowStepJobInProgress,
  en: 'Work in progress',
  de: 'Arbeit laeuft',
);
const _WorkflowStepDefinition _jobCompletedDef = _WorkflowStepDefinition(
  key: _workflowStepJobCompleted,
  en: 'Work completed',
  de: 'Arbeit erledigt',
);
const _WorkflowStepDefinition _deliveredDef = _WorkflowStepDefinition(
  key: _workflowStepDelivered,
  en: 'Delivered',
  de: 'Abgeschlossen',
);

_WorkflowProgress _deriveWorkflowProgress(ServiceRequestModel request) {
  final path = _resolvePath(request);
  final currentKey = _resolveCurrentStepKey(request, path);
  final includeAwaitingCustomerMedia =
      request.assessmentStatus == 'awaiting_customer_media';

  final definitions = <_WorkflowStepDefinition>[
    _requestSubmittedDef,
    _assessmentInReviewDef,
    if (includeAwaitingCustomerMedia) _awaitingCustomerMediaDef,
    ...switch (path) {
      _WorkflowPath.sharedOnly => const <_WorkflowStepDefinition>[],
      _WorkflowPath.remote => const <_WorkflowStepDefinition>[
        _finalEstimateSubmittedDef,
        _internalReviewDef,
        _readyForCustomerCareDef,
        _quotationSentDef,
        _quotationPaymentPendingDef,
        _quotationPaidDef,
        _jobScheduledDef,
        _jobInProgressDef,
        _jobCompletedDef,
        _deliveredDef,
      ],
      _WorkflowPath.siteReview => const <_WorkflowStepDefinition>[
        _siteReviewRequiredDef,
        _siteReviewScheduledDef,
        _siteReviewInternalReviewDef,
        _siteReviewReadyForCustomerCareDef,
        _siteReviewInvoiceSentDef,
        _siteReviewPaymentPendingDef,
        _siteReviewPaidDef,
        _siteReviewCompletedDef,
        _finalEstimateSubmittedDef,
        _internalReviewDef,
        _readyForCustomerCareDef,
        _quotationSentDef,
        _quotationPaymentPendingDef,
        _quotationPaidDef,
        _jobScheduledDef,
        _jobInProgressDef,
        _jobCompletedDef,
        _deliveredDef,
      ],
    },
  ];

  final currentIndex = definitions.indexWhere(
    (definition) => definition.key == currentKey,
  );
  final resolvedSteps = <_ResolvedWorkflowStep>[
    for (var index = 0; index < definitions.length; index += 1)
      _ResolvedWorkflowStep(
        definition: definitions[index],
        state: index < currentIndex
            ? _WorkflowStepVisualState.completed
            : index == currentIndex
            ? _visualStateForCurrentStep(definitions[index].key, request)
            : _WorkflowStepVisualState.future,
      ),
  ];

  if (currentIndex < 0 && resolvedSteps.isNotEmpty) {
    return _WorkflowProgress(
      steps: <_ResolvedWorkflowStep>[
        _ResolvedWorkflowStep(
          definition: resolvedSteps.first.definition,
          state: _WorkflowStepVisualState.current,
        ),
        ...resolvedSteps.skip(1),
      ],
    );
  }

  return _WorkflowProgress(steps: resolvedSteps);
}

_WorkflowPath _resolvePath(ServiceRequestModel request) {
  if ((request.assessmentType ?? '').trim().isEmpty) {
    return _WorkflowPath.sharedOnly;
  }

  if (request.isSiteReviewRequired ||
      request.invoice?.isSiteReview == true ||
      request.quoteReview?.isSiteReview == true ||
      request.isSiteReviewReadyForInternalReview ||
      request.isSiteReviewReadyForCustomerCare) {
    return _WorkflowPath.siteReview;
  }

  return _WorkflowPath.remote;
}

String _resolveCurrentStepKey(ServiceRequestModel request, _WorkflowPath path) {
  if (request.status == 'closed') {
    return _workflowStepDelivered;
  }
  if (request.status == 'work_done') {
    return _workflowStepJobCompleted;
  }
  if (request.status == 'project_started') {
    return _workflowStepJobInProgress;
  }
  if (request.status == 'appointment_confirmed' ||
      request.status == 'pending_start') {
    return _workflowStepJobScheduled;
  }

  final invoice = request.invoice;
  if (invoice?.isQuotation == true) {
    if (invoice!.isApproved || invoice.paidAt != null) {
      return _workflowStepQuotationPaid;
    }
    if (invoice.requiresCustomerProof &&
        (invoice.isSent || invoice.isRejected || invoice.isProofSubmitted)) {
      return _workflowStepQuotationPaymentPending;
    }
    return _workflowStepQuotationSent;
  }

  if (request.isQuoteReadyForCustomerCare) {
    return _workflowStepReadyForCustomerCare;
  }
  if (request.isSiteReviewReadyForCustomerCare) {
    return _workflowStepSiteReviewReadyForCustomerCare;
  }

  final hasCompleteFinalEstimate = request.quoteReadyEstimation != null;
  final internalReviewIsCurrent =
      hasCompleteFinalEstimate &&
      (request.quoteReview != null ||
          request.isQuoteReadyForInternalReview ||
          (request.latestEstimateUpdatedAt != null &&
              request.internalReviewUpdatedAt != null &&
              request.internalReviewUpdatedAt!.isBefore(
                request.latestEstimateUpdatedAt!,
              )));
  if (internalReviewIsCurrent) {
    return _workflowStepInternalReview;
  }

  if (path == _WorkflowPath.siteReview) {
    if (request.isSiteReviewReadyForInternalReview ||
        (request.quoteReview?.isSiteReview == true &&
            !request.isSiteReviewReadyForCustomerCare &&
            invoice == null)) {
      return _workflowStepSiteReviewInternalReview;
    }

    if (invoice?.isSiteReview == true) {
      if (invoice!.isApproved || invoice.paidAt != null) {
        return _workflowStepSiteReviewPaid;
      }
      if (invoice.requiresCustomerProof &&
          (invoice.isSent || invoice.isRejected || invoice.isProofSubmitted)) {
        return _workflowStepSiteReviewPaymentPending;
      }
      return _workflowStepSiteReviewInvoiceSent;
    }

    if (request.assessmentStatus == requestAssessmentStatusSiteVisitCompleted) {
      if (hasCompleteFinalEstimate) {
        return _workflowStepInternalReview;
      }
      return _workflowStepSiteReviewCompleted;
    }

    final hasBookedSiteReview =
        request.siteReviewReadyEstimation?.hasSiteReviewBooking == true ||
        request.assessmentStatus == 'site_visit_scheduled';
    if (hasBookedSiteReview) {
      return _workflowStepSiteReviewScheduled;
    }

    return _workflowStepSiteReviewRequired;
  }

  if (hasCompleteFinalEstimate) {
    return _workflowStepInternalReview;
  }

  if (request.assessmentStatus == 'awaiting_customer_media') {
    return _workflowStepAwaitingCustomerMedia;
  }

  final assessmentStarted =
      request.assignedStaff != null ||
      request.status == 'under_review' ||
      (request.assessmentType ?? '').trim().isNotEmpty;
  if (assessmentStarted) {
    return _workflowStepAssessmentInReview;
  }

  return _workflowStepRequestSubmitted;
}

_WorkflowStepVisualState _visualStateForCurrentStep(
  String key,
  ServiceRequestModel request,
) {
  switch (key) {
    case _workflowStepAwaitingCustomerMedia:
      return _WorkflowStepVisualState.waitingCustomer;
    case _workflowStepSiteReviewPaymentPending:
    case _workflowStepQuotationPaymentPending:
      final invoice = request.invoice;
      if (invoice?.isProofUploadExpired == true &&
          invoice?.isProofUploadUnlocked != true &&
          invoice?.isApproved != true) {
        return _WorkflowStepVisualState.blocked;
      }
      return _WorkflowStepVisualState.paymentActive;
    default:
      return _WorkflowStepVisualState.current;
  }
}

_WorkflowOwnership _resolveWorkflowOwnership(String currentStepKey) {
  switch (currentStepKey) {
    case _workflowStepAwaitingCustomerMedia:
    case _workflowStepSiteReviewPaymentPending:
    case _workflowStepQuotationPaymentPending:
    case _workflowStepQuotationSent:
      return const _WorkflowOwnership(
        currentOwner: _WorkflowOwner.customer,
        nextOwner: _WorkflowOwner.admin,
      );
    case _workflowStepInternalReview:
    case _workflowStepSiteReviewInternalReview:
    case _workflowStepFinalEstimateSubmitted:
    case _workflowStepSiteReviewCompleted:
      return const _WorkflowOwnership(
        currentOwner: _WorkflowOwner.admin,
        nextOwner: _WorkflowOwner.customerCare,
      );
    case _workflowStepSiteReviewReadyForCustomerCare:
    case _workflowStepReadyForCustomerCare:
    case _workflowStepSiteReviewInvoiceSent:
      return const _WorkflowOwnership(
        currentOwner: _WorkflowOwner.customerCare,
        nextOwner: _WorkflowOwner.customer,
      );
    case _workflowStepSiteReviewPaid:
    case _workflowStepJobScheduled:
    case _workflowStepJobInProgress:
    case _workflowStepJobCompleted:
      return const _WorkflowOwnership(
        currentOwner: _WorkflowOwner.technicianOrContractor,
        nextOwner: _WorkflowOwner.admin,
      );
    case _workflowStepDelivered:
      return const _WorkflowOwnership(
        currentOwner: _WorkflowOwner.customerCare,
        nextOwner: null,
      );
    case _workflowStepRequestSubmitted:
    case _workflowStepAssessmentInReview:
    case _workflowStepSiteReviewRequired:
    case _workflowStepSiteReviewScheduled:
    default:
      return const _WorkflowOwnership(
        currentOwner: _WorkflowOwner.technicianOrContractor,
        nextOwner: _WorkflowOwner.admin,
      );
  }
}
