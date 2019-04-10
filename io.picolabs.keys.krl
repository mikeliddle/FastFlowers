ruleset io.picolabs.keys {
  meta {
    key twilio {
      "account_sid": "AC750e968b5bc1cd5dba53022d05c7dede", 
      "auth_token" : "9d4a7a059152b83a28dc2c4c5732e6d4"
    }

    key google {
      "api_key": "AIzaSyC9I1YOXTvFUzG4i2JD26xPimgNyc9JrXs"
    }

    provides keys twilio to io.picolabs.twilio_v2
    provides keys google to Driver
  }
  global {
  }
}
