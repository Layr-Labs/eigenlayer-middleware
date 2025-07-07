import "Summaries/BN254-nondet.spec";
import "Summaries/Math.spec";

methods{
    function _.isRegistered(KeyRegistrar.OperatorSet, address) external => DISPATCHER(true);
    function _.getBN254Key(KeyRegistrar.OperatorSet, address) external => DISPATCHER(true);
    function _.merkleizeKeccak(bytes32[] memory) internal => NONDET;
    // function _getOperatorWeights(BN254TableCalculator.OperatorSet calldata) internal returns (address[] memory, uint256[][] memory) => returnEmptyWeights();

    unresolved external in _._ => DISPATCH
    [ 
        KeyRegistrar.isRegistered(BN254TableCalculator.OperatorSet, address),
        KeyRegistrar.getBN254Key(BN254TableCalculator.OperatorSet, address),
    ] default NONDET;
}

use builtin rule sanity filtered { f -> f.contract == currentContract }

function returnEmptyWeights() returns (address[], uint256[][]) {
    address[] addresses;
    uint256[][] weights;

    return (addresses, weights);
}  