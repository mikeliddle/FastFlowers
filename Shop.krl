ruleset Shop {
  meta {
    use module io.picolabs.wrangler alias wrangler
    use module io.picolabs.subscription alias Subscriptions
    use module io.picolabs.twilio_v2 alias twilio
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
    
    SMS_number = "3852509880"
    online_number = "17867888910"

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
      orders(){id.klog("order_id")}
    }
    
    // collect = function(driver) {
      
    // }
    
    // notify = function() {
    //   // not sure if we want this or just need Shop_status ruleset
    // }
    
    generateOrder = function( shop_host, timestamp ) {
      order_id = meta:eci + ":" + order_count().as("String");
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
      order = getOrder(order_id).klog("order")
    }

    if order{"status"} == "ready" then
      send_directive("order still available.")
      
    fired {
      // check request & approve/reject
      raise shop event "driver_decision" attributes event:attrs 
    }
  }
  
  rule delivery_check {
    select when shop driver_decision
    pre {
      order_id = event:attr("order_id")
      order = getOrder(order_id)
      driver_id = event:attr("driver_id")
      driver_rank = event:attr("driver_rank")
    }
    
    if driver_rank < ent:rank_threshold then
      event:send(
          { "eci": driver_id, 
            "eid": "rejected",
            "domain": "driver", 
            "type": "rejected",
            "attrs": { }})
     
    notfired {
      raise shop event "driver_eligible" attributes event:attrs
    }
  }
  
  rule collect_driver {
    select when shop driver_eligible where ent:auto_assign.defaultsTo(true) == false
    
    pre { 
      order_id = event:attr("order_id")
      order = getOrder(order_id)
      driver_id = event:attr("driver_id")
      order_group = ent:waiting_orders{order_id}.defaultsTo({}).put(driver_id, driver_id)
    }
    
    send_directive("adding driver to order collection")
    
    fired {
      ent:waiting_orders := ent:waiting_orders.defaultsTo({}).set(order_id, order_group)
    }
  }
  
  rule auto_assign_driver {
    select when shop driver_eligible where ent:auto_assign.defaultsTo(true)
    
    pre { 
      order_id = event:attr("order_id")
      order = getOrder(order_id)
      driver_id = event:attr("driver_id")
    }
    
    event:send(
          { "eci": driver_id, 
            "eid": "approved",
            "domain": "driver", 
            "type": "approved",
            "attrs": { 
              "order": order
            }})
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

      to = SMS_number
      from = online_number
      message = <<SHOP: Order #{order_ID}, update: #{status}>>
    }

    if status == "completed" then
      twilio:send_sms(to, from, message);

    always {
      ent:orders{[order_id, "status"]} := status
    }

  }
}
