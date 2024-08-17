// Copyright (c) Usher Labs
// SPDX-License-Identifier: Apache-2.0

// This module implements an oracle system for Verity.
// It allows users to create new requests for off-chain data,
// which are then fulfilled by designated oracles.
// The system manages pending requests and emits events
// for both new requests and fulfilled requests.
module verity::oracles {
    use moveos_std::event;
    use moveos_std::tx_context;
    use moveos_std::signer;
    use moveos_std::account;
    use moveos_std::object::{Self, Object};
    use std::vector;
    use std::hash;
    use rooch_framework::simple_rng;

    struct PendingRequest {
        id: u64, // ID is generated using a SHA3-256 hash of the request parameters, response pick, oracle address, and recipient address.
        // Generated ID is used to correlate the request with the fulfilled response.
        request_params: vector<u8>,
        response_pick: vector<u8>, // An optional JQ string to pick the value from the response JSON data structure.
        oracle: address,
        recipient: address,
    }

    struct Pending has key {
        requests: vector<PendingRequest>,
    }

    // Global params for the oracle system
    struct GlobalParams has key {
        // Refers to the verifier module
        verifier: address,
        owner: address,
    }

    struct FulfilRequestObject has key {
        result: vector<u8>,
    }

    struct PendingRequestEvent has copy, drop {
        pending_request: PendingRequest,
    }

    struct FulfilRequestEvent has copy, drop {
        fulfil_request: FulfilRequestObject,
    }

    fun init() {
        let module_signer = signer::module_signer<Pending>();
        let owner = tx_context::sender();

        account::move_resource_to(&module_signer, Pending{
            requests: vector::empty<PendingRequest>(),
        });
        account::move_resource_to(&module_signer, GlobalParams{
            verifier: signer::from_address(@verifierstub),
            owner,
        });
    }

    public entry fun set_verifier(
        verifier: address
    ) {
        let owner = tx_context::sender();
        let params = account::borrow_mut_resource<GlobalParams>(@oracles);
        assert!(params.owner == owner, 1004); // TODO: Create a const for Custom error code if owner is not the owner
        // TODO: Determine how this plays out if this verifier is a third-party verifier.
        params.verifier = verifier;
    }

    /// Creates a new oracle request for arbitrary API data.
    /// This function is intended to be called by third-party contracts
    /// to initiate off-chain data requests.
    public fun new_request(
        request_params: vector<u8>,
        response_pick: vector<u8>,
        oracle: address,
        recipient: address
    ) {
        let bytes = vector::concat(request_params, vector::concat(response_pick, vector::concat(vector::from_address(oracle), vector::from_address(recipient))));
        let seed = hash::sha3_256(bytes);
        let id = simple_rng::bytes_to_u64(seed);
        let pending_request = PendingRequest {
            id,
            request_params,
            response_pick,
            oracle,
            recipient,
        };
        // Store the pending request
        let pending = account::borrow_mut_resource<Pending>(@oracles);
        vector::push_back(&mut pending.requests, pending_request);
        // Emit event
        event::emit_event<PendingRequestEvent>(PendingRequestEvent {
            pending_request,
        });
    }

    /// Fulfils an existing oracle request with the provided result.
    /// This function is intended to be called by designated oracles
    /// to fulfill requests initiated by third-party contracts.
    public entry fun fulfil_request(
        id: u64,
        result: vector<u8>,
        proof: vector<u8>
    ) {
        let signer_address = tx_context::sender();
        let pending = account::borrow_mut_resource<Pending>(@oracles);

        // Iterate over pending.requests to find the matching request
        let mut found = false;
        let mut i = 0;
        while (i < vector::length(&pending.requests)) {
            let request = vector::borrow(&pending.requests, i);
            if (request.id == id) {
                found = true;
                break;
            }
            i = i + 1;
        }

        assert!(found, 1001); // TODO: Create a const for Custom error code if request is not found

        // Pending request ID is found
        let pending_request = vector::borrow(&pending.requests, i);
        // Verify the signer matches the pending request's signer/oracle
        assert!(pending_request.oracle == signer_address, 1002); // TODO: Create a const for Custom error code if signer is not the oracle

        // Verify the data and proof
        let verifier_address = account::borrow_resource<GlobalParams>(@oracles).verifier;
        let verifier_module = &verifier_address;
        assert!(verifier_module::verify(result, proof), 1003); // TODO: Create a const for Custom error code if proof is not valid

        // Create FulfilRequestObject and move to the recipient
        let fulfil_request = object::new(FulfilRequestObject {
            result,
        });
        object::transfer(fulfil_request, pending_request.recipient);

        // Add transfer permission that the FulfilRequestObject can be only consumed if the tx signer is the recipient.

        // Emit fulfil event
        Event::emit_event(&FulfilRequestEvent {
            fulfil_request,
        });
    }

    // External verifier module reference (implementation depends on module management strategy)
    // Owner can update the reference
}

module verity::verifierstub {
    public fun verify(
        data: vector<u8>,
        proof: vector<u8>
    ): bool {
        // ? Eventually this will be replaced with verification of a public key from decentralised verifier network.
        true
    }
}

module verity::test_oracles {
    use moveos_std::account;
    use moveos_std::event;
    use moveos_std::tx_context;
    use std::vector;
    use verity::oracles;
    use verity::oracles::FulfilRequestObject;

    /// Test function to consume the FulfilRequestObject
    public fun consume_fulfil_request() {
        // Simulate the creation of a fulfil request
        let request_params = vector::empty<u8>();
        let response_pick = vector::empty<u8>();
        let oracle = @0x1;
        let recipient = tx_context::sender();

        // Create a new request
        oracles::new_request(request_params, response_pick, oracle, recipient);

        // Simulate fulfilling the request
        let id = 1; // Assuming the ID is 1 for simplicity
        let result = vector::empty<u8>();
        let proof = vector::empty<u8>();

        oracles::fulfil_request(id, result, proof);

        // Consume the FulfilRequestObject
        let fulfil_request = account::move_resource_from<FulfilRequestObject>(&recipient);
        assert!(vector::is_empty(&fulfil_request.result), 1001); // Check if the result is as expected

        // Drop the FulfilRequestObject
        account::destroy_resource(fulfil_request);
    }

    #[test]
    public fun test_consume_fulfil_request() {
        consume_fulfil_request();
    }
}