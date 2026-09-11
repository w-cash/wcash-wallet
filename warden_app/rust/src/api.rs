//! Flat types and functions exported to Dart by flutter_rust_bridge.

/// Immutable identity of the only network available to Wcash Warden.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct WardenNetworkIdentity {
    /// Human-readable product network name.
    pub network_name: String,
    /// BIP70/RPC chain identifier expected from the wallet service.
    pub rpc_chain_name: String,
    /// Currency ticker for valueless Testnet coins.
    pub ticker: String,
    /// Number of decimal places in one TWC.
    pub decimals: u8,
    /// Fixed TLS wallet service endpoint.
    pub endpoint: String,
    /// Wcash Testnet consensus branch ID in RPC display order.
    pub consensus_branch_id: String,
    /// Frozen genesis hash in conventional display order.
    pub genesis_hash: String,
    /// Isolated persistent-state namespace reserved for this app.
    pub storage_namespace: String,
    /// Prefix of private Wcash Testnet Unified Addresses.
    pub private_address_prefix: String,
    /// Prefix of transparent mining addresses.
    pub mining_address_prefix: String,
}

/// Public addresses derived for one Wcash Testnet account.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct WardenAddresses {
    /// ZIP-32 account index used for derivation.
    pub account_index: u32,
    /// Private Wcash Unified Address for Ironwood receipts.
    pub private_receive_address: String,
    /// Transparent P2PKH address for pool-compatible coinbase payouts.
    pub transparent_mining_address: String,
}

/// Result of attesting the fixed Wcash Testnet wallet endpoint.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct WardenEndpointAttestation {
    /// Exact endpoint that passed Wcash chain attestation.
    pub endpoint: String,
    /// Human-readable accepted network name.
    pub network_name: String,
    /// Accepted Wcash consensus branch ID.
    pub consensus_branch_id: String,
    /// Accepted frozen genesis hash.
    pub genesis_hash: String,
    /// Best chain height reported at attestation time.
    pub tip_height: u32,
    /// Best chain hash reported at attestation time.
    pub tip_hash: String,
}

/// Returns the compiled-in identity of Wcash Testnet.
#[flutter_rust_bridge::frb(sync)]
pub fn network_identity() -> WardenNetworkIdentity {
    let identity = rust_warden::network_identity();
    WardenNetworkIdentity {
        network_name: identity.network_name,
        rpc_chain_name: identity.rpc_chain_name,
        ticker: identity.ticker,
        decimals: identity.decimals,
        endpoint: identity.endpoint,
        consensus_branch_id: identity.consensus_branch_id,
        genesis_hash: identity.genesis_hash,
        storage_namespace: identity.storage_namespace,
        private_address_prefix: identity.private_address_prefix,
        mining_address_prefix: identity.mining_address_prefix,
    }
}

/// Attests the fixed TLS endpoint against Wcash Testnet identity.
///
/// The caller cannot provide an endpoint or select another network.
pub async fn attest_endpoint() -> Result<WardenEndpointAttestation, String> {
    rust_warden::attest_testnet_endpoint()
        .await
        .map(|attestation| WardenEndpointAttestation {
            endpoint: attestation.endpoint,
            network_name: attestation.network_name,
            consensus_branch_id: attestation.consensus_branch_id,
            genesis_hash: attestation.genesis_hash,
            tip_height: attestation.tip_height,
            tip_hash: attestation.tip_hash,
        })
        .map_err(|error| error.to_string())
}

/// Derives Wcash Testnet receive and mining addresses in memory.
///
/// The bridge does not persist or log the mnemonic. This Testnet-only preview
/// is not a wallet and must not be used with a phrase that protects real funds.
#[flutter_rust_bridge::frb(sync)]
pub fn derive_addresses(mnemonic: String, account_index: u32) -> Result<WardenAddresses, String> {
    rust_warden::derive_testnet_addresses_from_mnemonic(mnemonic, account_index)
        .map(|addresses| WardenAddresses {
            account_index: addresses.account_index,
            private_receive_address: addresses.private_receive_address,
            transparent_mining_address: addresses.transparent_mining_address,
        })
        .map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    const MNEMONIC: &str =
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

    #[test]
    fn bridge_identity_is_testnet_only() {
        let identity = network_identity();
        assert_eq!(identity.network_name, "Wcash Testnet");
        assert_eq!(identity.ticker, "TWC");
        assert_eq!(identity.decimals, 8);
        assert_eq!(
            identity.endpoint,
            "https://wallet-testnet.wcashexplorer.com"
        );
        assert_eq!(identity.storage_namespace, "wcashtestnet-v5");
    }

    #[test]
    fn bridge_derives_only_wcash_addresses() {
        let addresses = derive_addresses(MNEMONIC.to_owned(), 0).unwrap();
        assert!(addresses.private_receive_address.starts_with("wutest1"));
        assert!(addresses.transparent_mining_address.starts_with("WT"));
    }

    #[test]
    fn bridge_error_does_not_echo_secret_input() {
        let secret = "not a valid mnemonic and must not be repeated";
        let error = derive_addresses(secret.to_owned(), 0).unwrap_err();
        assert!(!error.contains(secret));
    }
}
