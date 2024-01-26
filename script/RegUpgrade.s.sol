// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "../src/RegistryCoordinator.sol";
import "../src/ServiceManagerBase.sol";
import "../src/StakeRegistry.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "forge-std/Script.sol";
import "forge-std/Test.sol";

contract Upgrade_Reg_SM is Script, Test {
    RegistryCoordinator public newRegCoordinator;
    ServiceManagerBase public newServiceManager;
    ProxyAdmin public proxyAdmin;
    string defaultSocket = "69.69.69.69:420";
    IBLSApkRegistry.PubkeyRegistrationParams pubkeyRegistrationParams;

    function run() external {
        
        RegistryCoordinator regCord = RegistryCoordinator(0xc1DC4987Bd4c2f17446d51C9ED3397328b1827DA);
        IStakeRegistry stakeReg = regCord.stakeRegistry();
        ISignatureUtils.SignatureWithSaltAndExpiry memory emptySignatureAndExpiry;
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(1);

        IStakeRegistry.StrategyParams[] memory quorumStrategiesConsideredAndMultipliers =
        new IStakeRegistry.StrategyParams[](1);
        quorumStrategiesConsideredAndMultipliers[0] = IStakeRegistry.StrategyParams({
            strategy: IStrategy(0xed6DE3f2916d20Cb427fe7255194a05061319FFB),
            multiplier: 1e18
        });


        vm.startBroadcast();

        // stakeReg.addStrategies(
        //     0,
        //     quorumStrategiesConsideredAndMultipliers
        // );

        regCord.registerOperator(
            quorumNumbers,
            defaultSocket,
            pubkeyRegistrationParams,
            emptySignatureAndExpiry
        );
        // regCord.deregisterOperator(
        //     quorumNumbers
        // );


        // // Deploy New RegistryCoordinator
        // newRegCoordinator = new RegistryCoordinator(
        //     IServiceManager(0x88AE05e4FA3835CfD3Bd80B9a927c8301857Ef55),
        //     IStakeRegistry(0xd2701C630aBF8c41185734F0a237A4D5973E8cCF),
        //     IBLSApkRegistry(0x5b83b0131E65B5b71047162F38871E91cCaa817B),
        //     IIndexRegistry(0x6f9d5E456EE08c2857c0fF5bc25C7cDF9c3Dd318)
        // );

        // // Deploy New ServiceManager
        // newServiceManager = new ServiceManagerBase(
        //     IDelegationManager(0x45b4c4DAE69393f62e1d14C5fe375792DF4E6332),
        //     IRegistryCoordinator(0xc1DC4987Bd4c2f17446d51C9ED3397328b1827DA),
        //     IStakeRegistry(0xd2701C630aBF8c41185734F0a237A4D5973E8cCF)
        // );

        // // Upgrade Proxy Contract
        // proxyAdmin = ProxyAdmin(payable(0x2773976d6D37871fBD7De7572Ca52495e32900e4));
        // proxyAdmin.upgrade(
        //     TransparentUpgradeableProxy(payable(0xc1DC4987Bd4c2f17446d51C9ED3397328b1827DA)),
        //     address(newRegCoordinator)
        // );
        // proxyAdmin.upgrade(
        //     TransparentUpgradeableProxy(payable(0x787f666893F3EB6bF5D7A6AA9297784671A3312D)),
        //     address(newServiceManager)
        // );

        vm.stopBroadcast();
    }
}