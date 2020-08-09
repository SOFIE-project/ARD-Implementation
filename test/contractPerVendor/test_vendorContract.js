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
    const funds = web3.utils.toWei('5', 'ether');
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

            // Use any other bytes32 data
            await truffleAssert.fails(
                vendor.unregisterProduct(vulnerabilityHash, {from: vendorAddress}),
                truffleAssert.ErrorType.REVERT,
                "This product doesn't exist" // String of the revert
            );
        });
    });


    describe("newVulnerability()", function() {

        let vendor;
        let productId;

        beforeEach(async function() {

            vendor = await Vendor.new(vendorAddress, authorityAddress, {from: vendorAddress});
            const tx = await vendor.registerProduct(productName, {from: vendorAddress});
            productId = tx["logs"][0].args._productId;
        });

        it("Should store a new vulnerability record", async function() {

            const tx = await vendor.newVulnerability(vulnerabilityId, researcherAddress, productId, vulnerabilityHash, hashlock, {from: authorityAddress});

            const info = await vendor.getVulnerabilityInfo(vulnerabilityId);
            const metadata = await vendor.getVulnerabilityMetadata(vulnerabilityId);
            const reward = await vendor.getVulnerabilityReward(vulnerabilityId);
            
            const block_n = tx.receipt.blockNumber;
            const block = await web3.eth.getBlock(block_n);

            assert.equal(info[0], researcherAddress, "The researcher address should be " + researcherAddress);
            assert.equal(info[1], STATUS.Pending, "The status should be " + STATUS.Pending + " (Pending)");
            assert.equal(info[2], hashlock, "The hashlock should be " + hashlock);
            assert.equal(info[3], 0, "The timelock should be " + 0);
            assert.equal(info[4], 0, "The secret should be " + 0);
            assert.equal(info[5], "", "The vulnerability location should be empty");

            assert.equal(metadata[0], block.timestamp, "The creation timestamp should be " + block.timestamp);
            assert.equal(metadata[1], productId, "The product id should be " + productId);
            assert.equal(metadata[2], vulnerabilityHash, "The vulnerability hash data should be " + vulnerabilityHash);

            assert.equal(reward[0], REWARDSTATE.NULL, "The reward state should be " + REWARDSTATE.NULL + " (NULL)");
            assert.equal(reward[1], 0, "The reward amount should be " + 0);
        });

        it("Should NOT store a new vulnerability record: product does not exist", async function() {

            await truffleAssert.fails(
                vendor.newVulnerability(vulnerabilityId, researcherAddress, hashlock, // wrong product id 
                    vulnerabilityHash, hashlock, {from: authorityAddress}),
                truffleAssert.ErrorType.REVERT,
                "Product Id not registered" // String of the revert
            );
        });

        it("Should NOT store a new vulnerability record: wrong caller", async function() {

            await truffleAssert.fails(
                vendor.newVulnerability(vulnerabilityId, researcherAddress, productId, vulnerabilityHash, hashlock, {from: researcherAddress}),
                truffleAssert.ErrorType.REVERT,
                "The caller is not the authority" // String of the revert
            );
        });          
    });


    describe("set functions", function() {

        let vendor;
        let productId;

        beforeEach(async function() {

            vendor = await Vendor.new(vendorAddress, authorityAddress, {from: vendorAddress});
            const tx = await vendor.registerProduct(productName, {from: vendorAddress});
            productId = tx["logs"][0].args._productId;
            await vendor.newVulnerability(vulnerabilityId, researcherAddress, productId, vulnerabilityHash, hashlock, {from: authorityAddress});
        });

        it("setState()", async function() {

            // Any state
            const tx = await vendor.setState(vulnerabilityId, STATUS.Patched, {from: authorityAddress});

            const info = await vendor.getVulnerabilityInfo(vulnerabilityId);
            assert.equal(info[1], STATUS.Patched, "The status should be " + STATUS.Patched + " (Patched)");
        });

        it("setRewardState()", async function() {

            // Any state
            await vendor.setRewardState(vulnerabilityId, REWARDSTATE.SENT, {from: authorityAddress});

            const reward = await vendor.getVulnerabilityReward(vulnerabilityId);
            assert.equal(reward[0], REWARDSTATE.SENT, "The reward state should be " + REWARDSTATE.SENT + " (SENT)");
        });

        it("setTimelock()", async function() {

            const timelock = 10000;
            await vendor.setTimelock(vulnerabilityId, timelock, {from: authorityAddress});

            const info = await vendor.getVulnerabilityInfo(vulnerabilityId);
            assert.equal(info[3], timelock, "The timelock should be " + timelock);
        });

        it("setSecret()", async function() {

            await vendor.setSecret(vulnerabilityId, secret, {from: authorityAddress});

            const info = await vendor.getVulnerabilityInfo(vulnerabilityId);
            assert.equal(info[4], secret, "The secret should be " + secret);
        });

        it("setLocation()", async function() {

            await vendor.setLocation(vulnerabilityId, vulnerabilityLocation, {from: authorityAddress});

            const info = await vendor.getVulnerabilityInfo(vulnerabilityId);
            assert.equal(info[5], vulnerabilityLocation, "The vulnerability location should be " + vulnerabilityLocation);
        });
    });

    
    describe("receive()", function() {

        let vendor;

        beforeEach(async function() {

            vendor = await Vendor.new(vendorAddress, authorityAddress, {from: vendorAddress});
        });

        it("Should receive ether from the vendor", async function() {

            await web3.eth.sendTransaction({
                from: vendorAddress,
                to: vendor.address,
                value: funds
            });

            const balance = await web3.eth.getBalance(vendor.address);

            assert.equal(balance, funds, "The contract should have " + funds +  " wei in its balance");
        });

        it("Should NOT receive ether from others than the vendor", async function() {

            await truffleAssert.fails(
                web3.eth.sendTransaction({
                    from: researcherAddress,
                    to: vendor.address,
                    value: funds
                }),
                truffleAssert.ErrorType.REVERT,
                "Ownable: caller is not the owner" // String of the revert
            );
        });
    });


    describe("acknowledge()", function() {

        let vendor;
        let productId;

        beforeEach(async function() {

            vendor = await Vendor.new(vendorAddress, authorityAddress, {from: vendorAddress});
            const tx = await vendor.registerProduct(productName, {from: vendorAddress});
            productId = tx["logs"][0].args._productId;
            await vendor.newVulnerability(vulnerabilityId, researcherAddress, productId, vulnerabilityHash, hashlock, {from: authorityAddress});
            await web3.eth.sendTransaction({
                from: vendorAddress,
                to: vendor.address,
                value: funds
            });
        });

        it("Should acknowledge the vulnerability", async function() {

            const timelock = (new Date()).getTime() + 100000;

            // Set the state in a valid state for the function
            await vendor.setState(vulnerabilityId, STATUS.Valid, {from: authorityAddress});
            await vendor.setTimelock(vulnerabilityId, timelock, {from: authorityAddress});

            await vendor.acknowledge(vulnerabilityId, bounty, {from: vendorAddress});

            const info = await vendor.getVulnerabilityInfo(vulnerabilityId);
            const reward = await vendor.getVulnerabilityReward(vulnerabilityId);
            const balanceOwner = await vendor.balanceOwner();

            assert.equal(info[1], STATUS.Acknowledged, "The state should be " + STATUS.Acknowledged + " (Acknowledged)");
            assert.equal(reward[0], REWARDSTATE.SET, "The reward state should be " + REWARDSTATE.SET + " (SET)");
            assert.equal(reward[1], bounty, "The reward amount should be " + bounty);
            assert.equal(balanceOwner, funds - bounty, "The leftover balance of the contract should be " + funds - bounty);
        });

        // it("Should NOT receive ether from others than the vendor", async function() {

        //     await truffleAssert.fails(
        //         web3.eth.sendTransaction({
        //             from: researcherAddress,
        //             to: vendor.address,
        //             value: funds
        //         }),
        //         truffleAssert.ErrorType.REVERT,
        //         "Ownable: caller is not the owner" // String of the revert
        //     );
        // });
    });   
    
    describe("method name", function() {

        beforeEach(async function() {

            // Execute before each it() statement, common initialization
        });

        it("Should repsect this condition ....", async function() {

            // Write code to end up in a known ok state (tested before)
            
            // Write command to test

            // Assert the state of the contract and check it is the expected one
        });

        it("Should NOT respect this condition ....", async function() {

            // Write code to end up in a known ok state (tested before)
            
            // Write command to test

            // Assert the state of the contract and check it is the expected one
        });
    });     

    
});