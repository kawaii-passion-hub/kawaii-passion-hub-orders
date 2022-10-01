import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:event_bus/event_bus.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get_it/get_it.dart';
import 'package:google_api_availability/google_api_availability.dart';
import 'package:kawaii_passion_hub_authentication/kawaii_passion_hub_authentication.dart';
import 'package:kawaii_passion_hub_orders/kawaii_passion_hub_orders.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:synchronized/synchronized.dart';
import 'constants.dart' as constants;
import 'model.dart';

bool initialized = false;

void initialize({bool useEmulator = false, bool showGooglePlayDialog = true}) {
  if (initialized) {
    return;
  }
  initialized = true;

  FirebaseApp ordersApp =
      GetIt.I<FirebaseApp>(instanceName: constants.firebaseAppName);

  if (kDebugMode) {
    FirebaseDatabase.instanceFor(app: ordersApp).setLoggingEnabled(true);
  }

  if (useEmulator) {
    final host = Platform.isAndroid ? '10.0.2.2' : 'localhost';
    //const authPort = 9099;
    const functionsPort = 5001;
    const databasePort = 9000;

    // ignore: avoid_print
    print('Running with orders emulator.');

    //FirebaseAuth.instanceFor(app: ordersApp).useAuthEmulator(host, authPort);
    FirebaseFunctions.instanceFor(app: ordersApp)
        .useFunctionsEmulator(host, functionsPort);
    FirebaseDatabase.instanceFor(app: ordersApp)
        .useDatabaseEmulator(host, databasePort);
  }

  EventBus globalBus = GetIt.I<EventBus>();
  EventBus localBus = EventBus();
  Controller controller =
      Controller(globalBus, localBus, ordersApp, showGooglePlayDialog);
  GetIt.I.registerSingleton(controller);
  GetIt.I
      .registerSingleton(localBus, instanceName: 'kawaii_passion_hub_orders');
  controller.subscribeToEvents();
}

void initializeBackgroundService(int backgroundNotificationChannelId,
    String backgroundNotificationChannelName,
    {bool useEmulator = false}) {
  final FirebaseApp ordersApp =
      GetIt.I<FirebaseApp>(instanceName: constants.firebaseAppName);
  final ServiceInstance service = GetIt.I<ServiceInstance>();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (kDebugMode) {
    FirebaseDatabase.instanceFor(app: ordersApp).setLoggingEnabled(true);
  }

  if (useEmulator) {
    final host = Platform.isAndroid ? '10.0.2.2' : 'localhost';
    const databasePort = 9000;

    FirebaseDatabase.instanceFor(app: ordersApp)
        .useDatabaseEmulator(host, databasePort);
  }

  FirebaseDatabase.instanceFor(app: ordersApp)
      .ref('/public/ordersSummary')
      .onValue
      .listen((event) async {
    if (!event.snapshot.exists) {
      return;
    }
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        /// OPTIONAL for use custom notification
        /// the notification id must be equals with AndroidConfiguration when you call configure() method.
        Map summary = event.snapshot.value as Map;
        flutterLocalNotificationsPlugin.show(
          backgroundNotificationChannelId,
          'Kawaii Passion Background Service',
          'Open Orders: ${summary['open']}',
          NotificationDetails(
            android: AndroidNotificationDetails(
              backgroundNotificationChannelName,
              'Kawaii Passion Background Service',
              icon: 'ic_bg_service_small',
              ongoing: true,
            ),
          ),
        );

        if (kDebugMode) {
          print('FLUTTER BACKGROUND SERVICE: ${summary['open']}');
        }

        // if you don't using custom notification, uncomment this
        // service.setForegroundNotificationInfo(
        //   title: "My App Service",
        //   content: "Updated at ${DateTime.now()}",
        // );
      }
    }
  });

  // bring to foreground
  /* Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        /// OPTIONAL for use custom notification
        /// the notification id must be equals with AndroidConfiguration when you call configure() method.
        flutterLocalNotificationsPlugin.show(
          backgroundNotificationChannelId,
          'Kawaii Passion Background Service',
          'Awesome ${DateTime.now()}',
          NotificationDetails(
            android: AndroidNotificationDetails(
              backgroundNotificationChannelName,
              'Kawaii Passion Background Service',
              icon: 'ic_bg_service_small',
              ongoing: true,
            ),
          ),
        );

        // if you don't using custom notification, uncomment this
        // service.setForegroundNotificationInfo(
        //   title: "My App Service",
        //   content: "Updated at ${DateTime.now()}",
        // );
      }
    }

    /// you can see this log in logcat
    if (kDebugMode) {
      print('FLUTTER BACKGROUND SERVICE: ${DateTime.now()}');
    }
  }); */
}

class Controller extends Disposable {
  final EventBus globalBus;
  final EventBus localBus;
  final FirebaseApp ordersApp;
  final bool showGooglePlayDialog;
  bool initializedModel = false;
  final Lock modelInitalizationLock = Lock();
  final Lock authentificationLock = Lock();
  StreamSubscription<
          CombinedEvent<UserInformationUpdated, MessagingTokenUpdated>>?
      loginInformation;
  StreamSubscription<String>? messagingTokenRefreshed;
  StreamSubscription<DatabaseEvent>? databaseEvent;
  String? lastUserJWT;
  String? lastMessagingToken;

  Controller(
      this.globalBus, this.localBus, this.ordersApp, this.showGooglePlayDialog);

  void subscribeToEvents() {
    loginInformation = globalBus
        .on<UserInformationUpdated>()
        .combineLatest(
          localBus.on<MessagingTokenUpdated>(),
          (p0, p1) => CombinedEvent(p0, p1 as MessagingTokenUpdated),
        )
        .listen((event) {
      updateAuthentification(event);
    });
    startCloudMessaging(localBus);
  }

