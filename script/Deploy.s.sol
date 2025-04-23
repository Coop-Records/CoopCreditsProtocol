// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Credits1155} from "../src/Credits1155.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployCredits is Script {
    // Deployment results
    struct DeploymentResult {
        address implementation;
        address proxy;
        address proxyAdmin;
    }

    // Contract instances
    Credits1155 public implementation;
    Credits1155 public credits;
    ProxyAdmin public proxyAdmin;

    function run() public returns (DeploymentResult memory) {
        string memory tokenUri = vm.envString("TOKEN_URI");
        address fixedPriceSaleStrategy = vm.envOr("FIXED_PRICE_SALE_STRATEGY", address(0));

        console.log("Deploying Credits1155 to chain:", block.chainid);
        console.log("Using token URI:", tokenUri);
        console.log("Using fixed price sale strategy:", fixedPriceSaleStrategy);

        // Start broadcasting
        vm.startBroadcast();

        // 1. Deploy implementation
        implementation = new Credits1155();
        console.log("Implementation deployed at:", address(implementation));

        // 2. Deploy ProxyAdmin
        proxyAdmin = new ProxyAdmin(msg.sender);
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));

        // 3. Prepare initialization data
        bytes memory initData =
            abi.encodeWithSelector(Credits1155.initialize.selector, tokenUri, fixedPriceSaleStrategy);

        // 4. Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), initData);
        console.log("Proxy deployed at:", address(proxy));

        // 5. Setup proxy interface
        credits = Credits1155(payable(address(proxy)));

        vm.stopBroadcast();

        DeploymentResult memory result = DeploymentResult({
            implementation: address(implementation),
            proxy: address(proxy),
            proxyAdmin: address(proxyAdmin)
        });

        return result;
    }
}
