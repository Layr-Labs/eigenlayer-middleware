using ServiceManagerMock as serviceManager;
using StakeRegistryHarness as stakeRegistry;
using BLSApkRegistryHarness as blsApkRegistry;
using IndexRegistryHarness as indexRegistry;
// using DelegationManager as delegation;
// using BN254;
use builtin rule sanity;

methods {
    function _.isValidSignature(bytes32 hash, bytes signature) external => NONDET; // isValidSignatureCVL(hash,signature) expect bytes4;
    function _.unpauser() external => unpauser expect address;
    function _.isPauser(address user) external => pausers[user] expect bool;
    function _.isOperator(address operator) external => operators[operator] expect bool;

    // BN254 Library
    function BN254.pairing(BN254.G1Point memory, BN254.G2Point memory, BN254.G1Point memory, BN254.G2Point memory) internal returns (bool) => NONDET;
    function BN254.hashToG1(bytes32 x) internal returns (BN254.G1Point memory) => hashToG1Ghost(x);
    function BN254.plus(BN254.G1Point memory, BN254.G1Point memory) internal returns (BN254.G1Point memory) => returnG1();

    // external calls to ServiceManager
    function _.registerOperatorToAVS(address, ISignatureUtils.SignatureWithSaltAndExpiry) external => NONDET;
    function _.deregisterOperatorFromAVS(address) external => NONDET;

    // Registry contracts
    function StakeRegistryHarness.totalStakeHistory(uint8) external returns (IStakeRegistry.StakeUpdate[]) envfree;
    function StakeRegistry._weightOfOperatorForQuorum(uint8 quorumNumber, address operator) internal returns (uint96, bool) => weightOfOperatorGhost(quorumNumber, operator);

    function IndexRegistryHarness.operatorCountHistory(uint8) external returns (IIndexRegistry.QuorumUpdate[]) envfree;
    
    function BLSApkRegistryHarness.getApkHistory(uint8) external returns (IBLSApkRegistry.ApkUpdate[]) envfree;
    function BLSApkRegistryHarness.getOperatorId(address) external returns (bytes32) envfree;
    function BLSApkRegistryHarness.registerBLSPublicKey(address, IBLSApkRegistry.PubkeyRegistrationParams, BN254.G1Point) external returns (bytes32) => PER_CALLEE_CONSTANT;


    // RegistryCoordinator
    function getOperatorStatus(address operator) external returns (IRegistryCoordinator.OperatorStatus) envfree;
    function getOperatorId(address operator) external returns (bytes32) envfree;
    function RegistryCoordinator._verifyChurnApproverSignature(address, bytes32, IRegistryCoordinator.OperatorKickParam[] memory, ISignatureUtils.SignatureWithSaltAndExpiry memory) internal => NONDET;
    function RegistryCoordinator._validateChurn(uint8, uint96, address, uint96, IRegistryCoordinator.OperatorKickParam memory, IRegistryCoordinator.OperatorSetParam memory) internal => NONDET;

    // harnessed functions
    function bytesArrayContainsDuplicates(bytes bytesArray) external returns (bool) envfree;
    function bytesArrayIsSubsetOfBitmap(uint256 referenceBitmap, bytes arrayWhichShouldBeASubsetOfTheReference) external returns (bool) envfree;
    function quorumInBitmap(uint256 bitmap, uint8 numberToCheckForInclusion) external returns (bool) envfree;
    function getQuorumBitmapHistoryLength(bytes32) external returns (uint256) envfree;
    function hashToG1Harness(bytes32 x) external returns (BN254.G1Point memory) envfree;

    // BitmapUtils Libraries
    function BitmapUtils.orderedBytesArrayToBitmap(bytes memory a) internal returns (uint256) => bytesToBitmapCVL[a];
    function BitmapUtils.orderedBytesArrayToBitmap(bytes memory a, uint8 b) internal returns (uint256) => bytesToBitmapCappedCVL[a][b];
    function BitmapUtils.isArrayStrictlyAscendingOrdered(bytes calldata a) internal returns (bool) => ascendingArrayCVL[a];
    function BitmapUtils.bitmapToBytesArray(uint256 a) internal returns (bytes memory) => returnBytes();
    function BitmapUtils.countNumOnes(uint256 a) internal returns (uint16) => numOnesCVL[a];
}

