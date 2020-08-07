pragma solidity ^0.6.0;

import "./VendorContract.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VendorContractTest is VendorContract {

    constructor(address _vendor, address _authority)  VendorContract(_vendor, _authority) public {
       
    }

    function setMetadata(bytes32 _vulnerabilityID, uint32 _timestamp,
                         bytes32 _productID, bytes32 _vulnerabilityHash) public {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityID];
        v.metadata.timestamp = _timestamp;
        v.metadata.productId = _productID;
        v.metadata.vulnerabilityHash = _vulnerabilityHash;
    }

    function setReward(bytes32 _vulnerabilityID, RewardState _state, uint _amount) public {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityID];
        v.reward.state = _state;
        v.reward.amount = _amount;
    }

    function setVulnerability(bytes32 _vulnerabilityID, address payable _researcher,
                                uint32 _timelock, State _state, uint _secret,
                                bytes32 _hashlock, string memory _location) public {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityID];
        v.researcher = _researcher;
        v.timelock = _timelock;
        v.state = _state;
        v.secret = _secret;
        v.hashlock = _hashlock;
        v.vulnerabilityLocation = _location; 
    }

    function hashlockCheck(uint secret, bytes32 hashlock) public pure returns(bytes32 hashlockComputed, bool equal) {
        
        hashlockComputed = keccak256(abi.encodePacked(secret));
        equal = (hashlock == hashlockComputed);
    }

    function produceId(address _vendor, bytes32 _hashlock,
                        bytes32 _productId, bytes32 _vulnerabilityHash) public view returns(bytes32) {

        return keccak256(
            abi.encodePacked(
                msg.sender,
                _vendor,
                _hashlock,
                _productId,
                _vulnerabilityHash
            )
        );    
    }
}