import { test; suite } = "mo:test";
import ChainRegistry "../src/icp-intents-lib/chains/ChainRegistry";
import ChainTypes "../src/icp-intents-lib/chains/ChainTypes";
import Principal "mo:base/Principal";

suite("ChainRegistry - Initialization", func() {
  test("init creates empty registry", func() {
    let state = ChainRegistry.init();

    let chain = ChainRegistry.getChain(state, "ethereum");
    assert(chain == null);
  });
});

suite("ChainRegistry - Chain Registration", func() {
  test("registerChain stores EVM chain", func() {
    let state = ChainRegistry.init();
    let evmChain : ChainTypes.Chain = #EVM({
      name = "ethereum";
      chain_id = 1;
      network = "mainnet";
      rpc_urls = ?["https://eth.llamarpc.com"];
    });

    ChainRegistry.registerChain(state, "ethereum", evmChain);

    let retrieved = ChainRegistry.getChain(state, "ethereum");
    switch (retrieved) {
      case (?chain) {
        switch (chain) {
          case (#EVM(evm)) {
            assert(evm.name == "ethereum");
            assert(evm.chain_id == 1);
          };
          case (_) { assert(false) };
        };
      };
      case null { assert(false) };
    };
  });

  test("registerChain stores Hoosat chain", func() {
    let state = ChainRegistry.init();
    let hoosatChain : ChainTypes.Chain = #Hoosat({
      network = "mainnet";
      rpc_url = "https://api.hoosat.fi";
      min_confirmations = 6;
    });

    ChainRegistry.registerChain(state, "hoosat", hoosatChain);

    let retrieved = ChainRegistry.getChain(state, "hoosat");
    switch (retrieved) {
      case (?chain) {
        switch (chain) {
          case (#Hoosat(h)) {
            assert(h.network == "mainnet");
            assert(h.min_confirmations == 6);
          };
          case (_) { assert(false) };
        };
      };
      case null { assert(false) };
    };
  });

  test("registerChain stores Bitcoin chain", func() {
    let state = ChainRegistry.init();
    let btcChain : ChainTypes.Chain = #Bitcoin({
      network = "mainnet";
      min_confirmations = 6;
    });

    ChainRegistry.registerChain(state, "bitcoin", btcChain);

    let retrieved = ChainRegistry.getChain(state, "bitcoin");
    switch (retrieved) {
      case (?chain) {
        switch (chain) {
          case (#Bitcoin(btc)) {
            assert(btc.network == "mainnet");
            assert(btc.min_confirmations == 6);
          };
          case (_) { assert(false) };
        };
      };
      case null { assert(false) };
    };
  });

  test("registerChain stores Custom chain", func() {
    let state = ChainRegistry.init();
    let customChain : ChainTypes.Chain = #Custom({
      name = "icp";
      network = "mainnet";
      verification_canister = null;
      metadata = null;
    });

    ChainRegistry.registerChain(state, "icp", customChain);

    let retrieved = ChainRegistry.getChain(state, "icp");
    switch (retrieved) {
      case (?chain) {
        switch (chain) {
          case (#Custom(c)) {
            assert(c.name == "icp");
          };
          case (_) { assert(false) };
        };
      };
      case null { assert(false) };
    };
  });

  test("registerChain overwrites existing chain", func() {
    let state = ChainRegistry.init();
    let chain1 : ChainTypes.Chain = #EVM({
      name = "ethereum";
      chain_id = 1;
      network = "mainnet";
      rpc_urls = ?["https://old-rpc.com"];
    });

    ChainRegistry.registerChain(state, "ethereum", chain1);

    let chain2 : ChainTypes.Chain = #EVM({
      name = "ethereum";
      chain_id = 1;
      network = "mainnet";
      rpc_urls = ?["https://new-rpc.com"];
    });

    ChainRegistry.registerChain(state, "ethereum", chain2);

    let retrieved = ChainRegistry.getChain(state, "ethereum");
    switch (retrieved) {
      case (?chain) {
        switch (chain) {
          case (#EVM(evm)) {
            switch (evm.rpc_urls) {
              case (?urls) {
                assert(urls[0] == "https://new-rpc.com");
              };
              case null { assert(false) };
            };
          };
          case (_) { assert(false) };
        };
      };
      case null { assert(false) };
    };
  });
});

