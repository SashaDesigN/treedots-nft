// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TreeDots} from "../src/TreeDots.sol";

/**
 * @notice Deploy TreeDots to any EVM chain.
 *
 * Dry run (local fork, no broadcast):
 *   forge script script/Deploy.s.sol --rpc-url <RPC_URL>
 *
 * Live deploy:
 *   forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast --private-key <PK>
 *
 * With hardware wallet (Ledger):
 *   forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast --ledger
 */
contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        TreeDots nft = new TreeDots();

        console2.log("TreeDots deployed at :", address(nft));
        console2.log("Owner / royalty receiver :", nft.owner());
        console2.log("Max supply              :", nft.MAX_SUPPLY());
        console2.log("Mint price (wei)        :", nft.MINT_PRICE());

        vm.stopBroadcast();
    }
}
