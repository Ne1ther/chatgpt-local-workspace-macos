// Start a private POSIX session so Stop never touches unrelated processes.
#include <unistd.h>
#include <stdio.h>
int main(int argc, char **argv) {
    if (argc < 2) return 64;
    // Foundation Process may already make this child a private group leader.
    if (setsid() == -1 && getpgrp() != getpid()) { perror("setsid"); return 71; }
    execvp(argv[1], argv + 1);
    perror("execvp");
    return 127;
}
