// Copyright (c) Usher Labs
// SPDX-License-Identifier: LGPL-2.1

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
    use moveos_std::address;
    use moveos_std::object::{Self, ObjectID};
    use std::vector;
    use std::string::String;
    use std::option::{Self, Option};

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
        response_status: u8,
        response: Option<String>
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
        notify: Option<vector<u8>>,
        request_id: ObjectID
    }

    struct Fulfilment has copy, drop {
        request: Request,
    }
    // ------------------------

    fun init() {
        let module_signer = signer::module_signer<GlobalParams>();
        let owner = tx_context::sender();

        account::move_resource_to(&module_signer, GlobalParams {
            owner,
        });
    }

    // Only owner can set the verifier
    // TODO: Move this out into it's own ownable module.
    public entry fun set_owner(
        new_owner: address
    ) {
        let owner = tx_context::sender();
        let params = account::borrow_mut_resource<GlobalParams>(@verity);
        assert!(params.owner == owner, OnlyOwnerError);
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
        vector::append(&mut res, address::to_bytes(&notify_address));
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
        params: HTTPRequest,
        pick: String,
        oracle: address,
        notify: Option<vector<u8>>
    ): ObjectID {
        // let recipient = tx_context::sender();

        // TODO: Ensure that the recipient has enough gas for the request.

        // Create new request object
        let request = object::new(Request {
            params,
            pick,
            oracle,
            response_status: 0,
            response: option::none(),
        });
        let request_id = object::id(&request);
        object::transfer(request, oracle); // transfer to oracle to ensure permission

        // TODO: Move gas from recipient to module account

        // Emit event
        event::emit(RequestAdded {
            params,
            pick,
            oracle,
            notify,
            request_id
        });

        request_id
    }

    /// Fulfils an existing oracle request with the provided result.
    /// This function is intended to be called by designated oracles
    /// to fulfill requests initiated by third-party contracts.
    public entry fun fulfil_request(
        sender: &signer,
        id: ObjectID,
        response_status: u8,
        result: String
        // proof: String
    ) {
        let signer_address = tx_context::sender();
        assert!(object::exists_object_with_type<Request>(id), RequestNotFoundError);

        let request_ref = object::borrow_mut_object<Request>(sender, id);
        let request = object::borrow_mut(request_ref);
        // Verify the signer matches the pending request's signer/oracle
        assert!(request.oracle == signer_address, SignerNotOracleError);

        // // Verify the data and proof
        // assert!(verify(result, proof), ProofNotValidError);

        // Fulfil the request
        request.response = option::some(result);
        request.response_status = response_status;

        // TODO: Move gas from module escrow to Oracle

        // Emit fulfil event
        event::emit(Fulfilment {
            request: *request,
        });
    }

    #[test_only]
    public entry fun test_fulfil_request(
        sender: &signer,
        id: ObjectID,
        response_status: u8,
        result: String
        // proof: String
    ) {
        assert!(object::exists_object_with_type<Request>(id), RequestNotFoundError);

        let request_ref = object::borrow_mut_object<Request>(sender, id);
        let request = object::borrow_mut(request_ref);

        // // Verify the data and proof
        // assert!(verify(result, proof), ProofNotValidError);

        // Fulfil the request
        request.response = option::some(result);
        request.response_status = response_status;

        // TODO: Move gas from module escrow to Oracle

        // Emit fulfil event
        event::emit(Fulfilment {
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
    fun borrow_request(id: &ObjectID): &Request {
        let ref = object::borrow_object<Request>(*id);
        object::borrow(ref)
    }

    #[view]
    public fun get_request_oracle(id: &ObjectID): address {
        let request = borrow_request(id);
        request.oracle
    }

    #[view]
    public fun get_request_pick(id: &ObjectID): String {
        let request = borrow_request(id);
        request.pick
    }

    #[view]
    public fun get_request_params_url(id: &ObjectID): String {
        let request = borrow_request(id);
        request.params.url
    }

    #[view]
    public fun get_request_params_method(id: &ObjectID): String {
        let request = borrow_request(id);
        request.params.method
    }

    public fun get_request_params_headers(id: &ObjectID): String {
        let request = borrow_request(id);
        request.params.headers
    }

    #[view]
    public fun get_request_params_body(id: &ObjectID): String {
        let request = borrow_request(id);
        request.params.body
    }

    #[view]
    public fun get_response(id: &ObjectID): Option<String> {
        let request = borrow_request(id);
        request.response
    }

    #[view]
    public fun get_response_status(id: &ObjectID): u8 {
        let request = borrow_request(id);
        request.response_status
    }
}

#[test_only]
module verity::test_oracles {
    use std::string;
    use moveos_std::signer;
    use std::option::{Self};
    use verity::oracles::{Self,Request};
    use moveos_std::object::{Self,ObjectID};


    struct Test has key {
    }

    #[test_only]
    // Test for creating a new request
    public fun create_oracle_request(): ObjectID {
        let url = string::utf8(b"https://api.example.com/data");
        let method = string::utf8(b"GET");
        let headers = string::utf8(b"Content-Type: application/json\nUser-Agent: MoveClient/1.0");
        let body = string::utf8(b"");

        let http_request = oracles::build_request(url, method, headers, body);

        let response_pick = string::utf8(b"");
        let sig = signer::module_signer<Test>();

        let oracle = signer::address_of(&sig);
        // let recipient = @0x46;

        let request_id =oracles::new_request(http_request, response_pick, oracle, oracles::with_notify(@verity,b""));
        request_id
    }

    #[test_only]
    /// Test function to consume the FulfilRequestObject
    public fun fulfil_request(id: ObjectID) {
        let result = string::utf8(b"Hello World");
        // let proof = string::utf8(b"");

        let sig = signer::module_signer<Test>();
        oracles::test_fulfil_request(&sig, id, 200, result);
    }


    #[test]
    public fun test_view_functions(){
        let id = create_oracle_request();
        let sig = signer::module_signer<Test>();
        // Test the Object

        assert!(oracles::get_request_oracle(&id) == signer::address_of(&sig), 99951);
        assert!(oracles::get_request_params_url(&id) == string::utf8(b"https://api.example.com/data"), 99952);
        assert!(oracles::get_request_params_method(&id) == string::utf8(b"GET"), 99953);
        assert!(oracles::get_request_params_body(&id) == string::utf8(b""), 99954);
        assert!(oracles::get_response_status(&id) ==(0 as u8), 99955);
    }

    #[test]
    public fun test_consume_fulfil_request() {

        let id = create_oracle_request();
        let sig = signer::module_signer<Test>();

        let _data= object::borrow_object<Request>(id);
        let recipient = object::owner(_data);
        assert!(recipient == signer::address_of(&sig), 99955);

        fulfil_request(id);

        assert!(oracles::get_response(&id) == option::some(string::utf8(b"Hello World")), 99958);
        assert!(oracles::get_response_status(&id) == (200 as u8), 99959);
    }
}