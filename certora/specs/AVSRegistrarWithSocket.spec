import "AVSRegistrar.spec";
use builtin rule sanity filtered { f -> f.contract == currentContract }
use rule registerOperatorOnlyAllocationManager; 
use rule registerOperatorOnlyValidKeys;
use rule deregisterOperatorOnlyAllocationManager;