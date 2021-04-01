const Migrations = artifacts.require("Migrations");
const Authority = artifacts.require("AuthorityContract");
const Vendor = artifacts.require("VendorContract");
const Factory = artifacts.require("VendorFactory");


/**
 * This function creates the Authority contract and the Factory to build Vendor contracts
 * @param {*} authority The authority address
 * @param {*} interledger The interledger address
 * @returns The Authority smart contract instance
 */
async function deploy_authority_contract(authority, interledger) {

    let factoryC = await Factory.new({from: authority});
    let authorityC = await Authority.new(interledger, factoryC.address, {from: authority});
    await factoryC.transferOwnership(authorityC.address, {from: authority})

    return authorityC;
}


/**
 * This function creates a Vendor contract
 * @param {*} vendor The authority contract
 * @param {*} authority The authority address
 * @param {*} authorityC The Authority contract
 * @returns The Vendor smart contract instance
 */
async function deploy_vendor_contract(vendor, authority, authorityC) {

    // When calling a writing function, the result is a transaction object
        // The address of the vendor smart contract is emitted with an event
        // In this flow, the interesting event is the third fired
        // Once we have the address of the interesting contract, retrieve the instance so we can call the functions
    let tx = await authorityC.registerVendor(vendor, {from: authority});
    let address = tx["logs"][2].args.vendorContract;
    let vendorC = await Vendor.at(address);

    return vendorC;
}

/**
 * Register a product on a vendor contract
 * @param {*} vendor The authority contract
 * @param {*} name The product name
 * @param {*} vendorC The Vendor contract
 * @returns The product id
 */
async function register_product(vendor, name, vendorC) {

    let tx = await vendorC.registerProduct(name, {from: vendor});
    let p_id = tx["logs"][0].args.productId;

    return p_id;
}


/**
 * Submit a vulnerability to the Auhtority contract
 * @param {*} expert The expert contract
 * @param {*} authorityC The Authority contract
 * @param {*} vendor The vendor address
 * @param {*} hashlock The hashlock
 * @param {*} productId The product id
 * @param {*} vulnerabilityHash The hash of the vulnerability
 * @returns The vulnerability id
 */
async function register_vulnerability(expert, authorityC, vendor, hashlock, productId, vulnerabilityHash) {

    let tx = await authorityC.registerVulnerability(vendor, hashlock, productId, vulnerabilityHash, {from: expert});
    let v_id = tx["logs"][0].args.vulnerabilityId;

    return v_id;
}


/**
 * Truffle hook method
 * 
 * @param {*} deployer 
 * @param {*} network The network name in truffle-config.js
 * @param {*} accounts The list of accounts from the connected network
 */
module.exports = async function(deployer, network, accounts) {

    // Execute this script only with one of these two networks
    if(network != "to_patch" || network != "to_grace_period")
        return;
    
    // Store sample accounts for migration
        // These accounts belong to the actors like Authority, Vendor and Expert to interact with the system
        // Also know as Externally Owned Account (EOA)
    let authority = accounts[0];
    let expert = accounts[1];
    let vendor = accounts[2];
    let interledger = accounts[3];

    let authorityC;
    let vendorC;
    let productId;
    let vulnerabilityId;
    let timelock;

    const ackTimelock = Math.round(new Date() / 1000) + 5; // Seconds
    const DECISION = { Approved: 0, Invalid: 1, Duplicate: 2 };
    const bounty = web3.utils.toWei('1', 'ether');
    const funds = web3.utils.toWei('5', 'ether');
    const secret = 123;
    const hashlock = web3.utils.soliditySha3({type: 'uint', value: secret});
    const vulnerabilityData = "Vulnerability detailed description in text format";
    const vulnerabilityHash = web3.utils.soliditySha3({type: 'string', value: vulnerabilityData});

    authorityC = await deploy_authority_contract(authority, interledger);
    console.log("-- Authority Contract deployed at address: " + authorityC.address);

    vendorC = await deploy_vendor_contract(vendor, authority, authorityC);
    console.log("-- Vendor Contract deployed at address: " + vendorC.address);

    // Fund the Vendor contract with ETH to pay for the bounties (plain transaction)
    await web3.eth.sendTransaction({
        from: vendor,
        to: vendorC.address,
        value: funds
    });
    console.log("-- Vendor contract " + vendorC.address + " funded with " + web3.utils.fromWei(funds+'', 'ether') + " ETH");

    productId = await register_product(vendor, "Nokia", vendorC);
    console.log("-- Product registered with ID: " + productId);

    vulnerabilityId = await register_vulnerability(expert, authorityC, vendor, hashlock, productId, vulnerabilityHash);
    console.log("-- Vulnerability registered with ID: " + vulnerabilityId);

    // Interledger data payload
    const code = 1; // Approve
    const payload = web3.eth.abi.encodeParameters(['uint256', 'uint', 'bytes'], [vulnerabilityId.toNumber(), code, "0x0"]);

    if(network == "to_approve") {

        console.log("-- Vulnerability with ID " + vulnerabilityId + "waiting for approval.");
        console.log("-- Data payload the smart contract expects to receive: " + payload);
        console.log("--- Computed from Solidity's abi.encode() with input: [" + vulnerabilityId.toNumber() + ", " + true + ", 0x0]");
        return;
    }

    else if(network == "to_patch") {        
        // Give enough to the grace period
        timelock = Math.round(new Date() / 1000) + 100000;
    }

    else if(network == "to_grace_period") {
        // Give little grace period to be able to trigger the "expired grace period condition"
        timelock = Math.round(new Date() / 1000) + 10;
    }

    // Authority: Approve vulnerability
    await authority.interledgerReceive(vulnerabilityId, payload, {from: interledgerAddress});
    console.log("-- Vulnerability with ID " + vulnerabilityId + " approved. Timelock: " + (timelock - Math.round(new Date() / 1000)) + " seconds");

    // Vendor: Acknowledge vulnerability
    await vendorC.acknowledge(vulnerabilityId, bounty, {from: vendor});
    console.log("-- Vulnerability with ID " + vulnerabilityId + " acknowledged. Bounty: " + web3.utils.fromWei(bounty+'', 'ether') + " ETH");

    // **Eventually put here the call to the publishSecret function**
};
