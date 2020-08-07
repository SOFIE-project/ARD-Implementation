const truffleAssert = require('truffle-assertions');
const Authority = artifacts.require("AuthorityContract");
const Vendor = artifacts.require("VendorContractTest");
const Factory = artifacts.require("VendorFactory");

contract("AuthorityContract", function(accounts) {

    const researcherAddress = accounts[0];
    const vendorAddress = accounts[1];
    const authorityAddress = accounts[2];
    const interledgerAddress = accounts[3];
    
    const STATUS = {
        Pending: 0,
        Invalid: 1,
        Valid: 2,
        Acknowledged: 3,
        Patched: 4,
        Disclosable: 5,
        Disclosed: 6
    }

    const REWARDSTATE = {
        NULL: 0,
        SET: 1,
        CANCELED: 2,
        SENT: 3
    }

    // Test data
    const secret = 123;
    const hashlock = web3.utils.soliditySha3({type: 'uint', value: secret});
    const metadata = web3.utils.fromAscii(new String(13245678910)); // Random metadata in bytes32
    const bounty = web3.utils.toWei('1', 'ether');
    const vendorName = web3.utils.fromAscii("Test vendor");
    const productName = "Test product: Test version";
    const vulnerabilityData = "Vulnerability detailed description in text format";
    const vulnerabilityHash = web3.utils.soliditySha3({type: 'string', value: vulnerabilityData});
    const vulnerabilityLocation = "https://organization.org/report_1_test";
    const vulnerabilityId = web3.utils.soliditySha3({type: 'string', value: vulnerabilityLocation}); // An example of bytes32 for the vulnerabilityId

    describe("Constructor()", function() {

        it("Should execute the constructor with the correct params", async function() {

            // console.log(await Authority.new.estimateGas(interledgerAddress, accounts[8]));
            let vendor = await Vendor.new(vendorAddress, authorityAddress, {from: vendorAddress});

            const authority = await vendor.authority();

            assert.equal(authority, authorityAddress, "The address of authority should be " + authorityAddress);
        });
    });


    describe("registerProduct()", function() {

        let vendor;

        beforeEach(async function() {

            vendor = await Vendor.new(vendorAddress, authorityAddress, {from: vendorAddress});
        });

        it("Should store a new product record", async function() {

            const tx = await vendor.registerProduct(productName, {from: vendorAddress});

            const p_Id = tx["logs"][0].args._productId;
            const product = await vendor.getProductById(p_Id);
            const block_n = tx.receipt.blockNumber;
            const block = await web3.eth.getBlock(block_n);
         
            assert.equal(product.productName, productName, "Product name should be " + productName);
            assert.equal(product.registeredSince, block.timestamp, "Product registration timestamp should be " + block.timestamp);
            assert.equal(product.unregisteredSince, 0, "Product should not have un-registered date");
            assert.equal(product.registered, true, "Product should be registered");
        });

        it("Should NOT store a product record already present", async function() {

            await vendor.registerProduct(productName, {from: vendorAddress});

            await truffleAssert.fails(
                vendor.registerProduct(productName, {from: vendorAddress}),
                truffleAssert.ErrorType.REVERT,
                "This product already exist" // String of the revert
            );
        });

    });


    describe("unregisterProduct()", function() {

        let vendor;
        let productId;

        beforeEach(async function() {

            vendor = await Vendor.new(vendorAddress, authorityAddress, {from: vendorAddress});
            const tx = await vendor.registerProduct(productName, {from: vendorAddress});
            productId = tx["logs"][0].args._productId;
        });

        it("Should unregister a product previously registered", async function() {

            const tx = await vendor.unregisterProduct(productId, {from: vendorAddress});

            const product = await vendor.getProductById(productId);
            const block_n = tx.receipt.blockNumber;
            const block = await web3.eth.getBlock(block_n);
            
            truffleAssert.eventEmitted(tx, 'ProductUnregistered', (ev) => {                
                return (
                        ev._productId === productId
                        );
            }, 'ProductUnregistered event did not fire with correct parameters');

            assert.equal(product.unregisteredSince, block.timestamp, "Product un-registered date should be " + block.timestamp);
            assert.equal(product.registered, false, "Product should be unregistered");
        });

        it("Should NOT unregister a non-registered product", async function() {

            // Use other bytes32 data
            await truffleAssert.fails(
                vendor.unregisterProduct(vulnerabilityHash, {from: vendorAddress}),
                truffleAssert.ErrorType.REVERT,
                "This product doesn't exist" // String of the revert
            );
        });

    });

    describe("newVulnerability()", function() {

        let vendor;

        beforeEach(async function() {

            vendor = await Vendor.new(vendorAddress, authorityAddress, {from: vendorAddress});
        });

        it("Should store a new vulnerability record", async function() {

            // await vendor.newVulnerability(vulnerabilityId, researcherAddress, productId, vulnerabilityHash, hashlock);

            // const authority = await vendor.authority();

            // assert.equal(authority, authorityAddress, "The address of authority should be " + authorityAddress);
        });
    });

    
});