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
    
    getSeen = function() {
      ent:seen_orders => ent:seen_orders | {}
    }
    
    getPeer = function() {
      available_peers = ent:peers.defaultsTo({}).filter(function(peer_value,peer_id) {
        adjusted_orders = ent:orders.defaultsTo({}).filter(function(origin_group, origin_id) {
          order_id = ent:peers{[peer_id,"orders",origin_id]}.klog("order_id");
          
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
      available_groups = ent:orders.defaultsTo({}).klog("orders").filter(function(origin_group, origin_id) {
        current_order_id = driver{["orders", origin_id]}.defaultsTo(false);
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

    updateOrders = function(order) {
      update = orders().put([order{"StoreId"},order{"OrderId"}], order);
      update
    }
    
    chooseDriver = function() {
      neighbors = subscriptions:established("Tx_role", "driver");
      neighbors_eci = neighbors.map(function(v,k) {
        peer_eci = v{"Tx"}.klog("Peer's ECI: ");
        peer_eci
      });
      neighbors_eci[random:integer(neighbors.length()-1)]
    }
    
    getOrdersSummary = function() {
      // summary = s
    }
  }

  rule order_made_available {
    select when driver order_available
    pre {
      order = event:attr("order");
      new_orders = updateOrders(order);
    }
    send_directive("Updating Drivers Orders")
    always {
      ent:orders := new_orders;
      raise driver event "start_gossip"
        attributes event:attrs
    }
  }
  
  rule driver_gossip_started {
    select when driver start_gossip
    pre {
      neighbor = chooseDriver()
      updated_attrs = event:attrs.put(["driver"], neighbor);
      gossip_type = random:integer(1)
    }

    if gossip_type == 0 then
      send_directive("Sending Order gossip")

    fired {
      raise driver event "send_order"
        attributes updated_attrs
    }
    else {
      raise driver event "send_seen_orders"
        attributes updated_attrs
    }
  }
  
  rule send_order_gossip {
    select when driver send_order
    
  }
  
  rule handle_order_gossip {
    select when driver handle_seen_orders
    
  }
  
  rule send_seen_gossip {
    select when driver send_seen_orders
    pre {
      peer_eci = event:attr("driver").klog("Send Seen to: ");
      summary = getOrdersSummary();
      updated_attrs = event:attrs.put(["seen_orders"], summary).klog("Send_seen UPDATED ATTRS: ");
      
    }
    event:send( { "eci": peer_eci, "eid": "send-seen-order",
                  "domain": "gossip", "type": "seen_received",
                  "attrs": updated_attrs } )
    fired {
      // raise gossip event "schedule_heartbeat"
    }
  }
  
  rule handle_seen_gossip {
    select when driver handle_seen_orders
  }
  
  rule order_available {
    select when driver order_available
    pre {
      order = event:attr("order")
      shop_Rx = event:attr("Rx")
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

  rule release_request {
    select when driver rejected

    send_directive("releasing request")

    fired {
      // remove order from requested list.
    }
  }

  rule get_directions {
    select when driver approved

    pre { 
      location = event:attr("location")
    }

    if location then
      every {
        getDirections(location);
        send_directive("directions", directions);
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
    select when gossip heartbeat
    
    pre {
      order = random:integer(0,1) == 1
    }

    if order then
      send_directive("Sending Order gossip")

    fired {
      raise gossip event "order_gossip"
    }
    else {
      raise gossip event "delivery_gossip"
    }
  }

  rule schedule_gossip {
    select when system online or wrangler ruleset_added or gossip heartbeat

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