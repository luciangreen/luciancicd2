#include <stdio.h>

struct node { int value; struct node *next; };

/* Sums a linked list. */
int sum(struct node *n) {
    int s = 0;
    while (n != NULL) { s += n->value; n = n->next; }
    return s;
}

int main(void) {
    struct node c = {3, NULL}, b = {2, &c}, a = {1, &b};
    int xs[3] = {1, 2, 3};
    printf("%d %d\n", sum(&a), xs[0]);
    return 0;
}
