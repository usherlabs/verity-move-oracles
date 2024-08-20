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
    use std::string::String;
    use moveos_std::table::{Self, Table};

    const RequestNotFoundError: u64 = 1001;
    const SignerNotOracleError: u64 = 1002;
    const ProofNotValidError: u64 = 1003;
    const OnlyOwnerError: u64 = 1004;

    // Struct to represent HTTP request parameters
    // Designed to be imported by third-party contracts
    struct HTTPRequest has store, copy, drop {
        url: String,
        method: String,
        headers: String,
        body: String,
    }

    struct Response has store, copy, drop{
        body: String,
    }

    struct Request has key, store {
        params: HTTPRequest,
        pick: String, // An optional JQ string to pick the value from the response JSON data structure.
        oracle: address
    }

    struct Fulfilments has key {
        requests: Table<address, vector<ObjectID>>, // Recipient -> Request IDs
        responses: Table<ObjectID, Response>, // Request ID -> Response
    }

    // Global params for the oracle system
    struct GlobalParams has key {
        owner: address,
    }

    // -------- Events --------
    struct RequestAdded has copy, drop {
        params: HTTPRequest,
        pick: String, // An optional JQ string to pick the value from the response JSON data structure.
        oracle: address,
        recipient: address,
    }

    struct Fulfilment has copy, drop {
        request_id: ObjectID,
        response: Response,
    }
    // ------------------------

    fun init() {
        let module_signer = signer::module_signer<Fulfilments>();
        let owner = tx_context::sender();

        account::move_resource_to(&module_signer, Fulfilments{
            requests: table::new<address, vector<ObjectID>>(),
            responses: table::new<ObjectID, Response>(),
        });

        account::move_resource_to(&module_signer, GlobalParams{
            owner,
        });
    }

    // Only owner can set the verifier
    public entry fun set_owner(
        owner: address
    ) {
        let owner = tx_context::sender();
        let params = account::borrow_mut_resource<GlobalParams>(@verity);
        assert!(params.owner == owner, OnlyOwnerError);
        params.owner = owner;
    }

    // Builds a request object from the provided parameters
    public fun build_request(
        url: String,
        method: String,
        headers: String,
        body: String
    ): HTTPRequest {
        HTTPRequest {
            url,
            method,
            headers,
            body,
        }
    }

    /// Creates a new oracle request for arbitrary API data.
    /// This function is intended to be called by third-party contracts
    /// to initiate off-chain data requests.
    public fun new_request(
        params: HTTPRequest,
        pick: String,
        oracle: address,
        recipient: address,
    ): ObjectID {
        // TODO: Ensure that there is a enough gas transferred for the request.

        // Create new request object
        let request = object::new(Request {
            params,
            pick,
            oracle,
        });
        let request_id = object::id(&request);
        object::transfer(request, recipient);

        // Store the pending request
        let fulfilments = account::borrow_mut_resource<Fulfilments>(@verity);
        let f_requests = table::borrow_mut(&mut fulfilments.requests, recipient);
        vector::push_back(f_requests, request_id);

        // Emit event
        event::emit(RequestAdded {
            params,
            pick,
            oracle,
            recipient,
        });

        request_id
    }

    /// Fulfils an existing oracle request with the provided result.
    /// This function is intended to be called by designated oracles
    /// to fulfill requests initiated by third-party contracts.
    public entry fun fulfil_request(
        id: ObjectID,
        result: String,
        proof: String
    ) {
        let signer_address = tx_context::sender();
        let fulfilments = account::borrow_mut_resource<Fulfilments>(@verity);

        assert!(object::exists_object_with_type<Request>(id), RequestNotFoundError);

        let request_ref = object::borrow_object<Request>(id);
        assert!(table::contains(&fulfilments.requests, object::owner(request_ref)), RequestNotFoundError);

        // Verify the signer matches the pending request's signer/oracle
        let request = object::borrow(request_ref);
        assert!(request.oracle == signer_address, SignerNotOracleError);

        // Verify the data and proof
        assert!(verify(result, proof), ProofNotValidError);

        // Create Fulfilment
        let response = Response {
            body: result,
        };
        table::add(&mut fulfilments.responses, id, response);

        // Emit fulfil event
        event::emit(Fulfilment {
            request_id: id,
            response,
        });
    }

    // This is a Version 0 of the verifier.
    public fun verify(
        data: String,
        proof: String
    ): bool {
        // * Eventually this will be replaced with ECDSA signature verification of public key from MPC verifier network.
        true
    }

    // public fun consume(): vector<(Object<Request>, Response)> {
    //     let recipient = tx_context::sender();
    //     let fulfilments = account::borrow_mut_resource<Fulfilments>(@oracles);
    //     let request_ids = table::borrow(&fulfilments.requests, recipient);

    //     // For each request, get the response
    //     let result = vector::empty<(Object<Request>, Response)>();
    //     let i = 0;
    //     while (i < vector::length(&request_ids)) {
    //         let request_id = vector::borrow(&request_ids, i);
    //         let request = object::borrow(request_id);
    //         let response = table::borrow(&fulfilments.responses, request_id);
    //         vector::push_back(&mut result, (request, response));
    //         i = i + 1;
    //     }

    //     // Then clean the fulfilments - on the next consumption it's only fresh requests.
    //     // ? Should be destroy the objects here too?
    //     table::remove(&mut fulfilments.requests, recipient);

    //     result
    // }
}

module verity::test_oracles {
    use std::vector;
    use std::string;
    use verity::oracles;
    use moveos_std::object::{ObjectID};

    // Test for creating a new request
    public fun create_oracle_request(): ObjectID {
        let url = string::utf8(b"https://api.example.com/data");
        let method = string::utf8(b"GET");
        let headers = string::utf8(b"Content-Type: application/json\nUser-Agent: MoveClient/1.0");
        let body = string::utf8(b"");

        let http_request = oracles::build_request(url, method, headers, body);

        let response_pick = string::utf8(b"");
        let oracle = @0x45;
        let recipient = @0x46;

        oracles::new_request(http_request, response_pick, oracle, recipient)
    }

    /// Test function to consume the FulfilRequestObject
    public fun fulfil_request(id: ObjectID) {
        let result = string::utf8(b"");
        let proof = string::utf8(b"");

        oracles::fulfil_request(id, result, proof);
    }

    // // Test to demonstrate how a third-party contract can use the fulfil request
    // public fun consume(): vector<(Request, Response)> {
    //     let fulfilments = oracles::consume();

    //     result
    // }

    #[test]
    public fun test_consume_fulfil_request() {
        let id = create_oracle_request();
        fulfil_request(id);

        // let result = consume();
        // assert!(vector::length(&result) == 1, 99991); // "Expected 1 request to be consumed"

        // let first_result = vector::borrow(&result, 0);
        // let request = first_result.0;
        // let response = first_result.1;

        // assert!(request.request_params.url == b"https://api.example.com/data", 99992); // "Expected URL to match"

        //   // Test Response
        // assert!(vector::is_empty(&response.body), 99993); // "Expected response body to be empty"
    }
}