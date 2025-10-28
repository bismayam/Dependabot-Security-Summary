module github.com/bismayam/vuln-example

go 1.23.0

require golang.org/x/crypto v0.35.0 // vulnerable version

require (
	github.com/google/go-github/v57 v57.0.0
	golang.org/x/oauth2 v0.20.0
)

require (
	github.com/google/go-querystring v1.1.0 // indirect
	golang.org/x/sys v0.30.0 // indirect
)
