pragma solidity ^0.6.0;

// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// TODO Change the variables with the data types proposed in the ARD document

contract VendorContract is Ownable {

    constructor(address payable _vendor) public {

        vulnerabilityAuthority = msg.sender;
        transferOwnership(_vendor); // Otherwise the owner is the Authority contract
    }

    // Logs

    event LogVulnerabilityAcknowledgment(bytes32 indexed vulnerabilityId, address indexed vendor, uint bounty);
    event LogVulnerabilityPatch(bytes32 indexed vulnerabilityId, address indexed vendor);
    event LogBountyCanceled(bytes32 indexed vulnerabilityId, string reason);

    // Modifiers

    modifier onlyAuhtority {

        require(msg.sender == vulnerabilityAuthority);
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

    // uint totBalance;
    uint balanceOwner;              // This variable stores the amount the contract has "free" to pay for the bounties.
                                    // A new bounty decreases this amount; funding the contract or cancelling a bounty increase it
    address vulnerabilityAuthority;


    // States

    enum State {Pending, Invalid, Valid, Acknowledged, Patched, Disclosed}
    enum RewardState {NULL, SET, TOCLAIM, CANCELED, SENT}


    // Structs

    struct Reward {

        RewardState state;
        uint amount;
    }

    struct Metadata {

        address payable vendor;     // The address of the vendor
        uint32 vendorId;         // The Id of the vendor
        uint32 productId;          // The Id of the product (name and version)
        bytes32 vulnerabilityHash;  // The hash of the vulnerability information
    }

    struct Vulnerability {

        address payable researcher; // Researcher address
        uint32 timestamp;                 // The timestamp of the creation of the vulnerability
        uint32 timelock;                  // UNIX timestamp seconds - locked UNTIL this time //deadline
        State state;                  // The state of the vulnerability
        Metadata metadata;              // Metadata info
        Reward reward;                  // The reward for this vulnerability
        uint secret;                    // The secret
        bytes32 hashlock;               // Sha-2 sha256 the secret used as hashlock
        string vulnerabilityLocation;   // A pointer to a location with the vulnerability information
    }

    // Maps

    mapping  (bytes32 => Vulnerability) Vulnerabilities; //mapping _vulnerability_id => _vulnerability;

    // External methods (callable only by Authority contract)

    /**
     * @dev The function is called by the vulnerability authority to set up a new vulnerability contract.
     *
     * @param vulnerabilityId The identifier of the vulnerability
     * @param _vendor The Vendor address, the owner of the vulnerable device
     * @param _researcher The Resercher address
     * @param _vendorId The id of the vendor
     * @param _productId The id of the product
     * @param _vulnerabilityHash The hash of the vulnerability data
     * @param _hashlock The secret hash used also for the hashlock (sha-2 sha256).
     */

    function newVulnerability (
        bytes32 vulnerabilityId,
        address payable _vendor,
        address payable _researcher,
        uint32 _vendorId,
        uint32 _productId,
        bytes32 _vulnerabilityHash,
        bytes32 _hashlock
        ) external onlyAuhtority {

        // Store the new vulnerability entry
        Reward memory reward = Reward({amount: 0, state: RewardState.NULL});
        Metadata memory metadata = Metadata({
                                        vendor: _vendor,
                                        vendorId: _vendorId,
                                        productId: _productId,
                                        vulnerabilityHash: _vulnerabilityHash
                                    });

        // Create new vulnerability entry
        Vulnerabilities[vulnerabilityId] = Vulnerability({
            researcher: _researcher,
            timestamp: uint32(block.timestamp),
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
     * @dev The authority cacel the vulnerability bounty (e.g the researcher cheated)
     *
     * @param _vulnerabilityId The identifier of the vulnerability
     * @param reason The reason why vulnerability has been deleted
     */

    // TODO make this function a cooperation between Authority and Vendor
    function cancelBounty(bytes32 _vulnerabilityId, string calldata reason) external onlyAuhtority {

        Vulnerability storage v = Vulnerabilities[_vulnerabilityId];

        uint amount = v.reward.amount;
        v.reward.state = RewardState.CANCELED;
        v.reward.amount = 0;
        balanceOwner += amount;

        emit LogBountyCanceled(_vulnerabilityId, reason);
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



    function getVulnerabilityInfo (bytes32 _vulnerabilityId) external view returns(
        address ,
        uint32 ,
        State ,
        bytes32 ,
        uint32 ,
        uint ,
        string memory
        ) {

        Vulnerability memory v = Vulnerabilities[_vulnerabilityId];
        return(address(v.researcher), v.timestamp, v.state, v.hashlock, v.timelock, v.secret, v.vulnerabilityLocation);
    }


    function getVulnerabilityMetadata (bytes32 _vulnerabilityId) external view returns(
        address vendor,
        uint32 vendorId,
        uint32 productId,
        bytes32 vulnerabilityHash) {

        Vulnerability memory v = Vulnerabilities[_vulnerabilityId];
        return(address(v.metadata.vendor), v.metadata.vendorId, v.metadata.productId, v.metadata.vulnerabilityHash);
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
