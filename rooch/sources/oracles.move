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
    use moveos_std::object::{Self, ObjectID, Object};
    use std::vector;
    use rooch_framework::coin::{Self, Coin};
    use rooch_framework::gas_coin::RGas;
    use rooch_framework::account_coin_store;
    use rooch_framework::coin_store::{Self, CoinStore};
    use std::string::{Self,String};
    use std::option::{Self, Option};
    use moveos_std::simple_map::{Self, SimpleMap};

    #[test_only]
    use rooch_framework::genesis;
    use verity::registry::{Self as OracleSupport};


    const MIN_GAS_REQUIRED: u64 = 1000000000000000000;
    const RequestNotFoundError: u64 = 1001;
    const SignerNotOracleError: u64 = 1002;
    // const ProofNotValidError: u64 = 1003;
    const OnlyOwnerError: u64 = 1004;
    const NotEnoughGasError: u64 = 1005;
    const OracleSupportError: u64 = 1006;
    const DoubleFulfillmentError: u64= 1007;



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
        response: Option<String>,
        account_to_credit: address,
        amount: u256
    }

    // Global params for the oracle system
    struct GlobalParams has key {
        owner: address,
        treasury: Object<CoinStore<RGas>>,
        balances: SimpleMap<address, u256>,
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
        let treasury_obj = coin_store::create_coin_store<RGas>();


        account::move_resource_to(&module_signer, GlobalParams {
            owner,
            treasury: treasury_obj,
            balances: simple_map::new(),
        });
    }



    #[test_only]
    public fun init_for_test(){
        genesis::init_for_test();
        OracleSupport::init_for_test();
        init();
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

    fun create_request(
        params: HTTPRequest,
        pick: String,
        oracle: address,
        notify: Option<vector<u8>>,
        amount: u256
    ): ObjectID{
        // Create new request object
        let request = object::new(Request {
            params,
            pick,
            oracle,
            response_status: 0, 
            response: option::none(),
            account_to_credit: tx_context::sender(),
            amount,
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

        return request_id
    }

    /// Creates a new oracle request for arbitrary API data.
    /// This function is intended to be called by third-party contracts
    /// to initiate off-chain data requests.
    public fun new_request_with_payment(
        params: HTTPRequest,
        pick: String,
        oracle: address,
        notify: Option<vector<u8>>,
        payment: Coin<RGas>
    ): ObjectID {

        let sent_coin =  coin::value(&payment);
        // 1024 could be changed to the max string length allowed on Move
        let option_min_amount = OracleSupport::estimated_cost(oracle ,params.url, string::length(&params.body), 1024);
        assert!(option::is_some(&option_min_amount), OracleSupportError);
        let min_amount= option::destroy_some(option_min_amount);

        assert!(sent_coin >= min_amount, NotEnoughGasError);
        let global_param = account::borrow_mut_resource<GlobalParams>(@verity);
        coin_store::deposit(&mut global_param.treasury, payment);

        return create_request(
            params,
            pick,
            oracle,
            notify,
            min_amount
        )
    }

    public fun new_request(
        params: HTTPRequest,
        pick: String,
        oracle: address,
        notify: Option<vector<u8>>,
    ): ObjectID {

        let sender= tx_context::sender();
        let account_balance =  get_user_balance(sender);
        // 1024 could be changed to the max string length allowed on Move
        let option_min_amount = OracleSupport::estimated_cost(oracle ,params.url, string::length(&params.body), 1024);
        assert!(option::is_some(&option_min_amount), OracleSupportError);
        let min_amount= option::destroy_some(option_min_amount);

        assert!(account_balance >= min_amount, NotEnoughGasError);
        let global_params = account::borrow_mut_resource<GlobalParams>(@verity);
        let balance = simple_map::borrow_mut(&mut global_params.balances, &sender);
        *balance = *balance-min_amount;

        return create_request(
            params,
            pick,
            oracle,
            notify,
            min_amount
        )
    }



    public entry fun deposit_to_escrow(from: &signer, amount:u256){
        let global_params = account::borrow_mut_resource<GlobalParams>(@verity);
        let sender = signer::address_of(from);
        

        let deposit = account_coin_store::withdraw<RGas>(from, amount);
        coin_store::deposit(&mut global_params.treasury, deposit);

        if (!simple_map::contains_key(&global_params.balances, &sender)) {
            simple_map::add(&mut global_params.balances, sender, amount);
        } else{
            let balance = simple_map::borrow_mut(&mut global_params.balances, &sender);
            *balance = *balance+amount;
        };

    }

    // TODO: withdraw command for User

    public entry fun fulfil_request(
        caller: &signer,
        id: ObjectID,
        response_status: u16,
        result: String
    ) {
        let caller_address = signer::address_of(caller);
        assert!(object::exists_object_with_type<Request>(id), RequestNotFoundError);

        let request_ref = object::borrow_mut_object<Request>(caller, id);
        let request = object::borrow_mut(request_ref);
        // Verify the signer matches the pending request's signer/oracle
        assert!(request.oracle == caller_address, SignerNotOracleError);

        // Prevent double fulfillment
        assert!(request.response_status == 0 || option::is_none(&request.response), DoubleFulfillmentError);


        // // Verify the data and proofsin
        // assert!(verify(result, proof), ProofNotValidError);

        // Fulfil the request
        request.response = option::some(result);
        request.response_status = response_status;

        let option_fulfillment_cost= OracleSupport::estimated_cost(request.oracle ,request.params.url, string::length(&request.params.body), string::length(&result));
        assert!(option::is_some(&option_fulfillment_cost), OracleSupportError);
        let fulfillment_cost= option::destroy_some(option_fulfillment_cost);

        // send token to orchestrator wallet
        let global_params = account::borrow_mut_resource<GlobalParams>(@verity);
        let payment= coin_store::withdraw(&mut global_params.treasury, fulfillment_cost);

        account_coin_store::deposit(caller_address, payment);

        // add extra to balance if any exists 
        if (request.amount > fulfillment_cost &&(request.amount - fulfillment_cost)>0){
            if (!simple_map::contains_key(&global_params.balances, &request.account_to_credit)) {
                simple_map::add(&mut global_params.balances, request.account_to_credit,  request.amount - fulfillment_cost );
            } else{
                let balance = simple_map::borrow_mut(&mut global_params.balances, &request.account_to_credit);
                *balance = *balance+ request.amount - fulfillment_cost ;
            };
        };

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

    #[view]
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
    public fun get_response_status(id: &ObjectID): u16 {
        let request = borrow_request(id);
        request.response_status
    }

    #[view]
    public fun get_user_balance(user: address): u256 {
        let global_params = account::borrow_resource<GlobalParams>(@verity);

        if (simple_map::contains_key(&global_params.balances, &user)) {
            *simple_map::borrow(&global_params.balances, &user)
        } else {
            0
        }
    }
}

#[test_only]
module verity::test_oracles {
    use std::string;
    use moveos_std::signer;
    // use std::option;
    use verity::oracles;
    use moveos_std::object::ObjectID;
    use rooch_framework::gas_coin;

    struct Test has key {
    }

    #[test_only]
    // Test for creating a new request
    public fun create_oracle_request(): ObjectID {
        oracles::init_for_test();
        let sig = signer::module_signer<Test>();
        let oracle = signer::address_of(&sig);
        let url = string::utf8(b"https://api.example.com/data");
        let method = string::utf8(b"GET");
        let headers = string::utf8(b"Content-Type: application/json\nUser-Agent: MoveClient/1.0");
        let body = string::utf8(b"");

        let http_request = oracles::build_request(url, method, headers, body);

        let response_pick = string::utf8(b"");

        // let recipient = @0x46;
        let payment = gas_coin::mint_for_test(1000u256);

        let request_id = oracles::new_request_with_payment(
            http_request, 
            response_pick, 
            oracle, 
            oracles::with_notify(@verity,b""),
            payment
        );
        request_id
    }

    #[test_only]
    /// Test function to consume the FulfilRequestObject
    public fun fulfil_request(id: ObjectID) {
        oracles::init_for_test();
        let result = string::utf8(b"Hello World");
        // let proof = string::utf8(b"");

        let sig = signer::module_signer<Test>();
        oracles::fulfil_request(&sig, id, 200, result);
    }


    #[test]
    #[expected_failure(abort_code = 1006, location = verity::oracles)]
    public fun test_view_functions(){
        let id = create_oracle_request();
        let sig = signer::module_signer<Test>();
        // Test the Object

        assert!(oracles::get_request_oracle(&id) == signer::address_of(&sig), 99951);
        assert!(oracles::get_request_params_url(&id) == string::utf8(b"https://api.example.com/data"), 99952);
        assert!(oracles::get_request_params_method(&id) == string::utf8(b"GET"), 99953);
        assert!(oracles::get_request_params_body(&id) == string::utf8(b""), 99954);
        assert!(oracles::get_response_status(&id) ==(0 as u16), 99955);
    }

    #[test]
    #[expected_failure(abort_code = 1006, location = verity::oracles)]
    public fun test_consume_fulfil_request() {
        let id = create_oracle_request();
        fulfil_request(id);

        // assert!(oracles::get_response(&id) == option::some(string::utf8(b"Hello World")), 99958);
        assert!(oracles::get_response_status(&id) == (200 as u16), 99959);
    }
}