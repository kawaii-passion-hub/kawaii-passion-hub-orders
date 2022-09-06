import 'dart:io';

import 'package:collection/collection.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:kawaii_passion_hub_orders/kawaii_passion_hub_orders.dart';

class OrdersDashboard extends StatelessWidget {
  OrdersDashboard({Key? key}) : super(key: key) {
    localBus = GetIt.I.get(instanceName: 'kawaii_passion_hub_orders');
  }

  late final EventBus localBus;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OrdersUpdated>(
      stream: localBus.on<OrdersUpdated>(),
      initialData: OrdersUpdated(OrdersState.current),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const LoadingPage();
        }

        List<Order> orders = List.from(snapshot.data!.orders);
        orders.sort((a, b) => compareOrders(a, b));

        return Scaffold(
          appBar: AppBar(
            // Here we take the value from the MyHomePage object that was created by
            // the App.build method, and use it to set our appbar title.
            title: const Text('Orders Overview'),
            actions: <Widget>[
              IconButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => OpenOrderSummary(
                            openOrders: orders
                                .where((element) => element.state == "Open")
                                .toList()))),
                icon: const Icon(Icons.assignment_outlined),
                tooltip: 'Open orders summary',
              )
            ],
          ),
          body: ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              var order = orders.elementAt(index);
              return ListTile(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OrderDetailsView(order: order),
                    )),
                title: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(order.orderNumber)),
                subtitle: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                        '${order.customer.fullName} - ${order.price} € - ${order.state}')),
              );
            },
          ),
        );
      },
    );
  }

  int compareOrders(Order a, Order b) {
    bool aDone = a.state == "Done" || a.state == "Cancelled";
    bool bDone = b.state == "Done" || b.state == "Cancelled";
    if (aDone && !bDone) {
      return 1;
    }
    if (bDone && !aDone) {
      return -1;
    }
    return b.orderNumber.compareTo(a.orderNumber);
  }
}

class OpenOrderSummary extends StatelessWidget {
  const OpenOrderSummary({Key? key, required this.openOrders})
      : super(key: key);

  final List<Order> openOrders;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    TextStyle unimportantStyle = theme.textTheme.bodyText2!;
    Color? color = theme.textTheme.caption!.color;
    unimportantStyle = unimportantStyle.copyWith(color: color);

