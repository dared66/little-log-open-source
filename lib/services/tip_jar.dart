import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

abstract interface class TipStore {
  Stream<List<PurchaseDetails>> get purchases;
  Future<bool> isAvailable();
  Future<ProductDetailsResponse> products(Set<String> ids);
  Future<bool> buy(ProductDetails product);
  Future<void> complete(PurchaseDetails purchase);
  Future<bool> verify(PurchaseDetails purchase);
  Future<List<PurchaseDetails>> recover();
}

class AppleTipStore implements TipStore {
  AppleTipStore({
    Future<List<SK2Transaction>> Function()? unfinishedTransactions,
  }) : _unfinishedTransactions =
           unfinishedTransactions ?? SK2Transaction.unfinishedTransactions;

  final Future<List<SK2Transaction>> Function() _unfinishedTransactions;
  InAppPurchase get _store => InAppPurchase.instance;
  @override
  Future<List<PurchaseDetails>> recover() async =>
      (await _unfinishedTransactions())
          .map(
            (transaction) => SK2PurchaseDetails(
              productID: transaction.productId,
              purchaseID: transaction.id,
              verificationData: PurchaseVerificationData(
                localVerificationData: transaction.jsonRepresentation ?? '',
                serverVerificationData: transaction.receiptData ?? '',
                source: 'app_store',
              ),
              transactionDate: transaction.purchaseDate,
              status: PurchaseStatus.purchased,
            ),
          )
          .toList();
  @override
  Stream<List<PurchaseDetails>> get purchases => _store.purchaseStream;
  @override
  Future<bool> isAvailable() => _store.isAvailable();
  @override
  Future<ProductDetailsResponse> products(Set<String> ids) =>
      _store.queryProductDetails(ids);
  @override
  Future<bool> buy(ProductDetails product) => _store.buyConsumable(
    purchaseParam: PurchaseParam(productDetails: product),
  );
  @override
  Future<bool> verify(PurchaseDetails purchase) async =>
      // The native API returns only StoreKit-verified unfinished transactions.
      // Finished consumables need not appear in Transaction.all.
      (await _unfinishedTransactions()).any(
        (t) => t.id == purchase.purchaseID && t.productId == purchase.productID,
      );
  @override
  Future<void> complete(PurchaseDetails purchase) =>
      _store.completePurchase(purchase);
}

/// Google signs purchase data; the public licensing key is configured at build
/// time. No payment is offered until verification can be performed.
class GoogleTipStore extends AppleTipStore {
  static const publicKey = String.fromEnvironment('PLAY_BILLING_PUBLIC_KEY');
  static const _channel = MethodChannel('little_log/play_billing');
  InAppPurchaseAndroidPlatformAddition get _android =>
      _store.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();

  @override
  Future<bool> isAvailable() async =>
      publicKey.isNotEmpty && await _store.isAvailable();

  @override
  Future<bool> buy(ProductDetails product) => _store.buyConsumable(
    purchaseParam: PurchaseParam(productDetails: product),
    autoConsume: false,
  );

  @override
  Future<bool> verify(PurchaseDetails purchase) async {
    if (publicKey.isEmpty || purchase is! GooglePlayPurchaseDetails) {
      return false;
    }
    final data = purchase.billingClientPurchase;
    if (data.purchaseState != PurchaseStateWrapper.purchased) return false;
    return await _channel.invokeMethod<bool>('verify', {
          'publicKey': publicKey,
          'data': data.originalJson,
          'signature': data.signature,
          'productId': purchase.productID,
          'token': data.purchaseToken,
        }) ??
        false;
  }

  @override
  Future<void> complete(PurchaseDetails purchase) async {
    if (purchase.status != PurchaseStatus.purchased &&
        purchase.status != PurchaseStatus.restored) {
      return;
    }
    // Consuming also acknowledges a Play purchase, and permits another tip.
    final result = await _android.consumePurchase(purchase);
    if (result.responseCode != BillingResponse.ok &&
        result.responseCode != BillingResponse.itemNotOwned) {
      throw StateError('Google Play could not finish the tip.');
    }
  }

  @override
  Future<List<PurchaseDetails>> recover() async {
    if (!await isAvailable()) return [];
    final response = await _android.queryPastPurchases();
    if (response.error != null) {
      throw StateError('Could not check pending tips.');
    }
    return response.pastPurchases;
  }
}

