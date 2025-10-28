package main

import (
	"fmt"

	"golang.org/x/crypto/ssh"
)

func example() {
	fmt.Println("Example insecure Go app using old x/crypto package")

	// This code doesn't actually exploit anything — just imports a package
	// with known security vulnerabilities in this specific version.
	_ = ssh.CryptoPublicKey(nil)
}
