import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:little_log/services/tip_jar.dart';
import 'package:little_log/widgets/tip_jar_page.dart';

class FakeStore implements TipStore {
  final events = StreamController<List<PurchaseDetails>>.broadcast();
  List<PurchaseDetails> recovered = [];
  @override
  Future<List<PurchaseDetails>> recover() async => recovered;
  bool available = true;
  bool failFinish = false;
  List<String> missing = [];
  bool verified = true;
  Completer<void>? finishWait;
  int buys = 0;
  int finishes = 0;
  List<ProductDetails> catalog = [
    ProductDetails(
      id: TipJar.productIds.first,
      title: 'Small tip',
      description: 'Optional support',
      price: '€1,09',
      rawPrice: 1.09,
      currencyCode: 'EUR',
    ),
  ];
  @override
  Stream<List<PurchaseDetails>> get purchases => events.stream;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<ProductDetailsResponse> products(Set<String> ids) async =>
      ProductDetailsResponse(productDetails: catalog, notFoundIDs: missing);
  @override
  Future<bool> buy(ProductDetails product) async {
    buys++;
    return true;
  }

  @override
  Future<bool> verify(PurchaseDetails purchase) async => verified;
  @override
  Future<void> complete(PurchaseDetails purchase) async {
    finishes++;
    if (finishWait != null) await finishWait!.future;
    if (failFinish) throw StateError('offline');
  }

  void emit(PurchaseStatus status, {bool complete = false, String? id}) {
    events.add([
      PurchaseDetails(
        purchaseID: id ?? 'transaction-1',
        productID: TipJar.productIds.first,
        verificationData: PurchaseVerificationData(
          localVerificationData: '',
          serverVerificationData: '',
          source: 'test',
        ),
        transactionDate: '1',
        status: status,
      )..pendingCompletePurchase = complete,
    ]);
  }
}

