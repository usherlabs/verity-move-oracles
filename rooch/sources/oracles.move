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
    use moveos_std::hash;
    use moveos_std::object::{Self, ObjectID, Object};
    use moveos_std::simple_map::{Self, SimpleMap};
    use moveos_std::table::{Self, Table};
    use moveos_std::hex;

    use rooch_framework::coin::{Self, Coin};
    use rooch_framework::gas_coin::RGas;
    use rooch_framework::account_coin_store;
    use rooch_framework::coin_store::{Self, CoinStore};
    use rooch_framework::ecdsa_k1;
    use rooch_framework::ethereum_address::{Self,ETHAddress};
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use std::vector;
    use std::debug;


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
    const NoResponseBodyFound: u64 = 1012;
    const TLSVerificationFailed: u64 = 1012;



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

    /// New global parameters structure using Table
    struct GlobalParamsV2 has key {
        owner: address,
        treasury: Object<CoinStore<RGas>>,
        // Use Table instead of SimpleMap for better performance
        balances: Table<address, u256>,
        // Notification gas allocations using Table
        notification_gas_allocation: Table<String, Table<address, u256>>
    }

    /// New global parameters with CKTLS validation
    struct GlobalParamsV3 has key {
        owner: address,
        treasury: Object<CoinStore<RGas>>,
        // Use Table instead of SimpleMap for better performance
        balances: Table<address, u256>,
        // Notification gas allocations using Table
        notification_gas_allocation: Table<String, Table<address, u256>>,

        ic_public_address: ETHAddress
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
        init_v1();
        let module_signer = signer::module_signer<GlobalParams>();
        migrate_to_v2(&module_signer);
        migrate_to_v3(&module_signer)
    }

    fun init_v1(){
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

    /// Migration function to move from V1 to V2
    public entry fun migrate_to_v2(account: &signer) {
        assert!(signer::address_of(account) == @verity, OnlyOwnerError);
        
        // Unpack old params directly
        let GlobalParams {
            owner,
            treasury,
            balances: old_balances,
            notification_gas_allocation: old_notifications
        } = account::move_resource_from<GlobalParams>(@verity);
        
        // Create new tables
        let new_balances = table::new();
        let new_notifications = table::new();

        // Migrate balances
        let balance_keys = simple_map::keys(&old_balances);
        let balance_values = simple_map::values(&old_balances);
        let i = 0;
        let len = vector::length(&balance_keys);
        while (i < len) {
            let key = vector::borrow(&balance_keys, i);
            let value = vector::borrow(&balance_values, i);
            table::add(&mut new_balances, *key, *value);
            i = i + 1;
        };

        // Migrate notification allocations
        let notify_keys = simple_map::keys(&old_notifications);
        let notify_values = simple_map::values(&old_notifications);
        let i = 0;
        let len = vector::length(&notify_keys);
        while (i < len) {
            let notify_endpoint = vector::borrow(&notify_keys, i);
            let user_allocations = vector::borrow(&notify_values, i);
            
            let new_user_table = table::new();
            let user_keys = simple_map::keys(user_allocations);
            let user_values = simple_map::values(user_allocations);
            let j = 0;
            let user_len = vector::length(&user_keys);
            while (j < user_len) {
                let user = vector::borrow(&user_keys, j);
                let amount = vector::borrow(&user_values, j);
                table::add(&mut new_user_table, *user, *amount);
                j = j + 1;
            };
            
            table::add(&mut new_notifications, *notify_endpoint, new_user_table);
            i = i + 1;
        };

        // Create and move new GlobalParamsV2
        account::move_resource_to(account, GlobalParamsV2 {
            owner,
            treasury,
            balances: new_balances,
            notification_gas_allocation: new_notifications
        });
    }
    /// Migration function to move from V2 to V3
    public entry fun migrate_to_v3(account: &signer) {
        // Unpack old params directly
        let GlobalParamsV2 {
            owner,
            treasury,
            balances,
            notification_gas_allocation
        } = account::move_resource_from<GlobalParamsV2>(@verity);
        

        // Create and move new GlobalParamsV2
        account::move_resource_to(account, GlobalParamsV3 {
            owner,
            treasury,
            balances,
            notification_gas_allocation,
            ic_public_address: ethereum_address::from_bytes(hex::decode(&b"ba12a284e29aeaaea28ff233118841950f353990"))
        });
    }

    /// Update notification gas allocation for a specific notify address and user
    public entry fun update_notification_gas_allocation(
        from: &signer,
        notify_address: address,
        notify_function: String,
        amount: u256
    ) {
        assert!(amount==0 ||amount>500_000,MinGasLimitError);
        let global_params = account::borrow_mut_resource<GlobalParamsV3>(@verity);
        let sender = signer::address_of(from);
        let notification_endpoint= option::destroy_some(with_notify(notify_address,notify_function));

        if (!table::contains(&global_params.notification_gas_allocation, notification_endpoint)) {
            let user_allocations = table::new();
            table::add(&mut user_allocations, sender, amount);
            table::add(&mut global_params.notification_gas_allocation, notification_endpoint, user_allocations);
        } else {
            let user_allocations = table::borrow_mut(&mut global_params.notification_gas_allocation, notification_endpoint);
            if (!table::contains(user_allocations, sender)) {
                table::add(user_allocations, sender, amount);
            } else {
                let user_amount = table::borrow_mut(user_allocations, sender);
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
    public entry fun set_owner(
        new_owner: address
    ) {
        let owner = tx_context::sender();
        let params = account::borrow_mut_resource<GlobalParamsV3>(@verity);
        assert!(params.owner == owner, OnlyOwnerError);
        params.owner = new_owner;
    }

    /// Change the ic_public_address of the oracle system tls verification
    public entry fun set_ic_public_address(
        new_ic_public_address: String
    ) {
        let owner = tx_context::sender();
        let params = account::borrow_mut_resource<GlobalParamsV3>(@verity);
        assert!(params.owner == owner, OnlyOwnerError);
        params.ic_public_address = ethereum_address::from_bytes(string::into_bytes(new_ic_public_address));
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
        request_account: address,
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
            request_account,
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
    public fun new_request_with_payment(
        params: HTTPRequest,
        pick: String,
        oracle: address,
        notify: Option<String>,
        payment: Coin<RGas>
    ): ObjectID {
        let sent_coin = coin::value(&payment);
        // 65536 could be changed to the max string length allowed on Move
        // This 65536 is a default estaimate for the expected payload length, however, it's the user's responsibility to cover in case of requests that expect large payload responses.
        let option_min_amount = OracleSupport::estimated_cost(oracle, params.url, string::length(&params.body), 65536);
        assert!(option::is_some(&option_min_amount), OracleSupportError);
        let min_amount = option::destroy_some(option_min_amount);

        assert!(sent_coin >= min_amount, NotEnoughGasError);
        let global_param = account::borrow_mut_resource<GlobalParamsV3>(@verity);
        coin_store::deposit(&mut global_param.treasury, payment);
        let request_account = tx_context::sender();
        return create_request(
            request_account,
            params,
            pick,
            oracle,
            notify,
            min_amount
        )
    }

    /// Creates a new oracle request using tx sender's escrow balance
    public fun new_request(
        params: HTTPRequest,
        pick: String,
        oracle: address,
        notify: Option<String>,
    ): ObjectID {
        let request_account = tx_context::sender();
        new_request_with_request_account(request_account, params, pick, oracle, notify)
    }

    /// Creates a new oracle request using caller's escrow balance
    public fun new_request_by_signer(
        caller: &signer,
        params: HTTPRequest,
        pick: String,
        oracle: address,
        notify: Option<String>,
    ): ObjectID {
        let request_account = signer::address_of(caller);
        new_request_with_request_account(request_account, params, pick, oracle, notify)
    }

    fun new_request_with_request_account(
        request_account: address,
        params: HTTPRequest,
        pick: String,
        oracle: address,
        notify: Option<String>,
    ): ObjectID {
        let account_balance = get_user_balance(request_account);
        // 65536 could be changed to the max string length allowed on Move
        let option_min_amount = OracleSupport::estimated_cost(oracle, params.url, string::length(&params.body), 65536);
        assert!(option::is_some(&option_min_amount), OracleSupportError);
        let min_amount = option::destroy_some(option_min_amount);

        assert!(account_balance >= min_amount, NotEnoughGasError);
        let global_params = account::borrow_mut_resource<GlobalParamsV3>(@verity);
        let balance = table::borrow_mut(&mut global_params.balances, request_account);
        *balance = *balance - min_amount;

        return create_request(
            request_account,
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
        
        let global_params = account::borrow_mut_resource<GlobalParamsV3>(@verity);
        let sender = signer::address_of(from);
        
        let deposit = account_coin_store::withdraw<RGas>(from, amount);
        coin_store::deposit(&mut global_params.treasury, deposit);

        if (!table::contains(&global_params.balances, sender)) {
            table::add(&mut global_params.balances, sender, amount);
        } else {
            let balance = table::borrow_mut(&mut global_params.balances, sender);
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
        
        let global_params = account::borrow_mut_resource<GlobalParamsV3>(@verity);
        let sender = signer::address_of(from);
        
        // Check if user has a balance
        assert!(table::contains(&global_params.balances, sender), NoBalanceError);
        
        let balance = table::borrow_mut(&mut global_params.balances, sender);
        // Check if user has enough balance
        assert!(*balance >= amount, InsufficientBalanceError);
        
        // Update balance
        *balance = *balance - amount;
        
        // If balance becomes zero, remove the entry
        if (*balance == 0) {
            table::remove(&mut global_params.balances, sender);
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
        let global_params = account::borrow_mut_resource<GlobalParamsV3>(@verity);
        let payment = coin_store::withdraw(&mut global_params.treasury, fulfillment_cost);

        account_coin_store::deposit(caller_address, payment);

        let notification_cost = 0;
        if (option::is_some(&request.notify) && get_notification_gas_allocation_by_notification_endpoint(option::destroy_some(request.notify),request.request_account)>0 ){
            notification_cost =get_notification_gas_allocation_by_notification_endpoint(option::destroy_some(request.notify),request.request_account);
        };
        // add extra to balance if any exists 
        if (request.amount > fulfillment_cost + notification_cost) {
            if(notification_cost>0){
                let notification_payment = coin_store::withdraw(&mut global_params.treasury, notification_cost);
                account_coin_store::deposit(keeper, notification_payment);
            };
            if (!table::contains(&global_params.balances, request.request_account)) {
                table::add(&mut global_params.balances, request.request_account, request.amount - fulfillment_cost-notification_cost);
            } else {
                let balance = table::borrow_mut(&mut global_params.balances, request.request_account);
                *balance = *balance + request.amount - fulfillment_cost- notification_cost;
            };
        };

        // Emit fulfil event
        event::emit(Fulfilment {
            request: *request,
        });
    }

        /// Fulfill an oracle request with response data
    /// Only callable by the designated oracle
    public entry fun fulfil_request_with_tls_verification(
        caller: &signer,
        id: ObjectID,
        response_status: u16,
        proof: String,
        signature: String,
        keeper: address,
    ) {
        assert!(check_proof_signature_validity(proof,signature),TLSVerificationFailed);
        let result = extract_body(proof);
        fulfil_request(caller,id,response_status,result,keeper)
    }

    // // This is a Version 0 of the verifier.
    // public fun verify(
    //     data: String,
    //     proof: d
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
        let global_params = account::borrow_resource<GlobalParamsV3>(@verity);
        if (table::contains(&global_params.balances, user)) {
            *table::borrow(&global_params.balances, user)
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
        let global_params = account::borrow_resource<GlobalParamsV3>(@verity);

        if (!table::contains(&global_params.notification_gas_allocation, notification_endpoint)) {
            return 0
        };
        
        let user_allocations = table::borrow(&global_params.notification_gas_allocation, notification_endpoint);
        if (table::contains(user_allocations, user)) {
            *table::borrow(user_allocations, user)
        } else {
            0
        }
    }

    fun normalize_signature(sig: vector<u8>): vector<u8> {

        let len = vector::length(&sig);
        assert!(len == 65, 1);

        let v = vector::pop_back(&mut sig);
        let rec_id = if (v > 27) { v - 27 } else { v };
        vector::push_back(&mut sig, rec_id);
        sig
    }

    /// Split a string by a delimiter
    fun split(s: &String, delimiter: &String): vector<String> {
        let result = vector::empty<String>();
        let start = 0;
        let len = string::length(s);
        
        while (start <= len) {
            let pos = if (start == len) {
                len
            } else {
                let sub = string::sub_string(s, start, len);
                let idx = string::index_of(&sub, delimiter);
                if (idx == string::length(&sub)) {
                    len
                } else {
                    start + idx
                }
            };
            
            if (pos >= start) {
                let part = string::sub_string(s, start, pos);
                vector::push_back(&mut result, part);
            };
            
            if (pos == len) break;
            start = pos + string::length(delimiter);
        };
        result
    }

    #[view]
    public fun extract_body(data: String): String{
        let all_split=split(&data,&string::utf8(b"\r\n\r\n"));

        let body = string::utf8(b"");
        let len = vector::length(&all_split);
        assert!(len>2, NoResponseBodyFound);
        let start = 0;
        while (start <= len) {
            body = vector::pop_back(&mut all_split);
            if (string::length(&body)==0){
                start=start+1;
            }else {
                break
            };
            if (start == len) break;
        };

        let res_header = vector::pop_back(&mut all_split);

        if(string::index_of(&res_header, &string::utf8(b"application/json")) != string::length(&res_header)){
            let ends_at= string::index_of(&body, &string::utf8(b"}\r\n"));
            let start_at= string::index_of(&body, &string::utf8(b"{"));
            debug::print(&string::sub_string(&body,start_at,ends_at));
            return string::sub_string(&body,start_at,ends_at)
        }else{
            return body
        }
    }



    #[view]
    public fun check_proof_signature_validity( proof: String,signature: String):bool{
        let _prefix = b"\x19Ethereum Signed Message:\n";
        let message =   hex::encode(hash::sha2_256(string::into_bytes(proof)));
        vector::append(&mut _prefix, u64_to_string(vector::length(&message)));
        vector::append(&mut _prefix, message);

        let _signature=hex::decode(&string::into_bytes(signature));
        let pk = ecdsa_k1::ecrecover(&normalize_signature(_signature), &_prefix, ecdsa_k1::keccak256());
        let pk = ethereum_address::new(pk);
        let _address = ethereum_address::into_bytes(pk);


        let global_params = account::borrow_resource<GlobalParamsV3>(@verity);
        global_params.ic_public_address == pk

    }

    #[view]
    fun u64_to_string(n: u64): vector<u8> {
      let  digits = vector::empty<u8>();

      // Special case for zero
      if (n == 0) {
        // ASCII '0' is 48
        vector::push_back(&mut digits, 48);
        digits
      }else{
        // Extract digits in reverse order
        while (n > 0) {
            vector::push_back(&mut digits, ((n % 10) as u8) + 48);
            n = n / 10;
        };

        // Reverse to get the correct order
        vector::reverse(&mut digits);
        digits
        }
    }

   
}

#[test_only]
module verity::test_oracles {
    use std::string;
    use moveos_std::signer;
    use std::debug;
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
        let amount = 1000_000u256;

        // Test initial allocation
        oracles::update_notification_gas_allocation(&sig, sender, notify_address, amount);
        assert!(oracles::get_notification_gas_allocation(sender, notify_address, sender) == amount, 99962);

        // Test updating existing allocation
        let new_amount = 2000_000u256;
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
        let amount1 = 1000_000u256;
        let amount2 = 2000_000u256;

        oracles::update_notification_gas_allocation(&sig, sender, notify_address1, amount1);
        oracles::update_notification_gas_allocation(&sig, sender, notify_address2, amount2);
        
        assert!(oracles::get_notification_gas_allocation(sender, notify_address1, sender) == amount1, 99964);
        assert!(oracles::get_notification_gas_allocation(sender, notify_address2, sender) == amount2, 99965);

        // Update existing allocations
        let new_amount1 = 1500_000u256;
        let new_amount2 = 2500_000u256;
        
        oracles::update_notification_gas_allocation(&sig, sender, notify_address1, new_amount1);
        oracles::update_notification_gas_allocation(&sig, sender, notify_address2, new_amount2);

        assert!(oracles::get_notification_gas_allocation(sender, notify_address1, sender) == new_amount1, 99966);
        assert!(oracles::get_notification_gas_allocation(sender, notify_address2, sender) == new_amount2, 99967);
    }

    #[test]
    public fun test_compute_merkle_root_from_proof() {
        // Test function to fulfill a request  
        oracles::init_for_test();
        let proof = string::utf8(b"GET https://api.x.com/2/tweets?ids=1915138091142033501&tweet.fields=created_at,public_metrics&expansions=author_id&user.fields=created_at HTTP/1.1\r\nhost: api.x.com\r\naccept: */*\r\ncache-control: no-cache\r\nconnection: close\r\naccept-encoding: identity\r\nauthorization: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\r\n\r\n\n\nHTTP/1.1 200 OK\r\nDate: Wed, 23 Apr 2025 20:23:02 GMT\r\nContent-Type: application/json; charset=utf-8\r\nTransfer-Encoding: chunked\r\nConnection: close\r\nperf: 7402827104\r\nSet-Cookie: guest_id=v1%3A174543978261073637; Max-Age=34214400; Expires=Sun, 24 May 2026 20:23:02 GMT; Path=/; Domain=.x.com; Secure; SameSite=None\r\napi-version: 2.135\r\nCache-Control: no-cache, no-store, max-age=0\r\nx-access-level: read\r\nx-frame-options: SAMEORIGIN\r\nx-transaction-id: e89a9445df246a19\r\nx-xss-protection: 0\r\nx-rate-limit-limit: 15\r\nx-rate-limit-reset: 1745440262\r\ncontent-disposition: attachment; filename=json.json\r\nx-content-type-options: nosniff\r\nx-rate-limit-remaining: 12\r\nstrict-transport-security: max-age=631138519\r\nx-response-time: 47\r\nx-connection-hash: a9cd202325d14145aa91c16210abf78a1f099bc3f5b65c95b195ecd472e4eb1a\r\ncf-cache-status: DYNAMIC\r\nvary: accept-encoding\r\nSet-Cookie: __cf_bm=9wAVlwyQO1TTmsKP8MiY29Py.CkyhCtnbdlPACOQo4s-1745439782-1.0.1.1-SeBSXQQXJ6q3WcwNAUaCu5eCnppfAKlB.JMVZVYKOSsayUGx60QaptaKma1NW6K7HTTC_4IS3EGUV1dvYSh8CQsOovCvMFznWuXPslRWxw8; path=/; expires=Wed, 23-Apr-25 20:53:02 GMT; domain=.x.com; HttpOnly; Secure\r\nServer: cloudflare tsa_p\r\nCF-RAY: 935013912dda764c-SEA\r\n\r\n1bb\r\n{\"data\":[{\"text\":\"Test 23/04/2025\",\"author_id\":\"859712682181746688\",\"public_metrics\":{\"retweet_count\":0,\"reply_count\":0,\"like_count\":0,\"quote_count\":0,\"bookmark_count\":0,\"impression_count\":2},\"created_at\":\"2025-04-23T20:17:57.000Z\",\"edit_history_tweet_ids\":[\"1915138091142033501\"],\"id\":\"1915138091142033501\"}],\"includes\":{\"users\":[{\"id\":\"859712682181746688\",\"username\":\"xlassix\",\"created_at\":\"2017-05-03T10:14:10.000Z\",\"name\":\"Xlassix.eth\"}]}}\r\n0\r\n\r\n");
        let signature = string::utf8(b"5bfcd462623d7ab64665cfa71a36e3350378eb6959759244df1de83a06bab214450edb1cc77729e07ee1877ab8d4868e40812059b8e3bf1facd07d335d7d80351c");
        let signature2 = string::utf8(b"3542c6f79d33c0ddf980cfef4216bbd40291c3dae4b998864c844e6b41736ada0810be8315b9e28828413728c19b05674aafdb1561839c4f97d4a641c13219991c");
        let proof2 = string::utf8(b"GET https://api.x.com/2/tweets?ids=1583095539742408706&tweet.fields=created_at,public_metrics&expansions=author_id&user.fields=created_at HTTP/1.1\r\nhost: api.x.com\r\naccept: */*\r\ncache-control: no-cache\r\nconnection: close\r\naccept-encoding: identity\r\nauthorization: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\r\n\r\n\n\nHTTP/1.1 200 OK\r\nDate: Thu, 10 Apr 2025 08:09:13 GMT\r\nContent-Type: application/json; charset=utf-8\r\nTransfer-Encoding: chunked\r\nConnection: close\r\nperf: 7402827104\r\nSet-Cookie: guest_id_marketing=v1%3A174427255351633530; Max-Age=63072000; Expires=Sat, 10 Apr 2027 08:09:13 GMT; Path=/; Domain=.x.com; Secure; SameSite=None\r\napi-version: 2.133\r\nCache-Control: no-cache, no-store, max-age=0\r\nx-access-level: read\r\nx-frame-options: SAMEORIGIN\r\nx-transaction-id: ae74f6476b34881c\r\nx-xss-protection: 0\r\nx-rate-limit-limit: 15\r\nx-rate-limit-reset: 1744273020\r\ncontent-disposition: attachment; filename=json.json\r\nx-content-type-options: nosniff\r\nx-rate-limit-remaining: 12\r\nstrict-transport-security: max-age=631138519\r\nx-response-time: 38\r\nx-connection-hash: e1811c1af4a712f8b8f060cf83c9f3c52b760a83e1aa1322aec4d46c9d5a3d8a\r\nvary: accept-encoding\r\ncf-cache-status: DYNAMIC\r\nSet-Cookie: guest_id_ads=v1%3A174427255351633530; Max-Age=63072000; Expires=Sat, 10 Apr 2027 08:09:13 GMT; Path=/; Domain=.x.com; Secure; SameSite=None\r\nSet-Cookie: personalization_id=\"v1_g8oXK5WldT1cRKOnjUexkg==\"; Max-Age=63072000; Expires=Sat, 10 Apr 2027 08:09:13 GMT; Path=/; Domain=.x.com; Secure; SameSite=None\r\nSet-Cookie: guest_id=v1%3A174427255351633530; Max-Age=63072000; Expires=Sat, 10 Apr 2027 08:09:13 GMT; Path=/; Domain=.x.com; Secure; SameSite=None\r\nSet-Cookie: __cf_bm=aYHa3DJx6kIzxTz7IELrbFQBNKBL_5Iofd9W3AbYtno-1744272553-1.0.1.1-Zzj.yPyAK31VMOcg4ptXdkjlVf3gphX9d8lmQ1iKKqrYwyxw4YcCCw5uOPNO.Lm6z0iRWql437G2IO.hu8dl5MZk.4QNyoj8LrXtRdGAOh0; path=/; expires=Thu, 10-Apr-25 08:39:13 GMT; domain=.x.com; HttpOnly; Secure\r\nServer: cloudflare tsa_b\r\nCF-RAY: 92e0c2c31f50e3cd-LIS\r\n\r\n206\r\n{\"data\":[{\"id\":\"1583095539742408706\",\"text\":\"The cure to a  weak mind: \\nPush yourself when you are least motivated \\n\\n- David Goggins\",\"edit_history_tweet_ids\":[\"1583095539742408706\"],\"created_at\":\"2022-10-20T13:59:23.000Z\",\"author_id\":\"859712682181746688\",\"public_metrics\":{\"retweet_count\":0,\"reply_count\":0,\"like_count\":1,\"quote_count\":0,\"bookmark_count\":0,\"impression_count\":0}}],\"includes\":{\"users\":[{\"created_at\":\"2017-05-03T10:14:10.000Z\",\"name\":\"Xlassix.eth\",\"username\":\"xlassix\",\"id\":\"859712682181746688\"}]}}\r\n0\r\n\r\n");

        debug::print(&oracles::check_proof_signature_validity(proof,signature));
        debug::print(&oracles::check_proof_signature_validity(proof2,signature2));

        debug::print(&oracles::extract_body(proof2));

        assert!(oracles::check_proof_signature_validity(proof,signature),2999);
        assert!(!oracles::check_proof_signature_validity(proof2,signature2),2999);

    }

}