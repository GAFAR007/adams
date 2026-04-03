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
import '../../../core/i18n/app_language.dart';
import '../../../core/models/service_request_model.dart';
import '../../../core/network/api_client.dart';
import '../../auth/application/auth_controller.dart';
import '../../../shared/presentation/app_language_toggle.dart';
import '../../../shared/presentation/workspace_profile_action_button.dart';
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
  static const int _minimumRequestPhotos = 5;
  static const int _maximumRequestPhotos = 12;
  static const int _maximumRequestVideos = 2;

  static const List<_RequestDraftSeed> _requestDraftSeeds = <_RequestDraftSeed>[
    _RequestDraftSeed(
      serviceType: 'building_cleaning',
      addressLine1: '12 Clean Street',
      city: 'Monchengladbach',
      postalCode: '41189',
      preferredTimeWindow: 'Weekday morning (08:00 - 11:00)',
      message:
          'We need weekly building cleaning for the entrance, hallways, and kitchen before staff arrive.',
      accessMethod: 'meet_on_site',
      arrivalContactName: 'Marta Klein',
      arrivalContactPhone: '+4915111111111',
      accessNotes: 'Reception can escort the team to the service areas.',
    ),
    _RequestDraftSeed(
      serviceType: 'warehouse_hall_cleaning',
      addressLine1: '45 Warehouse Lane',
      city: 'Dusseldorf',
      postalCode: '40210',
      preferredTimeWindow: 'Afternoon (13:00 - 16:00)',
      message:
          'Please prepare a draft request for warehouse floor cleaning and dust removal around the loading area.',
      accessMethod: 'open_access',
      arrivalContactName: 'Sven Bauer',
      arrivalContactPhone: '+4915222222222',
      accessNotes: 'Loading bay access is open after 13:00.',
    ),
    _RequestDraftSeed(
      serviceType: 'window_glass_cleaning',
      addressLine1: '99 Glass Road',
      city: 'Cologne',
      postalCode: '50667',
      preferredTimeWindow: 'Flexible during business hours',
      message:
          'Storefront glass and upper window panels need cleaning before the next customer event.',
      accessMethod: 'meet_on_site',
      arrivalContactName: 'Fatima Kaya',
      arrivalContactPhone: '+4915333333333',
      accessNotes: 'Please ring the front bell and ask for the store manager.',
    ),
    _RequestDraftSeed(
      serviceType: 'winter_service',
      addressLine1: '28 Frost Avenue',
      city: 'Dortmund',
      postalCode: '44135',
      preferredTimeWindow: 'Early morning (06:00 - 09:00)',
      message:
          'We need snow clearing and grit service around the front entrance, bins, and parking access.',
      accessMethod: 'key_safe',
      arrivalContactName: 'Jonas Stein',
      arrivalContactPhone: '+4915444444444',
      accessNotes: 'Key safe next to the side gate. Code is shared by phone.',
    ),
    _RequestDraftSeed(
      serviceType: 'caretaker_service',
      addressLine1: '7 Garden Court',
      city: 'Essen',
      postalCode: '45127',
      preferredTimeWindow: 'Morning visit preferred',
      message:
          'Caretaker support is needed for a walkthrough, light fixes, and weekly property checks.',
      accessMethod: 'meet_on_site',
      arrivalContactName: 'Amina Yilmaz',
      arrivalContactPhone: '+4915555555555',
      accessNotes: 'Please meet at reception for handover.',
    ),
    _RequestDraftSeed(
      serviceType: 'garden_care',
      addressLine1: '31 Linden Park',
      city: 'Bonn',
      postalCode: '53111',
      preferredTimeWindow: 'Late morning (10:00 - 12:00)',
      message:
          'Please prepare a garden care draft for hedge trimming, leaf cleanup, and tidying shared outdoor areas.',
      accessMethod: 'open_access',
      arrivalContactName: 'Leonie Brandt',
      arrivalContactPhone: '+4915666666666',
      accessNotes: 'Garden gate remains open during working hours.',
    ),
    _RequestDraftSeed(
      serviceType: 'post_construction_cleaning',
      addressLine1: '63 Builder Square',
      city: 'Aachen',
      postalCode: '52062',
      preferredTimeWindow: 'Any time after 09:00',
      message:
          'A post-construction clean is needed after renovation, including dust removal, floors, and window frames.',
      accessMethod: 'reception_or_concierge',
      arrivalContactName: 'Daniel Weber',
      arrivalContactPhone: '+4915777777777',
      accessNotes:
          'Collect visitor badge from the concierge desk before entry.',
    ),
  ];

  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _postalCodeController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeWindowController = TextEditingController();
  final TextEditingController _accessMethodController = TextEditingController();
  final TextEditingController _arrivalContactNameController =
      TextEditingController();
  final TextEditingController _arrivalContactPhoneController =
      TextEditingController();
  final TextEditingController _accessNotesController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final Random _random = Random();
  final List<_RequestConversationMessage> _messages =
      <_RequestConversationMessage>[];
  final List<AddressPredictionResult> _addressPredictions =
      <AddressPredictionResult>[];
  final List<PickedRequestAttachmentFile> _pendingIntakePhotos =
      <PickedRequestAttachmentFile>[];
  final List<PickedRequestAttachmentFile> _pendingIntakeVideos =
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
  AppLanguage get _language => ref.read(appLanguageProvider);

  String _t({required String en, required String de}) {
    return _language.pick(en: en, de: de);
  }

  List<String> get _timeWindowChoices => <String>[
    _t(
      en: 'Weekday morning (08:00 - 11:00)',
      de: 'Wochentagmorgen (08:00 - 11:00)',
    ),
    _t(
      en: 'Late morning (10:00 - 12:00)',
      de: 'Später Vormittag (10:00 - 12:00)',
    ),
    _t(en: 'Afternoon (13:00 - 16:00)', de: 'Nachmittag (13:00 - 16:00)'),
    _t(en: 'Any time after 09:00', de: 'Jederzeit nach 09:00'),
    _t(
      en: 'Flexible during business hours',
      de: 'Flexibel während der Geschäftszeiten',
    ),
  ];

  List<String> get _accessMethodChoices => <String>[
    'meet_on_site',
    'reception_or_concierge',
    'key_safe',
    'open_access',
    'other',
  ];

  bool get _requiresEnhancedIntake => !_isEditing;

  bool get _hasRequiredIntakeMedia =>
      _pendingIntakePhotos.length >= _minimumRequestPhotos;

  List<PickedRequestAttachmentFile> get _pendingIntakeMediaFiles =>
      <PickedRequestAttachmentFile>[
        ..._pendingIntakePhotos,
        ..._pendingIntakeVideos,
      ];

  bool get _hasCapturedAccessDetails =>
      _accessMethodController.text.trim().isNotEmpty ||
      _arrivalContactNameController.text.trim().isNotEmpty ||
      _arrivalContactPhoneController.text.trim().isNotEmpty ||
      _accessNotesController.text.trim().isNotEmpty;

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
    _accessMethodController.dispose();
    _arrivalContactNameController.dispose();
    _arrivalContactPhoneController.dispose();
    _accessNotesController.dispose();
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

    if (_requiresEnhancedIntake &&
        _accessMethodController.text.trim().isEmpty) {
      return _RequestConversationStep.accessMethod;
    }

    if (_requiresEnhancedIntake &&
        _arrivalContactNameController.text.trim().isEmpty) {
      return _RequestConversationStep.arrivalContactName;
    }

    if (_requiresEnhancedIntake &&
        _arrivalContactPhoneController.text.trim().isEmpty) {
      return _RequestConversationStep.arrivalContactPhone;
    }

    if (_requiresEnhancedIntake && _accessNotesController.text.trim().isEmpty) {
      return _RequestConversationStep.accessNotes;
    }

    if (_messageController.text.trim().isEmpty) {
      return _RequestConversationStep.message;
    }

    if (_requiresEnhancedIntake && !_hasRequiredIntakeMedia) {
      return _RequestConversationStep.intakeMedia;
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
      return _t(
        en: 'I already have $serviceLabel noted from the previous step. What address should the team attend?',
        de: 'Ich habe $serviceLabel bereits aus dem vorherigen Schritt notiert. Welche Adresse soll das Team anfahren?',
      );
    }

    return _t(
      en: 'I will get this request ready like a live intake chat. Start by telling me which service you need.',
      de: 'Ich bereite diese Anfrage wie einen Live-Intake-Chat vor. Sagen Sie mir zuerst, welchen Service Sie brauchen.',
    );
  }

  String _editingGreeting({String? serviceLabel}) {
    final resolvedService =
        serviceLabel ?? _t(en: 'this request', de: 'diese Anfrage');
    return _t(
      en: 'I loaded your current $resolvedService request. Review the summary below and edit anything that has changed before saving.',
      de: 'Ich habe Ihre aktuelle Anfrage für $resolvedService geladen. Prüfen Sie die Übersicht unten und ändern Sie alles, was sich vor dem Speichern geändert hat.',
    );
  }

  String? get _selectedServiceLabel {
    final serviceType = _selectedServiceType;
    if (serviceType == null || serviceType.trim().isEmpty) {
      return null;
    }

    return AppConfig.serviceLabelFor(serviceType, language: _language);
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
    _accessMethodController.text = request.accessDetails?.accessMethod ?? '';
    _arrivalContactNameController.text =
        request.accessDetails?.arrivalContactName ?? '';
    _arrivalContactPhoneController.text =
        request.accessDetails?.arrivalContactPhone ?? '';
    _accessNotesController.text = request.accessDetails?.accessNotes ?? '';
    _messageController.text = request.message;
    _stepOverride = null;
    _pendingVerifiedAddress = null;
    _addressPredictions.clear();
    _pendingIntakePhotos.clear();
    _pendingIntakeVideos.clear();
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
      helpText: _t(en: 'Select preferred date', de: 'Wunschtermin auswählen'),
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
      _accessMethodController.text = seed.accessMethod;
      _arrivalContactNameController.text = seed.arrivalContactName;
      _arrivalContactPhoneController.text = seed.arrivalContactPhone;
      _accessNotesController.text = seed.accessNotes;
      _messageController.text = seed.message;
      _stepOverride = null;
      _pendingVerifiedAddress = null;
      _addressPredictions.clear();
      _pendingIntakePhotos.clear();
      _pendingIntakeVideos.clear();
      _lastAddressAutocompleteQuery = '';
      _isVerifyingAddress = false;
      _isLoadingAddressPredictions = false;
      _isUploadingSitePhotos = false;
      _addressVerificationFailureCount = 0;
      _hasSeededConversation = true;
      _messages
        ..clear()
        ..add(
          _RequestConversationMessage.user(
            text: _t(en: 'Generate test draft', de: 'Testentwurf erzeugen'),
          ),
        )
        ..add(
          _RequestConversationMessage.assistant(
            text: _t(
              en: 'I prepared a complete test draft for ${AppConfig.serviceLabelFor(seed.serviceType, language: _language)}. Add the required site photos or videos, then review the summary before sending.',
              de: 'Ich habe einen vollständigen Testentwurf für ${AppConfig.serviceLabelFor(seed.serviceType, language: _language)} vorbereitet. Fügen Sie die erforderlichen Standortfotos oder Videos hinzu und prüfen Sie dann die Übersicht vor dem Senden.',
            ),
          ),
        );
    });

    _scrollToBottom();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _t(
              en: 'Test draft loaded into the conversation',
              de: 'Testentwurf in die Unterhaltung geladen',
            ),
          ),
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
        userVisibleText = AppConfig.serviceLabelFor(
          matchedService,
          language: _language,
        );
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
      case _RequestConversationStep.accessMethod:
        final matchedAccessMethod = _matchAccessMethod(trimmedValue);
        if (matchedAccessMethod == null) {
          _pushAssistantMessage(_requiredFieldMessage(step));
          return;
        }
        _accessMethodController.text = matchedAccessMethod;
        userVisibleText = _accessMethodLabel(matchedAccessMethod);
      case _RequestConversationStep.arrivalContactName:
        _arrivalContactNameController.text = trimmedValue;
        userVisibleText = trimmedValue;
      case _RequestConversationStep.arrivalContactPhone:
        _arrivalContactPhoneController.text = trimmedValue;
        userVisibleText = trimmedValue;
      case _RequestConversationStep.accessNotes:
        _accessNotesController.text = trimmedValue;
        userVisibleText = trimmedValue;
      case _RequestConversationStep.message:
        _messageController.text = trimmedValue;
        userVisibleText = trimmedValue;
      case _RequestConversationStep.intakeMedia:
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
          text: _t(
            en: 'Use ${suggestion.city}, ${suggestion.postalCode}',
            de: '${suggestion.city}, ${suggestion.postalCode} verwenden',
          ),
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
          text: _t(
            en: 'No problem. Type the address again with the street and number, and I will check the city and postal code once more.',
            de: 'Kein Problem. Geben Sie die Adresse bitte noch einmal mit Straße und Hausnummer ein, dann prüfe ich Stadt und Postleitzahl erneut.',
          ),
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
            ? _t(
                en: 'Please enter a fuller address so staff know where to attend.',
                de: 'Bitte geben Sie eine vollständigere Adresse ein, damit das Team weiß, wohin es fahren soll.',
              )
            : null;
      case _RequestConversationStep.addressConfirmation:
        return null;
      case _RequestConversationStep.city:
        return value.length < 2
            ? _t(
                en: 'Please enter the city.',
                de: 'Bitte geben Sie die Stadt ein.',
              )
            : null;
      case _RequestConversationStep.postalCode:
        return value.length < 4
            ? _t(
                en: 'Please enter a valid postal code.',
                de: 'Bitte geben Sie eine gültige Postleitzahl ein.',
              )
            : null;
      case _RequestConversationStep.preferredDate:
        return _parseDateInput(value) == null ? _invalidDateMessage() : null;
      case _RequestConversationStep.preferredTimeWindow:
        return value.length < 4
            ? _t(
                en: 'Please share a usable time window.',
                de: 'Bitte nennen Sie ein brauchbares Zeitfenster.',
              )
            : null;
      case _RequestConversationStep.accessMethod:
        return _matchAccessMethod(value) != null
            ? null
            : _t(
                en: 'Choose one of the access options so staff know how to arrive.',
                de: 'Wählen Sie eine der Zugangsoptionen, damit das Team weiß, wie es ankommt.',
              );
      case _RequestConversationStep.arrivalContactName:
        return value.length < 2
            ? _t(
                en: 'Please enter the arrival contact name.',
                de: 'Bitte geben Sie den Namen der Ansprechperson vor Ort ein.',
              )
            : null;
      case _RequestConversationStep.arrivalContactPhone:
        return value.length < 7
            ? _t(
                en: 'Please enter a usable phone number for arrival.',
                de: 'Bitte geben Sie eine brauchbare Telefonnummer für die Ankunft an.',
              )
            : null;
      case _RequestConversationStep.accessNotes:
        return value.length < 4
            ? _t(
                en: 'Please add a short note about access.',
                de: 'Bitte ergänzen Sie einen kurzen Hinweis zum Zugang.',
              )
            : null;
      case _RequestConversationStep.message:
        return value.length < 12
            ? _t(
                en: 'Please add a little more detail about the work.',
                de: 'Bitte ergänzen Sie noch etwas mehr Details zur Arbeit.',
              )
            : null;
      case _RequestConversationStep.intakeMedia:
        return (!_requiresEnhancedIntake || _hasRequiredIntakeMedia)
            ? null
            : _t(
                en: 'Add at least 5 photos before continuing.',
                de: 'Fügen Sie vor dem Fortfahren mindestens 5 Fotos hinzu.',
              );
      case _RequestConversationStep.done:
        return null;
    }
  }

  String? _matchService(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    for (final key in AppConfig.serviceLabels.keys) {
      final englishLabel = AppConfig.serviceLabelFor(
        key,
        language: AppLanguage.english,
      ).toLowerCase();
      final germanLabel = AppConfig.serviceLabelFor(
        key,
        language: AppLanguage.german,
      ).toLowerCase();
      if (key.toLowerCase() == normalized ||
          englishLabel == normalized ||
          germanLabel == normalized) {
        return key;
      }
    }

    return null;
  }

  DateTime? _parseDateInput(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return null;
    }

    if (trimmed == 'today' || trimmed == 'heute') {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }

    if (trimmed == 'tomorrow' || trimmed == 'morgen') {
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

  String _accessMethodLabel(String value) {
    return switch (value.trim()) {
      'meet_on_site' => _t(en: 'Meet on site', de: 'Treffen vor Ort'),
      'reception_or_concierge' => _t(
        en: 'Reception or concierge',
        de: 'Empfang oder Concierge',
      ),
      'key_safe' => _t(en: 'Key safe', de: 'Schlüsseltresor'),
      'open_access' => _t(en: 'Open access', de: 'Freier Zugang'),
      'other' => _t(en: 'Other access arrangement', de: 'Andere Zugangslösung'),
      _ => value,
    };
  }

  String? _matchAccessMethod(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    for (final choice in _accessMethodChoices) {
      if (choice.toLowerCase() == normalized ||
          _accessMethodLabel(choice).toLowerCase() == normalized) {
        return choice;
      }
    }

    return null;
  }

  String _assistantFollowUp(
    _RequestConversationStep capturedStep,
    _RequestConversationStep nextStep,
  ) {
    if (nextStep == _RequestConversationStep.done) {
      return _isEditing
          ? _t(
              en: 'That is updated. Review the summary below and save your changes when you are ready.',
              de: 'Das ist aktualisiert. Prüfen Sie die Übersicht unten und speichern Sie Ihre Änderungen, wenn alles passt.',
            )
          : _t(
              en: 'Perfect. I have everything I need. Review the summary below and send the request when you are ready.',
              de: 'Perfekt. Ich habe jetzt alles, was ich brauche. Prüfen Sie die Übersicht unten und senden Sie die Anfrage ab, wenn Sie bereit sind.',
            );
    }

    return switch (capturedStep) {
      _RequestConversationStep.service => _t(
        en: 'Got it, ${_selectedServiceLabel ?? 'that service'} is noted. What address should the team attend?',
        de: 'Verstanden, ${_selectedServiceLabel ?? 'dieser Service'} ist notiert. Welche Adresse soll das Team anfahren?',
      ),
      _RequestConversationStep.address => _t(
        en: 'Thanks. Which city is that in?',
        de: 'Danke. In welcher Stadt liegt diese Adresse?',
      ),
      _RequestConversationStep.addressConfirmation => _t(
        en: 'Perfect. I will use ${_cityController.text.trim()} ${_postalCodeController.text.trim()} for that location. What date would you prefer? You can pick one below or open the calendar.',
        de: 'Perfekt. Ich verwende ${_cityController.text.trim()} ${_postalCodeController.text.trim()} für diesen Standort. Welchen Termin wünschen Sie? Sie können unten wählen oder den Kalender öffnen.',
      ),
      _RequestConversationStep.city => _t(
        en: 'Great. What postal code should I attach to this location?',
        de: 'Gut. Welche Postleitzahl soll ich für diesen Standort verwenden?',
      ),
      _RequestConversationStep.postalCode => _t(
        en: 'What date would you prefer? You can pick one below or open the calendar.',
        de: 'Welchen Termin wünschen Sie? Sie können unten wählen oder den Kalender öffnen.',
      ),
      _RequestConversationStep.preferredDate => _t(
        en: 'Nice. What time window works best for access?',
        de: 'Alles klar. Welches Zeitfenster passt am besten für den Zugang?',
      ),
      _RequestConversationStep.preferredTimeWindow => _t(
        en: _requiresEnhancedIntake
            ? 'Understood. How should the team get access when they arrive?'
            : 'Understood. Finally, describe the work so the team knows what to prepare.',
        de: _requiresEnhancedIntake
            ? 'Verstanden. Wie soll das Team bei der Ankunft Zugang erhalten?'
            : 'Verstanden. Beschreiben Sie zum Schluss bitte die Arbeit, damit das Team weiß, was vorbereitet werden muss.',
      ),
      _RequestConversationStep.accessMethod => _t(
        en: 'Thanks. Who should the team ask for on arrival?',
        de: 'Danke. Nach wem soll das Team bei der Ankunft fragen?',
      ),
      _RequestConversationStep.arrivalContactName => _t(
        en: 'Got it. What phone number should the team use if they need to call on arrival?',
        de: 'Alles klar. Welche Telefonnummer soll das Team bei Bedarf zur Ankunft verwenden?',
      ),
      _RequestConversationStep.arrivalContactPhone => _t(
        en: 'Perfect. Add any access notes, codes, or entry instructions the team should know.',
        de: 'Perfekt. Ergänzen Sie bitte Zugangshinweise, Codes oder Eintrittsanweisungen, die das Team kennen sollte.',
      ),
      _RequestConversationStep.accessNotes => _t(
        en: 'Now describe the work so the team knows what to prepare.',
        de: 'Beschreiben Sie nun die Arbeit, damit das Team weiß, was vorbereitet werden muss.',
      ),
      _RequestConversationStep.message => _t(
        en: _requiresEnhancedIntake
            ? 'Everything is captured. Add at least 5 photos and any optional videos from the intake step below before sending.'
            : 'Everything is captured. Review the request summary below before sending.',
        de: _requiresEnhancedIntake
            ? 'Alles ist erfasst. Fügen Sie im Intakeschritt unten mindestens 5 Fotos und optional Videos hinzu, bevor Sie senden.'
            : 'Alles ist erfasst. Prüfen Sie die Anfragenübersicht unten vor dem Senden.',
      ),
      _RequestConversationStep.intakeMedia => _t(
        en: _requiresEnhancedIntake
            ? 'Great. Review the summary below and send the request when you are ready.'
            : 'Media updated. Review the summary below and save when you are ready.',
        de: _requiresEnhancedIntake
            ? 'Gut. Prüfen Sie die Übersicht unten und senden Sie die Anfrage, wenn Sie bereit sind.'
            : 'Medien aktualisiert. Prüfen Sie die Übersicht unten und speichern Sie, wenn Sie bereit sind.',
      ),
      _RequestConversationStep.done => _stepPrompt(nextStep),
    };
  }

  String _stepPrompt(_RequestConversationStep step) {
    return switch (step) {
      _RequestConversationStep.service => _t(
        en: 'Which service do you need?',
        de: 'Welchen Service benötigen Sie?',
      ),
      _RequestConversationStep.address => _t(
        en: 'What Germany address should the team attend?',
        de: 'Welche Adresse in Deutschland soll das Team anfahren?',
      ),
      _RequestConversationStep.addressConfirmation => _t(
        en: 'Type confirm to use the detected city and postal code, or enter a different address.',
        de: 'Geben Sie bestätigen ein, um Stadt und Postleitzahl zu übernehmen, oder geben Sie eine andere Adresse ein.',
      ),
      _RequestConversationStep.city => _t(
        en: 'Which city is the job in?',
        de: 'In welcher Stadt liegt der Auftrag?',
      ),
      _RequestConversationStep.postalCode => _t(
        en: 'What postal code should I attach?',
        de: 'Welche Postleitzahl soll ich verwenden?',
      ),
      _RequestConversationStep.preferredDate => _t(
        en: 'What date would you prefer? Pick one below or open the calendar.',
        de: 'Welchen Termin wünschen Sie? Wählen Sie unten einen aus oder öffnen Sie den Kalender.',
      ),
      _RequestConversationStep.preferredTimeWindow => _t(
        en: 'What time window works best?',
        de: 'Welches Zeitfenster passt am besten?',
      ),
      _RequestConversationStep.accessMethod => _t(
        en: 'How should the team get access when they arrive?',
        de: 'Wie soll das Team bei der Ankunft Zugang erhalten?',
      ),
      _RequestConversationStep.arrivalContactName => _t(
        en: 'Who is the arrival contact on site?',
        de: 'Wer ist die Ansprechperson vor Ort für die Ankunft?',
      ),
      _RequestConversationStep.arrivalContactPhone => _t(
        en: 'What phone number should the team use on arrival?',
        de: 'Welche Telefonnummer soll das Team bei der Ankunft verwenden?',
      ),
      _RequestConversationStep.accessNotes => _t(
        en: 'Share any access notes, codes, or entry instructions.',
        de: 'Teilen Sie Zugangshinweise, Codes oder Eintrittsanweisungen mit.',
      ),
      _RequestConversationStep.message => _t(
        en: 'Describe the work so the team knows what to expect.',
        de: 'Beschreiben Sie die Arbeit, damit das Team weiß, was es erwartet.',
      ),
      _RequestConversationStep.intakeMedia => _t(
        en: _requiresEnhancedIntake
            ? 'Add at least 5 photos and any optional videos before sending.'
            : 'Add any extra intake photos or videos.',
        de: _requiresEnhancedIntake
            ? 'Fügen Sie vor dem Senden mindestens 5 Fotos und optional Videos hinzu.'
            : 'Fügen Sie weitere Intake-Fotos oder -Videos hinzu.',
      ),
      _RequestConversationStep.done => _t(
        en: 'Everything is ready to review.',
        de: 'Alles ist bereit zur Prüfung.',
      ),
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
      _RequestConversationStep.accessMethod =>
        _accessMethodController.text.trim().isEmpty
            ? ''
            : _accessMethodLabel(_accessMethodController.text.trim()),
      _RequestConversationStep.arrivalContactName =>
        _arrivalContactNameController.text.trim(),
      _RequestConversationStep.arrivalContactPhone =>
        _arrivalContactPhoneController.text.trim(),
      _RequestConversationStep.accessNotes =>
        _accessNotesController.text.trim(),
      _RequestConversationStep.message => _messageController.text.trim(),
      _RequestConversationStep.intakeMedia => '',
      _RequestConversationStep.done => '',
    };

    _scrollToBottom();
  }

  String _editingPrompt(_RequestConversationStep step) {
    return switch (step) {
      _RequestConversationStep.service => _t(
        en: 'No problem. Choose the updated service below or type it in.',
        de: 'Kein Problem. Wählen Sie unten den aktualisierten Service oder geben Sie ihn ein.',
      ),
      _RequestConversationStep.address => _t(
        en: 'What is the updated address?',
        de: 'Wie lautet die aktualisierte Adresse?',
      ),
      _RequestConversationStep.addressConfirmation => _t(
        en: 'Type confirm to keep the detected city and postal code, or type a different address.',
        de: 'Geben Sie bestätigen ein, um Stadt und Postleitzahl zu übernehmen, oder geben Sie eine andere Adresse ein.',
      ),
      _RequestConversationStep.city => _t(
        en: 'Which city should I use instead?',
        de: 'Welche Stadt soll ich stattdessen verwenden?',
      ),
      _RequestConversationStep.postalCode => _t(
        en: 'What is the updated postal code?',
        de: 'Wie lautet die aktualisierte Postleitzahl?',
      ),
      _RequestConversationStep.preferredDate => _t(
        en: 'Choose the updated preferred date below or open the calendar.',
        de: 'Wählen Sie unten den aktualisierten Wunschtermin oder öffnen Sie den Kalender.',
      ),
      _RequestConversationStep.preferredTimeWindow => _t(
        en: 'What time window should I use instead?',
        de: 'Welches Zeitfenster soll ich stattdessen verwenden?',
      ),
      _RequestConversationStep.accessMethod => _t(
        en: 'Choose the updated access method below.',
        de: 'Wählen Sie unten die aktualisierte Zugangsart.',
      ),
      _RequestConversationStep.arrivalContactName => _t(
        en: 'Who should the team ask for now?',
        de: 'Nach wem soll das Team nun fragen?',
      ),
      _RequestConversationStep.arrivalContactPhone => _t(
        en: 'What is the updated arrival phone number?',
        de: 'Wie lautet die aktualisierte Telefonnummer für die Ankunft?',
      ),
      _RequestConversationStep.accessNotes => _t(
        en: 'Share the updated access notes.',
        de: 'Teilen Sie die aktualisierten Zugangshinweise mit.',
      ),
      _RequestConversationStep.message => _t(
        en: 'Share the updated job description.',
        de: 'Teilen Sie die aktualisierte Arbeitsbeschreibung mit.',
      ),
      _RequestConversationStep.intakeMedia => _t(
        en: 'Add the updated intake photos or videos here.',
        de: 'Fügen Sie hier die aktualisierten Intake-Fotos oder -Videos hinzu.',
      ),
      _RequestConversationStep.done => _t(
        en: 'Review the summary and save when you are ready.',
        de: 'Prüfen Sie die Übersicht und speichern Sie, wenn alles passt.',
      ),
    };
  }

  String _requiredFieldMessage(_RequestConversationStep step) {
    return switch (step) {
      _RequestConversationStep.service => _t(
        en: 'Please choose a service first.',
        de: 'Bitte wählen Sie zuerst einen Service aus.',
      ),
      _RequestConversationStep.address => _t(
        en: 'Please enter the service address.',
        de: 'Bitte geben Sie die Einsatzadresse ein.',
      ),
      _RequestConversationStep.addressConfirmation => _t(
        en: 'Type confirm to use the detected city and postal code, or enter a different address.',
        de: 'Geben Sie bestätigen ein, um Stadt und Postleitzahl zu übernehmen, oder geben Sie eine andere Adresse ein.',
      ),
      _RequestConversationStep.city => _t(
        en: 'Please enter the city.',
        de: 'Bitte geben Sie die Stadt ein.',
      ),
      _RequestConversationStep.postalCode => _t(
        en: 'Please enter the postal code.',
        de: 'Bitte geben Sie die Postleitzahl ein.',
      ),
      _RequestConversationStep.preferredDate => _t(
        en: 'Please choose a date.',
        de: 'Bitte wählen Sie ein Datum aus.',
      ),
      _RequestConversationStep.preferredTimeWindow => _t(
        en: 'Please share a preferred time window.',
        de: 'Bitte nennen Sie ein bevorzugtes Zeitfenster.',
      ),
      _RequestConversationStep.accessMethod => _t(
        en: 'Please choose how the team will get access.',
        de: 'Bitte wählen Sie, wie das Team Zugang erhält.',
      ),
      _RequestConversationStep.arrivalContactName => _t(
        en: 'Please enter the arrival contact name.',
        de: 'Bitte geben Sie den Namen der Ansprechperson vor Ort ein.',
      ),
      _RequestConversationStep.arrivalContactPhone => _t(
        en: 'Please enter the arrival contact phone number.',
        de: 'Bitte geben Sie die Telefonnummer der Ansprechperson vor Ort ein.',
      ),
      _RequestConversationStep.accessNotes => _t(
        en: 'Please add the access notes.',
        de: 'Bitte ergänzen Sie die Zugangshinweise.',
      ),
      _RequestConversationStep.message => _t(
        en: 'Please describe the work that needs attention.',
        de: 'Bitte beschreiben Sie die Arbeit, die Aufmerksamkeit braucht.',
      ),
      _RequestConversationStep.intakeMedia => _t(
        en: _requiresEnhancedIntake
            ? 'Please add at least 5 photos before continuing.'
            : 'Add or remove intake media here, then return to the summary.',
        de: _requiresEnhancedIntake
            ? 'Bitte fügen Sie vor dem Fortfahren mindestens 5 Fotos hinzu.'
            : 'Fügen Sie hier Intake-Medien hinzu oder entfernen Sie sie und kehren Sie dann zur Übersicht zurück.',
      ),
      _RequestConversationStep.done => '',
    };
  }

  String _invalidServiceMessage() {
    return _t(
      en: 'Please choose one of the listed service types so I can route this correctly.',
      de: 'Bitte wählen Sie einen der aufgeführten Services aus, damit ich die Anfrage korrekt zuordnen kann.',
    );
  }

  String _invalidDateMessage() {
    return _t(
      en: 'Use one of the date shortcuts, open the calendar, or type a date like 2026-04-02.',
      de: 'Verwenden Sie eine der Datumsoptionen, öffnen Sie den Kalender oder geben Sie ein Datum wie 2026-04-02 ein.',
    );
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
    return _t(
      en: 'I found ${suggestion.addressLine1} in ${suggestion.city}, ${suggestion.postalCode}. Type confirm to use that city and postal code, or type the full address again if it needs correcting.',
      de: 'Ich habe ${suggestion.addressLine1} in ${suggestion.city}, ${suggestion.postalCode} gefunden. Geben Sie bestätigen ein, um Stadt und Postleitzahl zu übernehmen, oder geben Sie die vollständige Adresse erneut ein, falls etwas korrigiert werden muss.',
    );
  }

  String _addressRetypePrompt() {
    return _t(
      en: 'I could not clearly confirm the city and postal code from that address. Please type the full street address again, including the building number.',
      de: 'Ich konnte Stadt und Postleitzahl aus dieser Adresse nicht eindeutig bestätigen. Bitte geben Sie die vollständige Straßenadresse einschließlich Hausnummer erneut ein.',
    );
  }

  String _addressManualFallbackPrompt() {
    return _t(
      en: 'I still could not verify that address automatically, so I will continue manually. Which city is the job in?',
      de: 'Ich konnte diese Adresse weiterhin nicht automatisch prüfen, deshalb fahre ich manuell fort. In welcher Stadt liegt der Auftrag?',
    );
  }

  String _addressVerificationUnavailablePrompt() {
    return _t(
      en: 'I could not verify that address right now, so I will continue manually. Which city is the job in?',
      de: 'Ich konnte diese Adresse gerade nicht prüfen, deshalb fahre ich manuell fort. In welcher Stadt liegt der Auftrag?',
    );
  }

  void _pushAssistantMessage(String text) {
    setState(() {
      _messages.add(_RequestConversationMessage.assistant(text: text));
    });
    _scrollToBottom();
  }

  bool _isImageAttachment(PickedRequestAttachmentFile file) {
    final mimeType = file.mimeType.toLowerCase();
    if (mimeType.startsWith('image/')) {
      return true;
    }

    final lowerCaseName = file.name.toLowerCase();
    return lowerCaseName.endsWith('.png') ||
        lowerCaseName.endsWith('.jpg') ||
        lowerCaseName.endsWith('.jpeg') ||
        lowerCaseName.endsWith('.webp');
  }

  bool _isVideoAttachment(PickedRequestAttachmentFile file) {
    final mimeType = file.mimeType.toLowerCase();
    if (mimeType.startsWith('video/')) {
      return true;
    }

    final lowerCaseName = file.name.toLowerCase();
    return lowerCaseName.endsWith('.mp4') ||
        lowerCaseName.endsWith('.mov') ||
        lowerCaseName.endsWith('.webm');
  }

  Future<void> _pickIntakePhotos() async {
    if (_isSubmitting || _isUploadingSitePhotos) {
      return;
    }

    final remainingSlots = _maximumRequestPhotos - _pendingIntakePhotos.length;
    if (remainingSlots <= 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _t(
                en: 'You can add up to $_maximumRequestPhotos intake photos.',
                de: 'Sie können bis zu $_maximumRequestPhotos Intake-Fotos hinzufügen.',
              ),
            ),
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

      final imageFiles = pickedFiles.where(_isImageAttachment).toList();
      if (imageFiles.isEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                _t(
                  en: 'Only image files can be added as intake photos.',
                  de: 'Als Intake-Fotos können nur Bilddateien hinzugefügt werden.',
                ),
              ),
            ),
          );
        return;
      }

      final filesToAdd = imageFiles
          .take(remainingSlots)
          .toList(growable: false);
      setState(() {
        _pendingIntakePhotos.addAll(filesToAdd);
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _t(
                en: '${filesToAdd.length} intake photo${filesToAdd.length == 1 ? '' : 's'} added',
                de: '${filesToAdd.length} Intake-Foto${filesToAdd.length == 1 ? '' : 's'} hinzugefügt',
              ),
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

  Future<void> _pickIntakeVideos() async {
    if (_isSubmitting || _isUploadingSitePhotos) {
      return;
    }

    final remainingSlots = _maximumRequestVideos - _pendingIntakeVideos.length;
    if (remainingSlots <= 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _t(
                en: 'You can add up to $_maximumRequestVideos intake videos.',
                de: 'Sie können bis zu $_maximumRequestVideos Intake-Videos hinzufügen.',
              ),
            ),
          ),
        );
      return;
    }

    try {
      final pickedFiles = await pickRequestAttachmentFiles(
        maxFiles: remainingSlots,
      );

      if (!mounted || pickedFiles.isEmpty) {
        return;
      }

      final videoFiles = pickedFiles.where(_isVideoAttachment).toList();
      if (videoFiles.isEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                _t(
                  en: 'Only video files can be added as intake videos.',
                  de: 'Als Intake-Videos können nur Videodateien hinzugefügt werden.',
                ),
              ),
            ),
          );
        return;
      }

      final filesToAdd = videoFiles
          .take(remainingSlots)
          .toList(growable: false);
      setState(() {
        _pendingIntakeVideos.addAll(filesToAdd);
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _t(
                en: '${filesToAdd.length} intake video${filesToAdd.length == 1 ? '' : 's'} added',
                de: '${filesToAdd.length} Intake-Video${filesToAdd.length == 1 ? '' : 's'} hinzugefügt',
              ),
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

  void _removeIntakePhoto(PickedRequestAttachmentFile file) {
    setState(() {
      _pendingIntakePhotos.remove(file);
    });
  }

  void _removeIntakeVideo(PickedRequestAttachmentFile file) {
    setState(() {
      _pendingIntakeVideos.remove(file);
    });
  }

  void _completeIntakeMediaStep() {
    if (_requiresEnhancedIntake && !_hasRequiredIntakeMedia) {
      _pushAssistantMessage(
        _requiredFieldMessage(_RequestConversationStep.intakeMedia),
      );
      return;
    }

    setState(() {
      _stepOverride = null;
      _messages.add(
        _RequestConversationMessage.assistant(
          text: _assistantFollowUp(
            _RequestConversationStep.intakeMedia,
            _currentStep(),
          ),
        ),
      );
    });
    _scrollToBottom();
  }

  Future<int> _uploadPendingIntakeMedia(
    CustomerRepository repository,
    String requestId,
  ) async {
    final pendingFiles = _pendingIntakeMediaFiles;
    if (pendingFiles.isEmpty) {
      return 0;
    }

    setState(() {
      _isUploadingSitePhotos = true;
    });

    var uploadedCount = 0;

    try {
      for (var index = 0; index < pendingFiles.length; index += 1) {
        final file = pendingFiles[index];
        final label = _isVideoAttachment(file)
            ? _t(en: 'Intake video', de: 'Intake-Video')
            : _t(en: 'Intake photo', de: 'Intake-Foto');
        await repository.uploadRequestAttachment(
          requestId: requestId,
          bytes: file.bytes,
          fileName: file.name,
          mimeType: file.mimeType,
          caption: '$label ${index + 1} of ${pendingFiles.length}',
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
        'accessMethod': _accessMethodController.text.trim(),
        'arrivalContactName': _arrivalContactNameController.text.trim(),
        'arrivalContactPhone': _arrivalContactPhoneController.text.trim(),
        'accessNotes': _accessNotesController.text.trim(),
      };

      if (_requiresEnhancedIntake && !_hasRequiredIntakeMedia) {
        throw Exception(
          _t(
            en: 'Add at least $_minimumRequestPhotos photos before sending the request.',
            de: 'Fügen Sie vor dem Senden der Anfrage mindestens $_minimumRequestPhotos Fotos hinzu.',
          ),
        );
      }

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
          accessMethod: payload['accessMethod']!,
          arrivalContactName: payload['arrivalContactName']!,
          arrivalContactPhone: payload['arrivalContactPhone']!,
          accessNotes: payload['accessNotes']!,
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
          accessMethod: payload['accessMethod']!,
          arrivalContactName: payload['arrivalContactName']!,
          arrivalContactPhone: payload['arrivalContactPhone']!,
          accessNotes: payload['accessNotes']!,
          mediaFiles: _pendingIntakeMediaFiles,
        );
        requestId = createdRequest.id;
      }

      var uploadedAttachmentCount = 0;
      var attachmentUploadFailed = false;
      if (_isEditing &&
          requestId.isNotEmpty &&
          _pendingIntakeMediaFiles.isNotEmpty) {
        try {
          uploadedAttachmentCount = await _uploadPendingIntakeMedia(
            repository,
            requestId,
          );
        } catch (_) {
          attachmentUploadFailed = true;
        }
      }

      ref.invalidate(customerRequestsProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            attachmentUploadFailed
                ? (_isEditing
                      ? _t(
                          en: 'Request updated, but some intake files failed to upload',
                          de: 'Anfrage aktualisiert, aber einige Intake-Dateien konnten nicht hochgeladen werden',
                        )
                      : _t(
                          en: 'Request submitted, but some intake files failed to upload',
                          de: 'Anfrage gesendet, aber einige Intake-Dateien konnten nicht hochgeladen werden',
                        ))
                : uploadedAttachmentCount > 0
                ? (_isEditing
                      ? _t(
                          en: 'Request updated with $uploadedAttachmentCount intake file${uploadedAttachmentCount == 1 ? '' : 's'}',
                          de: 'Anfrage mit $uploadedAttachmentCount Intake-Datei${uploadedAttachmentCount == 1 ? '' : 'en'} aktualisiert',
                        )
                      : _t(
                          en: 'Request submitted with ${_pendingIntakePhotos.length} photo${_pendingIntakePhotos.length == 1 ? '' : 's'} and ${_pendingIntakeVideos.length} video${_pendingIntakeVideos.length == 1 ? '' : 's'}',
                          de: 'Anfrage mit ${_pendingIntakePhotos.length} Foto${_pendingIntakePhotos.length == 1 ? '' : 's'} und ${_pendingIntakeVideos.length} Video${_pendingIntakeVideos.length == 1 ? '' : 's'} gesendet',
                        ))
                : _isEditing
                ? _t(
                    en: 'Request updated successfully',
                    de: 'Anfrage erfolgreich aktualisiert',
                  )
                : _t(
                    en: 'Request submitted successfully',
                    de: 'Anfrage erfolgreich gesendet',
                  ),
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
          _pendingIntakePhotos.clear();
          _pendingIntakeVideos.clear();
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
    final weekdayLabels = _language.isGerman
        ? const <String>['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']
        : const <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final monthLabels = _language.isGerman
        ? const <String>[
            'Jan',
            'Feb',
            'Mär',
            'Apr',
            'Mai',
            'Jun',
            'Jul',
            'Aug',
            'Sep',
            'Okt',
            'Nov',
            'Dez',
          ]
        : const <String>[
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
    final authState = ref.watch(authControllerProvider);
    final title = _isEditing
        ? _t(en: 'Update Request', de: 'Anfrage aktualisieren')
        : _t(en: 'Create Request', de: 'Anfrage erstellen');
    final panelTitle = _isEditing
        ? _t(en: 'Update with AI', de: 'Mit KI aktualisieren')
        : _t(en: 'Request with AI', de: 'Mit KI anfragen');
    final currentStep = _currentStep();
    final showStepActions = currentStep != _RequestConversationStep.done;
    final showComposer =
        currentStep != _RequestConversationStep.done &&
        currentStep != _RequestConversationStep.intakeMedia;
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
                            ? _t(
                                en: 'Continue the request as a guided assistant conversation, then save the changes.',
                                de: 'Führen Sie die Anfrage als geführtes Assistentengespräch fort und speichern Sie danach die Änderungen.',
                              )
                            : _t(
                                en: 'Continue the request as a guided assistant conversation instead of filling a plain form.',
                                de: 'Führen Sie die Anfrage als geführtes Assistentengespräch fort, statt ein klassisches Formular auszufüllen.',
                              ),
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
                    label: Text(_t(en: 'Test Draft', de: 'Testentwurf')),
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
                              message.isAssistant
                                  ? _t(en: 'Naima AI', de: 'Naima KI')
                                  : _t(en: 'You', de: 'Sie'),
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
          if (showStepActions) ...<Widget>[
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
                  language: _language,
                  isLoading: _isLoadingAddressPredictions,
                  predictions: _addressPredictions,
                  onSelect: _selectAddressPrediction,
                ),
              ),
            if (showComposer)
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
                              : currentStep ==
                                    _RequestConversationStep.arrivalContactPhone
                              ? TextInputType.phone
                              : currentStep ==
                                        _RequestConversationStep.address ||
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
                            : () => _captureCurrentStep(
                                _chatInputController.text,
                              ),
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
                title: _t(en: 'Request summary', de: 'Anfrageübersicht'),
                subtitle: _t(
                  en: 'Everything is structured and ready for submission. Edit any row if you want to refine it first.',
                  de: 'Alles ist strukturiert und bereit zum Absenden. Bearbeiten Sie bei Bedarf einzelne Zeilen vorab.',
                ),
                addressLine1: _addressController.text.trim(),
                city: _cityController.text.trim(),
                postalCode: _postalCodeController.text.trim(),
                preferredDate: _displayDateFromStoredValue(
                  _dateController.text.trim(),
                ),
                preferredTimeWindow: _timeWindowController.text.trim(),
                message: _messageController.text.trim(),
                isSubmitting: _isSubmitting,
                submitLabel: _isEditing
                    ? _t(en: 'Save Changes', de: 'Änderungen speichern')
                    : _t(en: 'Send Request', de: 'Anfrage senden'),
                submittingLabel: _t(
                  en: 'Submitting...',
                  de: 'Wird gesendet...',
                ),
                editTooltip: _t(en: 'Edit', de: 'Bearbeiten'),
                onSubmit: _submitRequest,
                rows: <_RequestSummaryRowData>[
                  _RequestSummaryRowData(
                    label: _t(en: 'Service', de: 'Service'),
                    value:
                        _selectedServiceLabel ??
                        _t(en: 'Not selected', de: 'Nicht ausgewählt'),
                    icon: Icons.cleaning_services_rounded,
                    onEdit: () =>
                        _startEditingStep(_RequestConversationStep.service),
                  ),
                  _RequestSummaryRowData(
                    label: _t(en: 'Address', de: 'Adresse'),
                    value: _addressController.text.trim(),
                    icon: Icons.location_on_rounded,
                    onEdit: () =>
                        _startEditingStep(_RequestConversationStep.address),
                  ),
                  _RequestSummaryRowData(
                    label: _t(en: 'City', de: 'Stadt'),
                    value: _cityController.text.trim(),
                    icon: Icons.apartment_rounded,
                    onEdit: () =>
                        _startEditingStep(_RequestConversationStep.city),
                  ),
                  _RequestSummaryRowData(
                    label: _t(en: 'Postal code', de: 'Postleitzahl'),
                    value: _postalCodeController.text.trim(),
                    icon: Icons.markunread_mailbox_rounded,
                    onEdit: () =>
                        _startEditingStep(_RequestConversationStep.postalCode),
                  ),
                  _RequestSummaryRowData(
                    label: _t(en: 'Preferred date', de: 'Wunschtermin'),
                    value: _displayDateFromStoredValue(
                      _dateController.text.trim(),
                    ),
                    icon: Icons.calendar_today_rounded,
                    onEdit: () => _startEditingStep(
                      _RequestConversationStep.preferredDate,
                    ),
                  ),
                  _RequestSummaryRowData(
                    label: _t(en: 'Time window', de: 'Zeitfenster'),
                    value: _timeWindowController.text.trim(),
                    icon: Icons.schedule_rounded,
                    onEdit: () => _startEditingStep(
                      _RequestConversationStep.preferredTimeWindow,
                    ),
                  ),
                  _RequestSummaryRowData(
                    label: _t(en: 'Access method', de: 'Zugangsart'),
                    value: _accessMethodController.text.trim().isEmpty
                        ? _t(en: 'Not provided', de: 'Nicht angegeben')
                        : _accessMethodLabel(
                            _accessMethodController.text.trim(),
                          ),
                    icon: Icons.key_rounded,
                    onEdit: () => _startEditingStep(
                      _RequestConversationStep.accessMethod,
                    ),
                  ),
                  _RequestSummaryRowData(
                    label: _t(
                      en: 'Arrival contact',
                      de: 'Ansprechperson vor Ort',
                    ),
                    value: _arrivalContactNameController.text.trim().isEmpty
                        ? _t(en: 'Not provided', de: 'Nicht angegeben')
                        : _arrivalContactNameController.text.trim(),
                    icon: Icons.badge_rounded,
                    onEdit: () => _startEditingStep(
                      _RequestConversationStep.arrivalContactName,
                    ),
                  ),
                  _RequestSummaryRowData(
                    label: _t(en: 'Arrival phone', de: 'Telefon bei Ankunft'),
                    value: _arrivalContactPhoneController.text.trim().isEmpty
                        ? _t(en: 'Not provided', de: 'Nicht angegeben')
                        : _arrivalContactPhoneController.text.trim(),
                    icon: Icons.phone_rounded,
                    onEdit: () => _startEditingStep(
                      _RequestConversationStep.arrivalContactPhone,
                    ),
                  ),
                  _RequestSummaryRowData(
                    label: _t(en: 'Access notes', de: 'Zugangshinweise'),
                    value: _accessNotesController.text.trim().isEmpty
                        ? _t(en: 'Not provided', de: 'Nicht angegeben')
                        : _accessNotesController.text.trim(),
                    icon: Icons.lock_open_rounded,
                    onEdit: () =>
                        _startEditingStep(_RequestConversationStep.accessNotes),
                  ),
                  _RequestSummaryRowData(
                    label: _t(en: 'Work details', de: 'Arbeitsdetails'),
                    value: _messageController.text.trim(),
                    icon: Icons.notes_rounded,
                    onEdit: () =>
                        _startEditingStep(_RequestConversationStep.message),
                  ),
                  _RequestSummaryRowData(
                    label: _t(en: 'Intake media', de: 'Intake-Medien'),
                    value: _t(
                      en: '${_pendingIntakePhotos.length}/$_maximumRequestPhotos photos, ${_pendingIntakeVideos.length}/$_maximumRequestVideos videos ready',
                      de: '${_pendingIntakePhotos.length}/$_maximumRequestPhotos Fotos, ${_pendingIntakeVideos.length}/$_maximumRequestVideos Videos bereit',
                    ),
                    icon: Icons.perm_media_rounded,
                    onEdit: () =>
                        _startEditingStep(_RequestConversationStep.intakeMedia),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    final sidePanel = _RequestInfoPanel(
      language: _language,
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
        actions: <Widget>[
          WorkspaceCalendarActionButton(
            tooltip: _t(en: 'My calendar', de: 'Mein Kalender'),
            onPressed: () => context.go('/app/calendar'),
          ),
          WorkspaceProfileActionButton(
            tooltip: _t(en: 'My profile', de: 'Mein Profil'),
            onPressed: () => context.go('/app/profile'),
            displayName: authState.user?.fullName ?? '',
          ),
          AppLanguageToggle(
            language: _language,
            onChanged: ref.read(appLanguageProvider.notifier).setLanguage,
            compact: true,
          ),
          const SizedBox(width: 8),
        ],
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
            children: AppConfig.serviceLabels.keys
                .map(
                  (serviceType) => _ConversationChoiceChip(
                    label: AppConfig.serviceLabelFor(
                      serviceType,
                      language: _language,
                    ),
                    onTap: () => _captureCurrentStep(serviceType),
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
          ? _t(en: 'Use detected address', de: 'Erkannte Adresse verwenden')
          : _t(
              en: 'Use ${suggestion.city} · ${suggestion.postalCode}',
              de: '${suggestion.city} · ${suggestion.postalCode} verwenden',
            );

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
                label: Text(
                  _t(en: 'Retype address', de: 'Adresse neu eingeben'),
                ),
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
                label: Text(_t(en: 'Open calendar', de: 'Kalender öffnen')),
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

    if (currentStep == _RequestConversationStep.accessMethod) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _accessMethodChoices
                .map(
                  (choice) => _ConversationChoiceChip(
                    label: _accessMethodLabel(choice),
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
        child: Text(
          _requiresEnhancedIntake
              ? _t(
                  en: 'After the work details, you will add the required intake photos and any optional videos in the next step.',
                  de: 'Nach den Arbeitsdetails fügen Sie im nächsten Schritt die erforderlichen Intake-Fotos und optionale Videos hinzu.',
                )
              : _t(
                  en: 'Add as much detail as you can so the team can review the request properly.',
                  de: 'Fügen Sie so viele Details wie möglich hinzu, damit das Team die Anfrage richtig prüfen kann.',
                ),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.72),
            height: 1.35,
          ),
        ),
      );
    }

    if (currentStep == _RequestConversationStep.intakeMedia) {
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
                      : _pickIntakePhotos,
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
                    _t(
                      en: 'Add photos (${_pendingIntakePhotos.length}/$_maximumRequestPhotos, min $_minimumRequestPhotos)',
                      de: 'Fotos hinzufügen (${_pendingIntakePhotos.length}/$_maximumRequestPhotos, min. $_minimumRequestPhotos)',
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: (_isSubmitting || _isUploadingSitePhotos)
                      ? null
                      : _pickIntakeVideos,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  icon: const Icon(Icons.videocam_rounded, size: 18),
                  label: Text(
                    _t(
                      en: 'Add videos (${_pendingIntakeVideos.length}/$_maximumRequestVideos)',
                      de: 'Videos hinzufügen (${_pendingIntakeVideos.length}/$_maximumRequestVideos)',
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      (_isSubmitting ||
                          (_requiresEnhancedIntake && !_hasRequiredIntakeMedia))
                      ? null
                      : _completeIntakeMediaStep,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.cobalt.withValues(alpha: 0.16),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.task_alt_rounded, size: 18),
                  label: Text(
                    _t(en: 'Continue to summary', de: 'Zur Übersicht weiter'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _t(
                en: _requiresEnhancedIntake
                    ? 'New requests need at least $_minimumRequestPhotos photos. Videos are optional and can help with remote review.'
                    : 'You can add extra photos or videos here while the request is still unquoted.',
                de: _requiresEnhancedIntake
                    ? 'Neue Anfragen benötigen mindestens $_minimumRequestPhotos Fotos. Videos sind optional und können bei der Fernprüfung helfen.'
                    : 'Sie können hier zusätzliche Fotos oder Videos hinzufügen, solange die Anfrage noch nicht angeboten wurde.',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.68),
                height: 1.35,
              ),
            ),
            if (_pendingIntakeMediaFiles.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                height: 108,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pendingIntakeMediaFiles.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final file = _pendingIntakeMediaFiles[index];
                    final isVideo = _isVideoAttachment(file);
                    return _PendingRequestMediaCard(
                      language: _language,
                      file: file,
                      isVideo: isVideo,
                      onRemove: () => isVideo
                          ? _removeIntakeVideo(file)
                          : _removeIntakePhoto(file),
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
      _RequestConversationStep.service => _t(
        en: 'Type or choose a service',
        de: 'Service eingeben oder auswählen',
      ),
      _RequestConversationStep.address => _t(
        en: 'Street and number in Germany',
        de: 'Straße und Hausnummer in Deutschland',
      ),
      _RequestConversationStep.addressConfirmation => _t(
        en: 'Type confirm or enter a different address',
        de: 'Bestätigen eingeben oder andere Adresse eingeben',
      ),
      _RequestConversationStep.city => _t(en: 'City', de: 'Stadt'),
      _RequestConversationStep.postalCode => _t(
        en: 'Postal code',
        de: 'Postleitzahl',
      ),
      _RequestConversationStep.preferredDate => _t(
        en: 'Choose a date below or type 2026-04-02',
        de: 'Datum unten wählen oder 2026-04-02 eingeben',
      ),
      _RequestConversationStep.preferredTimeWindow => _t(
        en: 'Preferred access window',
        de: 'Bevorzugtes Zeitfenster',
      ),
      _RequestConversationStep.accessMethod => _t(
        en: 'Choose an access method below',
        de: 'Wählen Sie unten eine Zugangsart',
      ),
      _RequestConversationStep.arrivalContactName => _t(
        en: 'Arrival contact name',
        de: 'Name der Ansprechperson vor Ort',
      ),
      _RequestConversationStep.arrivalContactPhone => _t(
        en: 'Arrival contact phone number',
        de: 'Telefonnummer der Ansprechperson vor Ort',
      ),
      _RequestConversationStep.accessNotes => _t(
        en: 'Access notes, codes, or entry instructions',
        de: 'Zugangshinweise, Codes oder Eintrittsanweisungen',
      ),
      _RequestConversationStep.message => _t(
        en: 'Describe the work that needs attention',
        de: 'Beschreiben Sie die Arbeit, die Aufmerksamkeit braucht',
      ),
      _RequestConversationStep.intakeMedia => _t(
        en: 'Add the required intake photos and optional videos',
        de: 'Fügen Sie die erforderlichen Intake-Fotos und optionale Videos hinzu',
      ),
      _RequestConversationStep.done => _t(
        en: 'Ready to submit',
        de: 'Bereit zum Senden',
      ),
    };
  }

  String _currentStepLabel(_RequestConversationStep step) {
    return switch (step) {
      _RequestConversationStep.service => _t(
        en: 'Choosing service',
        de: 'Service auswählen',
      ),
      _RequestConversationStep.address => _t(
        en: 'Collecting address',
        de: 'Adresse erfassen',
      ),
      _RequestConversationStep.addressConfirmation => _t(
        en: 'Confirming detected city and post code',
        de: 'Erkannte Stadt und Postleitzahl bestätigen',
      ),
      _RequestConversationStep.city => _t(
        en: 'Collecting city',
        de: 'Stadt erfassen',
      ),
      _RequestConversationStep.postalCode => _t(
        en: 'Collecting postal code',
        de: 'Postleitzahl erfassen',
      ),
      _RequestConversationStep.preferredDate => _t(
        en: 'Choosing preferred date',
        de: 'Wunschtermin wählen',
      ),
      _RequestConversationStep.preferredTimeWindow => _t(
        en: 'Choosing time window',
        de: 'Zeitfenster wählen',
      ),
      _RequestConversationStep.accessMethod => _t(
        en: 'Choosing access method',
        de: 'Zugangsart wählen',
      ),
      _RequestConversationStep.arrivalContactName => _t(
        en: 'Collecting arrival contact',
        de: 'Ansprechperson erfassen',
      ),
      _RequestConversationStep.arrivalContactPhone => _t(
        en: 'Collecting arrival phone',
        de: 'Ankunftstelefon erfassen',
      ),
      _RequestConversationStep.accessNotes => _t(
        en: 'Collecting access notes',
        de: 'Zugangshinweise erfassen',
      ),
      _RequestConversationStep.message => _t(
        en: 'Collecting work details',
        de: 'Arbeitsdetails erfassen',
      ),
      _RequestConversationStep.intakeMedia => _t(
        en: 'Collecting intake media',
        de: 'Intake-Medien erfassen',
      ),
      _RequestConversationStep.done => _t(
        en: 'Ready to submit',
        de: 'Bereit zum Senden',
      ),
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
        label: _t(en: 'Service', de: 'Service'),
        isActive: current == _RequestConversationStep.service,
        isComplete: (_selectedServiceType ?? '').isNotEmpty,
      ),
      _ProgressChipData(
        label: _t(en: 'Address', de: 'Adresse'),
        isActive:
            current == _RequestConversationStep.address ||
            current == _RequestConversationStep.addressConfirmation,
        isComplete: _addressController.text.trim().isNotEmpty,
      ),
      _ProgressChipData(
        label: _t(en: 'City', de: 'Stadt'),
        isActive: current == _RequestConversationStep.city,
        isComplete: _cityController.text.trim().isNotEmpty,
      ),
      _ProgressChipData(
        label: _t(en: 'Post code', de: 'PLZ'),
        isActive: current == _RequestConversationStep.postalCode,
        isComplete: _postalCodeController.text.trim().isNotEmpty,
      ),
      _ProgressChipData(
        label: _t(en: 'Date', de: 'Datum'),
        isActive: current == _RequestConversationStep.preferredDate,
        isComplete: _dateController.text.trim().isNotEmpty,
      ),
      _ProgressChipData(
        label: _t(en: 'Time', de: 'Zeit'),
        isActive: current == _RequestConversationStep.preferredTimeWindow,
        isComplete: _timeWindowController.text.trim().isNotEmpty,
      ),
      if (_requiresEnhancedIntake || _hasCapturedAccessDetails)
        _ProgressChipData(
          label: _t(en: 'Access', de: 'Zugang'),
          isActive:
              current == _RequestConversationStep.accessMethod ||
              current == _RequestConversationStep.arrivalContactName ||
              current == _RequestConversationStep.arrivalContactPhone ||
              current == _RequestConversationStep.accessNotes,
          isComplete:
              _accessMethodController.text.trim().isNotEmpty &&
              _arrivalContactNameController.text.trim().isNotEmpty &&
              _arrivalContactPhoneController.text.trim().isNotEmpty &&
              _accessNotesController.text.trim().isNotEmpty,
        ),
      _ProgressChipData(
        label: _t(en: 'Details', de: 'Details'),
        isActive: current == _RequestConversationStep.message,
        isComplete: _messageController.text.trim().isNotEmpty,
      ),
      if (_requiresEnhancedIntake || _pendingIntakeMediaFiles.isNotEmpty)
        _ProgressChipData(
          label: _t(en: 'Media', de: 'Medien'),
          isActive: current == _RequestConversationStep.intakeMedia,
          isComplete: !_requiresEnhancedIntake || _hasRequiredIntakeMedia,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);

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
            appBar: AppBar(
              title: Text(
                _t(en: 'Update Request', de: 'Anfrage aktualisieren'),
              ),
            ),
            body: Center(
              child: Text(
                _t(
                  en: 'Request not found. Return to your inbox and try again.',
                  de: 'Anfrage nicht gefunden. Kehren Sie in Ihr Postfach zurück und versuchen Sie es erneut.',
                ),
              ),
            ),
          );
        }

        _hydrateFromRequest(request);
        _seedConversationIfNeeded(request: request);
        return _buildConversationScaffold(context);
      },
      loading: () => Scaffold(
        appBar: AppBar(
          title: Text(_t(en: 'Update Request', de: 'Anfrage aktualisieren')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace stackTrace) => Scaffold(
        appBar: AppBar(
          title: Text(_t(en: 'Update Request', de: 'Anfrage aktualisieren')),
        ),
        body: Center(child: Text(error.toString())),
      ),
    );
  }
}

class _RequestInfoPanel extends StatelessWidget {
  const _RequestInfoPanel({
    required this.language,
    required this.isEditing,
    required this.currentStepLabel,
    this.onGenerateTestDraft,
  });

  final AppLanguage language;
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
        border: Border.all(color: AppTheme.border),
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
            language.pick(
              en: isEditing ? 'How this update works' : 'How this intake works',
              de: isEditing
                  ? 'So funktioniert diese Aktualisierung'
                  : 'So funktioniert diese Anfrage',
            ),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            language.pick(
              en: isEditing
                  ? 'The assistant keeps the request structured, then you save the revised version once everything looks right.'
                  : 'The assistant collects the same request data as the old form, but in one continuous conversation.',
              de: isEditing
                  ? 'Der Assistent hält die Anfrage strukturiert, dann speichern Sie die überarbeitete Version, sobald alles passt.'
                  : 'Der Assistent erfasst dieselben Anfragedaten wie das frühere Formular, aber in einem durchgehenden Gespräch.',
            ),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 18),
          _InfoStatusPill(label: currentStepLabel),
          const SizedBox(height: 18),
          _InfoBullet(
            text: language.pick(
              en: 'Service, address, city, postal code, date, time window, and work details are still captured explicitly.',
              de: 'Service, Adresse, Stadt, Postleitzahl, Datum, Zeitfenster und Arbeitsdetails werden weiterhin eindeutig erfasst.',
            ),
          ),
          const SizedBox(height: 12),
          _InfoBullet(
            text: language.pick(
              en: 'Addresses are checked live first, so confirmed city and postal code can drop in automatically.',
              de: 'Adressen werden zuerst live geprüft, sodass bestätigte Stadt und Postleitzahl automatisch übernommen werden können.',
            ),
          ),
          const SizedBox(height: 12),
          _InfoBullet(
            text: language.pick(
              en: 'When the date step appears, quick picks and the calendar stay directly in the flow.',
              de: 'Wenn der Datumsschritt erscheint, bleiben Schnellwahl und Kalender direkt im Ablauf.',
            ),
          ),
          const SizedBox(height: 12),
          _InfoBullet(
            text: language.pick(
              en: 'New requests now require structured access details: access method, arrival contact, arrival phone, and access notes.',
              de: 'Neue Anfragen erfordern jetzt strukturierte Zugangsdaten: Zugangsart, Ansprechperson bei Ankunft, Ankunftstelefon und Zugangshinweise.',
            ),
          ),
          const SizedBox(height: 12),
          _InfoBullet(
            text: language.pick(
              en: 'Before a new request can be sent, it must include at least 5 photos. Videos stay optional for remote review.',
              de: 'Bevor eine neue Anfrage gesendet werden kann, muss sie mindestens 5 Fotos enthalten. Videos bleiben für die Fernprüfung optional.',
            ),
          ),
          const SizedBox(height: 12),
          _InfoBullet(
            text: language.pick(
              en: 'You can edit any captured detail from the summary before sending or saving.',
              de: 'Sie können jedes erfasste Detail in der Übersicht vor dem Senden oder Speichern bearbeiten.',
            ),
          ),
          if (!isEditing) ...<Widget>[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onGenerateTestDraft,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(
                  language.pick(
                    en: 'Generate Test Draft',
                    de: 'Testentwurf erzeugen',
                  ),
                ),
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
    required this.title,
    required this.subtitle,
    required this.serviceLabel,
    required this.addressLine1,
    required this.city,
    required this.postalCode,
    required this.preferredDate,
    required this.preferredTimeWindow,
    required this.message,
    required this.rows,
    required this.submitLabel,
    required this.submittingLabel,
    required this.editTooltip,
    required this.onSubmit,
    required this.isSubmitting,
  });

  final String title;
  final String subtitle;
  final String serviceLabel;
  final String addressLine1;
  final String city;
  final String postalCode;
  final String preferredDate;
  final String preferredTimeWindow;
  final String message;
  final List<_RequestSummaryRowData> rows;
  final String submitLabel;
  final String submittingLabel;
  final String editTooltip;
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
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.78),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RequestSummaryRow(data: row, editTooltip: editTooltip),
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
                child: Text(isSubmitting ? submittingLabel : submitLabel),
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
  const _RequestSummaryRow({required this.data, required this.editTooltip});

  final _RequestSummaryRowData data;
  final String editTooltip;

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
              tooltip: editTooltip,
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
    required this.language,
    required this.isLoading,
    required this.predictions,
    required this.onSelect,
  });

  final AppLanguage language;
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
              language.pick(
                en: 'Address suggestions in Germany',
                de: 'Adressvorschläge in Deutschland',
              ),
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
          color: AppTheme.infoSurface.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.info.withValues(alpha: 0.18)),
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

class _PendingRequestMediaCard extends StatelessWidget {
  const _PendingRequestMediaCard({
    required this.language,
    required this.file,
    required this.isVideo,
    required this.onRemove,
  });

  final AppLanguage language;
  final PickedRequestAttachmentFile file;
  final bool isVideo;
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
              child: isVideo
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppTheme.cobalt.withValues(alpha: 0.26),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.videocam_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    )
                  : Image.memory(
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
                tooltip: language.pick(
                  en: isVideo ? 'Remove video' : 'Remove photo',
                  de: isVideo ? 'Video entfernen' : 'Foto entfernen',
                ),
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
              '${isVideo ? 'Video' : 'Photo'} · ${file.name}',
              maxLines: 3,
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
    required this.accessMethod,
    required this.arrivalContactName,
    required this.arrivalContactPhone,
    required this.accessNotes,
  });

  final String serviceType;
  final String addressLine1;
  final String city;
  final String postalCode;
  final String preferredTimeWindow;
  final String message;
  final String accessMethod;
  final String arrivalContactName;
  final String arrivalContactPhone;
  final String accessNotes;
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
  accessMethod,
  arrivalContactName,
  arrivalContactPhone,
  accessNotes,
  message,
  intakeMedia,
  done,
}
