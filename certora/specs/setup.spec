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
    // function BN254.pairing(BN254.G1Point memory, BN254.G2Point memory, BN254.G1Point memory, BN254.G2Point memory) internal returns (bool) => NONDET;
    // function BN254.generatorG1() internal returns (BN254.G1Point memory) => returnG1();
    // function BN254.generatorG2() internal returns (BN254.G2Point memory) => returnG2();
    // function BN254.negGeneratorG2() internal returns (BN254.G2Point memory) => returnG2();
    // function BN254.negate(BN254.G1Point memory) internal returns (BN254.G1Point memory) => returnG1();
    function BN254.plus(BN254.G1Point memory, BN254.G1Point memory) internal returns (BN254.G1Point memory) => returnG1();
    // function BN254.scalar_mul_tiny(BN254.G1Point memory, uint16) internal returns (BN254.G1Point memory) => returnG1();
    // function BN254.scalar_mul(BN254.G1Point memory, uint256) internal returns (BN254.G1Point memory) => returnG1();
    // function BN254.safePairing(BN254.G1Point memory, BN254.G2Point memory, BN254.G1Point memory, BN254.G2Point memory, uint256) internal returns (bool, bool) => NONDET;
    // function BN254.hashG1Point(BN254.G1Point memory) internal returns (bytes32) => NONDET;
    // function BN254.hashG2Point(BN254.G2Point memory) internal returns (bytes32) => NONDET;
    // function BN254.findYFromX(uint256) internal returns (uint256, uint256) => NONDET;
    // function BN254.expMod(uint256, uint256, uint256) internal returns (uint256) => NONDET;

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
    function BitmapUtils.isSet(uint256 a, uint8 b) internal returns (bool) => isSetCVL[a][b];
    function BitmapUtils.setBit(uint256 a, uint8 b) internal returns (uint256) => setBitCVL[a][b];
    // function BitmapUtils.isEmpty(uint256 a) internal returns (bool) => isEmptyCVL[a];
    function BitmapUtils.noBitsInCommon(uint256 a, uint256 b) internal returns (bool) => noBitsInCommonCVL[a][b];
    function BitmapUtils.isSubsetOf(uint256 a, uint256 b) internal returns (bool) => isSubsetOfCVL[a][b];
    function BitmapUtils.plus(uint256 a, uint256 b) internal returns (uint256) => plusCVL[a][b];
    function BitmapUtils.minus(uint256 a, uint256 b) internal returns (uint256) => minusCVL[a][b];
    
}

/** Ghost variables **/

// BitmapUtils ghost summaries
ghost mapping(bytes => uint256) bytesToBitmapCVL;
ghost mapping(bytes => mapping(uint8 => uint256)) bytesToBitmapCappedCVL;
ghost mapping(bytes => bool) ascendingArrayCVL;
ghost mapping(uint256 => bytes) bitmapToBytesCVL;
ghost mapping(uint256 => uint16) numOnesCVL;
ghost mapping(uint256 => mapping(uint8 => bool)) isSetCVL;
ghost mapping(uint256 => mapping(uint8 => uint256)) setBitCVL;
// ghost mapping(uint256 => bool) isEmptyCVL;
ghost mapping(uint256 => mapping(uint256 => bool)) noBitsInCommonCVL {
    axiom forall uint256 x. forall uint256 y. noBitsInCommonCVL[x][y] == noBitsInCommonCVL[y][x];
}
ghost mapping(uint256 => mapping(uint256 => bool)) isSubsetOfCVL;
ghost mapping(uint256 => mapping(uint256 => uint256)) plusCVL {
    axiom forall uint256 x. forall uint256 y. plusCVL[x][y] == plusCVL[y][x];
}
ghost mapping(uint256 => mapping(uint256 => uint256)) minusCVL;

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
    bool val;
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

/// If my Operator status is REGISTERED ⇔ my quorum bitmap MUST BE nonzero
/// @notice _operatorBitmapHistory overflowing with 
// status: violated
invariant registeredOperatorsHaveNonzeroBitmaps(env e, address operator)
    getOperatorStatus(operator) == IRegistryCoordinator.OperatorStatus.REGISTERED <=>
        getCurrentQuorumBitmap(e, getOperatorId(operator)) != 0 && getOperatorId(operator) != to_bytes32(0)
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
        }
        // preserved registerOperator(
        //     bytes quorumNumbers,
        //     string socket,
        //     IBLSApkRegistry.PubkeyRegistrationParams params,
        //     ISignatureUtils.SignatureWithSaltAndExpiry signature
        // ) with (env e1) {

        // }
        // preserved registerOperatorWithChurn(
        //     bytes quorumNumbers,
        //     string socket,
        //     IBLSApkRegistry.PubkeyRegistrationParams params,
        //     IRegistryCoordinator.OperatorKickParam[] kickParams,
        //     ISignatureUtils.SignatureWithSaltAndExpiry churnSignature,
        //     ISignatureUtils.SignatureWithSaltAndExpiry operatorSignature
        // ) with (env e1) {}
        preserved updateOperators(address[] updatingOperators) with (env e1) {
            requireInvariant oneIdPerOperator(operator, updatingOperators[0]);
            requireInvariant oneIdPerOperator(updatingOperators[0], updatingOperators[1]);
            requireInvariant oneIdPerOperator(updatingOperators[1], operator);
            requireInvariant operatorIdandPubkeyHash(operator);
            requireInvariant operatorIdandPubkeyHash(updatingOperators[0]);
            requireInvariant operatorIdandPubkeyHash(updatingOperators[1]);
            require getQuorumBitmapHistoryLength(getOperatorId(operator)) < max_uint256;
        }
        preserved updateOperatorsForQuorum(address[][] updatingOperators, bytes quorumNumbers) with (env e1) {
            require updatingOperators.length == 1 && quorumNumbers.length == 1;
            requireInvariant oneIdPerOperator(operator, updatingOperators[0][0]);
            requireInvariant oneIdPerOperator(updatingOperators[0][0], updatingOperators[0][1]);
            requireInvariant oneIdPerOperator(updatingOperators[0][1], operator);
            requireInvariant operatorIdandPubkeyHash(operator);
            requireInvariant operatorIdandPubkeyHash(updatingOperators[0][0]);
            requireInvariant operatorIdandPubkeyHash(updatingOperators[0][1]);
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
    getOperatorStatus(operator) == IRegistryCoordinator.OperatorStatus.REGISTERED && 
    quorumInBitmap(assert_uint256(getCurrentQuorumBitmap(e, getOperatorId(operator))), quorumNumber) =>
        indexRegistry.currentOperatorIndex(e, quorumNumber, getOperatorId(operator)) < indexRegistry.totalOperatorsForQuorum(e, quorumNumber)
    {
        preserved deregisterOperator(bytes quorumNumbers) with (env e1) {
            require e1.msg.sender == e.msg.sender;
            requireInvariant oneIdPerOperator(operator, e.msg.sender);
        }
    }

/// if operator is registered for quorum number then operator has stake weight >= minStakeWeight(quorumNumber)
// status: violated
invariant operatorHasNonZeroStakeWeight(env e, address operator, uint8 quorumNumber)
    quorumInBitmap(assert_uint256(getCurrentQuorumBitmap(e, getOperatorId(operator))), quorumNumber) =>
        stakeRegistry.weightOfOperatorForQuorum(e, quorumNumber, operator) >= stakeRegistry.minimumStakeForQuorum(e, quorumNumber);

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