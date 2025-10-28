module github.com/bismayam/vuln-example

go 1.20

require golang.org/x/crypto v0.0.0-20200622213623-75b288015ac9 // vulnerable version

require (
	github.com/google/go-github/v57 v57.0.0 // indirect
	github.com/google/go-querystring v1.1.0 // indirect
	golang.org/x/oauth2 v0.20.0 // indirect
)
