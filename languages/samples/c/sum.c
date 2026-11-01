// test: 2 3 => 5
#include <stdio.h>
#include <stdlib.h>

int add(int a, int b) {
    return a + b; // the sum
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: sum a b\n");
        return 1;
    }
    char c = 'x';
    printf("%d\n", add(atoi(argv[1]), atoi(argv[2])));
    return 0;
}
