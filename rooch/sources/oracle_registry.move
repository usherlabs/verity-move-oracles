/// Module for managing oracle registry and URL support in the Verity system.
/// This module handles registration of oracles, their supported URLs, and cost calculations.
module verity::registry {
    use std::option::{Self, Option};
    use moveos_std::signer;
    use std::vector;
    use moveos_std::event;
    use moveos_std::account;
    use std::string::{Self, String};
    use moveos_std::simple_map::{Self, SimpleMap};
    use moveos_std::string_utils;

    /// Error code when caller is not a registered oracle
    const NotOracleError: u64 = 2001;
    /// Error code when URL prefix is invalid or not found 
    const InvalidURLPrefixError: u64 = 2002;

    /// Metadata structure for supported URL endpoints
    struct SupportedURLMetadata has copy, drop, store {
        /// The URL prefix that this oracle supports
        url_prefix: String,
        /// Base fee charged for requests to this endpoint
        base_fee: u256,
        /// Minimum payload length before additional charges apply
        minimum_payload_length: u64,
        /// Cost per token for payload beyond minimum length
        cost_per_payload_token: u256,
        /// Cost per token for response data
        cost_per_respond_token: u256,
    }

    /// Global storage for oracle registry
    struct GlobalParams has key {
        /// Mapping of oracle addresses to their supported URLs
        supported_urls: SimpleMap<address, vector<SupportedURLMetadata>>,
    }

    /// Initialize the registry module
    fun init() {
        let module_signer = signer::module_signer<GlobalParams>();
        account::move_resource_to(&module_signer, GlobalParams {
            supported_urls: simple_map::new(),
        });
    }

    #[test_only]
    /// Initialize the registry module for testing
    public fun init_for_test() {
        init();
    }

    // Events
    /// Event emitted when URL support is added
    struct URLSupportAdded has copy, drop {
        orchestrator: address,
        url: String,
        base_fee: u256,
        minimum_payload_length: u64,
        cost_per_payload_token: u256
    }

    /// Event emitted when URL support is removed
    struct URLSupportRemoved has copy, drop {
        orchestrator: address,
        url: String
    }

    // Compute the cost for an orchestrator request based on payload length
    // Returns Option<u256> - Some(cost) if URL is supported, None otherwise
    #[view]
    public fun estimated_cost(
        orchestrator: address,
        url: String,
        payload_length: u64,
        respond_length: u64
    ): Option<u256> {
        let supported_urls = &account::borrow_resource<GlobalParams>(@verity).supported_urls;

        let url = string_utils::to_lower_case(&url);
        // Is the Orchestrator registered as an Oracle?
        if (simple_map::contains_key(supported_urls, &orchestrator)) {
            let orchestrator_urls = simple_map::borrow(supported_urls, &orchestrator);

            let i = 0;
            while (i < vector::length(orchestrator_urls)) {
                let orchestrator_url = vector::borrow(orchestrator_urls, i);
                let prefix = string_utils::to_lower_case(&orchestrator_url.url_prefix);
                // if index is 0 then prefix is a prefix of URL since its at index 0
                if ((string::index_of(&url, &prefix) == 0)) {
                    if (orchestrator_url.minimum_payload_length > payload_length) {
                        return option::none()
                    };
                    // The minimum_payload_length covers for metadata associated request payload.
                    let chargeable_token: u256 = ((payload_length as u256) - (orchestrator_url.minimum_payload_length as u256));
                    return option::some(
                        orchestrator_url.base_fee + 
                        (chargeable_token * orchestrator_url.cost_per_payload_token) + 
                        (orchestrator_url.cost_per_respond_token * (respond_length as u256))
                    )
                };
                i = i + 1;
            }
        };
        option::none()
    }

    /// Add support for a new URL endpoint with specified pricing parameters
    /// If URL already exists, updates the existing metadata
    public fun add_supported_url(
        caller: &signer,
        url_prefix: String,
        base_fee: u256,
        minimum_payload_length: u64,
        cost_per_payload_token: u256,
        cost_per_respond_token: u256
    ) {
        let sender = signer::address_of(caller);
        let global_params = account::borrow_mut_resource<GlobalParams>(@verity);
        
        // Initialize orchestrator's URL vector if it doesn't exist
        if (!simple_map::contains_key(&global_params.supported_urls, &sender)) {
            simple_map::add(&mut global_params.supported_urls, sender, vector::empty());
        };

        let orchestrator_urls = simple_map::borrow_mut(&mut global_params.supported_urls, &sender);
        let metadata = SupportedURLMetadata {
            url_prefix,
            base_fee,
            minimum_payload_length,
            cost_per_payload_token,
            cost_per_respond_token
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
            cost_per_payload_token
        });
    }

    /// Remove support for a URL endpoint
    /// Aborts if URL is not found or caller is not the oracle
    public fun remove_supported_url(
        caller: &signer,
        url_prefix: String
    ) {
        let sender = signer::address_of(caller);
        let global_params = account::borrow_mut_resource<GlobalParams>(@verity);
        
        assert!(simple_map::contains_key(&global_params.supported_urls, &sender), NotOracleError);
        let orchestrator_urls = simple_map::borrow_mut(&mut global_params.supported_urls, &sender);
        
        let i = 0;
        let len = vector::length(orchestrator_urls);
        let found = false;
        while (i < len) {
            let metadata = vector::borrow(orchestrator_urls, i);
            if (metadata.url_prefix == url_prefix) {
                vector::remove(orchestrator_urls, i);
                found = true;
                event::emit(URLSupportRemoved {
                    orchestrator: sender,
                    url: url_prefix
                });
                break
            };
            i = i + 1;
        };
        // Ensure URL was actually found and removed
        assert!(found, InvalidURLPrefixError);
    }

    #[view]
    /// Get all supported URLs and their metadata for an orchestrator
    /// Returns empty vector if orchestrator not found
    public fun get_supported_urls(orchestrator: address): vector<SupportedURLMetadata> {
        let global_params = account::borrow_resource<GlobalParams>(@verity);
        
        if (simple_map::contains_key(&global_params.supported_urls, &orchestrator)) {
            *simple_map::borrow(&global_params.supported_urls, &orchestrator)
        } else {
            vector::empty()
        }
    }
}

