// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Credits1155} from "../src/Credits1155.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeCredits is Script {
    // Upgrade results
    struct UpgradeResult {
        address newImplementation;
        address proxy;
        address proxyAdmin;
    }

    // Contract instances
    Credits1155 public newImplementation;
    ProxyAdmin public proxyAdmin;

    function run() public returns (UpgradeResult memory) {
        // Get environment variables
        address creditsProxyAddress = vm.envAddress("CREDITS_PROXY_ADDRESS");
        address creditsProxyAdminAddress = vm.envAddress("CREDITS_PROXY_ADMIN");

        console.log("Upgrading Credits1155 on chain:", block.chainid);
        console.log("Proxy address:", creditsProxyAddress);
        console.log("Proxy admin address:", creditsProxyAdminAddress);

        // Start broadcasting
        vm.startBroadcast();

        // 1. Deploy new implementation
        newImplementation = new Credits1155();
        console.log("New implementation deployed at:", address(newImplementation));

        // 2. Get proxy admin instance
        proxyAdmin = ProxyAdmin(creditsProxyAdminAddress);

        // 3. Prepare upgrade data (if needed for initialization)
        // For a simple upgrade without re-initialization, use empty bytes
        bytes memory upgradeData = "";

        // 4. Upgrade the proxy to new implementation
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(creditsProxyAddress)), address(newImplementation), upgradeData
        );
        console.log("Proxy upgraded successfully to new implementation");

        vm.stopBroadcast();

        UpgradeResult memory result = UpgradeResult({
            newImplementation: address(newImplementation),
            proxy: creditsProxyAddress,
            proxyAdmin: creditsProxyAdminAddress
        });

        return result;
    }
}
