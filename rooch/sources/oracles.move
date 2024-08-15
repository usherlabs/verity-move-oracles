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
        let signer = signer::module_signer<Pending>();
        let owner = tx_context::sender();

        account::move_resource_to(&signer, Pending{
            requests: vector::empty<PendingRequest>(),
        });
        account::move_resource_to(&signer, GlobalParams{
            verifier: signer::from_address(@verifierstub),
            owner,
        });
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
        let verifier = account::borrow_resource<GlobalParams>(@oracles).verifier;
        assert!(verifier::verify(result, proof), 1003); // TODO: Create a const for Custom error code if proof is not valid


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

module verity::verifierstub {
    public fun verify(
        data: vector<u8>,
        proof: vector<u8>
    ): bool {
        // ? Eventually this will be replaced with verification of a public key from decentralised verifier network.
        true
    }
}