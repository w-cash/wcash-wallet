//! Narrow, Testnet-only core for the future Wcash Warden Flutter bridge.
//!
//! The crate intentionally has no dependency on the existing Vizor Rust bridge
//! and is not wired into Cargokit. Its API cannot select another endpoint or
//! network and cannot construct, sign, or broadcast transactions.

use bip39::{Language, Mnemonic};
use secrecy::SecretVec;
use thiserror::Error;
use wcash_wallet::{
    derive_wallet_spending_key, encode_orchard_receiver, encode_transparent_coinbase_receiver,
    AttestedWcashClient, WalletNetwork,
};
use zeroize::Zeroizing;

const ENDPOINT: &str = "https://wallet-testnet.wcashexplorer.com";
const NETWORK_NAME: &str = "Wcash Testnet";
const RPC_CHAIN_NAME: &str = "test";
const STORAGE_NAMESPACE: &str = "wcashtestnet-v5";
const TICKER: &str = "TWC";
const DECIMALS: u8 = 8;
const BRANCH_ID: &str = "b3cfd27e";
const GENESIS_HASH: &str = "0271b5b0a10b2838f43cccdec9ca2f72aa72a7c103830082bac8f82f47f0593a";
const PRIVATE_ADDRESS_PREFIX: &str = "wutest1";
const MINING_ADDRESS_PREFIX: &str = "WT";

/// Flat, immutable identity of the only network this crate can access.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NetworkIdentity {
    /// Human-readable network name.
    pub network_name: String,
    /// Chain name the Wcash wallet gRPC endpoint must report.
    pub rpc_chain_name: String,
    /// Currency ticker for valueless Testnet coins.
    pub ticker: String,
    /// Number of decimal places in one TWC.
    pub decimals: u8,
    /// Fixed TLS wallet service endpoint.
    pub endpoint: String,
    /// Wcash Testnet V6 consensus branch identifier in RPC display order.
    pub consensus_branch_id: String,
    /// Frozen genesis block identifier in conventional display order.
    pub genesis_hash: String,
    /// Persistent network namespace used to isolate Testnet wallet state.
    pub storage_namespace: String,
    /// Prefix of private Wcash Testnet Unified Addresses.
    pub private_address_prefix: String,
    /// Prefix of transparent Wcash Testnet mining addresses.
    pub mining_address_prefix: String,
}

/// Public addresses derived for one Wcash Testnet account.
///
/// This value contains no mnemonic, seed, viewing key, or spending key.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DerivedAddresses {
    /// ZIP-32 account index used for derivation.
    pub account_index: u32,
    /// Private Wcash Unified Address for Ironwood receipts.
    pub private_receive_address: String,
    /// Transparent P2PKH address for pool-compatible coinbase payouts.
    pub transparent_mining_address: String,
}

/// Result of attesting the fixed Wcash Testnet wallet service.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EndpointAttestation {
    /// Exact TLS endpoint that passed Wcash chain attestation.
    pub endpoint: String,
    /// Network identity accepted by the attested wallet client.
    pub network_name: String,
    /// Consensus branch expected after genesis.
    pub consensus_branch_id: String,
    /// Frozen Wcash Testnet genesis block identifier.
    pub genesis_hash: String,
    /// Height of the service's best chain tip at attestation time.
    pub tip_height: u32,
    /// Identifier of the service's best chain tip in display order.
    pub tip_hash: String,
}

/// Errors exposed by the narrow Warden bridge seam.
///
/// Variants intentionally carry no caller-provided mnemonic or other secret
/// material and are safe to surface across a future FFI boundary.
#[derive(Clone, Copy, Debug, Eq, Error, PartialEq)]
pub enum WardenError {
    /// The supplied phrase is not a checksummed English BIP-39 mnemonic.
    #[error("invalid English BIP-39 mnemonic")]
    InvalidMnemonic,
    /// The account index is outside the valid ZIP-32 range.
    #[error("account index must be below 2^31")]
    InvalidAccount,
    /// Wcash Testnet keys or addresses could not be derived.
    #[error("could not derive Wcash Testnet addresses")]
    AddressDerivation,
    /// The fixed public service failed transport or Wcash chain attestation.
    #[error("Wcash Testnet endpoint attestation failed")]
    EndpointAttestation,
    /// The pinned wallet dependency disagrees with the frozen app identity.
    #[error("pinned Wcash network identity does not match Warden")]
    IdentityMismatch,
}

