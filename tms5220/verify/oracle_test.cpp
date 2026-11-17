#include "oracle5220.cpp"
int main() { tms5220_oracle o; printf("status %02X irq %d\n", o.status(), o.irq()); for (int i = 0; i < 3; i++) printf("%d ", o.sample()); printf("\n"); }