/** Ghost variables **/

// BitmapUtils ghost summaries
ghost mapping(bytes => uint256) bytesToBitmapCVL;
ghost mapping(bytes => mapping(uint8 => uint256)) bytesToBitmapCappedCVL;
ghost mapping(bytes => bool) ascendingArrayCVL;
ghost mapping(uint256 => bytes) bitmapToBytesCVL;
ghost mapping(uint256 => uint16) numOnesCVL;

// Other ghost summaries
ghost address unpauser;
ghost mapping(address => bool) pausers;
ghost mapping(address => bool) operators;
ghost mapping(uint8 => mapping(address => uint96)) operatorWeight;

/** Functions **/

function isPauserCVL(address user) returns bool {
    return pausers[user];
}

function hashToG1Ghost(bytes32 x) returns BN254.G1Point {
    return hashToG1Harness(x);
}

function weightOfOperatorGhost(uint8 quorumNumber, address operator) returns (uint96, bool) {
    bool val = operatorWeight[quorumNumber][operator] >= stakeRegistry.minimumStakeForQuorum[quorumNumber];
    return (operatorWeight[quorumNumber][operator], val);
}

function returnG1() returns BN254.G1Point {
    BN254.G1Point retVal;
    return retVal;
}

function returnG2() returns BN254.G2Point {
    BN254.G2Point retVal;
    return retVal;
}

function returnBytes() returns bytes {
    bytes retVal;
    return retVal;
}

/** Properties **/

/// 
// status: verified
invariant initializedQuorumHistories(uint8 quorumNumber)
    quorumNumber < currentContract.quorumCount <=> 
        stakeRegistry.totalStakeHistory(quorumNumber).length != 0 && 
        indexRegistry.operatorCountHistory(quorumNumber).length != 0 &&
        blsApkRegistry.getApkHistory(quorumNumber).length != 0;

// Ensuring that RegistryCoordinator._operatorInfo and BLSApkRegistry.operatorToPubkeyHash operatorIds are consistent
// for the same operator
// status: verified
invariant operatorIdandPubkeyHash(address operator)
    getOperatorId(operator) == blsApkRegistry.getOperatorId(operator);