    List<CommentedOrderItem> items = groupBy(
            openOrders.expand((element) => element.items
                .map((item) => CommentedOrderItem(item, element.comment))),
            (CommentedOrderItem item) => item.productNumber)
        .map((key, value) => MapEntry(
            key, value.reduce((value, element) => value.mergeWith(element))))
        .values
        .toList();

    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: const Text('Open Orders Summary'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(5, 15, 5, 10),
        child: SingleChildScrollView(
          child: DataTable(
            dataRowHeight: 100,
            columns: const <DataColumn>[
              DataColumn(
                label: Text('Quantity'),
              ),
              DataColumn(
                label: Text('Product'),
              )
            ],
            rows: List<DataRow>.generate(
              items.length,
              (index) => DataRow(
                color: MaterialStateProperty.resolveWith<Color?>(
                    (Set<MaterialState> states) {
                  // All rows will have the same selected color.
                  if (states.contains(MaterialState.selected)) {
                    return Theme.of(context)
                        .colorScheme
                        .primary
                        .withOpacity(0.08);
                  }
                  // Even rows will have a grey color.
                  if (index.isEven) {
                    return Colors.grey.withOpacity(0.3);
                  }
                  return null; // Use default value for other states and odd rows.
                }),
                cells: <DataCell>[
                  DataCell(
                    Text(items[index].quantity.toString()),
                  ),
                  DataCell(
                    FittedBox(
                      fit: BoxFit.fitHeight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:
                            orderItemDetail(items[index], unimportantStyle),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> orderItemDetail(
      CommentedOrderItem item, TextStyle unimportantStyle) {
    List<Widget> result = List<Widget>.from([
      Text(item.productName),
      const SizedBox(height: 4),
      Text(
        item.productNumber,
        style: unimportantStyle,
      ),
    ]);
    result.addAll(item.options
        .map((o) => <Widget>[
              const SizedBox(height: 4),
              Text(o, style: unimportantStyle),
            ])
        .expand((element) => element));
    if (item.comment.isNotEmpty) {
      result.addAll([
        const SizedBox(height: 4),
        Text(
          item.comment,
          style: unimportantStyle,
        ),
      ]);
    }
    return result;
  }
}

class CommentedOrderItem extends OrderItem {
  final String comment;

  CommentedOrderItem(OrderItem decorated, this.comment)
      : super(decorated.productNumber, decorated.productName, decorated.options,
            decorated.quantity);

  CommentedOrderItem.withQuantity(
      OrderItem decorated, this.comment, int quantity)
      : super(decorated.productNumber, decorated.productName, decorated.options,
            quantity);

  CommentedOrderItem mergeWith(CommentedOrderItem element) {
    String comment = this.comment;
    if (comment.isNotEmpty && element.comment.isNotEmpty) {
      comment += '\n';
    }
    comment += element.comment;
    return CommentedOrderItem.withQuantity(
        this, comment, quantity + element.quantity);
  }
}

class OrderDetailsView extends StatelessWidget {
  const OrderDetailsView({Key? key, required this.order}) : super(key: key);

  final Order order;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    TextStyle unimportantStyle = theme.textTheme.bodyText2!;
    Color? color = theme.textTheme.caption!.color;
    unimportantStyle = unimportantStyle.copyWith(color: color);

    List<Widget> details = List<Widget>.from(
      [
        Card(
          clipBehavior: Clip.antiAlias,
          elevation: 2,
          shape: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(16),
                color: theme.colorScheme.primary.withOpacity(0.7),
                child: Text(
                  'Customer',
                  style: unimportantStyle,
                ),
              ),
              Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(order.customer.fullName),
              ),
              Container(
                alignment: Alignment.centerLeft,
                padding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                child: Text(order.customer.street),
              ),
              Container(
                alignment: Alignment.centerLeft,
                padding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                child: Text('${order.customer.zipCode} ${order.customer.city}'),
              ),
              Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text(order.customer.country),
              ),
            ],
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          elevation: 2,
          shape: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(16),
                color: theme.colorScheme.primary.withOpacity(0.7),
                child: Text(
                  'Products',
                  style: unimportantStyle,
                ),
              ),
              Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(16),
                child: DataTable(
                  dataRowHeight: 100,
                  columns: const <DataColumn>[
                    DataColumn(
                      label: Text('Quantity'),
                    ),
                    DataColumn(
                      label: Text('Product'),
                    )
                  ],
                  rows: List<DataRow>.generate(
                    order.items.length,
                    (index) => DataRow(
                      color: MaterialStateProperty.resolveWith<Color?>(
                          (Set<MaterialState> states) {
                        // All rows will have the same selected color.
                        if (states.contains(MaterialState.selected)) {
                          return Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.08);
                        }
                        // Even rows will have a grey color.
                        if (index.isEven) {
                          return Colors.grey.withOpacity(0.3);
                        }
                        return null; // Use default value for other states and odd rows.
                      }),
                      cells: <DataCell>[
                        DataCell(
                          Text(order.items[index].quantity.toString()),
                        ),
                        DataCell(
                          FittedBox(
                            fit: BoxFit.fitHeight,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: orderItemDetail(
                                  order.items[index], unimportantStyle),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (order.comment.isNotEmpty) {
      details.insert(
          0,
          Card(
            clipBehavior: Clip.antiAlias,
            elevation: 2,
            shape: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(16),
                  color: theme.colorScheme.primary.withOpacity(0.7),
                  child: Text(
                    'Comment',
                    style: unimportantStyle,
                  ),
                ),
                Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(16),
                  child: Text(order.comment),
                ),
              ],
            ),
          ));
    }

    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text('${order.orderNumber} Details'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(5, 15, 5, 10),
        child: SingleChildScrollView(
          child: Column(children: details),
        ),
      ),
    );
  }

  List<Widget> orderItemDetail(OrderItem item, TextStyle unimportantStyle) {
    List<Widget> result = List<Widget>.from([
      Text(item.productName),
      const SizedBox(height: 4),
      Text(
        item.productNumber,
        style: unimportantStyle,
      ),
    ]);
    result.addAll(item.options
        .map((o) => <Widget>[
              const SizedBox(height: 4),
              Text(o, style: unimportantStyle),
            ])
        .expand((element) => element));
    return result;
  }
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            CircularProgressIndicator(
              backgroundColor: Colors.white,
            ),
            SizedBox(height: 10),
            Text(
              'Carregando',
              style: TextStyle(
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
