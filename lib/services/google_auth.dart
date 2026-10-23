import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config.dart';

class GoogleAccountSession {
  const GoogleAccountSession(this.accountId, this.revision);
  final String accountId;
  final int revision;
}

class GoogleAuth extends ChangeNotifier {
  GoogleAuth({http.Client? verificationClient})
    : _verificationClient = verificationClient ?? http.Client();
  final http.Client _verificationClient;
  GoogleSignInAccount? _user;
  int _accountRevision = 0;
  GoogleSignInAccount? get user => _user;
  set user(GoogleSignInAccount? account) {
    if (_user?.id != account?.id) {
      _accountRevision++;
      _authorizationCheck++;
      _pickerToken = null;
      _pickerAccount = null;
      _pickerExpiry = null;
      driveConnected = false;
      checkingDrive = false;
      connectingDrive = false;
    }
    _user = account;
  }

  GoogleAccountSession captureAccount({String? expectedAccountId}) {
    final id = user?.id;
    if (id == null || (expectedAccountId != null && id != expectedAccountId)) {
      throw StateError('Sign in with this log’s Google account to continue.');
    }
    return GoogleAccountSession(id, _accountRevision);
  }

  void checkAccount(GoogleAccountSession session) {
    if (user?.id != session.accountId || _accountRevision != session.revision) {
      throw StateError('Google account changed. Try again.');
    }
  }

  String? _pickerToken;
  String? _pickerAccount;
  DateTime? _pickerExpiry;

  Future<void> acceptPickerToken(
    String token, {
    required String expectedEmail,
  }) async {
    final session = captureAccount();
    final response = await _verificationClient
        .get(
          Uri.https('www.googleapis.com', '/drive/v3/about', {
            'fields': 'user(emailAddress)',
          }),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 25));
    checkAccount(session);
    if (response.statusCode != 200) {
      throw StateError(
        'Google could not verify the selected account. Please try again.',
      );
    }
    final email = jsonDecode(response.body)['user']?['emailAddress'] as String?;
    if (email?.toLowerCase() != expectedEmail.toLowerCase() ||
        user?.email != expectedEmail) {
      throw StateError(
        'That file was selected with a different Google account. Choose $expectedEmail in Google Drive, or switch accounts in Little Log.',
      );
    }
    _pickerToken = token;
    _pickerAccount = user!.id;
    _pickerExpiry = DateTime.now().add(const Duration(minutes: 50));
    driveConnected = true;
    notifyListeners();
  }

  String? error;
  bool ready = false;
  bool driveConnected = false;
  bool checkingDrive = false;
  bool connectingDrive = false;
  int _authorizationCheck = 0;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _subscription;
  final _signIn = GoogleSignIn.instance;

  Future<void> initialize() async {
    if (!AppConfig.configured) return;
    try {
      await _signIn.initialize(
        clientId: kIsWeb
            ? AppConfig.webClientId
            : defaultTargetPlatform == TargetPlatform.iOS
            ? AppConfig.iosClientId
            : null,
        serverClientId: kIsWeb ? null : AppConfig.webClientId,
      );
      _subscription = _signIn.authenticationEvents.listen(
        (event) {
          final account = switch (event) {
            GoogleSignInAuthenticationEventSignIn() => event.user,
            GoogleSignInAuthenticationEventSignOut() => null,
          };
          _authorizationCheck++;
          driveConnected = false;
          checkingDrive = account != null;
          user = account;
          error = null;
          notifyListeners();
          if (account != null) unawaited(_restoreDriveConnection(account));
        },
        onError: (Object e) {
          error = 'Google sign-in did not complete. Please try again.';
          notifyListeners();
        },
      );
      ready = true;
      final attempt = _signIn.attemptLightweightAuthentication();
      if (attempt != null) unawaited(attempt.catchError((Object _) => null));
    } catch (_) {
      error = 'Google sign-in is not configured correctly for this build.';
    }
    notifyListeners();
  }

  Future<void> signIn() async {
    final account = await _signIn.authenticate();
    user = account;
    await _restoreDriveConnection(account);
    notifyListeners();
  }

  Future<void> _restoreDriveConnection(GoogleSignInAccount account) async {
    final check = ++_authorizationCheck;
    checkingDrive = true;
    notifyListeners();
    try {
      final authorization = await account.authorizationClient
          .authorizationForScopes(AppConfig.scopes);
      if (check != _authorizationCheck || user?.id != account.id) return;
      driveConnected = authorization != null;
    } catch (_) {
      if (check != _authorizationCheck || user?.id != account.id) return;
      driveConnected = false;
    } finally {
      if (check == _authorizationCheck && user?.id == account.id) {
        checkingDrive = false;
        notifyListeners();
      }
    }
  }

  Future<void> authorize() async {
    final account = user;
    if (account == null) throw StateError('Sign in to Google first.');
    if (connectingDrive) return;
    final check = ++_authorizationCheck;
    checkingDrive = false;
    connectingDrive = true;
    notifyListeners();
    try {
      await account.authorizationClient
          .authorizeScopes(AppConfig.scopes)
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () => throw StateError(
              'Google Drive did not finish connecting. Allow the Google sign-in '
              'popup, then try again. Your entries are saved on this device.',
            ),
          );
      if (check != _authorizationCheck || user?.id != account.id) {
        throw StateError(
          'The Google account changed. Connect Google Drive again with the account linked to this baby.',
        );
      }
      driveConnected = true;
    } finally {
      if (check == _authorizationCheck) {
        connectingDrive = false;
        notifyListeners();
      }
    }
  }

  Future<String> accessToken() async {
    if (_pickerToken != null &&
        _pickerAccount == user?.id &&
        _pickerExpiry!.isAfter(DateTime.now())) {
      return _pickerToken!;
    }
    final account = user;
    final check = _authorizationCheck;
    final authorization = await account?.authorizationClient
        .authorizationForScopes(AppConfig.scopes);
    if (check != _authorizationCheck || user?.id != account?.id) {
      throw StateError(
        'The Google account changed. Retry with the account linked to this baby.',
      );
    }
    if (authorization == null) {
      if (driveConnected) {
        driveConnected = false;
        notifyListeners();
      }
      throw StateError(
        'Connect Google Drive to continue. Your entries are saved on this device.',
      );
    }
    if (!driveConnected) {
      driveConnected = true;
      notifyListeners();
    }
    return authorization.accessToken;
  }

  Future<void> invalidateToken(String token) async {
    _pickerToken = null;
    _authorizationCheck++;
    checkingDrive = false;
    driveConnected = false;
    notifyListeners();
    await user?.authorizationClient.clearAuthorizationToken(accessToken: token);
  }

  Future<void> signOut() async {
    _pickerToken = null;
    _pickerAccount = null;
    _authorizationCheck++;
    user = null;
    driveConnected = false;
    checkingDrive = false;
    notifyListeners();
    await _signIn.signOut();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _verificationClient.close();
    super.dispose();
  }
}
