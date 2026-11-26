#include <stdint.h>
uint32_t Kinemium_GetABIVersion(void) { return 999; }
void *Kinemium_Create(void) { return (void *)1; }
void Kinemium_Destroy(void *context) { (void)context; }
