// Copyright (c) Usher Labs
// SPDX-License-Identifier: LGPL-2.1

// ? This module is an example caller used to demonstrate how to deploy Contracts on Rooch that integrate with Verity Move Oracles.
// ? Please keep aware of the OPTIONAL section in this module.
module verity_test_foreign_module::example_caller {
    use moveos_std::event;
    use moveos_std::account;
    use moveos_std::object::{ObjectID};
    use std::option::{Self, Option};
    use std::vector;
    use std::string::String;
    use verity::oracles::{Self as Oracles};

    struct GlobalParams has key {
      pending_requests: vector<ObjectID>,
    }

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
    fun init(){
      // let params = account::borrow_mut_resource<GlobalParams>(@verity_test_foreign_module); // account::borrow_mut_resource  in init throws an error on deployment
      // params.pending_requests = vector::empty<ObjectID>();
      let signer = moveos_std::signer::module_signer<GlobalParams>();
      account::move_resource_to(&signer, GlobalParams { pending_requests: vector::empty<ObjectID>() });
    }

    public entry fun request_data(
        url: String,
        method: String,
        headers: String,
        body: String,
        pick: String,
        oracle: address
    ) {
        let http_request = Oracles::build_request(url, method, headers, body);

        // We're passing the address and function identifier of the recipient address. in this from <module_name>::<function_name>
        // If you do not want to pay for the Oracle to notify your contract, you can pass in option::none() as the argument.
        let request_id = Oracles::new_request(http_request, pick, oracle, Oracles::with_notify(@verity_test_foreign_module, b"example_caller::receive_data"));
        // let no_notify_request_id = Oracles::new_request(http_request, pick, oracle, Oracles::without_notify());
        let params = account::borrow_mut_resource<GlobalParams>(@verity_test_foreign_module);
        vector::push_back(&mut params.pending_requests, request_id);
    }

    // This notify function is called by the Oracle.
    // ! It must not include parameters, or return arguments.
    public entry fun receive_data() {
        let params = account::borrow_mut_resource<GlobalParams>(@verity_test_foreign_module);
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
                event::emit(RequestFulfilledEvent {
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
