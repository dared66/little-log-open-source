import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:little_log/config.dart';
import 'package:little_log/services/google_auth.dart';
import 'support/invitation_harness.dart';

class AuthPlatform extends GoogleSignInPlatform {
  InitParameters? initialized;
  bool granted = false;
  bool failInit = false;
  bool failScopes = false;
  int interactiveRequests = 0;
  int silentRequests = 0;
  String? clearedToken;
  Completer<ClientAuthorizationTokenData?>? interactiveGate;
  Completer<ClientAuthorizationTokenData?>? silentGate;
  AuthenticationResults? restoredAccount;

  @override
  Future<void> init(InitParameters params) async {
    if (failInit) throw StateError('Synthetic configuration failure');
    initialized = params;
  }

  AuthenticationResults account() => const AuthenticationResults(
    user: GoogleSignInUserData(
      id: 'stable-google-account',
      email: 'tester@example.com',
    ),
    authenticationTokens: AuthenticationTokenData(
      idToken: 'synthetic-id-token',
    ),
  );

  @override
  Future<AuthenticationResults?> attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) async => restoredAccount;

  @override
  bool supportsAuthenticate() => true;

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async => account();

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async {
    expect(params.request.scopes, AppConfig.scopes);
    if (params.request.promptIfUnauthorized) {
      interactiveRequests++;
      if (interactiveGate != null) return interactiveGate!.future;
    } else {
      silentRequests++;
      if (silentGate != null) return silentGate!.future;
    }
    if (failScopes) throw StateError('Synthetic grant failure');
    return granted
        ? const ClientAuthorizationTokenData(
            accessToken: 'synthetic-drive-token',
          )
        : null;
  }

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async => throw StateError(
    'Little Log must not request server authorization tokens.',
  );

  @override
  Future<void> clearAuthorizationToken(
    ClearAuthorizationTokenParams params,
  ) async {
    clearedToken = params.accessToken;
    granted = false;
  }

  @override
  Future<void> signOut(SignOutParams params) async {}

  @override
  Future<void> disconnect(DisconnectParams params) async {}
}

