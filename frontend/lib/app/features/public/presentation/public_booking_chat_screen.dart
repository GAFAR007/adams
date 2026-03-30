library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_config.dart';
import '../../../core/models/public_company_profile.dart';
import '../../../core/network/api_client.dart';
import '../../../theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../data/public_repository.dart';
import '../data/public_service_concierge_repository.dart';
import 'public_site_shell.dart';

class PublicBookingChatScreen extends ConsumerStatefulWidget {
  const PublicBookingChatScreen({
    super.key,
    this.initialLanguageCode,
    this.initialServiceKey,
  });

  final String? initialLanguageCode;
  final String? initialServiceKey;

  @override
  ConsumerState<PublicBookingChatScreen> createState() =>
      _PublicBookingChatScreenState();
}

class _PublicBookingChatScreenState
    extends ConsumerState<PublicBookingChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_BookingChatMessage> _messages = <_BookingChatMessage>[];
  final _BookingDraft _draft = _BookingDraft();

  late PublicSiteLanguage _language;
  bool _hasSeededConversation = false;
  bool _isSending = false;
  bool _isCreatingAccount = false;
  bool _isSensitiveInputVisible = false;

  @override
  void initState() {
    super.initState();
    _language = publicSiteLanguageFromCode(widget.initialLanguageCode);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _languageCode => publicSiteLanguageCode(_language);

  void _seedConversationIfNeeded(PublicCompanyProfileModel profile) {
    if (_hasSeededConversation) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasSeededConversation) {
        return;
      }

      final initialService = _resolveInitialService(profile);
      if (initialService != null) {
        _draft.serviceKey = initialService.key;
        _draft.serviceName = resolvePublicText(initialService.label, _language);
      }

      setState(() {
        _hasSeededConversation = true;
        _messages.add(
          _BookingChatMessage.assistant(
            text: _initialAssistantGreeting(profile, initialService),
          ),
        );
      });

      _scrollToBottom();
    });
  }

  PublicServiceItem? _resolveInitialService(PublicCompanyProfileModel profile) {
    final serviceKey = (widget.initialServiceKey ?? '').trim();
    if (serviceKey.isEmpty) {
      return null;
    }

    for (final item in profile.serviceLabels) {
      if (item.key == serviceKey) {
        return item;
      }
    }

    return null;
  }

  String _initialAssistantGreeting(
    PublicCompanyProfileModel profile,
    PublicServiceItem? initialService,
  ) {
    final serviceName = initialService == null
        ? ''
        : resolvePublicText(initialService.label, _language);

    if (_language == PublicSiteLanguage.german) {
      if (serviceName.isNotEmpty) {
        return 'Hallo, ich bin Naima vom ${profile.companyName} Service Desk. Ich begleite Sie jetzt kurz durch die Buchung fur $serviceName und richte danach Ihren sicheren Kundenzugang ein. Wie lautet Ihr Vorname?';
      }

      return 'Hallo, ich bin Naima vom ${profile.companyName} Service Desk. Ich begleite Sie kurz durch die Buchung und richte danach Ihren sicheren Kundenzugang ein. Wahlen Sie zuerst die gewunschte Leistung.';
    }

    if (serviceName.isNotEmpty) {
      return "Hi, I'm Naima from ${profile.companyName}. I'll guide you through a quick booking setup for $serviceName, then create your secure customer access. What's your first name?";
    }

    return "Hi, I'm Naima from ${profile.companyName}. I'll guide you through a quick booking setup, then create your secure customer access. Start by choosing the service you need.";
  }

  _BookingStep _currentStep() {
    if (_draft.serviceKey.isEmpty && _draft.serviceName.isEmpty) {
      return _BookingStep.service;
    }

    if (_draft.firstName.isEmpty) {
      return _BookingStep.firstName;
    }

    if (_draft.lastName.isEmpty) {
      return _BookingStep.lastName;
    }

    if (_draft.email.isEmpty) {
      return _BookingStep.email;
    }

    if (_draft.verificationToken.isEmpty) {
      return _BookingStep.emailCode;
    }

    if (_draft.phone.isEmpty) {
      return _BookingStep.phone;
    }

    if (_draft.password.isEmpty) {
      return _BookingStep.password;
    }

    if (_draft.passwordConfirmation.isEmpty) {
      return _BookingStep.confirmPassword;
    }

    return _BookingStep.done;
  }

  List<String> _completedSteps() {
    final steps = <String>[];
    if (_draft.serviceKey.isNotEmpty || _draft.serviceName.isNotEmpty) {
      steps.add('service');
    }
    if (_draft.firstName.isNotEmpty) {
      steps.add('firstName');
    }
    if (_draft.lastName.isNotEmpty) {
      steps.add('lastName');
    }
    if (_draft.email.isNotEmpty) {
      steps.add('email');
    }
    if (_draft.verificationToken.isNotEmpty) {
      steps.add('emailVerified');
    }
    if (_draft.phone.isNotEmpty) {
      steps.add('phone');
    }
    if (_draft.password.isNotEmpty) {
      steps.add('password');
    }
    return steps;
  }

  Future<void> _handleSubmit(
    PublicCompanyProfileModel profile, {
    PublicServiceItem? selectedService,
  }) async {
    if (_isSending || _isCreatingAccount) {
      return;
    }

    final step = _currentStep();
    if (step == _BookingStep.done) {
      return;
    }

    final rawInput = selectedService == null
        ? _inputController.text.trim()
        : resolvePublicText(selectedService.label, _language);

    if (rawInput.isEmpty) {
      return;
    }

    final validationError = _validateInput(
      profile,
      step,
      rawInput,
      selectedService: selectedService,
    );
    if (validationError != null) {
      _pushAssistantMessage(validationError);
      return;
    }

    if (step == _BookingStep.email) {
      await _handleEmailStep(rawInput);
      return;
    }

    if (step == _BookingStep.emailCode) {
      await _handleEmailCodeStep(rawInput);
      return;
    }

    var userVisibleText = rawInput;
    if (step == _BookingStep.service) {
      final service = selectedService ?? _matchService(profile, rawInput);
      if (service == null) {
        _pushAssistantMessage(_invalidServiceMessage());
        return;
      }
      _draft.serviceKey = service.key;
      _draft.serviceName = resolvePublicText(service.label, _language);
      userVisibleText = _draft.serviceName;
    } else if (step == _BookingStep.firstName) {
      _draft.firstName = rawInput;
    } else if (step == _BookingStep.lastName) {
      _draft.lastName = rawInput;
    } else if (step == _BookingStep.phone) {
      _draft.phone = rawInput;
    } else if (step == _BookingStep.password) {
      _draft.password = rawInput;
      userVisibleText = _language == PublicSiteLanguage.german
          ? 'Sicheres Passwort erstellt'
          : 'Secure password created';
    } else if (step == _BookingStep.confirmPassword) {
      _draft.passwordConfirmation = rawInput;
      userVisibleText = _language == PublicSiteLanguage.german
          ? 'Passwort bestaetigt'
          : 'Password confirmed';
    }

    _inputController.clear();

    if (step == _BookingStep.password || step == _BookingStep.confirmPassword) {
      setState(() {
        _isSensitiveInputVisible = false;
        _messages.add(_BookingChatMessage.user(text: userVisibleText));
        _messages.add(
          _BookingChatMessage.assistant(
            text: step == _BookingStep.password
                ? _confirmPasswordPrompt()
                : _passwordConfirmedReply(),
          ),
        );
      });
      _scrollToBottom();
      return;
    }

    setState(() {
      _messages.add(_BookingChatMessage.user(text: userVisibleText));
      _isSending = true;
    });
    _scrollToBottom();

    final nextStep = _currentStep();

    try {
      final assistantReply = await ref
          .read(publicServiceConciergeRepositoryProvider)
          .fetchReply(
            languageCode: _languageCode,
            justCapturedStep: step.apiValue,
            nextStep: nextStep.apiValue,
            serviceKey: _draft.serviceKey,
            serviceName: _draft.serviceName,
            firstName: _draft.firstName,
            completedSteps: _completedSteps(),
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _messages.add(
          _BookingChatMessage.assistant(
            text: assistantReply.reply,
            senderName: assistantReply.assistantName,
          ),
        );
        _isSending = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _messages.add(
          _BookingChatMessage.assistant(text: _localFallbackReply(nextStep)),
        );
        _isSending = false;
      });
    }

    _scrollToBottom();
  }

  String? _validateInput(
    PublicCompanyProfileModel profile,
    _BookingStep step,
    String value, {
    PublicServiceItem? selectedService,
  }) {
    if (step == _BookingStep.service) {
      if (selectedService != null) {
        return null;
      }

      return _matchService(profile, value) == null
          ? _invalidServiceMessage()
          : null;
    }

    if (step == _BookingStep.firstName || step == _BookingStep.lastName) {
      return value.isEmpty ? _requiredFieldMessage(step) : null;
    }

    if (step == _BookingStep.email) {
      return _isValidEmailAddress(value) ? null : _invalidEmailMessage();
    }

    if (step == _BookingStep.emailCode) {
      if (_looksLikeEmailAddress(value)) {
        return _isValidEmailAddress(value) ? null : _invalidEmailMessage();
      }

      return _looksLikeVerificationCode(value)
          ? null
          : _invalidVerificationCodeMessage();
    }

    if (step == _BookingStep.phone) {
      return _looksLikePhoneNumber(value) ? null : _invalidPhoneMessage();
    }

    if (step == _BookingStep.password) {
      return value.length >= 8 ? null : _invalidPasswordMessage();
    }

    if (step == _BookingStep.confirmPassword) {
      return value == _draft.password ? null : _passwordMismatchMessage();
    }

    return null;
  }

  PublicServiceItem? _matchService(
    PublicCompanyProfileModel profile,
    String value,
  ) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    for (final service in profile.serviceLabels) {
      if (service.key.toLowerCase() == normalized ||
          service.label.en.trim().toLowerCase() == normalized ||
          service.label.de.trim().toLowerCase() == normalized) {
        return service;
      }
    }

    return null;
  }

  Future<void> _handleEmailStep(String rawInput) async {
    final email = rawInput.toLowerCase();
    _inputController.clear();

    setState(() {
      _messages.add(_BookingChatMessage.user(text: email));
      _isSending = true;
    });
    _scrollToBottom();

    try {
      await ref
          .read(authRepositoryProvider)
          .requestCustomerRegistrationCode(email: email);

      if (!mounted) {
        return;
      }

      setState(() {
        _draft.email = email;
        _draft.verificationToken = '';
        _messages.add(
          _BookingChatMessage.assistant(
            text: _verificationCodeSentMessage(email),
          ),
        );
        _isSending = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _messages.add(
          _BookingChatMessage.assistant(
            text: error.errorCode == 'CUSTOMER_REGISTER_EMAIL_TAKEN'
                ? _emailAlreadyRegisteredMessage(email)
                : _composeApiErrorMessage(error),
          ),
        );
        _isSending = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _messages.add(
          _BookingChatMessage.assistant(
            text: _verificationCodeSendFailureMessage(),
          ),
        );
        _isSending = false;
      });
    }

    _scrollToBottom();
  }

  Future<void> _handleEmailCodeStep(String rawInput) async {
    if (_looksLikeEmailAddress(rawInput)) {
      await _handleReplacementEmail(rawInput.toLowerCase());
      return;
    }

    _inputController.clear();

    setState(() {
      _messages.add(
        _BookingChatMessage.user(
          text: _language == PublicSiteLanguage.german
              ? 'Bestaetigungscode eingegeben'
              : 'Verification code entered',
        ),
      );
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final verificationToken = await ref
          .read(authRepositoryProvider)
          .verifyCustomerRegistrationCode(email: _draft.email, code: rawInput);

      if (!mounted) {
        return;
      }

      setState(() {
        _draft.verificationToken = verificationToken;
        _messages.add(
          _BookingChatMessage.assistant(text: _emailVerifiedReply()),
        );
        _isSending = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _messages.add(
          _BookingChatMessage.assistant(text: _composeApiErrorMessage(error)),
        );
        _isSending = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _messages.add(
          _BookingChatMessage.assistant(
            text: _invalidVerificationCodeMessage(),
          ),
        );
        _isSending = false;
      });
    }

    _scrollToBottom();
  }

  Future<void> _handleReplacementEmail(String email) async {
    _inputController.clear();

    setState(() {
      _messages.add(_BookingChatMessage.user(text: email));
      _isSending = true;
    });
    _scrollToBottom();

    try {
      await ref
          .read(authRepositoryProvider)
          .requestCustomerRegistrationCode(email: email);

      if (!mounted) {
        return;
      }

      setState(() {
        _draft.email = email;
        _draft.verificationToken = '';
        _messages.add(
          _BookingChatMessage.assistant(
            text: _verificationCodeResentMessage(email),
          ),
        );
        _isSending = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _messages.add(
          _BookingChatMessage.assistant(
            text: error.errorCode == 'CUSTOMER_REGISTER_EMAIL_TAKEN'
                ? _emailAlreadyRegisteredMessage(email)
                : _composeApiErrorMessage(error),
          ),
        );
        _isSending = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _messages.add(
          _BookingChatMessage.assistant(
            text: _verificationCodeSendFailureMessage(),
          ),
        );
        _isSending = false;
      });
    }

    _scrollToBottom();
  }

  void _pushAssistantMessage(String text) {
    setState(() {
      _messages.add(_BookingChatMessage.assistant(text: text));
    });
    _scrollToBottom();
  }

  String _requiredFieldMessage(_BookingStep step) {
    if (_language == PublicSiteLanguage.german) {
      return switch (step) {
        _BookingStep.firstName => 'Bitte geben Sie Ihren Vornamen ein.',
        _BookingStep.lastName => 'Bitte geben Sie Ihren Nachnamen ein.',
        _BookingStep.email => 'Bitte geben Sie Ihre E-Mail-Adresse ein.',
        _BookingStep.emailCode =>
          'Bitte geben Sie den 6-stelligen Code aus Ihrer E-Mail ein.',
        _BookingStep.phone => 'Bitte geben Sie Ihre Telefonnummer ein.',
        _BookingStep.password => 'Bitte geben Sie ein Passwort ein.',
        _BookingStep.confirmPassword => 'Bitte bestaetigen Sie Ihr Passwort.',
        _BookingStep.service || _BookingStep.done => '',
      };
    }

    return switch (step) {
      _BookingStep.firstName => 'Please enter your first name.',
      _BookingStep.lastName => 'Please enter your last name.',
      _BookingStep.email => 'Please enter your email address.',
      _BookingStep.emailCode =>
        'Please enter the 6-digit code from your email.',
      _BookingStep.phone => 'Please enter your phone number.',
      _BookingStep.password => 'Please create a password.',
      _BookingStep.confirmPassword => 'Please confirm your password.',
      _BookingStep.service || _BookingStep.done => '',
    };
  }

  String _invalidServiceMessage() {
    return _language == PublicSiteLanguage.german
        ? 'Bitte wahlen Sie eine der angebotenen Leistungen fur die erste Buchung aus.'
        : 'Please choose one of the listed services for the first booking step.';
  }

  String _invalidEmailMessage() {
    return _language == PublicSiteLanguage.german
        ? 'Bitte geben Sie eine gultige E-Mail-Adresse ein.'
        : 'Please enter a valid email address.';
  }

  String _composeApiErrorMessage(ApiException error) {
    final hint = error.resolutionHint?.trim() ?? '';
    if (hint.isEmpty) {
      return error.message;
    }

    if (_language == PublicSiteLanguage.german) {
      return '${error.message}. Hinweis: $hint.';
    }

    return '${error.message}. Hint: $hint.';
  }

  bool _isValidEmailAddress(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  bool _looksLikeEmailAddress(String value) {
    return value.contains('@');
  }

  bool _looksLikeVerificationCode(String value) {
    return RegExp(r'^\d{6}$').hasMatch(value.trim());
  }

  String _invalidVerificationCodeMessage() {
    return _language == PublicSiteLanguage.german
        ? 'Bitte geben Sie den 6-stelligen Code aus Ihrer E-Mail ein oder tragen Sie eine andere E-Mail-Adresse ein.'
        : 'Enter the 6-digit code from your email, or type a different email address.';
  }

  String _verificationCodeSentMessage(String email) {
    return _language == PublicSiteLanguage.german
        ? 'Perfekt. Ich habe einen 6-stelligen Code an $email gesendet. Geben Sie ihn jetzt hier ein. Wenn Sie eine andere E-Mail verwenden mochten, schicken Sie einfach die neue Adresse.'
        : 'Perfect. I sent a 6-digit code to $email. Enter it here next. If you want to use a different email, just send the new address.';
  }

  String _verificationCodeResentMessage(String email) {
    return _language == PublicSiteLanguage.german
        ? 'Danke. Ich habe einen neuen 6-stelligen Code an $email gesendet. Geben Sie ihn hier ein, sobald er angekommen ist.'
        : 'Thanks. I sent a fresh 6-digit code to $email. Enter it here as soon as it arrives.';
  }

  String _verificationCodeSendFailureMessage() {
    return _language == PublicSiteLanguage.german
        ? 'Ich konnte den Bestatigungscode gerade nicht senden. Versuchen Sie es bitte gleich noch einmal.'
        : 'I could not send the verification code right now. Please try again in a moment.';
  }

  String _emailAlreadyRegisteredMessage(String email) {
    return _language == PublicSiteLanguage.german
        ? 'Die Adresse $email ist bereits registriert. Melden Sie sich bitte stattdessen an. Wenn Sie das Passwort nicht mehr haben, fordern Sie bitte einen Passwort-Reset beim Support an.'
        : 'The email $email already has an account. Please log in instead. If you no longer have the password, request a password reset from support.';
  }

  String _emailVerifiedReply() {
    return _language == PublicSiteLanguage.german
        ? 'Perfekt. Ihre E-Mail ist bestatigt. Welche Telefonnummer sollen wir fur Ruckfragen verwenden?'
        : 'Perfect. Your email is verified. What phone number should we use if the team needs to reach you quickly?';
  }

  bool _looksLikePhoneNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    if (!RegExp(r'^[0-9+().\-\s]+$').hasMatch(trimmed)) {
      return false;
    }

    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
    return digitsOnly.length >= 7;
  }

  String _invalidPhoneMessage() {
    return _language == PublicSiteLanguage.german
        ? 'Bitte geben Sie eine gultige Telefonnummer mit mindestens 7 Ziffern ein.'
        : 'Please enter a valid phone number with at least 7 digits.';
  }

  String _invalidPasswordMessage() {
    return _language == PublicSiteLanguage.german
        ? 'Bitte erstellen Sie ein Passwort mit mindestens 8 Zeichen.'
        : 'Please create a password with at least 8 characters.';
  }

  String _passwordMismatchMessage() {
    return _language == PublicSiteLanguage.german
        ? 'Die Passwoerter stimmen nicht ueberein. Bitte geben Sie dieselbe Eingabe erneut ein.'
        : 'Passwords do not match. Please enter the same password again.';
  }

  String _confirmPasswordPrompt() {
    return _language == PublicSiteLanguage.german
        ? 'Danke. Bitte geben Sie dasselbe Passwort jetzt noch einmal zur Bestaetigung ein.'
        : 'Thanks. Please enter the same password again to confirm it.';
  }

  String _passwordConfirmedReply() {
    return _language == PublicSiteLanguage.german
        ? 'Perfekt. Ihr Passwort ist bestaetigt. Unten koennen Sie jetzt Ihren sicheren Kundenzugang erstellen und direkt zur Serviceanfrage weitergehen.'
        : 'Perfect. Your password is confirmed. Use the button below to create your secure customer access and continue to the service request.';
  }

  String _localFallbackReply(_BookingStep nextStep) {
    if (_language == PublicSiteLanguage.german) {
      return switch (nextStep) {
        _BookingStep.service =>
          'Wahlen Sie zuerst die gewunschte Leistung aus.',
        _BookingStep.firstName => 'Perfekt. Wie lautet Ihr Vorname?',
        _BookingStep.lastName => 'Danke. Wie lautet Ihr Nachname?',
        _BookingStep.email =>
          'Welche E-Mail-Adresse sollen wir fur Ihren Zugang verwenden?',
        _BookingStep.emailCode =>
          'Bitte geben Sie jetzt den 6-stelligen Code aus Ihrer E-Mail ein.',
        _BookingStep.phone =>
          'Welche Telefonnummer sollen wir fur Ruckfragen verwenden?',
        _BookingStep.password =>
          'Bitte erstellen Sie jetzt Ihr Passwort mit mindestens 8 Zeichen.',
        _BookingStep.confirmPassword =>
          'Bitte bestaetigen Sie Ihr Passwort jetzt noch einmal.',
        _BookingStep.done =>
          'Alles ist bereit. Unten konnen Sie Ihren sicheren Kundenzugang anlegen und direkt weiter zur Anfrage gehen.',
      };
    }

    return switch (nextStep) {
      _BookingStep.service => 'Start by choosing the service you need.',
      _BookingStep.firstName => 'Perfect. What is your first name?',
      _BookingStep.lastName => 'Thanks. What is your last name?',
      _BookingStep.email => 'What email address should we use for your access?',
      _BookingStep.emailCode => 'Enter the 6-digit code from your email now.',
      _BookingStep.phone =>
        'What phone number should we use if the team needs to reach you quickly?',
      _BookingStep.password =>
        'Please create your password now with at least 8 characters.',
      _BookingStep.confirmPassword =>
        'Please enter the same password again to confirm it.',
      _BookingStep.done =>
        'Everything is ready. Use the button below to create your secure customer access and continue to the request flow.',
    };
  }

  Future<void> _createAccount() async {
    if (_isCreatingAccount) {
      return;
    }

    setState(() => _isCreatingAccount = true);

    try {
      await ref
          .read(authControllerProvider.notifier)
          .registerCustomer(
            firstName: _draft.firstName,
            lastName: _draft.lastName,
            email: _draft.email,
            phone: _draft.phone,
            password: _draft.password,
            verificationToken: _draft.verificationToken,
          );

      if (!mounted) {
        return;
      }

      final requestService = _mappedRequestServiceType();
      final nextPath = requestService == null
          ? '/app/requests/new'
          : '/app/requests/new?service=$requestService';
      context.go(nextPath);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _messages.add(
          _BookingChatMessage.assistant(
            text: error.toString().replaceFirst('Exception: ', ''),
          ),
        );
        _isCreatingAccount = false;
      });
      _scrollToBottom();
      return;
    }
  }

  String? _mappedRequestServiceType() {
    if (AppConfig.serviceLabels.containsKey(_draft.serviceKey)) {
      return _draft.serviceKey;
    }

    return null;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(publicCompanyProfileProvider);

    return profileAsync.when(
      data: (profile) {
        _seedConversationIfNeeded(profile);
        return _buildLoaded(context, profile);
      },
      loading: () => const _BookingLoadingScaffold(),
      error: (error, stackTrace) => const _BookingErrorScaffold(),
    );
  }

  Widget _buildLoaded(BuildContext context, PublicCompanyProfileModel profile) {
    final bookingLabel = resolvePublicText(
      profile.createAccountLabel,
      _language,
    );
    final isGerman = _language == PublicSiteLanguage.german;
    final currentStep = _currentStep();
    final isSensitiveStep =
        currentStep == _BookingStep.password ||
        currentStep == _BookingStep.confirmPassword;
    final wide = MediaQuery.sizeOf(context).width >= 1080;

    final chatPanel = Container(
      decoration: BoxDecoration(
        color: AppTheme.ink,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: <BoxShadow>[
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
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFF2F68CE), Color(0xFF63C3E7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text(
                      'N',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        isGerman
                            ? 'Naima, Service Desk'
                            : 'Naima, Service Desk',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isGerman
                            ? 'Persoenliche Buchungshilfe und sicherer Kontostart.'
                            : 'Personal booking help and secure account setup.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF173A28),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isGerman ? 'Live intake' : 'Live intake',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: const Color(0xFF7EE1A6),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final chip in _buildProgressChips())
                  _ProgressPill(
                    label: chip.label,
                    isActive: chip.isActive,
                    isComplete: chip.isComplete,
                  ),
              ],
            ),
          ),
          Container(
            height: wide ? 520 : 500,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ListView.separated(
              controller: _scrollController,
              itemCount: _messages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Align(
                  alignment: message.isAssistant
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: message.isAssistant
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFF3D6FB7),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: message.isAssistant
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.white.withValues(alpha: 0.10),
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
          if (currentStep == _BookingStep.service)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: profile.serviceLabels
                      .map(
                        (service) => ActionChip(
                          backgroundColor: const Color(0xFFF4F7FC),
                          surfaceTintColor: Colors.transparent,
                          side: BorderSide(
                            color: AppTheme.cobalt.withValues(alpha: 0.16),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          label: Text(
                            resolvePublicText(service.label, _language),
                            style: const TextStyle(
                              color: AppTheme.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: () =>
                              _handleSubmit(profile, selectedService: service),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          if (currentStep == _BookingStep.done)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        isGerman
                            ? 'Bereit zum Fortfahren'
                            : 'Ready to continue',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isGerman
                            ? 'Ihr sicherer Kundenzugang wird jetzt erstellt. Danach geht es direkt in die Serviceanfrage.'
                            : 'Your secure customer access will be created now, then you will go straight into the service request.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.78),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _isCreatingAccount ? null : _createAccount,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppTheme.ink,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Text(
                            _isCreatingAccount
                                ? (isGerman
                                      ? 'Zugang wird erstellt...'
                                      : 'Creating access...')
                                : bookingLabel,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: TextField(
                      controller: _inputController,
                      enabled:
                          !_isSending &&
                          !_isCreatingAccount &&
                          currentStep != _BookingStep.done,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.ink,
                        fontWeight: FontWeight.w600,
                      ),
                      obscureText: isSensitiveStep && !_isSensitiveInputVisible,
                      keyboardType: switch (currentStep) {
                        _BookingStep.email => TextInputType.emailAddress,
                        _BookingStep.phone => TextInputType.phone,
                        _ => TextInputType.text,
                      },
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _handleSubmit(profile),
                      decoration: InputDecoration(
                        hintText: _placeholderForStep(currentStep),
                        hintStyle: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(
                              color: AppTheme.ink.withValues(alpha: 0.62),
                              fontWeight: FontWeight.w500,
                            ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        suffixIcon: isSensitiveStep
                            ? IconButton(
                                tooltip: _isSensitiveInputVisible
                                    ? (isGerman
                                          ? 'Passwort ausblenden'
                                          : 'Hide password')
                                    : (isGerman
                                          ? 'Passwort anzeigen'
                                          : 'Show password'),
                                onPressed: () {
                                  setState(() {
                                    _isSensitiveInputVisible =
                                        !_isSensitiveInputVisible;
                                  });
                                },
                                icon: Icon(
                                  _isSensitiveInputVisible
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  color: AppTheme.ink.withValues(alpha: 0.68),
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
                    color: currentStep == _BookingStep.done || _isSending
                        ? AppTheme.cobalt.withValues(alpha: 0.45)
                        : AppTheme.cobalt,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: IconButton(
                    onPressed: currentStep == _BookingStep.done || _isSending
                        ? null
                        : () => _handleSubmit(profile),
                    icon: _isSending
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
        ],
      ),
    );

    final sidePanel = PublicSurfaceCard(
      title: isGerman ? 'Was passiert als Nächstes?' : 'What happens next?',
      subtitle: isGerman
          ? 'Der Chat sammelt nur den sicheren Erstzugang und leitet Sie danach direkt in die Serviceanfrage.'
          : 'This chat only handles secure first-time access, then moves you directly into the service request.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PublicBulletList(
            items: <String>[
              isGerman
                  ? 'Leistung auswahlen oder aus der Serviceseite ubernehmen.'
                  : 'Choose a service or carry it in from the service page.',
              isGerman
                  ? 'Kontaktdaten Schritt fur Schritt wie im Kundenservice eingeben.'
                  : 'Share your details step by step like a customer-care conversation.',
              isGerman
                  ? 'Sicheren Zugang anlegen und danach direkt die Serviceanfrage absenden.'
                  : 'Create secure access and then go straight into the service request.',
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.go(
                _language == PublicSiteLanguage.german
                    ? '/login?lang=de'
                    : '/login',
              ),
              child: Text(
                isGerman
                    ? 'Bereits registriert? Login'
                    : 'Already registered? Login',
              ),
            ),
          ),
        ],
      ),
    );

    return PublicSiteShell(
      profile: profile,
      language: _language,
      onLanguageChanged: (language) {
        setState(() => _language = language);
      },
      activeItem: PublicNavItem.services,
      eyebrow: isGerman ? 'Service Concierge' : 'Service Concierge',
      pageTitle: bookingLabel,
      pageSubtitle: isGerman
          ? 'Starten Sie mit einem kurzen Kundenservice-Chat. Danach geht es direkt in die sichere Serviceanfrage.'
          : 'Start with a short customer-care chat, then continue straight into the secure service request flow.',
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 1080) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 7, child: chatPanel),
                const SizedBox(width: 20),
                Expanded(flex: 3, child: sidePanel),
              ],
            );
          }

          return Column(
            children: <Widget>[
              chatPanel,
              const SizedBox(height: 20),
              sidePanel,
            ],
          );
        },
      ),
    );
  }

  String _placeholderForStep(_BookingStep step) {
    if (_language == PublicSiteLanguage.german) {
      return switch (step) {
        _BookingStep.service => 'Leistung eingeben oder auswahlen',
        _BookingStep.firstName => 'Vorname',
        _BookingStep.lastName => 'Nachname',
        _BookingStep.email => 'E-Mail-Adresse',
        _BookingStep.emailCode => '6-stelliger Code oder neue E-Mail',
        _BookingStep.phone => 'Telefonnummer',
        _BookingStep.password => 'Passwort mit mindestens 8 Zeichen',
        _BookingStep.confirmPassword => 'Passwort bestaetigen',
        _BookingStep.done => 'Bereit zum Fortfahren',
      };
    }

    return switch (step) {
      _BookingStep.service => 'Type or choose a service',
      _BookingStep.firstName => 'First name',
      _BookingStep.lastName => 'Last name',
      _BookingStep.email => 'Email address',
      _BookingStep.emailCode => '6-digit code or different email',
      _BookingStep.phone => 'Phone number',
      _BookingStep.password => 'Password with at least 8 characters',
      _BookingStep.confirmPassword => 'Confirm password',
      _BookingStep.done => 'Ready to continue',
    };
  }

  List<_ProgressChipData> _buildProgressChips() {
    final current = _currentStep();
    return <_ProgressChipData>[
      _ProgressChipData(
        label: _language == PublicSiteLanguage.german ? 'Leistung' : 'Service',
        isActive: current == _BookingStep.service,
        isComplete:
            _draft.serviceKey.isNotEmpty || _draft.serviceName.isNotEmpty,
      ),
      _ProgressChipData(
        label: _language == PublicSiteLanguage.german
            ? 'Vorname'
            : 'First name',
        isActive: current == _BookingStep.firstName,
        isComplete: _draft.firstName.isNotEmpty,
      ),
      _ProgressChipData(
        label: _language == PublicSiteLanguage.german
            ? 'Nachname'
            : 'Last name',
        isActive: current == _BookingStep.lastName,
        isComplete: _draft.lastName.isNotEmpty,
      ),
      _ProgressChipData(
        label: _language == PublicSiteLanguage.german ? 'E-Mail' : 'Email',
        isActive: current == _BookingStep.email,
        isComplete: _draft.email.isNotEmpty,
      ),
      _ProgressChipData(
        label: _language == PublicSiteLanguage.german ? 'Code' : 'Verify email',
        isActive: current == _BookingStep.emailCode,
        isComplete: _draft.verificationToken.isNotEmpty,
      ),
      _ProgressChipData(
        label: _language == PublicSiteLanguage.german ? 'Telefon' : 'Phone',
        isActive: current == _BookingStep.phone,
        isComplete: _draft.phone.isNotEmpty,
      ),
      _ProgressChipData(
        label: _language == PublicSiteLanguage.german ? 'Passwort' : 'Password',
        isActive: current == _BookingStep.password,
        isComplete: _draft.password.isNotEmpty,
      ),
      _ProgressChipData(
        label: _language == PublicSiteLanguage.german
            ? 'Bestaetigen'
            : 'Confirm',
        isActive: current == _BookingStep.confirmPassword,
        isComplete: _draft.passwordConfirmation.isNotEmpty,
      ),
    ];
  }
}