/// @notice If my Operator status is REGISTERED ⇔ my quorum bitmap MUST BE nonzero
// status: verified
invariant registeredOperatorsHaveNonzeroBitmaps(env e, address operator)
    getOperatorStatus(operator) == IRegistryCoordinator.OperatorStatus.REGISTERED <=>
        getCurrentQuorumBitmap(e, getOperatorId(operator)) != 0 && getOperatorId(operator) != to_bytes32(0)
    {
        preserved with (env e1) {
            require e1.msg.sender == e.msg.sender;
            // Pushing to history overflows to 0 length and 0 length returns 0 bitmap
            require getQuorumBitmapHistoryLength(getOperatorId(operator)) < max_uint256;
            // If operator and msg.sender are not the same. msg.sender bitmap changing doesn't affect operator bitmap
            requireInvariant oneIdPerOperator(operator, e.msg.sender);
            // We store operatorId in multiple contracts. Preserves consistency when reading from RegistryCoordinator
            // or calling blsApkRegistry.getOperatorId(operator) in _getOrCreateOperatorId
            requireInvariant operatorIdandPubkeyHash(e.msg.sender);
            requireInvariant operatorIdandPubkeyHash(operator);
        }
        preserved ejectOperator(address operator1, bytes quorumNumbers) with (env e1) {
            requireInvariant oneIdPerOperator(operator1, operator);
            require getQuorumBitmapHistoryLength(getOperatorId(operator1)) < max_uint256;
        }
        preserved registerOperator(
            bytes quorumNumbers,
            string socket,
            IBLSApkRegistry.PubkeyRegistrationParams params,
            ISignatureUtils.SignatureWithSaltAndExpiry signature
        ) with (env e1) {
            require e1.msg.sender == e.msg.sender;
            require getQuorumBitmapHistoryLength(getOperatorId(operator)) < max_uint256;
            requireInvariant oneIdPerOperator(operator, e.msg.sender);
            requireInvariant operatorIdandPubkeyHash(e.msg.sender);
        }
        preserved registerOperatorWithChurn(
            bytes quorumNumbers,
            string socket,
            IBLSApkRegistry.PubkeyRegistrationParams params,
            IRegistryCoordinator.OperatorKickParam[] kickParams,
            ISignatureUtils.SignatureWithSaltAndExpiry churnSignature,
            ISignatureUtils.SignatureWithSaltAndExpiry operatorSignature
        ) with (env e1) {
            require quorumNumbers.length == 1;
            require e1.msg.sender == e.msg.sender;
            require getQuorumBitmapHistoryLength(getOperatorId(operator)) < max_uint256;
            requireInvariant oneIdPerOperator(operator, e.msg.sender);
            requireInvariant oneIdPerOperator(operator, kickParams[0].operator);
            requireInvariant operatorIdandPubkeyHash(e.msg.sender);
        }
        preserved updateOperators(address[] updatingOperators) with (env e1) {
            requireInvariant oneIdPerOperator(operator, updatingOperators[0]);
            requireInvariant oneIdPerOperator(updatingOperators[1], operator);
            require getQuorumBitmapHistoryLength(getOperatorId(operator)) < max_uint256;
        }
        preserved updateOperatorsForQuorum(address[][] updatingOperators, bytes quorumNumbers) with (env e1) {
            require updatingOperators.length == 1 && quorumNumbers.length == 1;
            requireInvariant oneIdPerOperator(operator, updatingOperators[0][0]);
            requireInvariant oneIdPerOperator(updatingOperators[0][1], operator);
            require getQuorumBitmapHistoryLength(getOperatorId(operator)) < max_uint256;
        }
    }


/// @notice unique address <=> unique operatorId
// status: verified
invariant oneIdPerOperator(address operator1, address operator2)
    operator1 != operator2
        => getOperatorId(operator1) != getOperatorId(operator2) || getOperatorId(operator1) == to_bytes32(0) && getOperatorId(operator2) == to_bytes32(0)
    {
        preserved {
            requireInvariant operatorIdandPubkeyHash(operator1);
            requireInvariant operatorIdandPubkeyHash(operator2);
        }    
    }