Future<void> settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late FakeStore store;
  late TipJar jar;
  setUp(() {
    store = FakeStore();
    jar = TipJar(store);
  });
  tearDown(() async {
    jar.dispose();
    await store.events.close();
  });

  test(
    'Apple recovers verified unfinished consumables for completion',
    () async {
      final apple = AppleTipStore(
        unfinishedTransactions: () async => [
          SK2Transaction(
            id: '42',
            originalId: '42',
            productId: TipJar.productIds.first,
            purchaseDate: '123',
            appAccountToken: null,
            receiptData: 'signed',
          ),
        ],
      );
      final purchase = (await apple.recover()).single;
      expect(purchase, isA<SK2PurchaseDetails>());
      expect(purchase.purchaseID, '42');
      expect(purchase.pendingCompletePurchase, isTrue);
      expect(purchase.verificationData.serverVerificationData, 'signed');
      expect(await apple.verify(purchase), isTrue);
      expect(
        await AppleTipStore(
          unfinishedTransactions: () async => [],
        ).verify(purchase),
        isFalse,
      );
    },
  );

  test('all four store-priced tips appear in ascending price order', () async {
    final amounts = {
      'tiny': 0.29,
      'small': 0.99,
      'medium': 2.99,
      'large': 4.99,
    };
    store.catalog = amounts.entries
        .map(
          (entry) => ProductDetails(
            id: 'app.littlelog.tip.${entry.key}',
            title: '${entry.key} tip',
            description: 'Optional support',
            price: '\$${entry.value.toStringAsFixed(2)}',
            rawPrice: entry.value,
            currencyCode: 'USD',
          ),
        )
        .toList()
        .reversed
        .toList();
    await jar.load();
    expect(jar.products.map((p) => p.rawPrice), amounts.values);
    expect(jar.products.map((p) => p.id).toSet(), TipJar.productIds);
    expect(jar.canRetry, isFalse);
  });

  test('duplicate stream and recovery delivery finishes a tip once', () async {
    await jar.load();
    store.emit(PurchaseStatus.purchased, complete: true, id: 'paid');
    store.emit(PurchaseStatus.purchased, complete: true, id: 'paid');
    await settle();
    expect(store.finishes, 1);
    expect(jar.busy, isFalse);
    store.emit(PurchaseStatus.purchased, complete: true, id: 'next-tip');
    await settle();
    expect(store.finishes, 2);
  });

  test(
    'partial catalog keeps available tips purchasable and offers retry',
    () async {
      store.missing = ['app.littlelog.tip.large'];
      await jar.load();
      expect(jar.products, hasLength(1));
      expect(jar.canRetry, isTrue);
      await jar.buy(jar.products.single);
      expect(store.buys, 1);
    },
  );

  test(
    'stalled completion becomes retryable without starting another charge',
    () async {
      jar.dispose();
      jar = TipJar(store, operationTimeout: const Duration(milliseconds: 10));
      await jar.load();
      store.finishWait = Completer<void>();
      store.emit(PurchaseStatus.purchased, complete: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(jar.canRetry, isTrue);
      expect(jar.busy, isTrue);
      expect(jar.message, contains('won’t charge you again'));
      store.finishWait!.complete();
      store.finishWait = null;
      await jar.load();
      expect(jar.busy, isFalse);
      expect(jar.canRetry, isFalse);
      expect(store.buys, 0);
    },
  );

  test(
    'unavailable and missing products never offer fabricated prices',
    () async {
      store.available = false;
      await jar.load();
      expect(jar.products, isEmpty);
      expect(jar.loading, isFalse);
      store.available = true;
      store.catalog = [];
      await jar.load();
      expect(jar.message, contains('currently unavailable'));
    },
  );

  test(
    'pending prevents duplicates; cancellation allows another tip',
    () async {
      await jar.load();
      final product = jar.products.single;
      await jar.buy(product);
      await jar.buy(product);
      expect(store.buys, 1);
      store.emit(PurchaseStatus.pending);
      await settle();
      expect(jar.busy, isTrue);
      store.emit(PurchaseStatus.canceled);
      await settle();
      expect(jar.busy, isFalse);
      await jar.buy(product);
      expect(store.buys, 2);
    },
  );

  test('successful tips finish and can be repeated', () async {
    await jar.load();
    await jar.buy(jar.products.single);
    store.emit(PurchaseStatus.purchased, complete: true);
    await settle();
    expect(store.finishes, 1);
    expect(jar.message, 'Tip completed.');
    expect(jar.busy, isFalse);
    await jar.buy(jar.products.single);
    expect(store.buys, 2);
  });

  test('unfinished payment retry does not charge again', () async {
    await jar.load();
    store.failFinish = true;
    store.emit(PurchaseStatus.purchased, complete: true);
    await settle();
    expect(jar.busy, isTrue);
    expect(jar.message, contains('finalized'));
    store.failFinish = false;
    await jar.load();
    expect(store.buys, 0);
    expect(store.finishes, 2);
    expect(jar.busy, isFalse);
  });

  test(
    'app-lifetime listener handles payment before opening tip screen',
    () async {
      jar.start();
      store.emit(PurchaseStatus.purchased, complete: true);
      await settle();
      expect(store.finishes, 1);
      store.emit(PurchaseStatus.error);
      await settle();
      expect(jar.message, contains('could not be completed'));
      expect(jar.busy, isFalse);
    },
  );

  test('unverified transaction never shows thanks or finishes', () async {
    await jar.load();
    store.verified = false;
    store.emit(PurchaseStatus.purchased, complete: true);
    await settle();
    expect(store.finishes, 0);
    expect(jar.message, contains('could not be verified'));
    expect(jar.busy, isTrue);
    store.verified = true;
    await jar.load();
    expect(store.finishes, 1);
    expect(jar.busy, isFalse);
  });

  test(
    'Android uses Google Play wording and finishes acknowledged consumables',
    () async {
      jar.dispose();
      jar = TipJar(store, storeName: 'Google Play');
      await jar.load();
      await jar.buy(jar.products.single);
      expect(jar.message, contains('Google Play'));
      store.emit(PurchaseStatus.pending);
      await settle();
      expect(jar.message, contains('Google Play'));
      // Play acknowledgement and consumption are different: already-acknowledged
      // purchases still need consumption before the same product can be bought.
      store.emit(PurchaseStatus.purchased, complete: false);
      await settle();
      expect(store.finishes, 1);
      expect(jar.busy, isFalse);
    },
  );

  test(
    'startup recovers paid tips and resume resolves pending approval',
    () async {
      final purchase = PurchaseDetails(
        purchaseID: 'recovered-transaction',
        productID: TipJar.productIds.first,
        verificationData: PurchaseVerificationData(
          localVerificationData: '',
          serverVerificationData: 'token',
          source: 'google_play',
        ),
        transactionDate: '1',
        status: PurchaseStatus.pending,
      );
      store.recovered = [purchase];
      jar.start();
      await settle();
      expect(jar.busy, isTrue);
      expect(store.finishes, 0);
      purchase.status = PurchaseStatus.purchased;
      await jar.recover();
      expect(store.finishes, 1);
      expect(store.buys, 0);
      expect(jar.busy, isFalse);
    },
  );

  testWidgets(
    'localized prices and unavailable state fit small large-text screen',
    (t) async {
      if (const bool.fromEnvironment('CAPTURE_TIPS')) {
        for (final name in ['Roboto', 'MaterialIcons']) {
          final loader = FontLoader(name)
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  File(
                    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/${name == 'Roboto' ? 'Roboto-Regular.ttf' : 'MaterialIcons-Regular.otf'}',
                  ).readAsBytesSync(),
                ),
              ),
            );
          await loader.load();
        }
      }
      jar.dispose();
      jar = TipJar(store);
      t.view.physicalSize = const Size(320, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorSchemeSeed: const Color(0xFF214B43)),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: RepaintBoundary(
              key: key,
              child: TipJarPage(jar: jar),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Leave a €1,09 tip'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await t.ensureVisible(find.text('Leave a €1,09 tip'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_TIPS')) {
        await t.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          await File(
            '../output/tip-jar-large-text.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        });
      }
      store.catalog = [];
      await jar.load();
      await t.pumpAndSettle();
      expect(find.textContaining('currently unavailable'), findsOneWidget);
      expect(find.text('Leave a €1,09 tip'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
