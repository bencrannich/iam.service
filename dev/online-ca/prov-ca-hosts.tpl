{
	"subject": {
		"organization": "Example Enterprises",
		"commonName": "Provisioning Certificate"
	},
	"sans": {{ toJson .SANs }},
	"keyUsage": [ "keyEncipherment", "digitalSignature" ],
	"extendedKeyUsage": [ "clientAuth" ],
	"basicConstraints": {
		"isCA": false
	},
	"extensions": [
		{ "id": "1.3.6.1.4.1.58118.113.1", "critical": false, "value": "NTA=" }
	]
}
