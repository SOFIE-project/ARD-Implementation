pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";

// TEMPORARY
// Documentation for the contractPerVendor functions, not in contracts/ otherwise it does not compile

/**
    @title VendorFactory
    @notice This contract has the job to instantiate VendorContract. This contract works only after its ownership will be tranfered (see ARD document). Inherits from OpenZeppelin Ownable
    @dev Letting the AuthorityContract create the VendorContract, it would not be deployable due to bytecode too large
 */
contract VendorFactory is Ownable {

    /**
        @notice Instantiate a contract of type VendorContract with _vendor as its owner
        @dev This function reverts if ownership has not been tranfered (see ARD document for motivation)
        @param _vendor The owner of the new VendorContract
     */
    function createVendorContract(address _vendor) onlyOwner public returns(VendorContract) { }

    /**
        @notice Override OpenZeppelin transfer method to unlock the creation method 
        @param newOwner The new owner
     */
    function transferOwnership(address newOwner) public virtual override onlyOwner { }
}






/**
    @title AuthorityContract
    @notice This contract reflects the Authority in the ARD process. Inherits from OpenZeppelin Ownable
 */
contract AuthorityContract is Ownable {

    /**
        @notice The constructor of the contract expects the Interledger address and the address of a VendorFactory contract
        @param _interledger The address of the interledger component
        @param _factory The address of a VendorFactory contract
     */
    constructor(address _interledger, VendorFactory _factory) public { }


    /**
        @notice Register a new vendor, i.e. create a new VendorContract through the Factory
        @param _vendor The address of vendor EOA to register (and owner of the VendorContract)
        @dev Emits an event VendorRegistered(address indexed _vendor, address _vendorContract) with the address of the vendor and the new VendorContract respectively
        @dev Only the Authority owner
     */     
    function registerVendor(address _vendor) external { }


    /**
        @notice Un-register a vendor
        @param _vendor The address of vendor EOA to un-register
        @dev Emits an event VendorUnregistered(address indexed _vendor) with the address of the vendor EOA
        @dev Only the Authority owner
     */     
    function unregisterVendor(address _vendor) external { }


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
                                                            bool registered) { }


    /**
        @notice Check if a vendor exists, i.e. they have a VendorContract associated
        @param _vendor The vendor EOA
        @return exists True if the vendor has a contract, false otherwise
        @dev Internal function
     */     
    function vendorExist(address _vendor) internal view returns (bool exists) { }


    /**
        @notice Check if a vendor is regitered
        @param _vendor The vendor EOA
        @return registered True if the vendor is registered, false otherwise
        @dev Internal function
     */     
    function vendorIsRegistered(address _vendor) internal view returns (bool registered){ }
    

    /**
        @notice The resercher sets up a new vulnerability record
        @param _vendor The Vendor EOA address, the owner of the vulnerable device
        @param _hashlock The hashlock, bytes32
        @param _productId The id of the product, bytes32
        @param _vulnerabilityHash The hash of the vulnerability data, bytes32
        @return _vulnerabilityId Id of the new contract. This is needed for subsequent calls
        @dev If positive, emits LogVulnerabilityNew(bytes32 indexed vulnerabilityId, address indexed researcher, address indexed vendor, bytes32 hashlock, bytes32 vulnerabilityHash)
        @dev If duplicate (_vulnerabilityHash already present), emits LogVulnerabilityDuplicate(bytes32 indexed vulnerabilityId, address indexed vendor, uint32 timestamp, bytes32 productId, bytes32 vulnerabilityHash, VendorContract.State state)
        @dev Reverts if the generated vulnerability id already exists
    */  
    function registerVulnerability(address _vendor, bytes32 _hashlock,
                                bytes32 _productId, bytes32 _vulnerabilityHash)
        external
        returns (bytes32 _vulnerabilityId) { }


    /**
        @notice Approves, or not, the vulnerability contract and provides the lock terms.
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _timelock The timelock in UNIX epoch time
        @param _approved True if the vulnerability has to be approved, false otherwise
        @dev Emits LogVulnerabilityApproval(bytes32 indexed vulnerabilityId, uint32 timelock, VendorContract.State state)
        @dev Only the Authority owner, _vulnerabilityId exists
     */
    function approve(bytes32 _vulnerabilityId, uint32 _timelock, bool _approved) public { }


    /**
        @notice Publish the secret after the secret if the disclosable condition is met. Pay the bounty
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _secret The preimage of the hashlock, uint
        @dev Emits LogVulnerabilitySecret(bytes32 indexed vulnerabilityId, uint secret)
        @dev The secret mathces the hashlock, _vulnerabilityId exists and the vulnerability is disclosable
     */
    function publishSecret(bytes32 _vulnerabilityId, uint _secret) external { }


    /**
        @notice Disclose the vulnerability data location
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _vulnerabilityLocation The location to disclose the vulnerability, string
        @return success True if the function terminates
        @dev Emits LogVulnerabilityDisclose(bytes32 indexed vulnerabilityId, address indexed communicator, string vulnerabilityLocation)
        @dev Only the interledger component, _vulnerabilityId exists
     */
    function disclose(bytes32 _vulnerabilityId, string calldata _vulnerabilityLocation) external returns (bool success) { }


    /**
        @notice Cancels the vulnerability bounty
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _motivation The motivation why vulnerability has been deleted, string
        @dev Only the owner, _vulnerabilityId exists
     */
    function cancelBounty(bytes32 _vulnerabilityId, string calldata _motivation) external { }


    /**
        @notice Check if a vulnerability id exists
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @return exists True if _vulnerabilityId exists, false otherwise
        @dev Internal function
     */
    function haveVulnerability(bytes32 _vulnerabilityId) internal view returns (bool exists){ }


    /**
        @notice Check if a vulnerability is disclosable
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @return True if _vulnerabilityId can be disclosed, false otherwise exists, false otherwise
     */
    function isDisclosable(bytes32 _vulnerabilityId) public view returns(bool) { }
}







