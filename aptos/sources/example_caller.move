// Copyright (c) Usher Labs
// SPDX-License-Identifier: LGPL-2.1

// ? This module is an example caller used to demonstrate how to deploy Contracts on Rooch that integrate with Verity Move Oracles.
// ? Please keep aware of the OPTIONAL section in this module.
module verity_test_foreign_module::example_caller {
    use aptos_framework::event::{EventHandle, emit_event};
    use aptos_framework::object::{Self, Object};
    use std::signer;
    use std::vector;
    use std::option::{Self, Option};
    use verity::oracles::{Self as Oracles};

    //:!>resource
    struct GlobalParams has key {
      pending_requests: vector<address>,
    }
    //<:!:resource

    // ? ------ OPTIONAL ------
    // ? This is totally OPTIONAL
    struct RequestFulfilledEvent has copy, drop {
      request_url: String,
      request_method: String,
      response: Option<String>,
    }
    // \ ------ OPTIONAL ------

    // Initiate the module with an empty vector of pending requests
    // Requests are managed in the caller to prevent other modules from impersonating the calling module, and spoofing new data.
    fun init_module(account: &signer){
      move_to(&account, GlobalParams {
          pending_requests: vector::empty<ObjectID>()
      });
    }

    public entry fun request_data(
      caller: &signer,
      url: vector<u8>,
      method: vector<u8>,
      headers: vector<u8>,
      body: vector<u8>,
      pick: vector<u8>,
      oracle: address
    ) acquires GlobalParams {
        let http_request = Oracles::build_request(url, method, headers, body);

        // If you do not want to pay for the Oracle to notify your contract, you can pass in option::none() as the argument.
        // We're passing the address and function identifier of the recipient address. in this from <module_name>::<function_name>
        let request_id = Oracles::new_request(caller, http_request, pick, oracle, Oracles::with_notify(@verity_test_foreign_module, b"example_caller::receive_data"));
        // let no_notify_request_id = Oracles::new_request(http_request, pick, oracle, Oracles::without_notify());
        let params = borrow_global_mut<GlobalParams>(@verity_test_foreign_module);
        vector::push_back(&mut params.pending_requests, request_id);
    }

    // This notify function is called by the Oracle.
    // ! It must not include parameters, or return arguments.
    public entry fun receive_data(caller: &signer) acquires GlobalParams {
      let caller_address = signer::address_of(caller);
      let params = borrow_global_mut<GlobalParams>(@verity_test_foreign_module);
      let pending_requests = params.pending_requests;

      let i = 0;
      while (i < vector::length(&pending_requests)) {
          let request_id = vector::borrow(&pending_requests, i);
          // Remove the fulfilled request from the pending_requests vector
          // This ensures unfulfilled requests are retained in the vector
          if (option::is_some(&Oracles::get_response(request_id))) {
              vector::remove(&mut params.pending_requests, i);
              // Decrement i to account for the removed element
              if (i > 0) {
                  i = i - 1;
              };

              // ? ------ OPTIONAL ------
              let request_url = Oracles::get_request_params_url(request_id);
              let request_method = Oracles::get_request_params_method(request_id);
              let response = Oracles::get_response(request_id);
              // For each fulfilment, emit an event
              let event_handle = EventHandle::new<RequestFulfilledEvent>(caller_address);
              emit_event<RequestFulfilledEvent>(&event_handle, RequestFulfilledEvent {
                request_url,
                request_method,
                response,
              });
              // \ ------ OPTIONAL ------
          };

          i = i + 1;
      };
    }
}
