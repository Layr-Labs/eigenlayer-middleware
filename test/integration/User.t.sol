// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "forge-std/Test.sol";

// Interfaces
import "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

// Core
import "eigenlayer-contracts/src/contracts/core/DelegationManager.sol";
import "eigenlayer-contracts/src/contracts/core/StrategyManager.sol";

// Middleware
import "src/RegistryCoordinator.sol";
import "src/BLSApkRegistry.sol";
import "src/IndexRegistry.sol";
import "src/StakeRegistry.sol";
import "src/ServiceManagerBase.sol";

import "src/libraries/BN254.sol";
import "test/integration/TimeMachine.t.sol";


interface IUserDeployer {
    function registryCoordinator() external view returns (RegistryCoordinator);
    function timeMachine() external view returns (TimeMachine);
}

contract User is Test {

    using BN254 for *;

    Vm cheats = Vm(HEVM_ADDRESS);

    // Core contracts
    DelegationManager delegationManager;
    StrategyManager strategyManager;

    // Middleware contracts
    RegistryCoordinator registryCoordinator;
    ServiceManagerBase serviceManager;
    BLSApkRegistry blsApkRegistry;
    StakeRegistry stakeRegistry;
    IndexRegistry indexRegistry;
    
    TimeMachine timeMachine;

    string public NAME;
    bytes32 public operatorId;

    // BLS keypair:
    uint privKey;
    IBLSApkRegistry.PubkeyRegistrationParams pubkeyParams;

    // EIP1271 sigs:
    mapping(bytes32 => bool) digests;
    uint salt = 0;

    constructor(string memory name, uint _privKey, IBLSApkRegistry.PubkeyRegistrationParams memory _pubkeyParams) {
        IUserDeployer deployer = IUserDeployer(msg.sender);

        registryCoordinator = deployer.registryCoordinator();
        serviceManager = ServiceManagerBase(address(registryCoordinator.serviceManager()));

        blsApkRegistry = BLSApkRegistry(address(registryCoordinator.blsApkRegistry()));
        stakeRegistry = StakeRegistry(address(registryCoordinator.stakeRegistry()));
        indexRegistry = IndexRegistry(address(registryCoordinator.indexRegistry()));

        delegationManager = DelegationManager(address(stakeRegistry.delegation()));
        strategyManager = StrategyManager(address(delegationManager.strategyManager()));

        timeMachine = deployer.timeMachine();

        NAME = name;

        // Generate BN254 keypair and registration signature
        privKey = _privKey;
        pubkeyParams = _pubkeyParams;

        BN254.G1Point memory registrationMessageHash = registryCoordinator.pubkeyRegistrationMessageHash(address(this));
        pubkeyParams.pubkeyRegistrationSignature = registrationMessageHash.scalar_mul(privKey);

        operatorId = pubkeyParams.pubkeyG1.hashG1Point();
    }

    modifier createSnapshot() virtual {
        timeMachine.createSnapshot();
        _;
    }

    receive() external payable {}

    /**
     * Middleware contracts:
     */

    function registerOperator(bytes calldata quorums) public createSnapshot virtual returns (bytes32) {
        emit log(_name(".registerOperator"));

        registryCoordinator.registerOperator({
            quorumNumbers: quorums,
            socket: NAME,
            params: pubkeyParams,
            operatorSignature: _genAVSRegistrationSig()
        });

        return pubkeyParams.pubkeyG1.hashG1Point();
    }

    function deregisterOperator() public createSnapshot virtual {
        emit log(_name(".deregisterOperator"));

        revert("TODO");   
    }

    /**
     * Core contracts:
     */

    function registerAsOperator() public createSnapshot virtual {
        emit log(_name(".registerAsOperator (core)"));

        IDelegationManager.OperatorDetails memory details = IDelegationManager.OperatorDetails({
            earningsReceiver: address(this),
            delegationApprover: address(0),
            stakerOptOutWindowBlocks: 0
        });

        delegationManager.registerAsOperator(details, NAME);
    }

    // Deposit LSTs into the StrategyManager. This setup does not use the EPMgr or native ETH.
    function depositIntoEigenlayer(IStrategy[] memory strategies, uint[] memory tokenBalances) public createSnapshot virtual {
        emit log(_name(".depositIntoEigenlayer (core)"));

        for (uint i = 0; i < strategies.length; i++) {
            IStrategy strat = strategies[i];
            uint tokenBalance = tokenBalances[i];

            IERC20 underlyingToken = strat.underlyingToken();
            underlyingToken.approve(address(strategyManager), tokenBalance);
            strategyManager.depositIntoStrategy(strat, underlyingToken, tokenBalance);
        }
    }

    function queueWithdrawals(
        IStrategy[] memory strategies, 
        uint[] memory shares
    ) public createSnapshot virtual returns (IDelegationManager.Withdrawal[] memory) {
        emit log(_name(".queueWithdrawals (core)"));

        revert("TODO"); 
    }

    /**
     * EIP1271 Signatures:
     */

    bytes4 internal constant EIP1271_MAGICVALUE = 0x1626ba7e;

    function isValidSignature(bytes32 digestHash, bytes memory) public view returns (bytes4) {
        if (digests[digestHash]) {
            return EIP1271_MAGICVALUE;
        }

        return bytes4(0);
    }

    function _genAVSRegistrationSig() internal returns (ISignatureUtils.SignatureWithSaltAndExpiry memory) {
        ISignatureUtils.SignatureWithSaltAndExpiry memory signature = ISignatureUtils.SignatureWithSaltAndExpiry({
            signature: new bytes(0),
            salt: bytes32(salt++),
            expiry: type(uint256).max
        });

        bytes32 digest = delegationManager.calculateOperatorAVSRegistrationDigestHash({
            operator: address(this),
            avs: address(serviceManager),
            salt: signature.salt,
            expiry: signature.expiry
        });

        digests[digest] = true;
        return signature;
    }

    function _name(string memory s) internal view returns (string memory) {
        return string.concat(NAME, s);
    }
}