  Future<void> startCloudMessaging(EventBus localBus) async {
    await setupInteractedMessage();

    GooglePlayServicesAvailability playStoreAvailability;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      playStoreAvailability = await GoogleApiAvailability.instance
          .checkGooglePlayServicesAvailability(showGooglePlayDialog);
    } on PlatformException {
      playStoreAvailability = GooglePlayServicesAvailability.unknown;
    }

    if (playStoreAvailability ==
            GooglePlayServicesAvailability.notAvailableOnPlatform ||
        playStoreAvailability == GooglePlayServicesAvailability.success) {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (kDebugMode) {
        print('Messaging key: $fcmToken');
      }
      messagingTokenRefreshed =
          FirebaseMessaging.instance.onTokenRefresh.listen((event) {
        if (kDebugMode) {
          print('New messaging key: $event');
        }
        OrdersState.messagingToken = event;
        localBus.fire(MessagingTokenUpdated(event));
      });
      OrdersState.messagingToken = fcmToken;
      localBus.fire(MessagingTokenUpdated(fcmToken));

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _handleMessage(message);
      });
    }
  }

  Future<void> setupInteractedMessage() async {
    // Get any messages which caused the application to open from
    // a terminated state.
    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();

    // If the message also contains a data property with a "type" of "chat",
    // navigate to a chat screen
    if (initialMessage != null) {
      _handleMessage(initialMessage);
    }

    // Also handle any interaction when the app is in the background via a
    // Stream listener
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
  }

  void _handleMessage(RemoteMessage message) {
    if (message.from == "/topics/new_order") {
      NavigationService().navigateTo('/orderDetails',
          arguments: OrderDetailsViewArguments(message.data['id']));
    }
  }

  void updateAuthentification(
      CombinedEvent<UserInformationUpdated, MessagingTokenUpdated>
          events) async {
    await authentificationLock.synchronized(() async {
      if (events.event1.newUser.isAuthenticated &&
          events.event1.newUser.claims?['whitelisted'] == true &&
          (events.event1.newUser.jwt != lastUserJWT ||
              events.event2.messagingToken != lastMessagingToken)) {
        try {
          HttpsCallableResult<String> result =
              await FirebaseFunctions.instanceFor(app: ordersApp)
                  .httpsCallable('authenticate')
                  .call({
            "jwt": events.event1.newUser.jwt,
            "notification": events.event2.messagingToken
          });

          lastUserJWT = events.event1.newUser.jwt;
          lastMessagingToken = events.event2.messagingToken;

          await FirebaseAuth.instanceFor(app: ordersApp)
              .signInWithCustomToken(result.data);
          await FirebaseAnalytics.instanceFor(app: ordersApp)
              .logLogin(loginMethod: "Custom Token");
          await initializeModel();
        } on FirebaseFunctionsException catch (error) {
          await FirebaseAnalytics.instanceFor(app: ordersApp)
              .logEvent(name: 'AuthError', parameters: {
            'Error': '${error.code}: ${error.message} - ${error.details}',
          });
          if (kDebugMode) {
            print('${error.code}: ${error.message} - ${error.details}');
          }
        }
      }
    });
  }

  Future initializeModel() async {
    if (initializedModel) {
      return;
    }
    await modelInitalizationLock.synchronized(() async {
      initializedModel = true;
      try {
        final ref = FirebaseDatabase.instanceFor(app: ordersApp).ref('orders');
        databaseEvent = ref.onValue.listen((event) {
          processDatabaseSnapshot(event.snapshot);
        });
      } on PlatformException catch (error) {
        await FirebaseAnalytics.instanceFor(app: ordersApp)
            .logEvent(name: 'DatabaseAccessError', parameters: {
          'Error': '${error.code}: ${error.message} - ${error.details}',
        });
        if (kDebugMode) {
          print('${error.code}: ${error.message} - ${error.details}');
        }
        return;
      }
    });
  }

  void processDatabaseSnapshot(DataSnapshot snapshot) {
    if (snapshot.exists) {
      final orders = (snapshot.value) as Map;
      List<Order> ordersModel = List.empty(growable: true);
      for (var orderId in orders.keys) {
        Map order = orders[orderId];
        OrderCustomer customer = OrderCustomer(
            '${order['address']['firstName']} ${order['address']['lastName']}',
            order['address']['street'],
            order['address']['zipcode'],
            order['address']['city'],
            order['address']['country']['name'],
            order['address']['country']['iso']);
        List<OrderItem> items = List.empty(growable: true);
        for (var itemId in order['lineItems'].keys) {
          Map item = order['lineItems'][itemId];
          if (item['type'] != 'product') {
            continue;
          }
          List<String> options = List.empty(growable: true);
          if (item['payload'].containsKey('options')) {
            for (var option in item['payload']['options']) {
              options.add('${option['group']}: ${option['option']}');
            }
          }
          OrderItem itemModel = OrderItem(item['payload']['productNumber'],
              item['label'], options, item['quantity']);
          items.add(itemModel);
        }
        Order orderModel = Order(
            order['orderNumber'],
            customer,
            items,
            double.parse(order['price']['netPrice'].toString()),
            true,
            order['stateMachineState']['name'],
            order.containsKey('customerComment')
                ? order['customerComment']
                : '',
            DateTime.parse(order['createdAt']));
        ordersModel.add(orderModel);
      }
      OrdersState.current = ordersModel;
      localBus.fire(OrdersUpdated(ordersModel));
      globalBus.fire(OrdersUpdated(ordersModel));
    } else {
      return;
    }
  }

  @override
  FutureOr onDispose() {
    loginInformation?.cancel();
    messagingTokenRefreshed?.cancel();
    databaseEvent?.cancel();
  }
}