/// @notice one way implication as IndexRegistry.currentOperatorIndex does not get updated on operator deregistration
// status: violated
invariant operatorIndexWithinRange(env e, address operator, uint8 quorumNumber, uint256 blocknumber, uint256 index)
    quorumInBitmap(assert_uint256(getCurrentQuorumBitmap(e, getOperatorId(operator))), quorumNumber) =>
        indexRegistry.currentOperatorIndex(e, quorumNumber, getOperatorId(operator)) < indexRegistry.totalOperatorsForQuorum(e, quorumNumber)
    {
        preserved with (env e1) {
            require e1.msg.sender == e.msg.sender;
            require getQuorumBitmapHistoryLength(getOperatorId(operator)) < max_uint256;
            requireInvariant oneIdPerOperator(operator, e.msg.sender);
            requireInvariant operatorIdandPubkeyHash(e.msg.sender);
            requireInvariant operatorIdandPubkeyHash(operator);
        }
        preserved ejectOperator(address operator1, bytes quorumNumbers) with (env e1) {
            requireInvariant oneIdPerOperator(operator1, operator);
            requireInvariant operatorIdandPubkeyHash(operator1);
            requireInvariant operatorIdandPubkeyHash(operator);
            require getQuorumBitmapHistoryLength(getOperatorId(operator1)) < max_uint256;
        }
        preserved registerOperator(
            bytes quorumNumbers,
            string socket,
            IBLSApkRegistry.PubkeyRegistrationParams params,
            ISignatureUtils.SignatureWithSaltAndExpiry signature
        ) with (env e1) {
            require e1.msg.sender == e.msg.sender;
            require getQuorumBitmapHistoryLength(getOperatorId(operator)) < max_uint256;
            requireInvariant oneIdPerOperator(operator, e.msg.sender);
            requireInvariant operatorIdandPubkeyHash(e.msg.sender);
            requireInvariant operatorIdandPubkeyHash(operator);

            require getCurrentQuorumBitmap(e, getOperatorId(operator)) + bytesToBitmapCVL[quorumNumbers] <= max_uint192;
        }
        preserved registerOperatorWithChurn(
            bytes quorumNumbers,
            string socket,
            IBLSApkRegistry.PubkeyRegistrationParams params,
            IRegistryCoordinator.OperatorKickParam[] kickParams,
            ISignatureUtils.SignatureWithSaltAndExpiry churnSignature,
            ISignatureUtils.SignatureWithSaltAndExpiry operatorSignature
        ) with (env e1) {
            require e1.msg.sender == e.msg.sender;
            require getQuorumBitmapHistoryLength(getOperatorId(operator)) < max_uint256;
            requireInvariant oneIdPerOperator(operator, e.msg.sender);
            requireInvariant operatorIdandPubkeyHash(e.msg.sender);
            requireInvariant operatorIdandPubkeyHash(operator);

            require getCurrentQuorumBitmap(e, getOperatorId(operator)) + bytesToBitmapCVL[quorumNumbers] <= max_uint192;
        }
        preserved updateOperators(address[] updatingOperators) with (env e1) {
            requireInvariant oneIdPerOperator(operator, updatingOperators[0]);
            requireInvariant oneIdPerOperator(updatingOperators[1], operator);
            require getQuorumBitmapHistoryLength(getOperatorId(operator)) < max_uint256;
        }
        preserved updateOperatorsForQuorum(address[][] updatingOperators, bytes quorumNumbers) with (env e1) {
            require updatingOperators.length == 1 && quorumNumbers.length == 1;
            requireInvariant oneIdPerOperator(operator, updatingOperators[0][0]);
            requireInvariant oneIdPerOperator(updatingOperators[0][1], operator);
            require getQuorumBitmapHistoryLength(getOperatorId(operator)) < max_uint256;
        }
    }


/// @notice if operator is registered for quorum number then operator has stake weight >= minStakeWeight(quorumNumber)
// status: violated
invariant operatorHasNonZeroStakeWeight(env e, address operator, uint8 quorumNumber)
    quorumInBitmap(assert_uint256(getCurrentQuorumBitmap(e, getOperatorId(operator))), quorumNumber) =>
        stakeRegistry.weightOfOperatorForQuorum(e, quorumNumber, operator) >= stakeRegistry.minimumStakeForQuorum(e, quorumNumber)
    {
        preserved with (env e1) {
            require e1.msg.sender == e.msg.sender;
            require getQuorumBitmapHistoryLength(getOperatorId(operator)) < max_uint256;
            requireInvariant oneIdPerOperator(operator, e.msg.sender);
            requireInvariant operatorIdandPubkeyHash(e.msg.sender);
            requireInvariant operatorIdandPubkeyHash(operator);
        }
        preserved ejectOperator(address operator1, bytes quorumNumbers) with (env e1) {
            requireInvariant oneIdPerOperator(operator1, operator);
            requireInvariant operatorIdandPubkeyHash(operator1);
            requireInvariant operatorIdandPubkeyHash(operator);
            require getQuorumBitmapHistoryLength(getOperatorId(operator1)) < max_uint256;
        }
        preserved registerOperator(
            bytes quorumNumbers,
            string socket,
            IBLSApkRegistry.PubkeyRegistrationParams params,
            ISignatureUtils.SignatureWithSaltAndExpiry signature
        ) with (env e1) {
            require e1.msg.sender == e.msg.sender;
            require getQuorumBitmapHistoryLength(getOperatorId(operator)) < max_uint256;
            requireInvariant oneIdPerOperator(operator, e.msg.sender);
            requireInvariant operatorIdandPubkeyHash(e.msg.sender);
            requireInvariant operatorIdandPubkeyHash(operator);

            require getCurrentQuorumBitmap(e, getOperatorId(operator)) + bytesToBitmapCVL[quorumNumbers] <= max_uint192;
        }
        preserved registerOperatorWithChurn(
            bytes quorumNumbers,
            string socket,
            IBLSApkRegistry.PubkeyRegistrationParams params,
            IRegistryCoordinator.OperatorKickParam[] kickParams,
            ISignatureUtils.SignatureWithSaltAndExpiry churnSignature,
            ISignatureUtils.SignatureWithSaltAndExpiry operatorSignature
        ) with (env e1) {
            require e1.msg.sender == e.msg.sender;
            require getQuorumBitmapHistoryLength(getOperatorId(operator)) < max_uint256;
            requireInvariant oneIdPerOperator(operator, e.msg.sender);
            requireInvariant operatorIdandPubkeyHash(e.msg.sender);
            requireInvariant operatorIdandPubkeyHash(operator);

            require getCurrentQuorumBitmap(e, getOperatorId(operator)) + bytesToBitmapCVL[quorumNumbers] <= max_uint192;
        }
        preserved updateOperators(address[] updatingOperators) with (env e1) {
            requireInvariant oneIdPerOperator(operator, updatingOperators[0]);
            requireInvariant oneIdPerOperator(updatingOperators[1], operator);
            require getQuorumBitmapHistoryLength(getOperatorId(operator)) < max_uint256;
        }
        preserved updateOperatorsForQuorum(address[][] updatingOperators, bytes quorumNumbers) with (env e1) {
            require updatingOperators.length == 1 && quorumNumbers.length == 1;
            requireInvariant oneIdPerOperator(operator, updatingOperators[0][0]);
            requireInvariant oneIdPerOperator(updatingOperators[0][1], operator);
            require getQuorumBitmapHistoryLength(getOperatorId(operator)) < max_uint256;
        }
    }

