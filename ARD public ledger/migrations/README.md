# Migration folder

This folder contains the Truffle migration files. The file `2_interledger_setup.js` is a script to deploy the smart contracts and set them up in a condition that is possible to test Interledger. **NOTE: the script does not invoke Interledger, but sets up the contract prior calling Intelredger.**. Namely, the script creates the required Authority and Vendor contracts, creates a product, and a vulnerability report.

There are two scenarios involving Interledger:
- (1) Interledger is triggered to approve a vulnerability reported by an expert. The communication comes from the private ledger, so this step calls the *interledgerReceive* function in the Authority smart contract;
- (2) Interledger is triggered to disclose an acknowledged vulnerability. The communcation is two sided: it begins with the caller invoking the *publishSecret* function on the Authority smart contract, and later Interledger invokes the *interledgerReceive* function on the same contract. In this scenario there are two conditions to disclose a vulnerability: (2.1)with a patch, (2.2) or after the expiration of the grance period.

To differentiate testing cases, the configuration file `../truffle-config.js` exposes three aliases of the same network: `to_approve`, `to_patch`, and `to_grace_period`. That means the configuration of ganache is the same, but it helps the `2_interledger_setup.js` script to differentiate between the three cases described above (1, 2.1, 2.2 respectively).

The following guide explains how to work with a local testing network, like ganache-cli.

## Setup
Run [ganache-cli](https://github.com/trufflesuite/ganache-cli) at port 7545. If you encounter an error like *"Error: The network id specified in the truffle config (5777) does not match the one returned by the network (1606900697560)"*, include also the network id 5777.

    ganache-cli -p 7545 -i 5777

## Run script

Running the `2_interledger_setup.js` will print con console all the data, accounts and smart contract addresses.

As said, there are two network aliases to run the script.

### Test case (1): Approve a vulnerability

Run the script with the following Truffle command:

    truffle migrate --network to_approve --reset

(--reset is required to force Truffle to run the script a second time and so on).

The Authority smart contract has a new vulnerability report ready to be approved.

Next step: Interledger should trigger the smart contract with an operation beginning from chaincode. The `vulnerability id` and the `payload` that chaincode should produce to pass to interledger are printed on the console.

### Test case (2.1): Disclose a vulnerability patched by the vendor

Run the script with the following Truffle command:

    truffle migrate --network to_patch --reset

In this case, the timelock to patch a vulnerability is set to 100000 seconds. Therefore the Vendor has the time required to provide a patch, and test the condition that is the Vendor calling the smart contract with the secret, and thus triggering Interledger.

Next step: the *publishSecret* function exposed by the Auhtority smart contract needs to be invoked by the vendor.

### Test case (2.2): Disclose a vulnerability after the expiration of the grace period

Run the script with the following Truffle command:

    truffle migrate --network to_grace_period --reset

In this case, the timelock to patch a vulnerability is set to 10 seconds. So it is possible to test the condition that the Expert, or the Authority, can trigger the disclosure procedure by revealing the secret. NOTE: the Vendor can also trigger the disclosure procedure, but an event will notify that the grace period has expired.

Next step: the *publishSecret* function exposed by the Auhtority smart contract needs to be invoked by anyone.

## Publish the secret

To publish the secret, thus triggering the disclosure procedure, is required to call the `publishSecret` function of the Auhtority smart contract. Depending on the caller and on the condition (to patch, or grace period expired), the function will emit events with different parameters. To call the function is possible to include **one of** the following lines at the bottom of  `2_interledger_setup.js` (so executing the script will trigger Interledger):

```javascript
await authorityC.publishSecret(vulnerabilityId, secret, {from: expert});
// or
await authorityC.publishSecret(vulnerabilityId, secret, {from: vendor});
```

Or via Truffle console (after running the script), but in this case is required to retrieve all the variables (i.e. the contract instances and addresses). For example, with the `to_patch` network:

    # Terminal (bash etc...)
    truffle console --network to_patch 

    # Commands in the truffle console
    console)> const expert = "expert address (printed by script)"
    console)> const secret = 123
    console)> const authorityC = await AuthorityContract.deployed()
    console)> await authorityC.publishSecret(vulnerabilityId, secret, {from: expert})

## Note

The accounts of Expert, Authority, Vendor and Interledger are picked from those generated by ganache-cli. If any of those should have a predefined account or address, remeber to substitute the following fields in the `2_interledger_setup.js` script:

```javascript
let authority = accounts[0];
let expert = accounts[1];
let vendor = accounts[2];
let interledger = accounts[3];
```

Or, alternatively, include in the scripts the code to read them from a configuration file, if any.

## References

These steps follow the Truffle tool. Truffle provides a wrapper library of web3js called **truffle-contract** that simplifies the syntax and allows methods like `.at()` and `.deployed()`.


truffle-contract library [documentation](https://www.npmjs.com/package/@truffle/contract);

truffle migration scripts [documentation](https://www.trufflesuite.com/docs/truffle/getting-started/running-migrations);

truffle console [documentation](https://www.trufflesuite.com/docs/truffle/getting-started/using-truffle-develop-and-the-console);