// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Test.sol";

import "./IntegrationDeployer.t.sol";
import "../ffi/util/G2Operations.sol";
import "./utils/BitmapStrings.t.sol";
import {ISlashingRegistryCoordinatorTypes} from
    "../../src/interfaces/ISlashingRegistryCoordinator.sol";

contract Constants {
    /// IECDSAStakeRegistryTypes.Quorum Config:

    /// @dev Default OperatorSetParam values used to initialize quorums
    /// NOTE: This means each quorum has an operator limit of MAX_OPERATOR_COUNT by default
    ///       This is a low number because each operator receives its own BLS keypair, which
    ///       is very slow to generate.
    uint32 constant MAX_OPERATOR_COUNT = 5;
    uint16 constant KICK_BIPS_OPERATOR_STAKE = 15000;
    uint16 constant KICK_BIPS_TOTAL_STAKE = 150;

    /// Other:

    /// @dev Number of BLS keypairs to pregenerate. This is a slow operation,
    /// so I've set this to a low number.
    uint256 constant NUM_GENERATED_OPERATORS = MAX_OPERATOR_COUNT + 5;

    uint256 constant MAX_QUORUM_COUNT = 192; // From RegistryCoordinator.MAX_QUORUM_COUNT

    uint16 internal constant BIPS_DENOMINATOR = 10000;
}

