library;

import 'package:flutter/material.dart';

import '../../../core/models/service_request_model.dart';
import '../../../shared/presentation/invoice_draft_dialog.dart';
import '../../../theme/app_theme.dart';

class AdminInternalReviewScreen extends StatelessWidget {
  const AdminInternalReviewScreen({super.key, required this.request});

  final ServiceRequestModel request;

  bool get _isPostReviewQuotationFlow {
    return request.isQuoteReadyForInternalReview ||
        request.isQuoteReadyForCustomerCare ||
        (!request.isSiteReviewPending && request.quoteReadyEstimation != null);
  }

  bool get _isSiteReviewFlow {
    if (_isPostReviewQuotationFlow) {
      return false;
    }

    return request.isSiteReviewReadyForInternalReview ||
        request.isSiteReviewReadyForCustomerCare ||
        request.quoteReview?.isSiteReview == true ||
        request.invoice?.isSiteReview == true ||
        (request.isSiteReviewPending &&
            request.siteReviewReadyEstimation != null);
  }

  @override
  Widget build(BuildContext context) {
    final initialInvoice = _isSiteReviewFlow
        ? (request.invoice?.isSiteReview == true ? request.invoice : null)
        : (request.invoice?.isQuotation == true ? request.invoice : null);

    return Scaffold(
      backgroundColor: AppTheme.darkPage,
      appBar: AppBar(
        title: Text(
          _isSiteReviewFlow ? 'Site review internal review' : 'Internal review',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: InvoiceDraftDialog(
                // WHY: A paid site-review invoice can still exist during the
                // post-review quotation stage, but it must not force this form
                // back into site-review mode or block the customer-care handoff.
                initialInvoice: initialInvoice,
                request: request,
                title: _isSiteReviewFlow
                    ? 'Site review internal review'
                    : 'Internal review',
                submitLabel: _isSiteReviewFlow
                    ? 'Save site review review'
                    : 'Save internal review',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
