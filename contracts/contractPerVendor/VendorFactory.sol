pragma solidity ^0.6.0;

import "./VendorContract.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VendorFactory is Ownable {

    bool public working = false;
    mapping(address => bool) public contracts;

    function createVendorContract(address _vendor) onlyOwner public virtual returns(VendorContract) {

        require(working == true, "Factory is not working");

        VendorContract c = new VendorContract(_vendor, msg.sender);
        contracts[address(c)] = true;

        return c;
    }

    function transferOwnership(address newOwner) onlyOwner public virtual override {
        super.transferOwnership(newOwner);
        working = true;        
    }
}

contract VendorFactoryTest is VendorFactory {

    event ContractAddress(address c);

    function createVendorContract(address _vendor) onlyOwner public virtual override returns(VendorContract) {
        VendorContract c = super.createVendorContract(_vendor);
        emit ContractAddress(address(c));
    }
}