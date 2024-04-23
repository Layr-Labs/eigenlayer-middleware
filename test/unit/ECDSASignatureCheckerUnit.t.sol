// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {ECDSAStakeRegistry} from "../../src/unaudited/ECDSAStakeRegistry.sol";
import {ECDSAStakeRegistryEventsAndErrors, Quorum, StrategyParams} from "../../src/interfaces/IECDSAStakeRegistryEventsAndErrors.sol";

contract MockServiceManager {
    // solhint-disable-next-line
    function deregisterOperatorFromAVS(address) external {}

    function registerOperatorToAVS(
        address,
        ISignatureUtils.SignatureWithSaltAndExpiry memory // solhint-disable-next-line
    ) external {}
}

contract MockDelegationManager {
    function operatorShares(address, address) external pure returns (uint256) {
        return 1000; // Return a dummy value for simplicity
    }

    function getOperatorShares(
        address,
        address[] memory strategies
    ) external pure returns (uint256[] memory) {
        uint256[] memory response = new uint256[](strategies.length);
        for (uint256 i; i < strategies.length; i++) {
            response[i] = 1000;
        }
        return response; // Return a dummy value for simplicity
    }
}

contract ECDSASignatureCheckerSetup is Test, ECDSAStakeRegistryEventsAndErrors {
    MockDelegationManager public mockDelegationManager;
    MockServiceManager public mockServiceManager;
    address internal operator1;
    address internal operator2;
    uint256 internal operator1Pk;
    uint256 internal operator2Pk;
    bytes internal signature1;
    bytes internal signature2;
    address[] internal signers;
    bytes[] internal signatures;
    bytes32 internal msgHash;

    function setUp() public virtual {
        (operator1, operator1Pk) = makeAddrAndKey("Signer 1");
        (operator2, operator2Pk) = makeAddrAndKey("Signer 2");
        mockDelegationManager = new MockDelegationManager();
        mockServiceManager = new MockServiceManager();
    }
}

contract ECDSASignatureCheckerTest is ECDSASignatureCheckerSetup {
    ECDSAStakeRegistry public registry;

    function setUp() public virtual override {
        super.setUp();
        IStrategy mockStrategy = IStrategy(address(0x1234));
        Quorum memory quorum = Quorum({strategies: new StrategyParams[](1)});
        quorum.strategies[0] = StrategyParams({
            strategy: mockStrategy,
            multiplier: 10000
        });
        registry = new ECDSAStakeRegistry(
            IDelegationManager(address(mockDelegationManager))
        );
        registry.initialize(address(mockServiceManager), 100, quorum);
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature;
        registry.registerOperatorWithSignature(operator1, operatorSignature);
        registry.registerOperatorWithSignature(operator2, operatorSignature);
    }

    function test_Function() public {
        vm.skip(true);
    }
}
