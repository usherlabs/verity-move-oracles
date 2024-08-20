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
    use moveos_std::object::{Self, Object, ObjectID};
    use std::vector;
    use std::hash;
    use rooch_framework::simple_rng;
    use moveos_std::table::{Self, Table};

    const RequestNotFoundError: u64 = 1001;
    const SignerNotOracleError: u64 = 1002;
    const ProofNotValidError: u64 = 1003;
    const OnlyOwnerError: u64 = 1004;

    // Struct to represent HTTP request parameters
    // Designed to be imported by third-party contracts
    public struct HTTPRequest {
        url: vector<u8>,
        method: vector<u8>,
        headers: vector<u8>,
        body: vector<u8>,
    }

    struct Request has key, store {
        // // id: u64, // ID is generated using a SHA3-256 hash of the request parameters, response pick, oracle address, and recipient address.
        // // Generated ID is used to correlate the request with the fulfilled response.
        request_params: HTTPRequest,
        response_pick: vector<u8>, // An optional JQ string to pick the value from the response JSON data structure.
        oracle: address
    }

    struct Response {
        body: vector<u8>,
    }

    struct Fulfilments has key {
        requests: Table<address, vector<ObjectID>>, // Recipient -> Request IDs
        responses: Table<ObjectID, Response>, // Request ID -> Response
    }

    // Global params for the oracle system
    struct GlobalParams has key {
        // Refers to the verifier module
        verifier: address,
        owner: address,
    }

    struct RequestAdded has copy, drop {
        request: Object<Request>,
    }

    struct Fulfilment has copy, drop {
        request_id: ObjectID,
        response: Response,
    }

    fun init() {
        let module_signer = signer::module_signer<Fulfilments>();
        let owner = tx_context::sender();

        account::move_resource_to(&module_signer, Fulfilments{
            requests: table::new<address, vector<ObjectID>>(),
            responses: table::new<ObjectID, Response>(),
        });

        account::move_resource_to(&module_signer, GlobalParams{
            verifier: signer::from_address(@verifierstub),
            owner,
        });
    }

    // Only owner can set the verifier
    public entry fun set_verifier(
        verifier: address
    ) {
        let owner = tx_context::sender();
        let params = account::borrow_mut_resource<GlobalParams>(@oracles);
        assert!(params.owner == owner, OnlyOwnerError);
        // ? Quite sure this is how to version the verifier
        params.verifier = verifier;
    }

    /// Creates a new oracle request for arbitrary API data.
    /// This function is intended to be called by third-party contracts
    /// to initiate off-chain data requests.
    public fun new_request(
        request_params: HTTPRequest,
        response_pick: vector<u8>,
        oracle: address,
        recipient: address,
    ): u64 {
        // TODO: Ensure that there is a enough gas transferred for the request.

        // Create new request object
        let request = object::new(Request {
            request_params,
            response_pick,
            oracle,
        });
        object::transfer(request, recipient);
        let request_id = object::id(request);

        // Store the pending request
        let fulfilments = account::borrow_mut_resource<Fulfilments>(@oracles);
        let f_requests = table::borrow_mut(&mut fulfilments.requests, recipient);
        vector::push_back(&mut f_requests, request_id);

        // Emit event
        event::emit_event<RequestAdded>(RequestAdded {
            request,
        });

        id
    }

    /// Fulfils an existing oracle request with the provided result.
    /// This function is intended to be called by designated oracles
    /// to fulfill requests initiated by third-party contracts.
    public entry fun fulfil_request(
        id: ObjectID,
        result: vector<u8>,
        proof: vector<u8>
    ) {
        let signer_address = tx_context::sender();
        let fulfilments = account::borrow_mut_resource<Fulfilments>(@oracles);

        assert!(object::exists_object(id), RequestNotFoundError);

        let request = object::borrow(id);
        assert!(table::contains(&fulfilments.requests, object::owner(request)), RequestNotFoundError);

        // Verify the signer matches the pending request's signer/oracle
        assert!(request.oracle == signer_address, SignerNotOracleError);

        // Verify the data and proof
        // let verifier_address = account::borrow_resource<GlobalParams>(@oracles).verifier;
        // let verifier_module = &verifier_address;
        // assert!(verifier_module::verify(result, proof), ProofNotValidError);

        // Create Fulfilment
        let response = Response {
            body: result,
        };
        table::insert(&mut fulfilments.responses, id, response);

        // Emit fulfil event
        event::emit_event<Fulfilment>(Fulfilment {
            request_id: id,
            response,
        });
    }

    public fun consume(): vector<(Request, Response)> {
        let recipient = tx_context::sender();
        let fulfilments = account::borrow_resource<Fulfilments>(@oracles);
        let request_ids = table::borrow(&fulfilments.requests, recipient);

        // For each request, get the response
        let mut result = vector::empty<(Request, Response)>();
        let mut i = 0;
        while (i < vector::length(&request_ids)) {
            let request_id = vector::borrow(&request_ids, i);
            let request = object::borrow(request_id);
            let response = table::borrow(&fulfilments.responses, request_id);
            vector::push_back(&mut result, (request, response));
            i = i + 1;
        }

        // Then clean the fulfilments - on the next consumption it's only fresh requests.
        // ? Should be destroy the objects here too?
        table::remove(&mut fulfilments.requests, recipient);

        result
    }
}

module verity::verifierstub {
    public fun verify(
        data: vector<u8>,
        proof: vector<u8>
    ): bool {
        // * Eventually this will be replaced with verification of a public key from decentralised verifier network.
        true
    }
}

module verity::test_oracles {
    use moveos_std::account;
    use moveos_std::event;
    use moveos_std::tx_context;
    use std::vector;
    use verity::oracles;
    use verity::oracles::{HTTPRequest, FulfilRequestObject};

    // Test for creating a new request
    public fun create_oracle_request(): u64 {
        let url = vector::from_utf8(b"https://api.example.com/data");
        let method = vector::from_utf8(b"GET");
        let headers = vector::from_utf8(b"Content-Type: application/json\nUser-Agent: MoveClient/1.0");
        let body = vector::empty<u8>();

        let http_request = HTTPRequest {
            url,
            method,
            headers,
            body,
        };

        let request_params = bcs::to_bytes(&http_request);
        let response_pick = vector::empty<u8>();
        let oracle = @0x1;
        let recipient = @0x2;

        oracles::new_request(request_params, response_pick, oracle, recipient)
    }

    /// Test function to consume the FulfilRequestObject
    public fun fulfil_request(id: u64) {
        let result = vector::empty<u8>();
        let proof = vector::empty<u8>();

        oracles::fulfil_request(id, result, proof);
    }

    // Test to demonstrate how a third-party contract can use the fulfil request
    public fun consume(): vector<(Request, Response)> {
        let fulfilments = oracles::consume();

        result
    }

    #[test]
    public fun test_consume_fulfil_request() {
        let id = create_oracle_request();
        fulfil_request(id);

        let result = consume();
        assert!(vector::length(&result) == 1, 99991); // "Expected 1 request to be consumed"

        let first_result = vector::borrow(&result, 0);
        let request = first_result.0;
        let response = first_result.1;

        assert!(request.request_params.url == b"https://api.example.com/data", 99992); // "Expected URL to match"

          // Test Response
        assert!(vector::is_empty(&response.body), 99993); // "Expected response body to be empty"
    }
}