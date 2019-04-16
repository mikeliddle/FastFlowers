ruleset Shop {
  meta {
    use module io.picolabs.wrangler alias wrangler
    use module io.picolabs.subscription alias Subscriptions
    shares __testing
  }
  global {
    __testing = { 
      "queries": [ 
        { "name": "__testing" } 
      ],
      "events": [ 
        { "domain": "shop", "type": "order_received"}
        //{ "domain": "mischief", "type": "hat_lifted"} 
      ] }
    
    rank_threshold = 2
    auto_assign = true
    // location
    
    order_count = function() {
      ent:order_num.defaultsTo(0)
    }
    
    drivers = function() {
      ent:drivers.defaultsTo([])
    }
    
    orders = function() {
      ent:reports.defaultsTo({})
    }
    
    getStatus = function(id) {
      
    }
    
    getOrder = function(id) {
      
    }
    
    collect = function(driver) {
      
    }
    
    notify = function() {
      // not sure if we want this or just need Shop_status ruleset
    }
    
    generateOrder = function( storeId, timestamp  ) {
      order_id = storeId + ":" + order_count().as("String");
      order = {
        "OrderId": order_id,
        "ShopId": storeId,
        "Timestamp": timestamp,
        "Status" : "ready"
      };
      order
    }
  }
  
  rule delivery_requested {
    select when shop delivery_requested
    pre {
      driver_id = event:attr("driver_id")
    }
    
    if ent:auto_select then
      event:send({
        "eid": "none",
        "domain": "shop",
        "type": "driver_decision",
        "attrs": {
          "driver_id": driver_id
        }
      })

    fired {
      // check request
      raise driver event ""
        attributes { "driver_id": driver_id } 
    }
  }
  
  rule driver_approved_rejected {
    select when shop approved_rejected
    pre {
      driver_id = event:attr("driver_id")
    }
    // send to driver
  }
  
  rule order_received {
    select when shop order_received
    pre {
      store_id = meta:picoId;
      current_time = time:now();
      order = generateOrder(store_id, current_time);
      updated_attrs = event:attrs.put(["order"],order)
    }
    always {
      ent:order_num := order_count() + 1;
      ent:reports := orders().put([order{"order_id"}], order);
      raise shop event "order_ready"
        attributes updated_attrs;
    }
  }
  
  rule order_ready {
    select when shop order_ready
    // Choose 1 (or multiple?) driver(s) from a pool of known drivers to send order to.
    foreach Subscriptions:established("Tx_role", "driver") setting (driver)
    pre {
      order = event:attr("order");
    }
    event:send(
          { "eci": driver["Tx"], "eid": "order-ready",
            "domain": "driver", "type": "order_ready",
            "attrs": { "order": order }})
  }
  
  rule order_available {
    select when shop order_available
    // send each driver status_updated with it's eci
    foreach Subscriptions:established("Tx_role", "neighbor") setting (var)
    event:send(
          { "eci": var["Tx"], "eid": "whatever",
            "domain": "sensor", "type": "report",
            "attrs": { "Rx": var["Rx"]  }})
  }
  
  rule status_updated {
    // send customer update info
    select when shop status_updated
    pre {
      order_id = event:attr("order_id")
    }
    // update order
    // pick_up, enroute, completed
  }
}
