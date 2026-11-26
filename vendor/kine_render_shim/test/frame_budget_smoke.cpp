#include "../src/kine_frame_budget.h"
#include <cassert>
#include <cstdio>
#include <limits>

int main() {
    KineFrameBudget budget;
    budget.configure(true,0.5f,1.0f);
    for (int i=0;i<120;++i) budget.update(0.014f,0.006f,144);
    assert(budget.scale==0.5f);
    budget.configure(true,0.5f,1.0f);
    assert(budget.scale==0.5f);
    for (int i=0;i<1000;++i) budget.update(0.004f,0.0001f,144);
    assert(budget.scale>0.5f && budget.scale<=1);
    budget.configure(false,0.5f,1.0f);
    for (int i=0;i<100;++i) budget.update(0.02f,0.01f,144);
    assert(budget.scale==1);
    budget.configure(true,0.5f,1.0f);
    for (int i=0;i<200;++i) budget.update(0.015f,0.0001f,144);
    assert(budget.scale==1);
    for (int i=0;i<200;++i) budget.update(0.2f,0.15f,144);
    assert(budget.scale==1);
    budget.configure(true,0.7f,0.7f);
    assert(budget.scale==0.7f);
    for (int i=0;i<200;++i) budget.update(0.02f,0.01f,144);
    assert(budget.scale==0.7f);
    KineFrameBudget tailBudget;
    tailBudget.configure(true,0.5f,1.0f);
    for(int i=0;i<160;++i) tailBudget.update(i%4==0?0.010f:0.004f,0.0015f,144);
    assert(tailBudget.scale<1);
    KineFrameBudget cpuBudget;
    cpuBudget.configure(true,0.5f,1.0f);
    for(int i=0;i<160;++i) cpuBudget.update(i%4==0?0.010f:0.004f,0.0001f,144);
    assert(cpuBudget.scale==1);
    assert(kine_budget_shadow_size(2048,2048,0.70f,true)==1024);
    assert(kine_budget_shadow_size(2048,1024,0.82f,true)==1024);
    assert(kine_budget_shadow_size(2048,1024,0.91f,true)==2048);
    assert(kine_budget_shadow_size(2048,1024,0.35f,true)==512);
    assert(kine_budget_shadow_size(2048,512,0.45f,true)==512);
    assert(kine_budget_shadow_size(2048,512,0.6f,true)==1024);
    assert(kine_budget_shadow_size(2048,512,0.35f,false)==2048);
    assert(kine_budget_shadow_size(256,256,0.35f,true)==256);
    std::puts("FRAME_BUDGET_SMOKE_PASSED");
}
