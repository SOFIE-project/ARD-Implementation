pragma solidity ^0.6.0;

import "./VendorContract.sol";
import "./VendorFactory.sol";
import "./InterledgerSenderInterface.sol";
import "./InterledgerReceiverInterface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
    @title AuthorityContract
    @notice This contract reflects the Authority in the ARD process. Inherits from OpenZeppelin Ownable, SOFIE InterledgerSenderInterface and InterledgerReceiverInterface
 */
contract AuthorityContract is Ownable, InterledgerSenderInterface, InterledgerReceiverInterface {

    
    /**
        Contract state attributes
     */

    // Interledger address
    address public interledger;
    // Address of the Factory smart contract to deploy Vendor contracts
    VendorFactory public factory;

    // Data structures to map the address of a Vendor EOA to a Vendor data structure
    mapping(address => VendorRecord) public vendorRecords;

    // Map a vulnerabilityHash to the related vendor
    mapping(bytes32 => address) public VendorVulnerabilities; 

    /**
        Structs and Enums
     */

    // Data structure of a Vendor, including the address of its smart contract, and the registration variables
    struct VendorRecord {
        VendorContract _contract;
        uint32 registeredSince;   // registration timestamp
        uint32 unregisteredSince;   // unregistration timestamp
        bool registered;
    }


    /**
        @notice The constructor of the contract expects the Interledger address and the address of a VendorFactory contract
        @param _interledger The address of the interledger component
        @param _factory The address of a VendorFactory contract
     */
    constructor (address _interledger, VendorFactory _factory) public {

        interledger = _interledger;
        factory = _factory;
    }


    /**
        Events
     */

    event LogVulnerabilityNew(bytes32 indexed vulnerabilityHash, address indexed expert, address indexed vendor, bytes32 hashlock);
    event LogVulnerabilityApproval(bytes32 indexed vulnerabilityHash, uint32 ackTimelock, uint32 timelock, VendorContract.State state);
    event LogVulnerabilityDisclose(bytes32 indexed vulnerabilityHash, address indexed communicator, string vulnerabilityLocation);
    event LogVulnerabilityPatched(bytes32 indexed vulnerabilityHash, bool patched, bool timelock_expired);

    event VendorRegistered(address indexed vendor, address vendorContract);
    event VendorUnregistered(address indexed vendor);
    
    event InterledgerAbort(uint256 id, uint256 reason);
    event InterledgerCommit(uint256 id);


    /**
        Modifiers and utility functions
     */

    modifier onlyInterledger {
        require(msg.sender == interledger, "Not the interledger component");
        _;
    }

    modifier vulnerabilityExists(bytes32 _vulnerabilityHash) {
        require(haveVulnerability(_vulnerabilityHash), "Vulnerability identified by _vulnerabilityHash does not exist");
        _;
    }

    modifier hashlockMatches(bytes32 _vulnerabilityHash, uint _secret) {

        address _vendor = VendorVulnerabilities[_vulnerabilityHash];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;
        (,,bytes32 _hashlock,,,,) = vendorContract.getVulnerabilityInfo(_vulnerabilityHash);
        require(_hashlock == keccak256(abi.encodePacked(_secret)),"Hashed secret and hashlock do not match");
        _;
    }

    /**
        @notice Check if a vulnerability id exists
        @param _vulnerabilityHash The vulnerability identifier, bytes32
        @return exists True if _vulnerabilityHash exists, false otherwise
        @dev Internal function
     */
    function haveVulnerability(bytes32 _vulnerabilityHash)
        internal
        view
        returns (bool exists){
        exists = (address(VendorVulnerabilities[_vulnerabilityHash]) != address(0));
    }

    /**
        @notice Check if a vulnerability is disclosable
        @param _vulnerabilityHash The vulnerability identifier, bytes32
        @return True if _vulnerabilityHash can be disclosed, false otherwise exists, false otherwise
     */
    function isDisclosable(bytes32 _vulnerabilityHash) public view returns(bool) {

        address _vendor = VendorVulnerabilities[_vulnerabilityHash];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        (,VendorContract.State _state,,uint _timelock,uint _acktimelock,,)=vendorContract.getVulnerabilityInfo(_vulnerabilityHash);
        return  ((_state == VendorContract.State.Valid && _acktimelock < block.timestamp ) || (_state == VendorContract.State.Acknowledged && _timelock < block.timestamp));
    }

    /**
        @notice Check if a vendor is regitered
        @param _vendor The vendor EOA
        @return registered True if the vendor is registered, false otherwise
        @dev Internal function
     */     
    function isVendorRegistered(address _vendor)
        internal
        view
        returns (bool registered) {

        registered = vendorRecords[_vendor].registered && vendorRecords[_vendor].unregisteredSince == 0;
    }

    /**
        Methods
     */


    /**
        Vendor's related methods

     */

    /**
        @notice Register a new vendor, i.e. create a new VendorContract through the Factory
        @param _vendor The address of vendor EOA to register (and owner of the VendorContract)
        @dev Emits an event VendorRegistered(address indexed _vendor, address _vendorContract) with the address of the vendor and the new VendorContract respectively
        @dev Only the Authority owner
     */
    function registerVendor(address _vendor) onlyOwner external {

        require(!isVendorRegistered(_vendor), "This vendor already exists");

        VendorContract contractVendorAddress = factory.createVendorContract(_vendor);
        VendorRecord memory record = VendorRecord({_contract: contractVendorAddress,
                                                    registeredSince: uint32(block.timestamp),
                                                    unregisteredSince: 0,
                                                    registered: true
                                                });

        vendorRecords[_vendor] = record;

        emit VendorRegistered(_vendor, address(contractVendorAddress));
    }

    /**
        @notice Un-register a vendor
        @param _vendor The address of vendor EOA to un-register
        @dev Emits an event VendorUnregistered(address indexed _vendor) with the address of the vendor EOA
        @dev Only the Authority owner
     */
    function unregisterVendor(address _vendor) onlyOwner external {

        require(isVendorRegistered(_vendor),"This vendor is already unregistered");

        // Deactivate the Vendor contract
        VendorRecord storage record = vendorRecords[_vendor];
        record.registered = false;
        record.unregisteredSince = uint32(block.timestamp);
        emit VendorUnregistered(_vendor);
    }

    /**

        ARD process methods
     */

    /**
        @notice The resercher sets up a new vulnerability record
        @param _vendor The Vendor EOA address, the owner of the vulnerable device
        @param _hashlock The hashlock, bytes32
        @param _productId The id of the product, bytes32
        @param _vulnerabilityHash The hash of the vulnerability data, bytes32
        @return _vulnerabilityHash The input vulnerability hash
        @dev If positive, emits LogVulnerabilityNew(bytes32 indexed vulnerabilityHash, address indexed researcher, address indexed vendor, bytes32 hashlock)
        @dev Reverts if the generated vulnerability id already exists
    */  
    function registerVulnerability(address _vendor, bytes32 _hashlock,
                                bytes32 _productId, bytes32 _vulnerabilityHash)
        external
        returns (bytes32) {

        // Check vendor if vendor is registered
        require(isVendorRegistered(_vendor), "This vendor is not registered");

        // Retrive VendorContract
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        // Associate the contract with the vulnerability metadata
        vendorContract.newVulnerability(_vulnerabilityHash,
                                        payable(msg.sender),
                                        _productId,
                                        _hashlock);

        VendorVulnerabilities[_vulnerabilityHash] = _vendor;

        emit LogVulnerabilityNew(
            _vulnerabilityHash,
            msg.sender,
            _vendor,
            _hashlock
        );

        return _vulnerabilityHash;
    }

    /**
        @notice Approve the vulnerability contract and provides the lock terms.
        @param _vulnerabilityHash The vulnerability hash identifier, bytes32
        @dev Emits LogVulnerabilityApproval(uint indexed vulnerabilityHash, uint32 timelock, VendorContract.State state)
        @dev Only the Authority owner, _vulnerabilityHash exists
     */
    function _approve(bytes32 _vulnerabilityHash)
        private
        vulnerabilityExists(_vulnerabilityHash) {

        // Retrive VendorContract
        address _vendor = VendorVulnerabilities[_vulnerabilityHash];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;
        uint32 _ackTimelock = uint32(block.timestamp + 1 weeks);
        uint32 _patchTimelock = uint32(_ackTimelock + 12 weeks);

        (,VendorContract.State _state,,,,,) = vendorContract.getVulnerabilityInfo(_vulnerabilityHash);
        require(_state == VendorContract.State.Pending, "The vulnerability should be in pending state");

        // Reject if the contract isn't aprroved (the verification is off chain)
        vendorContract.setTimelock(_vulnerabilityHash, _ackTimelock, _patchTimelock);
        vendorContract.setState(_vulnerabilityHash, VendorContract.State.Valid);

        emit LogVulnerabilityApproval(
            _vulnerabilityHash,
            _ackTimelock,
            _patchTimelock,
            VendorContract.State.Valid
        );
    }

    /**
        @notice Approve the vulnerability contract and provides the lock terms.
        @param _vulnerabilityHash The vulnerability hash identifier, bytes32
        @param _flag true if Invalid vulnerability, false if Duplicate vulnerability
        @dev Emits LogVulnerabilityApproval(uint indexed vulnerabilityHash, uint32 timelock, VendorContract.State state)
        @dev Only the Authority owner, _vulnerabilityHash exists
     */
    function reject(bytes32 _vulnerabilityHash, bool _flag) external onlyOwner vulnerabilityExists(_vulnerabilityHash) {

        address _vendor = VendorVulnerabilities[_vulnerabilityHash];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        if(_flag) {
            vendorContract.setState(_vulnerabilityHash, VendorContract.State.Invalid);        
            emit LogVulnerabilityApproval(_vulnerabilityHash, 0, 0, VendorContract.State.Invalid);
        }
        else {
            vendorContract.setState(_vulnerabilityHash, VendorContract.State.Duplicate);        
            emit LogVulnerabilityApproval(_vulnerabilityHash, 0, 0, VendorContract.State.Duplicate);
        }
    }


    /**
        @notice Publish the secret after the secret if the disclosable condition is met. Pay the bounty
        @param _vulnerabilityHash The vulnerability hash identifier, bytes32
        @param _secret The preimage of the hashlock, uint
        @dev Emits InterledgerEventSending(uint256 id, bytes data)
        @dev Emits LogVulnerabilityPatched(uint vulnerabilityHash, bool patched, bool timelock_expired)
        @dev The secret mathces the hashlock, _vulnerabilityHash exists and the vulnerability is disclosable
        @dev WARNING Function subsceptible to stack too deep compilation error
     */
    function publishSecret(bytes32 _vulnerabilityHash, uint _secret)
        external
        vulnerabilityExists(_vulnerabilityHash)
        hashlockMatches(_vulnerabilityHash, _secret) {
        
        // Retrive VendorContract and info
        address _vendor = VendorVulnerabilities[_vulnerabilityHash];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        if(msg.sender == vendorContract.owner()) {

            (, VendorContract.State _state,, uint32 _timelock,,,) = vendorContract.getVulnerabilityInfo(_vulnerabilityHash);
            require(_state == VendorContract.State.Acknowledged, "The vulnerability can be patched only if previously Acknowledged");
            // if block.timestamp > _timelock, then the vendor released a patch after the expiration of the timelock
            emit LogVulnerabilityPatched(_vulnerabilityHash, true, block.timestamp > _timelock);
        }
        else {
            require(isDisclosable(_vulnerabilityHash), "The secret cannot be disclosed before the timelock by other than the Vendor");
            emit LogVulnerabilityPatched(_vulnerabilityHash, false, true);
        }


        // Set secret and state, and disclose secret
        vendorContract.setSecret(_vulnerabilityHash, _secret);
        vendorContract.setState(_vulnerabilityHash, VendorContract.State.Disclosable);

        // Encoding, need uint id for interledger
        uint vulnerabilityHashUint = uint(_vulnerabilityHash);
        bytes memory data = abi.encode(_vulnerabilityHash, _secret);
        emit InterledgerEventSending(vulnerabilityHashUint, data);


        // Process reward
        (VendorContract.RewardState _rewardState, uint _amount) = vendorContract.getVulnerabilityReward(_vulnerabilityHash);

            // Send the reward only if present (the Vendor has acknowledged and funded the reward)
        if(_rewardState == VendorContract.RewardState.SET && _amount > 0)
            vendorContract.payBounty(_vulnerabilityHash);
    }

    /**
        @param id The id of the vulnerability
        @param location The link where the vulnerability has been published
        @dev Emits LogVulnerabilityDisclose(uint indexed vulnerabilityHash, address indexed communicator, string vulnerabilityLocation)
     */
    function _disclose(bytes32 id, string memory location) private vulnerabilityExists(id) {

        // Retrive VendorContract
        address _vendor = VendorVulnerabilities[id];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        //Retrive rewardState
        (,VendorContract.State state,,,,,) = vendorContract.getVulnerabilityInfo(id);

        //verify secret has been published
        require(state == VendorContract.State.Disclosable, "The state should be Disclosable");

        vendorContract.setState(id, VendorContract.State.Disclosed);
        vendorContract.setLocation(id, location);

        emit LogVulnerabilityDisclose(id, msg.sender, location);
    }


    /**
        @dev Communicate the approval, or the disclosure, of a vulnerability
        @dev Inherited from InterledgerReceiverInterface
        @dev Emits InterledgerEventAccepted(nonce)
        @dev Only the interledger component
     */
    function interledgerReceive(uint256 nonce, bytes memory data) override public onlyInterledger {

        (bytes32 _vulnerabilityHash, uint _actionId, string memory _location) =  abi.decode(data, (bytes32, uint, string));

        if(_actionId==1) // 1: code for Approve
            _approve(_vulnerabilityHash);
        else if(_actionId==2) // 2: code for Disclose
            _disclose(_vulnerabilityHash, _location);
        else
            revert("Invalid _action value: must be either 1 to approve a vulnerability, or 2 to discolse.");

        emit InterledgerEventAccepted(nonce);
    }

    // InterledgerSenderInterface methods
    function interledgerCommit(uint256 id) override public {
        emit InterledgerCommit(id);
    }

    function interledgerCommit(uint256 id, bytes memory data) override public {
        emit InterledgerCommit(id);
    }

    function interledgerAbort(uint256 id, uint256 reason) override public {
        emit InterledgerAbort(id, reason);
    }

    /**
        Cancel bounty
     */


    /**
        @notice Cancels the vulnerability bounty
        @param _vulnerabilityHash The vulnerability hash identifier, bytes32
        @param _reason The reason why vulnerability has been deleted, string
        @dev Only the owner, _vulnerabilityHash exists
     */
    function cancelBounty(bytes32 _vulnerabilityHash, string calldata _reason) external onlyOwner {

        address _vendor = VendorVulnerabilities[_vulnerabilityHash];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        vendorContract.cancelBounty(_vulnerabilityHash, _reason);
    }

}
