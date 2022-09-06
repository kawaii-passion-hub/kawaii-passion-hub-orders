import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:event_bus/event_bus.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:kawaii_passion_hub_authentication/kawaii_passion_hub_authentication.dart';
import 'package:synchronized/synchronized.dart';
import 'constants.dart' as constants;
import 'model.dart';

bool initialized = false;

void initialize({bool useEmulator = false}) {
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
  Controller controller = Controller(globalBus, localBus, ordersApp);
  GetIt.I.registerSingleton(controller);
  GetIt.I
      .registerSingleton(localBus, instanceName: 'kawaii_passion_hub_orders');
  controller.subscribeToEvents();
}

class Controller extends Disposable {
  final EventBus globalBus;
  final EventBus localBus;
  final FirebaseApp ordersApp;
  bool initializedModel = false;
  final Lock modelInitalizationLock = Lock();
  StreamSubscription<UserInformationUpdated>? loginInformation;

  Controller(this.globalBus, this.localBus, this.ordersApp);

  void subscribeToEvents() {
    loginInformation = globalBus.on<UserInformationUpdated>().listen((event) {
      updateAuthentification(event);
    });
  }

  void updateAuthentification(UserInformationUpdated event) async {
    if (event.newUser.isAuthenticated &&
        event.newUser.claims?['whitelisted'] == true) {
      try {
        HttpsCallableResult<String> result =
            await FirebaseFunctions.instanceFor(app: ordersApp)
                .httpsCallable('authenticate')
                .call({"jwt": event.newUser.jwt});
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
  }

  Future initializeModel() async {
    if (initializedModel) {
      return;
    }
    await modelInitalizationLock.synchronized(() async {
      initializedModel = true;
      try {
        final ref = FirebaseDatabase.instanceFor(app: ordersApp).ref('orders');
        final snapshot = await ref.get();
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
                    : '');
            ordersModel.add(orderModel);
          }
          OrdersState.current = ordersModel;
          localBus.fire(OrdersUpdated(ordersModel));
        } else {
          return;
        }
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

  @override
  FutureOr onDispose() {
    loginInformation?.cancel();
  }
}
