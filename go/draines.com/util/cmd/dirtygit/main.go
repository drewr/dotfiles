package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"path"
	"syscall"
)

func main() {
	for _, arg := range os.Args[1:] {
		if pathIsARepo(arg) {

			switch gitDiffIndex(arg) {
			case 128:
				fmt.Println("nohead:", arg)
			case 1:
				fmt.Println("dirty:", arg)
			case 0:
				fmt.Println("clean:", arg)
			}
		}
	}
}

func pathIsARepo(possiblePath string) bool {
	if _, err := os.Stat(path.Join(possiblePath, ".git")); os.IsNotExist(err) {
		return false
	}
	return true
}

func gitDiffIndex(dir string) int {
	git := exec.Command("git", "diff-index", "--quiet", "HEAD")
	git.Dir = dir
	if err := git.Run(); err != nil {
		if exiterr, ok := err.(*exec.ExitError); ok {
			if status, ok := exiterr.Sys().(syscall.WaitStatus); ok {
				return status.ExitStatus()
			}
		} else {
			log.Fatalf("cmd.Wait: %v", err)
		}
	}
	return 0
}
