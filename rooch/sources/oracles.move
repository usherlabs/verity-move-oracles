module Oracle {
    use 0x1::Signer;
    use 0x1::Event;
    use 0x1::Address;

    struct PendingRequest has key {
        request_params: vector<u8>,
        response_pick: vector<u8>, // An optional JQ string to pick the value from the response JSON data structure.
        oracle: address,
        recipient: address,
    }

    struct Pending {
        pending_requests: vector<PendingRequest>,
    }

    struct FulfilRequestObject has key {
        result: vector<u8>,
    }

    struct PendingRequestEvent has copy, drop, store {
        pending_request: PendingRequest,
    }

    struct FulfilRequestEvent has copy, drop, store {
        fulfil_request: FulfilRequestObject,
    }

    public entry fun new_request(
        account: &signer,
        request_params: vector<u8>,
        response_pick: vector<u8>,
        oracle: address,
        recipient: address
    ) {
        let signer_address = Signer::address_of(oracle);
        let pending_request = PendingRequest {
            request_params,
            response_pick,
            oracle: Signer::address_of(oracle),
            recipient: Signer::address_of(recipient),
        };
        // Store the pending request (implementation depends on storage strategy)
        let pending = borrow_global_mut<Pending>(signer_address);
        vector::push_back(&mut pending.pending_requests, pending_request);
        // Emit event
        Event::emit_event(&PendingRequestEvent {
            pending_request,
        });
    }

    public fun fulfil_request(
        account: &signer,
        id: u64,
        result: vector<u8>
    ) {
        let signer_address = Signer::address_of(account);
        // Verify the signer matches the pending request's signer
        // (implementation depends on storage strategy)
        // Emit fulfil event
        Event::emit_event(&FulfilRequestEvent {
            id,
            result,
        });
    }

    // External verifier module reference (implementation depends on module management strategy)
    // Owner can update the reference
}
