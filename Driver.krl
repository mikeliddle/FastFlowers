ruleset Driver {
  meta {
    use module io.picolabs.subscription alias subscriptions
    use module io.picolabs.keys
    shares __testing
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

    get_random_order = function() {
      
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
      raise gossip event "seen_gossip"
    }
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
    select when sensor new_peer

    pre {
      peer_id = event:attr("eci")
      peer_name = event:attr("sensor_name")
      host = event:attr("host")
      tx = event:attr("tx")
    }

    send_directive("received a new peer!")

    always {
      ent:peers := ent:peers.defaultsTo({}).put(peer_id, {
        "id": peer_id,
        "messages": {}
      });

      raise wrangler event "subscription" attributes {
        "name": peer_id,
        "Rx_role": "driver",
        "Tx_role": tx,
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
      role = event:attr("Tx_role").defaultsTo(False) == "driver"
    }

    if role then
      send_directive("updating peer")

    fired {
      ent:peers := ent:peers.delete(peer_id);
      ent:peers := ent:peers.defaultsTo({}).set(new_id, {
        "id": new_id,
        "orders": {}
      });
    }
  }

  rule schedule_gossip {
    select when system online or wrangler ruleset_added or gossip heartbeat

    if ent:status.defaultsTo(true) then
      send_directive("Scheduled Heartbeat!")

    fired {
      schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": ent:gossip_interval.defaultsTo("5")})
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
