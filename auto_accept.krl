ruleset auto_accept {
    meta{
        use module io.picolabs.wrangler alias wrangler
    }
    
    rule auto_accept {
        select when wrangler inbound_pending_subscription_added
        fired {
            raise wrangler event "pending_subscription_approval"
            attributes event:attrs
        }
    }
}