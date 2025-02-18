/// Module for managing oracle registry and URL support in the Verity system.
/// This module handles registration of oracles, their supported URLs, and cost calculations.
module verity::registry {
    use moveos_std::signer;
    use moveos_std::event;
    use moveos_std::account;
    use moveos_std::simple_map::{Self, SimpleMap};
    use moveos_std::string_utils;
    use moveos_std::table::{Self, Table};

    use std::option::{Self, Option};
    use std::string::{Self, String};
    use std::vector;

    /// Error code when caller is not a registered oracle
    const NotOracleError: u64 = 2001;
    /// Error code when URL prefix is invalid or not found 
    const InvalidURLPrefixError: u64 = 2002;
    const OnlyOwnerError: u64 = 2003;


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
        cost_per_response_token: u256,
    }

    /// Global storage for oracle registry
    struct GlobalParams has key {
        /// Mapping of oracle addresses to their supported URLs
        supported_urls: SimpleMap<address, vector<SupportedURLMetadata>>,
    }

    /// New global parameters structure using Table
    struct GlobalParamsV2 has key {
        supported_urls: Table<address, vector<SupportedURLMetadata>>
    }
    /// Initialize the registry module
    fun init() {
        init_v1();
        let module_signer = signer::module_signer<GlobalParamsV2>();
        migrate_to_v2(&module_signer);
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

    fun init_v1() {
        let module_signer = signer::module_signer<GlobalParams>();
        account::move_resource_to(&module_signer, GlobalParams {
            supported_urls: simple_map::new(),
        });
    }


    /// Migration function to move from V1 to V2
    public entry fun migrate_to_v2(account: &signer) {
        assert!(signer::address_of(account) == @verity, OnlyOwnerError);
        
        // Unpack old GlobalParams
        let GlobalParams { supported_urls: old_supported_urls } = account::move_resource_from<GlobalParams>(@verity);
        
        // Create new table for GlobalParamsV2
        let new_supported_urls = table::new<address, vector<SupportedURLMetadata>>();
        
        // Migrate data from SimpleMap to Table
        let keys = simple_map::keys(&old_supported_urls);
        let values = simple_map::values(&old_supported_urls);
        let i = 0;
        let len = vector::length(&keys);
        while (i < len) {
            let key = vector::borrow(&keys, i);
            let value = vector::borrow(&values, i);
            table::add(&mut new_supported_urls, *key, *value);
            i = i + 1;
        };
        
        // Move GlobalParamsV2
        account::move_resource_to(account, GlobalParamsV2 {
            supported_urls: new_supported_urls,
        });
    }

    // Compute the cost for an orchestrator request based on payload length
    // Returns Option<u256> - Some(cost) if URL is supported, None otherwise
    #[view]
    public fun estimated_cost(
        orchestrator: address,
        url: String,
        payload_length: u64,
        response_length: u64
    ): Option<u256> {
        let global_params = account::borrow_resource<GlobalParamsV2>(@verity);
        let supported_urls = &global_params.supported_urls;

        let url = string_utils::to_lower_case(&url);
        // Is the Orchestrator registered as an Oracle?
        if (table::contains(supported_urls, orchestrator)) {
            let orchestrator_urls = table::borrow(supported_urls, orchestrator);

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
                        (orchestrator_url.cost_per_response_token * (response_length as u256))
                    )
                };
                i = i + 1;
            }
        };
        option::none()
    }

    /// Add support for a new URL endpoint with specified pricing parameters
    /// If URL already exists, updates the existing metadata
    public entry fun  add_supported_url(
        caller: &signer,
        url_prefix: String,
        base_fee: u256,
        minimum_payload_length: u64,
        cost_per_payload_token: u256,
        cost_per_response_token: u256
    ) {
        let sender = signer::address_of(caller);
        let global_params = account::borrow_mut_resource<GlobalParamsV2>(@verity);
        
        // Initialize orchestrator's URL vector if it doesn't exist
        if (!table::contains(&global_params.supported_urls, sender)) {
            table::add(&mut global_params.supported_urls, sender, vector::empty());
        };

        let orchestrator_urls = table::borrow_mut(&mut global_params.supported_urls, sender);
        let metadata = SupportedURLMetadata {
            url_prefix,
            base_fee,
            minimum_payload_length,
            cost_per_payload_token,
            cost_per_response_token
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
    public  entry fun remove_supported_url(
        caller: &signer,
        url_prefix: String
    ) {
        let sender = signer::address_of(caller);
        let global_params = account::borrow_mut_resource<GlobalParamsV2>(@verity);
        
        assert!(table::contains(&global_params.supported_urls, sender), NotOracleError);
        let orchestrator_urls = table::borrow_mut(&mut global_params.supported_urls, sender);
        
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
        let global_params = account::borrow_resource<GlobalParamsV2>(@verity);
        
        if (table::contains(&global_params.supported_urls, orchestrator)) {
            *table::borrow(&global_params.supported_urls, orchestrator)
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