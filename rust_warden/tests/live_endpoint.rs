//! Opt-in verification against the deployed Wcash Testnet wallet service.

use rust_warden::{attest_testnet_endpoint, network_identity};

#[tokio::test]
#[ignore = "requires the deployed Wcash Testnet wallet service"]
async fn fixed_public_endpoint_attests_to_wcash_testnet() {
    let expected = network_identity();
    let attested = attest_testnet_endpoint()
        .await
        .expect("the fixed endpoint must attest as Wcash Testnet");

    assert_eq!(attested.endpoint, expected.endpoint);
    assert_eq!(attested.network_name, expected.network_name);
    assert_eq!(attested.consensus_branch_id, expected.consensus_branch_id);
    assert_eq!(attested.genesis_hash, expected.genesis_hash);
    assert_eq!(attested.tip_hash.len(), 64);
}
