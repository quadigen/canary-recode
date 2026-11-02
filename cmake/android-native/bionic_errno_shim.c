int *__errno_location(void) {
    extern int *__errno(void);
    return __errno();
}