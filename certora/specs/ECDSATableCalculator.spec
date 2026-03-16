methods {
    function _.isRegistered(KeyRegistrar.OperatorSet, address) external => DISPATCHER(true);
    function _.getECDSAAddress(KeyRegistrar.OperatorSet, address) external => DISPATCHER(true);

    unresolved external in _._ => DISPATCH[
        KeyRegistrar.getECDSAAddress(KeyRegistrar.OperatorSet, address),
        KeyRegistrar.isRegistered(KeyRegistrar.OperatorSet, address),
    ] default NONDET;
}

use builtin rule sanity filtered { f -> f.contract == currentContract }