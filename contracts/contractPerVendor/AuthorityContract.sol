pragma solidity ^0.6.0;

 //Remix only
 //import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

import "./VendorContract.sol";
import "./VendorFactory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VulnerabilityRegistry
 *
 * @notice This contract supports responsible disclosure of vulnerabilities. For each vulnerability a state machine identifies the stage of the responsible disclosure process
 *
 */

contract AuthorityContract is Ownable {

    address public interledger;
    VendorFactory public factory;

    constructor(address _interledger, VendorFactory _factory) public {

        interledger = _interledger;
        factory = _factory;
    }

    // Logs

    event LogVulnerabilityNew(
        bytes32 indexed vulnerabilityId,
        address indexed expert,
        address indexed vendor,
        bytes32 hashlock,
        bytes32 vulnerabilityHash
    );


    event LogVulnerabilityApproval(
        bytes32 indexed vulnerabilityId,
        uint32 timelock,
        VendorContract.State state
    );

    event LogVulnerabilitySecret(bytes32 indexed vulnerabilityId, uint secret);
    event LogVulnerabilityDisclose(bytes32 indexed vulnerabilityId, address indexed communicator, string vulnerabilityLocation);
    event vendorRegistered(address indexed _vendor, address _vendorContract);
    event vendorUnregistered(address indexed _vendor);

    // Modifiers

    modifier onlyInterledger {

        require(msg.sender == interledger);
        _;
    }

    modifier futureTimelock(uint32 _time1, uint32 _time2) {
    
        // The timelocks are after the last blocktime (now).
        require(_time1 > uint32(block.timestamp) && _time2 > uint32(block.timestamp) , "timelocks must be in the future");
        // The timelock time is after the last blocktime (now).
        require(_time2 > _time1, "timelock shuold be greater than ack timelock");
        _;
    }

    modifier vulnerabilityExists(bytes32 _vulnerabilityId) {

        require(haveVulnerability(_vulnerabilityId), "vulnerabilityId does not exist");
        _;
    }

    modifier hashlockMatches(bytes32 _vulnerabilityId, uint _secret) {

        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;
        (,,bytes32 _hashlock,,,,) = vendorContract.getVulnerabilityInfo(_vulnerabilityId);
        require(_hashlock == keccak256(abi.encodePacked(_secret)),"Hashed secret and hashlock do not match");
        _;
    }

    modifier disclosable(bytes32 _vulnerabilityId) {

        // Check the condition to disclose a vulnerability
        require(isDisclosable(_vulnerabilityId), "This contract cannot be discolsed");
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

    mapping(bytes32 => address) public VendorVulnerabilities; // map vulnerabilityId to vendor
    bytes32[] public vulnerabilityIndex; // The array provides a list of vulnerabilityId to easy retrive them all



    // Methods

    /**
        Vendor's related methods

     */

    /**
     * @dev The Authority register a Vendor
     *
     * @param _vendor The vendor address (EOA)
     */

    function registerVendor(address _vendor) onlyOwner external {

        require(!vendorExist(_vendor),"This vendor already exist");

        // VendorContract contractVendorAddress = new VendorContract(payable(_vendor));
        VendorContract contractVendorAddress = factory.createVendorContract(_vendor);
        VendorRecord memory record = VendorRecord({_contract: contractVendorAddress,
                                                    registeredSince: uint32(block.timestamp),
                                                    unregisteredSince: 0,
                                                    registered: true
                                                });

        vendorRecords[_vendor] = record;     // Store in the map the new pair (_vendorAddress, record)
        vendorIndex.push(_vendor);   // Store vendor address in array

        emit vendorRegistered(_vendor, address(contractVendorAddress));

    }

    /**
     * @dev The Authority unregisters a Vendor
     *
     * @param _vendor The vendor address
     */

    function unregisterVendor(address _vendor) onlyOwner external {

        require(vendorIsRegistered(_vendor),"This vendor is already unregistered");

        // Deactivate the Vendor contract
        VendorRecord storage record = vendorRecords[_vendor];
        record.registered=false;
        record.unregisteredSince = uint32(block.timestamp);
        emit vendorUnregistered(_vendor);
    }

   /**
     * @dev Get vendor by index
     *
     * @param idx THe position of vendor in the array vendorIndex
     */

    function getVendorRecordByIdx(uint idx) public view returns(
        VendorContract _contract,
        uint32 registeredSince,
        uint32 unregisteredSince,
        bool registered){

        require(idx<vulnerabilityIndex.length, "Out of range");
        address vendor=vendorIndex[idx];
        VendorRecord memory vr= vendorRecords[vendor];
        return (vr._contract,vr.registeredSince,vr.unregisteredSince,vr.registered);

     }


    function vendorExist(address _vendor)
        internal
        view
        returns (bool exists){

        exists=(address(vendorRecords[_vendor]._contract) != address(0));

    }

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
     * @dev The resercher sets up a new vulnerability contract.
     *
     * @param _vendor The Vendor address, the owner of the vulnerable device
     * @param _hashlock The secret hash used also for the hashlock (sha-2 sha256).
     * @param _productId The id of the product
     * @param _vulnerabilityHash The hash of the vulnerability data
     *
     * @return _vulnerabilityId Id of the new contract. This is needed for subsequent calls.
     */


    function registerVulnerability(address _vendor, bytes32 _hashlock,
                                bytes32 _productId, bytes32 _vulnerabilityHash)
        external
        returns (bytes32 _vulnerabilityId){

        //Check vendor if  vendor is registered{
        require(vendorIsRegistered(_vendor),"This vendor is unregistered");

        // Create a new entry
        _vulnerabilityId = keccak256(
            abi.encodePacked(
                msg.sender,
                _vendor,
                _hashlock,
                _productId,
                _vulnerabilityHash
            )
        );

        // Retrive VendorContract
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        // Reject if a contract already exists with the same parameters. The
        // sender must change one of these parameters to create a new distinct
        // contract.
        if (haveVulnerability(_vulnerabilityId))
            revert("Vulnerability already exists");


        // Associate the contract with the vulnerability metadata
        vendorContract.newVulnerability(_vulnerabilityId,
                                        payable(msg.sender),
                                        _productId,
                                        _vulnerabilityHash,
                                        _hashlock);


        VendorVulnerabilities[_vulnerabilityId] = _vendor;
        vulnerabilityIndex.push(_vulnerabilityId);

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
     * @dev The authority approves the vulnerability contract and provides the lock terms.
     *
     * @param _timelock UNIX epoch seconds time that  lock expires at.
     * @param _vulnerabilityId The condract identifier.
     * @param _decision The approval parameter.
     */
    function approve(bytes32 _vulnerabilityId, uint32 _ackTimelock, uint32 _timelock, ApprovedType _decision)
        public
        onlyOwner()
        futureTimelock(_ackTimelock,_timelock)
        vulnerabilityExists(_vulnerabilityId){
        
        
        // Retrive VendorContract
        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;


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
            _timelock,
            _newState
        );

    }

 /**
     * @dev Called by who knows the secret (the expert or the authority).
     * This will allow the expert to withdraw the bounty.
     *
     * @param _vulnerabilityId Id of the VulnerabilityContract.
     * @param _secret The preimage of the hashlock
     */
    function publishSecret(bytes32 _vulnerabilityId, uint _secret)
        external
        vulnerabilityExists(_vulnerabilityId)
        disclosable(_vulnerabilityId)
        hashlockMatches(_vulnerabilityId, _secret){

        // Retrive VendorContract
        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        //Retrive rewardState
        (VendorContract.RewardState _rewardState, uint _amount) = vendorContract.getVulnerabilityReward(_vulnerabilityId);

        //Set secret and state
        vendorContract.setSecret(_vulnerabilityId, _secret);
        vendorContract.setState(_vulnerabilityId, VendorContract.State.Disclosable);

        require(_rewardState == VendorContract.RewardState.SET && _amount > 0, "Cannot claim reward");

        vendorContract.payBounty(_vulnerabilityId);

        emit LogVulnerabilitySecret(_vulnerabilityId, _secret);

    }

     /**
     * @dev Called by interledger (the expert or the authority).
     * This will allow the expert to withdraw the bounty.
     *
     * @param _vulnerabilityId Id of the VulnerabilityContract.
     * @param _vulnerabilityLocation The preimage of the hashlock
     */
    function disclose(bytes32 _vulnerabilityId, string calldata _vulnerabilityLocation)
        external
        vulnerabilityExists(_vulnerabilityId)
        onlyInterledger
        returns (bool success){

        // Retrive VendorContract
        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        //Retrive rewardState
        (,VendorContract.State state,,,,,) = vendorContract.getVulnerabilityInfo(_vulnerabilityId);

        //verify secret has been published
        require(state == VendorContract.State.Disclosable);

        vendorContract.setState(_vulnerabilityId, VendorContract.State.Disclosed);
        vendorContract.setLocation(_vulnerabilityId, _vulnerabilityLocation);

        emit LogVulnerabilityDisclose(_vulnerabilityId, msg.sender, _vulnerabilityLocation);

        success = true;

    }


    /**
        Cancel bounty
     */


    /**
     * @dev Cancels the vulnerability bounty
     *
     * @param _vulnerabilityId The identifier of the vulnerability
     * @param _motivation The motivation why vulnerability has been deleted
     */
    function cancelBounty(bytes32 _vulnerabilityId, string calldata _motivation) external onlyOwner {

        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        vendorContract.cancelBounty(_vulnerabilityId, _motivation);
    }

    /**
     * @dev Is there a contract with id _vulnerabilityId.
     * @param _vulnerabilityId Id into Vulnerabilities mapping.
     */
    function haveVulnerability(bytes32 _vulnerabilityId)
        internal
        view
        returns (bool exists){
        exists = (address(VendorVulnerabilities[_vulnerabilityId]) != address(0));
    }

    /**
     * @dev Is the input contract disclosable
     * @param _vulnerabilityId Contract identifier
     */
    function isDisclosable(bytes32 _vulnerabilityId) public view returns(bool) {

        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        (,VendorContract.State _state,,uint _timelock,uint _acktimelock,,)=vendorContract.getVulnerabilityInfo(_vulnerabilityId);
        return  ((_state == VendorContract.State.Valid && _acktimelock < block.timestamp ) || (_state == VendorContract.State.Acknowledged && _timelock < block.timestamp) ||
                (_state == VendorContract.State.Patched));
    }

}
