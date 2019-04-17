ruleset Shop {
  meta {
    use module io.picolabs.wrangler alias wrangler
    use module io.picolabs.subscription alias Subscriptions
    shares __testing, orders
  }
  global {
    __testing = { 
      "queries": [ 
        { "name": "__testing" },
        { "name": "orders" }
      ],
      "events": [ 
        { "domain": "shop", "type": "order_available"}
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
    
    // Shouldn't orders contain {order_id :  { order_id, store_id, status, timestamp, driver_id, direction } }
    orders = function() { // contain {order_id :  { order_id, status, driver_id, direction } }
      ent:orders.defaultsTo({})
    }
    
    getStatus = function(id) {
      ent:orders[id]["status"]
    }
    
    getOrder = function(id) {
      ent:orders.get(id)
    }
    
    // collect = function(driver) {
      
    // }
    
    // notify = function() {
    //   // not sure if we want this or just need Shop_status ruleset
    // }
    
    generateOrder = function( shop_host, timestamp ) {
      order_id = meta:picoId + ":" + order_count().as("String");
      order = {
        "order_id": order_id,
        "shop_host": shop_host,
        "timestamp": timestamp,
        "status" : "ready",
        "driver_id" : "",
        "destination" : ""
      };
      order
    }
  }
  
  rule delivery_requested {
    select when shop delivery_requested
    pre {
      order_id = event:attr("order_id")
      driver_id = event:attr("driver_id")
      store_id = meta:picoId;
      current_time = time:now();
      
    // TODO: generateOrder || getOrder
      order = generateOrder(store_id, current_time);
      // order = getOrder(order_id)
      updated_attrs = event:attrs.put(["order"],order)
    }
    // if ent:auto_select then
    //   event:send({
    //     "eid": "none",
    //     "domain": "shop",
    //     "type": "driver_decision",
    //     "attrs": {
    //       "driver_id": driver_id
    //     }
    //   })
      
    always {
      ent:order_num := order_count() + 1;
      ent:orders := orders().put([order{"order_id"}], order);
      raise shop event "driver_decision"
        attributes updated_attrs;
    }
    // fired {
    //   // check request & approve/reject
    //   raise driver event ""
    //     attributes { "driver_id": driver_id } 
    // }
  }
  
  rule delivery_check {
    select when shop driver_decision
    pre {
      order = event:attr("order")
      driver_id = event:attr("driver_id")
    }
    // TODO: for approve/reject 
    fired {
      event:send(
          { "eci": driver_id, "eid": "approved",
            "domain": "driver", "type": "approved",
            "attrs": {  }})
    } else {
      event:send(
          { "eci": driver_id, "eid": "rejected",
            "domain": "driver", "type": "rejected",
            "attrs": {   }})
    }
  }
  
  rule order_available {
    select when shop order_available
    pre {
    // Choose 1 driver from a pool of known drivers to send order to.
      subs = Subscriptions:established("Tx_role", "driver").klog("Subs: ")
      randNum = random:integer(subs.length()-1).klog("RAND NUM: ")
      driver = subs[randNum].klog("DRIVER: ")
      order = generateOrder(meta:host, time:now());
    }
    event:send(
          { "eci": driver{"Tx"}, "eid": "order_available",
            "domain": "driver", "type": "order_available",
            "attrs": { "order": order, "Rx": driver{"Rx"}  }})
    always{
      ent:orders := orders().put([order{"order_id"}], order);
      ent:order_num := order_count() + 1
    }
  }
  
  rule status_updated {
    // send customer update info
    select when shop status_updated
    pre {
      driver_id = event:attr("driver_id")
      order_id = event:attr("order_id")
      status = event:attr("status")
    }
    // update order: pick_up, enroute, completed
    
    // if status = "completed" then
    //   sendSMS & remove from order
  }
}
