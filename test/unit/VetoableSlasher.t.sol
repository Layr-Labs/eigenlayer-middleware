// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {VetoableSlasher} from "../../src/slashers/VetoableSlasher.sol";
import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISlasher, ISlasherTypes, ISlasherErrors} from "../../src/interfaces/ISlasher.sol";
import {ISlashingRegistryCoordinator} from "../../src/interfaces/ISlashingRegistryCoordinator.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {EmptyContract} from "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";

contract VetoableSlasherTest is Test {
    VetoableSlasher public vetoableSlasher;
    VetoableSlasher public vetoableSlasherImplementation;
    ProxyAdmin public proxyAdmin;
    EmptyContract public emptyContract;

    address public allocationManager;
    address public slashingRegistryCoordinator;
    address public vetoCommittee;
    address public slasher;
    address public operator;
    IStrategy public mockStrategy;
    address public proxyAdminOwner = address(uint160(uint256(keccak256("proxyAdminOwner"))));

    uint256 constant VETO_PERIOD = 3 days;

    function setUp() public {
        allocationManager = address(0x1);
        vetoCommittee = address(0x2);
        slasher = address(0x3);
        operator = address(0x4);
        mockStrategy = IStrategy(address(0x5));
        slashingRegistryCoordinator = address(0x6);

        vm.startPrank(proxyAdminOwner);
        proxyAdmin = new ProxyAdmin();
        emptyContract = new EmptyContract();

        vetoableSlasher = VetoableSlasher(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        vetoableSlasherImplementation = new VetoableSlasher(
            IAllocationManager(allocationManager),
            ISlashingRegistryCoordinator(slashingRegistryCoordinator)
        );

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(vetoableSlasher))),
            address(vetoableSlasherImplementation)
        );
        vm.stopPrank();

        vetoableSlasher.initialize(vetoCommittee, slasher);
    }

    function test_initialization() public {
        assertEq(vetoableSlasher.vetoCommittee(), vetoCommittee);
        assertEq(vetoableSlasher.VETO_PERIOD(), VETO_PERIOD);
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

    function test_queueSlashingRequest_revert_notSlasher() public {
        IAllocationManagerTypes.SlashingParams memory params = _createMockSlashingParams();
        vm.expectRevert(ISlasherErrors.OnlySlasher.selector);
        vetoableSlasher.queueSlashingRequest(params);
    }

    function test_queueSlashingRequest() public {
        IAllocationManagerTypes.SlashingParams memory params = _createMockSlashingParams();

        vm.prank(slasher);
        vetoableSlasher.queueSlashingRequest(params);

        (IAllocationManagerTypes.SlashingParams memory resultParams, uint256 requestTimestamp, ISlasherTypes.SlashingStatus status) = vetoableSlasher.slashingRequests(0);
        ISlasherTypes.SlashingRequest memory request = ISlasherTypes.SlashingRequest(params, requestTimestamp, status);
        assertEq(resultParams.operator, operator);
        assertEq(resultParams.operatorSetId, 1);
        assertEq(resultParams.wadsToSlash[0], 0.5e18);
        assertEq(resultParams.description, "Test slashing");
        assertEq(uint8(status), uint8(ISlasherTypes.SlashingStatus.Requested));
        assertEq(requestTimestamp, block.timestamp);
    }

    function test_cancelSlashingRequest_revert_notVetoCommittee() public {
        IAllocationManagerTypes.SlashingParams memory params = _createMockSlashingParams();

        vm.prank(slasher);
        vetoableSlasher.queueSlashingRequest(params);

        vm.expectRevert(ISlasherErrors.OnlyVetoCommittee.selector);
        vetoableSlasher.cancelSlashingRequest(0);
    }

    function test_cancelSlashingRequest_revert_afterVetoPeriod() public {
        IAllocationManagerTypes.SlashingParams memory params = _createMockSlashingParams();

        vm.prank(slasher);
        vetoableSlasher.queueSlashingRequest(params);

        vm.warp(block.timestamp + VETO_PERIOD + 1);

        vm.prank(vetoCommittee);
        vm.expectRevert(ISlasherErrors.VetoPeriodPassed.selector);
        vetoableSlasher.cancelSlashingRequest(0);
    }

    function test_cancelSlashingRequest() public {
        IAllocationManagerTypes.SlashingParams memory params = _createMockSlashingParams();

        vm.prank(slasher);
        vetoableSlasher.queueSlashingRequest(params);

        vm.prank(vetoCommittee);
        vetoableSlasher.cancelSlashingRequest(0);

        (IAllocationManagerTypes.SlashingParams memory resultParams, uint256 requestTimestamp, ISlasherTypes.SlashingStatus status) = vetoableSlasher.slashingRequests(0);
        assertEq(uint8(status), uint8(ISlasherTypes.SlashingStatus.Cancelled));
    }

    function test_fulfillSlashingRequest_revert_beforeVetoPeriod() public {
        IAllocationManagerTypes.SlashingParams memory params = _createMockSlashingParams();

        vm.prank(slasher);
        vetoableSlasher.queueSlashingRequest(params);

        vm.prank(slasher);
        vm.expectRevert(ISlasherErrors.VetoPeriodNotPassed.selector);
        vetoableSlasher.fulfillSlashingRequest(0);
    }

    function test_fulfillSlashingRequest() public {
        vm.skip(true);
        IAllocationManagerTypes.SlashingParams memory params = _createMockSlashingParams();

        vm.prank(slasher);
        vetoableSlasher.queueSlashingRequest(params);

        vm.warp(block.timestamp + VETO_PERIOD + 1);

        vm.prank(slasher);
        vetoableSlasher.fulfillSlashingRequest(0);

        (IAllocationManagerTypes.SlashingParams memory resultParams, uint256 requestTimestamp, ISlasherTypes.SlashingStatus status) = vetoableSlasher.slashingRequests(0);
        assertEq(uint8(status), uint8(ISlasherTypes.SlashingStatus.Completed));
    }
}