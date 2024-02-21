using ServiceManagerMock as serviceManager;
using StakeRegistryHarness as stakeRegistry;
using BLSApkRegistryHarness as blsApkRegistry;
using IndexRegistryHarness as indexRegistry;
// using DelegationManager as delegation;
use builtin rule sanity;

methods {
    function _.isValidSignature(bytes32 hash, bytes signature) external => NONDET; // isValidSignatureCVL(hash,signature) expect bytes4;
    function _.unpauser() external => unpauser expect address;
    function _.isPauser(address user) external => isPauserCVL(user) expect bool;
    
    // BN254 Library
    function BN254.pairing(BN254.G1Point memory, BN254.G2Point memory, BN254.G1Point memory, BN254.G2Point memory) internal returns (bool) => NONDET;

    // external calls to ServiceManager
    function _.registerOperatorToAVS(address, ISignatureUtils.SignatureWithSaltAndExpiry) external => DISPATCHER(true);
    function _.deregisterOperatorFromAVS(address) external => DISPATCHER(true);

    // Registry contracts
    function StakeRegistryHarness.totalStakeHistory(uint8) external returns (IStakeRegistry.StakeUpdate[]) envfree;
    function StakeRegistry._weightOfOperatorForQuorum(uint8, address) internal returns (uint96, bool) => NONDET;

    function IndexRegistryHarness.operatorCountHistory(uint8) external returns (IIndexRegistry.QuorumUpdate[]) envfree;
    
    function BLSApkRegistryHarness.getApkHistory(uint8) external returns (IBLSApkRegistry.ApkUpdate[]) envfree;
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
}
ghost address unpauser;
ghost mapping(address => bool) pausers;
function isPauserCVL(address user) returns bool {
    return pausers[user];
}

// invariant initializedQuorumHistories(uint8 quorumNumber)
//     quorumNumber < currentContract.quorumCount <=> 
//         stakeRegistry._totalStakeHistory[quorumNumber].length != 0 && 
//         indexRegistry._operatorCountHistory[quorumNumber].length != 0 &&
//         blsApkRegistry.apkHistory[quorumNumber].length != 0;

invariant initializedQuorumHistories(uint8 quorumNumber)
    quorumNumber < currentContract.quorumCount <=> 
        stakeRegistry.totalStakeHistory(quorumNumber).length != 0 && 
        indexRegistry.operatorCountHistory(quorumNumber).length != 0 &&
        blsApkRegistry.getApkHistory(quorumNumber).length != 0;

/// @notice unique address <=> unique operatorId
invariant oneIdPerOperator(address operator1, address operator2)
    operator1 != operator2 => getOperatorId(operator1) != getOperatorId(operator2);

/// @notice one way implication as IndexRegistry.currentOperatorIndex does not get updated on operator deregistration
invariant operatorIndexWithinRange(env e, address operator, uint8 quorumNumber, uint256 blocknumber, uint256 index)
    getOperatorStatus(operator) == IRegistryCoordinator.OperatorStatus.REGISTERED && 
    quorumInBitmap(assert_uint256(getCurrentQuorumBitmap(e, getOperatorId(operator))), quorumNumber) =>
        indexRegistry.currentOperatorIndex(e, quorumNumber, getOperatorId(operator)) < indexRegistry.totalOperatorsForQuorum(e, quorumNumber)
    {
        preserved deregisterOperator(bytes quorumNumbers) with (e) {
            requireInvariant oneIdPerOperator(operator, e.msg.sender);
        }
    }
