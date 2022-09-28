{
	"subject": {
		"organization": "Example Enterprises",
		"commonName": "{{ .Subject.CommonName }}"
	},
	"keyUsage": [ "keyEncipherment", "digitalSignature" ],
	"extendedKeyUsage": [ "clientAuth", "serverAuth" ],
	"basicConstraints": {
		"isCA": false
	}
}
