// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "test/integration/User.t.sol";

import "test/integration/IntegrationChecks.t.sol";

contract Integration_AVS_Sync_GasCosts_FFI is IntegrationChecks {
    using BN254 for *;
    using BitmapUtils for *;

    // Private keys sorted by operatorIds.
    uint256[] public privateKeys = [853, 690, 815, 398, 987, 432, 946, 717, 760, 840, 719, 714, 11, 554, 528, 368, 160, 22, 562, 266, 827, 488, 335, 566, 365, 54, 6, 733, 835, 656, 496, 472, 126, 50, 643, 632, 421, 797, 610, 737, 154, 918, 819, 694, 556, 608, 203, 521, 188, 908, 400, 349, 290, 463, 680, 973, 204, 439, 822, 799, 795, 251, 482, 326, 411, 839, 851, 652, 458, 108, 92, 278, 8, 773, 302, 699, 936, 427, 321, 700, 683, 36, 828, 732, 963, 664, 776, 161, 460, 426, 878, 96, 572, 678, 898, 372, 764, 579, 215, 507, 533, 965, 72, 708, 706, 334, 722, 665, 446, 397, 151, 802, 224, 753, 206, 190, 569, 253, 735, 578, 859, 711, 135, 944, 344, 655, 202, 743, 292, 176, 262, 961, 270, 117, 502, 546, 247, 31, 663, 515, 850, 509, 728, 424, 197, 239, 905, 545, 121, 438, 513, 881, 233, 221, 593, 831, 491, 282, 979, 410, 873, 316, 210, 371, 40, 255, 329, 483, 975, 742, 214, 813, 691, 467, 830, 808, 951, 924, 147, 705, 772, 30, 486, 576, 469, 331, 27, 313, 849, 805, 499, 404, 178, 10, 399, 485, 627, 60, 709, 570, 97, 894, 88, 264, 245, 129, 818, 218, 395, 387, 110, 455, 695, 199, 648, 444, 435, 230, 84, 489, 649, 385, 274, 95, 442, 899, 999, 651, 310, 227, 823, 538, 345, 229, 551, 24, 686, 877, 707, 671, 585, 530, 952, 28, 692, 336, 673, 777, 789, 366, 781, 872, 386, 64, 342, 244, 445, 816, 332, 436, 596, 148, 425, 863, 967, 611, 153, 749, 940, 150, 280, 634, 631, 954, 891, 666, 319, 93, 807, 82, 79, 91, 146, 291, 78, 923, 910, 320, 529, 857, 945, 205, 602, 974, 41, 503, 868, 783, 303, 536, 523, 357, 409, 832, 474, 862, 516, 140, 617, 543, 356, 77, 328, 976, 46, 834, 750, 99, 633, 949, 568, 636, 766, 363, 174, 138, 112, 574, 541, 703, 81, 412, 98, 477, 452, 755, 598, 464, 880, 884, 418, 829, 645, 607, 279, 820, 66, 416, 517, 384, 29, 192, 59, 15, 573, 94, 383, 981, 889, 914, 172, 322, 248, 845, 775, 1000, 854, 817, 668, 724, 786, 575, 710, 825, 407, 592, 890, 911, 641, 544, 989, 347, 196, 125, 370, 459, 803, 454, 564, 939, 658, 624, 996, 142, 514, 758, 848, 980, 955, 855, 298, 119, 391, 341, 130, 577, 798, 323, 986, 58, 171, 14, 959, 234, 838, 811, 958, 715, 902, 846, 571, 456, 268, 882, 257, 591, 497, 630, 20, 136, 672, 621, 744, 791, 314, 252, 367, 833, 23, 693, 726, 595, 276, 620, 167, 325, 401, 481, 63, 730, 771, 613, 614, 943, 526, 604, 104, 932, 856, 263, 650, 590, 232, 462, 931, 236, 915, 402, 644, 315, 213, 249, 869, 179, 312, 718, 675, 493, 903, 542, 287, 752, 285, 487, 661, 616, 182, 888, 929, 842, 364, 720, 935, 396, 763, 235, 226, 879, 346, 916, 615, 800, 972, 906, 547, 997, 198, 500, 39, 193, 864, 837, 301, 484, 362, 836, 293, 913, 324, 269, 520, 25, 169, 745, 960, 883, 61, 741, 382, 115, 220, 953, 612, 970, 207, 796, 901, 865, 53, 275, 408, 639, 875, 265, 756, 887, 133, 586, 296, 450, 433, 200, 49, 662, 2, 4, 183, 697, 222, 479, 429, 747, 143, 713, 784, 982, 539, 380, 75, 667, 601, 992, 457, 70, 103, 587, 785, 107, 186, 679, 804, 821, 567, 201, 928, 461, 413, 120, 67, 164, 441, 89, 962, 738, 801, 242, 740, 373, 759, 68, 490, 43, 358, 677, 937, 778, 589, 947, 565, 414, 861, 712, 299, 83, 904, 978, 886, 969, 701, 453, 933, 757, 76, 721, 286, 311, 968, 156, 184, 998, 994, 921, 159, 790, 934, 12, 128, 519, 307, 809, 687, 228, 393, 52, 912, 217, 113, 736, 195, 858, 925, 21, 170, 305, 892, 977, 360, 139, 810, 71, 727, 669, 622, 919, 32, 173, 208, 34, 535, 957, 782, 792, 874, 48, 132, 177, 57, 13, 475, 243, 647, 352, 5, 494, 277, 681, 580, 338, 158, 920, 350, 300, 284, 626, 297, 369, 806, 470, 895, 603, 420, 768, 761, 33, 191, 449, 359, 375, 844, 561, 86, 355, 606, 676, 734, 271, 381, 716, 767, 337, 688, 938, 746, 540, 942, 209, 451, 267, 907, 731, 674, 180, 619, 166, 893, 100, 704, 993, 294, 583, 770, 739, 256, 508, 495, 440, 289, 145, 237, 557, 109, 187, 102, 80, 843, 273, 37, 38, 354, 584, 794, 134, 194, 927, 922, 885, 118, 65, 684, 45, 431, 419, 281, 582, 531, 504, 471, 900, 51, 896, 124, 216, 466, 26, 378, 9, 137, 116, 588, 988, 423, 729, 157, 600, 152, 698, 106, 774, 448, 950, 56, 876, 379, 956, 163, 702, 511, 69, 3, 473, 990, 181, 555, 563, 165, 549, 447, 560, 510, 552, 304, 629, 930, 518, 826, 991, 17, 16, 35, 505, 723, 480, 478, 841, 254, 640, 405, 867, 522, 175, 468, 926, 852, 241, 860, 74, 443, 501, 769, 394, 246, 225, 966, 388, 111, 272, 259, 376, 985, 765, 984, 231, 597, 548, 374, 295, 870, 917, 897, 725, 642, 780, 422, 283, 971, 415, 240, 787, 238, 340, 149, 527, 550, 377, 964, 558, 144, 553, 788, 618, 351, 330, 525, 685, 625, 85, 42, 465, 941, 762, 47, 476, 751, 871, 189, 212, 754, 824, 223, 748, 7, 532, 670, 162, 403, 1, 659, 306, 657, 317, 623, 318, 605, 537, 131, 689, 308, 430, 168, 309, 599, 682, 654, 866, 90, 327, 581, 909, 635, 114, 559, 123, 127, 660, 646, 288, 19, 389, 793, 406, 638, 812, 343, 62, 498, 437, 44, 260, 122, 101, 628, 779, 417, 847, 696, 492, 211, 434, 339, 594, 333, 219, 348, 18, 250, 105, 512, 185, 524, 506, 155, 948, 141, 55, 428, 637, 392, 609, 995, 361, 983, 261, 653, 258, 87, 353, 390, 73, 534, 814];
    bytes32[] public operatorIds;
    address[] public operatorAddresses;

    constructor() {
        // Emit generated BLS keys for storing to config file
        // Should already be done and added to test/ffi/configs/operatorBLSKeys.json
        // for 200 operators
        // _generateOperatorKeys();

        // read from test/ffi/configs/operatorBLSKeys.json
        string memory keysConfigPath = string(bytes("test/ffi/configs/operatorBLSKeys.json"));

        // READ JSON CONFIG DATA
        string memory config_data = vm.readFile(keysConfigPath);
        for (uint256 i = 0; i < MAX_OPERATOR_COUNT; i++) {
            IBLSApkRegistry.PubkeyRegistrationParams memory pubkey;
            uint256 privateKey = privateKeys[i];
            // G1
            pubkey.pubkeyG1.X = stdJson.readUint(
                config_data,
                string.concat(".G1x[", vm.toString(i), "]")
            );
            pubkey.pubkeyG1.Y = stdJson.readUint(
                config_data,
                string.concat(".G1y[", vm.toString(i), "]")
            );
            // G2 
            pubkey.pubkeyG2.X[1] = stdJson.readUint(
                config_data,
                string.concat(".G2x1[", vm.toString(i), "]")
            );
            pubkey.pubkeyG2.Y[1] = stdJson.readUint(
                config_data,
                string.concat(".G2y1[", vm.toString(i), "]")
            );
            pubkey.pubkeyG2.X[0] = stdJson.readUint(
                config_data,
                string.concat(".G2x0[", vm.toString(i), "]")
            );
            pubkey.pubkeyG2.Y[0] = stdJson.readUint(
                config_data,
                string.concat(".G2y0[", vm.toString(i), "]")
            );
            privKeys.push(privateKey);
            pubkeys.push(pubkey);
        }
    }

    function _generateOperatorKeys() internal {
        for (uint256 i = 0; i < 200; i++) {
            IBLSApkRegistry.PubkeyRegistrationParams memory pubkey;
            uint256 privateKey = privateKeys[i];
            pubkey.pubkeyG1 = BN254.generatorG1().scalar_mul(privateKey);
            pubkey.pubkeyG2 = G2Operations.mul(privateKey);

            emit log_uint(pubkey.pubkeyG1.X);
            emit log_uint(pubkey.pubkeyG1.Y);

            emit log_uint(pubkey.pubkeyG2.X[1]);
            emit log_uint(pubkey.pubkeyG2.Y[1]);
            emit log_uint(pubkey.pubkeyG2.X[0]);
            emit log_uint(pubkey.pubkeyG2.Y[0]);

            privKeys.push(privateKey);
            pubkeys.push(pubkey);
        }
    }

    /// forge-config: default.fuzz.runs = 1
    function test_gasCosts_25Strats() public {
        _configRand({
            _randomSeed: 1,
            _userTypes: DEFAULT,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE,
                numStrategies: TWENTYFIVE,
                minimumStake: NO_MINIMUM,
                fillTypes: FULL
            })
        });
        _updateOperators_SingleQuorum();
    }

    // Configure quorum with several strategies and log gas costs
    /// forge-config: default.fuzz.runs = 1
    function test_gasCosts_20Strats() public {
        _configRand({
            _randomSeed: 1,
            _userTypes: DEFAULT,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE,
                numStrategies: TWENTY,
                minimumStake: NO_MINIMUM,
                fillTypes: FULL
            })
        });

        _updateOperators_SingleQuorum();
    }

    /// forge-config: default.fuzz.runs = 1
    function test_gasCosts_15Strats() public {
        _configRand({
            _randomSeed: 1,
            _userTypes: DEFAULT,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE,
                numStrategies: FIFTEEN,
                minimumStake: NO_MINIMUM,
                fillTypes: FULL
            })
        });
        _updateOperators_SingleQuorum();
    }

    function _updateOperators_SingleQuorum() internal {
        // Sort operator addresses
        address[] memory operators = operatorsForQuorum[0];
        operators = _sortArray(operators);

        // Call params
        address[][] memory operatorsPerQuorum = new address[][](1);
        operatorsPerQuorum[0] = operators;
        bytes memory quorumNumbers = quorumArray;

        // Update Operators for quorum 0
        uint256 gasBefore = gasleft();
        registryCoordinator.updateOperatorsForQuorum(operatorsPerQuorum, quorumNumbers);
        uint256 gasAfter = gasleft();
        // emit log_uint(gasBefore - gasAfter);
        console.log(gasBefore - gasAfter);
        console.log("Num operators updated: ", operators.length);
        console.log("Gas used for updateOperatorsForQuorum: ", gasBefore - gasAfter);
    }

    function _sortArray(address[] memory arr) internal pure returns (address[] memory) {
        uint256 l = arr.length;
        for(uint i = 0; i < l; i++) {
            for(uint j = i+1; j < l ;j++) {
                if(arr[i] > arr[j]) {
                    address temp = arr[i];
                    arr[i] = arr[j];
                    arr[j] = temp;
                }
            }
        }
        return arr;
    }
}