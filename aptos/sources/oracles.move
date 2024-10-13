// Copyright (c) Usher Labs
// SPDX-License-Identifier: LGPL-2.1

// This module implements an oracle system for Verity.
// It allows users to create new requests for off-chain data,
// which are then fulfilled by designated oracles.
// The system manages pending requests and emits events
// for both new requests and fulfilled requests.
module verity::oracles {
    use aptos_framework::object;
    use std::signer;
    use std::vector;
    use std::string::{String};
    use std::option::{Self, Option};
    use std::event;
    use std::bcs;

    const RequestNotFoundError: u64 = 1001;
    const SignerNotOracleError: u64 = 1002;
    // const ProofNotValidError: u64 = 1003;
    const OnlyOwnerError: u64 = 1004;

    // Struct to represent HTTP request parameters
    // Designed to be imported by third-party contracts
    struct HTTPRequest has store, copy, drop {
        url: String,
        method: String,
        headers: String,
        body: String,
    }

    struct Request has key, store, copy, drop {
        params: HTTPRequest,
        pick: String, // An optional JQ string to pick the value from the response JSON data structure.
        oracle: address,
        response_status: u16,
        response: Option<String>
    }

    // Global params for the oracle system
    //:!>resource
    struct GlobalParams has key {
        owner: address,
    }
    //<:!:resource

    // -------- Events --------
    #[event]
    struct RequestAdded has drop, store {
        creator: address,
        params: HTTPRequest,
        pick: String, // An optional JQ string to pick the value from the response JSON data structure.
        oracle: address,
        notify: Option<vector<u8>>,
        request_id: address
    }

    #[event]
    struct Fulfilment has drop, store {
        request: Request,
    }
    // ------------------------

    fun init_module(account: &signer) {
        move_to(account, GlobalParams {
            owner: signer::address_of(account),
        });
    }

    // Only owner can set the verifier
    public entry fun set_owner(
        owner: &signer,
        new_owner: address
    ) acquires GlobalParams {
        let params = borrow_global_mut<GlobalParams>(@verity);
        assert!(params.owner == signer::address_of(owner), OnlyOwnerError);
        params.owner = new_owner;
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

    // Inspo from https://github.com/rooch-network/rooch/blob/65f436ba16b04e479125ac414cf5c6c876a8809d/frameworks/bitcoin-move/sources/types.move#L77
    public fun with_notify(
        notify_address: address,
        notify_function: vector<u8>
    ): Option<vector<u8>> {
        let res = vector::empty<u8>();
        vector::append(&mut res, bcs::to_bytes(&notify_address));
        vector::append(&mut res, b"::"); // delimiter
        vector::append(&mut res, notify_function);
        option::some(res)
    }

    public fun without_notify(): Option<vector<u8>> {
        option::none()
    }

    /// Creates a new oracle request for arbitrary API data.
    /// This function is intended to be called by third-party contracts
    /// to initiate off-chain data requests.
    public fun new_request(
        caller: &signer,
        params: HTTPRequest,
        pick: String,
        oracle: address,
        notify: Option<vector<u8>>
    ): address {
        // TODO: Ensure that the recipient has enough gas for the request.

        // Create new request object
        let caller_address = signer::address_of(caller);
        let constructor_ref = object::create_object(caller_address);
        let object_signer = object::generate_signer(&constructor_ref);

        // Set up the object by creating a request resource in it.
        move_to(&object_signer, Request {
            params,
            pick,
            oracle,
            response_status: 0,
            response: option::none(),
        });
        // Transfer ownership to oracle
        let request_object = object::object_from_constructor_ref<Request>(&constructor_ref);
        object::transfer(caller, request_object, oracle);

        let request_id = signer::address_of(&object_signer);

        // TODO: Move gas from recipient to module account

        // Emit event
        event::emit<RequestAdded>(RequestAdded {
            request_id,
            creator: caller_address,
            params,
            pick,
            oracle,
            notify,
        });

        request_id
    }

    /// Fulfils an existing oracle request with the provided result.
    /// This function is intended to be called by designated oracles
    /// to fulfill requests initiated by third-party contracts.
    public entry fun fulfil_request(
        caller: &signer,
        id: address,
        response_status: u16,
        result: String
        // proof: String
    ) acquires Request {
        let caller_address = signer::address_of(caller);
        assert!(exists<Request>(id), RequestNotFoundError);

        let request = borrow_global_mut<Request>(id);
        // Verify the signer matches the pending request's signer/oracle
        assert!(request.oracle == caller_address, SignerNotOracleError);

        // // Verify the data and proof
        // assert!(verify(result, proof), ProofNotValidError);

        // Fulfil the request
        request.response = option::some(result);
        request.response_status = response_status;

        // TODO: Move gas from module escrow to Oracle

        // Emit fulfil event
        event::emit<Fulfilment>(Fulfilment {
            request: *request,
        });
    }

    // // This is a Version 0 of the verifier.
    // public fun verify(
    //     data: String,
    //     proof: String
    // ): bool {
    //     // * Eventually this will be replaced with ECDSA signature verification of public key from MPC verifier network.
    //     true
    // }

    // ------------ HELPERS ------------
    #[view]
    public fun get_request_oracle(id: address): address acquires Request {
        let request = borrow_global<Request>(id);
        request.oracle
    }

    #[view]
    public fun get_request_pick(id: address): String acquires Request {
        let request = borrow_global<Request>(id);
        request.pick
    }

    #[view]
    public fun get_request_params_url(id: address): String acquires Request {
        let request = borrow_global<Request>(id);
        request.params.url
    }

    #[view]
    public fun get_request_params_method(id: address): String acquires Request {
        let request = borrow_global<Request>(id);
        request.params.method
    }

    #[view]
    public fun get_request_params_headers(id: address): String acquires Request {
        let request = borrow_global<Request>(id);
        request.params.headers
    }

    #[view]
    public fun get_request_params_body(id: address): String acquires Request {
        let request = borrow_global<Request>(id);
        request.params.body
    }

    #[view]
    public fun get_response(id: address): Option<String> acquires Request {
        let request = borrow_global<Request>(id);
        request.response
    }

    #[view]
    public fun get_response_status(id: address): u16 acquires Request {
        let request = borrow_global<Request>(id);
        request.response_status
    }
}

#[test_only]
module verity::test_oracles {
    use std::signer;
    use std::option::{Self};
    use std::string;
    use verity::oracles;