class _BookingLoadingScaffold extends StatelessWidget {
  const _BookingLoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.ink,
      body: Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}

class _BookingErrorScaffold extends StatelessWidget {
  const _BookingErrorScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Unable to load booking assistant')),
    );
  }
}

class _BookingDraft {
  String serviceKey = '';
  String serviceName = '';
  String firstName = '';
  String lastName = '';
  String email = '';
  String verificationToken = '';
  String phone = '';
  String password = '';
  String passwordConfirmation = '';
}

class _BookingChatMessage {
  const _BookingChatMessage({
    required this.senderName,
    required this.text,
    required this.isAssistant,
  });

  const _BookingChatMessage.assistant({
    required this.text,
    this.senderName = 'Naima',
  }) : isAssistant = true;

  const _BookingChatMessage.user({required this.text})
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

    if (isComplete) {
      backgroundColor = const Color(0xFF173A28);
      foregroundColor = const Color(0xFF8FE7B1);
    } else if (isActive) {
      backgroundColor = AppTheme.cobalt;
      foregroundColor = Colors.white;
    } else {
      backgroundColor = Colors.white.withValues(alpha: 0.07);
      foregroundColor = Colors.white.withValues(alpha: 0.72);
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

enum _BookingStep {
  service('service'),
  firstName('firstName'),
  lastName('lastName'),
  email('email'),
  emailCode('emailCode'),
  phone('phone'),
  password('password'),
  confirmPassword('password'),
  done('done');

  const _BookingStep(this.apiValue);

  final String apiValue;
}
