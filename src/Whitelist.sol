// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

event AddedToWhiteList(address indexed added);
event RemovedFromWhiteList(address indexed removed);
/*
 * Note: The OwnableUpgradeable contract is used to ensure that only the owner of the contract
 * can add or remove addresses from the whitelist. It must be OwnableUpgradeable instead of Ownable
 * because RegistryCoordinator is OwnableUpgradeable, and it caused conflicts on onlyOwner modifier.
 */
contract Whitelist is OwnableUpgradeable {
    mapping(address => bool) whitelist;

    modifier onlyWhitelisted() {
        require(isWhitelisted(msg.sender), "not whitelisted");
        _;
    }

    function add(address _address) public onlyOwner {
        whitelist[_address] = true;
        emit AddedToWhiteList(_address);
    }

    function remove(address _address) public onlyOwner {
        whitelist[_address] = false;
        emit RemovedFromWhiteList(_address);
    }

    function isWhitelisted(address _address) public view returns (bool) {
        return whitelist[_address];
    }
}
