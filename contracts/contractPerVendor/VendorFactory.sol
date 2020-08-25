pragma solidity ^0.6.0;

import "./VendorContract.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
    @title VendorFactory
    @notice This contract has the job to instantiate VendorContract. This contract works only after its ownership will be tranfered (see ARD document). Inherits from OpenZeppelin Ownable
    @dev Letting the AuthorityContract create the VendorContract, it would not be deployable due to bytecode too large
 */
contract VendorFactory is Ownable {

    bool public working = false;
    mapping(address => bool) public contracts;

    /**
        @notice Instantiate a contract of type VendorContract with _vendor as its owner
        @dev This function reverts if ownership has not been tranfered (see ARD document for motivation)
        @param _vendor The owner of the new VendorContract
     */
    function createVendorContract(address _vendor) onlyOwner public virtual returns(VendorContract) {

        require(working == true, "Factory is not working");

        VendorContract c = new VendorContract(_vendor, msg.sender);
        contracts[address(c)] = true;

        return c;
    }

    /**
        @notice Override OpenZeppelin transfer method to unlock the creation method 
        @param newOwner The new owner
     */
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