Future<void> drainEvents() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('production Google authentication lifecycle', () {
    late GoogleSignInPlatform previous;
    late AuthPlatform platform;
    late GoogleAuth auth;
    setUp(() async {
      previous = GoogleSignInPlatform.instance;
      platform = AuthPlatform();
      GoogleSignInPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      auth = GoogleAuth();
    });
    tearDown(() async {
      auth.dispose();
      await drainEvents();
      debugDefaultTargetPlatformOverride = null;
      GoogleSignInPlatform.instance = previous;
    });

    Future<void> signedIn() async {
      await auth.initialize();
      await drainEvents();
      await auth.signIn();
      await drainEvents();
    }

    test(
      'initializes SDK with production iOS and server clients without a grant prompt',
      () async {
        await auth.initialize();
        await drainEvents();
        expect(auth.ready, isTrue);
        expect(auth.error, isNull);
        expect(platform.initialized!.clientId, AppConfig.iosClientId);
        expect(platform.initialized!.serverClientId, AppConfig.webClientId);
        expect(platform.interactiveRequests, 0);
        expect(auth.user, isNull);
      },
    );

    test(
      'signed-in tester with expired project grants stays disconnected without prompting',
      () async {
        await signedIn();
        expect(auth.user!.id, 'stable-google-account');
        expect(auth.driveConnected, isFalse);
        expect(auth.checkingDrive, isFalse);
        expect(platform.interactiveRequests, 0);
        await expectLater(auth.accessToken(), throwsStateError);
      },
    );

    test(
      'lightweight restored sign-in restores only existing production grants',
      () async {
        platform.restoredAccount = platform.account();
        platform.granted = true;
        await auth.initialize();
        await drainEvents();
        expect(auth.user!.email, 'tester@example.com');
        expect(auth.driveConnected, isTrue);
        expect(platform.interactiveRequests, 0);
      },
    );

    test(
      'explicit grant reconnects and prevents duplicate permission requests',
      () async {
        await signedIn();
        platform.interactiveGate = Completer<ClientAuthorizationTokenData?>();
        final first = auth.authorize();
        await drainEvents();
        await auth.authorize();
        expect(platform.interactiveRequests, 1);
        expect(auth.connectingDrive, isTrue);
        platform.interactiveGate!.complete(
          const ClientAuthorizationTokenData(accessToken: 'synthetic'),
        );
        await first;
        expect(auth.driveConnected, isTrue);
        expect(auth.connectingDrive, isFalse);
      },
    );

    test('grant failure resets busy state so the tester can retry', () async {
      await signedIn();
      platform.failScopes = true;
      await expectLater(auth.authorize(), throwsStateError);
      expect(auth.connectingDrive, isFalse);
      expect(auth.driveConnected, isFalse);
      platform.failScopes = false;
      platform.granted = true;
      await auth.authorize();
      expect(auth.driveConnected, isTrue);
    });

    test(
      'signing out during permission consent rejects its stale result',
      () async {
        await signedIn();
        platform.interactiveGate = Completer<ClientAuthorizationTokenData?>();
        final pending = auth.authorize();
        final rejected = expectLater(pending, throwsStateError);
        await drainEvents();
        await auth.signOut();
        await drainEvents();
        platform.interactiveGate!.complete(
          const ClientAuthorizationTokenData(accessToken: 'synthetic'),
        );
        await rejected;
        expect(auth.user, isNull);
        expect(auth.driveConnected, isFalse);
        expect(auth.connectingDrive, isFalse);
      },
    );

    test(
      'switching accounts during permission consent cannot connect the new account',
      () async {
        await signedIn();
        platform.interactiveGate = Completer<ClientAuthorizationTokenData?>();
        final pending = auth.authorize();
        final rejected = expectLater(pending, throwsStateError);
        await drainEvents();
        auth.user = HarnessAccount('other@example.com');
        platform.interactiveGate!.complete(
          const ClientAuthorizationTokenData(accessToken: 'synthetic'),
        );
        await rejected;
        expect(auth.driveConnected, isFalse);
      },
    );

    test(
      'token invalidation clears authorization and silent restore cannot revive it',
      () async {
        platform.granted = true;
        await signedIn();
        expect(await auth.accessToken(), 'synthetic-drive-token');
        await auth.invalidateToken('synthetic-drive-token');
        expect(platform.clearedToken, 'synthetic-drive-token');
        expect(auth.driveConnected, isFalse);
        await expectLater(auth.accessToken(), throwsStateError);
      },
    );

    test(
      'SDK initialization failure gives a recoverable configuration error',
      () async {
        platform.failInit = true;
        await auth.initialize();
        expect(auth.ready, isFalse);
        expect(auth.error, contains('not configured correctly'));
        expect(platform.interactiveRequests, 0);
      },
    );

    test(
      'grant restoration failure leaves the signed-in account usable locally',
      () async {
        platform.failScopes = true;
        await signedIn();
        expect(auth.user, isNotNull);
        expect(auth.driveConnected, isFalse);
        expect(auth.checkingDrive, isFalse);
        expect(platform.interactiveRequests, 0);
      },
    );

    test(
      'account switch while silently fetching a token rejects the old token',
      () async {
        await signedIn();
        platform.silentGate = Completer<ClientAuthorizationTokenData?>();
        final pending = auth.accessToken();
        final rejected = expectLater(pending, throwsStateError);
        await drainEvents();
        auth.user = HarnessAccount('other@example.com');
        platform.silentGate!.complete(
          const ClientAuthorizationTokenData(accessToken: 'old-account-token'),
        );
        await rejected;
        expect(auth.driveConnected, isFalse);
      },
    );

    test(
      'signout while silently fetching a token rejects the old token',
      () async {
        await signedIn();
        platform.silentGate = Completer<ClientAuthorizationTokenData?>();
        final pending = auth.accessToken();
        final rejected = expectLater(pending, throwsStateError);
        await drainEvents();
        await auth.signOut();
        await drainEvents();
        platform.silentGate!.complete(
          const ClientAuthorizationTokenData(accessToken: 'old-account-token'),
        );
        await rejected;
        expect(auth.user, isNull);
        expect(auth.driveConnected, isFalse);
      },
    );

    test('authorization requires a signed-in account', () async {
      await auth.initialize();
      await drainEvents();
      await expectLater(auth.authorize(), throwsStateError);
      expect(platform.interactiveRequests, 0);
    });
  }, skip: !AppConfig.configured);
}
