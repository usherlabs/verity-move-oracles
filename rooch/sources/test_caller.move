module verity_test_foreign_module::test_caller {
    use moveos_std::event;
    use moveos_std::tx_context;
    use moveos_std::signer;
    use moveos_std::account;
    use moveos_std::object::{Self, Object, ObjectID};
    use std::vector;
    use std::string::String;
    use verity::oracles::{Self as Oracles, RequestResponsePair};

    struct RequestFulfilledEvent has copy, drop {
        pair: RequestResponsePair,
    }

    public entry fun request_data(
        url: String,
        method: String,
        headers: String,
        body: String,
        pick: String,
        oracle: address
    ): ObjectID {
        let http_request = Oracles::build_request(url, method, headers, body);

        // We're passing the address of the module as the recipient.
        Oracles::new_request(http_request, pick, oracle, @verity_test_foreign_module)
    }

    // This is a special function with a dedicated name that Oracles will scan for and call.
    public entry fun vo_receive() {
        let fulfilments = Oracles::consume();
        let i = 0;
        while (i < vector::length(&fulfilments)) {
            let pair = vector::borrow(&fulfilments, i);
            // For each fulfilment, emit an event
            event::emit(RequestFulfilledEvent {
              pair,
            });
            i = i + 1;
        }
    }
}
