/// WHAT: Renders request intake as a guided customer-facing conversation.
/// WHY: A chat-style flow feels lighter on mobile while still collecting the same structured request payload.
/// HOW: Step through the required request fields, offer inline choices for service/date/time, then submit through the repository.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_config.dart';
import '../../../core/models/service_request_model.dart';
import '../../../core/network/api_client.dart';
import '../../../theme/app_theme.dart';
import '../../customer/data/customer_repository.dart';
import '../../../shared/utils/request_attachment_picker.dart';
import '../../../shared/utils/request_attachment_picker_types.dart';
import 'customer_requests_screen.dart';

class CustomerCreateRequestScreen extends ConsumerStatefulWidget {
  const CustomerCreateRequestScreen({
    super.key,
    this.requestId,
    this.initialServiceType,
  });

  final String? requestId;
  final String? initialServiceType;

  @override
  ConsumerState<CustomerCreateRequestScreen> createState() =>
      _CustomerCreateRequestScreenState();
}

class _CustomerCreateRequestScreenState
    extends ConsumerState<CustomerCreateRequestScreen> {
  static const List<_RequestDraftSeed> _requestDraftSeeds = <_RequestDraftSeed>[
    _RequestDraftSeed(
      serviceType: 'building_cleaning',
      addressLine1: '12 Clean Street',
      city: 'Monchengladbach',
      postalCode: '41189',
      preferredTimeWindow: 'Weekday morning (08:00 - 11:00)',
      message:
          'We need weekly building cleaning for the entrance, hallways, and kitchen before staff arrive.',
    ),
    _RequestDraftSeed(
      serviceType: 'warehouse_hall_cleaning',
      addressLine1: '45 Warehouse Lane',
      city: 'Dusseldorf',
      postalCode: '40210',
      preferredTimeWindow: 'Afternoon (13:00 - 16:00)',
      message:
          'Please prepare a draft request for warehouse floor cleaning and dust removal around the loading area.',
    ),
    _RequestDraftSeed(
      serviceType: 'window_glass_cleaning',
      addressLine1: '99 Glass Road',
      city: 'Cologne',
      postalCode: '50667',
      preferredTimeWindow: 'Flexible during business hours',
      message:
          'Storefront glass and upper window panels need cleaning before the next customer event.',
    ),
    _RequestDraftSeed(
      serviceType: 'winter_service',
      addressLine1: '28 Frost Avenue',
      city: 'Dortmund',
      postalCode: '44135',
      preferredTimeWindow: 'Early morning (06:00 - 09:00)',
      message:
          'We need snow clearing and grit service around the front entrance, bins, and parking access.',
    ),
    _RequestDraftSeed(
      serviceType: 'caretaker_service',
      addressLine1: '7 Garden Court',
      city: 'Essen',
      postalCode: '45127',
      preferredTimeWindow: 'Morning visit preferred',
      message:
          'Caretaker support is needed for a walkthrough, light fixes, and weekly property checks.',
    ),
    _RequestDraftSeed(
      serviceType: 'garden_care',
      addressLine1: '31 Linden Park',
      city: 'Bonn',
      postalCode: '53111',
      preferredTimeWindow: 'Late morning (10:00 - 12:00)',
      message:
          'Please prepare a garden care draft for hedge trimming, leaf cleanup, and tidying shared outdoor areas.',
    ),
    _RequestDraftSeed(
      serviceType: 'post_construction_cleaning',
      addressLine1: '63 Builder Square',
      city: 'Aachen',
      postalCode: '52062',
      preferredTimeWindow: 'Any time after 09:00',
      message:
          'A post-construction clean is needed after renovation, including dust removal, floors, and window frames.',
    ),
  ];

  static const List<String> _timeWindowChoices = <String>[
    'Weekday morning (08:00 - 11:00)',
    'Late morning (10:00 - 12:00)',
    'Afternoon (13:00 - 16:00)',
    'Any time after 09:00',
    'Flexible during business hours',
  ];

  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _postalCodeController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeWindowController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final Random _random = Random();
  final List<_RequestConversationMessage> _messages =
      <_RequestConversationMessage>[];
  final List<AddressPredictionResult> _addressPredictions =
      <AddressPredictionResult>[];
  final List<PickedRequestAttachmentFile> _pendingSitePhotos =
      <PickedRequestAttachmentFile>[];

  String? _selectedServiceType;
  String? _hydratedRequestId;
  _RequestConversationStep? _stepOverride;
  _VerifiedAddressSuggestion? _pendingVerifiedAddress;
  Timer? _addressAutocompleteDebounce;
  String _lastAddressAutocompleteQuery = '';
  bool _hasSeededConversation = false;
  bool _isSubmitting = false;
  bool _isVerifyingAddress = false;
  bool _isLoadingAddressPredictions = false;
  bool _isUploadingSitePhotos = false;
  int _addressVerificationFailureCount = 0;

  bool get _isEditing => widget.requestId != null;

  @override
  void initState() {
    super.initState();
    _chatInputController.addListener(_handleChatInputChanged);
    final requestedService = widget.initialServiceType;
    _selectedServiceType =
        requestedService != null &&
            AppConfig.serviceLabels.containsKey(requestedService)
        ? requestedService
        : null;
  }

  @override
  void dispose() {
    _addressAutocompleteDebounce?.cancel();
    _addressController.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
    _dateController.dispose();
    _timeWindowController.dispose();
    _messageController.dispose();
    _chatInputController.removeListener(_handleChatInputChanged);
    _chatInputController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  _RequestConversationStep _currentStep() {
    if (_stepOverride != null) {
      return _stepOverride!;
    }

    if ((_selectedServiceType ?? '').trim().isEmpty) {
      return _RequestConversationStep.service;
    }

    if (_addressController.text.trim().isEmpty) {
      return _RequestConversationStep.address;
    }

    if (_pendingVerifiedAddress != null &&
        _cityController.text.trim().isEmpty &&
        _postalCodeController.text.trim().isEmpty) {
      return _RequestConversationStep.addressConfirmation;
    }

    if (_cityController.text.trim().isEmpty) {
      return _RequestConversationStep.city;
    }

    if (_postalCodeController.text.trim().isEmpty) {
      return _RequestConversationStep.postalCode;
    }

    if (_dateController.text.trim().isEmpty) {
      return _RequestConversationStep.preferredDate;
    }

    if (_timeWindowController.text.trim().isEmpty) {
      return _RequestConversationStep.preferredTimeWindow;
    }

    if (_messageController.text.trim().isEmpty) {
      return _RequestConversationStep.message;
    }

    return _RequestConversationStep.done;
  }

  bool get _canPredictAddress =>
      _currentStep() == _RequestConversationStep.address &&
      !_isVerifyingAddress &&
      !_isSubmitting;

  void _handleChatInputChanged() {
    if (!_canPredictAddress) {
      _clearAddressPredictions();
      return;
    }

    final query = _chatInputController.text.trim();
    if (query.length < 3) {
      _clearAddressPredictions();
      return;
    }

    _addressAutocompleteDebounce?.cancel();
    _addressAutocompleteDebounce = Timer(
      const Duration(milliseconds: 280),
      () => _loadAddressPredictions(query),
    );
  }

  void _clearAddressPredictions() {
    _addressAutocompleteDebounce?.cancel();
    _lastAddressAutocompleteQuery = '';
    if (_addressPredictions.isEmpty && !_isLoadingAddressPredictions) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoadingAddressPredictions = false;
      _addressPredictions.clear();
    });
  }

  Future<void> _loadAddressPredictions(String query) async {
    if (!_canPredictAddress) {
      return;
    }

    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 3) {
      _clearAddressPredictions();
      return;
    }

    _lastAddressAutocompleteQuery = normalizedQuery;
    if (mounted) {
      setState(() {
        _isLoadingAddressPredictions = true;
      });
    }

    try {
      final predictions = await ref
          .read(customerRepositoryProvider)
          .autocompleteAddress(input: normalizedQuery);

      if (!mounted ||
          !_canPredictAddress ||
          _chatInputController.text.trim() != normalizedQuery ||
          _lastAddressAutocompleteQuery != normalizedQuery) {
        return;
      }

      setState(() {
        _addressPredictions
          ..clear()
          ..addAll(predictions);
        _isLoadingAddressPredictions = false;
      });
    } catch (_) {
      if (!mounted || _lastAddressAutocompleteQuery != normalizedQuery) {
        return;
      }

      setState(() {
        _addressPredictions.clear();
        _isLoadingAddressPredictions = false;
      });
    }
  }

  void _seedConversationIfNeeded({ServiceRequestModel? request}) {
    if (_hasSeededConversation) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasSeededConversation) {
        return;
      }

      final serviceLabel = _selectedServiceLabel;
      setState(() {
        _hasSeededConversation = true;
        _messages.add(
          _RequestConversationMessage.assistant(
            text: _isEditing
                ? _editingGreeting(serviceLabel: serviceLabel)
                : _newRequestGreeting(serviceLabel: serviceLabel),
          ),
        );
      });
      _scrollToBottom();
    });
  }

  String _newRequestGreeting({String? serviceLabel}) {
    if (serviceLabel != null && serviceLabel.isNotEmpty) {
      return 'I already have $serviceLabel noted from the previous step. What address should the team attend?';
    }

    return 'I will get this request ready like a live intake chat. Start by telling me which service you need.';
  }

  String _editingGreeting({String? serviceLabel}) {
    final resolvedService = serviceLabel ?? 'this request';
    return 'I loaded your current $resolvedService request. Review the summary below and edit anything that has changed before saving.';
  }

  String? get _selectedServiceLabel {
    final serviceType = _selectedServiceType;
    if (serviceType == null || serviceType.trim().isEmpty) {
      return null;
    }

    return AppConfig.serviceLabelFor(serviceType);
  }

  void _hydrateFromRequest(ServiceRequestModel request) {
    if (_hydratedRequestId == request.id) {
      return;
    }

    _hydratedRequestId = request.id;
    _selectedServiceType = request.serviceType;
    _addressController.text = request.addressLine1;
    _cityController.text = request.city;
    _postalCodeController.text = request.postalCode;
    _dateController.text = request.preferredDate == null
        ? ''
        : _formatPayloadDate(request.preferredDate!);
    _timeWindowController.text = request.preferredTimeWindow;
    _messageController.text = request.message;
    _stepOverride = null;
    _pendingVerifiedAddress = null;
    _addressPredictions.clear();
    _pendingSitePhotos.clear();
    _lastAddressAutocompleteQuery = '';
    _isVerifyingAddress = false;
    _isLoadingAddressPredictions = false;
    _isUploadingSitePhotos = false;
    _addressVerificationFailureCount = 0;
    _hasSeededConversation = false;
    _messages.clear();
  }

  Future<void> _pickDateFromCalendar() async {
    final initialDate =
        _parseDateInput(_dateController.text.trim()) ??
        DateTime.now().add(const Duration(days: 1));

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(DateTime.now())
          ? DateTime.now()
          : initialDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select preferred date',
    );

    if (selectedDate == null || !mounted) {
      return;
    }

    _captureCurrentStep(
      _formatPayloadDate(selectedDate),
      displayValue: _formatDisplayDate(selectedDate),
    );
  }

  void _generateTestDraftConversation() {
    final seed = _requestDraftSeeds[_random.nextInt(_requestDraftSeeds.length)];
    final preferredDate = DateTime.now().add(
      Duration(days: _random.nextInt(21) + 1),
    );

    setState(() {
      _selectedServiceType = seed.serviceType;
      _addressController.text = seed.addressLine1;
      _cityController.text = seed.city;
      _postalCodeController.text = seed.postalCode;
      _dateController.text = _formatPayloadDate(preferredDate);
      _timeWindowController.text = seed.preferredTimeWindow;
      _messageController.text = seed.message;
      _stepOverride = null;
      _pendingVerifiedAddress = null;
      _addressPredictions.clear();
      _pendingSitePhotos.clear();
      _lastAddressAutocompleteQuery = '';
      _isVerifyingAddress = false;
      _isLoadingAddressPredictions = false;
      _isUploadingSitePhotos = false;
      _addressVerificationFailureCount = 0;
      _hasSeededConversation = true;
      _messages
        ..clear()
        ..add(
          const _RequestConversationMessage.user(text: 'Generate test draft'),
        )
        ..add(
          _RequestConversationMessage.assistant(
            text:
                'I prepared a complete test draft for ${AppConfig.serviceLabelFor(seed.serviceType)}. Review the summary below, edit anything you want, or send it now.',
          ),
        );
    });

    _scrollToBottom();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Test draft loaded into the conversation'),
        ),
      );
  }

  void _captureCurrentStep(String rawValue, {String? displayValue}) {
    _captureCurrentStepAsync(rawValue, displayValue: displayValue);
  }

  Future<void> _captureCurrentStepAsync(
    String rawValue, {
    String? displayValue,
  }) async {
    if (_isSubmitting || _isVerifyingAddress) {
      return;
    }

    final step = _currentStep();
    if (step == _RequestConversationStep.done) {
      return;
    }

    final trimmedValue = rawValue.trim();
    if (trimmedValue.isEmpty) {
      _pushAssistantMessage(_requiredFieldMessage(step));
      return;
    }

    final validationError = _validateInput(step, trimmedValue);
    if (validationError != null) {
      _pushAssistantMessage(validationError);
      return;
    }

    if (step == _RequestConversationStep.address) {
      await _handleAddressStep(trimmedValue);
      return;
    }

    if (step == _RequestConversationStep.addressConfirmation) {
      await _handleAddressConfirmationStep(trimmedValue);
      return;
    }

    late final String userVisibleText;
    switch (step) {
      case _RequestConversationStep.service:
        final matchedService = _matchService(trimmedValue);
        if (matchedService == null) {
          _pushAssistantMessage(_invalidServiceMessage());
          return;
        }
        _selectedServiceType = matchedService;
        userVisibleText = AppConfig.serviceLabelFor(matchedService);
      case _RequestConversationStep.address:
      case _RequestConversationStep.addressConfirmation:
        return;
      case _RequestConversationStep.city:
        _cityController.text = trimmedValue;
        userVisibleText = trimmedValue;
      case _RequestConversationStep.postalCode:
        _postalCodeController.text = trimmedValue;
        userVisibleText = trimmedValue;
      case _RequestConversationStep.preferredDate:
        final parsedDate = _parseDateInput(trimmedValue);
        if (parsedDate == null) {
          _pushAssistantMessage(_invalidDateMessage());
          return;
        }
        _dateController.text = _formatPayloadDate(parsedDate);
        userVisibleText = displayValue ?? _formatDisplayDate(parsedDate);
      case _RequestConversationStep.preferredTimeWindow:
        _timeWindowController.text = trimmedValue;
        userVisibleText = trimmedValue;
      case _RequestConversationStep.message:
        _messageController.text = trimmedValue;
        userVisibleText = trimmedValue;
      case _RequestConversationStep.done:
        return;
    }

    _chatInputController.clear();
    _stepOverride = null;
    final nextStep = _currentStep();

    setState(() {
      _messages.add(_RequestConversationMessage.user(text: userVisibleText));
      _messages.add(
        _RequestConversationMessage.assistant(
          text: _assistantFollowUp(step, nextStep),
        ),
      );
    });
    _scrollToBottom();
  }

  Future<void> _handleAddressStep(
    String addressLine1, {
    String? placeId,
  }) async {
    _chatInputController.clear();

    setState(() {
      _messages.add(_RequestConversationMessage.user(text: addressLine1));
      _isVerifyingAddress = true;
      _isLoadingAddressPredictions = false;
      _pendingVerifiedAddress = null;
      _stepOverride = null;
      _addressPredictions.clear();
      _cityController.clear();
      _postalCodeController.clear();
    });
    _scrollToBottom();

    try {
      final verification = await ref
          .read(customerRepositoryProvider)
          .verifyAddress(addressLine1: addressLine1, placeId: placeId);

      if (!mounted) {
        return;
      }

      if (verification.isVerified) {
        final suggestion = _VerifiedAddressSuggestion.fromResult(verification);

        setState(() {
          _addressController.text = suggestion.addressLine1;
          _pendingVerifiedAddress = suggestion;
          _addressVerificationFailureCount = 0;
          _stepOverride = _RequestConversationStep.addressConfirmation;
          _addressPredictions.clear();
          _messages.add(
            _RequestConversationMessage.assistant(
              text: _verifiedAddressPrompt(suggestion),
            ),
          );
          _isVerifyingAddress = false;
        });
        _scrollToBottom();
        return;
      }

      if (verification.isNotFound) {
        final shouldFallbackToManual = _addressVerificationFailureCount >= 1;

        setState(() {
          _addressController.text = addressLine1;
          _pendingVerifiedAddress = null;
          _addressVerificationFailureCount += 1;
          _stepOverride = shouldFallbackToManual
              ? null
              : _RequestConversationStep.address;
          _addressPredictions.clear();
          _messages.add(
            _RequestConversationMessage.assistant(
              text: shouldFallbackToManual
                  ? _addressManualFallbackPrompt()
                  : _addressRetypePrompt(),
            ),
          );
          _isVerifyingAddress = false;
        });
        _scrollToBottom();
        return;
      }

      setState(() {
        _addressController.text = addressLine1;
        _pendingVerifiedAddress = null;
        _addressVerificationFailureCount = 0;
        _stepOverride = null;
        _addressPredictions.clear();
        _messages.add(
          _RequestConversationMessage.assistant(
            text: _addressVerificationUnavailablePrompt(),
          ),
        );
        _isVerifyingAddress = false;
      });
    } on ApiException {
      if (!mounted) {
        return;
      }

      setState(() {
        _addressController.text = addressLine1;
        _pendingVerifiedAddress = null;
        _addressVerificationFailureCount = 0;
        _stepOverride = null;
        _addressPredictions.clear();
        _messages.add(
          _RequestConversationMessage.assistant(
            text: _addressVerificationUnavailablePrompt(),
          ),
        );
        _isVerifyingAddress = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _addressController.text = addressLine1;
        _pendingVerifiedAddress = null;
        _addressVerificationFailureCount = 0;
        _stepOverride = null;
        _messages.add(
          _RequestConversationMessage.assistant(
            text: _addressVerificationUnavailablePrompt(),
          ),
        );
        _isVerifyingAddress = false;
      });
    }

    _scrollToBottom();
  }

  Future<void> _handleAddressConfirmationStep(String rawValue) async {
    if (_looksLikeAddressConfirmation(rawValue)) {
      _confirmVerifiedAddress();
      return;
    }

    await _handleAddressStep(rawValue);
  }

  Future<void> _selectAddressPrediction(
    AddressPredictionResult prediction,
  ) async {
    _chatInputController.text = prediction.description;
    await _handleAddressStep(
      prediction.description,
      placeId: prediction.placeId,
    );
  }

  void _confirmVerifiedAddress() {
    final suggestion = _pendingVerifiedAddress;
    if (suggestion == null) {
      _pushAssistantMessage(_addressRetypePrompt());
      return;
    }

    final nextStep = _RequestConversationStep.preferredDate;

    setState(() {
      _cityController.text = suggestion.city;
      _postalCodeController.text = suggestion.postalCode;
      _addressController.text = suggestion.addressLine1;
      _pendingVerifiedAddress = null;
      _addressVerificationFailureCount = 0;
      _stepOverride = null;
      _addressPredictions.clear();
      _messages.add(
        _RequestConversationMessage.user(
          text: 'Use ${suggestion.city}, ${suggestion.postalCode}',
        ),
      );
      _messages.add(
        _RequestConversationMessage.assistant(
          text: _assistantFollowUp(
            _RequestConversationStep.addressConfirmation,
            nextStep,
          ),
        ),
      );
    });
    _scrollToBottom();
  }

  void _promptRetypedAddress() {
    if (_isSubmitting || _isVerifyingAddress) {
      return;
    }

    setState(() {
      _pendingVerifiedAddress = null;
      _addressVerificationFailureCount += 1;
      _stepOverride = _RequestConversationStep.address;
      _addressPredictions.clear();
      _messages.add(
        _RequestConversationMessage.assistant(
          text:
              'No problem. Type the address again with the street and number, and I will check the city and postal code once more.',
        ),
      );
    });
    _scrollToBottom();
  }

  String? _validateInput(_RequestConversationStep step, String value) {
    switch (step) {
      case _RequestConversationStep.service:
        return _matchService(value) == null ? _invalidServiceMessage() : null;
      case _RequestConversationStep.address:
        return value.length < 5
            ? 'Please enter a fuller address so staff know where to attend.'
            : null;
      case _RequestConversationStep.addressConfirmation:
        return null;
      case _RequestConversationStep.city:
        return value.length < 2 ? 'Please enter the city.' : null;
      case _RequestConversationStep.postalCode:
        return value.length < 4 ? 'Please enter a valid postal code.' : null;
      case _RequestConversationStep.preferredDate:
        return _parseDateInput(value) == null ? _invalidDateMessage() : null;
      case _RequestConversationStep.preferredTimeWindow:
        return value.length < 4 ? 'Please share a usable time window.' : null;
      case _RequestConversationStep.message:
        return value.length < 12
            ? 'Please add a little more detail about the work.'
            : null;
      case _RequestConversationStep.done:
        return null;
    }
  }

  String? _matchService(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    for (final entry in AppConfig.serviceLabels.entries) {
      if (entry.key.toLowerCase() == normalized ||
          entry.value.toLowerCase() == normalized) {
        return entry.key;
      }
    }

    return null;
  }

  DateTime? _parseDateInput(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return null;
    }

    if (trimmed == 'today') {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }

    if (trimmed == 'tomorrow') {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      return DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    }

    final parsed = DateTime.tryParse(trimmed);
    if (parsed != null) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }

    final match = RegExp(
      r'^(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{4})$',
    ).firstMatch(trimmed);
    if (match == null) {
      return null;
    }

    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final year = int.tryParse(match.group(3)!);
    if (day == null || month == null || year == null) {
      return null;
    }

    final candidate = DateTime(year, month, day);
    if (candidate.year != year ||
        candidate.month != month ||
        candidate.day != day) {
      return null;
    }

    return candidate;
  }

  String _assistantFollowUp(
    _RequestConversationStep capturedStep,
    _RequestConversationStep nextStep,
  ) {
    if (nextStep == _RequestConversationStep.done) {
      return _isEditing
          ? 'That is updated. Review the summary below and save your changes when you are ready.'
          : 'Perfect. I have everything I need. Review the summary below and send the request when you are ready.';
    }

    return switch (capturedStep) {
      _RequestConversationStep.service =>
        'Got it, ${_selectedServiceLabel ?? 'that service'} is noted. What address should the team attend?',
      _RequestConversationStep.address => 'Thanks. Which city is that in?',
      _RequestConversationStep.addressConfirmation =>
        'Perfect. I will use ${_cityController.text.trim()} ${_postalCodeController.text.trim()} for that location. What date would you prefer? You can pick one below or open the calendar.',
      _RequestConversationStep.city =>
        'Great. What postal code should I attach to this location?',
      _RequestConversationStep.postalCode =>
        'What date would you prefer? You can pick one below or open the calendar.',
      _RequestConversationStep.preferredDate =>
        'Nice. What time window works best for access?',
      _RequestConversationStep.preferredTimeWindow =>
        'Understood. Finally, describe the work so the team knows what to prepare. If it helps, add up to 5 site photos below.',
      _RequestConversationStep.message =>
        'Everything is captured. Review the request summary below before sending.',
      _RequestConversationStep.done => _stepPrompt(nextStep),
    };
  }

  String _stepPrompt(_RequestConversationStep step) {
    return switch (step) {
      _RequestConversationStep.service => 'Which service do you need?',
      _RequestConversationStep.address =>
        'What Germany address should the team attend?',
      _RequestConversationStep.addressConfirmation =>
        'Type confirm to use the detected city and postal code, or enter a different address.',
      _RequestConversationStep.city => 'Which city is the job in?',
      _RequestConversationStep.postalCode =>
        'What postal code should I attach?',
      _RequestConversationStep.preferredDate =>
        'What date would you prefer? Pick one below or open the calendar.',
      _RequestConversationStep.preferredTimeWindow =>
        'What time window works best?',
      _RequestConversationStep.message =>
        'Describe the work so the team knows what to expect.',
      _RequestConversationStep.done => 'Everything is ready to review.',
    };
  }

  void _startEditingStep(_RequestConversationStep step) {
    setState(() {
      if (step == _RequestConversationStep.address) {
        _pendingVerifiedAddress = null;
        _addressVerificationFailureCount = 0;
      }
      _stepOverride = step;
      _messages.add(
        _RequestConversationMessage.assistant(text: _editingPrompt(step)),
      );
    });

    _chatInputController.text = switch (step) {
      _RequestConversationStep.service => '',
      _RequestConversationStep.address => _addressController.text.trim(),
      _RequestConversationStep.addressConfirmation => '',
      _RequestConversationStep.city => _cityController.text.trim(),
      _RequestConversationStep.postalCode => _postalCodeController.text.trim(),
      _RequestConversationStep.preferredDate => '',
      _RequestConversationStep.preferredTimeWindow =>
        _timeWindowController.text.trim(),
      _RequestConversationStep.message => _messageController.text.trim(),
      _RequestConversationStep.done => '',
    };

    _scrollToBottom();
  }

  String _editingPrompt(_RequestConversationStep step) {
    return switch (step) {
      _RequestConversationStep.service =>
        'No problem. Choose the updated service below or type it in.',
      _RequestConversationStep.address => 'What is the updated address?',
      _RequestConversationStep.addressConfirmation =>
        'Type confirm to keep the detected city and postal code, or type a different address.',
      _RequestConversationStep.city => 'Which city should I use instead?',
      _RequestConversationStep.postalCode => 'What is the updated postal code?',
      _RequestConversationStep.preferredDate =>
        'Choose the updated preferred date below or open the calendar.',
      _RequestConversationStep.preferredTimeWindow =>
        'What time window should I use instead?',
      _RequestConversationStep.message =>
        'Share the updated job description and add up to 5 site photos if they help.',
      _RequestConversationStep.done =>
        'Review the summary and save when you are ready.',
    };
  }

  String _requiredFieldMessage(_RequestConversationStep step) {
    return switch (step) {
      _RequestConversationStep.service => 'Please choose a service first.',
      _RequestConversationStep.address => 'Please enter the service address.',
      _RequestConversationStep.addressConfirmation =>
        'Type confirm to use the detected city and postal code, or enter a different address.',
      _RequestConversationStep.city => 'Please enter the city.',
      _RequestConversationStep.postalCode => 'Please enter the postal code.',
      _RequestConversationStep.preferredDate => 'Please choose a date.',
      _RequestConversationStep.preferredTimeWindow =>
        'Please share a preferred time window.',
      _RequestConversationStep.message =>
        'Please describe the work that needs attention.',
      _RequestConversationStep.done => '',
    };
  }

  String _invalidServiceMessage() {
    return 'Please choose one of the listed service types so I can route this correctly.';
  }

  String _invalidDateMessage() {
    return 'Use one of the date shortcuts, open the calendar, or type a date like 2026-04-02.';
  }

  bool _looksLikeAddressConfirmation(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'confirm' ||
        normalized == 'confirmed' ||
        normalized == 'yes' ||
        normalized == 'y' ||
        normalized == 'ok' ||
        normalized == 'okay' ||
        normalized == 'use it' ||
        normalized == 'use this' ||
        normalized == 'correct' ||
        normalized == 'ja' ||
        normalized == 'stimmt' ||
        normalized == 'bestaetigen' ||
        normalized == 'bestatigen';
  }

  String _verifiedAddressPrompt(_VerifiedAddressSuggestion suggestion) {
    return 'I found ${suggestion.addressLine1} in ${suggestion.city}, ${suggestion.postalCode}. Type confirm to use that city and postal code, or type the full address again if it needs correcting.';
  }

  String _addressRetypePrompt() {
    return 'I could not clearly confirm the city and postal code from that address. Please type the full street address again, including the building number.';
  }

  String _addressManualFallbackPrompt() {
    return 'I still could not verify that address automatically, so I will continue manually. Which city is the job in?';
  }

  String _addressVerificationUnavailablePrompt() {
    return 'I could not verify that address right now, so I will continue manually. Which city is the job in?';
  }

  void _pushAssistantMessage(String text) {
    setState(() {
      _messages.add(_RequestConversationMessage.assistant(text: text));
    });
    _scrollToBottom();
  }

  Future<void> _pickSitePhotos() async {
    if (_isSubmitting || _isUploadingSitePhotos) {
      return;
    }

    final remainingSlots = 5 - _pendingSitePhotos.length;
    if (remainingSlots <= 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('You can add up to 5 site photos at a time.'),
          ),
        );
      return;
    }

    try {
      final pickedFiles = await pickRequestAttachmentFiles(
        maxFiles: remainingSlots,
        imagesOnly: true,
      );

      if (!mounted || pickedFiles.isEmpty) {
        return;
      }

      setState(() {
        _pendingSitePhotos.addAll(pickedFiles.take(remainingSlots));
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${pickedFiles.take(remainingSlots).length} site ${pickedFiles.length == 1 ? 'photo' : 'photos'} added',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
    }
  }

  void _removeSitePhoto(PickedRequestAttachmentFile file) {
    setState(() {
      _pendingSitePhotos.remove(file);
    });
  }

  Future<int> _uploadPendingSitePhotos(
    CustomerRepository repository,
    String requestId,
  ) async {
    if (_pendingSitePhotos.isEmpty) {
      return 0;
    }

    setState(() {
      _isUploadingSitePhotos = true;
    });

    var uploadedCount = 0;

    try {
      for (var index = 0; index < _pendingSitePhotos.length; index += 1) {
        final file = _pendingSitePhotos[index];
        await repository.uploadRequestAttachment(
          requestId: requestId,
          bytes: file.bytes,
          fileName: file.name,
          mimeType: file.mimeType,
          caption:
              'Site photo ${index + 1} of ${_pendingSitePhotos.length} from request intake',
        );
        uploadedCount += 1;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingSitePhotos = false;
        });
      }
    }

    return uploadedCount;
  }

  Future<void> _submitRequest() async {
    setState(() => _isSubmitting = true);

    try {
      final repository = ref.read(customerRepositoryProvider);
      final payload = <String, String>{
        'serviceType': _selectedServiceType ?? '',
        'addressLine1': _addressController.text.trim(),
        'city': _cityController.text.trim(),
        'postalCode': _postalCodeController.text.trim(),
        'preferredDate': _dateController.text.trim(),
        'preferredTimeWindow': _timeWindowController.text.trim(),
        'message': _messageController.text.trim(),
      };

      String requestId = widget.requestId ?? '';

      if (_isEditing) {
        await repository.updateRequest(
          requestId: widget.requestId!,
          serviceType: payload['serviceType']!,
          addressLine1: payload['addressLine1']!,
          city: payload['city']!,
          postalCode: payload['postalCode']!,
          preferredDate: payload['preferredDate']!,
          preferredTimeWindow: payload['preferredTimeWindow']!,
          message: payload['message']!,
        );
      } else {
        final createdRequest = await repository.createRequest(
          serviceType: payload['serviceType']!,
          addressLine1: payload['addressLine1']!,
          city: payload['city']!,
          postalCode: payload['postalCode']!,
          preferredDate: payload['preferredDate']!,
          preferredTimeWindow: payload['preferredTimeWindow']!,
          message: payload['message']!,
        );
        requestId = createdRequest.id;
      }

      var uploadedPhotoCount = 0;
      var photoUploadFailed = false;
      if (requestId.isNotEmpty && _pendingSitePhotos.isNotEmpty) {
        try {
          uploadedPhotoCount = await _uploadPendingSitePhotos(
            repository,
            requestId,
          );
        } catch (_) {
          photoUploadFailed = true;
        }
      }

      ref.invalidate(customerRequestsProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            photoUploadFailed
                ? (_isEditing
                      ? 'Request updated, but some site photos failed to upload'
                      : 'Request submitted, but some site photos failed to upload')
                : uploadedPhotoCount > 0
                ? (_isEditing
                      ? 'Request updated with $uploadedPhotoCount site photos'
                      : 'Request submitted with $uploadedPhotoCount site photos')
                : _isEditing
                ? 'Request updated successfully'
                : 'Request submitted successfully',
          ),
        ),
      );
      context.go('/app/requests');
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          if (!_isEditing) {
            _pendingSitePhotos.clear();
          }
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chatScrollController.hasClients) {
        return;
      }

      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent + 140,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _formatPayloadDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDisplayDate(DateTime date) {
    const weekdayLabels = <String>[
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    const monthLabels = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final weekday = weekdayLabels[date.weekday - 1];
    final month = monthLabels[date.month - 1];
    return '$weekday, ${date.day} $month ${date.year}';
  }

  List<DateTime> _quickDateChoices() {
    final now = DateTime.now();
    return <DateTime>[
      DateTime(now.year, now.month, now.day).add(const Duration(days: 1)),
      DateTime(now.year, now.month, now.day).add(const Duration(days: 3)),
      DateTime(now.year, now.month, now.day).add(const Duration(days: 7)),
    ];
  }

  Widget _buildConversationScaffold(BuildContext context) {
    final title = _isEditing ? 'Update Request' : 'Create Request';
    final panelTitle = _isEditing ? 'Update with AI' : 'Request with AI';
    final currentStep = _currentStep();
    final showComposer = currentStep != _RequestConversationStep.done;
    final showAddressPredictions =
        currentStep == _RequestConversationStep.address &&
        (_isLoadingAddressPredictions || _addressPredictions.isNotEmpty);
    final wide = MediaQuery.sizeOf(context).width >= 1080;
    final fullBleedChat = !wide;
    final chatSurfaceColor = Color.lerp(AppTheme.ink, AppTheme.cobalt, 0.2)!;
    final pageTopColor = Color.lerp(AppTheme.sand, AppTheme.cobalt, 0.12)!;
    final pageMiddleColor = Color.lerp(AppTheme.sand, AppTheme.ink, 0.07)!;
    final pageBottomColor = Color.lerp(AppTheme.sand, AppTheme.clay, 0.3)!;

    final chatPanel = Container(
      decoration: BoxDecoration(
        color: chatSurfaceColor,
        borderRadius: fullBleedChat
            ? BorderRadius.zero
            : BorderRadius.circular(30),
        border: fullBleedChat
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: fullBleedChat
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: AppTheme.ink.withValues(alpha: 0.22),
                  blurRadius: 26,
                  offset: const Offset(0, 18),
                ),
              ],
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              fullBleedChat ? 16 : 20,
              fullBleedChat ? 16 : 20,
              fullBleedChat ? 16 : 20,
              12,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFF2F68CE), Color(0xFF63C3E7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        panelTitle,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isEditing
                            ? 'Continue the request as a guided assistant conversation, then save the changes.'
                            : 'Continue the request as a guided assistant conversation instead of filling a plain form.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.72),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isEditing)
                  OutlinedButton.icon(
                    onPressed: _isSubmitting
                        ? null
                        : _generateTestDraftConversation,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                    ),
                    icon: const Icon(Icons.bolt_rounded, size: 18),
                    label: const Text('Test Draft'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              fullBleedChat ? 16 : 20,
              0,
              fullBleedChat ? 16 : 20,
              16,
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _buildProgressChips()
                  .map(
                    (chip) => _ProgressPill(
                      label: chip.label,
                      isActive: chip.isActive,
                      isComplete: chip.isComplete,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          Container(
            height: wide ? 520 : 470,
            padding: EdgeInsets.symmetric(horizontal: fullBleedChat ? 16 : 20),
            child: ListView.separated(
              controller: _chatScrollController,
              itemCount: _messages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Align(
                  alignment: message.isAssistant
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: message.isAssistant
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFF315B9A),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: message.isAssistant
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              message.senderName,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: message.isAssistant
                                        ? const Color(0xFF7ED2FF)
                                        : Colors.white.withValues(alpha: 0.86),
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              message.text,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: Colors.white, height: 1.45),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (showComposer) ...<Widget>[
            _buildStepActions(context, currentStep),
            if (showAddressPredictions)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  fullBleedChat ? 16 : 20,
                  12,
                  fullBleedChat ? 16 : 20,
                  0,
                ),
                child: _AddressPredictionsCard(
                  isLoading: _isLoadingAddressPredictions,
                  predictions: _addressPredictions,
                  onSelect: _selectAddressPrediction,
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                fullBleedChat ? 16 : 20,
                12,
                fullBleedChat ? 16 : 20,
                fullBleedChat ? 16 : 20,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: TextField(
                        controller: _chatInputController,
                        enabled: !_isSubmitting && !_isVerifyingAddress,
                        textInputAction: TextInputAction.send,
                        keyboardType:
                            currentStep == _RequestConversationStep.postalCode
                            ? TextInputType.number
                            : currentStep == _RequestConversationStep.address ||
                                  currentStep ==
                                      _RequestConversationStep
                                          .addressConfirmation
                            ? TextInputType.streetAddress
                            : TextInputType.text,
                        minLines:
                            currentStep == _RequestConversationStep.message
                            ? 3
                            : 1,
                        maxLines:
                            currentStep == _RequestConversationStep.message
                            ? 5
                            : 1,
                        onSubmitted: (_) =>
                            _captureCurrentStep(_chatInputController.text),
                        decoration: InputDecoration(
                          hintText: _placeholderForStep(currentStep),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          suffixIcon:
                              currentStep ==
                                  _RequestConversationStep.preferredDate
                              ? IconButton(
                                  onPressed: _pickDateFromCalendar,
                                  icon: const Icon(
                                    Icons.calendar_month_rounded,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: (_isSubmitting || _isVerifyingAddress)
                          ? AppTheme.cobalt.withValues(alpha: 0.45)
                          : AppTheme.cobalt,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: IconButton(
                      onPressed: (_isSubmitting || _isVerifyingAddress)
                          ? null
                          : () =>
                                _captureCurrentStep(_chatInputController.text),
                      icon: (_isSubmitting || _isVerifyingAddress)
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.arrow_upward_rounded),
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ] else
            Padding(
              padding: EdgeInsets.fromLTRB(
                fullBleedChat ? 16 : 20,
                0,
                fullBleedChat ? 16 : 20,
                fullBleedChat ? 16 : 20,
              ),
              child: _RequestSummaryCard(
                serviceLabel: _selectedServiceLabel ?? 'Service',
                addressLine1: _addressController.text.trim(),
                city: _cityController.text.trim(),
                postalCode: _postalCodeController.text.trim(),
                preferredDate: _displayDateFromStoredValue(
                  _dateController.text.trim(),
                ),
                preferredTimeWindow: _timeWindowController.text.trim(),
                message: _messageController.text.trim(),
                isSubmitting: _isSubmitting,
                submitLabel: _isEditing ? 'Save Changes' : 'Send Request',
                onSubmit: _submitRequest,
                rows: <_RequestSummaryRowData>[
                  _RequestSummaryRowData(
                    label: 'Service',
                    value: _selectedServiceLabel ?? 'Not selected',
                    icon: Icons.cleaning_services_rounded,
                    onEdit: () =>
                        _startEditingStep(_RequestConversationStep.service),
                  ),
                  _RequestSummaryRowData(
                    label: 'Address',
                    value: _addressController.text.trim(),
                    icon: Icons.location_on_rounded,
                    onEdit: () =>
                        _startEditingStep(_RequestConversationStep.address),
                  ),
                  _RequestSummaryRowData(
                    label: 'City',
                    value: _cityController.text.trim(),
                    icon: Icons.apartment_rounded,
                    onEdit: () =>
                        _startEditingStep(_RequestConversationStep.city),
                  ),
                  _RequestSummaryRowData(
                    label: 'Postal code',
                    value: _postalCodeController.text.trim(),
                    icon: Icons.markunread_mailbox_rounded,
                    onEdit: () =>
                        _startEditingStep(_RequestConversationStep.postalCode),
                  ),
                  _RequestSummaryRowData(
                    label: 'Preferred date',
                    value: _displayDateFromStoredValue(
                      _dateController.text.trim(),
                    ),
                    icon: Icons.calendar_today_rounded,
                    onEdit: () => _startEditingStep(
                      _RequestConversationStep.preferredDate,
                    ),
                  ),
                  _RequestSummaryRowData(
                    label: 'Time window',
                    value: _timeWindowController.text.trim(),
                    icon: Icons.schedule_rounded,
                    onEdit: () => _startEditingStep(
                      _RequestConversationStep.preferredTimeWindow,
                    ),
                  ),
                  _RequestSummaryRowData(
                    label: 'Work details',
                    value: _messageController.text.trim(),
                    icon: Icons.notes_rounded,
                    onEdit: () =>
                        _startEditingStep(_RequestConversationStep.message),
                  ),
                  if (_pendingSitePhotos.isNotEmpty)
                    _RequestSummaryRowData(
                      label: 'Site photos',
                      value:
                          '${_pendingSitePhotos.length} photo${_pendingSitePhotos.length == 1 ? '' : 's'} ready to upload with this request',
                      icon: Icons.photo_library_rounded,
                      onEdit: () =>
                          _startEditingStep(_RequestConversationStep.message),
                    ),
                ],
              ),
            ),
        ],
      ),
    );

    final sidePanel = _RequestInfoPanel(
      isEditing: _isEditing,
      onGenerateTestDraft: _isEditing || _isSubmitting
          ? null
          : _generateTestDraftConversation,
      currentStepLabel: _currentStepLabel(currentStep),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: fullBleedChat ? chatSurfaceColor : pageTopColor,
        surfaceTintColor: Colors.transparent,
      ),
      backgroundColor: fullBleedChat ? chatSurfaceColor : pageTopColor,
      body: wide
          ? DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    pageTopColor,
                    pageMiddleColor,
                    pageBottomColor,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const <double>[0, 0.42, 1],
                ),
              ),
              child: Stack(
                children: <Widget>[
                  Positioned(
                    top: 120,
                    left: -120,
                    child: _AmbientGlow(
                      diameter: 260,
                      color: Color.lerp(
                        AppTheme.cobalt,
                        Colors.white,
                        0.55,
                      )!.withValues(alpha: 0.16),
                    ),
                  ),
                  Positioned(
                    top: -120,
                    right: -90,
                    child: _AmbientGlow(
                      diameter: 280,
                      color: AppTheme.cobalt.withValues(alpha: 0.1),
                    ),
                  ),
                  Positioned(
                    bottom: -150,
                    left: -80,
                    child: _AmbientGlow(
                      diameter: 240,
                      color: AppTheme.clay.withValues(alpha: 0.2),
                    ),
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(flex: 7, child: chatPanel),
                            const SizedBox(width: 20),
                            Expanded(flex: 3, child: sidePanel),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: chatPanel,
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStepActions(
    BuildContext context,
    _RequestConversationStep currentStep,
  ) {
    if (currentStep == _RequestConversationStep.service) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: AppConfig.serviceLabels.entries
                .map(
                  (entry) => _ConversationChoiceChip(
                    label: entry.value,
                    onTap: () => _captureCurrentStep(entry.key),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      );
    }

    if (currentStep == _RequestConversationStep.addressConfirmation) {
      final suggestion = _pendingVerifiedAddress;
      final confirmLabel = suggestion == null
          ? 'Use detected address'
          : 'Use ${suggestion.city} · ${suggestion.postalCode}';

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _ConversationChoiceChip(
                label: confirmLabel,
                onTap: _confirmVerifiedAddress,
              ),
              OutlinedButton.icon(
                onPressed: _promptRetypedAddress,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
                ),
                icon: const Icon(Icons.edit_location_alt_rounded, size: 18),
                label: const Text('Retype address'),
              ),
            ],
          ),
        ),
      );
    }

    if (currentStep == _RequestConversationStep.preferredDate) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              ..._quickDateChoices().map(
                (date) => _ConversationChoiceChip(
                  label: _formatDisplayDate(date),
                  onTap: () => _captureCurrentStep(
                    _formatPayloadDate(date),
                    displayValue: _formatDisplayDate(date),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickDateFromCalendar,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
                ),
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: const Text('Open calendar'),
              ),
            ],
          ),
        ),
      );
    }

    if (currentStep == _RequestConversationStep.preferredTimeWindow) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _timeWindowChoices
                .map(
                  (choice) => _ConversationChoiceChip(
                    label: choice,
                    onTap: () => _captureCurrentStep(choice),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      );
    }

    if (currentStep == _RequestConversationStep.message) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: (_isSubmitting || _isUploadingSitePhotos)
                      ? null
                      : _pickSitePhotos,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  icon: _isUploadingSitePhotos
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.photo_camera_back_rounded, size: 18),
                  label: Text(
                    _pendingSitePhotos.isEmpty
                        ? 'Add site photos (max 5)'
                        : 'Add more photos (${_pendingSitePhotos.length}/5)',
                  ),
                ),
                if (_pendingSitePhotos.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_pendingSitePhotos.length} photo${_pendingSitePhotos.length == 1 ? '' : 's'} selected',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            if (_pendingSitePhotos.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                height: 108,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pendingSitePhotos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final photo = _pendingSitePhotos[index];
                    return _PendingSitePhotoCard(
                      file: photo,
                      onRemove: () => _removeSitePhoto(photo),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  String _placeholderForStep(_RequestConversationStep step) {
    return switch (step) {
      _RequestConversationStep.service => 'Type or choose a service',
      _RequestConversationStep.address => 'Street and number in Germany',
      _RequestConversationStep.addressConfirmation =>
        'Type confirm or enter a different address',
      _RequestConversationStep.city => 'City',
      _RequestConversationStep.postalCode => 'Postal code',
      _RequestConversationStep.preferredDate =>
        'Choose a date below or type 2026-04-02',
      _RequestConversationStep.preferredTimeWindow => 'Preferred access window',
      _RequestConversationStep.message =>
        'Describe the work that needs attention and add photos if helpful',
      _RequestConversationStep.done => 'Ready to submit',
    };
  }

  String _currentStepLabel(_RequestConversationStep step) {
    return switch (step) {
      _RequestConversationStep.service => 'Choosing service',
      _RequestConversationStep.address => 'Collecting address',
      _RequestConversationStep.addressConfirmation =>
        'Confirming detected city and post code',
      _RequestConversationStep.city => 'Collecting city',
      _RequestConversationStep.postalCode => 'Collecting postal code',
      _RequestConversationStep.preferredDate => 'Choosing preferred date',
      _RequestConversationStep.preferredTimeWindow => 'Choosing time window',
      _RequestConversationStep.message => 'Collecting work details',
      _RequestConversationStep.done => 'Ready to submit',
    };
  }

  String _displayDateFromStoredValue(String value) {
    final parsed = _parseDateInput(value);
    return parsed == null ? value : _formatDisplayDate(parsed);
  }

  List<_ProgressChipData> _buildProgressChips() {
    final current = _currentStep();
    return <_ProgressChipData>[
      _ProgressChipData(
        label: 'Service',
        isActive: current == _RequestConversationStep.service,
        isComplete: (_selectedServiceType ?? '').isNotEmpty,
      ),
      _ProgressChipData(
        label: 'Address',
        isActive:
            current == _RequestConversationStep.address ||
            current == _RequestConversationStep.addressConfirmation,
        isComplete: _addressController.text.trim().isNotEmpty,
      ),
      _ProgressChipData(
        label: 'City',
        isActive: current == _RequestConversationStep.city,
        isComplete: _cityController.text.trim().isNotEmpty,
      ),
      _ProgressChipData(
        label: 'Post code',
        isActive: current == _RequestConversationStep.postalCode,
        isComplete: _postalCodeController.text.trim().isNotEmpty,
      ),
      _ProgressChipData(
        label: 'Date',
        isActive: current == _RequestConversationStep.preferredDate,
        isComplete: _dateController.text.trim().isNotEmpty,
      ),
      _ProgressChipData(
        label: 'Time',
        isActive: current == _RequestConversationStep.preferredTimeWindow,
        isComplete: _timeWindowController.text.trim().isNotEmpty,
      ),
      _ProgressChipData(
        label: 'Details',
        isActive: current == _RequestConversationStep.message,
        isComplete: _messageController.text.trim().isNotEmpty,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEditing) {
      _seedConversationIfNeeded();
      return _buildConversationScaffold(context);
    }

    final requestsAsync = ref.watch(customerRequestsProvider);

    return requestsAsync.when(
      data: (List<ServiceRequestModel> requests) {
        ServiceRequestModel? request;
        for (final item in requests) {
          if (item.id == widget.requestId) {
            request = item;
            break;
          }
        }

        if (request == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Update Request')),
            body: const Center(
              child: Text(
                'Request not found. Return to your inbox and try again.',
              ),
            ),
          );
        }

        _hydrateFromRequest(request);
        _seedConversationIfNeeded(request: request);
        return _buildConversationScaffold(context);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Update Request')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('Update Request')),
        body: Center(child: Text(error.toString())),
      ),
    );
  }
}

