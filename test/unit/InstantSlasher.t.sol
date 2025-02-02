// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {InstantSlasher} from "../../src/slashers/InstantSlasher.sol";
import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISlasher, ISlasherTypes, ISlasherErrors} from "../../src/interfaces/ISlasher.sol";
import {ISlashingRegistryCoordinator} from "../../src/interfaces/ISlashingRegistryCoordinator.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {EmptyContract} from "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";

contract InstantSlasherTest is Test {
    InstantSlasher public instantSlasher;
    InstantSlasher public instantSlasherImplementation;
    ProxyAdmin public proxyAdmin;
    EmptyContract public emptyContract;

    address public allocationManager;
    address public slashingRegistryCoordinator;
    address public slasher;
    address public operator;
    IStrategy public mockStrategy;
    address public proxyAdminOwner = address(uint160(uint256(keccak256("proxyAdminOwner"))));

    function setUp() public {
        allocationManager = address(0x1);
        slasher = address(0x3);
        operator = address(0x4);
        mockStrategy = IStrategy(address(0x5));
        slashingRegistryCoordinator = address(0x6);

        vm.startPrank(proxyAdminOwner);
        proxyAdmin = new ProxyAdmin();
        emptyContract = new EmptyContract();

        instantSlasher = InstantSlasher(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        instantSlasherImplementation = new InstantSlasher(
            IAllocationManager(allocationManager),
            ISlashingRegistryCoordinator(slashingRegistryCoordinator),
            slasher
        );

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(instantSlasher))),
            address(instantSlasherImplementation)
        );
        vm.stopPrank();

        instantSlasher.initialize(slasher);
    }

    function test_initialization() public {
        assertEq(instantSlasher.slasher(), slasher);
    }

    function _createMockSlashingParams() internal view returns (IAllocationManagerTypes.SlashingParams memory) {
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = mockStrategy;

        uint256[] memory wadsToSlash = new uint256[](1);
        wadsToSlash[0] = 0.5e18; // 50% slash

        return IAllocationManagerTypes.SlashingParams({
            operator: operator,
            operatorSetId: 1,
            strategies: strategies,
            wadsToSlash: wadsToSlash,
            description: "Test slashing"
        });
    }

    function test_fulfillSlashingRequest_revert_notSlasher() public {
        IAllocationManagerTypes.SlashingParams memory params = _createMockSlashingParams();
        vm.expectRevert(ISlasherErrors.OnlySlasher.selector);
        instantSlasher.fulfillSlashingRequest(params);
    }

    function test_fulfillSlashingRequest() public {
        vm.skip(true); // TODO:
        IAllocationManagerTypes.SlashingParams memory params = _createMockSlashingParams();

        vm.prank(slasher);
        instantSlasher.fulfillSlashingRequest(params);
    }
}
