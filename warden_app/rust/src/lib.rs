//! Narrow Flutter bridge for Wcash Warden Testnet.
//!
//! The bridge deliberately exposes only immutable network identity, fixed
//! service attestation, and in-memory receive-address derivation. Wallet state,
//! synchronization, transaction construction, signing, and broadcasting are
//! outside this milestone.

pub mod api;
mod frb_generated;
