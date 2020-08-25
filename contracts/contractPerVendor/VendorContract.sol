pragma solidity ^0.6.0;

//import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


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
    constructor(address _vendor, address _authority) public {

        authority = _authority;
        transferOwnership(_vendor); // Otherwise the owner is the Authority contract
    }

    // Logs

    event LogVulnerabilityAcknowledgment(bytes32 indexed vulnerabilityId, address indexed vendor, uint bounty);
    event LogVulnerabilityPatch(bytes32 indexed vulnerabilityId, address indexed vendor);
    event LogBountyCanceled(bytes32 indexed vulnerabilityId, string motivation);
    event ProductRegistered(bytes32 indexed productId);
    event ProductUnregistered(bytes32 indexed productId);

    // Modifiers

    modifier onlyAuhtority {

        require(msg.sender == authority, "The caller is not the authority");
        _;
    }

    modifier fundsSent() {

        require(msg.value > 0, "msg.value must be > 0");
        _;
    }

     modifier vulnerabilityExists(bytes32 _vulnerabilityId) {

        require(haveVulnerability(_vulnerabilityId), "vulnerabilityId does not exist");
        _;
    }

    modifier isValid(bytes32 _vulnerabilityId) {

        // Check whether a contract is Valid, i.e. it has been approved
        require(Vulnerabilities[_vulnerabilityId].state == State.Valid, "State is not Valid");
        _;
    }


    // State variables

    uint public balanceOwner;       // This variable stores the amount the contract has "free" to pay for the bounties.
                                    // A new bounty decreases this amount; funding the contract or cancelling a bounty increase it
    address public authority;


    // States

    enum State {Pending, Invalid, Valid, Duplicate, Acknowledged, Patched, Disclosable, Disclosed}
    enum RewardState {NULL, SET, CANCELED, SENT}


    // Structs

    struct Product {
        uint32 registeredSince;
        uint32 unregisteredSince;
        bool registered;
        string productName;
    }

    struct Reward {

        RewardState state;
        uint amount;
    }

    // Extra data to track 
    struct Metadata {
        uint32 timestamp;                 // The timestamp of the creation of the vulnerability
        bytes32 productId;          // The Id of the product (name and version)
        bytes32 vulnerabilityHash;  // The hash of the vulnerability information
    }

    struct Vulnerability {

        address payable expert; // expert address
        uint32 ackTimelock;                 // UNIX timestamp seconds - locked UNTIL this time //first deadline
        uint32 timelock;                  // UNIX timestamp seconds - locked UNTIL this time //second deadline
        State state;                  // The state of the vulnerability
        Reward reward;                  // The reward for this vulnerability
        Metadata metadata;              // Metadata info
        uint secret;                    // The secret
        bytes32 hashlock;               // Sha-2 sha256 the secret used as hashlock
        string vulnerabilityLocation;   // A pointer to a location with the vulnerability information
    }

    // Maps

    mapping (bytes32 => Vulnerability) Vulnerabilities; //mapping _vulnerability_id => _vulnerability;
    mapping (bytes32=> Product) public Products;// mapping productId => Product
    bytes32[] public productIdx; // a list of vendor's product by product id



    // External methods (callable only by Authority contract)

    /**
        @notice The function is called by the Authority to set up a new vulnerability record
        @param vulnerabilityId The vulnerability identifier, bytes32
        @param _expert The Expert address
        @param _productId The id of the product, bytes32
        @param _vulnerabilityHash The hash of the vulnerability data, bytes32
        @param _hashlock The hashlock, bytes32
        @dev Only the authority
    */
    function newVulnerability (
        bytes32 vulnerabilityId,
        address payable _expert,
        bytes32 _productId,
        bytes32 _vulnerabilityHash,
        bytes32 _hashlock
        ) external onlyAuhtority {

        require(productExist(_productId), "Product Id not registered");

        // Store the new vulnerability entry
        Reward memory reward = Reward({amount: 0, state: RewardState.NULL});
        Metadata memory metadata = Metadata({
                                        timestamp: uint32(block.timestamp),
                                        productId: _productId,
                                        vulnerabilityHash: _vulnerabilityHash
                                    });

        // Create new vulnerability entry
        Vulnerabilities[vulnerabilityId] = Vulnerability({
            expert: _expert,
            hashlock: _hashlock,
            ackTimelock:0,
            timelock: 0,
            vulnerabilityLocation: "",
            state: State.Pending,
            secret: 0,
            metadata: metadata,
            reward: reward
        });

    }

    /**
        @notice Set the state of the vulnerability in the ARD process
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _state The state to set
        @dev Only the authority
    */
    function setState(bytes32 _vulnerabilityId, State _state) external onlyAuhtority {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];
        v.state = _state;
    }

    /**
        @notice Set the state of the reward
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _rewState The state to set
        @dev Only the authority
    */
    function setRewardState(bytes32 _vulnerabilityId, RewardState _rewState) external onlyAuhtority {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];
        v.reward.state = _rewState;
    }

    /**
        @notice Set the timelock
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _timelock The new timelock in UNIX epoch time
        @dev Only the authority
    */
    function setTimelock(bytes32 _vulnerabilityId, uint32 _ackTimelock, uint32 _timelock) external onlyAuhtority {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];

        require(v.timelock == 0, "Timelock has been set already");
        v.ackTimelock = _ackTimelock;
        v.timelock = _timelock;
    }

    /**
        @notice Set the secret
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _secret The hashlock preimage, uint
        @dev Only the authority
    */
    function setSecret(bytes32 _vulnerabilityId,uint _secret) external onlyAuhtority {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];

        require(v.secret == 0, "Secret has been set already");
        v.secret = _secret;
    }

    /**
        @notice Set the location of the vulnerability information
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _location The location to disclose the vulnerability, string
        @dev Only the authority
    */
    function setLocation(bytes32 _vulnerabilityId,string calldata _location) external onlyAuhtority {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];
        v.vulnerabilityLocation = _location;
    }

    /**
        @notice Cancel the bounty assigned to a vulnerability
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _motivation The motivation why vulnerability has been deleted, string
        @dev Emits LogBountyCanceled(bytes32 indexed vulnerabilityId, string motivation)
        @dev Only the authority
    */
    function cancelBounty(bytes32 _vulnerabilityId, string calldata _motivation) external onlyAuhtority {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];

        require(v.reward.state == RewardState.SET, "A bounty has to be SET to be canceled");

        uint amount = v.reward.amount;
        v.reward.state = RewardState.CANCELED;
        v.reward.amount = 0;
        balanceOwner += amount;

        emit LogBountyCanceled(_vulnerabilityId, _motivation);
    }

    /**
        @notice Pay the bounty to the researcher of a vulnerability
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @dev Only the authority
    */
     function payBounty(bytes32 _vulnerabilityId) external onlyAuhtority {
        // Checks done by the Authority.withdrawBounty function
        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];

        uint amount = v.reward.amount;
        address payable _expert = v.expert;
        v.reward.state = RewardState.SENT;
        _expert.transfer(amount);
    }


    // Public methods callable only by the Owner (the vendor)


    /**
        @notice Register a product in the contract
        @param _productName The product name, string
        @dev Emits ProductRegistered(bytes32 indexed _productId)
        @dev Only the owner
    */
     function registerProduct(string calldata _productName) onlyOwner external {

         bytes32 _productId = keccak256(
            abi.encodePacked(
            owner(),
            _productName
            )
        );

        require(!productExist(_productId),"This product already exist");

        Product memory newProduct = Product({productName:_productName,
                                                  registeredSince:uint32(block.timestamp),
                                                  unregisteredSince:0,
                                                  registered:true
                                                });

        Products[_productId] = newProduct;     // Store in the map the new pair (_productId, newProduct)
        productIdx.push(_productId);   // Store vendor address in array

        emit ProductRegistered(_productId);
    }

    /**
        @notice Unregister a product in the contract
        @param _productId The id of the product, bytes32
        @dev Emits ProductUnregistered(bytes32 indexed _productId)
        @dev Only the owner
    */
    function unregisterProduct(bytes32 _productId) onlyOwner external {

        require(productIsRegistered(_productId));

        // Deactivate product
        Product storage p = Products[_productId];
        p.registered=false;
        p.unregisteredSince = uint32(block.timestamp);

        emit ProductUnregistered(_productId);
    }



    /**
        @notice Acknowledge the vulnerability and set a bounty as a reward
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @param _bounty The reward to the Researcher
        @dev Emits LogVulnerabilityAcknowledgment(bytes32 indexed vulnerabilityId, address indexed vendor, uint bounty)
        @dev Only the owner, _vulnerabilityId exists and it is valid, and the contract has sufficient funds for the bounty
    */
    function acknowledge(bytes32 _vulnerabilityId, uint _bounty)
        public
        vulnerabilityExists(_vulnerabilityId)
        isValid(_vulnerabilityId)
        onlyOwner {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];

        require(uint32(block.timestamp) < v.ackTimelock, "The ack timelock has expired");
        require(balanceOwner > _bounty, "Available balance not enough to fund the bounty");

        v.state = State.Acknowledged;
        
        v.reward.state = RewardState.SET;
        v.reward.amount = _bounty;
        balanceOwner -= _bounty;

        emit LogVulnerabilityAcknowledgment(_vulnerabilityId, msg.sender, _bounty);
    }

    /**
        @notice Set the vulnerability as patched
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @dev Emits LogVulnerabilityPatch(bytes32 indexed vulnerabilityId, address indexed vendor)
        @dev Only the owner, _vulnerabilityId exists and it is acknowledged
    */
    function patch(bytes32 _vulnerabilityId) public vulnerabilityExists(_vulnerabilityId) onlyOwner {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];

        require(v.state == State.Acknowledged, "The vulnerability has not been acknowledged");

        v.state = State.Patched;
        emit LogVulnerabilityPatch(_vulnerabilityId, msg.sender);
    }

    /**
        @notice Allow the owner to withdraw some funds
        @param _amount The amount to withdraw, uint
        @dev Only the owner
    */
    function withdraw(uint _amount) external onlyOwner {
        require(balanceOwner >= _amount, "Funds not available");
        balanceOwner -= _amount;
        payable(owner()).transfer(_amount);
    }


    // Getter and Utility

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
        bool registered){

        require(idx<productIdx.length, "Out of range");
        bytes32 productId=productIdx[idx];
        Product memory p = Products[productId];
        return (p.productName,p.registeredSince,p.unregisteredSince,p.registered);
     }


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
        bool registered) {

        Product memory p = Products[_productId];
        return (p.productName,p.registeredSince,p.unregisteredSince,p.registered);
     }


    /**
        @notice Check whether a product exists
        @param _productId The id of the product, bytes32
        @return exists True if the product exists, false otherwise
    */
      function productExist(bytes32 _productId)
        internal
        view
        returns (bool exists)
    {
        string memory pname=Products[_productId].productName;
        exists=( bytes(pname).length != 0);
    }

    /**
        @notice Check whether a product is registered
        @param _productId The id of the product, bytes32
        @return registered True if the product is registered, false otherwise
    */
    function productIsRegistered(bytes32 _productId)
        internal
        view
        returns (bool registered)
    {
        require(productExist(_productId), "This product doesn't exist");
        registered=Products[_productId].registered;
    }


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
    function getVulnerabilityInfo(bytes32 _vulnerabilityId) external view returns(
        address ,
        State ,
        bytes32 ,
        uint32 ,
        uint32 ,
        uint ,
        string memory
        ) {

        Vulnerability memory v = Vulnerabilities[_vulnerabilityId];
        return(address(v.expert), v.state, v.hashlock, v.timelock, v.ackTimelock, v.secret, v.vulnerabilityLocation);
    }

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
        bytes32 vulnerabilityHash) {

        Vulnerability memory v = Vulnerabilities[_vulnerabilityId];
        return(v.metadata.timestamp, v.metadata.productId, v.metadata.vulnerabilityHash);
    }

    /**
        @notice Get the reward data of a vulnerability
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @return _state The reward state,uint8
        @return _amount The reward amount, uint
        @dev The reason the get function has been split is due to StackTooDeep Exception
    */
    function getVulnerabilityReward (bytes32 _vulnerabilityId) external view returns(RewardState _state, uint _amount){

        Vulnerability memory v = Vulnerabilities[_vulnerabilityId];
        return(v.reward.state,v.reward.amount);
    }


    /**
        @dev Check if a vulnerability id exists
        @param _vulnerabilityId The vulnerability identifier, bytes32
        @return exists True if the vulnerability exists, false otherwise
     */
    function haveVulnerability(bytes32 _vulnerabilityId)
        internal
        view
        returns (bool exists) {
        exists = (Vulnerabilities[_vulnerabilityId].expert != address(0));
    }

    /**
        @dev The solidity > 0.6 keyword function to receive ether
        @dev Only by the Owner
    */
    receive() external payable onlyOwner {
        balanceOwner += msg.value;
    }
}
