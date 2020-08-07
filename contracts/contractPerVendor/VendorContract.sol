pragma solidity ^0.6.0;

//import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VendorContract is Ownable {

    constructor(address _vendor, address _authority) public {

        authority = _authority;
        transferOwnership(_vendor); // Otherwise the owner is the Authority contract
    }

    // Logs

    event LogVulnerabilityAcknowledgment(bytes32 indexed vulnerabilityId, address indexed vendor, uint bounty);
    event LogVulnerabilityPatch(bytes32 indexed vulnerabilityId, address indexed vendor);
    event LogBountyCanceled(bytes32 indexed vulnerabilityId, string motivation);
    event ProductRegistered(bytes32 indexed _productId);
    event ProductUnregistered(bytes32 indexed _productId);

    // Modifiers

    modifier onlyAuhtority {

        require(msg.sender == authority);
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

    enum State {Pending, Invalid, Valid, Acknowledged, Patched, Disclosable, Disclosed}
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

        address payable researcher; // Researcher address
        uint32 timelock;                  // UNIX timestamp seconds - locked UNTIL this time //deadline
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
     * @dev The function is called by the vulnerability authority to set up a new vulnerability contract.
     *
     * @param vulnerabilityId The identifier of the vulnerability
     * @param _researcher The Resercher address
     * @param _productId The id of the product
     * @param _vulnerabilityHash The hash of the vulnerability data
     * @param _hashlock The secret hash used also for the hashlock (sha-2 sha256).
     */

    function newVulnerability (
        bytes32 vulnerabilityId,
        address payable _researcher,
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
            researcher: _researcher,
            hashlock: _hashlock,
            timelock: 0,
            vulnerabilityLocation: "",
            state: State.Pending,
            secret: 0,
            metadata: metadata,
            reward: reward
        });

    }

    /**
     * @dev The authority set the state of vulnerability
     *
     * @param _vulnerabilityId The identifier of the vulnerability
     * @param _state The state of the vulnerability
     */

    function setState(bytes32 _vulnerabilityId, State _state) external onlyAuhtority {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];
        v.state = _state;
    }

    /**
     * @dev The authority set the state of the reward
     *
     * @param _vulnerabilityId The identifier of the vulnerability
     * @param _rewState The state of the reward
     */

    function setRewardState(bytes32 _vulnerabilityId, RewardState _rewState) external onlyAuhtority {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];
        v.reward.state = _rewState;
    }

     /**
     * @dev The authority set the timelock of the vulnerability
     *
     * @param _vulnerabilityId The identifier of the vulnerability
     * @param _timelock The new timelock of the vulnerability
     */

    function setTimelock(bytes32 _vulnerabilityId, uint32 _timelock) external onlyAuhtority {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];

        require(v.timelock == 0, "Timelock has been set already");
        v.timelock = _timelock;
    }

    /**
     * @dev The authority set the secret of the vulnerability
     *
     * @param _vulnerabilityId The identifier of the vulnerability
     * @param _secret The secret of the vulnerability
     */

    function setSecret(bytes32 _vulnerabilityId,uint _secret) external onlyAuhtority {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];

        require(v.secret == 0, "Secret has been set already");
        v.secret = _secret;
    }

     /**
     * @dev The authority set the location (URL) of the vulnerability
     *
     * @param _vulnerabilityId The identifier of the vulnerability
     * @param _location The locaction of the vulnerability
     */

    function setLocation(bytes32 _vulnerabilityId,string calldata _location) external onlyAuhtority {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];
        v.vulnerabilityLocation = _location;
    }

    /**
     * @dev The authority cancels the vulnerability bounty (e.g the researcher cheated)
     *
     * @param _vulnerabilityId The identifier of the vulnerability
     * @param _motivation The motivation why vulnerability has been deleted
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
     * @dev The authority pay the bounty to the researcher (e.g the researcher cheated)
     *
     * @param _vulnerabilityId The identifier of the vulnerability
     */

     function payBounty(bytes32 _vulnerabilityId) external onlyAuhtority {
        // Checks done by the Authority.withdrawBounty function
        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];

        uint amount = v.reward.amount;
        address payable _researcher = v.researcher;
        v.reward.state = RewardState.SENT;
        _researcher.transfer(amount);
    }


    // Public methods callable only by the Owner (the vendor)

    /**
     * @dev The Vendor registers a product
     *
     * @param _productName The product name
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
     * @dev The Vendor unregisters a product
     *
     * @param _productId The product identifier
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
     * @dev The vendor acknowledges the vulnerability and set the ETH as a reward for the researcher.
     *
     * @param _vulnerabilityId The condract identifier.
     * @param _bounty The bounty in ETH.
     */

    function acknowledge(bytes32 _vulnerabilityId, uint _bounty)
        public
        // payable
        // fundsSent()
        vulnerabilityExists(_vulnerabilityId)
        isValid(_vulnerabilityId)
        onlyOwner {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];

        require(uint32(block.timestamp) < v.timelock, "The timelock has expired");
        // require(msg.value == _bounty, "Value sent does not match the input bounty");
        require(balanceOwner > _bounty);

        v.state = State.Acknowledged;
        v.reward.state = RewardState.SET;
        v.reward.amount = _bounty;
        balanceOwner -= _bounty;

        emit LogVulnerabilityAcknowledgment(_vulnerabilityId, msg.sender, _bounty);
    }

    /**
     * @dev The vendor provides a patch to the vulnerability.
     *
     * @param _vulnerabilityId The condract identifier.
     */

    function patch(bytes32 _vulnerabilityId) public vulnerabilityExists(_vulnerabilityId) onlyOwner {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];

        require(v.state == State.Acknowledged, "The vulnerability has not been acknowledged");

        v.state = State.Patched;
        emit LogVulnerabilityPatch(_vulnerabilityId, msg.sender);
    }

    /**
    * @dev The vendor withdraw ETH from the contract.
     *
     * @param _amount The amount to withdraw
     */

    function withdraw(uint _amount) external onlyOwner {
        require(balanceOwner >= _amount);
        balanceOwner -= _amount;
        payable(owner()).transfer(_amount);
    }


    // Getter and Utility

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

    function getProductById(bytes32 _productId) public view returns(
        string memory productName,
        uint32 registeredSince,
        uint32 unregisteredSince,
        bool registered) {

        Product memory p = Products[_productId];
        return (p.productName,p.registeredSince,p.unregisteredSince,p.registered);
     }

      function productExist(bytes32 _productId)
        internal
        view
        returns (bool exists)
    {
        string memory pname=Products[_productId].productName;
        exists=( bytes(pname).length != 0);
    }

    function productIsRegistered(bytes32 _productId)
        internal
        view
        returns (bool registered)
    {
        require(productExist(_productId), "This product doesn't exist");
        registered=Products[_productId].registered;
    }


    function getVulnerabilityInfo (bytes32 _vulnerabilityId) external view returns(
        address ,
        State ,
        bytes32 ,
        uint32 ,
        uint ,
        string memory
        ) {

        Vulnerability memory v = Vulnerabilities[_vulnerabilityId];
        return(address(v.researcher), v.state, v.hashlock, v.timelock, v.secret, v.vulnerabilityLocation);
    }


    function getVulnerabilityMetadata (bytes32 _vulnerabilityId) external view returns(
        uint32 timestamp,
        bytes32 productId,
        bytes32 vulnerabilityHash) {

        Vulnerability memory v = Vulnerabilities[_vulnerabilityId];
        return(v.metadata.timestamp, v.metadata.productId, v.metadata.vulnerabilityHash);
    }

    function getVulnerabilityReward (bytes32 _vulnerabilityId) external view returns(RewardState _state, uint _amount){

        Vulnerability memory v = Vulnerabilities[_vulnerabilityId];
        return(v.reward.state,v.reward.amount);
    }

      /**
     * @dev Is there a contract with id _vulnerabilityId.
     * @param _vulnerabilityId Id into Vulnerabilities mapping.
     */
    function haveVulnerability(bytes32 _vulnerabilityId)
        internal
        view
        returns (bool exists) {
        exists = (Vulnerabilities[_vulnerabilityId].researcher != address(0));
    }

    // Receive function to fund the contract
    receive() external payable onlyOwner {
        balanceOwner += msg.value;
    }
}
