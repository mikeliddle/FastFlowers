ruleset io.picolabs.twilio_v2 {
  meta {
    use module io.picolabs.keys alias twilio
      // with account_sid = keys:twilio{"account_sid"}
      //     auth_token = keys:twilio{"auth_token"}
    provides
        send_sms,
        get_sms_logs,
        getContent
  }
 
  global {
    send_sms = defaction(to, from, message) {
      base_url = <<https://#{keys:twilio{"account_sid"}}:#{keys:twilio{"auth_token"}}@api.twilio.com/2010-04-01/Accounts/#{keys:twilio{"account_sid"}}/>>
      every {
       http:post(base_url + "Messages.json", form = {"From":from, "To":to, "Body":message});
       send_directive("Successfully sent message!");
      }
    }
    
    get_sms_logs = function(from, to, pageSize) {
      base_url = <<https://#{keys:twilio{"account_sid"}}:#{keys:twilio{"auth_token"}}@api.twilio.com/2010-04-01/Accounts/#{keys:twilio{"account_sid"}}/>>;
      json_from_url = http:get(base_url + "Messages.json", form = {"From":from, "To":to, "PageSize":pageSize}){"content"}.decode();
      // json_from_url = http:get(base_url + "Messages.json", form = {"page_size":page_size, "page":page}){"content"}.decode();
      // // http:post(base_url + "Messages.json", form = {"Page_size":page_size, "Page":page});
      json_from_url
    }
  }
}
