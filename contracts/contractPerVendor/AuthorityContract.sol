pragma solidity ^0.6.0;

// Remix only
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

import "./VendorContract.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VulnerabilityRegistry
 *
 * @notice This contract supports responsible disclosure of vulnerabilities. For each vulnerability a state machine identifies the stage of the responsible disclosure process
 *
 */

 // TODO Change the variables with the data types proposed in the ARD document
contract AuthorityContract is Ownable {

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
        uint32 productId,
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
        bytes32 _hashlock,
        uint32 _timelock,
        uint _secret,
        VendorContract.RewardState,
        uint amount
    );

    event LogMetadatabyID (
            address vendor,
            uint32 vendorId,
            uint32 productId,
            bytes32 vulnerabilityHash
        );

    event LogVulnerabilityNotFound(bytes32 indexed vulnerabilityId);
    event LogVulnerabilitySecret(bytes32 indexed vulnerabilityId, uint secret);
    event LogVulnerabilityDisclose(bytes32 indexed vulnerabilityId, address indexed communicator, string vulnerabilityLocation);
    event vendorRegistered(address indexed _vendor);
    event vendorUnregistered(address indexed _vendor);

    // Modifiers

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

        VendorContract vendorContract = VendorVulnerabilities[_vulnerabilityId];
        (,,,bytes32 _hashlock,,,) = vendorContract.getVulnerabilityInfo(_vulnerabilityId);
        require(_hashlock == keccak256(abi.encodePacked(_secret)),"Hashed secret and hashlock do not match");
        _;
    }

    modifier disclosable(bytes32 _vulnerabilityId) {

        // Check the condition to disclose a vulnerability
        require(isDisclosable(_vulnerabilityId), "This contract cannot be discolsed");
        _;
    }

    // Maps and arrays

    struct VendorRecord {
        VendorContract _contract;
        uint32 registeredSince;   // registration timestamp
        uint32 unregisteredSince;   // unregistration timestamp
        bool registered;
    }

    // mapping(address => VendorContract) public vendorContracts;// map vendor address to deposit vendor contract

    mapping(address => uint) vendorArrayIndexes; // maps a vendor address to the position of its smart contract in the array
    VendorRecord[] vendorContractsList;      // The array provides a list of the vendor contracts, not possible to retrieve it from a mapping

    mapping(bytes32 => VendorContract) public VendorVulnerabilities; // map vulnerabilityId to Vendodor contract
    mapping(bytes32 => bytes32) HashData; // mapping vulnerability_hash => vulnerabilityId

    // Methods

    /**
     * @dev The Authority register a Vendor
     *
     * @param _vendor The vendor address (EOA)
     */

    function registerVendor(address _vendor) onlyOwner external {

        VendorContract contractVendorAddress = new VendorContract(payable(_vendor));
        uint _idx = vendorContractsList.length;
        
        VendorRecord memory record = VendorRecord({_contract: contractVendorAddress, 
                                                    registeredSince: uint32(block.timestamp),
                                                    unregisteredSince: 0,
                                                    registered: true});

        vendorContractsList.push(record);   // Store vendor record in array
        vendorArrayIndexes[_vendor] = _idx;     // Store in the map the new pair (_vendorAddress, position in array)

        emit vendorRegistered(_vendor);
    }

    /**
     * @dev The Authority unregisters a Vendor
     *
     * @param _vendor The vendor address
     */

    function unregisterVendor(address _vendor) onlyOwner external {

        // Deactivate the Vendor contract
        uint _idx = vendorArrayIndexes[_vendor];
        VendorRecord storage record = vendorContractsList[_idx];

        record.registered = false;
        record.unregisteredSince = uint32(block.timestamp);
        // vendorContracts[_vendor]._contract = VendorContract(address(0));
        emit vendorUnregistered(_vendor);
    }

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
                                uint32 _vendorId, uint32 _productId,
                                bytes32 _vulnerabilityHash)
        external
        returns (bytes32 _vulnerabilityId)
    {

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
        // VendorContract vendorContract = vendorContracts[_vendor]._contract;
        VendorContract vendorContract = vendorContractsList[ vendorArrayIndexes[_vendor] ]._contract; // Cannot split, otherwise stack too deep

        // Reject if a contract already exists with the same parameters. The
        // sender must change one of these parameters to create a new distinct
        // contract.
        if (haveVulnerability(_vulnerabilityId))
            revert("Vulnerability already exists");

        // If the submission contains already the same vulnerability information hash, fire event and return the currently stored contract
        if (haveHashData(_vulnerabilityHash)) {
            
            _vulnerabilityId = HashData[_vulnerabilityHash];

            // Retrive vulnerability metadata
            (address __vendor,
            uint32 __vendorId,
            uint32 __productId,
            ) = vendorContract.getVulnerabilityMetadata(_vulnerabilityId);
            (,,VendorContract.State _state,,,,) = vendorContract.getVulnerabilityInfo(_vulnerabilityId);

            emit LogVulnerabilityDuplicate(_vulnerabilityId,
                            __vendor,
                            __vendorId,
                            __productId,
                            _vulnerabilityHash,
                            _state
                            );

            return _vulnerabilityId;
        }

        // Associate the contract with the vulnerability metadata
        HashData[_vulnerabilityHash] = _vulnerabilityId;
        VendorVulnerabilities[_vulnerabilityId] = vendorContract;
        vendorContract.newVulnerability(_vulnerabilityId,
                                        payable(_vendor),
                                        payable(msg.sender),
                                        _vendorId,
                                        _productId,
                                        _vulnerabilityHash,
                                        _hashlock);

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
    function approve(uint32 _timelock, bytes32 _vulnerabilityId, bool _approved)
        public
        onlyOwner()
        futureTimelock(_timelock)
        vulnerabilityExists(_vulnerabilityId)
    {
        // Retrive VendorContract
        VendorContract vendorContract = VendorVulnerabilities[_vulnerabilityId];

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
    function disclose(bytes32 _vulnerabilityId, uint _secret, string calldata _vulnerabilityLocation)
        external
        vulnerabilityExists(_vulnerabilityId)
        disclosable(_vulnerabilityId)
        hashlockMatches(_vulnerabilityId, _secret)

        returns (bool success)
    {

        // Retrive VendorContract
        VendorContract vendorContract = VendorVulnerabilities[_vulnerabilityId];

        //Retrive rewardState
        (VendorContract.RewardState _rewardState, uint _amount) = vendorContract.getVulnerabilityReward(_vulnerabilityId);

        // Label the reward to TOCLAIM only if there is a reward
        // else keep the reward state to NULL (the vendor never acknowledged the vulnerability)
        if(_rewardState == VendorContract.RewardState.SET && _amount > 0)
            vendorContract.setRewardState(_vulnerabilityId, VendorContract.RewardState.TOCLAIM);

        vendorContract.setSecret(_vulnerabilityId, _secret);
        vendorContract.setState(_vulnerabilityId, VendorContract.State.Disclosed);
        vendorContract.setLocation(_vulnerabilityId, _vulnerabilityLocation);

        emit LogVulnerabilityDisclose(_vulnerabilityId, msg.sender, _vulnerabilityLocation);
        emit LogVulnerabilitySecret(_vulnerabilityId, _secret);

        success = true;
    }

     /**
     * @dev Withdraw the bounty
     *
     * @param _vulnerabilityId Id of the VulnerabilityContract.
     */
    function withdrawBounty(bytes32 _vulnerabilityId) external {

        // Retrive VendorContract
        VendorContract vendorContract = VendorVulnerabilities[_vulnerabilityId];

        (address _researcher,,,,,,) = vendorContract.getVulnerabilityInfo(_vulnerabilityId);
        (VendorContract.RewardState _rewState, ) = vendorContract.getVulnerabilityReward(_vulnerabilityId);

        require(_rewState == VendorContract.RewardState.TOCLAIM, "Cannot claim reward yet");
        require(msg.sender == _researcher, "Only the original researcher can withdraw the reward");

        vendorContract.payBounty(_vulnerabilityId);
    }

    // TODO why these two functions are not view?
    /**
     * @notice Get contract details.
     * @dev Need to split in two functions to avoid stack too deep exc
     * @param _vulnerabilityId contract id
     */
    function getVulnerabilityById(bytes32 _vulnerabilityId)
        public
    {

        // Check if vulnerabilitie exists
        if (haveVulnerability(_vulnerabilityId) == false){
            emit LogVulnerabilityNotFound(_vulnerabilityId);
            return;
        }


        // Retrive VendorContract
        VendorContract vendorContract = VendorVulnerabilities[_vulnerabilityId];

        // Retrive vulnerability information

        (address _researcher,
        uint _timestamp,
        VendorContract.State _state,
        bytes32 _hashlock,
        uint32 _timelock,
        uint _secret,
        string memory _location
        ) = vendorContract.getVulnerabilityInfo(_vulnerabilityId);

        // Retrive vulnerability RewardState
        (VendorContract.RewardState _rewState, uint _amount) = vendorContract.getVulnerabilityReward(_vulnerabilityId);

        emit LogVulnerabilitybyID(
         _researcher,
         _timestamp,
         _state,
         _hashlock,
         _timelock,
         _secret,
         _rewState,
        _amount);
    }

    /**
     * @notice Get the metadata of a vulnerability
     * @dev Need to split in two functions to avoid stack too deep exc
     * @param _vulnerabilityId Id into Vulnerabilities mapping.
     */
    function getMetadataById(bytes32 _vulnerabilityId)
        public
    {
        if (haveVulnerability(_vulnerabilityId) == false){
            emit LogVulnerabilityNotFound(_vulnerabilityId);
            return;
        }

        VendorContract vendorContract = VendorVulnerabilities[_vulnerabilityId];

        //Retrivevulnerability metadata

        (address vendor,
        uint32 vendorId,
        uint32 productId,
        bytes32 vulnerabilityHash) = vendorContract.getVulnerabilityMetadata(_vulnerabilityId);

        emit LogMetadatabyID(vendor, vendorId, productId, vulnerabilityHash);
    }

    
    /**
     * @dev Get the list of registered vendors
     * @return The list of vendor smart contract addresses
     */
    function getRegisteredVendors() public view returns(address[] memory) {

        uint len = vendorContractsList.length;
        address[] memory _contracts = new address[](len);

        for(uint i=0; i<len; i++) {
            _contracts[i] = address(vendorContractsList[i]._contract);
        }

        return _contracts;
    }

    /**
     * @dev Is there a contract with id _vulnerabilityId.
     * @param _vulnerabilityId Id into Vulnerabilities mapping.
     */
    function haveVulnerability(bytes32 _vulnerabilityId)
        internal
        view
        returns (bool exists)
    {
        exists = (address(VendorVulnerabilities[_vulnerabilityId]) != address(0));
    }

    /**
     * @dev Is there a contract with meta _meta.
     * @param _hashData the hash of the vulnerability data
     */
    function haveHashData(bytes32 _hashData)
        internal
        view
        returns (bool exists)
    {
        exists = (HashData[_hashData] != 0x0);
    }

    /**
     * @dev Is the input contract disclosable
     * @param _vulnerabilityId Contract identifier
     */
    function isDisclosable(bytes32 _vulnerabilityId) public view returns(bool) {

        VendorContract vendorContract = VendorVulnerabilities[_vulnerabilityId];
        (,,VendorContract.State _state,,uint _timlock,,)=vendorContract.getVulnerabilityInfo(_vulnerabilityId);
        return  ((_state == VendorContract.State.Valid || _state == VendorContract.State.Acknowledged) && _timlock < block.timestamp) ||
                (_state == VendorContract.State.Patched);

    }

}
