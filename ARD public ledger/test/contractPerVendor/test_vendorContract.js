const truffleAssert = require('truffle-assertions');
const Authority = artifacts.require("AuthorityContract");
const Vendor = artifacts.require("VendorContract");
const Factory = artifacts.require("VendorFactory");

contract("VendorContract", function(accounts) {

    const expertAddress = accounts[0];
    const vendorAddress = accounts[1];
    const authorityAddress = accounts[2];
    const interledgerAddress = accounts[3];
    
    const STATUS = {
        Pending: 0,
        Invalid: 1,
        Valid: 2,
        Duplicate: 3,
        Acknowledged: 4,
        // Patched: 5,
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
    // const vulnerabilityId = web3.utils.soliditySha3({type: 'string', value: vulnerabilityLocation}); // An example of bytes32 for the vulnerabilityId
    const vulnerabilityId = vulnerabilityHash;


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
            console.log("register product " + tx.receipt.gasUsed);

            const p_Id = tx["logs"][0].args.productId;
            const product = await vendor.getProductByUniqueId(p_Id);
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
                "This product is already registered" // String of the revert
            );
        });
    });


    describe("unregisterProduct()", function() {

        let vendor;
        let productId;

        beforeEach(async function() {

            vendor = await Vendor.new(vendorAddress, authorityAddress, {from: vendorAddress});
            const tx = await vendor.registerProduct(productName, {from: vendorAddress});
            productId = tx["logs"][0].args.productId;
        });

        it("Should unregister a product previously registered", async function() {

            const tx = await vendor.unregisterProduct(productId, {from: vendorAddress});

            const product = await vendor.getProductByUniqueId(productId);
            const block_n = tx.receipt.blockNumber;
            const block = await web3.eth.getBlock(block_n);
            
            truffleAssert.eventEmitted(tx, 'ProductUnregistered', (ev) => {                
                return (
                        ev.productId === productId
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
                "A product must be registered to un-register it" // String of the revert
            );
        });
    });


    describe("newVulnerability()", function() {

        let vendor;
        let productId;

        beforeEach(async function() {

            vendor = await Vendor.new(vendorAddress, authorityAddress, {from: vendorAddress});
            const tx = await vendor.registerProduct(productName, {from: vendorAddress});
            productId = tx["logs"][0].args.productId;
        });

        it("Should store a new vulnerability record", async function() {

            const tx = await vendor.newVulnerability(vulnerabilityId, expertAddress, productId, hashlock, {from: authorityAddress});

            const info = await vendor.getVulnerabilityInfo(vulnerabilityId);
            const metadata = await vendor.getVulnerabilityMetadata(vulnerabilityId);
            const reward = await vendor.getVulnerabilityReward(vulnerabilityId);
            
            const block_n = tx.receipt.blockNumber;
            const block = await web3.eth.getBlock(block_n);

            assert.equal(info[0], expertAddress, "The expert address should be " + expertAddress);
            assert.equal(info[1], STATUS.Pending, "The status should be " + STATUS.Pending + " (Pending)");
            assert.equal(info[2], hashlock, "The hashlock should be " + hashlock);
            assert.equal(info[3], 0, "The timelock should be " + 0);
            assert.equal(info[4], 0, "The ack timelock should be " + 0);
            assert.equal(info[5], 0, "The secret should be " + 0);
            assert.equal(info[6], "", "The vulnerability location should be empty");

            assert.equal(metadata[0], block.timestamp, "The creation timestamp should be " + block.timestamp);
            assert.equal(metadata[1], productId, "The product id should be " + productId);

            assert.equal(reward[0], REWARDSTATE.NULL, "The reward state should be " + REWARDSTATE.NULL + " (NULL)");
            assert.equal(reward[1], 0, "The reward amount should be " + 0);
        });

        it("Should NOT store a new vulnerability record: product does not exist", async function() {

            await truffleAssert.fails(
                vendor.newVulnerability(vulnerabilityId, expertAddress, hashlock, // wrong product id 
                    hashlock, {from: authorityAddress}),
                truffleAssert.ErrorType.REVERT,
                "Product with input ID is not registered" // String of the revert
            );
        });

        it("Should NOT store a new vulnerability record: wrong caller", async function() {

            await truffleAssert.fails(
                vendor.newVulnerability(vulnerabilityId, expertAddress, productId, hashlock, {from: expertAddress}),
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
            productId = tx["logs"][0].args.productId;
            await vendor.newVulnerability(vulnerabilityId, expertAddress, productId, hashlock, {from: authorityAddress});
        });

        it("setState()", async function() {

            // Any state
            const tx = await vendor.setState(vulnerabilityId, STATUS.Acknowledged, {from: authorityAddress});

            const info = await vendor.getVulnerabilityInfo(vulnerabilityId);
            assert.equal(info[1], STATUS.Acknowledged, "The status should be " + STATUS.Acknowledged + " (Acknowledged)");
        });

        it("setRewardState()", async function() {

            // Any state
            await vendor.setRewardState(vulnerabilityId, REWARDSTATE.SENT, {from: authorityAddress});

            const reward = await vendor.getVulnerabilityReward(vulnerabilityId);
            assert.equal(reward[0], REWARDSTATE.SENT, "The reward state should be " + REWARDSTATE.SENT + " (SENT)");
        });

        it("setTimelock()", async function() {

            // Solidity block.timestamp is *in seconds*. Need to round them down to integer
            const timelock = Math.round(new Date() / 1000) + 100000;
            const ackTimelock = Math.round(new Date() / 1000) + 1000;

            await vendor.setTimelock(vulnerabilityId, ackTimelock, timelock, {from: authorityAddress});

            const info = await vendor.getVulnerabilityInfo(vulnerabilityId);
            assert.equal(info[3].toString(), ""+timelock, "The timelock should be " + timelock);
            assert.equal(info[4].toString(), ""+ ackTimelock, "The ack timelock should be " + ackTimelock);
        });

        it("setSecret()", async function() {

            await vendor.setSecret(vulnerabilityId, secret, {from: authorityAddress});

            const info = await vendor.getVulnerabilityInfo(vulnerabilityId);
            assert.equal(info[5], secret, "The secret should be " + secret);
        });

        it("setLocation()", async function() {

            await vendor.setLocation(vulnerabilityId, vulnerabilityLocation, {from: authorityAddress});

            const info = await vendor.getVulnerabilityInfo(vulnerabilityId);
            assert.equal(info[6], vulnerabilityLocation, "The vulnerability location should be " + vulnerabilityLocation);
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
                    from: expertAddress,
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
            productId = tx["logs"][0].args.productId;
            await vendor.newVulnerability(vulnerabilityId, expertAddress, productId, hashlock, {from: authorityAddress});
            await web3.eth.sendTransaction({
                from: vendorAddress,
                to: vendor.address,
                value: funds
            });
        });

        it("Should acknowledge the vulnerability", async function() {

            const timelock = Math.round(new Date() / 1000) + 100000;
            const ackTimelock = Math.round(new Date() / 1000) + 10000;

            // Set the state in a valid state for the function
            await vendor.setState(vulnerabilityId, STATUS.Valid, {from: authorityAddress});
            await vendor.setTimelock(vulnerabilityId, ackTimelock, timelock, {from: authorityAddress});

            tx = await vendor.acknowledge(vulnerabilityId, bounty, {from: vendorAddress});
            console.log("Acknwoledge " + tx.receipt.gasUsed);

            const info = await vendor.getVulnerabilityInfo(vulnerabilityId);
            const reward = await vendor.getVulnerabilityReward(vulnerabilityId);
            const balanceOwner = await vendor.balanceOwner();

            assert.equal(info[1], STATUS.Acknowledged, "The state should be " + STATUS.Acknowledged + " (Acknowledged)");
            assert.equal(reward[0], REWARDSTATE.SET, "The reward state should be " + REWARDSTATE.SET + " (SET)");
            assert.equal(reward[1], bounty, "The reward amount should be " + bounty);
            assert.equal(balanceOwner, funds - bounty, "The leftover balance of the contract should be " + funds - bounty);
        });

        it("Should NOT acknowledge the vulnerability: expired ack timelock", async function() {

            const timelock = Math.round(new Date() / 1000) + 100000;
            const ackTimelock = Math.round(new Date() / 1000) - 10000;

            // Set the state in a valid state for the function
            await vendor.setState(vulnerabilityId, STATUS.Valid, {from: authorityAddress});
            await vendor.setTimelock(vulnerabilityId, ackTimelock, timelock, {from: authorityAddress});

            await truffleAssert.fails(
                vendor.acknowledge(vulnerabilityId, bounty, {from: vendorAddress}),
                truffleAssert.ErrorType.REVERT,
                "The ack timelock has expired" // String of the revert
            );
        });

        it("Should NOT acknowledge the vulnerability: vulnerability not Valid", async function() {

            const timelock = Math.round(new Date() / 1000) + 100000;
            const ackTimelock = Math.round(new Date() / 1000) + 10000;

            // Set the state in a valid state for the function
            await vendor.setState(vulnerabilityId, STATUS.Invalid, {from: authorityAddress});
            await vendor.setTimelock(vulnerabilityId, ackTimelock, timelock, {from: authorityAddress});

            await truffleAssert.fails(
                vendor.acknowledge(vulnerabilityId, bounty, {from: vendorAddress}),
                truffleAssert.ErrorType.REVERT,
                "State is not Valid" // String of the revert
            );
        });

        it("Should NOT acknowledge the vulnerability: balance not enough to fund the bounty", async function() {

            const timelock = Math.round(new Date() / 1000) + 100000;
            const ackTimelock = Math.round(new Date() / 1000) + 10000;

            // Set the state in a valid state for the function
            await vendor.setState(vulnerabilityId, STATUS.Valid, {from: authorityAddress});
            await vendor.setTimelock(vulnerabilityId, ackTimelock, timelock, {from: authorityAddress});

            await truffleAssert.fails(
                vendor.acknowledge(vulnerabilityId, bounty + web3.utils.toWei('10', 'ether'), {from: vendorAddress}),
                truffleAssert.ErrorType.REVERT,
                "Available balance not enough to fund the bounty" // String of the revert
            );
        });

    });   


    // describe("patch()", function() {

    //     let vendor;
    //     let productId;

    //     beforeEach(async function() {

    //         const timelock = Math.round(new Date() / 1000) + 100000;
    //         const ackTimelock = Math.round(new Date() / 1000) + 10000;

    //         vendor = await Vendor.new(vendorAddress, authorityAddress, {from: vendorAddress});
    //         const tx = await vendor.registerProduct(productName, {from: vendorAddress});
    //         productId = tx["logs"][0].args.productId;
    //         await vendor.newVulnerability(vulnerabilityId, expertAddress, productId, vulnerabilityHash, hashlock, {from: authorityAddress});
    //         await web3.eth.sendTransaction({
    //             from: vendorAddress,
    //             to: vendor.address,
    //             value: funds
    //         });

    //         await vendor.setState(vulnerabilityId, STATUS.Valid, {from: authorityAddress});
    //         await vendor.setTimelock(vulnerabilityId, ackTimelock, timelock, {from: authorityAddress});
    //     });

    //     it("Should patch the vulnerability", async function() {

    //         await vendor.acknowledge(vulnerabilityId, bounty, {from: vendorAddress});

    //         await vendor.patch(vulnerabilityId, {from: vendorAddress});

    //         const info = await vendor.getVulnerabilityInfo(vulnerabilityId);
    //         assert.equal(info[1], STATUS.Patched, "The state should be " + STATUS.PAtched + " (Patched)");
    //     });

    //     it("Should NOT patch the vulnerability: not acknowledged", async function() {

    //         await truffleAssert.fails(
    //             vendor.patch(vulnerabilityId, {from: vendorAddress}),
    //             truffleAssert.ErrorType.REVERT,
    //             "The vulnerability has not been acknowledged" // String of the revert
    //         );
    //     });
    // });  

    
    describe("withdraw()", function() {

        let vendor;
        let productId;

        beforeEach(async function() {

            vendor = await Vendor.new(vendorAddress, authorityAddress, {from: vendorAddress});
            const tx = await vendor.registerProduct(productName, {from: vendorAddress});
            productId = tx["logs"][0].args.productId;
            await vendor.newVulnerability(vulnerabilityId, expertAddress, productId, hashlock, {from: authorityAddress});
            await web3.eth.sendTransaction({
                from: vendorAddress,
                to: vendor.address,
                value: funds
            });
        });

        it("Should withdraw some funds from the contract: no bounties", async function() {

            // The contract is funded with 5 ETH

            await vendor.withdraw(bounty, {from: vendorAddress}); // 1 ETH

            const balance = await web3.eth.getBalance(vendor.address);
            const balanceOwner = await vendor.balanceOwner();

            assert.equal(balance, (funds - bounty), "The contract should have " + (funds - bounty) +  " wei in its balance");
            assert.equal(balanceOwner, (funds - bounty), "The balance owner should be " + (funds - bounty) +  " wei (equal to balance)");
        });

        it("Should withdraw some funds from the contract: a bounty set", async function() {

            // The contract is funded with 5 ETH

            // Lock some funds in a bounty with acknwoledge: 1 ETH
            const timelock = Math.round(new Date() / 1000) + 100000;
            const ackTimelock = Math.round(new Date() / 1000) + 10000;

            await vendor.setState(vulnerabilityId, STATUS.Valid, {from: authorityAddress});
            await vendor.setTimelock(vulnerabilityId, ackTimelock, timelock, {from: authorityAddress});
            await vendor.acknowledge(vulnerabilityId, bounty, {from: vendorAddress});

            await vendor.withdraw(bounty, {from: vendorAddress}); // 1 ETH

            const balance = await web3.eth.getBalance(vendor.address);
            const balanceOwner = await vendor.balanceOwner();

            assert.equal(balance, (funds - bounty), "The contract should have " + (funds - bounty) +  " wei in its balance");
            assert.equal(balanceOwner, (funds - 2*bounty), "The balance owner should be " + (funds - bounty) +  " wei");
        });

        it("Should NOT withdraw funds from the contract if they exceed the available amount", async function() {

            // The contract is funded with 5 ETH

            // Lock some funds in a bounty with acknwoledge: 1 ETH
            const timelock = Math.round(new Date() / 1000) + 100000;
            const ackTimelock = Math.round(new Date() / 1000) + 10000;

            await vendor.setState(vulnerabilityId, STATUS.Valid, {from: authorityAddress});
            await vendor.setTimelock(vulnerabilityId, ackTimelock, timelock, {from: authorityAddress});
            await vendor.acknowledge(vulnerabilityId, bounty, {from: vendorAddress});

            // Withdraw 5 ETH (4 ETH available)
            await truffleAssert.fails(
                vendor.withdraw(funds, {from: vendorAddress}),
                truffleAssert.ErrorType.REVERT,
                "Funds not available" // String of the revert
            );
        });
    });  


    describe("payBounty()", function() {

        let vendor;
        let productId;

        beforeEach(async function() {

            const timelock = Math.round(new Date() / 1000) + 100000;
            const ackTimelock = Math.round(new Date() / 1000) + 10000;

            vendor = await Vendor.new(vendorAddress, authorityAddress, {from: vendorAddress});
            const tx = await vendor.registerProduct(productName, {from: vendorAddress});
            productId = tx["logs"][0].args.productId;
            await vendor.newVulnerability(vulnerabilityId, expertAddress, productId, hashlock, {from: authorityAddress});
            await web3.eth.sendTransaction({
                from: vendorAddress,
                to: vendor.address,
                value: funds
            });

            await vendor.setState(vulnerabilityId, STATUS.Valid, {from: authorityAddress});
            await vendor.setTimelock(vulnerabilityId, ackTimelock, timelock, {from: authorityAddress});

        });

        it("Should pay the bounty to the expert", async function() {

            // Bounty: 1 ETH
            await vendor.acknowledge(vulnerabilityId, bounty, {from: vendorAddress});

            // The contract is funded with 5 ETH
            await vendor.payBounty(vulnerabilityId, {from:authorityAddress});

            const balance = await web3.eth.getBalance(vendor.address);
            const balanceOwner = await vendor.balanceOwner();
            const reward = await vendor.getVulnerabilityReward(vulnerabilityId);

            assert.equal(balance, (funds - bounty), "The contract should have " + (funds - bounty) +  " wei in its balance");
            assert.equal(balanceOwner, (funds - bounty), "The balance owner should be " + (funds - bounty) +  " wei (equal to balance)");
            assert.equal(reward[0], REWARDSTATE.SENT, "The reward state should be " + REWARDSTATE.SENT + " (SENT)");
        });
    });  


    describe("cancelBounty()", function() {

        let vendor;
        let productId;

        beforeEach(async function() {

            const timelock = Math.round(new Date() / 1000) + 100000;
            const ackTimelock = Math.round(new Date() / 1000) + 10000;

            vendor = await Vendor.new(vendorAddress, authorityAddress, {from: vendorAddress});
            const tx = await vendor.registerProduct(productName, {from: vendorAddress});
            productId = tx["logs"][0].args.productId;
            await vendor.newVulnerability(vulnerabilityId, expertAddress, productId, hashlock, {from: authorityAddress});
            await web3.eth.sendTransaction({
                from: vendorAddress,
                to: vendor.address,
                value: funds
            });

            await vendor.setState(vulnerabilityId, STATUS.Valid, {from: authorityAddress});
            await vendor.setTimelock(vulnerabilityId, ackTimelock, timelock, {from: authorityAddress});

        });

        it("Should cancel the bounty to the expert", async function() {

            const motivation = "The expert disclosed the vulnerability in www.site.com";

            // Bounty: 1 ETH
            await vendor.acknowledge(vulnerabilityId, bounty, {from: vendorAddress});

            // The contract is funded with 5 ETH
            await vendor.cancelBounty(vulnerabilityId, motivation, {from:authorityAddress});

            const balance = await web3.eth.getBalance(vendor.address);
            const balanceOwner = await vendor.balanceOwner();
            const reward = await vendor.getVulnerabilityReward(vulnerabilityId);

            assert.equal(balance, funds, "The contract should have " + funds +  " wei in its balance");
            assert.equal(balanceOwner, funds, "The balance owner should be " + funds +  " wei (equal to balance)");
            assert.equal(reward[0], REWARDSTATE.CANCELED, "The reward state should be " + REWARDSTATE.CANCELED + " (CANCELED)");
            assert.equal(reward[1], 0, "The reward amount should be 0");
        });
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