// Copyright (c) Usher Labs
// SPDX-License-Identifier: LGPL-2.1

/// This module implements an oracle system for Verity.
/// It allows users to create new requests for off-chain data,
/// which are then fulfilled by designated oracles.
/// The system manages pending requests and emits events
/// for both new requests and fulfilled requests.
module verity::oracles {
    
    use moveos_std::event;
    use moveos_std::tx_context;
    use moveos_std::signer;
    use moveos_std::account;
    use moveos_std::address;
    use moveos_std::object::{Self, ObjectID, Object};

    use rooch_framework::coin::{Self, Coin};
    use rooch_framework::gas_coin::RGas;
    use rooch_framework::account_coin_store;
    use rooch_framework::coin_store::{Self, CoinStore};
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use moveos_std::simple_map::{Self, SimpleMap};

    #[test_only]
    use rooch_framework::genesis;
    use verity::registry::{Self as OracleSupport};

    const RequestNotFoundError: u64 = 1001;
    const SignerNotOracleError: u64 = 1002;
    // const ProofNotValidError: u64 = 1003; // Commented out since proof verification is not implemented yet
    const OnlyOwnerError: u64 = 1004;
    const NotEnoughGasError: u64 = 1005;
    const OracleSupportError: u64 = 1006;
    const DoubleFulfillmentError: u64 = 1007;
    const InsufficientBalanceError: u64 = 1008;
    const NoBalanceError: u64 = 1009;
    const ZeroAmountError: u64 = 1010;
    const MinGasLimitError: u64 = 1011;

    /// Struct to represent HTTP request parameters
    /// Designed to be imported by third-party contracts
    struct HTTPRequest has store, copy, drop {
        url: String,
        method: String,
        headers: String,
        body: String,
    }

    /// Represents an oracle request with all necessary parameters
    struct Request has key, store, copy, drop {
        params: HTTPRequest,
        pick: String, // An optional JQ string to pick the value from the response JSON data structure.
        oracle: address,
        response_status: u16,
        response: Option<String>,
        // This is an account to be paid back by the Contract in case of excess payment.
        request_account: address,
        amount: u256,
        notify: Option<String>
    }

    /// Global parameters for the oracle system
    struct GlobalParams has key {
        owner: address,
        treasury: Object<CoinStore<RGas>>,
        // Holds the address of each requesting Contract and their balance
        // Either a calling Contract, or a User adjust the balance.
        balances: SimpleMap<address, u256>,

        // Notify=> Address => UserAddress => Amount Allocation
        notification_gas_allocation: SimpleMap<String, SimpleMap<address, u256>>
    }

    // -------- Events --------
    /// Event emitted when a new request is added
    struct RequestAdded has copy, drop {
        params: HTTPRequest,
        pick: String, // An optional JQ string to pick the value from the response JSON data structure.
        oracle: address,
        notify: Option<String>,
        request_id: ObjectID
    }

    /// Event emitted when a request is fulfilled
    struct Fulfilment has copy, drop {
        request: Request,
    }

    /// Event emitted for escrow deposits/withdrawals
    struct EscrowEvent has copy, drop {
        user: address,
        amount: u256,
        is_deposit: bool,
    }
    // ------------------------

    /// Initialize the oracle system
    fun init() {
        let module_signer = signer::module_signer<GlobalParams>();
        let owner = tx_context::sender();
        let treasury_obj = coin_store::create_coin_store<RGas>();

        account::move_resource_to(&module_signer, GlobalParams {
            owner,
            treasury: treasury_obj,
            balances: simple_map::new(),
            notification_gas_allocation: simple_map::new()
        });
    }


    /// Update notification gas allocation for a specific notify address and user
    public entry fun update_notification_gas_allocation(
        from: &signer,
        notify_address: address,
        notify_function: String,
        amount: u256
    ) {
        assert!(amount==0 ||amount>=500_000,MinGasLimitError);
        let global_params = account::borrow_mut_resource<GlobalParams>(@verity);
        let sender = signer::address_of(from);
        let notification_endpoint= option::destroy_some(with_notify(notify_address,notify_function));

        if (!simple_map::contains_key(&global_params.notification_gas_allocation, &notification_endpoint)) {
            let user_allocations = simple_map::new();
            simple_map::add(&mut user_allocations, sender, amount);
            simple_map::add(&mut global_params.notification_gas_allocation, notification_endpoint, user_allocations);
        } else {
            let user_allocations = simple_map::borrow_mut(&mut global_params.notification_gas_allocation, &notification_endpoint);
            if (!simple_map::contains_key(user_allocations, &sender)) {
                simple_map::add(user_allocations, sender, amount);
            } else {
                let user_amount = simple_map::borrow_mut(user_allocations, &sender);
                *user_amount = amount;
            }
        }
    }

