// Copyright (c) Usher Labs
// SPDX-License-Identifier: LGPL-2.1

module verity_test_foreign_module::example_caller {
    use sui::object::{Self, ID, UID};
    use sui::tx_context::TxContext;
    use sui::transfer;
    use std::vector;
    use std::string::{Self, String};
    use std::option;
    use verity::oracles::{Self as Oracles};

    // Store pending requests
    struct GlobalStore has key {
        id: UID,
        pending_requests: vector<ID>
    }

    // Initialize the module with empty pending requests
    fun init(ctx: &mut TxContext) {
        let store = GlobalStore {
            id: object::new(ctx),
            pending_requests: vector::empty<ID>()
        };
        transfer::share_object(store);
    }

    public entry fun request_data(
        store: &mut GlobalStore,
        url: String,
        method: String,
        headers: String,
        body: String,
        pick: String,
        oracle: address,
        ctx: &mut TxContext
    ) {
        assert!(
            method == string::utf8(b"GET") || 
            method == string::utf8(b"POST") ||
            method == string::utf8(b"PUT") ||
            method == string::utf8(b"DELETE"),
            0
        );

        Oracles::new_request(
            url,
            method,
            headers,
            body,
            pick,
            oracle,
            option::some(b"example_caller::receive_data"),
            ctx
        );
    }

    public entry fun receive_data(store: &mut GlobalStore) {
        let i = 0;
        while (i < vector::length(&store.pending_requests)) {
            let _request_id = *vector::borrow(&store.pending_requests, i);
            vector::remove(&mut store.pending_requests, i);
            i = i + 1;
        }
    }

    public entry fun request_openai_chat(
        store: &mut GlobalStore,
        prompt: String,
        model: String,
        pick: String,
        oracle: address,
        ctx: &mut TxContext
    ) {
        let request = Oracles::create_openai_request(prompt, model);
        
        Oracles::new_request(
            Oracles::get_request_url(&request),
            Oracles::get_request_method(&request),
            Oracles::get_request_headers(&request),
            Oracles::get_request_body(&request),
            pick,
            oracle,
            option::some(b"example_caller::receive_data"),
            ctx
        );
    }

    #[test]
    fun test_request_data() {
        use sui::test_scenario;

        let user = @0xCAFE;
        let oracle = @0xDEAD;
        
        let scenario = test_scenario::begin(user);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            init(ctx);
        };

        test_scenario::next_tx(&mut scenario, user);
        {
            let store = test_scenario::take_shared<GlobalStore>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            request_data(
                &mut store,
                string::utf8(b"https://api.test.com"),
                string::utf8(b"GET"),
                string::utf8(b""),
                string::utf8(b""),
                string::utf8(b"$.data"),
                oracle,
                ctx
            );

            test_scenario::return_shared(store);
        };
        test_scenario::end(scenario);
    }
} 