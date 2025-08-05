// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// This library holds the deployed contract addresses for easy import into other scripts.
library DeployedContracts {
    // --- BSC Testnet (Chain ID 97) ---

    // CORRECTED THE ADDRESS TO USE THE CHECKSUM PROVIDED BY THE COMPILER
    address constant AccessControl_97 = 0xC8c9077Dd990B0B17bd9F22049d31aeE9e34870d;
    
    // I am correcting all of them now to prevent this error from happening again
    // for other contracts. Please ensure these match what your compiler outputs
    // if you add more.
    address constant EmergencyController_97 = 0xf8EBF1E71783e752184f068958C20654bbC61589;
    address constant TokenStaking_97 = 0x410e58408A8a8B96bf281216F0d6A0431237cbD9;
    address constant pREWAToken_97 = 0x1376BAeca50F85Ce912FBb60E4cD6A2e0CC082A0;
    address constant OracleIntegration_97 = 0xAE4a41dAd3339bf3f01Dc2FF8C6A02A942359Cd9;
}