    #[test_only]
    /// Initialize the oracle system for testing
    public fun init_for_test() {
        genesis::init_for_test();
        OracleSupport::init_for_test();
        init();
    }

    /// Change the owner of the oracle system
    /// Only callable by current owner
    public entry fun set_owner(
        new_owner: address
    ) {
        let owner = tx_context::sender();
        let params = account::borrow_mut_resource<GlobalParams>(@verity);
        assert!(params.owner == owner, OnlyOwnerError);
        params.owner = new_owner;
    }

    /// Create a new HTTPRequest struct with the given parameters
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

    // Create notification data for request callbacks
    #[view]
    public fun with_notify(
        notify_address: address,
        notify_function: String,
    ): Option<String> {
        let res = address::to_string(&notify_address);
        string::append(&mut res,string::utf8(b"::")); // append delimiter
        string::append(&mut res ,notify_function);
        option::some(res)
    }

    /// Create empty notification data
    public fun without_notify(): Option<String> {
        option::none()
    }

    /// Internal function to create a new request
    fun create_request(
        params: HTTPRequest,
        pick: String,
        oracle: address,
        notify: Option<String>,
        amount: u256
    ): ObjectID {
        // Create new request object
        let request = object::new(Request {
            params,
            pick,
            oracle,
            response_status: 0,
            response: option::none(),
            request_account: tx_context::sender(),
            amount,
            notify
        });
        let request_id = object::id(&request);
        object::transfer(request, oracle); // transfer to oracle to ensure permission

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

    /// Creates a new oracle request with direct payment
    /// Caller must provide sufficient RGas payment
    public fun new_request_with_payment(
        params: HTTPRequest,
        pick: String,
        oracle: address,
        notify: Option<String>,
        payment: Coin<RGas>
    ): ObjectID {
        let sent_coin = coin::value(&payment);
        // 1024 could be changed to the max string length allowed on Move
        // This 1024 is a default estaimate for the expected payload length, however, it's the user's responsibility to cover in case of requests that expect large payload responses.
        let option_min_amount = OracleSupport::estimated_cost(oracle, params.url, string::length(&params.body), 1024);
        assert!(option::is_some(&option_min_amount), OracleSupportError);
        let min_amount = option::destroy_some(option_min_amount);

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

    /// Creates a new oracle request using caller's escrow balance
    public fun new_request(
        params: HTTPRequest,
        pick: String,
        oracle: address,
        notify: Option<String>,
    ): ObjectID {
        let sender = tx_context::sender();
        let account_balance = get_user_balance(sender);
        // 1024 could be changed to the max string length allowed on Move
        let option_min_amount = OracleSupport::estimated_cost(oracle, params.url, string::length(&params.body), 1024);
        assert!(option::is_some(&option_min_amount), OracleSupportError);
        let min_amount = option::destroy_some(option_min_amount);

        assert!(account_balance >= min_amount, NotEnoughGasError);
        let global_params = account::borrow_mut_resource<GlobalParams>(@verity);
        let balance = simple_map::borrow_mut(&mut global_params.balances, &sender);
        *balance = *balance - min_amount;

        return create_request(
            params,
            pick,
            oracle,
            notify,
            min_amount
        )
    }

    /// Deposit RGas into escrow for future oracle requests
    public entry fun deposit_to_escrow(from: &signer, amount: u256) {
        // Check that amount is not zero
        assert!(amount > 0, ZeroAmountError);
        
        let global_params = account::borrow_mut_resource<GlobalParams>(@verity);
        let sender = signer::address_of(from);
        
        let deposit = account_coin_store::withdraw<RGas>(from, amount);
        coin_store::deposit(&mut global_params.treasury, deposit);

        if (!simple_map::contains_key(&global_params.balances, &sender)) {
            simple_map::add(&mut global_params.balances, sender, amount);
        } else {
            let balance = simple_map::borrow_mut(&mut global_params.balances, &sender);
            *balance = *balance + amount;
        };

        // Emit deposit event
        event::emit(EscrowEvent {
            user: sender,
            amount,
            is_deposit: true,
        });
    }

    /// Withdraw RGas from escrow
    public entry fun withdraw_from_escrow(from: &signer, amount: u256) {
        // Check that amount is not zero
        assert!(amount > 0, ZeroAmountError);
        
        let global_params = account::borrow_mut_resource<GlobalParams>(@verity);
        let sender = signer::address_of(from);
        
        // Check if user has a balance
        assert!(simple_map::contains_key(&global_params.balances, &sender), NoBalanceError);
        
        let balance = simple_map::borrow_mut(&mut global_params.balances, &sender);
        // Check if user has enough balance
        assert!(*balance >= amount, InsufficientBalanceError);
        
        // Update balance
        *balance = *balance - amount;
        
        // If balance becomes zero, remove the entry
        if (*balance == 0) {
            simple_map::remove(&mut global_params.balances, &sender);
        };
        
        // Withdraw from treasury and deposit to user
        let withdrawal = coin_store::withdraw(&mut global_params.treasury, amount);
        account_coin_store::deposit(sender, withdrawal);
        
        // Emit withdraw event
        event::emit(EscrowEvent {
            user: sender,
            amount,
            is_deposit: false,
        });
    }

    /// Fulfill an oracle request with response data
    /// Only callable by the designated oracle
    public entry fun fulfil_request(
        caller: &signer,
        id: ObjectID,
        response_status: u16,
        result: String,
        keeper: address,
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

        let option_fulfillment_cost = OracleSupport::estimated_cost(request.oracle, request.params.url, string::length(&request.params.body), string::length(&result));
        assert!(option::is_some(&option_fulfillment_cost), OracleSupportError);
        let fulfillment_cost = option::destroy_some(option_fulfillment_cost);

        // send token to orchestrator wallet
        let global_params = account::borrow_mut_resource<GlobalParams>(@verity);
        let payment = coin_store::withdraw(&mut global_params.treasury, fulfillment_cost);

        account_coin_store::deposit(caller_address, payment);

        let notification_cost =0;
        if (option::is_some(&request.notify) && get_notification_gas_allocation_by_notification_endpoint(option::destroy_some(request.notify),request.request_account)>0 ){
            notification_cost =get_notification_gas_allocation_by_notification_endpoint(option::destroy_some(request.notify),request.request_account);
            let notification_payment = coin_store::withdraw(&mut global_params.treasury, notification_cost);
            account_coin_store::deposit(keeper, notification_payment);
        };

        // add extra to balance if any exists 
        if (request.amount > fulfillment_cost && (request.amount - fulfillment_cost - notification_cost) > 0) {
            if (!simple_map::contains_key(&global_params.balances, &request.request_account)) {
                simple_map::add(&mut global_params.balances, request.request_account, request.amount - fulfillment_cost-notification_cost);
            } else {
                let balance = simple_map::borrow_mut(&mut global_params.balances, &request.request_account);
                *balance = *balance + request.amount - fulfillment_cost- notification_cost;
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
    /// Internal helper to borrow a request object
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

    #[view]
    // Get notification gas allocation for a specific notify address and user
    public fun get_notification_gas_allocation(
        notify_address: address,
        notify_function: String,
        user: address
    ): u256 {
        let notification_endpoint= option::destroy_some(with_notify(notify_address,notify_function));
        get_notification_gas_allocation_by_notification_endpoint(notification_endpoint,user)
    }

    #[view]
    // Get notification gas allocation for a specific notify address and user
    public fun get_notification_gas_allocation_by_notification_endpoint(
        notification_endpoint : String,
        user: address
    ): u256 {
        let global_params = account::borrow_resource<GlobalParams>(@verity);

        if (!simple_map::contains_key(&global_params.notification_gas_allocation, &notification_endpoint)) {
            0
        } else {
            let user_allocations = simple_map::borrow(&global_params.notification_gas_allocation, &notification_endpoint);
            if (!simple_map::contains_key(user_allocations, &user)) {
                0
            } else {
                *simple_map::borrow(user_allocations, &user)
            }
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
    public fun create_oracle_request(): ObjectID {
        // Test for creating a new request
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
            oracles::with_notify(@verity, string::utf8(b"")),
            payment
        );
        request_id
    }

    #[test_only]
    public fun fulfil_request(id: ObjectID) {
        // Test function to fulfill a request  
        oracles::init_for_test();
        let result = string::utf8(b"Hello World");
        // let proof = string::utf8(b"");

        let sig = signer::module_signer<Test>();
        oracles::fulfil_request(&sig, id, 200, result,@0x555555);
    }

    #[test]
    #[expected_failure(abort_code = 1006, location = verity::oracles)]
    public fun test_view_functions() {
        // Test view functions
        let id = create_oracle_request();
        let sig = signer::module_signer<Test>();
        // Test the Object

        assert!(oracles::get_request_oracle(&id) == signer::address_of(&sig), 99951);
        assert!(oracles::get_request_params_url(&id) == string::utf8(b"https://api.example.com/data"), 99952);
        assert!(oracles::get_request_params_method(&id) == string::utf8(b"GET"), 99953);
        assert!(oracles::get_request_params_body(&id) == string::utf8(b""), 99954);
        assert!(oracles::get_response_status(&id) == (0 as u16), 99955);
    }

    #[test]
    #[expected_failure(abort_code = 1006, location = verity::oracles)]
    public fun test_consume_fulfil_request() {
        // Test request fulfillment
        let id = create_oracle_request();
        fulfil_request(id);

        // assert!(oracles::get_response(&id) == option::some(string::utf8(b"Hello World")), 99958);
        assert!(oracles::get_response_status(&id) == (200 as u16), 99959);
    }

    #[test]
    public fun test_deposit_and_withdraw() {
        // Test escrow deposit and withdrawal
        // Initialize test environment
        oracles::init_for_test();
        let sig = signer::module_signer<Test>();
        let user = signer::address_of(&sig);

        // Test deposit
        let deposit_amount = 1000u256;
        gas_coin::faucet_entry(&sig, deposit_amount);
        oracles::deposit_to_escrow(&sig, deposit_amount);

        // Verify balance after deposit
        assert!(oracles::get_user_balance(user) == deposit_amount, 99960);

        // Test withdraw
        let withdraw_amount = 500u256;
        oracles::withdraw_from_escrow(&sig, withdraw_amount);

        // Verify balance after withdrawal
        assert!(oracles::get_user_balance(user) == deposit_amount - withdraw_amount, 99961);
    }

    #[test]
    #[expected_failure(abort_code = 1010, location = verity::oracles)]
    public fun test_zero_amount_deposit() {
        // Test zero amount deposit failure
        oracles::init_for_test();
        let sig = signer::module_signer<Test>();
        oracles::deposit_to_escrow(&sig, 0);
    }

    #[test]
    #[expected_failure(abort_code = 1008, location = verity::oracles)]
    public fun test_insufficient_balance_withdraw() {
        // Test insufficient balance withdrawal failure
        oracles::init_for_test();
        let sig = signer::module_signer<Test>();
        let deposit_amount = 100u256;
        gas_coin::faucet_entry(&sig, deposit_amount);
        
        oracles::deposit_to_escrow(&sig, deposit_amount);
        // Try to withdraw more than deposited
        oracles::withdraw_from_escrow(&sig, 200u256);
    }

    #[test]
    public fun test_update_notification_gas_allocation() {
        // Initialize test environment
        oracles::init_for_test();
        let sig = signer::module_signer<Test>();
        let sender = signer::address_of(&sig);
        let notify_address = string::utf8(b"test_notify_address");
        let amount = 1_000_000u256;

        // Test initial allocation
        oracles::update_notification_gas_allocation(&sig, sender, notify_address, amount);
        assert!(oracles::get_notification_gas_allocation(sender, notify_address, sender) == amount, 99962);

        // Test updating existing allocation
        let new_amount = 2_1_000_000u256;
        oracles::update_notification_gas_allocation(&sig, sender, notify_address, new_amount);
        assert!(oracles::get_notification_gas_allocation(sender, notify_address, sender) == new_amount, 99963);
    }

    #[test]
    public fun test_multiple_notification_gas_allocations() {
        // Initialize test environment
        oracles::init_for_test();
        let sig = signer::module_signer<Test>();
        let sender = signer::address_of(&sig);
        
        // Test multiple notify addresses
        let notify_address1 = string::utf8(b"test_notify_address1");
        let notify_address2 = string::utf8(b"test_notify_address2");
        let amount1 = 1_000_000u256;
        let amount2 = 2_000_000u256;

        oracles::update_notification_gas_allocation(&sig, sender, notify_address1, amount1);
        oracles::update_notification_gas_allocation(&sig, sender, notify_address2, amount2);
        
        assert!(oracles::get_notification_gas_allocation(sender, notify_address1, sender) == amount1, 99964);
        assert!(oracles::get_notification_gas_allocation(sender, notify_address2, sender) == amount2, 99965);

        // Update existing allocations
        let new_amount1 = 500_000u256;
        let new_amount2 = 2_500_000u256;
        
        oracles::update_notification_gas_allocation(&sig, sender, notify_address1, new_amount1);
        oracles::update_notification_gas_allocation(&sig, sender, notify_address2, new_amount2);

        assert!(oracles::get_notification_gas_allocation(sender, notify_address1, sender) == new_amount1, 99966);
        assert!(oracles::get_notification_gas_allocation(sender, notify_address2, sender) == new_amount2, 99967);
    }
}