class _RequestInfoPanel extends StatelessWidget {
  const _RequestInfoPanel({
    required this.isEditing,
    required this.currentStepLabel,
    this.onGenerateTestDraft,
  });

  final bool isEditing;
  final String currentStepLabel;
  final VoidCallback? onGenerateTestDraft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFE7DCCB)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppTheme.ink.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            isEditing ? 'How this update works' : 'How this intake works',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            isEditing
                ? 'The assistant keeps the request structured, then you save the revised version once everything looks right.'
                : 'The assistant collects the same request data as the old form, but in one continuous conversation.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 18),
          _InfoStatusPill(label: currentStepLabel),
          const SizedBox(height: 18),
          _InfoBullet(
            text:
                'Service, address, city, postal code, date, time window, and work details are still captured explicitly.',
          ),
          const SizedBox(height: 12),
          _InfoBullet(
            text:
                'Addresses are checked live first, so confirmed city and postal code can drop in automatically.',
          ),
          const SizedBox(height: 12),
          _InfoBullet(
            text:
                'When the date step appears, quick picks and the calendar stay directly in the flow.',
          ),
          const SizedBox(height: 12),
          _InfoBullet(
            text:
                'At the details step, customers can add up to 5 site photos to help the team prepare.',
          ),
          const SizedBox(height: 12),
          _InfoBullet(
            text:
                'You can edit any captured detail from the summary before sending or saving.',
          ),
          if (!isEditing) ...<Widget>[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onGenerateTestDraft,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Generate Test Draft'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoStatusPill extends StatelessWidget {
  const _InfoStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.cobalt.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppTheme.cobalt,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _InfoBullet extends StatelessWidget {
  const _InfoBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: AppTheme.pine,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ),
      ],
    );
  }
}