/// Operator cant go from registered to NEVER_REGISTERED. Can write some parametric rule
// status: verified
rule registeredOperatorCantBeNeverRegistered(address operator) {
    require(getOperatorStatus(operator) != IRegistryCoordinator.OperatorStatus.NEVER_REGISTERED);

    calldataarg arg;
    env e;
    method f;
    f(e, arg);

    assert(getOperatorStatus(operator) != IRegistryCoordinator.OperatorStatus.NEVER_REGISTERED);
}

/* 
Potential properties:

* EigenDA wallet below X ETH in Funds
    * potential rule: eigenDA must have >0 funds (if ensured in the constructor)
* No successful posts of data (calls to EigenDAServiceManager.confirmBatch) in the last hour
* Total number of operators decreases by more than 10 in the last 6 hours
    * potential rule: operators > 0 (if added in constructor)
* All registered operators are registered for at least one quorum i.e nonzero quorum bitmap
    * potential rule: quorum bitmap must be nonzero
* Batch with 1% less than max nonsigners percentage for a batch posted
    * potential rule: A posted batch must not have more non-signers than some defined percentage
* List of non-signers for a confirmed batch contains:
    * Duplicate entries OR
        * potential rule: no duplicate non-signers
    * An entry which corresponds to a non-registered operator
        * potential rule: no unregistered non-signers
* A registered operator falls below the minimum stake for a quorum. Can check when an operator is deregistered for this quorum on-chain when OperatorStakeUpdate(operatorId, quorumNumber, newStake) is emitted with newStake = 0. Or monitor all registered operator stakes and calculate offchain.
    * potential rule: registered operator must be above minimum stake
* For all currently registered operators, each operatorIndex is in the range [0, IndexRegistry.totalOperatorsForQuorum - 1]. Currently, registered operators can be fetched by OperatorState.getOperatorState at the current block number
* Each initialized quorum must have consistent quorum histories across registry contracts.
* For initialized quorumNumbers
    * StakeRegistry: _totalStakeHistory[quorumNumber].length != 0
    * IndexRegistry: _operatorCountHistory[quorumNumber].length != 0
    * BLSApkRegistry: apkHistory[quorumNumber].length != 0
* For non-init quorumNumbers
    * StakeRegistry: _totalStakeHistory[quorumNumber].length == 0
    * IndexRegistry: _operatorCountHistory[quorumNumber].length == 0
    * BLSApkRegistry: apkHistory[quorumNumber].length == 0
