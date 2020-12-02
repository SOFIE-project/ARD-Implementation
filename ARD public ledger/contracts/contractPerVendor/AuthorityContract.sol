pragma solidity ^0.6.0;

 //Remix only
 //import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

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

    address public interledger;
    VendorFactory public factory;


    /**
        @notice The constructor of the contract expects the Interledger address and the address of a VendorFactory contract
        @param _interledger The address of the interledger component
        @param _factory The address of a VendorFactory contract
     */
    constructor (address _interledger, VendorFactory _factory) public {

        interledger = _interledger;
        factory = _factory;
    }

    // Logs

    event LogVulnerabilityNew(uint indexed vulnerabilityId, address indexed expert, address indexed vendor, bytes32 hashlock, bytes32 vulnerabilityHash    );
    event LogVulnerabilityApproval(uint indexed vulnerabilityId, uint32 ackTimelock, uint32 timelock, VendorContract.State state, string motivation);
    event LogVulnerabilityDisclose(uint indexed vulnerabilityId, address indexed communicator, string vulnerabilityLocation);
    event LogVulnerabilityPatched(uint indexed vulnerabilityId, bool patched, bool timelock_expired);

    event VendorRegistered(address indexed vendor, address vendorContract);
    event VendorUnregistered(address indexed vendor);
    
    event InterledgerAbort(uint256 id, uint256 reason);
    event InterledgerCommit(uint256 id);

    // Modifiers

    modifier onlyInterledger {

        require(msg.sender == interledger, "Not the interledger component");
        _;
    }

    modifier futureTimelock(uint32 _time1, uint32 _time2) {
    
        // The timelocks are after the last blocktime (now).
        require(_time1 > uint32(block.timestamp) && _time2 > uint32(block.timestamp) , "timelocks must be in the future");
        // The timelock time is after the last blocktime (now).
        require(_time2 > _time1, "timelock shuold be greater than ack timelock");
        _;
    }

    modifier vulnerabilityExists(uint _vulnerabilityId) {

        require(haveVulnerability(_vulnerabilityId), "vulnerabilityId does not exist");
        _;
    }

    modifier hashlockMatches(uint _vulnerabilityId, uint _secret) {

        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;
        (,,bytes32 _hashlock,,,,) = vendorContract.getVulnerabilityInfo(_vulnerabilityId);
        require(_hashlock == keccak256(abi.encodePacked(_secret)),"Hashed secret and hashlock do not match");
        _;
    }

    //Struct

    struct VendorRecord {
        VendorContract _contract;
        uint32 registeredSince;   // registration timestamp
        uint32 unregisteredSince;   // unregistration timestamp
        bool registered;
    }

    enum ApprovedType { Approved, Invalid, Duplicate }

    // Maps and arrays


    mapping(address => VendorRecord) public vendorRecords; // maps a vendor address to the his Vendor record
    address[] public vendorIndex;      // The array provides a list of the vendor address, not possible to retrieve it from a mapping

    mapping(uint => address) public VendorVulnerabilities; // map vulnerabilityId to vendor

    uint ID;

    // Methods

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

        require(!vendorExist(_vendor), "This vendor already exists");

        // VendorContract contractVendorAddress = new VendorContract(payable(_vendor));
        VendorContract contractVendorAddress = factory.createVendorContract(_vendor);
        VendorRecord memory record = VendorRecord({_contract: contractVendorAddress,
                                                    registeredSince: uint32(block.timestamp),
                                                    unregisteredSince: 0,
                                                    registered: true
                                                });

        vendorRecords[_vendor] = record;     // Store in the map the new pair (_vendorAddress, record)
        vendorIndex.push(_vendor);   // Store vendor address in array

        emit VendorRegistered(_vendor, address(contractVendorAddress));

    }

    /**
        @notice Un-register a vendor
        @param _vendor The address of vendor EOA to un-register
        @dev Emits an event VendorUnregistered(address indexed _vendor) with the address of the vendor EOA
        @dev Only the Authority owner
     */
    function unregisterVendor(address _vendor) onlyOwner external {

        require(vendorIsRegistered(_vendor),"This vendor is already unregistered");

        // Deactivate the Vendor contract
        VendorRecord storage record = vendorRecords[_vendor];
        record.registered=false;
        record.unregisteredSince = uint32(block.timestamp);
        emit VendorUnregistered(_vendor);
    }

    /**
        @notice Get the vendor data record given its id
        @param idx The index (uint) of the vendor to read
        @return _contract The address of the associated VendorContract
        @return registeredSince The timestamp of the registration date of the vendor
        @return unregisteredSince The timestamp of the unregistration date of the vendor (0 if still registered)
        @return registered True if the vendor is registered, false otherwise
     */
    function getVendorRecordByIdx(uint idx) public view returns(
        VendorContract _contract,
        uint32 registeredSince,
        uint32 unregisteredSince,
        bool registered){

        require(idx<vendorIndex.length, "Out of range");
        address vendor=vendorIndex[idx];
        VendorRecord memory vr= vendorRecords[vendor];
        return (vr._contract,vr.registeredSince,vr.unregisteredSince,vr.registered);

     }


    /**
        @notice Check if a vendor exists, i.e. they have a VendorContract associated
        @param _vendor The vendor EOA
        @return exists True if the vendor has a contract, false otherwise
        @dev Internal function
     */     
    function vendorExist(address _vendor)
        internal
        view
        returns (bool exists){

        exists=(address(vendorRecords[_vendor]._contract) != address(0));

    }

    /**
        @notice Check if a vendor is regitered
        @param _vendor The vendor EOA
        @return registered True if the vendor is registered, false otherwise
        @dev Internal function
     */     
    function vendorIsRegistered(address _vendor)
        internal
        view
        returns (bool registered){

        require(vendorExist(_vendor),"This vendor doesn't exist");
        registered=vendorRecords[_vendor].registered;

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
        @return _vulnerabilityId Id of the new contract. This is needed for subsequent calls
        @dev If positive, emits LogVulnerabilityNew(uint indexed vulnerabilityId, address indexed researcher, address indexed vendor, bytes32 hashlock, bytes32 vulnerabilityHash)
        @dev Reverts if the generated vulnerability id already exists
    */  
    function registerVulnerability(address _vendor, bytes32 _hashlock,
                                bytes32 _productId, bytes32 _vulnerabilityHash)
        external
        returns (uint _vulnerabilityId){

        //Check vendor if  vendor is registered{
        require(vendorIsRegistered(_vendor),"This vendor is unregistered");

        // Create a new entry
        _vulnerabilityId = ++ID;

        // Retrive VendorContract
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        // Associate the contract with the vulnerability metadata
        vendorContract.newVulnerability(_vulnerabilityId,
                                        payable(msg.sender),
                                        _productId,
                                        _vulnerabilityHash,
                                        _hashlock);


        VendorVulnerabilities[_vulnerabilityId] = _vendor;

        emit LogVulnerabilityNew(
            _vulnerabilityId,
            msg.sender,
            _vendor,
            _hashlock,
            _vulnerabilityHash
        );

        return _vulnerabilityId;
    }

    /**
        @notice Approves, or not, the vulnerability contract and provides the lock terms.
        @param _vulnerabilityId The vulnerability identifier, uint
        @param _ackTimelock UNIX epoch in seconds the vendor has to acknowledge
        @param _timelock The timelock in UNIX epoch time
        @param _decision The approval decision flag
        @param _motivation The motivation string
        @dev Emits LogVulnerabilityApproval(uint indexed vulnerabilityId, uint32 timelock, VendorContract.State state, string motivation)
        @dev Only the Authority owner, _vulnerabilityId exists
     */
    function approve(uint _vulnerabilityId, uint32 _ackTimelock, uint32 _timelock, ApprovedType _decision, string memory _motivation)
        public
        onlyOwner()
        futureTimelock(_ackTimelock,_timelock)
        vulnerabilityExists(_vulnerabilityId){

        // Retrive VendorContract
        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        (,VendorContract.State _state,,,,,)=vendorContract.getVulnerabilityInfo(_vulnerabilityId);
        require(_state == VendorContract.State.Pending, "The vulnerability should be in pending state");

        // Reject if the contract isn't aprroved (the verification is off chain)
        VendorContract.State _newState;

        if(_decision == ApprovedType.Invalid) 
            _newState = VendorContract.State.Invalid;

        else if(_decision == ApprovedType.Duplicate)
            _newState = VendorContract.State.Duplicate;

        else {
            vendorContract.setTimelock(_vulnerabilityId,_ackTimelock,_timelock);
            _newState = VendorContract.State.Valid;
        }

        vendorContract.setState(_vulnerabilityId, _newState);

        emit LogVulnerabilityApproval(
            _vulnerabilityId,
            _ackTimelock,
            _timelock,
            _newState,
            _motivation
        );

    }


    /**
        @notice Publish the secret after the secret if the disclosable condition is met. Pay the bounty
        @param _vulnerabilityId The vulnerability identifier, uint
        @param _secret The preimage of the hashlock, uint
        @dev Emits InterledgerEventSending(uint256 id, bytes data)
        @dev Emits LogVulnerabilityPatched(uint vulnerabilityId, bool patched, bool timelock_expired)
        @dev The secret mathces the hashlock, _vulnerabilityId exists and the vulnerability is disclosable
     */
    function publishSecret(uint _vulnerabilityId, uint _secret)
        external
        vulnerabilityExists(_vulnerabilityId)
        hashlockMatches(_vulnerabilityId, _secret) {
        
        // Retrive VendorContract and info
        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;
        bool patched = false;

        if(msg.sender == vendorContract.owner()) {

            patched = true;
            require(vendorContract.canBePatched(_vulnerabilityId), "The vulnerability can be patched only if previously Acknowledged");
            emit LogVulnerabilityPatched(_vulnerabilityId, patched, vendorContract.isTimelockExpired(_vulnerabilityId));
        }
        else {
            require(isDisclosable(_vulnerabilityId), "The secret cannot be disclosed before the timelock by other than the Vendor");
            emit LogVulnerabilityPatched(_vulnerabilityId, patched, true);
        }


        // Set secret and state, and disclose secret
        vendorContract.setSecret(_vulnerabilityId, _secret);
        vendorContract.setState(_vulnerabilityId, VendorContract.State.Disclosable);

        bytes memory data = abi.encode(_vulnerabilityId, _secret);
        emit InterledgerEventSending(_vulnerabilityId, data);


        // Process reward
        (VendorContract.RewardState _rewardState, uint _amount) = vendorContract.getVulnerabilityReward(_vulnerabilityId);

            // Send the reward only if present (the Vendor has acknowledged and funded the reward)
        if(_rewardState == VendorContract.RewardState.SET && _amount > 0)
            vendorContract.payBounty(_vulnerabilityId);
    }

    /**
        @dev Inherited from InterledgerReceiverInterface 
        @dev Emits LogVulnerabilityDisclose(uint indexed vulnerabilityId, address indexed communicator, string vulnerabilityLocation)
        @dev Only the interledger component
     */
    function interledgerReceive(uint256 nonce, bytes memory data)   
        override public onlyInterledger {

        // Get the Id from the data field
        uint id;
        string memory location;
        (id, location) = abi.decode(data, (uint256, string));

        // Retrive VendorContract
        require(haveVulnerability(id), "vulnerabilityId does not exist");

        address _vendor = VendorVulnerabilities[id];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        //Retrive rewardState
        (,VendorContract.State state,,,,,) = vendorContract.getVulnerabilityInfo(id);

        //verify secret has been published
        require(state == VendorContract.State.Disclosable, "The state should be Disclosable");

        vendorContract.setState(id, VendorContract.State.Disclosed);
        vendorContract.setLocation(id, location);

        emit LogVulnerabilityDisclose(id, msg.sender, location);
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
        @param _vulnerabilityId The vulnerability identifier, uint
        @param _motivation The motivation why vulnerability has been deleted, string
        @dev Only the owner, _vulnerabilityId exists
     */
    function cancelBounty(uint _vulnerabilityId, string calldata _motivation) external onlyOwner {

        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        vendorContract.cancelBounty(_vulnerabilityId, _motivation);
    }

    /**
        @notice Check if a vulnerability id exists
        @param _vulnerabilityId The vulnerability identifier, uint
        @return exists True if _vulnerabilityId exists, false otherwise
        @dev Internal function
     */
    function haveVulnerability(uint _vulnerabilityId)
        internal
        view
        returns (bool exists){
        exists = (address(VendorVulnerabilities[_vulnerabilityId]) != address(0));
    }

    /**
        @notice Check if a vulnerability is disclosable
        @param _vulnerabilityId The vulnerability identifier, uint
        @return True if _vulnerabilityId can be disclosed, false otherwise exists, false otherwise
     */
    function isDisclosable(uint _vulnerabilityId) public view returns(bool) {

        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        (,VendorContract.State _state,,uint _timelock,uint _acktimelock,,)=vendorContract.getVulnerabilityInfo(_vulnerabilityId);
        return  ((_state == VendorContract.State.Valid && _acktimelock < block.timestamp ) || (_state == VendorContract.State.Acknowledged && _timelock < block.timestamp));
    }

}