    #[test_only]
    // Test for creating a new request
    public fun create_oracle_request(caller: &signer, oracle: &signer): address {
        let url = string::utf8(b"https://api.example.com/data");
        let method = string::utf8(b"GET");
        let headers = string::utf8(b"Content-Type: application/json\nUser-Agent: MoveClient/1.0");
        let body = string::utf8(b"");

        let http_request = oracles::build_request(url, method, headers, body);

        let response_pick = string::utf8(b"");

        let oracle_address = signer::address_of(oracle);
        // let recipient = @0x46;

        let request_id = oracles::new_request(caller, http_request, response_pick, oracle_address, oracles::with_notify(@verity, b""));
        request_id
    }

    #[test_only]
    /// Test function to consume the FulfilRequestObject
    public fun fulfil_request(caller: &signer, id: address) {
        let result = string::utf8(b"Hello World");
        // let proof = string::utf8(b"");

        oracles::fulfil_request(caller, id, 200, result);
    }


    #[test(caller = @0xA1, oracle = @0xA2)]
    public fun test_view_functions(caller: &signer, oracle: &signer){
        let id = create_oracle_request(caller, oracle);
        // Test the Object

        assert!(oracles::get_request_oracle(id) == signer::address_of(oracle), 99951);
        assert!(oracles::get_request_params_url(id) == string::utf8(b"https://api.example.com/data"), 99952);
        assert!(oracles::get_request_params_method(id) == string::utf8(b"GET"), 99953);
        assert!(oracles::get_request_params_body(id) == string::utf8(b""), 99954);
        assert!(oracles::get_response_status(id) ==(0 as u16), 99955);
    }

    #[test(caller = @0xA1, oracle = @0xA2)]
    public fun test_consume_fulfil_request(caller: &signer, oracle: &signer){
        let id = create_oracle_request(caller, oracle);

        // * This test fulfil passes the oracle as the caller to the fulfil mechanism
        fulfil_request(oracle, id);

        assert!(oracles::get_response(id) == option::some(string::utf8(b"Hello World")), 99958);
        assert!(oracles::get_response_status(id) == (200 as u16), 99959);
    }
}