class _RequestSummaryCard extends StatelessWidget {
  const _RequestSummaryCard({
    required this.serviceLabel,
    required this.addressLine1,
    required this.city,
    required this.postalCode,
    required this.preferredDate,
    required this.preferredTimeWindow,
    required this.message,
    required this.rows,
    required this.submitLabel,
    required this.onSubmit,
    required this.isSubmitting,
  });

  final String serviceLabel;
  final String addressLine1;
  final String city;
  final String postalCode;
  final String preferredDate;
  final String preferredTimeWindow;
  final String message;
  final List<_RequestSummaryRowData> rows;
  final String submitLabel;
  final VoidCallback onSubmit;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Request summary',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Everything is structured and ready for submission. Edit any row if you want to refine it first.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.78),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RequestSummaryRow(data: row),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: isSubmitting ? null : onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.ink,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(isSubmitting ? 'Submitting...' : submitLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestSummaryRowData {
  const _RequestSummaryRowData({
    required this.label,
    required this.value,
    required this.icon,
    required this.onEdit,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onEdit;
}

class _RequestSummaryRow extends StatelessWidget {
  const _RequestSummaryRow({required this.data});

  final _RequestSummaryRowData data;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(data.icon, color: const Color(0xFF7ED2FF), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    data.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    data.value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: data.onEdit,
              icon: const Icon(Icons.edit_rounded, color: Colors.white),
              tooltip: 'Edit',
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestConversationMessage {
  const _RequestConversationMessage({
    required this.senderName,
    required this.text,
    required this.isAssistant,
  });

  const _RequestConversationMessage.assistant({required this.text})
    : senderName = 'Naima AI',
      isAssistant = true;

  const _RequestConversationMessage.user({required this.text})
    : senderName = 'You',
      isAssistant = false;

  final String senderName;
  final String text;
  final bool isAssistant;
}

class _ProgressChipData {
  const _ProgressChipData({
    required this.label,
    required this.isActive,
    required this.isComplete,
  });

  final String label;
  final bool isActive;
  final bool isComplete;
}

class _ProgressPill extends StatelessWidget {
  const _ProgressPill({
    required this.label,
    required this.isActive,
    required this.isComplete,
  });

  final String label;
  final bool isActive;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor;
    final Color foregroundColor;
    final inactiveColor = Color.lerp(AppTheme.ink, AppTheme.cobalt, 0.18)!;

    if (isComplete) {
      backgroundColor = const Color(0xFF173A28);
      foregroundColor = const Color(0xFF8FE7B1);
    } else if (isActive) {
      backgroundColor = AppTheme.cobalt;
      foregroundColor = Colors.white;
    } else {
      backgroundColor = inactiveColor;
      foregroundColor = Colors.white.withValues(alpha: 0.84);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ConversationChoiceChip extends StatelessWidget {
  const _ConversationChoiceChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chipColor = Color.lerp(AppTheme.ink, AppTheme.cobalt, 0.28)!;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: chipColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppTheme.ink.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _AddressPredictionsCard extends StatelessWidget {
  const _AddressPredictionsCard({
    required this.isLoading,
    required this.predictions,
    required this.onSelect,
  });

  final bool isLoading;
  final List<AddressPredictionResult> predictions;
  final Future<void> Function(AddressPredictionResult prediction) onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppTheme.ink.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Address suggestions in Germany',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppTheme.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            ...predictions.map(
              (prediction) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AddressPredictionTile(
                  prediction: prediction,
                  onTap: () {
                    onSelect(prediction);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressPredictionTile extends StatelessWidget {
  const _AddressPredictionTile({required this.prediction, required this.onTap});

  final AddressPredictionResult prediction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7FC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD8E2F1)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.cobalt.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: AppTheme.cobalt,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      prediction.primaryText.isEmpty
                          ? prediction.description
                          : prediction.primaryText,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (prediction.secondaryText.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        prediction.secondaryText,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF657287),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingSitePhotoCard extends StatelessWidget {
  const _PendingSitePhotoCard({required this.file, required this.onRemove});

  final PickedRequestAttachmentFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 134,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.memory(
                Uint8List.fromList(file.bytes),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: <Color>[
                    Colors.transparent,
                    AppTheme.ink.withValues(alpha: 0.75),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black.withValues(alpha: 0.35),
              shape: const CircleBorder(),
              child: IconButton(
                onPressed: onRemove,
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                tooltip: 'Remove photo',
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Text(
              file.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({required this.diameter, required this.color});

  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color,
              blurRadius: diameter * 0.4,
              spreadRadius: diameter * 0.05,
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestDraftSeed {
  const _RequestDraftSeed({
    required this.serviceType,
    required this.addressLine1,
    required this.city,
    required this.postalCode,
    required this.preferredTimeWindow,
    required this.message,
  });

  final String serviceType;
  final String addressLine1;
  final String city;
  final String postalCode;
  final String preferredTimeWindow;
  final String message;
}

class _VerifiedAddressSuggestion {
  const _VerifiedAddressSuggestion({
    required this.addressLine1,
    required this.city,
    required this.postalCode,
    required this.formattedAddress,
  });

  final String addressLine1;
  final String city;
  final String postalCode;
  final String formattedAddress;

  factory _VerifiedAddressSuggestion.fromResult(
    AddressVerificationResult result,
  ) {
    return _VerifiedAddressSuggestion(
      addressLine1: result.addressLine1,
      city: result.city,
      postalCode: result.postalCode,
      formattedAddress: result.formattedAddress,
    );
  }
}

enum _RequestConversationStep {
  service,
  address,
  addressConfirmation,
  city,
  postalCode,
  preferredDate,
  preferredTimeWindow,
  message,
  done,
}
