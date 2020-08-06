const truffleAssert = require('truffle-assertions');
const Authority = artifacts.require("AuthorityContract");
const Vendor = artifacts.require("VendorContractTest");
const Factory = artifacts.require("VendorFactoryTest");

contract("VendorFactory", function(accounts) {

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

    const secret = 123;
    const hashlock = web3.utils.soliditySha3({type: 'uint', value: secret});
    const metadata = web3.utils.fromAscii(new String(13245678910)); // Random metadata in bytes32
    const bounty = web3.utils.toWei('1', 'ether');
    const vendorName = web3.utils.fromAscii("Test vendor");
    const productName = web3.utils.fromAscii("Test product");
    const productVersion = web3.utils.fromAscii("Test version");
    const vulnerabilityData = "Vulnerability detailed description in text format";
    const vulnerabilityHash = web3.utils.soliditySha3({type: 'string', value: vulnerabilityData});
    const vulnerabilityLocation = "https://organization.org/report_1_test";

    describe("Constructor()", function() {

        it("Should execute the constructor with the correct params", async function() {

            // console.log(await Factory.new.estimateGas(accounts[8]));
            let factory = await Factory.new({from: authorityAddress});

            const owner = await factory.owner();
            const working = await factory.working();

            assert.equal(owner, authorityAddress, "The address of the owner should be " + authorityAddress);
            assert.equal(working, false, "The factory should not work after construction");
        });
    });


    describe("transferOwnership()", function() {

        let factory;

        beforeEach(async function() {

            factory = await Factory.new({from: authorityAddress});
        });

        it("Should tranfer the ownership, and set the factory to working mode on", async function() {

            await factory.transferOwnership(accounts[8], {from: authorityAddress});

            const owner = await factory.owner();
            const working = await factory.working();

            assert.equal(owner, accounts[8], "The address of the  new owner should be " + accounts[8]);
            assert.equal(working, true, "The factory should work");
        });

        it("Should NOT tranfer the ownership if not called by the owner", async function() {

            await truffleAssert.fails(
                factory.transferOwnership(accounts[8], {from: accounts[8]}),
                truffleAssert.ErrorType.REVERT,
                "Ownable: caller is not the owner" // String of the revert
            );

            const working = await factory.working();

            assert.equal(working, false, "The factory should not work after failed owner transfer");
        });

    });


    describe("createVendorContract()", function() {

        let factory;

        beforeEach(async function() {

            factory = await Factory.new({from: authorityAddress});
        });

        it("Should create a smart contract if the ownership has been transfered", async function() {

            // Accounts[8] simulates the address of the authority smart contract
            await factory.transferOwnership(accounts[8], {from: authorityAddress});
            const tx = await factory.createVendorContract(vendorAddress, {from: accounts[8]});

            const evnt = tx["logs"][tx["logs"].length-1]; // Our event is the last one
            const success = await factory.contracts(evnt.args.c);

            assert.equal(success, true, "The factory stored the correct contract");
        });

        it("Should NOT tranfer the ownership if not called by the owner", async function() {

            await truffleAssert.fails(
                factory.createVendorContract(accounts[8], {from: authorityAddress}),
                truffleAssert.ErrorType.REVERT,
                "Factory is not working" // String of the revert
            );
        });

    });    
});