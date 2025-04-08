// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

/**
 * @title MerkleTreeLib
 * @notice Library for Merkle tree operations, specifically for building Merkle trees and generating/verifying proofs
 */
library MerkleTreeLib {
    /**
     * @notice Computes the Merkle root from an array of leaf nodes
     * @param leaves Array of leaf node hashes
     * @return root The Merkle root
     */
    function merkleRoot(bytes32[] memory leaves) internal pure returns (bytes32 root) {
        require(leaves.length > 0, "Empty leaves");
        
        if (leaves.length == 1) {
            return leaves[0];
        }
        
        // Create a new array for the next level of the tree
        uint256 n = leaves.length;
        uint256 nextLevelSize = (n + 1) / 2;
        bytes32[] memory nextLevel = new bytes32[](nextLevelSize);
        
        // Combine pairs of nodes to form the next level
        for (uint256 i = 0; i < n; i += 2) {
            uint256 j = i / 2;
            if (i + 1 < n) {
                nextLevel[j] = keccak256(abi.encodePacked(leaves[i], leaves[i + 1]));
            } else {
                // If there's an odd number of nodes, the last node is carried forward
                nextLevel[j] = leaves[i];
            }
        }
        
        // Recursively compute the root of the next level
        return merkleRoot(nextLevel);
    }
    
    /**
     * @notice Generates a Merkle proof for a leaf at the specified index
     * @param leaves Array of leaf node hashes
     * @param index Index of the leaf to generate a proof for
     * @return proof The Merkle proof as a bytes array
     */
    function getProof(bytes32[] memory leaves, uint256 index) internal pure returns (bytes memory) {
        require(leaves.length > 0, "Empty leaves");
        require(index < leaves.length, "Index out of bounds");
        
        if (leaves.length == 1) {
            return "";
        }
        
        // Initialize proof
        bytes32[] memory siblings = new bytes32[]((leaves.length <= 2) ? 1 : 32 - clz(leaves.length - 1));
        uint256 siblingCount = 0;
        
        // Start with the leaves
        bytes32[] memory currentLevel = leaves;
        uint256 currentIndex = index;
        
        // Traverse the tree from bottom to top
        while (currentLevel.length > 1) {
            uint256 n = currentLevel.length;
            uint256 nextLevelSize = (n + 1) / 2;
            bytes32[] memory nextLevel = new bytes32[](nextLevelSize);
            
            // Get sibling index
            uint256 siblingIndex = (currentIndex % 2 == 0) ? currentIndex + 1 : currentIndex - 1;
            
            // Add sibling to proof if it exists
            if (siblingIndex < n) {
                siblings[siblingCount++] = currentLevel[siblingIndex];
            }
            
            // Compute next level
            for (uint256 i = 0; i < n; i += 2) {
                uint256 j = i / 2;
                if (i + 1 < n) {
                    nextLevel[j] = keccak256(abi.encodePacked(currentLevel[i], currentLevel[i + 1]));
                } else {
                    nextLevel[j] = currentLevel[i];
                }
            }
            
            // Update current index for next level
            currentIndex = currentIndex / 2;
            currentLevel = nextLevel;
        }
        
        // Resize the siblings array to the actual number of siblings
        assembly {
            mstore(siblings, siblingCount)
        }
        
        // Encode the siblings array as bytes
        return abi.encode(siblings);
    }
    
    /**
     * @notice Verifies a Merkle proof
     * @param root The Merkle root
     * @param leaf The leaf node being verified
     * @param index The index of the leaf in the tree
     * @param proof The Merkle proof as a bytes array
     * @return True if the proof is valid, false otherwise
     */
    function verifyProof(
        bytes32 root, 
        bytes32 leaf, 
        uint256 index, 
        bytes memory proof
    ) internal pure returns (bool) {
        // Decode the proof
        bytes32[] memory siblings = abi.decode(proof, (bytes32[]));
        
        // Start with the leaf
        bytes32 computedHash = leaf;
        
        // Traverse the tree from bottom to top
        for (uint256 i = 0; i < siblings.length; i++) {
            bytes32 sibling = siblings[i];
            
            // Determine if the current node is a left or right child
            if (index % 2 == 0) {
                // Current node is a left child
                computedHash = keccak256(abi.encodePacked(computedHash, sibling));
            } else {
                // Current node is a right child
                computedHash = keccak256(abi.encodePacked(sibling, computedHash));
            }
            
            // Move up to the parent
            index = index / 2;
        }
        
        // The computed hash should equal the root
        return computedHash == root;
    }
    
    /**
     * @notice Count leading zeros in a number's binary representation
     * @param x The number to count leading zeros for
     * @return The number of leading zeros
     */
    function clz(uint256 x) internal pure returns (uint8) {
        if (x == 0) return 255; // Can only store up to 255 in uint8
        
        uint8 n = 0;
        if (x & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000 == 0) { n += 128; x <<= 128; }
        if (x & 0xFFFFFFFFFFFFFFFF000000000000000000000000000000000000000000000000 == 0) { n += 64; x <<= 64; }
        if (x & 0xFFFFFFFF00000000000000000000000000000000000000000000000000000000 == 0) { n += 32; x <<= 32; }
        if (x & 0xFFFF000000000000000000000000000000000000000000000000000000000000 == 0) { n += 16; x <<= 16; }
        if (x & 0xFF00000000000000000000000000000000000000000000000000000000000000 == 0) { n += 8; x <<= 8; }
        if (x & 0xF000000000000000000000000000000000000000000000000000000000000000 == 0) { n += 4; x <<= 4; }
        if (x & 0xC000000000000000000000000000000000000000000000000000000000000000 == 0) { n += 2; x <<= 2; }
        if (x & 0x8000000000000000000000000000000000000000000000000000000000000000 == 0) { n += 1; }
        
        return n;
    }
}