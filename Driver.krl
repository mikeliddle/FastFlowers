ruleset Driver {
  meta {
    use module io.picolabs.subscription alias subscriptions
    use module io.picolabs.keys
    shares __testing, orders
  }
  global {
    __testing = { "queries":
      [ { "name": "__testing" }
      //, { "name": "entry", "args": [ "key" ] }
      ] , "events":
      [ //{ "domain": "d1", "type": "t1" }
      //, { "domain": "d2", "type": "t2", "attrs": [ "a1", "a2" ] }
      ]
    }

    getDirections = defaction(my_location, destination) {
      base_url = <<https://maps.googleapis.com/maps/api/directions/json?key=#{keys:google}>>
      
      driving_mode = "DRIVING"
      
      body = {
        "origin": my_location,
        "destination": destination,
        "travelMode": driving_mode
      }

      http:post(base_url, form=body);
    }

    getOrderStatus = function() {
      1 // pick_up, enroute, completed
    }
    
    getOrders = function() {
      ent:orders => ent:orders | {}
    }

    getPeers = function() {
      ent:peers => ent:peers | {}
    }
    
    getSeen = function() {
      ent:seen_orders => ent:seen_orders | {}
    }
    
    getPeer = function() {
      available_peers = getPeers().filter(function(peer_value,peer_id) {
        adjusted_orders = getOrders().filter(function(origin_group, store_id) {
          order_id = ent:peers{[peer_id,"orders",store_id]}.klog("order_id");
          
          origin_group.keys().any(function(x) {x > order_id}).klog("origin_groups");
        });
        
        length(adjusted_orders) != 0;
      });
      
      peer_count = length(available_peers.keys()) - 1;
      rand_index = random:integer(0,peer_count).klog("rand_index");
      
      peer_index = available_peers.keys()[rand_index].klog("peer_index");
      
      available_peers{peer_index}.klog("driver");
    }

    getAnyPeer = function() {
      peer_count = length(subscriptions:established("Tx_role", "driver")) - 1;
      rand_index = random:integer(peer_count).klog("peer_index");
      subscriptions:established("Tx_role", "driver").klog("drivers")[rand_index].klog("driver");
    }

    getOrder = function(driver) {
      available_groups = getOrders().klog("orders").filter(function(origin_group, store_id) {
        current_order_id = driver{["orders", store_id]}.defaultsTo(false);
        orders = origin_group.keys().klog("order_keys");
        last_order = orders[length(orders) - 1];
      
        test = current_order_id => (current_order_id < last_order) | true;
        test
      });
      rand_index = random:integer(0,length(available_groups.keys()) - 1).klog("rand_index");
      group_index = available_groups.keys()[rand_index].klog("group_index");
      
      order_index = peer{["orders", group_index]};
      order_index = order_index => (math:int(order_index) + 1).as("String") | "1";
      
      {
        "OrderId": group_index + ":" + order_index,
        "Order": ent:orders{[group_index, order_index.klog("OrderId")]}.klog("returns")
      }
    }

    get_random_order = function() {
      
    }
  }

  rule order_made_available {
    select when driver order_available
    pre {
      order = event:attr("order");
      store_id = order{"StoreId"};
      order_status = order{"Status"};
      timestamp = order{"Timestamp"}
      order_group = getOrders(){store_id}.defaultsTo({})
      order_id = order{"OrderId"}
    }
    if order then
      send_directive("Order Available")
    fired {
      ent:orders{store_id} := order_group.put(order_id, {
        "Status" : order_status,
        "Timestamp" : timestamp
      });
      ent:seen_orders{store_id} := order_id;
      raise driver event "gossip_heartbeat"
    }
  }
    
  rule send_order_gossip {
    select when driver send_order where ent:status.defaultsTo(true)
    pre {
      current_peer = getPeer()
      peer_entity = ent:peers{current_peer{"id"}}.defaultsTo({})  // TODO: Art ask Mike about "id" and how it's set.
      order = getOrder(current_peer)
      peer_subscription = subscriptions:established("Tx_role", "peer").filter(function(x) {
        x{"Tx"}.klog("tx") == current_peer{"id"}.klog("peerId")
      })[0].klog("subscription")
    }
    
    every{
      send_directive("peer", peer_subscription);
      event:send({
        "eci": peer_subscription{"Tx"},
        "eid": "none",
        "domain": "driver",
        "type": "handle_order",
        "attrs": order
      });
    }
  }
  
  rule handle_order_gossip {
    select when driver handle_order where ent:status.defaultsTo(true)
    
    pre {
      order_id = event:attr("OrderId")
      id_array = ids.split(re#:#)
      store_id = id_array[0]
      order_num = math:int(id_array[1])
      order = event:attr("Order")

      origin_group = getOrders().get(origin_id).defaultsTo({})
      updated_orders = origin_group.put(order_num, order)
    }
    
    if origin_group != {} && order_num - 1 != math:int(ent:seen{store_id}) then
      send_directive("Not adding Order", {"ids": ids})
 
    notfired {
      ent:orders := getOrders().set(store_id, updated_orders);
      ent:seen{store_id} := order_num;
    }
  }
  
  rule send_seen_gossip {
    select when driver send_seen_orders where ent:status.defaultsTo(true)
    pre {
      peer_subscription = getAnyPeer()
      my_seen = getSeen()
    }
    every {
      event:send( { 
        "eci": peer_subscription{"Tx"}, 
        "eid": "send-seen-order",
        "domain": "driver", 
        "type": "handle_seen_orders",
        "attrs": my_seen } )
    }
  }
  
  rule handle_seen_gossip {
    select when driver handle_seen_orders where ent:status.defaultsTo(true)
    pre {
      my_eci = meta:eci;
      gossiper_name = subscriptions:established("Rx", my_eci)[0].klog("driver"){"Tx"};
      new_seen = event:attrs
    }
    
    send_directive("received seen", new_seen);
    
    always {
      ent:peers{[their_name, "orders"]} := new_seen
    }
  }
  
  rule order_status_update {
    select when driver status_update
    pre {
      order = "something"
      order_id = order["order_id"]
      shop_id = order["ship_id"] // from order
      status = getOrderStatus()
    }
    event:send(
          { "eci": shop_id, "eid": "status_update",
            "domain": "shop", "type": "status_update",
            "attrs": { "driver_id": meta:picoId, "order_id": order_id,"status": status }})
  }

  rule ready_for_delivery {
    select when gossip heartbeat where length(ent:requested.keys()) == 0

    pre {
      order = get_random_order()
      ids = event:attr("id")
      id_array = ids.split(re#:#)
      shop_id = id_array[0]
      order_id = id_array[1]
      order = event:attr("order")
      shop_host = order{"shop_host"}
    }

    fired {
      ent:requested := ent:requested.defaultsTo({}).put(ids, order);
      raise wrangler event "subscription" attributes {
        "name": shop_id,
        "Rx_role": "driver",
        "Tx_role": "shop",
        "Tx_host": shop_host,
        "channel_type": "subscription",
        "wellKnown_Tx": shop_id
      };
    }
  }

  rule release_request {
    select when driver rejected

    pre {
      order_id = event:attr("order_id")
    }

    send_directive("releasing request")

    fired {
      ent:requested := ent:requested.delete(order_id)
    }
  }

  rule driver_approved {
    select when driver approved

    pre {
      delivery = event:attr("order")
      id = delivery{"id"}
      
    }

    send_directive("new delivery")

    fired {
      ent:deliveries := ent:deliveries.defaultsTo({}).put(id, delivery);
      raise driver event "delivery_created" attributes event:attrs;
    }
  }

  rule get_directions {
    select when driver delivery_created

    pre { 
      order = event:attr("order")
      location = order{"location"}
    }

    if location then
      every {
        getDirections(location);
        send_directive("directions", directions);
      }
  }

  rule scheduling_update {
    select when driver delivery_created

    pre {
      order = event:attr("order")
    }

    send_directive("scheduling status updates")

    fired {
      schedule driver event "status_updated" at time:add(time:now(), {"seconds": "5"})
        attributes {
          "status": "driver assigned",
          "order_id": order{"id"}
        }
    }
  }

  rule send_update {
    select when driver status_updated

    pre {
      new_status = ent:status.defaultsTo("picking up flowers")
      order_id = event:attr("order_id")
      store_subscription = subscriptions:established("Tx_role", "store").filter(function(x) {
        x{"Tx"}.klog("tx") == current_store{"id"}.klog("storeId")
      })[0].klog("subscription")
      completed = new_status == "completed"
    }

    if completed then
      every {
        send_directive("delivery complete!");
        event:send({
          "eci": store_subscription{"Tx"},
          "eid": "none",
          "domain": "gossip",
          "type": "seen",
          "attrs": my_seen
        });
      }

    notfired {
      schedule driver event "status_updated" at time:add(time:now(), {"seconds": "5"})
        attributes {
          "status": new_status
        };
    }
  }

  rule new_peer {
    select when driver new_peer

    pre {
      peer_id = event:attr("eci")
      peer_name = event:attr("sensor_name")
      host = event:attr("host")
    }

    send_directive("received a new peer!")

    always {
      ent:peers := ent:peers.defaultsTo({}).put(peer_id, {
        "id": peer_id,
        "orders": {}
      });

      raise wrangler event "subscription" attributes {
        "name": peer_id,
        "Rx_role": "peer",
        "Tx_role": "peer",
        "Tx_host": host,
        "channel_type": "subscription",
        "wellKnown_Tx": peer_id
      }
    }
  }

  rule update_peer {
    select when wrangler subscription_added

    pre {
      peer_id = event:attr("name").klog("name")
      new_id = event:attr("Tx").klog("tx")
    }

    send_directive("updating peer")

    fired {
      ent:peers := ent:peers.delete(peer_id);
      ent:peers := ent:peers.defaultsTo({}).set(new_id, {
        "id": new_id,
        "orders": {}
      });
    }
  }
  
  rule gossip {
    select when driver gossip_heartbeat
    
    pre {
      order = random:integer(0,1) == 1
    }

    if order then
      send_directive("Sending Gossip")

    fired {
      raise driver event "send_order"
    }
    else {
      raise driver event "send_seen_orders"
    }
  }

  rule schedule_gossip {
    select when system online or wrangler ruleset_added or driver gossip_heartbeat

    if ent:status.defaultsTo(true) then
      send_directive("Scheduled Heartbeat!")
      
    fired {
      //schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": ent:gossip_interval.defaultsTo("5")})
    }
  }

  rule status_changed {
    select when gossip process
    
    pre {
      status = event:attr("status")
      new_status = status == "on" => true | status != "off"
    }
    
    send_directive("updated status")
    
    fired {
      ent:status := new_status
    }
  }

  rule interval_changed {
    select when gossip interval_changed

    pre { 
      new_n = event:attr("n").defaultsTo(false)
    }

    if new_n then
      send_directive("updating n", new_n)

    fired {
      ent:gossip_interval := new_n
    }
  }
}
