// The PS's GP0 as zm_glass_regs_tb.cpp drives it: an AXI3 master of single
// beats, with AW/W in any order and B/R back-pressured at random. Included
// once, after the CXXRTL model and CHECK.
#pragma once

using Top = cxxrtl_design::p_zm__glass__regs;
static Top top;
static unsigned rng = 12345;
static bool coin() { return ((rng = rng * 1103515245u + 12345u) >> 16) & 1; }

// The extra step settles combinational outputs that read a memory (key_data):
// CXXRTL can leave one a delta behind the registers it was just committed from.
static void tick() {
    top.p_clk.set(false);
    top.step();
    top.p_clk.set(true);
    top.step();
    top.step();
}

static void idle() {
    top.p_s__awvalid.set(false);
    top.p_s__wvalid.set(false);
    top.p_s__arvalid.set(false);
    top.p_key__pop.set(false);
    top.p_cart__state__we.set(false);
    top.p_cart__beat__we.set(false);
}

// AW and W until both are taken; `order` 0 = AW first, 1 = W first, 2 = together.
static bool handshake(unsigned addr, unsigned data, unsigned strb, int order, unsigned id) {
    bool aw = order != 1, w = order != 0, aw_done = false, w_done = false;
    for (int guard = 0; !(aw_done && w_done); guard++) {
        CHECK(guard < 20, "write 0x%x never accepted", addr);
        if (guard >= 20) return false;
        top.p_s__awvalid.set(aw && !aw_done);
        // Address and data are garbage whenever their VALID is low, as AXI allows.
        top.p_s__awaddr.set(aw && !aw_done ? addr : 0x0BEC);
        top.p_s__awid.set(id);
        top.p_s__wvalid.set(w && !w_done);
        top.p_s__wdata.set(w && !w_done ? data : 0xDEADBEEF);
        top.p_s__wstrb.set(strb);
        top.step();
        bool aw_hs = aw && !aw_done && top.p_s__awready.get<bool>();
        bool w_hs = w && !w_done && top.p_s__wready.get<bool>();
        tick();
        aw_done |= aw_hs;
        w_done |= w_hs;
        aw = w = true;
    }
    return true;
}

// One write, its B accepted after a random wait. Returns the BID.
static unsigned axi_write(unsigned addr, unsigned data, unsigned strb = 0xF, int order = 2, unsigned id = 7) {
    if (!handshake(addr, data, strb, order, id)) return 0;
    idle();
    top.p_s__bready.set(false);
    for (int i = 0; i < 3 && coin(); i++) tick();
    top.p_s__bready.set(true);
    for (int guard = 0; !top.p_s__bvalid.get<bool>(); guard++) {
        CHECK(guard < 5, "no B for 0x%x", addr);
        if (guard >= 5) return 0;
        tick();
    }
    CHECK(top.p_s__bresp.get<unsigned>() == 0, "BRESP %u", top.p_s__bresp.get<unsigned>());
    unsigned bid = top.p_s__bid.get<unsigned>();
    tick();
    CHECK(!top.p_s__bvalid.get<bool>(), "B held after it was taken");
    return bid;
}

static unsigned axi_read(unsigned addr, unsigned id = 3) {
    top.p_s__arvalid.set(true);
    top.p_s__araddr.set(addr);
    top.p_s__arid.set(id);
    top.p_s__rready.set(false);
    top.step();
    CHECK(top.p_s__arready.get<bool>(), "AR not ready for 0x%x", addr);
    tick();
    idle();
    for (int i = 0; i < 2 && coin(); i++) tick();
    CHECK(top.p_s__rvalid.get<bool>(), "no R for 0x%x", addr);
    CHECK(top.p_s__rid.get<unsigned>() == id && top.p_s__rlast.get<bool>(), "RID/RLAST wrong");
    unsigned v = top.p_s__rdata.get<unsigned>();
    top.p_s__rready.set(true);
    tick();
    CHECK(!top.p_s__rvalid.get<bool>(), "R held after it was taken");
    return v;
}

