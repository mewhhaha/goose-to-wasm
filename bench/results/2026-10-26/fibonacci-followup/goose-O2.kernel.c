static int64_t kernel_g(int64_t n_g) {
    if ((uint8_t)((int64_t)((int64_t)(n_g)) < (int64_t)(2))) {
        int64_t t0;
        t0 = n_g;
        return t0;
    }
    int64_t t1;
    int64_t t2;
    int64_t n_g_2 = gs_sub_i64((int64_t)(n_g), 1, gs_file0, 7);
    {
        if ((uint8_t)((int64_t)((int64_t)(n_g_2)) < (int64_t)(2))) {
            t2 = n_g_2;
        } else {
            int64_t t3 = kernel_g(n_g_2);
            t2 = t3;
        }
    }
    int64_t t4 = t2;
    int64_t t5;
    int64_t n_g_3 = gs_sub_i64((int64_t)(n_g), 2, gs_file0, 7);
    {
        if ((uint8_t)((int64_t)((int64_t)(n_g_3)) < (int64_t)(2))) {
            t5 = n_g_3;
        } else {
            int64_t t6 = kernel_g(n_g_3);
            t5 = t6;
        }
    }
    t1 = gs_add_i64(t4, t5, gs_file0, 7);
    return t1;
    GS_UNREACHABLE(gs_file0, 5);
    int64_t t7 = {0};
    return t7;
}
