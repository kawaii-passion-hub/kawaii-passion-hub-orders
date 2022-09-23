import 'package:event_bus/event_bus.dart';
import 'package:kawaii_passion_hub_orders/kawaii_passion_hub_orders.dart';
import 'package:kawaii_passion_hub_orders_example/global_context.dart';
import 'package:kawaii_passion_hub_orders_example/widgets/auth_gat.dart';
import 'package:kawaii_passion_hub_orders_example/widgets/event_bus_widget.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:kawaii_passion_hub_authentication/kawaii_passion_hub_authentication.dart'
    as auth;
import 'package:kawaii_passion_hub_orders/kawaii_passion_hub_orders.dart'
    as orders;
import 'package:kawaii_passion_hub_orders_example/widgets/home.dart';
import 'auth_firebase_options.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseApp ordersApp = await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseApp authApp = await Firebase.initializeApp(
      options: AuthFirebaseOptions.currentPlatform, name: 'auth');
  EventBus globalBus = initializeApp(authApp, ordersApp);
  runApp(MyApp(
    eventBus: globalBus,
  ));
}

EventBus initializeApp(FirebaseApp authApp, FirebaseApp ordersApp) {
  EventBus globalBus = EventBus();
  GetIt.I.registerSingleton(globalBus);
  GetIt.I.registerSingleton(authApp, instanceName: auth.FirebaseAppName);
  GetIt.I.registerSingleton(ordersApp, instanceName: orders.firebaseAppName);
  orders.initialize(useEmulator: useEmulator);
  return globalBus;
}

class MyApp extends StatelessWidget {
  // ignore: prefer_const_constructors_in_immutables
  MyApp({Key? key, required this.eventBus}) : super(key: key);

  final EventBus eventBus;

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return EventBusWidget(
      eventBus: eventBus,
      child: MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData(
          // This is the theme of your application.
          //
          // Try running your application with "flutter run". You'll see the
          // application has a blue toolbar. Then, without quitting the app, try
          // changing the primarySwatch below to Colors.green and then invoke
          // "hot reload" (press "r" in the console where you ran "flutter run",
          // or simply save your changes to "hot reload" in a Flutter IDE).
          // Notice that the counter didn't reset back to zero; the application
          // is not restarted.
          primarySwatch: Colors.blue,
        ),
        initialRoute: '/',
        navigatorKey: NavigationService().navigatorKey,
        routes: {
          '/': (context) =>
              AuthGate(nextScreenBuilder: (c) => const MyHomePage()),
          OrderDetailsView.route: (context) =>
              AuthGate(nextScreenBuilder: (c) => orders.OrderDetailsView()),
        },
      ),
    );
  }
}
