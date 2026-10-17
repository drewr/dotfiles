// Spike 1 helper: a tiny binary that proves execve works when the target exists in the image.
#include <stdio.h>
#include <unistd.h>
int main(int argc, char **argv) {
    printf("[spikeecho] ran as pid=%d argc=%d arg0=%s arg1=%s\n",
           (int)getpid(), argc, argc > 0 ? argv[0] : "-", argc > 1 ? argv[1] : "-");
    fflush(stdout);
    return 7; // distinctive exit code the parent can assert on
}