suite("ChainRegistry - Chain Lookup", func() {
  test("getChain returns None for unregistered chain", func() {
    let state = ChainRegistry.init();

    let chain = ChainRegistry.getChain(state, "nonexistent");
    assert(chain == null);
  });

  test("getChain is case-insensitive", func() {
    let state = ChainRegistry.init();
    let evmChain : ChainTypes.Chain = #EVM({
      name = "ethereum";
      chain_id = 1;
      network = "mainnet";
      rpc_urls = ?["https://eth.llamarpc.com"];
    });

    ChainRegistry.registerChain(state, "ethereum", evmChain);

    // Test various casings
    let lower = ChainRegistry.getChain(state, "ethereum");
    let upper = ChainRegistry.getChain(state, "ETHEREUM");
    let mixed = ChainRegistry.getChain(state, "EtHeReUm");

    assert(lower != null);
    assert(upper != null);
    assert(mixed != null);
  });

  test("isSupported returns true for registered chain", func() {
    let state = ChainRegistry.init();
    let evmChain : ChainTypes.Chain = #EVM({
      name = "ethereum";
      chain_id = 1;
      network = "mainnet";
      rpc_urls = ?["https://eth.llamarpc.com"];
    });

    ChainRegistry.registerChain(state, "ethereum", evmChain);

    assert(ChainRegistry.isSupported(state, "ethereum"));
  });

  test("isSupported returns false for unregistered chain", func() {
    let state = ChainRegistry.init();

    assert(not ChainRegistry.isSupported(state, "nonexistent"));
  });

  test("getChainBySpec returns chain for valid EVM spec", func() {
    let state = ChainRegistry.init();
    let evmChain : ChainTypes.Chain = #EVM({
      name = "ethereum";
      chain_id = 1;
      network = "mainnet";
      rpc_urls = ?["https://eth.llamarpc.com"];
    });

    ChainRegistry.registerChain(state, "ethereum", evmChain);

    let spec : ChainTypes.ChainSpec = {
      chain = "ethereum";
      chain_id = ?1;
      token = "ETH";
      network = "mainnet";
    };

    let chain = ChainRegistry.getChainBySpec(state, spec);
    assert(chain != null);
  });

  test("getChainBySpec returns None for invalid spec", func() {
    let state = ChainRegistry.init();

    let spec : ChainTypes.ChainSpec = {
      chain = "nonexistent";
      chain_id = null;
      token = "NONE";
      network = "mainnet";
    };

    let chain = ChainRegistry.getChainBySpec(state, spec);
    assert(chain == null);
  });
});

