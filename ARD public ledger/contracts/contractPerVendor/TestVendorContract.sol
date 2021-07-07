pragma solidity ^0.6.0;

import "./VendorContract.sol";
import "./VendorFactory.sol";

/**
    @title TestVendorContract
    @notice This contract extends VendorContract for testing purposes
 */
contract TestVendorContract is VendorContract {

    /**
        @notice The constructor calls the parent constructor
        @param _vendor The address of the vendor EOA
        @param _authority The address of the AuthorityContract
     */
    constructor(address _vendor, address _authority) VendorContract(_vendor, _authority) public {    }



   function debug_setTimelock(bytes32 _vulnerabilityHash, uint32 _ackTimelock, uint32 _timelock) external {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityHash];

        v.ackTimelock = _ackTimelock;
        v.timelock = _timelock;
    }    
}

contract TestVendorFactory is VendorFactory {

    function createVendorContract(address _vendor) onlyOwner public override returns(VendorContract) {

        require(working == true, "Factory is not working");

        VendorContract c = new TestVendorContract(_vendor, msg.sender);
        contracts[address(c)] = true;

        return c;
    }
}