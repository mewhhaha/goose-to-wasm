static int64_t kernel_g(int64_t n_g) {
    if ((uint8_t)((int64_t)((int64_t)(n_g)) < (int64_t)(2))) {
        int64_t t0;
        t0 = n_g;
        return t0;
    }
    int64_t t1;
    int64_t t2 = kernel_g(gs_sub_i64((int64_t)(n_g), 1, gs_file0, 7));
    int64_t t3 = t2;
    int64_t t4 = kernel_g(gs_sub_i64((int64_t)(n_g), 2, gs_file0, 7));
    t1 = gs_add_i64(t3, t4, gs_file0, 7);
    return t1;
    GS_UNREACHABLE(gs_file0, 5);
    int64_t t5 = {0};
    return t5;
}