suite("ChainRegistry - Chain Validation", func() {
  test("validateSpec succeeds for registered EVM chain with matching chain_id", func() {
    let state = ChainRegistry.init();
    let evmChain : ChainTypes.Chain = #EVM({
      name = "ethereum";
      chain_id = 1;
      network = "mainnet";
      rpc_urls = ?["https://eth.llamarpc.com"];
    });

    ChainRegistry.registerChain(state, "ethereum", evmChain);

    let spec : ChainTypes.ChainSpec = {
      chain = "ethereum";
      chain_id = ?1;
      token = "ETH";
      network = "mainnet";
    };

    let result = ChainRegistry.validateSpec(state, spec);
    switch (result) {
      case (#ok(chain)) {
        switch (chain) {
          case (#EVM(evm)) {
            assert(evm.chain_id == 1);
          };
          case (_) { assert(false) };
        };
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("validateSpec fails for EVM chain with mismatched chain_id", func() {
    let state = ChainRegistry.init();
    let evmChain : ChainTypes.Chain = #EVM({
      name = "ethereum";
      chain_id = 1;
      network = "mainnet";
      rpc_urls = ?["https://eth.llamarpc.com"];
    });

    ChainRegistry.registerChain(state, "ethereum", evmChain);

    let spec : ChainTypes.ChainSpec = {
      chain = "ethereum";
      chain_id = ?137; // Wrong chain_id (Polygon)
      token = "ETH";
      network = "mainnet";
    };

    let result = ChainRegistry.validateSpec(state, spec);
    switch (result) {
      case (#ok(_)) { assert(false) };
      case (#err(#InvalidChain(_))) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });

  test("validateSpec succeeds for EVM chain without chain_id in spec", func() {
    let state = ChainRegistry.init();
    let evmChain : ChainTypes.Chain = #EVM({
      name = "ethereum";
      chain_id = 1;
      network = "mainnet";
      rpc_urls = ?["https://eth.llamarpc.com"];
    });

    ChainRegistry.registerChain(state, "ethereum", evmChain);

    let spec : ChainTypes.ChainSpec = {
      chain = "ethereum";
      chain_id = null; // No chain_id specified
      token = "ETH";
      network = "mainnet";
    };

    let result = ChainRegistry.validateSpec(state, spec);
    switch (result) {
      case (#ok(_)) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });

  test("validateSpec fails for unregistered chain", func() {
    let state = ChainRegistry.init();

    let spec : ChainTypes.ChainSpec = {
      chain = "nonexistent";
      chain_id = null;
      token = "NONE";
      network = "mainnet";
    };

    let result = ChainRegistry.validateSpec(state, spec);
    switch (result) {
      case (#ok(_)) { assert(false) };
      case (#err(#ChainNotSupported(_))) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });

  test("validateSpec succeeds for non-EVM chains", func() {
    let state = ChainRegistry.init();
    let hoosatChain : ChainTypes.Chain = #Hoosat({
      network = "mainnet";
      rpc_url = "https://api.hoosat.fi";
      min_confirmations = 6;
    });

    ChainRegistry.registerChain(state, "hoosat", hoosatChain);

    let spec : ChainTypes.ChainSpec = {
      chain = "hoosat";
      chain_id = ?999; // chain_id validation only applies to EVM
      token = "HST";
      network = "mainnet";
    };

    let result = ChainRegistry.validateSpec(state, spec);
    switch (result) {
      case (#ok(_)) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });
});

suite("ChainRegistry - Multiple Chains", func() {
  test("can register and retrieve multiple chains", func() {
    let state = ChainRegistry.init();

    let eth : ChainTypes.Chain = #EVM({
      name = "ethereum";
      chain_id = 1;
      network = "mainnet";
      rpc_urls = ?["https://eth.llamarpc.com"];
    });

    let polygon : ChainTypes.Chain = #EVM({
      name = "polygon";
      chain_id = 137;
      network = "mainnet";
      rpc_urls = ?["https://polygon-rpc.com"];
    });

    let hoosat : ChainTypes.Chain = #Hoosat({
      network = "mainnet";
      rpc_url = "https://api.hoosat.fi";
      min_confirmations = 6;
    });

    ChainRegistry.registerChain(state, "ethereum", eth);
    ChainRegistry.registerChain(state, "polygon", polygon);
    ChainRegistry.registerChain(state, "hoosat", hoosat);

    assert(ChainRegistry.isSupported(state, "ethereum"));
    assert(ChainRegistry.isSupported(state, "polygon"));
    assert(ChainRegistry.isSupported(state, "hoosat"));
  });
});

suite("ChainRegistry - Verifier Registration", func() {
  test("registerVerifier stores verifier principal", func() {
    let state = ChainRegistry.init();
    let verifier = Principal.fromText("aaaaa-aa");

    ChainRegistry.registerVerifier(state, "ethereum", verifier);

    let retrieved = ChainRegistry.getVerifier(state, "ethereum");
    switch (retrieved) {
      case (?v) { assert(Principal.equal(v, verifier)) };
      case null { assert(false) };
    };
  });

  test("getVerifier returns None for unregistered verifier", func() {
    let state = ChainRegistry.init();

    let verifier = ChainRegistry.getVerifier(state, "nonexistent");
    assert(verifier == null);
  });

  test("registerVerifier is case-insensitive", func() {
    let state = ChainRegistry.init();
    let verifier = Principal.fromText("aaaaa-aa");

    ChainRegistry.registerVerifier(state, "ethereum", verifier);

    let retrieved = ChainRegistry.getVerifier(state, "ETHEREUM");
    assert(retrieved != null);
  });
});
