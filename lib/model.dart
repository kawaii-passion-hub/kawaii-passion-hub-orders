class OrdersState {
  static List<Order> current = List.empty();
  static String? messagingToken;
}

class OrdersUpdated {
  final List<Order> orders;

  OrdersUpdated(this.orders);
}

class MessagingTokenUpdated {
  final String? messagingToken;

  MessagingTokenUpdated(this.messagingToken);
}

class CombinedEvent<T1, T2> {
  final T1 event1;
  final T2 event2;

  CombinedEvent(this.event1, this.event2);
}

class Order {
  final String orderNumber;
  final OrderCustomer customer;
  final List<OrderItem> items;
  final double price;
  final bool paid;
  final String state;
  final String comment;
  final DateTime issued;

  Order(this.orderNumber, this.customer, this.items, this.price, this.paid,
      this.state, this.comment, this.issued);
}

class OrderItem {
  final String productNumber;
  final String productName;
  final List<String> options;
  final int quantity;

  OrderItem(this.productNumber, this.productName, this.options, this.quantity);
}

class OrderCustomer {
  final String fullName;
  final String street;
  final String zipCode;
  final String city;
  final String country;
  final String countryIso;

  OrderCustomer(this.fullName, this.street, this.zipCode, this.city,
      this.country, this.countryIso);
}