/**
    @title VendorContract
    @notice This contract reflects the Vendor in the ARD process. Inherits from OpenZeppelin Ownable
 */
contract VendorContract is Ownable {

    
    /**
        @notice The constructor of the contract expects the EOA vendor address to transfer the ownership to, and the address the Authority smart contract
        @param _vendor The address of the vendor EOA
        @param _authority The address of the AuthorityContract
     */
    constructor(address _vendor, address _authority) public { }


    /**
        @notice The function is called by the Authority to set up a new vulnerability record
        @param vulnerabilityId The vulnerability identifier, bytes32
        @param _researcher The Resercher address
        @param _productId The id of the product, bytes32
        @param _vulnerabilityHash The hash of the vulnerability data, bytes32
        @param _hashlock The hashlock, bytes32
        @dev Only the authority
    */
    function newVulnerability (
        bytes32 vulnerabilityId,
        address payable _researcher,
        bytes32 _productId,
        bytes32 _vulnerabilityHash,
        bytes32 _hashlock) external { }


    /**
        @notice Set the state of the vulnerability in the ARD process
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _state The state to set
        @dev Only the authority
    */
    function setState(bytes32 _vulnerabilityId, State _state) external { }


    /**
        @notice Set the state of the reward
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _rewState The state to set
        @dev Only the authority
    */
    function setRewardState(bytes32 _vulnerabilityId, RewardState _rewState) external { }


    /**
        @notice Set the timelock
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _timelock The new timelock in UNIX epoch time
        @dev Only the authority
    */
    function setTimelock(bytes32 _vulnerabilityId, uint32 _timelock) external { }


    /**
        @notice Set the secret
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _secret The hashlock preimage, uint
        @dev Only the authority
    */
    function setSecret(bytes32 _vulnerabilityId, uint _secret) external { }


    /**
        @notice Set the location of the vulnerability information
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _location The location to disclose the vulnerability, string
        @dev Only the authority
    */
    function setLocation(bytes32 _vulnerabilityId,string calldata _location) external { }


    /**
        @notice Cancel the bounty assigned to a vulnerability
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _motivation The motivation why vulnerability has been deleted, string
        @dev Emits LogBountyCanceled(bytes32 indexed vulnerabilityId, string motivation)
        @dev Only the authority
    */
    function cancelBounty(bytes32 _vulnerabilityId, string calldata _motivation) external { }


    /**
        @notice Pay the bounty to the researcher of a vulnerability
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @dev Only the authority
    */
     function payBounty(bytes32 _vulnerabilityId) external { }


    /**
        @notice Register a product in the contract
        @param _productName The product name, string
        @dev Emits ProductRegistered(bytes32 indexed _productId)
        @dev Only the owner
    */
     function registerProduct(string calldata _productName) external { }


    /**
        @notice Unregister a product in the contract
        @param _productId The id of the product, bytes32
        @dev Emits ProductUnregistered(bytes32 indexed _productId)
        @dev Only the owner
    */
    function unregisterProduct(bytes32 _productId) onlyOwner external { }


    /**
        @notice Acknowledge the vulnerability and set a bounty as a reward
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _bounty The reward to the Researcher
        @dev Emits LogVulnerabilityAcknowledgment(bytes32 indexed vulnerabilityId, address indexed vendor, uint bounty)
        @dev Only the owner, _vulnerabilityId exists and it is valid, and the contract has sufficient funds for the bounty
    */
    function acknowledge(bytes32 _vulnerabilityId, uint _bounty) public { }


    /**
        @notice Set the vulnerability as patched
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @dev Emits LogVulnerabilityPatch(bytes32 indexed vulnerabilityId, address indexed vendor)
        @dev Only the owner, _vulnerabilityId exists and it is acknowledged
    */
    function patch(bytes32 _vulnerabilityId) public { }


    /**
        @notice Allow the owner to withdraw some funds
        @param _amount The amount to withdraw, uint
        @dev Only the owner
    */
    function withdraw(uint _amount) external { }


    /**
        @notice Get a product by the array index
        @param idx The index of the product, uint
        @return productName The name the product, string
        @return registeredSince The timestamp of the registration date of the vendor
        @return unregisteredSince The timestamp of the unregistration date of the vendor (0 if still registered)
        @return registered True if the vendor is registered, false otherwise
    */
    function getProductyIdx(uint idx) public view returns(
                                                    string memory productName,
                                                    uint32 registeredSince,
                                                    uint32 unregisteredSince,
                                                    bool registered) { }



    /**
        @notice Get a product by its Id
        @param _productId The index of the product, uint
        @return productName The name the product, string
        @return registeredSince The timestamp of the registration date of the vendor
        @return unregisteredSince The timestamp of the unregistration date of the vendor (0 if still registered)
        @return registered True if the vendor is registered, false otherwise
    */
    function getProductById(bytes32 _productId) public view returns(
        string memory productName,
        uint32 registeredSince,
        uint32 unregisteredSince,
        bool registered) { }


    /**
        @notice Check whether a product exists
        @param _productId The id of the product, bytes32
        @return exists True if the product exists, false otherwise
    */
    function productExist(bytes32 _productId) internal view returns (bool exists) { }


    /**
        @notice Check whether a product is registered
        @param _productId The id of the product, bytes32
        @return exists True if the product is registered, false otherwise
    */
    function productIsRegistered(bytes32 _productId) internal view returns (bool registered) { }


    /**
        @notice Get the information of a vulnerability
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @return The researcher address, 
        @return The state of the vulnerability in the process, uint8
        @return The hashlock, bytes32
        @return The timelock, uint32
        @return The secret, uint
        @return The vulnerability location, string
        @dev The reason the get function has been split is due to StackTooDeep Exception
    */
    function getVulnerabilityInfo (bytes32 _vulnerabilityId) external view returns(
        address ,
        State ,
        bytes32 ,
        uint32 ,
        uint ,
        string memory
        ) { }



    /**
        @notice Get the metadata of a vulnerability
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @return timestamp The creation timestamp, uint32 
        @return productId The id of the product involved, uint32
        @return vulnerabilityHash The hash of the vulnerability data, bytes32
        @dev The reason the get function has been split is due to StackTooDeep Exception
    */
    function getVulnerabilityMetadata (bytes32 _vulnerabilityId) external view returns(
        uint32 timestamp,
        bytes32 productId,
        bytes32 vulnerabilityHash) { }


    /**
        @notice Get the reward data of a vulnerability
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @return _state The reward state,uint8
        @return _amount The reward amount, uint
        @dev The reason the get function has been split is due to StackTooDeep Exception
    */
    function getVulnerabilityReward (bytes32 _vulnerabilityId) external view returns(RewardState _state, uint _amount){ }


    /**
        @dev Check if a vulnerability id exists
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @return exists True if the vulnerability exists, false otherwise
     */
    function haveVulnerability(bytes32 _vulnerabilityId) internal view returns (bool exists) { }


    /**
        @dev The solidity > 0.6 keyword function to receive ether
        @dev Only by the Owner
    */
    receive() external payable { }
}
