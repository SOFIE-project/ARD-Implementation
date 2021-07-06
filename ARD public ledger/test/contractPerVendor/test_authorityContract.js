const truffleAssert = require('truffle-assertions');
const Authority = artifacts.require("AuthorityContract");
const Vendor = artifacts.require("VendorContract");
const Factory = artifacts.require("VendorFactory");

contract("AuthorityContract", function(accounts) {

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
        Disclosable: 5,
        Disclosed: 6
    }

    const REWARDSTATE = {
        NULL: 0,
        SET: 1,
        CANCELED: 2,
        SENT: 3
    }

    const DECISION = {
        Approved: 0,
        Invalid: 1,
        Duplicate: 2
    }

    const secret = 123;
    const nonce = 1234;
    const hashlock = web3.utils.soliditySha3({type: 'uint', value: secret});
    const metadata = web3.utils.fromAscii(new String(13245678910)); // Random metadata in bytes32
    const bounty = web3.utils.toWei('1', 'ether');
    const funds = web3.utils.toWei('5', 'ether');
    const vendorName = web3.utils.fromAscii("Test vendor");
    const productName = web3.utils.fromAscii("Test product");
    const productVersion = web3.utils.fromAscii("Test version");
    const vulnerabilityData = "Vulnerability detailed description in text format";
    const vulnerabilityHash = web3.utils.soliditySha3({type: 'string', value: vulnerabilityData});
    const vulnerabilityId = vulnerabilityHash;
    const vulnerabilityLocation = "https://organization.org/report_1_test";

    function sleep(ms) {
        return new Promise((resolve) => {
            setTimeout(resolve, ms);
        });
    } 

    describe("Constructor()", function() {

        let factory;
        
        beforeEach(async function() {
            factory = await Factory.new({from: authorityAddress});
        });

        it("Should execute the constructor with the correct params", async function() {

            console.log(await Authority.new.estimateGas(interledgerAddress, accounts[8]));
            let authority = await Authority.new(interledgerAddress, factory.address, {from: authorityAddress});
            await factory.transferOwnership(authority.address, {from: authorityAddress});

            const il = await authority.interledger();
            const f = await authority.factory();

            assert.equal(il, interledgerAddress, "The address of interledger should be " + interledgerAddress);
            assert.equal(f, factory.address, "The address of the factory should be " + factory.address);
        });
    });

    describe("registerVendor()", function() {

        let factory;
        let authority;

        beforeEach(async function() {
            factory = await Factory.new({from: authorityAddress});
            authority = await Authority.new(interledgerAddress, factory.address, {from: authorityAddress});
            await factory.transferOwnership(authority.address, {from: authorityAddress});
        });

        it("Should register a vendor", async function() {

            let tx = await authority.registerVendor(vendorAddress, {from: authorityAddress});
            console.log("Register vendor " + tx.receipt.gasUsed);

            const vendorRecord = await authority.vendorRecords(vendorAddress);

            const block_n = tx.receipt.blockNumber;
            const block = await web3.eth.getBlock(block_n);

            assert.equal(vendorRecord.registeredSince, block.timestamp, "The vendor should be registered since timestamp " + block.timestamp);
            assert.equal(vendorRecord.registered, true, "The vendor should be registered");
            assert.equal(vendorRecord.unregisteredSince, 0, "The vendor should NOT be un-registered");
        });
    
    
        it("Should NOT register the same vendor twice", async function() {

            await authority.registerVendor(vendorAddress, {from: authorityAddress});

            await truffleAssert.fails(
                authority.registerVendor(vendorAddress, {from: authorityAddress}),
                truffleAssert.ErrorType.REVERT,
                "This vendor already exist" // String of the revert
            );
        });
    });


    describe("unregisterVendor()", function() {

        let factory;
        let authority;

        beforeEach(async function() {
            factory = await Factory.new({from: authorityAddress});
            authority = await Authority.new(interledgerAddress, factory.address, {from: authorityAddress});
            await factory.transferOwnership(authority.address, {from: authorityAddress});
            await authority.registerVendor(vendorAddress, {from: authorityAddress});
        });

        it("Should unregister a vendor", async function() {
    
            let tx = await authority.unregisterVendor(vendorAddress, {from: authorityAddress});
            
            const vendorRecord = await authority.vendorRecords(vendorAddress);

            const block_n = tx.receipt.blockNumber;
            const block = await web3.eth.getBlock(block_n);

            assert.equal(vendorRecord.unregisteredSince, block.timestamp, "The vendor should be un-registered since timestamp " + block.timestamp);
            assert.equal(vendorRecord.registered, false, "The vendor should be un-registered");
        });
    
    
        it("Should NOT unregister an un-registered vendor", async function() {

            await authority.unregisterVendor(vendorAddress, {from: authorityAddress});

            await truffleAssert.fails(
                authority.unregisterVendor(vendorAddress, {from: authorityAddress}),
                truffleAssert.ErrorType.REVERT,
                "This vendor is already unregistered" // String of the revert
            );
        });
    });


    describe("registerVulnerability()", function() {

        let factory;
        let authority;
        let vendor;
        let productId;

        beforeEach(async function() {
            factory = await Factory.new({from: authorityAddress});
            authority = await Authority.new(interledgerAddress, factory.address, {from: authorityAddress});
            await factory.transferOwnership(authority.address, {from: authorityAddress});
            let tx = await authority.registerVendor(vendorAddress, {from: authorityAddress});
            vendor = await Vendor.at(tx["logs"][2].args.vendorContract); // vendorRegistered is the 3rd event in registerVendor()
            tx = await vendor.registerProduct(productName, {from: vendorAddress});
            productId = tx["logs"][0].args.productId;
        });

        it("Should register a new vulnerability", async function() {
    
            let tx = await authority.registerVulnerability(vendorAddress, hashlock, productId, vulnerabilityHash, {from: expertAddress});
            console.log("Register vulnerability " + tx.receipt.gasUsed);
            
            let event = tx["logs"][0].args;
            let v = await authority.VendorVulnerabilities(event.vulnerabilityId);
            let info = await vendor.getVulnerabilityInfo(event.vulnerabilityId);

            // Recall vulnerabilityId == vulnerabilityHash
            assert.equal(v, vendorAddress, "The id "+event.vulnerabilityId+" should be mapped to " + vendorAddress)
            assert.equal(event.expert, expertAddress, "The sender should be the expert: " + expertAddress);
            assert.equal(event.vendor, vendorAddress, "The target vendor should be " + vendorAddress);
            assert.equal(event.hashlock, hashlock, "The used hashlock should be " + hashlock);
            assert.equal(event.vulnerabilityId, vulnerabilityId, "The hash of the vulnerability description should be" + vulnerabilityId);
            assert.equal(info[0], expertAddress, "The vendor contract should store the vulnerability, and have expert field as" + expertAddress);
        });   
    });


    describe("approve()", function() {

        let factory;
        let authority;
        let vendor;
        let productId;

        // Solidity block.timestamp is *in seconds*. Need to round them down to integer
        // const timelock = Math.round(new Date() / 1000) + 100000;
        // const ackTimelock = Math.round(new Date() / 1000) + 1000;
        
        beforeEach(async function() {
            factory = await Factory.new({from: authorityAddress});
            authority = await Authority.new(interledgerAddress, factory.address, {from: authorityAddress});
            await factory.transferOwnership(authority.address, {from: authorityAddress});
            let tx = await authority.registerVendor(vendorAddress, {from: authorityAddress});
            vendor = await Vendor.at(tx["logs"][2].args.vendorContract); // vendorRegistered is the 3rd event in registerVendor()
            tx = await vendor.registerProduct(productName, {from: vendorAddress});
            productId = tx["logs"][0].args.productId;
            tx = await authority.registerVulnerability(vendorAddress, hashlock, productId, vulnerabilityHash, {from: expertAddress});
        });

        it("Should approve a vulnerability", async function() {

            let code = 1; // Approve code
            const motivation = "Vulnerability approved";
            const data = web3.eth.abi.encodeParameters(['bytes32', 'uint', 'string'], [vulnerabilityId, code, "0x0"]);
            let tx = await authority.interledgerReceive(vulnerabilityId, data, {from: interledgerAddress});
            console.log("Interledger receive: approve " + tx.receipt.gasUsed);

            truffleAssert.eventEmitted(tx, 'LogVulnerabilityApproval', (ev) => {                
                return (
                        ev.vulnerabilityId == vulnerabilityId,
                        ev.state == STATUS.Valid
                        );
            }, 'LogVulnerabilityApproval event did not fire with correct parameters');
        });
    
        it("Should not approve a vulnerability: invalid", async function() {

            const motivation = "Not relevant imporntance";
            let tx = await authority.reject(vulnerabilityId, true, {from: authorityAddress});

            truffleAssert.eventEmitted(tx, 'LogVulnerabilityApproval', (ev) => {                
                return (
                        ev.vulnerabilityId == vulnerabilityId,
                        ev.timelock == 0,
                        ev.actTimelock == 0,
                        ev.state == STATUS.Invalid
                        );
            }, 'LogVulnerabilityApproval event did not fire with correct parameters');
        });

        it("Should not approve a vulnerability: duplicate", async function() {

            const motivation = "Already submitted";
            let tx = await authority.reject(vulnerabilityId, false, {from: authorityAddress});

            truffleAssert.eventEmitted(tx, 'LogVulnerabilityApproval', (ev) => {                
                return (
                        ev.vulnerabilityId == vulnerabilityId,
                        ev.timelock == 0,
                        ev.actTimelock == 0,
                        ev.state == STATUS.Duplicate
                        );
            }, 'LogVulnerabilityApproval event did not fire with correct parameters');
        });
    });    


    describe("publishSecret()", function() {

        let factory;
        let authority;
        let vendor;
        let productId;
        
        beforeEach(async function() {

            factory = await Factory.new({from: authorityAddress});
            authority = await Authority.new(interledgerAddress, factory.address, {from: authorityAddress});
            await factory.transferOwnership(authority.address, {from: authorityAddress});
            let tx = await authority.registerVendor(vendorAddress, {from: authorityAddress});
            vendor = await Vendor.at(tx["logs"][2].args.vendorContract); // vendorRegistered is the 3rd event in registerVendor()
            tx = await vendor.registerProduct(productName, {from: vendorAddress});
            productId = tx["logs"][0].args.productId;
            tx = await authority.registerVulnerability(vendorAddress, hashlock, productId, vulnerabilityHash, {from: expertAddress});
            const code = 1;
            const data = web3.eth.abi.encodeParameters(['bytes32', 'uint', 'string'], [vulnerabilityId, code, "null"]);
            await authority.interledgerReceive(vulnerabilityId, data, {from: interledgerAddress});
            await web3.eth.sendTransaction({
                from: vendorAddress,
                to: vendor.address,
                value: funds
            });
        });

        it("Should publish the secret: Patched by vendor", async function() {

            await vendor.acknowledge(vulnerabilityId, bounty, {from: vendorAddress});
            const expertBalance_before = web3.utils.fromWei(await web3.eth.getBalance(expertAddress), 'ether');

            let tx = await authority.publishSecret(vulnerabilityId, secret, {from: vendorAddress});
            console.log("Publish secret from vendor " + tx.receipt.gasUsed);

            const info = await vendor.getVulnerabilityInfo(vulnerabilityId);
            const expertBalance_after = web3.utils.fromWei(await web3.eth.getBalance(expertAddress), 'ether');

            assert.equal(info[1], STATUS.Disclosable, "The status should be " + STATUS.Disclosable + " (Disclosable)");
            assert.isAtLeast(parseInt(expertBalance_after), parseInt(expertBalance_before), "The expert should gain the reward and thus have higher balance than before");

            const data = web3.eth.abi.encodeParameters(['bytes32', 'uint256'], [vulnerabilityId, secret]);
            truffleAssert.eventEmitted(tx, 'InterledgerEventSending', (ev) => {                
                return (
                        ev.id == vulnerabilityId,
                        ev.data == data
                        );
            }, 'InterledgerEventSending event did not fire with correct parameters');

            truffleAssert.eventEmitted(tx, 'LogVulnerabilityPatched', (ev) => {                
                return (
                        ev.id == vulnerabilityId,
                        ev.patched == true,
                        ev.timelock_expired == false
                        );
            }, 'LogVulnerabilityPatched event did not fire with correct parameters');
        });

        it("Should NOT publish the secret: Not Acknowledged by vendor", async function() {

            await truffleAssert.fails(
                authority.publishSecret(vulnerabilityId, secret, {from: vendorAddress}),
                truffleAssert.ErrorType.REVERT,
                "The vulnerability can be patched only if previously Acknowledged" // String of the revert
            );
        });

        it("Should publish the secret: Patched by vendor, after timelock", async function() {

            await vendor.acknowledge(vulnerabilityId, bounty, {from: vendorAddress});
            const expertBalance_before = web3.utils.fromWei(await web3.eth.getBalance(expertAddress), 'ether');

            // Set timelock to past to avoid waiting, otherwise set to 4 weeks in the smart contract
            const v = await authority.vendorRecords(vendorAddress); // get an object with Vendor's data
            const v_contract = await Vendor.at(v[0]);
            await v_contract.debug_setTimelock(vulnerabilityId, 1, 2);

            
            let tx = await authority.publishSecret(vulnerabilityId, secret, {from: vendorAddress});

            const info = await vendor.getVulnerabilityInfo(vulnerabilityId);
            const expertBalance_after = web3.utils.fromWei(await web3.eth.getBalance(expertAddress), 'ether');

            assert.equal(info[1], STATUS.Disclosable, "The status should be " + STATUS.Disclosable + " (Disclosable)");
            assert.isAtLeast(parseInt(expertBalance_after), parseInt(expertBalance_before), "The expert should gain the reward and thus have higher balance than before");

            const data = web3.eth.abi.encodeParameters(['bool', 'uint256'], [true, secret]);

            truffleAssert.eventEmitted(tx, 'LogVulnerabilityPatched', (ev) => {                
                return (
                        ev.id == vulnerabilityId,
                        ev.patched == true,
                        ev.timelock_expired == true
                        );
            }, 'LogVulnerabilityPatched event did not fire with correct parameters');
        });

        it("Should publish the secret: ackTimelock expired", async function() {

            // wait for the ack timelock to expire
            const expertBalance_before = web3.utils.fromWei(await web3.eth.getBalance(expertAddress), 'ether');

            // Set timelock to past to avoid waiting, otherwise set to 1 week in the smart contract
            const v = await authority.vendorRecords(vendorAddress); // get an object with Vendor's data
            const v_contract = await Vendor.at(v[0]);
            await v_contract.debug_setTimelock(vulnerabilityId, 1, 2);
            
            
            let tx = await authority.publishSecret(vulnerabilityId, secret, {from: expertAddress});
            console.log("Publish secret from expert " + tx.receipt.gasUsed);

            const info = await vendor.getVulnerabilityInfo(vulnerabilityId);
            const expertBalance_after = web3.utils.fromWei(await web3.eth.getBalance(expertAddress), 'ether');

            assert.equal(info[1], STATUS.Disclosable, "The status should be " + STATUS.Disclosable + " (Disclosable)");
            assert.isAtLeast(parseInt(expertBalance_before), parseInt(expertBalance_after), "The expert should have lost ETH due to gas");

            truffleAssert.eventEmitted(tx, 'LogVulnerabilityPatched', (ev) => {                
                return (
                        ev.id == vulnerabilityId,
                        ev.patched == false,
                        ev.timelock_expired == true
                        );
            }, 'LogVulnerabilityPatched event did not fire with correct parameters');            
        });
    
        it("Should publish the secret: timelock expired", async function() {

            await vendor.acknowledge(vulnerabilityId, bounty, {from: vendorAddress});

            // wait for the ack timelock to expire
            const expertBalance_before = web3.utils.fromWei(await web3.eth.getBalance(expertAddress), 'ether');

            // Set timelock to past to avoid waiting, otherwise set to 4 weeks in the smart contract
            const v = await authority.vendorRecords(vendorAddress); // get an object with Vendor's data
            const v_contract = await Vendor.at(v[0]);
            await v_contract.debug_setTimelock(vulnerabilityId, 1, 2);
            
    
            let tx = await authority.publishSecret(vulnerabilityId, secret, {from: expertAddress});
            console.log("Publish secret from expert, with bounty transfer " + tx.receipt.gasUsed);

            const info = await vendor.getVulnerabilityInfo(vulnerabilityId);
            const expertBalance_after = web3.utils.fromWei(await web3.eth.getBalance(expertAddress), 'ether');

            assert.equal(info[1], STATUS.Disclosable, "The status should be " + STATUS.Disclosable + " (Disclosable)");
            assert.isAtLeast(parseInt(expertBalance_after), parseInt(expertBalance_before), "The expert should gain the reward and thus have higher balance than before");

            truffleAssert.eventEmitted(tx, 'LogVulnerabilityPatched', (ev) => {                
                return (
                        ev.id == vulnerabilityId,
                        ev.patched == false,
                        ev.timelock_expired == true
                        );
            }, 'LogVulnerabilityPatched event did not fire with correct parameters');
        });

        it("Should NOT publish the secret: ack timelock not expired", async function() {
    
            await vendor.acknowledge(vulnerabilityId, bounty, {from: vendorAddress});

            await truffleAssert.fails(
                authority.publishSecret(vulnerabilityId, secret, {from: expertAddress}),
                truffleAssert.ErrorType.REVERT,
                "The secret cannot be disclosed before the timelock by other than the Vendor" // String of the revert
            );
        });

        it("Should NOT publish the secret: secret does not match the hashlock", async function() {
    
            await vendor.acknowledge(vulnerabilityId, bounty, {from: vendorAddress});

            // await sleep(10000)

            await truffleAssert.fails(
                authority.publishSecret(vulnerabilityId, 12, {from: expertAddress}),
                truffleAssert.ErrorType.REVERT,
                "Hashed secret and hashlock do not match" // String of the revert
            );
        });
    });    



    describe("interledgerReceive() (disclose)", function() {

        let factory;
        let authority;
        let vendor;
        let productId;

        // Solidity block.timestamp is *in seconds*. Need to round them down to integer
        const timelock = Math.round(new Date() / 1000) + 100000;
        const ackTimelock = Math.round(new Date() / 1000) + 1000;
        
        beforeEach(async function() {
            factory = await Factory.new({from: authorityAddress});
            authority = await Authority.new(interledgerAddress, factory.address, {from: authorityAddress});
            await factory.transferOwnership(authority.address, {from: authorityAddress});
            let tx = await authority.registerVendor(vendorAddress, {from: authorityAddress});
            vendor = await Vendor.at(tx["logs"][2].args.vendorContract); // vendorRegistered is the 3rd event in registerVendor()
            tx = await vendor.registerProduct(productName, {from: vendorAddress});
            productId = tx["logs"][0].args.productId;
            tx = await authority.registerVulnerability(vendorAddress, hashlock, productId, vulnerabilityHash, {from: expertAddress});
            // vulnerabilityId = tx["logs"][0].args.vulnerabilityId;
            const code = 1; // Approve
            const data = web3.eth.abi.encodeParameters(['bytes32', 'uint', 'string'], [vulnerabilityId, code, "null"]);
            await authority.interledgerReceive(vulnerabilityId, data, {from: interledgerAddress});
            await web3.eth.sendTransaction({
                from: vendorAddress,
                to: vendor.address,
                value: funds
            });            
            await vendor.acknowledge(vulnerabilityId, bounty, {from: vendorAddress});
        });

        it("Should fully disclose the vulnerability", async function() {

            await authority.publishSecret(vulnerabilityId, secret, {from: vendorAddress});

            const code = 2; // Disclose
            const data = web3.eth.abi.encodeParameters(['bytes32', 'uint', 'string'], [vulnerabilityId, code, vulnerabilityLocation]);
            let tx = await authority.interledgerReceive(nonce, data, {from: interledgerAddress});
            console.log("InterledgerReceive: disclose " + tx.receipt.gasUsed);

            const info = await vendor.getVulnerabilityInfo(vulnerabilityId);

            assert.equal(info[1], STATUS.Disclosed, "The status should be " + STATUS.Disclosed + " (Disclosed)");
            assert.equal(info[6], vulnerabilityLocation, "The vulnerability location should be " + vulnerabilityLocation);

            truffleAssert.eventEmitted(tx, 'LogVulnerabilityDisclose', (ev) => {                
                return (
                        ev.vulnerabilityId == vulnerabilityId,
                        ev.communicator == interledgerAddress,
                        ev.vulnerabilityLocation == vulnerabilityLocation
                        );
            }, 'LogVulnerabilityDisclose event did not fire with correct parameters');

            truffleAssert.eventEmitted(tx, 'InterledgerEventAccepted', (ev) => {                
                return (
                        ev.nonce == nonce
                        );
            }, 'InterledgerEventAccepted event did not fire with correct parameters');
        });
        
        it("Should NOT fully disclose the vulnerability: invalid sender", async function() {
            
            await authority.publishSecret(vulnerabilityId, secret, {from: vendorAddress});

            const code = 2; // Disclose
            const data = web3.eth.abi.encodeParameters(['bytes32', 'uint', 'string'], [vulnerabilityId, code, vulnerabilityLocation]);

            await truffleAssert.fails(
                authority.interledgerReceive(nonce, data, {from: expertAddress}),
                truffleAssert.ErrorType.REVERT,
                "Not the interledger component" // String of the revert
            );
        });

        it("Should NOT fully disclose the vulnerability: invalid state", async function() {

            const code = 2; // Disclose
            const data = web3.eth.abi.encodeParameters(['bytes32', 'uint', 'string'], [vulnerabilityId, code, vulnerabilityLocation]);

            await truffleAssert.fails(
                authority.interledgerReceive(nonce, data, {from: interledgerAddress}),
                truffleAssert.ErrorType.REVERT,
                "The state should be Disclosable" // String of the revert
            );
        });
    });    


    describe("cancelBounty()", function() {

        let factory;
        let authority;
        let vendor;
        let productId;
        
        beforeEach(async function() {
            factory = await Factory.new({from: authorityAddress});
            authority = await Authority.new(interledgerAddress, factory.address, {from: authorityAddress});
            await factory.transferOwnership(authority.address, {from: authorityAddress});
            let tx = await authority.registerVendor(vendorAddress, {from: authorityAddress});
            vendor = await Vendor.at(tx["logs"][2].args.vendorContract); // vendorRegistered is the 3rd event in registerVendor()
            tx = await vendor.registerProduct(productName, {from: vendorAddress});
            productId = tx["logs"][0].args.productId;
            tx = await authority.registerVulnerability(vendorAddress, hashlock, productId, vulnerabilityHash, {from: expertAddress});
            const code = 1; // Approve
            const data = web3.eth.abi.encodeParameters(['bytes32', 'uint', 'string'], [vulnerabilityId, code, "null"]);
            await authority.interledgerReceive(vulnerabilityId, data, {from: interledgerAddress});
            await web3.eth.sendTransaction({
                from: vendorAddress,
                to: vendor.address,
                value: funds
            });
        });

        it("Should cancel the bounty", async function() {

            const motivation = "The expert disclosed the vulnerability in www.site.com";
            await vendor.acknowledge(vulnerabilityId, bounty, {from: vendorAddress});

            await authority.cancelBounty(vulnerabilityId, motivation, {from: authorityAddress});

            const reward = await vendor.getVulnerabilityReward(vulnerabilityId);

            assert.equal(reward[0], REWARDSTATE.CANCELED, "The reward state should be " + REWARDSTATE.CANCELED + " (CANCELED)");
            assert.equal(reward[1], 0, "The reward amount should be 0");
        });
    });    


    // describe("method name", function() {

    //     beforeEach(async function() {

    //         // Execute before each it() statement, common initialization
    //     });

    //     it("Should repsect this condition ....", async function() {

    //         // Write code to end up in a known ok state (tested before)
            
    //         // Write command to test

    //         // Assert the state of the contract and check it is the expected one
    //     });

    //     it("Should NOT respect this condition ....", async function() {

    //         // Write code to end up in a known ok state (tested before)
            
    //         // Write command to test

    //         // Assert the state of the contract and check it is the expected one
    //     });
    // });         

});