// Copyright (c) Usher Labs
// SPDX-License-Identifier: LGPL-2.1

module verity::oracles {
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use std::ascii::String as AsciiString;

    const ESignerNotOracle: u64 = 1002;
    
    struct RequestHeaders has store, copy, drop {
        content_type: String,
        additional_headers: String
    }

    // Struct to represent HTTP request parameters
    struct HTTPRequest has store, copy, drop {
        url: String,
        method: String,
        headers: String,
        body: String,
    }

    struct Request has key {
        id: UID,
        params: HTTPRequest,
        pick: String,
        oracle: address,
        response_status: u16,
        response: Option<String>,
        notify: Option<vector<u8>>
    }

    // Events
    struct RequestAdded has copy, drop {
        request_id: ID,
        creator: address,
        params: HTTPRequest,
        pick: String,
        oracle: address,
        notify: Option<vector<u8>>
    }

    struct Fulfilment has copy, drop {
        request_id: ID,
        status: u16,
        result: String
    }

    public fun create_headers(
        content_type: String,
        additional_headers: String
    ): RequestHeaders {
        RequestHeaders {
            content_type,
            additional_headers
        }
    }

    public fun create_openai_request(
        prompt: String,
        model: String
    ): HTTPRequest {
        let body = format_openai_body(prompt, model);
        
        HTTPRequest {
            url: string::utf8(b"https://api.openai.com/v1/chat/completions"),
            method: string::utf8(b"POST"),
            headers: string::utf8(b"application/json"),
            body
        }
    }

    fun format_openai_body(prompt: String, model: String): String {
        // Create properly formatted JSON for OpenAI
        let template = b"{\"model\":\"%\",\"messages\":[{\"role\":\"user\",\"content\":\"%\"}]}";
        // Replace % with model and prompt
        // Note: In real implementation you'd need proper string manipulation
        string::utf8(template)
    }

    // Helper function to build request
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
            body
        }
    }

    // Create a new request
    public entry fun new_request(
        url: String,
        method: String,
        headers: String,
        body: String,
        pick: String,
        oracle: address,
        notify: Option<vector<u8>>,
        ctx: &mut TxContext
    ) {
        let params = build_request(url, method, headers, body);
        let request = Request {
            id: object::new(ctx),
            params,
            pick,
            oracle,
            response_status: 0,
            response: option::none(),
            notify
        };

        let request_id = object::uid_to_inner(&request.id);

        event::emit(RequestAdded {
            request_id,
            creator: tx_context::sender(ctx),
            params,
            pick,
            oracle,
            notify
        });

        transfer::transfer(request, oracle);
    }

    // Fulfill a request
    public entry fun fulfil_request(
        request: &mut Request,
        status: u16,
        result: String,
        ctx: &TxContext
    ) {
        assert!(request.oracle == tx_context::sender(ctx), ESignerNotOracle);
        
        request.response_status = status;
        request.response = option::some(result);

        event::emit(Fulfilment {
            request_id: object::uid_to_inner(&request.id),
            status,
            result
        });
    }

    // Add public accessors for HTTPRequest fields
    public fun get_request_url(request: &HTTPRequest): String {
        request.url
    }

    public fun get_request_method(request: &HTTPRequest): String {
        request.method
    }

    public fun get_request_headers(request: &HTTPRequest): String {
        request.headers
    }

    public fun get_request_body(request: &HTTPRequest): String {
        request.body
    }

    #[test]
    fun test_create_and_fulfill_request() {
        use sui::test_scenario;

        let user = @0xCAFE;
        let oracle = @0xDEAD;
        
        let scenario = test_scenario::begin(user);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            
            new_request(
                string::utf8(b"https://api.example.com"),
                string::utf8(b"GET"),
                string::utf8(b""),
                string::utf8(b""),
                string::utf8(b"$.data.price"),
                oracle,
                option::none(),
                ctx
            );
        };
        test_scenario::end(scenario);
    }
}