
package main

import (
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/hyperledger/fabric/core/chaincode/shim"
	pb "github.com/hyperledger/fabric/protos/peer"
)



// Peers in authoritymsp and vendormsp will have this private data in a side database
type vulnerabilityCollection struct {
	  //ObjectType string 'json:"docType"''
	  VendorId string 'json:"vendorId"'
	  VulnerabilityId string 'json: "vulnerabilityId"'
	  VendorName string 'json:"vendorName"'
	  ProductName string 'json:"productName"'
	  VulnerabilityType string 'json:"vulnerabilityType"'
	  VulnerabilitySeverity string 'json:"vulnerabilitySeverity"'
	  PatchState string 'json:"patchState"'
	  PaymentState string 'json:"paymentState"'
	  GracePeriod float64 'json:"gracePeriod"'
	  BountyAmt float64 'json:"bountyAmt"'
	  
}

// Only peers in auth0ritymsp will have this private data in a side database
type vulnerabilityPrivateDetails struct {
	//ObjectType string 'json:"docType"''
	VulnerabilityId string 'json:"vulnerabilityId"'
	VendorName string 'json:"vendorName"'
	ProductName string 'json:"productName"'
	ResearcherContact string 'json:"researcherContact"'
  
}

type VulnerabilityChaincode struct { // defined to implement CC interface
}

func main() {

	err := shim.Start(new(vulnerabilityChaincode))

	if err != nil {
		fmt.Printf("Error starting the Vulnerability Contract: %s", err)
	}

}

// Implement Barebone Init
func (t *vulnerabilityChaincode) Init(stub shim.ChaincodeStubInterface) pb.Response {

	fmt.Println("Successfully init chaincode")

	return shim.Success(nil)

}

// Implement Invoke
func (t *vulnerabilityChaincode) Invoke(stub shim.ChaincodeStubInterface) pb.Response {

	fmt.Println("Start Invoke")
	defer fmt.Println("Stop Invoke")

	// Get function name and args
	function, args := stub.GetFunctionAndParameters()

	switch function {

	case "createVulnerability":
		return t.createVulnerability(stub, args)
	/*case "getVulnerability":
		return t.getVulnerability(stub, args)*/
	case "getVendorHistory":
		return t.getVendorHistory(stub, args)
	case "getResearcherContact":
		return t.getResearcherContact(stub, args)
	/*case "getPaymentDetails":
		return t.getPaymentDetails(stub, args)*/
	
	default:
		return shim.Error("Invalid invoke function name.")
	}

}

func (t *vulnerabilityChaincode) createVulnerability(stub shim.ChaincodeStubInterface, args []string) pb.Response {

	vendorId := args[0]
	vulnerabilityId :=args[1]																							
	vendorName := args[2]
	productName := args[3]
	vulnerabilityType := args[4]
	vulnerabilitySeverity := args[5]
	patchState := args[6]
	paymentState := args[7]
	gracePeriod, err1 := strconv.ParseFloat(args[8], 32)
	bountyAmt, err2 := strconv.ParseFloat(args[9], 32)
	researcherContact := args[10]

	if err1 != nil || err2 != nil {
		return shim.Error("Error parsing the values")
	}

	collectionVulnerability := &collectionVulnerability{vendorId, vulnerabilityId, vendorName, productName, vulnerabilityType, vulnerabilitySeverity, patchState, paymentState, gracePeriod, bountyAmt}
	collectionVulnerabilityBytes, err3 := json.Marshal(collectionVulnerability)

	if err3 != nil {
		return shim.Error(err1.Error())
	}

	collectionVulnerabilityPrivateDetails := &vcollectionVulnerabilityPrivateDetails{vulnerabilityid, vendorId, vendorName, productName, researcherContact}
	collectionVulnerabilityPrivateDetailsBytes, err4 := json.Marshal(collectionVulnerabilityPrivateDetails)

	if err4 != nil {
		return shim.Error(err2.Error())
	}

	err5 := stub.PutPrivateData("collectionVulnerability", vendorId, collectionVulnerabilityBytes)

	if err5 != nil {
		return shim.Error(err5.Error())
	}

	err6 := stub.PutPrivateData("collectionVulnerabilityPrivateDetails", vulnerabilityId, collectionVulnerabilityPrivateDetailsBytes)

	if err6 != nil {
		return shim.Error(err6.Error())
	}

	jsoncollectionVulnerability, err7 := json.Marshal(collectionVulnerability)
	if err7 != nil {
		return shim.Error(err7.Error())
	}

	return shim.Success(jsoncollectionVulnerability)

}

func (t *vulnerabilityChaincode) getVendorHistory(stub shim.ChaincodeStubInterface, args []string) pb.Response {

	vendorId := args[0]
	collectionVulnerability := collectionVulnerability{}

	collectionVulnerabilityBytes, err1 := stub.GetPrivateData("collectionVulnerability", vendorId)
	if err1 != nil {
		return shim.Error(err1.Error())
	}

	err2 := json.Unmarshal(collectionVulnerabilityBytes, &collectionVulnerability)

	if err2 != nil {
		fmt.Println("Error unmarshalling object with id: " + vendorId)
		return shim.Error(err2.Error())
	}

	jsoncollectionVulnerability, err3 := json.Marshal(collectionVulnerability)
	if err3 != nil {
		return shim.Error(err3.Error())
	}

	return shim.Success(jsoncollectionVulnerability)

}

func (t *vulnerabilityChaincode) getResearcherContact(stub shim.ChaincodeStubInterface, args []string) pb.Response {

	vulnerabilityId := args[1]
	collectionVulnerabilityPrivateDetails := collectionVulnerabilityPrivateDetails{}

	collectionVulnerabilityPrivateDetailsBytes, err1 := stub.GetPrivateData("collectionVulnerabilityPrivateDetails", vulnerabilityId)
	if err1 != nil {
		return shim.Error(err1.Error())
	}

	err2 := json.Unmarshal(vcollectionVulnerabilityPrivateDetailsBytes, &collectionVulnerabilityPrivateDetails)

	if err2 != nil {
		fmt.Println("Error unmarshalling object with id: " + vulnerabilityId)
		return shim.Error(err2.Error())
	}

	jsoncollectionVulnerabilityPrivateDetails, err3 := json.Marshal(collectionVulnerabilityPrivateDetails)
	if err3 != nil {
		return shim.Error(err3.Error())
	}

	return shim.Success(collectionVulnerabilityPrivateDetails)

}

/*func(t *vulnerabilityChaincode) getPaymentDetails(stub shim.ChaincodeStubInterface, args []string) pb.Response {

	vendorId :=args[0]
	vulnerabilityCollection := vulnerabilityCollection{}

	vulnerabilityCollectionBytes, err1 := stub.GetPrivateData("vulnerabilityCollection", vendorId)
	if err1 != nil {
		return shim.Error(err1.Error())
	}

	err2 := json.Unmarshal(vulnerabilityCollectionBytes, &vulnerabilityCollection)

	if err2 != nil {
		fmt.Println("Error unmarshalling object with id: " + vendorId)
		return shim.Error(err2.Error())
	}

	jsonVulnerabilityCollection, err3 := json.Marshal(vulnerabilityCollection)
	if err3 != nil {
		return shim.Error(err3.Error())
	}

	return shim.Success(jsonVulnerabilityCollection)


}*/




