/// App-lifetime listener: leaving Settings must not abandon a payment.
class TipJar extends ChangeNotifier {
  TipJar(
    this.store, {
    this.storeName = 'App Store',
    this.operationTimeout = const Duration(seconds: 15),
  });
  final Duration operationTimeout;
  final String storeName;
  final TipStore store;
  static const productIds = {
    'app.littlelog.tip.tiny',
    'app.littlelog.tip.small',
    'app.littlelog.tip.medium',
    'app.littlelog.tip.large',
  };
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);
  static final shared = defaultTargetPlatform == TargetPlatform.android
      ? TipJar(GoogleTipStore(), storeName: 'Google Play')
      : TipJar(AppleTipStore());

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Future<void> _queue = Future.value();
  final Map<String, PurchaseDetails> _unfinished = {};
  final Set<String> _pending = {};
  final Set<String> _completed = {};
  bool _retryNeeded = false;
  bool get canRetry => !loading && _retryNeeded;
  List<ProductDetails> products = [];
  bool loading = false;
  bool _recovering = false;
  bool _opening = false;
  bool get busy => _opening || _pending.isNotEmpty || _unfinished.isNotEmpty;
  String? message;

  void start() {
    if (_subscription != null) return;
    _subscription = store.purchases.listen(
      (updates) {
        _queue = _queue.then((_) => _handle(updates));
      },
      onError: (Object error) {
        _retryNeeded = true;
        message = 'Could not check your tip. Please try again.';
        notifyListeners();
      },
    );
    unawaited(recover());
  }

  Future<void> recover() async {
    if (_recovering) return;
    _recovering = true;
    try {
      final updates = await store.recover().timeout(operationTimeout);
      _queue = _queue.then((_) => _handle(updates));
      await _queue;
    } catch (_) {
      _retryNeeded = true;
      message = 'Could not check pending tips. Please try again.';
      notifyListeners();
    } finally {
      _recovering = false;
    }
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    message = null;
    _retryNeeded = false;
    notifyListeners();
    try {
      start();
      if (!await store.isAvailable().timeout(operationTimeout)) {
        products = [];
        _retryNeeded = true;
        message = 'Tipping is unavailable right now. Please try again later.';
      } else {
        final response = await store
            .products(productIds)
            .timeout(operationTimeout);
        products =
            response.productDetails
                .where((p) => productIds.contains(p.id))
                .toList()
              ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
        if (products.isEmpty) {
          _retryNeeded = true;
          message = 'Tips are currently unavailable.';
        } else if (response.notFoundIDs.any(productIds.contains)) {
          _retryNeeded = true;
          message = 'Some tip amounts aren’t available right now.';
        }
        if (response.error != null) {
          _retryNeeded = true;
          message = 'Some tips could not be loaded. Please try again.';
        }
      }
      await recover();
      // Retry finishing already-paid tips without creating another charge.
      _queue = _queue.then((_) => _handle(_unfinished.values.toList()));
      await _queue;
    } catch (_) {
      _retryNeeded = true;
      products = [];
      message = 'Could not connect to $storeName. Please try again.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> buy(ProductDetails product) async {
    if (busy || loading || !products.any((p) => identical(p, product))) return;
    _opening = true;
    _pending.add(product.id);
    message = 'Confirm your tip with $storeName.';
    notifyListeners();
    try {
      if (!await store.buy(product)) {
        _pending.remove(product.id);
        message = 'The purchase could not start. Please try again.';
      }
    } catch (_) {
      _pending.remove(product.id);
      message = 'The purchase could not start. Please try again.';
    } finally {
      _opening = false;
      notifyListeners();
    }
  }

  Future<void> _handle(List<PurchaseDetails> updates) async {
    for (final purchase in updates) {
      if (!productIds.contains(purchase.productID)) continue;
      final key = purchase.purchaseID ?? purchase.productID;
      if ((purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) &&
          purchase.purchaseID != null &&
          _completed.contains(key)) {
        continue;
      }
      if (purchase.status == PurchaseStatus.pending) {
        _pending.add(purchase.productID);
        message = 'Your tip is awaiting approval from $storeName.';
      } else {
        _pending.remove(purchase.productID);
        try {
          if (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) {
            _unfinished[key] = purchase;
            if (!await store.verify(purchase).timeout(operationTimeout)) {
              _retryNeeded = true;
              message =
                  'Your tip could not be verified. Tap Retry to check again.';
              continue;
            }
          }
          if (purchase.pendingCompletePurchase ||
              purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) {
            _unfinished[key] = purchase;
            await store.complete(purchase).timeout(operationTimeout);
          }
          _unfinished.remove(key);
          if ((purchase.status == PurchaseStatus.purchased ||
                  purchase.status == PurchaseStatus.restored) &&
              purchase.purchaseID != null) {
            _completed.add(key);
          }
          switch (purchase.status) {
            case PurchaseStatus.purchased:
            case PurchaseStatus.restored:
              // Platform verification happens before finishing. Tips grant no
              // entitlement and are never recorded in the family's baby log.
              message = 'Tip completed.';
            case PurchaseStatus.canceled:
              message = 'Tip canceled.';
            case PurchaseStatus.error:
              message = 'Your tip could not be completed. Please try again.';
            case PurchaseStatus.pending:
              break;
          }
        } catch (_) {
          _retryNeeded = true;
          message =
              'Your tip is still being finalized. Tap Retry to check it; '
              'this won’t charge you again.';
        }
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
