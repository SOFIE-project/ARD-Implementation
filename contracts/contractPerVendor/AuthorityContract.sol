pragma solidity ^0.6.0;

 //Remix only
 //import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

import "./VendorContract.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VulnerabilityRegistry
 *
 * @notice This contract supports responsible disclosure of vulnerabilities. For each vulnerability a state machine identifies the stage of the responsible disclosure process
 *
 */

contract AuthorityContract is Ownable {

    constructor(address _interledger) public {
        //add interledger account
        interledger = _interledger;

    }

    // Logs

    event LogVulnerabilityNew(
        bytes32 indexed vulnerabilityId,
        address indexed researcher,
        address indexed vendor,
        bytes32 hashlock,
        bytes32 vulnerabilityHash
    );

    event LogVulnerabilityDuplicate(
        bytes32 indexed vulnerabilityId,
        address indexed vendor,
        uint32 vendorId,
        bytes32 productId,
        bytes32 vulnerabilityHash,
        VendorContract.State state
    );

    event LogVulnerabilityApproval(
        bytes32 indexed vulnerabilityId,
        uint32 timelock,
        VendorContract.State state
    );

    event LogVulnerabilitybyID(
        address _researcher,
        uint _timestamp,
        VendorContract.State _state,
        bytes32 indexed _hashlock,
        uint32 _timelock,
        uint _secret,
        VendorContract.RewardState,
        uint amount
    );

    event LogMetadatabyID (
            address vendor,
            uint32 vendorId,
            bytes32 indexed productId,
            bytes32 indexed vulnerabilityHash
        );

    event LogVulnerabilityNotFound(bytes32 indexed vulnerabilityId);
    event LogVulnerabilitySecret(bytes32 indexed vulnerabilityId, uint secret);
    event LogVulnerabilityDisclose(bytes32 indexed vulnerabilityId, address indexed communicator, string vulnerabilityLocation);
    event vendorRegistered(address indexed _vendor);
    event vendorUnregistered(address indexed _vendor);

    // Modifiers

    modifier onlyInterledger {

        require(msg.sender == interledger);
        _;
    }

    modifier futureTimelock(uint32 _time) {

        // The timelock time is after the last blocktime (now).
        require(_time > uint32(block.timestamp), "timelock time must be in the future");
        _;
    }

    modifier vulnerabilityExists(bytes32 _vulnerabilityId) {

        require(haveVulnerability(_vulnerabilityId), "vulnerabilityId does not exist");
        _;
    }

    modifier hashlockMatches(bytes32 _vulnerabilityId, uint _secret) {

        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;
        (,,,bytes32 _hashlock,,,) = vendorContract.getVulnerabilityInfo(_vulnerabilityId);
        require(_hashlock == keccak256(abi.encodePacked(_secret)),"Hashed secret and hashlock do not match");
        _;
    }

    modifier disclosable(bytes32 _vulnerabilityId) {

        // Check the condition to disclose a vulnerability
        require(isDisclosable(_vulnerabilityId), "This contract cannot be discolsed");
        _;
    }

    address interledger;

    //Struct

    struct VendorRecord {
        VendorContract _contract;
        uint32 registeredSince;   // registration timestamp
        uint32 unregisteredSince;   // unregistration timestamp
        bool registered;
    }

    // Maps and arrays


    mapping(address => VendorRecord) public vendorRecords; // maps a vendor address to the his Vendor record
    address[] public vendorIndex;      // The array provides a list of the vendor address, not possible to retrieve it from a mapping

    mapping(bytes32 => address) public VendorVulnerabilities; // map vulnerabilityId to vendor
    bytes32[] public vulnerabilityIndex; // The array provides a list of vulnerabilityId to easy retrive them all

    mapping(bytes32 => bytes32) HashData; // mapping vulnerability_hash => vulnerabilityId


    // Methods

    ///Manage Vendor

    /**
     * @dev The Authority register a Vendor
     *
     * @param _vendor The vendor address (EOA)
     */

    function registerVendor(address _vendor) onlyOwner external {

        require(!vendorExist(_vendor),"This vendor already exist");

        VendorContract contractVendorAddress = new VendorContract(payable(_vendor));
        VendorRecord memory record = VendorRecord({_contract: contractVendorAddress,
                                                    registeredSince: uint32(block.timestamp),
                                                    unregisteredSince: 0,
                                                    registered: true
                                                });

        vendorRecords[_vendor] = record;     // Store in the map the new pair (_vendorAddress, record)
        vendorIndex.push(_vendor);   // Store vendor address in array

        emit vendorRegistered(_vendor);

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
        // vendorContracts[_vendor]._contract = VendorContract(address(0));
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

    /// Manage vulnerability

    /**
     * @dev The resercher sets up a new vulnerability contract.
     *
     * @param _vendor The Vendor address, the owner of the vulnerable device
     * @param _hashlock The secret hash used also for the hashlock (sha-2 sha256).
     * @param _vendorId The id of the vendor
     * @param _productId The id of the product
     * @param _vulnerabilityHash The hash of the vulnerability data
     *
     * @return _vulnerabilityId Id of the new contract. This is needed for subsequent calls.
     */


    function registerVulnerability(address _vendor, bytes32 _hashlock,
                                uint32 _vendorId, bytes32 _productId,
                                bytes32 _vulnerabilityHash)
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

        // If the submission contains already the same vulnerability information hash, fire event and return the currently stored contract
        if (haveHashData(_vulnerabilityHash)) {

            _vulnerabilityId = HashData[_vulnerabilityHash];

            // Retrive vulnerability metadata
            (uint32 __vendorId,
             bytes32 __productId,
            ) = vendorContract.getVulnerabilityMetadata(_vulnerabilityId);
            (,,VendorContract.State _state,,,,) = vendorContract.getVulnerabilityInfo(_vulnerabilityId);

            emit LogVulnerabilityDuplicate(_vulnerabilityId,
                            _vendor,
                            __vendorId,
                            __productId,
                            _vulnerabilityHash,
                            _state
                            );

            return _vulnerabilityId;
        }

        // Associate the contract with the vulnerability metadata
        vendorContract.newVulnerability(_vulnerabilityId,
                                        payable(msg.sender),
                                        _vendorId,
                                        _productId,
                                        _vulnerabilityHash,
                                        _hashlock);
        HashData[_vulnerabilityHash] = _vulnerabilityId;
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
     * @param _approved The approval parameter.
     */
    function approve(bytes32 _vulnerabilityId, uint32 _timelock, bool _approved)
        public
        onlyOwner()
        futureTimelock(_timelock)
        vulnerabilityExists(_vulnerabilityId){

        // Retrive VendorContract
        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;


        // Reject if the contract isn't aprroved (the verification is off chain)
        VendorContract.State _newState;
        if (!_approved) {
            _newState = VendorContract.State.Invalid;
        }
        else {
            vendorContract.setTimelock(_vulnerabilityId,_timelock);
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
     * @dev Called by who knows the secret (the researcher or the authority).
     * This will allow the researcher to withdraw the bounty.
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

        //set secret
        vendorContract.setSecret(_vulnerabilityId, _secret);

        (address _researcher,,,,,,) = vendorContract.getVulnerabilityInfo(_vulnerabilityId);
        require(_rewardState == VendorContract.RewardState.SET && _amount > 0, "Cannot claim reward");
        require(msg.sender == _researcher, "Only the original researcher can withdraw the reward");
        vendorContract.payBounty(_vulnerabilityId);

        emit LogVulnerabilitySecret(_vulnerabilityId, _secret);

    }

     /**
     * @dev Called by interledger (the researcher or the authority).
     * This will allow the researcher to withdraw the bounty.
     *
     * @param _vulnerabilityId Id of the VulnerabilityContract.
     * @param _vulnerabilityLocation The preimage of the hashlock
     */
    function disclose(bytes32 _vulnerabilityId, string calldata _vulnerabilityLocation)
        external
        vulnerabilityExists(_vulnerabilityId)
        disclosable(_vulnerabilityId)
        onlyInterledger
        returns (bool success){

        // Retrive VendorContract
        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        //Retrive rewardState
        (,,,,,uint secret,) = vendorContract.getVulnerabilityInfo(_vulnerabilityId);

        //verify secret has been published
        require(secret!=0);

        vendorContract.setState(_vulnerabilityId, VendorContract.State.Disclosed);
        vendorContract.setLocation(_vulnerabilityId, _vulnerabilityLocation);

        emit LogVulnerabilityDisclose(_vulnerabilityId, msg.sender, _vulnerabilityLocation);

        success = true;

    }


    /**
     * @notice Get contract details.
     * @dev Need to split in two functions to avoid stack too deep exc
     * @param _vulnerabilityId contract id
     */
    function getVulnerabilityInfoById(bytes32 _vulnerabilityId)
        vulnerabilityExists(_vulnerabilityId)
        view
        public
        returns(
        address _researcher,
        uint _timestamp,
        VendorContract.State _state,
        bytes32 _hashlock,
        uint32 _timelock,
        uint _secret,
        string memory _location
        ){

        // Retrive VendorContract
        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        return vendorContract.getVulnerabilityInfo(_vulnerabilityId);

    }

     /**
     * @notice Get contract details.
     * @dev Need to split in two functions to avoid stack too deep exc
     * @param _vulnerabilityId contract id
     */
    function getVulnerabilityRewardInfoById(bytes32 _vulnerabilityId)
        vulnerabilityExists(_vulnerabilityId)
        view
        public
        returns(
        VendorContract.RewardState _rewState,
        uint _amount
        ){

        // Retrive VendorContract
        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        // Retrive vulnerability RewardState
        return vendorContract.getVulnerabilityReward(_vulnerabilityId);

    }

    /**
     * @notice Get the metadata of a vulnerability
     * @dev Need to split in two functions to avoid stack too deep exc
     * @param _vulnerabilityId Id into Vulnerabilities mapping.
     */
    function getMetadataById(bytes32 _vulnerabilityId)
        public{

        if (haveVulnerability(_vulnerabilityId) == false){
            emit LogVulnerabilityNotFound(_vulnerabilityId);
            return;
        }

        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        //Retrivevulnerability metadata
        (uint32 vendorId,
         bytes32 productId,
         bytes32 vulnerabilityHash) = vendorContract.getVulnerabilityMetadata(_vulnerabilityId);

        emit LogMetadatabyID(_vendor, vendorId, productId, vulnerabilityHash);
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
     * @dev Is there a contract with meta _meta.
     * @param _hashData the hash of the vulnerability data
     */
    function haveHashData(bytes32 _hashData)
        internal
        view
        returns (bool exists){

        exists = (HashData[_hashData] != 0x0);
    }

    /**
     * @dev Is the input contract disclosable
     * @param _vulnerabilityId Contract identifier
     */
    function isDisclosable(bytes32 _vulnerabilityId) public view returns(bool) {

        address _vendor = VendorVulnerabilities[_vulnerabilityId];
        VendorContract vendorContract = vendorRecords[_vendor]._contract;

        (,,VendorContract.State _state,,uint _timlock,,)=vendorContract.getVulnerabilityInfo(_vulnerabilityId);
        return  ((_state == VendorContract.State.Valid || _state == VendorContract.State.Acknowledged) && _timlock < block.timestamp) ||
                (_state == VendorContract.State.Patched);
    }

}
