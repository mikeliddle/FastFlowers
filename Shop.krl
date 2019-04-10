ruleset Shop {
  meta {
    use module io.picolabs.wrangler alias wrangler
    use module io.picolabs.subscription alias Subscriptions
    shares __testing
  }
  global {
    __testing = { "queries": [ { "name": "__testing" } ],
                  "events": [ { "domain": "mischief", "type": "identity"},
                              { "domain": "mischief", "type": "hat_lifted"} ] }
    
    rank_threshold = 2
    auto_assign = true
    // location
    
    drivers = function() {
      ent:drivers.defaultsTo([])
    }
    
    orders = function() {
      ent:reports.defaultsTo([])
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
  
  rule order_ready {
    select when shop order_ready
    pre {
      order_id = event:attr("order_id")
    }
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
