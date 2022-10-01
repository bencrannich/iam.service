{
	"subject": {
		"organization": "Example Enterprises",
		"commonName": "Device Provisioning Certificate"
	},
	"sans": {{ toJson .SANs }},
	"keyUsage": [ "keyEncipherment", "digitalSignature" ],
	"extendedKeyUsage": [ "clientAuth" ],
	"basicConstraints": {
		"isCA": false
	},
	"extensions": [
		{ "id": "1.3.6.1.4.1.58118.104.1", "critical": false, "value": "DB9EZXZpY2UgUHJvdmlzaW9uaW5nIENlcnRpZmljYXRl" }
	],
	"policyIdentififers": [
		"1.3.6.1.4.1.58118.113.1.1"
	]
}