contract IntegrationConfig is IntegrationDeployer, G2Operations, Constants {
    using BitmapStrings for *;
    using Strings for *;
    using BN254 for *;
    using BitmapUtils for *;

    /// @dev Tracking variables for randomness and _randConfig
    // All _rand methods use/update this value
    bytes32 random;
    // Every time a new user is generated, it uses a random flag from this array
    bytes userFlags;
    // Every time a quorum is created, it uses random flags pulled from these arrays
    bytes numQuorumFlags;
    bytes numStrategyFlags;
    bytes minStakeFlags;
    bytes fillTypeFlags;
    bytes quorumTypeFlags;
    uint256 constant FLAG = 1;

    /// @dev Flags for userTypes
    uint256 constant DEFAULT = (FLAG << 0);
    uint256 constant ALT_METHODS = (FLAG << 1);

    /// @dev Flags for using SlashingRegistryCoordinator or RegistryCoordinator (M2)
    uint256 constant SLASHING = (FLAG << 0);
    uint256 constant M2 = (FLAG << 1);

    /// @dev Flags for numQuorums and numStrategies
    uint256 constant ONE = (FLAG << 0);
    uint256 constant TWO = (FLAG << 1);
    uint256 constant MANY = (FLAG << 2);
    uint256 constant FIFTEEN = (FLAG << 3);
    uint256 constant TWENTY = (FLAG << 4);
    uint256 constant TWENTYFIVE = (FLAG << 5);

    /// @dev Flags for minimumStake
    uint256 constant NO_MINIMUM = (FLAG << 0);
    uint256 constant HAS_MINIMUM = (FLAG << 1);

    /// @dev Flags for fillTypes
    uint256 constant EMPTY = (FLAG << 0);
    uint256 constant SOME_FILL = (FLAG << 1);
    uint256 constant FULL = (FLAG << 2);

    /// @dev Flags for quorumType
    uint256 constant DELEGATED_STAKE = (FLAG << 0);
    uint256 constant SLASHABLE_STAKE = (FLAG << 1);
    uint256 constant BOTH = (FLAG << 2);

    /// @dev Tracking variables for pregenerated BLS keypairs:
    /// (See _fetchKeypair)
    uint256 fetchIdx = 0;
    uint256[] privKeys;
    IBLSApkRegistryTypes.PubkeyRegistrationParams[] pubkeys;

    /// @dev Current initialized quorums are tracked here:
    uint256 quorumCount;
    uint192 quorumBitmap;
    bytes quorumArray;

    /// @dev Number of operators generated so far
    uint256 numOperators = 0;
    /// @dev current array of operatorIds registered so far per quorum.
    /// does not update and remove if an operator is deregistered however, used for testing updateOperatorsForQuorum
    mapping(uint8 => address[]) operatorsForQuorum;

    /**
     * Since BLS key generation uses FFI, it's pretty slow. Pregenerating keys
     * in the constructor apparently ensures that this only happens once,
     * so this is the best way to speed things up when running multiple tests.
     */
    constructor() {
        for (uint256 i = 0; i < NUM_GENERATED_OPERATORS; i++) {
            IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkey;
            uint256 privKey = uint256(keccak256(abi.encodePacked(i + 1)));

            pubkey.pubkeyG1 = BN254.generatorG1().scalar_mul(privKey);
            pubkey.pubkeyG2 = G2Operations.mul(privKey);

            privKeys.push(privKey);
            pubkeys.push(pubkey);
        }
    }

    /**
     * @dev Used by _configRand to configure what types of quorums get
     * created during setup
     */
    struct QuorumConfig {
        /// @dev The number of quorums created during setup
        uint256 numQuorums; // ONE | TWO | MANY
        /// @dev The number of strategies a quorum will consider
        uint256 numStrategies; // ONE | TWO | MANY
        /// @dev Whether each quorum has a minimum stake
        /// NOTE: Minimum stake is currently MIN_BALANCE by default
        uint256 minimumStake; // NO_MINIMUM | HAS_MINIMUM
        /// @dev Whether each quorum created is pre-populated with operators
        /// NOTE: Default
        uint256 fillTypes; // EMPTY | SOME_FILL | FULL
        /// @dev Whether quorums created are delegated stake quorum, slashable stake quorums, or both
        uint256 quorumType; // DELEGATED_STAKE | SLASHABLE_STAKE | BOTH
    }

    /**
     * @param _randomSeed Fuzz tests supply a random u24 as input
     * @param _userTypes [DEFAULT | ALT_METHODS] - every time a user is generated, it will use these values
     * @param _quorumConfig Quorums that are created/initialized in this method will be configured according
     * to this struct. See `QuorumConfig` above for details on each parameter.
     */
    function _configRand(
        uint24 _randomSeed,
        uint256 _userTypes,
        QuorumConfig memory _quorumConfig
    ) internal {
        emit log_named_uint("_configRand: set random seed to", _randomSeed);
        random = keccak256(abi.encodePacked(_randomSeed));

        // Convert flag bitmaps to byte arrays for easier random lookup
        userFlags = _bitmapToBytes(_userTypes);
        numQuorumFlags = _bitmapToBytes(_quorumConfig.numQuorums);
        numStrategyFlags = _bitmapToBytes(_quorumConfig.numStrategies);
        minStakeFlags = _bitmapToBytes(_quorumConfig.minimumStake);
        fillTypeFlags = _bitmapToBytes(_quorumConfig.fillTypes);
        quorumTypeFlags = _bitmapToBytes(_quorumConfig.quorumType);
        // Sanity check config
        assertTrue(userFlags.length != 0, "_configRand: invalid _userTypes, no flags passed");
        assertTrue(numQuorumFlags.length != 0, "_configRand: invalid numQuorums, no flags passed");
        assertTrue(
            numStrategyFlags.length != 0, "_configRand: invalid numStrategies, no flags passed"
        );
        assertTrue(minStakeFlags.length != 0, "_configRand: invalid minimumStake, no flags passed");
        assertTrue(fillTypeFlags.length != 0, "_configRand: invalid fillTypes, no flags passed");
        assertTrue(quorumTypeFlags.length != 0, "_configRand: invalid quorumType, no flags passed");
        // Decide how many quorums to initialize
        quorumCount = _randQuorumCount();
        quorumBitmap = uint192((1 << quorumCount) - 1);
        quorumArray = BitmapUtils.bitmapToBytesArray(quorumBitmap);
        emit log_named_uint("_configRand: number of quorums being initialized", quorumCount);

        // Default OperatorSetParams for all quorums
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSet =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: MAX_OPERATOR_COUNT,
            kickBIPsOfOperatorStake: KICK_BIPS_OPERATOR_STAKE,
            kickBIPsOfTotalStake: KICK_BIPS_TOTAL_STAKE
        });

        // Initialize each quorum
        for (uint256 i = 0; i < quorumCount; i++) {
            IStakeRegistryTypes.StrategyParams[] memory strategyParams = _randStrategyParams();
            uint96 minimumStake = _randMinStake();

            uint256 quorumType = _randValue(quorumTypeFlags);

            emit log_named_uint("_configRand: creating quorum", i);
            emit log_named_uint("- Max operator count", operatorSet.maxOperatorCount);
            emit log_named_uint("- Num strategies considered", strategyParams.length);
            emit log_named_uint("- Minimum stake", minimumStake);
            emit log_named_uint("- Quorum type", quorumType);

            if (quorumType == DELEGATED_STAKE) {
                cheats.prank(registryCoordinatorOwner);
                slashingRegistryCoordinator.createTotalDelegatedStakeQuorum({
                    operatorSetParams: operatorSet,
                    minimumStake: minimumStake,
                    strategyParams: strategyParams
                });
            } else if (quorumType == SLASHABLE_STAKE) {
                cheats.prank(registryCoordinatorOwner);
                slashingRegistryCoordinator.createSlashableStakeQuorum({
                    operatorSetParams: operatorSet,
                    minimumStake: minimumStake,
                    strategyParams: strategyParams,
                    lookAheadPeriod: 0
                });
            } else if (quorumType == BOTH) {
                // randomly choose one of the two
                uint256 randomChoice = _randValue(quorumTypeFlags);
                if (randomChoice == DELEGATED_STAKE) {
                    cheats.prank(registryCoordinatorOwner);
                    slashingRegistryCoordinator.createTotalDelegatedStakeQuorum({
                        operatorSetParams: operatorSet,
                        minimumStake: minimumStake,
                        strategyParams: strategyParams
                    });
                } else if (randomChoice == SLASHABLE_STAKE) {
                    cheats.prank(registryCoordinatorOwner);
                    slashingRegistryCoordinator.createSlashableStakeQuorum({
                        operatorSetParams: operatorSet,
                        minimumStake: minimumStake,
                        strategyParams: strategyParams,
                        lookAheadPeriod: 0
                    });
                }
            }

            cheats.prank(address(serviceManager));
            allocationManager.updateAVSMetadataURI(address(serviceManager), "test-avs-metadata");

            cheats.prank(registryCoordinatorOwner);
            slashingRegistryCoordinator.createTotalDelegatedStakeQuorum({
                operatorSetParams: operatorSet,
                minimumStake: minimumStake,
                strategyParams: strategyParams
            });
        }

        /// Setup the RegistryCoordinator as M2 RegistryCoordinator with M2 quorums
        /// TODO: refactor Integration framework to test both M2 upgrade path and new
        /// registration/deregistration flow of operatorSets
        _setOperatorSetsEnabled(false);
        _setM2QuorumsDisabled(false);
        _setM2QuorumBitmap(0);

        // Decide how many operators to register for each quorum initially
        uint256 initialOperators = _randInitialOperators(operatorSet);
        emit log(
            string.concat(
                "Registering ", initialOperators.toString(), " initial operators in each quorum"
            )
        );

        // For each initial operator, register for all quorums
        for (uint256 j = 0; j < initialOperators; j++) {
            User operator = _newRandomOperator();

            operator.registerOperator(quorumArray);
            for (uint256 k = 0; k < quorumArray.length; k++) {
                uint8 quorum = uint8(quorumArray[k]);
                operatorsForQuorum[quorum].push(address(operator));
            }
        }

        emit log("=====================");
        emit log("_configRand complete; starting test!");
        emit log("=====================");
    }

    /**
     * Gen/Init methods:
     */
    function _newRandomOperator() internal returns (User) {
        string memory operatorName = string.concat("Operator", numOperators.toString());
        numOperators++;

        (User operator, IStrategy[] memory strategies, uint256[] memory tokenBalances) =
            _randUser(operatorName);

        operator.registerAsOperator();
        operator.depositIntoEigenlayer(strategies, tokenBalances);

        assertTrue(
            delegationManager.isOperator(address(operator)),
            "_newRandomOperator: operator should be registered"
        );

        return operator;
    }

    /// @dev Create a new user with token balances in ALL core-whitelisted strategies
    function _randUser(
        string memory name
    ) internal returns (User, IStrategy[] memory, uint256[] memory) {
        // Create User contract and give it a unique BLS keypair
        (uint256 privKey, IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkey) =
            _fetchKeypair();

        // Use userFlags to pick the kind of user to generate
        User user;
        uint256 userType = _randValue(userFlags);

        if (userType == DEFAULT) {
            user = new OperatorSetUser(name, privKey, pubkey);
        } else if (userType == ALT_METHODS) {
            name = string.concat(name, "_Alt");
            user = new OperatorSetUser_AltMethods(name, privKey, pubkey);
        }

        emit log_named_string("_randUser: Created user", user.NAME());

        (IStrategy[] memory strategies, uint256[] memory balances) = _dealRandTokens(user);
        return (user, strategies, balances);
    }

    function _dealRandTokens(
        User user
    ) internal returns (IStrategy[] memory, uint256[] memory) {
        IStrategy[] memory strategies = new IStrategy[](allStrats.length);
        uint256[] memory balances = new uint256[](allStrats.length);
        emit log_named_string("_dealRandTokens: dealing assets to", user.NAME());

        // Deal the user a random balance between [MIN_BALANCE, MAX_BALANCE] for each existing strategy
        for (uint256 i = 0; i < allStrats.length; i++) {
            IStrategy strat = allStrats[i];
            IERC20 underlyingToken = strat.underlyingToken();

            uint256 balance = _randUint({min: MIN_BALANCE, max: MAX_BALANCE});
            StdCheats.deal(address(underlyingToken), address(user), balance);

            strategies[i] = strat;
            balances[i] = balance;
        }

        return (strategies, balances);
    }

    function _dealMaxTokens(
        User user
    ) internal returns (IStrategy[] memory, uint256[] memory) {
        IStrategy[] memory strategies = new IStrategy[](allStrats.length);
        uint256[] memory balances = new uint256[](allStrats.length);
        emit log_named_string("_dealMaxTokens: dealing assets to", user.NAME());

        // Deal the user the 100 * MAX_BALANCE for each existing strategy
        for (uint256 i = 0; i < allStrats.length; i++) {
            IStrategy strat = allStrats[i];
            IERC20 underlyingToken = strat.underlyingToken();

            uint256 balance = 100 * MAX_BALANCE;
            StdCheats.deal(address(underlyingToken), address(user), balance);

            strategies[i] = strat;
            balances[i] = balance;
        }

        return (strategies, balances);
    }

    /// @param incomingOperator the operator that will churn operators in churnQuorums
    /// @param churnQuorums the quorums that we need to select churnable operators from
    /// @param standardQuorums the quorums that we want to register for WITHOUT churn
    /// @return churnTargets: one churnable operator for each churnQuorum
    function _getChurnTargets(
        User incomingOperator,
        bytes memory churnQuorums,
        bytes memory standardQuorums
    ) internal returns (User[] memory) {
        emit log_named_string("_getChurnTargets: incoming operator", incomingOperator.NAME());
        emit log_named_string("_getChurnTargets: churnQuorums", churnQuorums.toString());
        emit log_named_string("_getChurnTargets: standardQuorums", standardQuorums.toString());

        // For each standard registration quorum, eject operators to make room
        _makeRoom(standardQuorums);

        // For each churn quorum, select operators as churn targets
        User[] memory churnTargets = new User[](churnQuorums.length);

        for (uint256 i = 0; i < churnQuorums.length; i++) {
            uint8 quorum = uint8(churnQuorums[i]);

            ISlashingRegistryCoordinatorTypes.OperatorSetParam memory params =
                slashingRegistryCoordinator.getOperatorSetParams(quorum);

            // Sanity check - make sure we're at the operator cap
            uint32 curNumOperators = indexRegistry.totalOperatorsForQuorum(quorum);
            assertTrue(
                curNumOperators >= params.maxOperatorCount,
                "_getChurnTargets: non-full quorum cannot be churned"
            );

            // Get a random registered operator
            churnTargets[i] = _selectRandRegisteredOperator(quorum);
            emit log_named_string(
                string.concat(
                    "_getChurnTargets: selected churn target for quorum ",
                    uint256(quorum).toString()
                ),
                churnTargets[i].NAME()
            );

            uint96 currentTotalStake = stakeRegistry.getCurrentTotalStake(quorum);
            uint96 operatorToChurnStake =
                stakeRegistry.getCurrentStake(churnTargets[i].operatorId(), quorum);

            // Ensure the incoming operator exceeds the individual stake threshold --
            // more stake than the outgoing operator by kickBIPsOfOperatorStake
            while (
                _getWeight(quorum, incomingOperator)
                    <= _individualKickThreshold(operatorToChurnStake, params)
                    || operatorToChurnStake
                        >= _totalKickThreshold(
                            currentTotalStake + _getWeight(quorum, incomingOperator), params
                        )
            ) {
                (IStrategy[] memory strategies, uint256[] memory balances) =
                    _dealMaxTokens(incomingOperator);
                incomingOperator.depositIntoEigenlayer(strategies, balances);
            }
        }

        // Oh jeez that was a lot. Return the churn targets
        return churnTargets;
    }

    /// From RegistryCoordinator._individualKickThreshold
    function _individualKickThreshold(
        uint96 operatorStake,
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory setParams
    ) internal pure returns (uint96) {
        return operatorStake * setParams.kickBIPsOfOperatorStake / BIPS_DENOMINATOR;
    }

    /// From RegistryCoordinator._totalKickThreshold
    function _totalKickThreshold(
        uint96 totalStake,
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory setParams
    ) internal pure returns (uint96) {
        return totalStake * setParams.kickBIPsOfTotalStake / BIPS_DENOMINATOR;
    }

    function _getWeight(uint8 quorum, User operator) internal view returns (uint96) {
        return stakeRegistry.weightOfOperatorForQuorum(quorum, address(operator));
    }

    function _makeRoom(
        bytes memory quorums
    ) private {
        emit log_named_string(
            "_getChurnTargets: making room by removing operators from quorums", quorums.toString()
        );

        for (uint256 i = 0; i < quorums.length; i++) {
            uint8 quorum = uint8(quorums[i]);
            uint32 maxOperatorCount =
                slashingRegistryCoordinator.getOperatorSetParams(quorum).maxOperatorCount;

            // Continue deregistering until we're under the cap
            // This uses while in case we tested a config change that lowered the max count
            while (indexRegistry.totalOperatorsForQuorum(quorum) >= maxOperatorCount) {
                // Select a random operator and deregister them from the quorum
                User operatorToKick = _selectRandRegisteredOperator(quorum);

                bytes memory quorumArr = new bytes(1);
                quorumArr[0] = bytes1(quorum);
                operatorToKick.deregisterOperator(quorumArr);
            }
        }
    }

    function _selectRandRegisteredOperator(
        uint8 quorum
    ) internal returns (User) {
        uint32 curNumOperators = indexRegistry.totalOperatorsForQuorum(quorum);

        bytes32 randId = indexRegistry.getLatestOperatorUpdate({
            quorumNumber: quorum,
            operatorIndex: uint32(_randUint({min: 0, max: curNumOperators - 1}))
        }).operatorId;

        return User(blsApkRegistry.getOperatorFromPubkeyHash(randId));
    }

    function _fetchKeypair()
        internal
        returns (uint256, IBLSApkRegistryTypes.PubkeyRegistrationParams memory)
    {
        // should probably just generate another keypair at this point
        if (fetchIdx == privKeys.length) {
            revert(
                "_fetchKeypair: not enough generated keys. Check IntegrationDeployer.constructor"
            );
        }

        uint256 privKey = privKeys[fetchIdx];
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkey = pubkeys[fetchIdx];
        fetchIdx++;

        return (privKey, pubkey);
    }

    /// @dev Uses `random` to return a random uint, with a range given by `min` and `max` (inclusive)
    /// @return `min` <= result <= `max`
    function _randUint(uint256 min, uint256 max) internal returns (uint256) {
        uint256 range = max - min + 1;

        // calculate the number of bits needed for the range
        uint256 bitsNeeded = 0;
        uint256 tempRange = range;
        while (tempRange > 0) {
            bitsNeeded++;
            tempRange >>= 1;
        }

        // create a mask for the required number of bits
        // and extract the value from the hash
        uint256 mask = (1 << bitsNeeded) - 1;
        uint256 value = uint256(random) & mask;

        // in case value is out of range, wrap around or retry
        while (value >= range) {
            value = (value - range) & mask;
        }

        // Hash `random` with itself so the next value we generate is different
        random = keccak256(abi.encodePacked(random));
        return min + value;
    }

    function _randBool() internal returns (bool) {
        return _randUint({min: 0, max: 1}) == 0;
    }

    function _selectRand(
        bytes memory quorums
    ) internal returns (bytes memory) {
        assertTrue(quorums.length != 0, "_selectRand: tried to select from empty quorum list");

        uint192 result;
        for (uint256 i = 0; i < quorums.length; i++) {
            if (_randBool()) {
                result = uint192(result.setBit(uint8(quorums[i])));
            }
        }

        // Ensure we return at least one quorum
        if (result.isEmpty()) {
            result = uint192(result.setBit(uint8(quorums[0])));
        }

        bytes memory resultArray = result.bitmapToBytesArray();

        emit log_named_uint("_selectRand: input quorum count", quorums.length);
        emit log_named_uint("_selectRand: selected quorum count", resultArray.length);
        return resultArray;
    }

    /// @dev Select a random value from `arr` and return it. Reverts if arr is empty
    function _randValue(
        bytes memory arr
    ) internal returns (uint256) {
        assertTrue(arr.length > 0, "_randValue: tried to select value from empty array");

        uint256 idx = _randUint({min: 0, max: arr.length - 1});
        return uint256(uint8(arr[idx]));
    }

    /// Private _randX methods used by _configRand:

    /// @dev Select a random number of quorums to initialize
    /// NOTE: This should only be used when initializing quorums for the first time (in _configRand)
    function _randQuorumCount() private returns (uint256) {
        uint256 quorumFlag = _randValue(numQuorumFlags);

        if (quorumFlag == ONE) {
            return 1;
        } else if (quorumFlag == TWO) {
            return 2;
        } else if (quorumFlag == MANY) {
            // Ideally this would be MAX_QUORUM_COUNT, but that really slows tests
            // that have users register for all quorums
            return _randUint({min: 3, max: 10});
        } else {
            revert("_randQuorumCount: flag not recognized");
        }
    }

    /// @dev Select a random number of strategies and multipliers to create a quorum with
    /// NOTE: This should only be used when creating a quorum for the first time. If you're
    /// selecting strategies to add after the quorum has been initialized, this is likely to
    /// return duplicates.
    function _randStrategyParams() private returns (IStakeRegistryTypes.StrategyParams[] memory) {
        uint256 strategyFlag = _randValue(numStrategyFlags);
        uint256 strategyCount;

        if (strategyFlag == ONE) {
            strategyCount = 1;
        } else if (strategyFlag == TWO) {
            strategyCount = 2;
        } else if (strategyFlag == MANY) {
            strategyCount = _randUint({min: 3, max: allStrats.length - 1});
        } else if (strategyFlag == FIFTEEN) {
            strategyCount = 15;
        } else if (strategyFlag == TWENTY) {
            strategyCount = 20;
        } else if (strategyFlag == TWENTYFIVE) {
            strategyCount = 25;
        } else {
            revert("_randStrategyCount: flag not recognized");
        }

        IStakeRegistryTypes.StrategyParams[] memory params =
            new IStakeRegistryTypes.StrategyParams[](strategyCount);

        for (uint256 i = 0; i < params.length; i++) {
            params[i] = IStakeRegistryTypes.StrategyParams({
                strategy: allStrats[i],
                multiplier: DEFAULT_STRATEGY_MULTIPLIER
            });
        }

        return params;
    }

    /**
     * @dev Uses _randFillType to determine how many operators to register for a quorum initially
     * @return The number of operators to register
     */
    function _randInitialOperators(
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSet
    ) private returns (uint256) {
        uint256 fillTypeFlag = _randValue(fillTypeFlags);

        if (fillTypeFlag == EMPTY) {
            return 0;
        } else if (fillTypeFlag == SOME_FILL) {
            return _randUint({min: 1, max: operatorSet.maxOperatorCount - 1});
        } else if (fillTypeFlag == FULL) {
            return operatorSet.maxOperatorCount;
        } else {
            revert("_randInitialOperators: flag not recognized");
        }
    }

    /// @dev Select a random number of quorums to initialize
    function _randMinStake() private returns (uint96) {
        uint256 minStakeFlag = _randValue(minStakeFlags);

        if (minStakeFlag == NO_MINIMUM) {
            return 0;
        } else if (minStakeFlag == HAS_MINIMUM) {
            return uint96(MIN_BALANCE);
        } else {
            revert("_randQuorumCount: flag not recognized");
        }
    }

    /**
     * @dev Converts a bitmap into an array of bytes
     * @dev Each byte in the input is processed as indicating a single bit to flip in the bitmap
     */
    function _bitmapToBytes(
        uint256 bitmap
    ) internal pure returns (bytes memory bytesArray) {
        for (uint256 i = 0; i < 256; ++i) {
            // Mask for i-th bit
            uint256 mask = uint256(1 << i);

            // emit log_named_uint("mask: ", mask);

            // If the i-th bit is flipped, add a byte to the return array
            if (bitmap & mask != 0) {
                bytesArray = bytes.concat(bytesArray, bytes1(uint8(1 << i)));
            }
        }
        return bytesArray;
    }
}
