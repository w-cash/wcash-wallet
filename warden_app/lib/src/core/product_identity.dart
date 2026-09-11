abstract final class WardenProductIdentity {
  static const applicationId = 'com.wcashwallet.warden.testnet';
  static const executableName = 'wcash-warden-testnet';
  static const databaseFileName = 'wcash-warden-wcashtestnet-v5.sqlite3';
  static const walletStorageNamespace = 'wcashtestnet-v5';
  static const secureStorageScope =
      'com.wcashwallet.warden.testnet.secure-store';
  static const secureStorageKeyPrefix = 'wcash_warden_testnet_v1';
  static const mnemonicStorageKey = '$secureStorageScope.mnemonic.v1';
}
