module orchestrator_registry::registry {

    use std::option::{Self, Option};
    use std::vector;
    use moveos_std::event;
    use moveos_std::account;
    use std::string::{Self, String};
    use moveos_std::simple_map::{Self, SimpleMap};
    use moveos_std::tx_context;
    use moveos_std::string_utils;

    const NotOracleError: u64 = 1;

    struct SupportedURLMetadata has copy, drop, store {
        url_prefix: String,
        base_fee: u256,
        minimum_payload_length: u64,
        cost_per_token: u256,
    }

    struct GlobalParams has key {
        supported_urls: SimpleMap<address, vector<SupportedURLMetadata>>,
    }

    // Events
    struct URLSupportAdded has copy, drop {
        orchestrator: address,
        url: String,
        base_fee: u256,
        minimum_payload_length: u64,
        cost_per_token: u256
    }

    struct URLSupportRemoved has copy, drop {
        orchestrator: address,
        url: String
    }

    /// Compute the cost for an orchestrator request based on payload length
    public fun compute_cost(
        orchestrator: address,
        url: String,
        payload_length: u64
    ): Option<u256> {
        let supported_urls = &account::borrow_resource<GlobalParams>(@orchestrator_registry).supported_urls;

        let url = string_utils::to_lower_case(&url);
        if (simple_map::contains_key(supported_urls, &orchestrator)) {
            let orchestrator_urls = simple_map::borrow(supported_urls, &orchestrator) ;


            let i = 0;
            while (i < vector::length(orchestrator_urls)) {
                let orchestrator_url = vector::borrow(orchestrator_urls, i);
                let prefix = string::sub_string(&string_utils::to_lower_case(&orchestrator_url.url_prefix), 0,string::length(&url) );
                if (!(string::index_of(&url, &prefix) == string::length(&url))) {
                    let chargeable_token: u256 = ((orchestrator_url.minimum_payload_length as u256) - (payload_length as u256));
                    return option::some(orchestrator_url.base_fee + (chargeable_token * orchestrator_url.cost_per_token))
                };
                i = i + 1;
            }
        };
        return option::none()
    }

    /// Add support for a new URL endpoint with specified pricing parameters
    public fun add_supported_url(
        url_prefix: String,
        base_fee: u256,
        minimum_payload_length: u64,
        cost_per_token: u256
    ) {
        let sender = tx_context::sender();
        let global_params = account::borrow_mut_resource<GlobalParams>(@orchestrator_registry);
        
        // Initialize orchestrator's URL vector if it doesn't exist
        if (!simple_map::contains_key(&global_params.supported_urls, &sender)) {
            simple_map::add(&mut global_params.supported_urls, sender, vector::empty());
        };

        let orchestrator_urls = simple_map::borrow_mut(&mut global_params.supported_urls, &sender);
        let metadata = SupportedURLMetadata {
            url_prefix,
            base_fee,
            minimum_payload_length,
            cost_per_token
        };

        // Check if URL prefix already exists
        let i = 0;
        let len = vector::length(orchestrator_urls);
        let found = false;
        while (i < len) {
            let existing_metadata = vector::borrow_mut(orchestrator_urls, i);
            if (existing_metadata.url_prefix == url_prefix) {
                // Update existing metadata
                *existing_metadata = metadata;
                found = true;
                break
            };
            i = i + 1;
        };

        // If URL prefix not found, add new entry
        if (!found) {
            vector::push_back(orchestrator_urls, metadata);
        };

        // Emit event
        event::emit(URLSupportAdded {
            orchestrator: sender,
            url: url_prefix,
            base_fee,
            minimum_payload_length,
            cost_per_token
        });
    }

    /// Remove support for a URL endpoint
    public fun remove_supported_url(url_prefix: String) {
        let sender = tx_context::sender();
        let global_params = account::borrow_mut_resource<GlobalParams>(@orchestrator_registry);
        
        assert!(simple_map::contains_key(&global_params.supported_urls, &sender), NotOracleError);
        let orchestrator_urls = simple_map::borrow_mut(&mut global_params.supported_urls, &sender);
        
        let i = 0;
        let len = vector::length(orchestrator_urls);
        while (i < len) {
            let metadata = vector::borrow(orchestrator_urls, i);
            if (metadata.url_prefix == url_prefix) {
                vector::remove(orchestrator_urls, i);
                // Emit event
                event::emit(URLSupportRemoved {
                    orchestrator: sender,
                    url: url_prefix
                });
                break
            };
            i = i + 1;
        };
    }

    #[view]
    /// Get all supported URLs and their metadata for an orchestrator
    public fun get_supported_urls(orchestrator: address): vector<SupportedURLMetadata> {
        let global_params = account::borrow_resource<GlobalParams>(@orchestrator_registry);
        
        if (simple_map::contains_key(&global_params.supported_urls, &orchestrator)) {
            *simple_map::borrow(&global_params.supported_urls, &orchestrator)
        } else {
            vector::empty()
        }
    }

    #[test]
    fun test_add_supported_url() {
        // Test adding new URL support
        let url = string::utf8(b"https://api.example.com");
        add_supported_url(url, 100, 1000, 1);
        
        let urls = get_supported_urls(tx_context::sender());
        assert!(vector::length(&urls) == 1, 0);
        
        let metadata = vector::borrow(&urls, 0);
        assert!(metadata.url_prefix == url, 0);
        assert!(metadata.base_fee == 100, 0);
        assert!(metadata.minimum_payload_length == 1000, 0);
        assert!(metadata.cost_per_token == 1, 0);
    }

    #[test]
    fun test_update_existing_url() {
        // Test updating existing URL support
        let url = string::utf8(b"https://api.example.com");
        add_supported_url(url, 100, 1000, 1);
        add_supported_url(url, 200, 2000, 2);
        
        let urls = get_supported_urls(tx_context::sender());
        assert!(vector::length(&urls) == 1, 0);
        
        let metadata = vector::borrow(&urls, 0);
        assert!(metadata.base_fee == 200, 0);
        assert!(metadata.minimum_payload_length == 2000, 0);
        assert!(metadata.cost_per_token == 2, 0);
    }

    #[test]
    fun test_remove_supported_url() {
        // Test removing URL support
        let url = string::utf8(b"https://api.example.com");
        add_supported_url(url, 100, 1000, 1);
        
        remove_supported_url(url);
        let urls = get_supported_urls(tx_context::sender());
        assert!(vector::length(&urls) == 0, 0);
    }

    #[test]
    fun test_compute_cost() {
        // Test cost computation
        let url = string::utf8(b"https://api.example.com");
        add_supported_url(url, 100, 1000, 1);
        
        let cost = compute_cost(tx_context::sender(), url, 500);
        assert!(option::is_some(&cost), 0);
        assert!(option::extract(&mut cost) == 600, 0); // base_fee + (min_length - payload_length) * cost_per_token
    }

    #[test]
    fun test_compute_cost_nonexistent_url() {
        // Test cost computation for non-existent URL
        let url = string::utf8(b"https://nonexistent.com");
        let cost = compute_cost(tx_context::sender(), url, 500);
        assert!(option::is_none(&cost), 0);
    }

    #[test]
    #[expected_failure(abort_code = NotOracleError)]
    fun test_remove_url_non_oracle() {
        // Test removing URL as non-oracle
        let url = string::utf8(b"https://api.example.com");
        remove_supported_url(url);
    }
}