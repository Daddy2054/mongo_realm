import 'package:flutter_todo/realm/schemas.dart';
import 'package:realm/realm.dart';
import 'package:flutter/material.dart';

class RealmServices with ChangeNotifier {
  static const String queryAllName = "getAllItemsSubscription";
  static const String queryMyItemsName = "getMyItemsSubscription";
  static const String queryMyHighPriorityItemsName =
      "getMyHighPriorityItemsSubscription";
  static const String queryMyHighOrNoPriorityItemsName =
      "getMyHighOrNoPriorityItemsSubscription";

  bool showAll = false;
  bool offlineModeOn = false;
  bool isWaiting = false;
  late Realm realm;
  User? currentUser;
  App app;

  RealmServices(this.app) {
    if (app.currentUser != null || currentUser != app.currentUser) {
      currentUser ??= app.currentUser;
      realm = Realm(Configuration.flexibleSync(currentUser!, [Item.schema]));
      showAll = (realm.subscriptions.findByName(queryAllName) != null);
       // Check if subscription previously exists on the realm
      final subscriptionDoesNotExists =
          realm.subscriptions.findByName(queryMyHighOrNoPriorityItemsName) ==
              null;
      if (realm.subscriptions.isEmpty || subscriptionDoesNotExists) {
        updateSubscriptions();
      }
    }
  }

  Future<void> updateSubscriptions() async {
    realm.subscriptions.update((mutableSubscriptions) {
      mutableSubscriptions.clear();
      if (showAll) {
        mutableSubscriptions.add(realm.all<Item>(), name: queryAllName);
      } else {
        mutableSubscriptions.add(
            realm.query<Item>(
              r'owner_id == $0 AND priority IN {$1, $2, $3}',
              [currentUser?.id, PriorityLevel.high, PriorityLevel.severe, null],
            ),
            name: queryMyHighPriorityItemsName);
      }
    });
    await realm.subscriptions.waitForSynchronization();
  }

  Future<void> sessionSwitch() async {
    offlineModeOn = !offlineModeOn;
    if (offlineModeOn) {
      realm.syncSession.pause();
    } else {
      try {
        isWaiting = true;
        notifyListeners();
        realm.syncSession.resume();
        await updateSubscriptions();
      } finally {
        isWaiting = false;
      }
    }
    notifyListeners();
  }

  Future<void> switchSubscription(bool value) async {
    showAll = value;
    if (!offlineModeOn) {
      try {
        isWaiting = true;
        notifyListeners();
        await updateSubscriptions();
      } finally {
        isWaiting = false;
      }
    }
    notifyListeners();
  }

void createItem(String summary, bool isComplete, int? priority) {
    final newItem = Item(ObjectId(), summary, currentUser!.id,
        isComplete: isComplete, priority: priority);
    realm.write<Item>(() => realm.add<Item>(newItem));
    notifyListeners();
  }

  void deleteItem(Item item) {
    realm.write(() => realm.delete(item));
    notifyListeners();
  }

  Future<void> updateItem(Item item,
      {String? summary, bool? isComplete, int? priority}) async {
    realm.write(() {
      if (summary != null) {
        item.summary = summary;
      }
      if (isComplete != null) {
        item.isComplete = isComplete;
      }
      if (priority != null) {
        item.priority = priority;
      }
    });
    notifyListeners();
  }

  Future<void> close() async {
    if (currentUser != null) {
      await currentUser?.logOut();
      currentUser = null;
    }
    realm.close();
  }

  @override
  void dispose() {
    realm.close();
    super.dispose();
  }
}

abstract class PriorityLevel {
  static int severe = 0;
  static int high = 1;
  static int medium = 2;
  static int low = 3;
}