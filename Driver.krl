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

  rule delivery_gossip_requested {
    select when gossip delivery_gossip

    pre {
      seen = random:integer(0,1) == 1
    }

    if seen then
      send_directive("delivery seen message")

    fired {
      raise gossip event "delivery_seen"
    }
    else {
      raise gossip event "delivery_message"
    }
  }

    rule send_delivery_seen {
    select when gossip delivery_seen where ent:process.defaultsTo(true)

    pre {
      peer_subscription = getAnyPeer()
      my_delivery_seen = ent:seen.defaultsTo({})
    }

    every {
      send_directive("seen", my_delivery_seen);
      event:send({
          "eci": peer_subscription{"Tx"},
          "eid": "none",
          "domain": "gossip",
          "type": "new_delivery_seen",
          "attrs": my_delivery_seen
        });
    }
  }

  rule release_request {
    select when driver rejected

    send_directive("releasing request")

    fired {
      // remove order from requested list.
    }
  }

  rule driver_approved {
    select when driver approved

    pre {
      delivery = event:attr("delivery")
      id = delivery{"id"}
      
    }

    send_directive("new delivery")

    fired {
      ent:deliveries := ent:deliveries.defaultsTo({}).put(id, delivery);
      raise driver event "delivery_created" attributes event:attrs
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
    }

    send_directive("updating peer")

    fired {
      ent:peers := ent:peers.delete(peer_id);
      ent:peers := ent:peers.defaultsTo({}).set(new_id, {
        "id": new_id,
        "messages": {}
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
