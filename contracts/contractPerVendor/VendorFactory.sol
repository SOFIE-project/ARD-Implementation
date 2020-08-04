pragma solidity ^0.6.0;

import "./VendorContract.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VendorFactory is Ownable {

    mapping(address => bool) public contracts;

    constructor(address _authorityContract) public {

        transferOwnership(_authorityContract); 
    }

    function createVendorContract(address _vendor) onlyOwner public returns(VendorContract) {

        VendorContract c = new VendorContract(_vendor, msg.sender);
        contracts[address(c)] = true;

        return c;
    }
}