#[test_only]
module verity::test_registry {
    use std::string;
    use moveos_std::signer;
    use std::option;
    use std::vector;
    use verity::registry;
    
    struct Test has key {}

    #[test]
    fun test_add_supported_url() {
        // Test adding a new supported URL
        let test = signer::module_signer<Test>();
        registry::init_for_test();
        
        // Test adding new URL support
        let url = string::utf8(b"https://api.example.com");
        registry::add_supported_url(&test, url, 100, 0, 1, 0);
        
        let urls = registry::get_supported_urls(signer::address_of(&test));
        assert!(vector::length(&urls) == 1, 0);
        
        let cost = registry::estimated_cost(signer::address_of(&test), url, 500, 0);
        assert!(option::is_some(&cost), 0);
        assert!(option::extract(&mut cost) == 600, 0); // base_fee + (min_length - payload_length) * cost_per_payload_token
    }

    #[test]
    fun test_update_existing_url() {
        // Test updating an existing URL
        let test = signer::module_signer<Test>();
        registry::init_for_test();

        let url = string::utf8(b"https://api.example.com");
        
        // Add initial URL support with base parameters
        registry::add_supported_url(&test, url, 100, 50, 1, 2);
        
        // Verify initial parameters
        let urls = registry::get_supported_urls(signer::address_of(&test));
        assert!(vector::length(&urls) == 1, 0);
        
        let initial_cost = registry::estimated_cost(signer::address_of(&test), url, 100, 200);
        assert!(option::is_some(&initial_cost), 1);
        // Cost should be: base_fee(100) + (100-50)*1 + 200*2 = 550
        assert!(option::destroy_some(initial_cost) == 550, 2);
        
        // Update URL with new parameters
        registry::add_supported_url(&test, url, 200, 100, 2, 4);
        
        // Verify updated parameters
        let urls = registry::get_supported_urls(signer::address_of(&test));
        assert!(vector::length(&urls) == 1, 3);
        
        let updated_cost = registry::estimated_cost(signer::address_of(&test), url, 150, 100);
        assert!(option::is_some(&updated_cost), 4);
        // New cost should be: base_fee(200) + (150-100)*2 + 100*4 = 700
        assert!(option::destroy_some(updated_cost) == 700, 5);
    }

    #[test]
    fun test_remove_supported_url() {
        // Test removing a supported URL
        let test = signer::module_signer<Test>();
        registry::init_for_test();
        
        // Test removing URL support
        let url = string::utf8(b"https://api.example.com");
        registry::add_supported_url(&test, url, 100, 0, 1, 0);
        
        let urls = registry::get_supported_urls(signer::address_of(&test));
        assert!(vector::length(&urls) == 1, 1);
        
        registry::remove_supported_url(&test, url);
        let urls = registry::get_supported_urls(signer::address_of(&test));
        assert!(vector::length(&urls) == 0, 0);
    }

    #[test]
    fun test_compute_cost() {
        // Test cost computation for supported URL
        let test = signer::module_signer<Test>();
        registry::init_for_test();
        
        // Test cost computation
        let url = string::utf8(b"https://api.example.com");
        registry::add_supported_url(&test, url, 100, 0, 1, 0);
        
        let cost = registry::estimated_cost(signer::address_of(&test), url, 500, 0);
        assert!(option::is_some(&cost), 0);
        assert!(option::extract(&mut cost) == 600, 0); // base_fee + (min_length - payload_length) * cost_per_payload_token
    }

    #[test]
    fun test_compute_cost_nonexistent_url() {
        // Test cost computation for non-existent URL
        let test = signer::module_signer<Test>();
        registry::init_for_test();
        
        // Test cost computation for non-existent URL
        let url = string::utf8(b"https://nonexistent.com");
        let cost = registry::estimated_cost(signer::address_of(&test), url, 500, 0);
        assert!(option::is_none(&cost), 0);
    }
}