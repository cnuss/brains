package main

import (
	"fmt"

	"rsc.io/quote"
)

// main prints a friendly greeting using the quote package.
func main() {
	fmt.Println(Hello())
}

func Hello() string {
	return quote.Hello()
}
