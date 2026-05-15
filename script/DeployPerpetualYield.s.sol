// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "forge-std/Script.sol";
import "../src/PerpetualYield.sol";

contract DeployPerpetualYield is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        PerpetualYield token = new PerpetualYield();
        
        // Optional: Admin sets initial settings if required
        // token.externalMint(vm.addr(deployerPrivateKey), 1000000 * 1e18);

        vm.stopBroadcast();
    }
}