using ServiceManagerMock as serviceManager;
using StakeRegistry as stakeRegistry;
using BLSApkRegistry as blsApkRegistry;
using IndexRegistry as indexRegistry;
using DelegationManager as delegation;
methods {
    function _.isValidSignature(bytes32 hash, bytes signature) external => NONDET; // isValidSignatureCVL(hash,signature) expect bytes4;
    function _.unpauser() external => unpauser expect address;
    function _.isPauser(address user) external => isPauserCVL(user) expect bool;
}
ghost address unpauser;
ghost mapping(address => bool) pausers;
function isPauserCVL(address user) returns bool {
    return pausers[user];
}
use builtin rule sanity;
