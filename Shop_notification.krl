ruleset Shop_notification {
  meta {
    use module io.picolabs.twilio_v2 alias twilio
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
    
    SMS_number = "3852509880"
    online_number = "17867888910"
  }
  
  rule send_notification {
    select when shop sendSMS
    pre {
      driver_id = event:attr("driver_id")
      order_id = event:attr("order_id")
      to = SMS_number
      from = online_number
      message = <<SHOP: Order #{order_ID} update!!!>>
    }
    twilio:send_sms(to, from, message);
  }
}