/// Returns the frozen identity of the only network available to Warden.
pub fn network_identity() -> NetworkIdentity {
    NetworkIdentity {
        network_name: NETWORK_NAME.to_owned(),
        rpc_chain_name: RPC_CHAIN_NAME.to_owned(),
        ticker: TICKER.to_owned(),
        decimals: DECIMALS,
        endpoint: ENDPOINT.to_owned(),
        consensus_branch_id: BRANCH_ID.to_owned(),
        genesis_hash: GENESIS_HASH.to_owned(),
        storage_namespace: STORAGE_NAMESPACE.to_owned(),
        private_address_prefix: PRIVATE_ADDRESS_PREFIX.to_owned(),
        mining_address_prefix: MINING_ADDRESS_PREFIX.to_owned(),
    }
}

/// Derives Wcash Testnet receive and mining addresses from an English BIP-39
/// mnemonic using the standard empty BIP-39 passphrase.
///
/// The owned phrase is wrapped in zeroizing storage immediately. Parsed
/// mnemonic and seed material are also cleared on drop. This function does not
/// persist or log secret material.
pub fn derive_testnet_addresses_from_mnemonic(
    mnemonic: String,
    account_index: u32,
) -> Result<DerivedAddresses, WardenError> {
    // Take zeroizing ownership before any validation can return. Even an
    // unrelated invalid account index must not leave the phrase's heap buffer
    // to an ordinary `String` drop.
    let phrase = Zeroizing::new(mnemonic);
    if account_index >= (1 << 31) {
        return Err(WardenError::InvalidAccount);
    }

    let parsed = Mnemonic::parse_in(Language::English, phrase.as_str())
        .map_err(|_| WardenError::InvalidMnemonic)?;
    let bip39_seed = Zeroizing::new(parsed.to_seed_normalized(""));
    let master_seed = SecretVec::new(bip39_seed[..].to_vec());

    derive_addresses_from_seed(&master_seed, account_index)
}

/// Connects only to the compiled-in TLS service and requires its chain name,
/// height-aware branch ID, and exact height-zero hash to match Wcash Testnet.
///
/// A successful return is proof that the endpoint passed the attestation
/// implemented by the exact pinned `wcash-wallet` revision. Failure returns a
/// stable non-secret error without exposing transport internals.
pub async fn attest_testnet_endpoint() -> Result<EndpointAttestation, WardenError> {
    verify_pinned_identity()?;

    let mut client = AttestedWcashClient::connect(ENDPOINT, WalletNetwork::Testnet)
        .await
        .map_err(|_| WardenError::EndpointAttestation)?;
    let tip = client
        .latest_block()
        .await
        .map_err(|_| WardenError::EndpointAttestation)?;

    Ok(EndpointAttestation {
        endpoint: ENDPOINT.to_owned(),
        network_name: NETWORK_NAME.to_owned(),
        consensus_branch_id: BRANCH_ID.to_owned(),
        genesis_hash: GENESIS_HASH.to_owned(),
        tip_height: tip.height,
        tip_hash: display_hash(tip.hash),
    })
}

fn derive_addresses_from_seed(
    master_seed: &SecretVec<u8>,
    account_index: u32,
) -> Result<DerivedAddresses, WardenError> {
    verify_pinned_identity()?;

    let spending_key =
        derive_wallet_spending_key(master_seed, WalletNetwork::Testnet, account_index).map_err(
            |error| match error {
                wcash_wallet::WalletKeyError::InvalidAccount => WardenError::InvalidAccount,
                _ => WardenError::AddressDerivation,
            },
        )?;
    let viewing_key = spending_key.to_unified_full_viewing_key();
    let private_receive_address = encode_orchard_receiver(&viewing_key, WalletNetwork::Testnet)
        .map_err(|_| WardenError::AddressDerivation)?;
    let transparent_mining_address =
        encode_transparent_coinbase_receiver(&viewing_key, WalletNetwork::Testnet)
            .map_err(|_| WardenError::AddressDerivation)?;

    if !private_receive_address.starts_with(PRIVATE_ADDRESS_PREFIX)
        || !transparent_mining_address.starts_with(MINING_ADDRESS_PREFIX)
    {
        return Err(WardenError::IdentityMismatch);
    }

    Ok(DerivedAddresses {
        account_index,
        private_receive_address,
        transparent_mining_address,
    })
}

fn verify_pinned_identity() -> Result<(), WardenError> {
    let network = WalletNetwork::Testnet;
    let parameters = network.parameters();
    if network.branch_id_hex() != BRANCH_ID
        || display_hash(network.genesis_hash()) != GENESIS_HASH
        || parameters.bip70_network_name() != RPC_CHAIN_NAME
        || parameters.lowercase_name() != STORAGE_NAMESPACE
    {
        return Err(WardenError::IdentityMismatch);
    }
    Ok(())
}

fn display_hash(mut internal_hash: [u8; 32]) -> String {
    internal_hash.reverse();
    hex::encode(internal_hash)
}

#[cfg(test)]
mod tests {
    use super::*;

    const MNEMONIC: &str =
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

    #[test]
    fn identity_matches_the_pinned_wcash_testnet() {
        let identity = network_identity();
        assert_eq!(identity.network_name, "Wcash Testnet");
        assert_eq!(identity.rpc_chain_name, "test");
        assert_eq!(identity.ticker, "TWC");
        assert_eq!(identity.decimals, 8);
        assert_eq!(identity.endpoint, ENDPOINT);
        assert_eq!(identity.consensus_branch_id, "b3cfd27e");
        assert_eq!(
            identity.genesis_hash,
            "0271b5b0a10b2838f43cccdec9ca2f72aa72a7c103830082bac8f82f47f0593a"
        );
        assert_eq!(identity.storage_namespace, "wcashtestnet-v5");
        verify_pinned_identity().unwrap();
    }

    #[test]
    fn mnemonic_derivation_is_deterministic_and_wcash_namespaced() {
        let first = derive_testnet_addresses_from_mnemonic(MNEMONIC.to_owned(), 0).unwrap();
        let second = derive_testnet_addresses_from_mnemonic(MNEMONIC.to_owned(), 0).unwrap();

        assert_eq!(first, second);
        assert_eq!(first.account_index, 0);
        assert_eq!(
            first.private_receive_address,
            "wutest1346rfcs4mxccv05222xt2mk7j5uve0gujp9r7tc95h3ef7mz3h2cejt5ml358z3hlvg5ynljkz7ezzqmxkpcyxtqr2nx20kdkyrsh2hq"
        );
        assert_eq!(
            first.transparent_mining_address,
            "WTD3nxTFsmT1Wgo7RoCzXiFV4MeTkvJKdCn"
        );
        assert!(first.private_receive_address.starts_with("wutest1"));
        assert!(first.transparent_mining_address.starts_with("WT"));
        assert!(!first.private_receive_address.starts_with('u'));
        assert!(!first.transparent_mining_address.starts_with("tm"));
    }

    #[test]
    fn accounts_are_domain_separated() {
        let first = derive_testnet_addresses_from_mnemonic(MNEMONIC.to_owned(), 0).unwrap();
        let second = derive_testnet_addresses_from_mnemonic(MNEMONIC.to_owned(), 1).unwrap();

        assert_ne!(
            first.private_receive_address,
            second.private_receive_address
        );
        assert_ne!(
            first.transparent_mining_address,
            second.transparent_mining_address
        );
    }

    #[test]
    fn invalid_secret_input_is_reported_without_echoing_it() {
        let secret = "this phrase must never appear in an error";
        let error = derive_testnet_addresses_from_mnemonic(secret.to_owned(), 0).unwrap_err();

        assert_eq!(error, WardenError::InvalidMnemonic);
        assert!(!error.to_string().contains(secret));
        assert!(!format!("{error:?}").contains(secret));
    }

    #[test]
    fn invalid_account_is_rejected_without_parsing_the_zeroized_secret() {
        let error = derive_testnet_addresses_from_mnemonic(
            "not a mnemonic and must not be parsed".to_owned(),
            1 << 31,
        )
        .unwrap_err();

        assert_eq!(error, WardenError::InvalidAccount);
    }
}
